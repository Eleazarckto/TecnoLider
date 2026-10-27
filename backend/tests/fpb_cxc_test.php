<?php
// ════════════════════════════════════════════════════════════════════
//  fpb_cxc_test.php — La deuda de una venta FPB, en el servidor
//  (lib/factura_cuadre.php). Port adaptado del de Brizuela al esquema de
//  TecnoLíder (cuentas_cobrar con borrado lógico, sin guardarCuentaCobrar).
//
//      php backend/tests/fpb_cxc_test.php
//
//  Necesita pdo_sqlite. Nunca toca la base real.
// ════════════════════════════════════════════════════════════════════

declare(strict_types=1);
// Solo por consola: si se llega a subir, por la web no hace nada.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }

require __DIR__ . '/../lib/factura_cuadre.php';

$fallos = 0;
$pasadas = 0;
function comprobar(string $nombre, $esperado, $obtenido): void {
    global $fallos, $pasadas;
    if ($esperado === $obtenido) { $pasadas++; return; }
    $fallos++;
    fwrite(STDERR, "  FALLA  $nombre\n         esperado: " . var_export($esperado, true)
                 . "\n         obtenido: " . var_export($obtenido, true) . "\n");
}

$PDOS = [];   // vivos: que ningún PDO nuevo herede el id de objeto de otro
function base(): PDO {
    global $PDOS;
    $pdo = new PDO('sqlite::memory:');
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    // Como en producción: sin nro_factura ni tienda (los agrega el esquema).
    $pdo->exec('CREATE TABLE cuentas_cobrar (id INTEGER PRIMARY KEY AUTOINCREMENT, cedula TEXT,
        nombre TEXT, telefono TEXT, correo TEXT, monto_total REAL, saldo_favor REAL DEFAULT 0,
        factura_id INT, financiadora TEXT, notas TEXT, creado_en TEXT, eliminado_en TEXT)');
    $pdo->exec('CREATE TABLE cuentas_cobrar_cuotas (id INTEGER PRIMARY KEY AUTOINCREMENT,
        cuenta_id INT, numero INT, monto REAL, fecha TEXT, pagada INT DEFAULT 0, fecha_pago TEXT)');
    $pdo->exec('CREATE TABLE cuentas_cobrar_pagos (id INTEGER PRIMARY KEY AUTOINCREMENT,
        cuenta_id INT, metodo TEXT, monto REAL, fecha TEXT, referencia TEXT, notas TEXT)');
    fc_asegurar_esquema($pdo, true);
    return $PDOS[] = $pdo;
}

$factura = [
    'nro_factura' => '1791390473465-0428', 'cedula' => '30128398', 'cliente' => 'Eduardo Perez',
    'telefono' => '04126775841', 'tienda' => 'Tecno Líder Principal',
    'fpb' => ['deuda' => 300, 'cuotas' => [
        ['numero' => 1, 'monto' => 150, 'fecha' => '2026-11-16'],
        ['numero' => 2, 'monto' => 150, 'fecha' => '2026-12-16']]],
];

echo "== Crear la cuenta con la factura ==\n";
$pdo = base();
$r = fc_con_cuenta_fpb($pdo, 7830, $factura, ['ok' => true, 'id' => 7830]);
comprobar('la respuesta trae la cuenta creada', true, $r['cxc']['creada'] ?? null);
comprobar('por la deuda', 300.0, $r['cxc']['monto'] ?? null);
$c = $pdo->query('SELECT * FROM cuentas_cobrar')->fetch(PDO::FETCH_ASSOC);
comprobar('vinculada a la factura', [7830, '1791390473465-0428'], [(int)$c['factura_id'], $c['nro_factura']]);
comprobar('con la tienda', 'Tecno Líder Principal', $c['tienda']);
comprobar('financiadora FPB', 'FPB', $c['financiadora']);
comprobar('con la nota de siempre', 'Generado automáticamente desde factura 1791390473465-0428 · 2 cuota(s)', $c['notas']);
comprobar('con sus cuotas', 2, (int)$pdo->query('SELECT COUNT(*) FROM cuentas_cobrar_cuotas')->fetchColumn());

echo "== Un reintento no duplica ==\n";
$r = fc_con_cuenta_fpb($pdo, 7830, $factura, ['ok' => true, 'id' => 7830, 'ya_existia' => true]);
comprobar('devuelve la misma cuenta', [false, (int)$c['id']], [$r['cxc']['creada'], $r['cxc']['id']]);
comprobar('sigue habiendo una sola', 1, (int)$pdo->query('SELECT COUNT(*) FROM cuentas_cobrar')->fetchColumn());

echo "== Sin FPB no se toca nada ==\n";
$r = fc_con_cuenta_fpb($pdo, 9999, ['cedula' => 'x'], ['ok' => true, 'id' => 9999]);
comprobar('una factura de contado no lleva cxc', false, isset($r['cxc']) || isset($r['cxc_error']));

echo "== Datos malos: la factura queda, la app se entera ==\n";
$r = fc_con_cuenta_fpb($pdo, 8000, ['fpb' => ['deuda' => 0]] + $factura, ['ok' => true, 'id' => 8000]);
comprobar('deuda 0', 'La deuda FPB tiene que ser mayor que 0.', $r['cxc_error'] ?? null);
$malo = $factura; $malo['fpb']['cuotas'][1]['fecha'] = '16/12/2026';
$r = fc_con_cuenta_fpb($pdo, 8001, $malo, ['ok' => true, 'id' => 8001]);
comprobar('cuota sin fecha válida', 'La cuota 2 del FPB está incompleta.', $r['cxc_error'] ?? null);

echo "== Cuotas que no suman la deuda se reparten de nuevo ==\n";
$n = fc_fpb_normalizar(['deuda' => 100, 'cuotas' => [
    ['numero' => 1, 'monto' => 40, 'fecha' => '2026-11-01'],
    ['numero' => 2, 'monto' => 40, 'fecha' => '2026-12-01'],
    ['numero' => 3, 'monto' => 40, 'fecha' => '2027-01-01']]]);
comprobar('33,33 + 33,33 + 33,34', [33.33, 33.33, 33.34], array_column($n['cuotas'], 'monto'));
$n = fc_fpb_normalizar(['deuda' => 120]);
comprobar('sin cuotas también vale', [120.0, []], [$n['deuda'], $n['cuotas']]);

echo "== Al eliminar la factura ==\n";
$pdo = base();
fc_fpb_asegurar_cuenta($pdo, 1, $factura);
$r = fc_anular_cxc_de_factura($pdo, 1);
comprobar('sin abonos: se anula', [[1], []], [$r['eliminadas'], $r['conservadas']]);
comprobar('borrado lógico de la cuenta', 1,
    (int)$pdo->query('SELECT COUNT(*) FROM cuentas_cobrar WHERE eliminado_en IS NOT NULL')->fetchColumn());
comprobar('y sus cuotas', 0, (int)$pdo->query('SELECT COUNT(*) FROM cuentas_cobrar_cuotas')->fetchColumn());
comprobar('una factura nueva con la misma id crea otra cuenta (la anulada no cuenta)', true,
    fc_fpb_asegurar_cuenta($pdo, 1, $factura)['creada']);

$pdo = base();
$cta = fc_fpb_asegurar_cuenta($pdo, 2, $factura)['id'];
$pdo->prepare("INSERT INTO cuentas_cobrar_pagos (cuenta_id, metodo, monto, fecha) VALUES (?, 'Divisas', 50, '2026-10-20')")
    ->execute([$cta]);
$r = fc_anular_cxc_de_factura($pdo, 2);
comprobar('con abonos: se conserva', [[], [$cta]], [$r['eliminadas'], $r['conservadas']]);
$c = $pdo->query('SELECT * FROM cuentas_cobrar')->fetch(PDO::FETCH_ASSOC);
comprobar('viva', null, $c['eliminado_en']);
comprobar('con aviso en la nota', true, strpos((string)$c['notas'], 'AVISO: la factura de esta deuda se eliminó') !== false);
comprobar('y conserva lo que decía', 0, strpos((string)$c['notas'], 'Generado automáticamente desde factura'));

$pdo = base();
$cta = fc_fpb_asegurar_cuenta($pdo, 3, $factura)['id'];
$pdo->prepare('UPDATE cuentas_cobrar_cuotas SET pagada = 1 WHERE cuenta_id = ? AND numero = 1')->execute([$cta]);
comprobar('una cuota pagada también la conserva', [$cta], fc_anular_cxc_de_factura($pdo, 3)['conservadas']);

$pdo = base();
$pdo->exec("INSERT INTO cuentas_cobrar (cedula, nombre, monto_total, notas) VALUES ('1', 'A mano', 50, 'Préstamo')");
comprobar('una cuenta sin factura no se toca', [[], []],
    array_values(fc_anular_cxc_de_factura($pdo, 0)));
comprobar('sigue viva', 1, (int)$pdo->query('SELECT COUNT(*) FROM cuentas_cobrar WHERE eliminado_en IS NULL')->fetchColumn());

echo "\n" . ($fallos === 0 ? "OK" : "FALLAS: $fallos") . " — $pasadas comprobaciones pasadas\n";
exit($fallos === 0 ? 0 : 1);
