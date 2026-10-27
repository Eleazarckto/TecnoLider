<?php
// ════════════════════════════════════════════════════════════════════
//  crud.php — Helpers genéricos para CRUD (sin field_mapper)
// ════════════════════════════════════════════════════════════════════
//  Versión limpia: la app y la BD usan los MISMOS nombres de columna.
//  No hay traducción intermedia. Si la app envía 'cliente', la BD
//  recibe 'cliente'. Esto evita los bugs de columnas mal mapeadas.
// ════════════════════════════════════════════════════════════════════

declare(strict_types=1);

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/response.php';

/**
 * Lista registros de una tabla con soft-delete y filtros básicos.
 *
 * @param string $tabla   Nombre de tabla
 * @param array  $filtros Filtros opcionales (column => valor)
 * @param string $orderBy Columna por la que ordenar (con DESC opcional)
 * @param int    $limit   Límite máximo de filas (0 = sin límite)
 */
function listar(string $tabla, array $filtros = [],
                string $orderBy = 'id DESC', int $limit = 0): array {
    $sql = "SELECT * FROM `$tabla` WHERE eliminado_en IS NULL";
    $params = [];
    foreach ($filtros as $col => $val) {
        if ($val === null || $val === '') continue;
        $sql .= " AND `$col` = ?";
        $params[] = $val;
    }
    $sql .= " ORDER BY $orderBy";
    if ($limit > 0) $sql .= " LIMIT $limit";
    $stmt = db()->prepare($sql);
    $stmt->execute($params);
    return $stmt->fetchAll();
}

/**
 * Obtiene un registro por id (NULL si no existe o está soft-deleted).
 */
function obtener(string $tabla, $id) {
    $stmt = db()->prepare("SELECT * FROM `$tabla` WHERE id = ? AND eliminado_en IS NULL");
    $stmt->execute([$id]);
    $row = $stmt->fetch();
    return $row ?: null;
}

/**
 * Inserta un registro y devuelve su id.
 *
 * @param string $tabla
 * @param array  $datos        column => valor
 * @param array  $columnasPermitidas Lista blanca de columnas (anti SQL injection)
 */
function insertar(string $tabla, array $datos, array $columnasPermitidas): int {
    // Filtrar contra la lista blanca de columnas. El array_intersect_key
    // descarta cualquier clave que no esté en $columnasPermitidas.
    $datos = filtrar_columnas($datos, $columnasPermitidas);
    if (empty($datos)) json_error('No hay datos para insertar', 400);

    $cols = array_keys($datos);
    $placeholders = implode(', ', array_fill(0, count($cols), '?'));
    $colsSql = '`' . implode('`, `', $cols) . '`';

    $sql = "INSERT INTO `$tabla` ($colsSql) VALUES ($placeholders)";
    $stmt = db()->prepare($sql);
    $stmt->execute(array_values($datos));
    return (int) db()->lastInsertId();
}

/**
 * Actualiza un registro por id.
 */
function actualizar(string $tabla, $id, array $datos, array $columnasPermitidas): int {
    $datos = filtrar_columnas($datos, $columnasPermitidas);
    if (empty($datos)) json_error('No hay datos para actualizar', 400);

    $set = [];
    $params = [];
    foreach ($datos as $col => $val) {
        $set[] = "`$col` = ?";
        $params[] = $val;
    }
    $params[] = $id;

    $sql = "UPDATE `$tabla` SET " . implode(', ', $set) .
           " WHERE id = ? AND eliminado_en IS NULL";
    $stmt = db()->prepare($sql);
    $stmt->execute($params);
    return $stmt->rowCount();
}

/**
 * Soft-delete: marca eliminado_en = NOW().
 */
function eliminar_logico(string $tabla, $id): int {
    $stmt = db()->prepare(
        "UPDATE `$tabla` SET eliminado_en = NOW()
         WHERE id = ? AND eliminado_en IS NULL"
    );
    $stmt->execute([$id]);
    return $stmt->rowCount();
}

/**
 * Restaura un registro soft-deleted.
 */
function restaurar(string $tabla, $id): int {
    $stmt = db()->prepare(
        "UPDATE `$tabla` SET eliminado_en = NULL WHERE id = ?"
    );
    $stmt->execute([$id]);
    return $stmt->rowCount();
}

/**
 * Filtra un array de datos dejando solo las columnas permitidas.
 * Esto evita inyección SQL cuando construimos queries dinámicas.
 */
function filtrar_columnas(array $datos, array $permitidas): array {
    return array_intersect_key($datos, array_flip($permitidas));
}

/**
 * Despachador estándar de método HTTP a operación CRUD.
 *
 * Patrón:
 *   GET     /?resource=X         -> listar todos
 *   GET     /?resource=X&id=N    -> obtener uno
 *   POST    /?resource=X         -> crear (body JSON)
 *   PUT     /?resource=X&id=N    -> actualizar (body JSON)
 *   DELETE  /?resource=X&id=N    -> soft-delete
 */
function despachar_crud(string $tabla, array $columnasPermitidas,
                        string $orderBy = 'id DESC',
                        ?callable $onCreate = null,
                        ?callable $onUpdate = null,
                        ?callable $onDelete = null): void {
    $metodo = $_SERVER['REQUEST_METHOD'];
    $id = get_param('id');

    switch ($metodo) {
        case 'GET':
            if ($id !== null) {
                $row = obtener($tabla, $id);
                if (!$row) json_error('No encontrado', 404);
                json_response($row);
            } else {
                $filtros = [];
                foreach ($_GET as $k => $v) {
                    if (in_array($k, ['resource', 'id', 'limit', 'order'])) continue;
                    if (in_array($k, $columnasPermitidas)) $filtros[$k] = $v;
                }
                $limit = (int) (get_param('limit', 0));
                $orden = get_param('order', $orderBy);
                json_response(listar($tabla, $filtros, $orden, $limit));
            }
            break;

        case 'POST': {
            $body = json_body();
            if ($onCreate) {
                $id = $onCreate($body);
            } else {
                $id = insertar($tabla, $body, $columnasPermitidas);
            }
            audit($tabla, $id, 'INSERT', $body['_usuario'] ?? null, null, $body);
            json_response(['ok' => true, 'id' => $id], 201);
            break;
        }

        case 'PUT': {
            if ($id === null) json_error('Falta id', 400);
            $body = json_body();
            $antes = obtener($tabla, $id);
            if (!$antes) json_error('No encontrado', 404);

            if ($onUpdate) {
                $rows = $onUpdate($id, $body);
            } else {
                $rows = actualizar($tabla, $id, $body, $columnasPermitidas);
            }
            $despues = obtener($tabla, $id);
            audit($tabla, $id, 'UPDATE', $body['_usuario'] ?? null, $antes, $despues);
            json_response(['ok' => true, 'rows' => $rows]);
            break;
        }

        case 'DELETE': {
            if ($id === null) json_error('Falta id', 400);
            $antes = obtener($tabla, $id);
            if (!$antes) json_error('No encontrado', 404);

            if ($onDelete) {
                $rows = $onDelete($id);
            } else {
                $rows = eliminar_logico($tabla, $id);
            }
            audit($tabla, $id, 'DELETE', get_param('usuario'), $antes, null);
            json_response(['ok' => true, 'rows' => $rows]);
            break;
        }

        default:
            json_error('Método no permitido', 405);
    }
}
