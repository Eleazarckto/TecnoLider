<?php
// Endpoint TEMPORAL de diagnóstico v3 — solo tabla `facturas`
// URL: /api.php?resource=diagnostico_factura_cuotas
//
// Los pagos están dentro de la propia factura. Este diagnóstico
// muestra el schema de `facturas` y la última fila completa, para
// ver si los campos de cuotas están llegando y guardándose.
//
// BORRAR este archivo cuando el problema esté resuelto.

$pdo = db();
$pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);

// Schema completo de la tabla facturas
$schemaFacturas = [];
try {
    $schemaFacturas = $pdo->query(
        "SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT
         FROM INFORMATION_SCHEMA.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'facturas'
         ORDER BY ORDINAL_POSITION"
    )->fetchAll();
} catch (Throwable $e) {
    $schemaFacturas = ['error' => $e->getMessage()];
}

// Última factura completa
$ultimaFactura = null;
try {
    $ultimaFactura = $pdo->query(
        "SELECT * FROM facturas ORDER BY id DESC LIMIT 1"
    )->fetch();
} catch (Throwable $e) {
    $ultimaFactura = ['error' => $e->getMessage()];
}

json_response([
    'schema_tabla_facturas' => $schemaFacturas,
    'ultima_factura'        => $ultimaFactura,
    'timestamp'             => date('Y-m-d H:i:s'),
]);