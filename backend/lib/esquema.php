<?php
// ════════════════════════════════════════════════════════════════════
//  esquema.php — Introspección de la base de datos
// ════════════════════════════════════════════════════════════════════
//  Los endpoints que escriben en varias tablas a la vez necesitan saber
//  qué columnas existen REALMENTE antes de armar el INSERT. Sin esto,
//  cualquier diferencia entre el esquema de producción y el que asumió
//  el programador termina en un error 500 ("Unknown column 'x'") que el
//  usuario ve como "Error del servidor" sin más pistas.
//
//  Con estos helpers el endpoint arma la consulta con las columnas que
//  la tabla tiene hoy y descarta el resto en silencio: si mañana alguien
//  agrega o quita una columna, el endpoint sigue funcionando.
// ════════════════════════════════════════════════════════════════════

declare(strict_types=1);

require_once __DIR__ . '/db.php';

/**
 * Lista de columnas de una tabla, en el orden en que estan definidas.
 * Devuelve [] si la tabla no existe.
 *
 * El resultado se cachea por request: information_schema es cara y un
 * mismo endpoint puede preguntar por la misma tabla varias veces.
 */
function columnas_de(string $tabla): array {
    $cache =& esquema_cache();
    if (isset($cache[$tabla])) return $cache[$tabla];
    $stmt = db()->prepare(
        "SELECT COLUMN_NAME FROM information_schema.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
         ORDER BY ORDINAL_POSITION"
    );
    $stmt->execute([$tabla]);
    return $cache[$tabla] = $stmt->fetchAll(PDO::FETCH_COLUMN);
}

/**
 * Caché compartida del esquema. Se devuelve por referencia para que
 * `columnas_de()` escriba en ella y `esquema_refrescar()` la vacie.
 */
function &esquema_cache(): array {
    static $cache = [];
    return $cache;
}

/**
 * Olvida el esquema cacheado. Hay que llamarlo justo despues de un
 * CREATE TABLE o un ALTER hecho dentro del mismo request: si no, se
 * sigue viendo la tabla como estaba antes (o como inexistente).
 */
function esquema_refrescar(?string $tabla = null): void {
    $cache =& esquema_cache();
    if ($tabla === null) { $cache = []; return; }
    unset($cache[$tabla]);
}

/** true si la tabla existe en la base actual. */
function tabla_existe(string $tabla): bool {
    $stmt = db()->prepare(
        "SELECT COUNT(*) FROM information_schema.TABLES
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?"
    );
    $stmt->execute([$tabla]);
    return ((int)$stmt->fetchColumn()) > 0;
}

/** true si la tabla tiene esa columna. */
function tabla_tiene(string $tabla, string $columna): bool {
    return in_array($columna, columnas_de($tabla), true);
}

/**
 * Filtra un mapa columna=>valor dejando solo las columnas que la tabla
 * realmente tiene. Es lo que evita el 500 por "Unknown column".
 */
function solo_columnas_reales(string $tabla, array $datos): array {
    $cols = columnas_de($tabla);
    if (!$cols) return [];
    return array_intersect_key($datos, array_flip($cols));
}

/**
 * INSERT armado a partir de un mapa columna=>valor, descartando las
 * columnas que no existen. Devuelve el id insertado.
 */
function insertar_en(string $tabla, array $datos): int {
    $datos = solo_columnas_reales($tabla, $datos);
    if (!$datos) {
        throw new RuntimeException(
            "No hay columnas válidas para insertar en `$tabla`");
    }
    $cols  = array_keys($datos);
    $marks = implode(', ', array_fill(0, count($cols), '?'));
    $sql   = 'INSERT INTO `' . $tabla . '` (`' . implode('`, `', $cols) .
             '`) VALUES (' . $marks . ')';
    db()->prepare($sql)->execute(array_values($datos));
    return (int)db()->lastInsertId();
}

/**
 * Fragmento `AND eliminado_en IS NULL` solo si la tabla tiene esa
 * columna. Varias tablas del sistema (por ejemplo `tasa_bcv`) NO la
 * tienen, y darla por sentada rompe la consulta entera.
 */
function filtro_no_eliminado(string $tabla, string $alias = ''): string {
    if (!tabla_tiene($tabla, 'eliminado_en')) return '';
    $p = $alias === '' ? '' : ($alias . '.');
    return " AND {$p}eliminado_en IS NULL";
}
