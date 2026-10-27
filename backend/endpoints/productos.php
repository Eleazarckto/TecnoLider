<?php
// Endpoint: /api.php?resource=productos
//
// CRUD estándar de la tabla `productos`. Con soporte para múltiples
// filas del mismo `codigo` en distintas tiendas.
//
// HISTORIAL: originalmente la tabla tenía UNIQUE(codigo) — impedía que
// un mismo producto se pudiera agregar a otra tienda. Se cambió a
// UNIQUE(codigo, tienda) para que el mismo SKU pueda estar en varias
// sedes con su propio stock. Este endpoint verifica y aplica la
// migración de constraint si detecta la vieja.

$pdo = db();
$pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);

// Listas de precios desde el costo (16/10/2026). DORMIDO: los enganches
// salen enseguida si `precios_auto_activo` no vale 1 en configuracion, y aun
// encendidos solo tocan listas con modo_precios = 'costo'. Nunca rompen el
// guardado del producto (atrapan todo y lo dejan en el log).
require_once __DIR__ . '/../lib/precios_listas.php';

// ── Auto-migración de constraint UNIQUE ─────────────────────────
// Si la tabla `productos` tiene UNIQUE solo en `codigo`, la cambiamos
// a UNIQUE compuesto (codigo, tienda) para permitir el mismo producto
// en varias tiendas.
try {
    $indices = $pdo->query(
        "SELECT INDEX_NAME,
                GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS cols
         FROM INFORMATION_SCHEMA.STATISTICS
         WHERE TABLE_SCHEMA = DATABASE()
           AND TABLE_NAME = 'productos'
           AND NON_UNIQUE = 0
         GROUP BY INDEX_NAME"
    )->fetchAll();
    $hayUniqueSoloCodigo = false;
    $hayUniqueComposite  = false;
    $nombreIndiceCodigo  = null;
    foreach ($indices as $idx) {
        if ($idx['cols'] === 'codigo') {
            $hayUniqueSoloCodigo = true;
            $nombreIndiceCodigo  = $idx['INDEX_NAME'];
        }
        if ($idx['cols'] === 'codigo,tienda' || $idx['cols'] === 'tienda,codigo') {
            $hayUniqueComposite = true;
        }
    }
    if ($hayUniqueSoloCodigo && !$hayUniqueComposite && $nombreIndiceCodigo !== null) {
        // Migrar: quitar UNIQUE simple y crear compuesto
        $pdo->exec("ALTER TABLE productos DROP INDEX `$nombreIndiceCodigo`");
        $pdo->exec("ALTER TABLE productos ADD UNIQUE KEY codigo_tienda (codigo, tienda)");
        error_log('[productos.php] Migrado UNIQUE(codigo) → UNIQUE(codigo, tienda)');
    }
} catch (Throwable $e) {
    // No abortar por esto — el endpoint sigue funcionando.
    error_log('[productos.php] Aviso migración constraint: ' . $e->getMessage());
}

$tabla = 'productos';
$columnas = [
    'codigo', 'nombre', 'categoria', 'marca', 'modelo', 'tipo',
    'precio_costo', 'precio_venta', 'stock_manual', 'porcentaje_bateria',
    'producto_padre_codigo', 'variante', 'tienda',
];

$metodo = $_SERVER['REQUEST_METHOD'];

// GET → si se pide con ?id=X trae uno, sino trae todos (incluye
// múltiples filas del mismo codigo en distintas tiendas)
if ($metodo === 'GET') {
    $id = get_param('id');
    if ($id !== null) {
        $stmt = $pdo->prepare("SELECT * FROM productos WHERE id = ? AND eliminado_en IS NULL");
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        if (!$row) json_error('No encontrado', 404);
        json_response($row);
    }
    $rows = $pdo->query(
        "SELECT * FROM productos WHERE eliminado_en IS NULL ORDER BY codigo, tienda"
    )->fetchAll();
    json_response($rows);
}

// POST → crear producto. Si YA existe con el mismo codigo Y misma
// tienda, actualiza en vez de duplicar. Si existe con el mismo codigo
// pero DISTINTA tienda, crea una fila nueva (permitido).
if ($metodo === 'POST') {
    $body = json_decode(file_get_contents('php://input'), true);
    if (!is_array($body)) json_error('JSON inválido', 400);

    $codigo = trim((string) ($body['codigo'] ?? ''));
    $tienda = trim((string) ($body['tienda'] ?? ''));
    if ($codigo === '') json_error('Falta el código del producto', 400);
    // Precio de venta desde su lista (solo con precio_venta_desde_lista = 1).
    $body = plEnganchePrepararProducto($pdo, $body, $codigo);

    try {
        // Buscar si ya existe con misma clave (codigo + tienda)
        $stmt = $pdo->prepare(
            "SELECT id FROM productos WHERE codigo = ? AND tienda = ? LIMIT 1"
        );
        $stmt->execute([$codigo, $tienda]);
        $existe = $stmt->fetch();

        if ($existe) {
            // Actualizar la fila existente
            $sets   = [];
            $values = [];
            foreach ($columnas as $c) {
                if (array_key_exists($c, $body)) {
                    $sets[]   = "`$c` = ?";
                    $values[] = $body[$c];
                }
            }
            $values[] = (int) $existe['id'];
            $sql = "UPDATE productos SET " . implode(',', $sets)
                 . ", eliminado_en = NULL WHERE id = ?";
            $pdo->prepare($sql)->execute($values);
            plEngancheProducto($pdo, $codigo);
            $stmt = $pdo->prepare("SELECT * FROM productos WHERE id = ?");
            $stmt->execute([(int)$existe['id']]);
            json_response($stmt->fetch(), 200);
        }

        // Insertar como fila nueva (permite mismo codigo en otra tienda)
        $cols   = [];
        $values = [];
        foreach ($columnas as $c) {
            if (array_key_exists($c, $body)) {
                $cols[]   = $c;
                $values[] = $body[$c];
            }
        }
        if (empty($cols)) json_error('Body sin columnas válidas', 400);
        $placeholders = implode(',', array_fill(0, count($cols), '?'));
        $sqlCols      = implode(',', array_map(fn($c) => "`$c`", $cols));
        $pdo->prepare(
            "INSERT INTO productos ($sqlCols) VALUES ($placeholders)"
        )->execute($values);
        $id = (int) $pdo->lastInsertId();
        plEngancheProducto($pdo, $codigo);
        $stmt = $pdo->prepare("SELECT * FROM productos WHERE id = ?");
        $stmt->execute([$id]);
        json_response($stmt->fetch(), 201);
    } catch (Throwable $e) {
        json_error('Error creando producto: ' . $e->getMessage(), 500);
    }
}

// PUT → actualizar producto por id
if ($metodo === 'PUT') {
    $id = get_param('id');
    if ($id === null) json_error('Falta id', 400);
    $body = json_decode(file_get_contents('php://input'), true);
    if (!is_array($body)) json_error('JSON inválido', 400);

    // Código de la fila (para el enganche de listas; dormido por defecto).
    $codigoPut = '';
    try {
        $st = $pdo->prepare("SELECT codigo FROM productos WHERE id = ?");
        $st->execute([$id]);
        $codigoPut = (string) ($st->fetchColumn() ?: '');
    } catch (Throwable $e) { /* sin código: el enganche no hace nada */ }
    $body = plEnganchePrepararProducto($pdo, $body, $codigoPut);

    $sets   = [];
    $values = [];
    foreach ($columnas as $c) {
        if (array_key_exists($c, $body)) {
            $sets[]   = "`$c` = ?";
            $values[] = $body[$c];
        }
    }
    if (empty($sets)) json_error('Sin columnas para actualizar', 400);
    $values[] = $id;
    try {
        $pdo->prepare("UPDATE productos SET " . implode(',', $sets)
                    . " WHERE id = ?")->execute($values);
        plEngancheProducto($pdo, trim((string) ($body['codigo'] ?? $codigoPut)));
        $stmt = $pdo->prepare("SELECT * FROM productos WHERE id = ?");
        $stmt->execute([$id]);
        json_response($stmt->fetch());
    } catch (Throwable $e) {
        json_error('Error actualizando: ' . $e->getMessage(), 500);
    }
}

// DELETE → soft-delete
if ($metodo === 'DELETE') {
    $id = get_param('id');
    if ($id === null) json_error('Falta id', 400);
    $pdo->prepare(
        "UPDATE productos SET eliminado_en = NOW() WHERE id = ?"
    )->execute([$id]);
    json_response(['ok' => true, 'id' => (int)$id]);
}

json_error('Método no permitido', 405);
