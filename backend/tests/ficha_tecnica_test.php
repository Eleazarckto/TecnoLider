<?php
// ============================================================================
//  ficha_tecnica_test.php — Pruebas de la ficha técnica
//  (endpoints/ficha_tecnica.php, traída de Brizuela, sin IA).
//
//      php backend/tests/ficha_tecnica_test.php
//
//  SQLite en memoria (hace falta pdo_sqlite): no toca ninguna base real.
//  NO se sube al servidor.
// ============================================================================

declare(strict_types=1);

// Solo desde la consola: si desplegar.sh lo sube con el resto de backend/,
// por la web no hace nada.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }

define('FICHA_SOLO_FUNCIONES', true);
require __DIR__ . '/../endpoints/ficha_tecnica.php';

$fallos = 0;
$pasadas = 0;
function comprobar(string $nombre, $esperado, $obtenido): void {
    global $fallos, $pasadas;
    if ($esperado === $obtenido) { $pasadas++; return; }
    $fallos++;
    fwrite(STDERR, "  FALLA  $nombre\n         esperado: " . var_export($esperado, true)
                 . "\n         obtenido: " . var_export($obtenido, true) . "\n");
}
function valor(array $ficha, string $grupo, string $campo): ?string {
    foreach ($ficha['campos'] as $c) if ($c['grupo'] === $grupo && $c['campo'] === $campo) return $c['valor'];
    return null;
}

echo "== Qué plantilla le toca a cada producto ==\n";
$casos = [
    ['Telefono', 'Redmi 13 8/256', true, 'equipo'],
    ['Equipos', 'Samsung Galaxy A15', false, 'equipo'],
    ['Accesorio', 'Forro iPhone 13 Pro', false, 'forro'],
    ['Accesorio', 'Cargador Apple Watch', false, 'carga'],
    ['Accesorio', 'Apple Watch Series 9', false, 'reloj'],
    ['Accesorio', 'Audífonos Bluetooth JBL Tune 520', false, 'audio'],
    ['Accesorio', 'AirPods Pro 2', false, 'audio'],
    ['Accesorio', 'Vidrio templado A15', false, 'vidrio'],
    ['Accesorio', 'Power bank 10000 mAh', false, 'bateria'],
    ['Televisor', 'Samsung 55" Crystal UHD', false, 'televisor'],
    ['Linea Blanca', 'Nevera Mabe 14 pies', false, 'linea_blanca'],
    ['Hogar', 'Lavadora LG 17 kg', false, 'linea_blanca'],
    ['Linea', 'Línea Movistar prepago', false, 'linea'],
    ['Servicio Tecnico', 'Cambio de pantalla', false, 'servicio'],
    ['Tablets', 'iPad 10ma generación', false, 'equipo'],
    ['Otros', 'Mochila', false, 'generico'],
    ['Accesorio', 'ROUTER MERCUSYS MR60X WIFI 6 AX1500', false, 'red'],
    ['Accesorio', 'tarjeta de memoria harvic class 10 16gb', false, 'memoria'],
    ['Accesorio', 'mini ups 10000 MaH', false, 'bateria'],
    ['Accesorio', 'Correa smart watch deportiva', false, 'accesorio'],
    ['Laptops', 'Laptop HP 15-FS0230WM 13 8/256', false, 'computadora'],
    ['Televisor', 'Soporte para tv', false, 'accesorio'],
    ['Telefono', 'control gamepad para celular', false, 'accesorio'],
    ['Linea Blanca', 'TV DE 43 GOOGLE TV QLED', false, 'televisor'],
];
foreach ($casos as [$cat, $nom, $imei, $esperada]) {
    comprobar("$cat / $nom", $esperada, fichaPlantillaPara($cat, $nom, $imei));
}

echo "== Plantillas ==\n";
foreach (array_keys(fichaPlantillas()) as $pl) {
    comprobar("plantilla $pl tiene campos", true, count(fichaCamposVacios($pl)) > 0);
}

echo "== Normalizar lo que manda la app ==\n";
$n = fichaNormalizarCampos([
    ['grupo' => ' Pantalla ', 'campo' => 'Tamaño', 'valor' => ' 6,7 pulgadas '],
    ['grupo' => 'pantalla', 'campo' => 'tamaño', 'valor' => 'duplicado'],
    ['grupo' => '', 'campo' => 'Extra', 'valor' => str_repeat('x', 500)],
    ['grupo' => 'X', 'campo' => '', 'valor' => 'sin campo'],
    'basura',
]);
comprobar('recorta', '6,7 pulgadas', $n[0]['valor']);
comprobar('sin duplicados ni campos sin nombre', 2, count($n));
comprobar('sin grupo va a General', 'General', $n[1]['grupo']);
comprobar('valor con tope', FICHA_MAX_VALOR, mb_strlen($n[1]['valor']));
$comb = fichaCombinar('forro', [['grupo' => 'Incluye', 'campo' => 'Garantía', 'valor' => ''],
                                ['grupo' => 'Extras', 'campo' => 'Radio', 'valor' => 'Sí']]);
comprobar('combinar: 4 de la plantilla + el extra con valor', 5, count($comb));

echo "== Con base de datos (como la de Tecno Líder) ==\n";
$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
// Una fila por tienda y borrado lógico, como en producción.
$pdo->exec("CREATE TABLE productos (id INTEGER PRIMARY KEY AUTOINCREMENT, codigo TEXT, tienda TEXT,
            nombre TEXT, categoria TEXT, marca TEXT, modelo TEXT, eliminado_en TEXT NULL)");
$pdo->exec("CREATE TABLE configuracion (id INTEGER PRIMARY KEY AUTOINCREMENT, clave TEXT UNIQUE, valor TEXT)");
$pdo->exec("CREATE TABLE usuarios (id INTEGER PRIMARY KEY AUTOINCREMENT, correo TEXT, rol TEXT,
            activo INTEGER DEFAULT 1, eliminado_en TEXT NULL)");
$pdo->prepare("INSERT INTO configuracion (clave, valor) VALUES (?, ?)")->execute([FICHA_CLAVE_CATEGORIAS,
    json_encode([['nombre' => 'Equipos Xiaomi', 'usa_imei' => true], ['nombre' => 'Accesorio', 'usa_imei' => false]])]);
$pdo->exec("INSERT INTO productos (codigo, tienda, nombre, categoria, marca, modelo, eliminado_en) VALUES
    ('RED13', 'Principal', 'Redmi 13 8/256', 'Equipos Xiaomi', 'Xiaomi', 'Redmi 13', NULL),
    ('RED13', 'Sucursal',  'Redmi 13 8/256', 'Equipos Xiaomi', 'Xiaomi', 'Redmi 13', NULL),
    ('FORRO', 'Principal', 'Forro iPhone 13', 'Accesorio', 'Genérico', '', NULL),
    ('VIEJO', 'Principal', 'Producto borrado', 'Accesorio', '', '', '2026-01-01 00:00:00')");
$pdo->exec("INSERT INTO usuarios (correo, rol, activo, eliminado_en) VALUES
    ('enc@x', 'Encargado', 1, NULL), ('ven@x', 'Vendedor', 1, NULL),
    ('ina@x', 'Dueño', 0, NULL), ('bor@x', 'Administrador', 1, '2026-01-01 00:00:00')");
fichaEsquema($pdo);

comprobar('usa IMEI por la configuración de la app', true, fichaUsaImei($pdo, 'equipos xiaomi'));
comprobar('categoría sin IMEI', false, fichaUsaImei($pdo, 'Accesorio'));
comprobar('categoría desconocida', false, fichaUsaImei($pdo, 'Nada'));
$sin = fichaDe($pdo, fichaProducto($pdo, 'RED13'));
comprobar('sin ficha: muestra la plantilla vacía', 0, $sin['llenos']);
comprobar('plantilla de teléfono por usa_imei (el nombre no lo dice)', 'equipo', $sin['plantilla']);
comprobar('un producto borrado no existe', null, fichaProducto($pdo, 'VIEJO'));
$res = fichaResumen($pdo);
comprobar('resumen: códigos distintos sin los borrados', [2, 0], [$res['total'], $res['con_ficha']]);

$enc = fichaIdentidad($pdo, ['usuario_correo' => 'ENC@x'], true);
$campos = $sin['campos'];
foreach ($campos as &$c) if ($c['campo'] === 'Procesador') $c['valor'] = 'MediaTek Helio G91 Ultra';
unset($c);
$campos[] = ['grupo' => 'Extras', 'campo' => 'Radio FM', 'valor' => 'Sí'];
$g = fichaGuardar($pdo, ['codigo' => 'RED13', 'campos' => $campos], $enc);
comprobar('guardado a mano', 'MediaTek Helio G91 Ultra', valor($g, 'Rendimiento', 'Procesador'));
comprobar('queda manual', 'manual', $g['origen']);
comprobar('conserva el campo agregado', 'Sí', valor($g, 'Extras', 'Radio FM'));
comprobar('quién la guardó', 'enc@x', $g['por']);
$g = fichaGuardar($pdo, ['codigo' => 'RED13', 'campos' => $campos], $enc);
comprobar('guardar dos veces lo mismo no duplica', 1,
    (int)$pdo->query("SELECT COUNT(*) FROM fichas_tecnicas WHERE producto_codigo = 'RED13'")->fetchColumn());
$g2 = fichaGuardar($pdo, ['codigo' => 'FORRO', 'campos' => [['grupo' => 'General', 'campo' => 'Tipo', 'valor' => 'Forro']],
                          'por_revisar' => true], $enc);
comprobar('carga por script: queda «auto» (revisar)', 'auto', $g2['origen']);
$res = fichaResumen($pdo);
comprobar('resumen: 2 con ficha', 2, $res['con_ficha']);
try { fichaGuardar($pdo, ['codigo' => 'VIEJO', 'campos' => []], $enc); $cod = 0; }
catch (FichaError $e) { $cod = $e->getCode(); }
comprobar('no se guarda ficha de un producto borrado', 400, $cod);

echo "== Quién puede ==\n";
$cod = function (string $correo, bool $editar) use ($pdo) {
    try { fichaIdentidad($pdo, ['usuario_correo' => $correo], $editar); return 200; }
    catch (FichaError $e) { return $e->getCode(); }
};
comprobar('el Vendedor ve', 200, $cod('ven@x', false));
comprobar('sin correo se ve igual (como el resto de la API)', 200, $cod('', false));
comprobar('el Vendedor no edita', 400, $cod('ven@x', true));
comprobar('el Encargado edita', 200, $cod('enc@x', true));
comprobar('un usuario desactivado no edita', 400, $cod('ina@x', true));
comprobar('un usuario borrado no edita', 400, $cod('bor@x', true));
comprobar('un correo que no existe no edita', 400, $cod('nadie@x', true));
comprobar('sin correo no edita', 400, $cod('', true));
comprobar('el maestro de soporte edita (no está en usuarios)', 200, $cod('EleazarCeccato@gmail.com', true));

echo "== Router ==\n";
$r = fichaAtender($pdo, 'GET', 'ficha_tecnica', [], ['codigo' => 'FORRO']);
comprobar('GET ficha_tecnica?codigo', [200, 'Forro'], [$r[0], valor($r[1]['data'], 'General', 'Tipo')]);
$r = fichaAtender($pdo, 'GET', 'ficha_tecnica', [], []);
comprobar('GET resumen', [200, true, 2], [$r[0], $r[1]['ok'], $r[1]['data']['total']]);
$r = fichaAtender($pdo, 'GET', 'ficha_tecnica', [], ['codigo' => 'NOEXISTE']);
comprobar('producto que no existe: 400 con ok:false', [400, false], [$r[0], $r[1]['ok']]);
$r = fichaAtender($pdo, 'POST', 'ficha_tecnica_guardar', ['codigo' => 'FORRO', 'campos' => [], 'usuario_correo' => 'ven@x'], []);
comprobar('el Vendedor no puede guardar por el router', [400, false], [$r[0], $r[1]['ok']]);
$r = fichaAtender($pdo, 'POST', 'ficha_tecnica_guardar', ['codigo' => 'FORRO',
    'campos' => [['grupo' => 'General', 'campo' => 'Material', 'valor' => 'Silicón']], 'usuario_correo' => 'enc@x'], []);
comprobar('el Encargado guarda por el router', [200, 'Silicón'], [$r[0], valor($r[1]['data'], 'General', 'Material')]);
comprobar('método equivocado: no lo atiende', null, fichaAtender($pdo, 'DELETE', 'ficha_tecnica', [], []));
comprobar('no existe «generar» (sin IA)', null, fichaAtender($pdo, 'POST', 'ficha_tecnica_generar', [], []));

echo "\n$pasadas pasadas, $fallos fallidas\n";
exit($fallos === 0 ? 0 : 1);
