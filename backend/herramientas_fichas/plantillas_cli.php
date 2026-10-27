<?php
// ============================================================================
//  plantillas_cli.php — Para los scripts de fichas (traído de Brizuela): lee
//  por stdin {"productos":[…], "categorias":[…]} y devuelve cada producto con
//  su plantilla, más las plantillas con sus campos. Misma regla que el
//  servidor (fichaPlantillaPara de endpoints/ficha_tecnica.php), sin base
//  de datos.
//
//  `categorias` es la lista que la app guarda en configuracion
//  (cfg_categorias_productos): [{nombre, usa_imei}].
//
//      php plantillas_cli.php < entrada.json > salida.json
//
//  Corre en la PC. NO se sube al servidor.
// ============================================================================

declare(strict_types=1);

// Solo desde la consola: si desplegar.sh lo sube con el resto de backend/,
// por la web no hace nada.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
define('FICHA_SOLO_FUNCIONES', true);
require __DIR__ . '/../endpoints/ficha_tecnica.php';

$e = json_decode((string)stream_get_contents(STDIN), true) ?: [];
$imei = [];
foreach (($e['categorias'] ?? []) as $c) {
    if (!is_array($c)) continue;
    $u = $c['usa_imei'] ?? false;
    $imei[mb_strtolower(trim((string)($c['nombre'] ?? '')), 'UTF-8')] =
        $u === true || $u === 1 || $u === '1' || $u === 'true';
}
$salida = ['plantillas' => [], 'productos' => []];
foreach (fichaPlantillas() as $nombre => $p) $salida['plantillas'][$nombre] = $p['grupos'];
foreach (($e['productos'] ?? []) as $p) {
    $cat = (string)($p['categoria'] ?? '');
    $salida['productos'][] = [
        'codigo'    => (string)($p['codigo'] ?? ''),
        'nombre'    => (string)($p['nombre'] ?? ''),
        'categoria' => $cat,
        'marca'     => (string)($p['marca'] ?? ''),
        'modelo'    => (string)($p['modelo'] ?? ''),
        'plantilla' => fichaPlantillaPara($cat, (string)($p['nombre'] ?? ''),
            $imei[mb_strtolower(trim($cat), 'UTF-8')] ?? false),
    ];
}
echo json_encode($salida, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
