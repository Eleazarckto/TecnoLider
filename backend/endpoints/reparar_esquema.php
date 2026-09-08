<?php
// ════════════════════════════════════════════════════════════════════
//  Endpoint: /api.php?resource=reparar_esquema   (GET o POST)
// ════════════════════════════════════════════════════════════════════
//  Chequeo de salud + reparación del esquema, para abrir desde el
//  navegador y ver de una si el backend está sano:
//
//    https://sistemasceccato.com/tecnolider/api.php?resource=reparar_esquema
//
//  Hace dos cosas:
//
//  1. REPARA lo que falta en la base. Todas las operaciones son
//     idempotentes y NO destructivas: solo CREATE TABLE / CREATE VIEW /
//     ADD COLUMN. Nunca borra, nunca modifica datos existentes.
//     Correrlo dos veces no cambia nada la segunda vez.
//
//  2. INFORMA qué recursos del router están rotos: cuáles apuntan a un
//     archivo PHP que no está subido. Es el chequeo que hubiera evitado
//     el "Recurso no encontrado [POST traslado_aplicar]": el mapa de
//     `api.php` puede nombrar un handler que nadie subió, y eso recién
//     se descubre cuando un usuario usa la función.
//
//  Es de solo lectura para los datos del negocio, así que se puede
//  llamar cuantas veces se quiera.
// ════════════════════════════════════════════════════════════════════

require_once __DIR__ . '/../lib/esquema.php';

$aplicado = [];   // cambios hechos ahora
$ya_estaba = [];  // cosas que ya estaban bien
$errores  = [];   // reparaciones que no se pudieron hacer

/** Corre una reparación y anota el resultado sin cortar las demás. */
$reparar = static function (string $titulo, callable $yaEsta, callable $accion)
        use (&$aplicado, &$ya_estaba, &$errores): void {
    try {
        if ($yaEsta()) { $ya_estaba[] = $titulo; return; }
        $accion();
        $aplicado[] = $titulo;
    } catch (Throwable $e) {
        $errores[] = $titulo . ': ' . $e->getMessage();
    }
};

// ── 1. `tasa_bcv` sin la columna del borrado lógico ────────────────
//  El CRUD genérico agrega `WHERE eliminado_en IS NULL` a toda consulta.
//  La tabla `tasa_bcv` se creó sin esa columna, así que el endpoint
//  entero responde 500 con "Unknown column 'eliminado_en'".
$reparar(
    "tasa_bcv.eliminado_en",
    static fn(): bool => !tabla_existe('tasa_bcv')
                         || tabla_tiene('tasa_bcv', 'eliminado_en'),
    static function (): void {
        db()->exec('ALTER TABLE tasa_bcv ADD COLUMN eliminado_en DATETIME NULL');
        esquema_refrescar('tasa_bcv');
    }
);

// ── 2. Tablas de cotizaciones ──────────────────────────────────────
$reparar(
    "tabla cotizaciones",
    static fn(): bool => tabla_existe('cotizaciones'),
    static function (): void {
        db()->exec(
            "CREATE TABLE IF NOT EXISTS cotizaciones (
                id             INT AUTO_INCREMENT PRIMARY KEY,
                cliente_nombre VARCHAR(160)  NOT NULL DEFAULT '',
                cliente_cedula VARCHAR(40)   NOT NULL DEFAULT '',
                cliente_tel    VARCHAR(40)   NOT NULL DEFAULT '',
                cliente_correo VARCHAR(160)  NOT NULL DEFAULT '',
                moneda         VARCHAR(8)    NOT NULL DEFAULT 'USD',
                incluye_iva    TINYINT(1)    NOT NULL DEFAULT 0,
                tasa           DECIMAL(18,4) NOT NULL DEFAULT 0,
                subtotal       DECIMAL(14,2) NOT NULL DEFAULT 0,
                monto_iva      DECIMAL(14,2) NOT NULL DEFAULT 0,
                total          DECIMAL(14,2) NOT NULL DEFAULT 0,
                fecha_creacion DATE          NULL,
                fecha_vence    DATE          NULL,
                estado         VARCHAR(20)   NOT NULL DEFAULT 'pendiente',
                nro_factura    VARCHAR(80)   NOT NULL DEFAULT '',
                fecha_cobro    DATETIME      NULL,
                usuario        VARCHAR(160)  NOT NULL DEFAULT '',
                creado_en      TIMESTAMP     NULL DEFAULT CURRENT_TIMESTAMP,
                eliminado_en   DATETIME      NULL,
                INDEX idx_estado (estado),
                INDEX idx_cedula (cliente_cedula),
                INDEX idx_vivas  (eliminado_en, id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
        );
        esquema_refrescar();
    }
);

$reparar(
    "tabla cotizacion_items",
    static fn(): bool => tabla_existe('cotizacion_items'),
    static function (): void {
        db()->exec(
            "CREATE TABLE IF NOT EXISTS cotizacion_items (
                id              INT AUTO_INCREMENT PRIMARY KEY,
                cotizacion_id   INT           NOT NULL,
                producto_codigo VARCHAR(60)   NOT NULL DEFAULT '',
                producto_nombre VARCHAR(200)  NOT NULL DEFAULT '',
                marca           VARCHAR(80)   NOT NULL DEFAULT '',
                modelo          VARCHAR(80)   NOT NULL DEFAULT '',
                cantidad        INT           NOT NULL DEFAULT 1,
                precio_unitario DECIMAL(14,2) NOT NULL DEFAULT 0,
                INDEX idx_cotizacion (cotizacion_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
        );
        esquema_refrescar();
    }
);

// ── 3. Imágenes de producto ────────────────────────────────────────
$reparar(
    "tabla producto_imagenes",
    static fn(): bool => tabla_existe('producto_imagenes'),
    static function (): void {
        db()->exec(
            "CREATE TABLE IF NOT EXISTS producto_imagenes (
                id              INT AUTO_INCREMENT PRIMARY KEY,
                producto_codigo VARCHAR(60) NOT NULL,
                imagen_base64   LONGTEXT    NOT NULL,
                imagen_ext      VARCHAR(8)  NOT NULL DEFAULT 'jpg',
                creado_en       TIMESTAMP   NULL DEFAULT CURRENT_TIMESTAMP,
                actualizado_en  DATETIME    NULL,
                UNIQUE KEY uk_producto (producto_codigo)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
        );
        esquema_refrescar();
    }
);

// ── 4. Vista `v_stock_disponible` ──────────────────────────────────
//  El recurso `stock_disponible` lee esta vista y hoy responde 500
//  porque nunca se creó.
//
//  Una fila por producto y tienda:
//    · `stock_manual`  → las unidades sueltas que lleva `productos`
//    · `unidades_imei` → los IMEIs sin vender ubicados en esa tienda
//    · `disponible`    → lo que hay de verdad. Para lo que se controla
//      por IMEI manda el conteo de IMEIs; para el resto, `stock_manual`.
//      No se pueden sumar: qué categorías usan IMEI se configura en la
//      app, no en la base, así que la única regla estable es "si tiene
//      IMEIs cargados, esos son sus unidades".
$reparar(
    "vista v_stock_disponible",
    static fn(): bool => tabla_existe('v_stock_disponible'),
    static function (): void {
        db()->exec(
            "CREATE OR REPLACE VIEW v_stock_disponible AS
             SELECT
                 p.id                AS producto_id,
                 p.codigo            AS codigo,
                 p.codigo            AS producto_codigo,
                 p.nombre            AS nombre,
                 p.nombre            AS producto_nombre,
                 p.categoria         AS categoria,
                 p.marca             AS marca,
                 p.modelo            AS modelo,
                 p.tienda            AS tienda,
                 p.tienda            AS ubicacion,
                 p.precio_costo      AS precio_costo,
                 p.precio_venta      AS precio_venta,
                 p.stock_manual      AS stock_manual,
                 COALESCE(i.unidades, 0) AS unidades_imei,
                 CASE WHEN COALESCE(i.unidades, 0) > 0
                      THEN i.unidades
                      ELSE p.stock_manual
                 END                 AS disponible,
                 CASE WHEN COALESCE(i.unidades, 0) > 0
                      THEN i.unidades
                      ELSE p.stock_manual
                 END                 AS stock_disponible
             FROM productos p
             LEFT JOIN (
                 SELECT producto_codigo, ubicacion, COUNT(*) AS unidades
                 FROM stock_imei
                 WHERE (vendido = 0 OR vendido IS NULL)
                   AND eliminado_en IS NULL
                 GROUP BY producto_codigo, ubicacion
             ) i ON i.producto_codigo = p.codigo AND i.ubicacion = p.tienda
             WHERE p.eliminado_en IS NULL"
        );
    }
);

// ── 5. Recursos del router que apuntan a un archivo inexistente ────
$handlersFaltantes = [];
$handlersOk        = 0;
foreach (get_endpoints() as $recurso => $archivo) {
    if (is_file(__DIR__ . '/' . $archivo)) { $handlersOk++; continue; }
    $handlersFaltantes[$recurso] = $archivo;
}

// ── Informe ────────────────────────────────────────────────────────
$sano = !$errores && !$handlersFaltantes;

json_response([
    'ok'        => $sano,
    'estado'    => $sano
        ? 'Backend sano: esquema completo y todos los handlers subidos.'
        : 'Revisar: hay reparaciones fallidas o handlers sin subir.',
    'reparado'  => $aplicado,
    'ya_estaba' => $ya_estaba,
    'errores'   => $errores,
    'handlers'  => [
        'ok'        => $handlersOk,
        'faltantes' => $handlersFaltantes,
        'nota'      => $handlersFaltantes
            ? 'Estos recursos están registrados en api.php pero el archivo '
              . 'no está en /endpoints/. La app va a fallar con '
              . '"Recurso no encontrado" al usarlos. Subí los archivos.'
            : 'Todos los recursos registrados tienen su archivo subido.',
    ],
    'timestamp' => date('Y-m-d H:i:s'),
]);
