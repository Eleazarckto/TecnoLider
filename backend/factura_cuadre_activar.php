<?php
// ════════════════════════════════════════════════════════════════════
//  factura_cuadre_activar.php — Enciende (o apaga) el cuadre y la deuda
//  FPB en el servidor (ver lib/factura_cuadre.php).
//
//  Encendido (`configuracion.factura_cuadre_servidor` = '1'):
//    · el servidor repite el cuadre de la app NUEVA y rechaza con 422 la
//      factura que no cuadra;
//    · el servidor crea la cuenta por cobrar FPB en la misma petición.
//  La app vieja (1.0.17) no manda el bloque `cuadre`: encendido o
//  apagado, sigue facturando exactamente igual.
//
//  Se corre en el servidor, desde la carpeta del api.php:
//
//     php factura_cuadre_activar.php              # enciende
//     php factura_cuadre_activar.php --apagar     # apaga
//     php factura_cuadre_activar.php --estado
//
//  (Equivale a POST configuracion {"factura_cuadre_servidor": "1"}.)
// ════════════════════════════════════════════════════════════════════
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }

require __DIR__ . '/lib/db.php';
require __DIR__ . '/lib/factura_cuadre.php';

$pdo = db();
fc_asegurar_esquema($pdo, true);
$modo = $argv[1] ?? '';
if ($modo !== '--estado') {
    $pdo->exec("CREATE TABLE IF NOT EXISTS configuracion (
        id INT AUTO_INCREMENT PRIMARY KEY,
        clave VARCHAR(120) NOT NULL UNIQUE,
        valor TEXT NULL,
        actualizado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    $pdo->prepare('INSERT INTO configuracion (clave, valor) VALUES (?, ?)
                   ON DUPLICATE KEY UPDATE valor = VALUES(valor)')
        ->execute([FC_FLAG, $modo === '--apagar' ? '0' : '1']);
}
echo 'Cuadre de facturas en el servidor: ' . (fc_flag_activo($pdo)
    ? "ENCENDIDO (valida la app nueva y crea la deuda FPB)\n"
    : "apagado (solo guarda los datos nuevos; la app crea la deuda FPB)\n");
