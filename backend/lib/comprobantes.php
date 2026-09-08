<?php
// ════════════════════════════════════════════════════════════════════
//  comprobantes.php — Helpers de la tabla `comprobantes`
// ════════════════════════════════════════════════════════════════════
//  Guarda las fotos y PDFs que el usuario adjunta desde la app:
//  la factura original de una cuenta, el recibo de un abono, o el
//  respaldo de un aumento de deuda.
//
//  Los nombres de columna (`imagen_base64`, `imagen_ext`, `created_at`)
//  son los que la app YA lee al listar comprobantes. Si se renombran,
//  la pantalla los muestra vacíos.
// ════════════════════════════════════════════════════════════════════

declare(strict_types=1);

require_once __DIR__ . '/db.php';

/**
 * true si la tabla `comprobantes` ya está creada.
 *
 * @param bool $refrescar Ignora el valor cacheado y vuelve a consultar.
 *        Necesario justo después de crear la tabla, porque el resultado
 *        anterior (false) quedó guardado.
 */
function tabla_comprobantes_existe(bool $refrescar = false): bool {
    static $existe = null;
    if ($existe !== null && !$refrescar) return $existe;
    $stmt = db()->prepare(
        "SELECT COUNT(*) FROM information_schema.TABLES
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'comprobantes'"
    );
    $stmt->execute();
    return $existe = ((int)$stmt->fetchColumn() > 0);
}

/**
 * Crea la tabla `comprobantes` si la instalación todavía no la tiene.
 *
 * En el servidor de producción la tabla YA existía con este mismo
 * esquema, así que este CREATE solo corre en instalaciones nuevas. Las
 * columnas están calcadas de la tabla real — no agregar ni renombrar
 * ninguna sin revisar antes qué lee la app.
 */
function asegurar_tabla_comprobantes(): void {
    if (tabla_comprobantes_existe()) return;
    db()->exec(
        "CREATE TABLE IF NOT EXISTS comprobantes (
            id             INT AUTO_INCREMENT PRIMARY KEY,
            ambito         VARCHAR(40)  NOT NULL DEFAULT 'cuentas_cobrar',
            entidad_tipo   VARCHAR(40)  NOT NULL,
            entidad_id     INT          NOT NULL,
            cuenta_id      INT          NOT NULL,
            imagen_base64  LONGTEXT     NOT NULL,
            imagen_ext     VARCHAR(8)   NOT NULL DEFAULT 'jpg',
            created_at     TIMESTAMP    NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_entidad (entidad_tipo, entidad_id),
            INDEX idx_cuenta (cuenta_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );
    tabla_comprobantes_existe(true); // refrescar la caché
}
