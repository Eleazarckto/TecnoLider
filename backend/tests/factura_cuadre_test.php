<?php
// ════════════════════════════════════════════════════════════════════
//  factura_cuadre_test.php — Cuadre de la factura en el servidor
//  (lib/factura_cuadre.php). Port adaptado de factura_lista_test.php de
//  Brizuela: sin chips, sin modalidad por factura, sin vuelto por Pago
//  Móvil ni DPF. Contado/financiado POR PRODUCTO y tasa BCV.
//
//      php backend/tests/factura_cuadre_test.php
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

function contado(float $div, ?float $bcv = null, string $ref = 'A1'): array {
    return ['ref' => $ref, 'tipo' => 'item', 'financiada' => false,
            'precio_divisa' => $div] + ($bcv === null ? [] : ['precio_bcv' => $bcv]);
}
function financiada(float $div, ?float $inicial, float $precioFin = 0, string $ref = '351111'): array {
    $l = ['ref' => $ref, 'tipo' => 'equipo', 'financiada' => true, 'precio_divisa' => $div,
          'precio_financiadora' => $precioFin, 'nombre' => 'Redmi 13'];
    if ($inicial !== null) $l['inicial'] = $inicial;
    return $l;
}
function pago(string $metodo, float $monto, bool $vuelto = false): array {
    return ['metodo' => $metodo, 'monto' => $monto] + ($vuelto ? ['es_vuelto' => true] : []);
}

$TASA = 100.0;

echo "== Moneda de cada método (igual que esMetodoEnBolivares de la app) ==\n";
foreach (['Pago Móvil' => 'BS', 'Pago Movil' => 'BS', 'Efectivo Bs' => 'BS', 'Transferencia' => 'BS',
          'Punto de venta' => 'BS', 'Punto de Venta BDV' => 'BS', 'Transferencia Bs' => 'BS',
          'Efectivo Bs.' => 'BS', 'Biopago Bs' => 'BS',
          'Zelle' => 'USD', 'Divisas' => 'USD', 'Efectivo $' => 'USD', 'Binance' => 'USD',
          'Cashea' => 'USD', 'Transferencia USD' => 'USD', 'Efectivo divisas' => 'USD'] as $m => $esp) {
    comprobar("moneda de $m", $esp, fc_moneda_de_metodo($m));
}
comprobar('vuelto en efectivo $', true, fc_metodo_permite_vuelto('Efectivo $'));
comprobar('vuelto en efectivo Bs', true, fc_metodo_permite_vuelto('Efectivo Bs'));
comprobar('vuelto en divisas', true, fc_metodo_permite_vuelto('Divisas'));
comprobar('vuelto por Pago Móvil NO', false, fc_metodo_permite_vuelto('Pago Móvil'));
comprobar('vuelto por punto NO', false, fc_metodo_permite_vuelto('Punto de venta'));
comprobar('vuelto por Zelle NO', false, fc_metodo_permite_vuelto('Zelle'));

echo "== Contado ==\n";
$r = fc_cuadre([contado(100)], [pago('Divisas', 100)], $TASA);
comprobar('pagado en $ al precio de divisas: cuadra', null, $r['problema']);
$r = fc_cuadre([contado(100, 110)], [pago('Pago Móvil', 11000)], $TASA);
comprobar('pagado en Bs al precio BCV × tasa: cuadra', null, $r['problema']);
$r = fc_cuadre([contado(100, 110)], [pago('Pago Móvil', 10000)], $TASA);
comprobar('en Bs al precio de divisas NO alcanza', 'Falta cobrar $9.09 o Bs 1000.00.', $r['problema']);
$r = fc_cuadre([contado(100)], [pago('Divisas', 50), pago('Pago Móvil', 5000)], $TASA);
comprobar('mezclado sin precio BCV: $50 + Bs 5000 cuadra', null, $r['problema']);
$r = fc_cuadre([contado(100, 110)], [pago('Divisas', 50), pago('Pago Móvil', 5500)], $TASA);
comprobar('mezclado: $50 (media) + Bs 5500 (media a BCV) cuadra', null, $r['problema']);
$r = fc_cuadre([contado(100)], [pago('Divisas', 60), pago('Pago Móvil', 5000)], $TASA);
comprobar('no se suman $ y Bs crudos: pagó de más', true,
    strpos((string)$r['problema'], 'de más') !== false);
comprobar('sobra $10', 10.0, $r['sobra_usd']);
comprobar('o Bs 1000', 1000.0, $r['sobra_bs']);
$r = fc_cuadre([contado(100)], [pago('Pago Móvil', 9999.5)], $TASA);
comprobar('tolerancia de 1 Bs', null, $r['problema']);
$r = fc_cuadre([contado(100)], [pago('Pago Móvil', 9998)], $TASA);
comprobar('2 Bs ya no', true, $r['problema'] !== null);
$r = fc_cuadre([contado(100)], [pago('Divisas', 99.995)], $TASA);
comprobar('tolerancia de $0,01', null, $r['problema']);
$r = fc_cuadre([contado(100)], [pago('Pago Móvil', 10000)], 0);
comprobar('sin tasa no se convierten los Bs', 'No hay tasa BCV: no se pueden convertir los pagos en Bs.', $r['problema']);

echo "== Vuelto ==\n";
$r = fc_cuadre([contado(95)], [pago('Divisas', 100), pago('Efectivo $', 5, true)], $TASA);
comprobar('vuelto en efectivo $: cuadra', null, $r['problema']);
$r = fc_cuadre([contado(95)], [pago('Divisas', 100), pago('Efectivo $', -5)], $TASA);
comprobar('vuelto guardado en negativo: cuadra', null, $r['problema']);
$r = fc_cuadre([contado(95)], [pago('Divisas', 100), pago('Efectivo Bs', 500, true)], $TASA);
comprobar('vuelto en efectivo Bs: cuadra', null, $r['problema']);
$r = fc_cuadre([contado(95)], [pago('Divisas', 100), pago('Pago Móvil', 500, true)], $TASA);
comprobar('vuelto por Pago Móvil: NO', 'El vuelto solo se da en efectivo o divisas (no por Pago Móvil).', $r['problema']);

echo "== Mixto: teléfono por Krece + forro de contado ==\n";
$lin = [financiada(200, 50, 260), contado(5, 6, 'FORRO')];
$r = fc_cuadre($lin, [pago('Divisas', 55)], $TASA);
comprobar('inicial 50 + forro 5 en $: cuadra', null, $r['problema']);
comprobar('inicial', 50.0, $r['inicial']);
comprobar('financiado = precio Krece − inicial', 210.0, $r['monto_financiado']);
$r = fc_cuadre($lin, [pago('Pago Móvil', 5600)], $TASA);
comprobar('en Bs: (inicial 50 + forro BCV 6) × tasa cuadra', null, $r['problema']);
$r = fc_cuadre($lin, [pago('Divisas', 50)], $TASA);
comprobar('falta el forro', 'Falta cobrar $5.00 o Bs 600.00 (contado + inicial).', $r['problema']);
$r = fc_cuadre([financiada(200, null), contado(5)], [pago('Divisas', 55)], $TASA);
comprobar('sin inicial escrita no se emite', 'Escriba la inicial aprobada por la financiadora de: Redmi 13.', $r['problema']);
$r = fc_cuadre([financiada(200, 0, 260)], [pago('Sin inicial (promoción)', 0)], $TASA);
comprobar('venta financiada sin inicial con pago $0: cuadra', null, $r['problema']);
comprobar('todo financiado', 260.0, $r['monto_financiado']);
$r = fc_cuadre([financiada(200, 0, 260)], [pago('Divisas', 10)], $TASA);
comprobar('sin inicial pero pagó algo: es vuelto', true, strpos((string)$r['problema'], 'de más') !== false);

echo "== FPB ==\n";
$r = fc_cuadre([contado(300)], [pago('Divisas', 100)], $TASA, true);
comprobar('FPB sale con lo que pague el cliente', null, $r['problema']);
comprobar('deuda propuesta = total − pagado', 200.0, $r['deuda_fpb']);
$r = fc_cuadre([contado(300)], [], $TASA, true);
comprobar('FPB sin pago: todo es deuda', 300.0, $r['deuda_fpb']);
$r = fc_cuadre([contado(300, 330)], [pago('Pago Móvil', 16500)], $TASA, true);
comprobar('FPB pagando la mitad en Bs (a BCV): deuda $150', 150.0, $r['deuda_fpb']);
$r = fc_cuadre([contado(300)], [pago('Divisas', 300)], $TASA, true);
comprobar('FPB pagado todo: sin deuda', 0.0, $r['deuda_fpb']);
$r = fc_cuadre([contado(300)], [pago('Divisas', 320)], $TASA, true);
comprobar('FPB pagó de más: vuelto', true, strpos((string)$r['problema'], 'de más') !== false);

echo "== Validar contra la base (SQLite) ==\n";
$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$pdo->exec('CREATE TABLE productos (id INTEGER PRIMARY KEY, codigo TEXT, tienda TEXT, precio_venta REAL, eliminado_en TEXT)');
$pdo->exec('CREATE TABLE stock_imei (id INTEGER PRIMARY KEY, imei TEXT, producto_codigo TEXT)');
$pdo->exec("INSERT INTO productos (codigo, tienda, precio_venta) VALUES
    ('FORRO', '', 5), ('FORRO', 'Sucursal', 6), ('R13', '', 200)");
$pdo->exec("INSERT INTO stock_imei (imei, producto_codigo) VALUES ('351111', 'R13')");
$body = [
    'tienda' => 'Principal',
    'equipos' => [['imei' => '351111', 'vendedor' => '']],
    'items' => [['codigo' => 'FORRO', 'vendedor' => '']],
    'pagos' => [pago('Divisas', 55)],
    'cuadre' => ['tasa_bcv' => 100, 'fpb' => false, 'lineas' => [
        financiada(200, 50, 260), contado(5, null, 'FORRO')]],
];
$r = fc_validar($pdo, $body);
comprobar('la factura de la app cuadra', [50.0, 210.0], [$r['inicial'], $r['monto_financiado']]);
$b = $body; $b['cuadre']['lineas'][1]['precio_divisa'] = 1;   // la app manda otro precio
$b['pagos'] = [pago('Divisas', 51)];
try { fc_validar($pdo, $b); $msg = 'sin error'; } catch (FacturaCuadreError $e) { $msg = $e->getMessage(); }
comprobar('el precio de contado lo pone el servidor (catálogo)', 'Falta cobrar $4.00 o Bs 400.00 (contado + inicial).', $msg);
$b = $body; $b['tienda'] = 'Sucursal'; $b['pagos'] = [pago('Divisas', 56)];
comprobar('con la fila de la tienda', 50.0, fc_validar($pdo, $b)['inicial']);
$b = $body; array_pop($b['cuadre']['lineas']);
try { fc_validar($pdo, $b); $msg = 'sin error'; } catch (FacturaCuadreError $e) { $msg = $e->getMessage(); }
comprobar('las líneas tienen que ser los productos', true, strpos($msg, 'no coinciden') !== false);
$b = $body; $b['items'] = [['codigo' => 'NOEXISTE']]; $b['cuadre']['lineas'][1]['ref'] = 'NOEXISTE';
try { fc_validar($pdo, $b); $msg = 'sin error'; } catch (FacturaCuadreError $e) { $msg = $e->getMessage(); }
comprobar('producto inexistente', 'El producto NOEXISTE no está en el inventario.', $msg);

echo "== Esquema (aditivo e idempotente) ==\n";
$pdoValidar = $pdo;   // vivo: que el PDO nuevo no herede su id de objeto
$pdo = new PDO('sqlite::memory:');
$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
$pdo->exec('CREATE TABLE facturas (id INTEGER PRIMARY KEY, nro_factura TEXT, total REAL, eliminado_en TEXT)');
$pdo->exec('CREATE TABLE factura_items (id INTEGER PRIMARY KEY, factura_id INT, producto_codigo TEXT)');
$pdo->exec('CREATE TABLE factura_equipos (id INTEGER PRIMARY KEY, factura_id INT, imei TEXT)');
$pdo->exec('CREATE TABLE factura_pagos (id INTEGER PRIMARY KEY, factura_id INT, metodo TEXT, monto REAL, referencia TEXT)');
$pdo->exec('CREATE TABLE cuentas_cobrar (id INTEGER PRIMARY KEY, factura_id INT, notas TEXT)');
$pdo->exec("INSERT INTO facturas (nro_factura, total) VALUES ('VIEJA', 123)");
$pdo->exec("INSERT INTO factura_pagos (factura_id, metodo, monto) VALUES (1, 'Divisas', 123)");
[$ap, $ya, $err] = fc_asegurar_esquema($pdo, true);
comprobar('sin errores', [], $err);
comprobar('agrega 12 columnas (factura_id ya estaba)', 12, count($ap));
comprobar('agrega facturas.direccion', true, in_array('facturas.direccion', $ap, true));
comprobar('factura_id ya estaba', true, in_array('cuentas_cobrar.factura_id', $ya, true));
[$ap2] = fc_asegurar_esquema($pdo, true);
comprobar('la segunda vez no hace nada', [], $ap2);
$f = $pdo->query('SELECT * FROM facturas')->fetch(PDO::FETCH_ASSOC);
comprobar('no toca las facturas viejas', [123.0, null, null], [(float)$f['total'], $f['inicial'], $f['clave_idempotencia']]);
$p = $pdo->query('SELECT * FROM factura_pagos')->fetch(PDO::FETCH_ASSOC);
comprobar('pago viejo: es_vuelto 0 y sin moneda', [0, null], [(int)$p['es_vuelto'], $p['moneda']]);
$pdo->exec("UPDATE facturas SET clave_idempotencia = 'abcdef0123456789' WHERE id = 1");
comprobar('clave encontrada', 1, fc_factura_de_clave($pdo, 'abcdef0123456789'));
comprobar('clave inválida se ignora', null, fc_clave(['clave_idempotencia' => "x'; DROP"]));
try {
    $pdo->exec("INSERT INTO facturas (nro_factura, clave_idempotencia) VALUES ('OTRA', 'abcdef0123456789')");
    $dup = 'entró';
} catch (PDOException $e) { $dup = 'rechazada'; }
comprobar('la clave es única', 'rechazada', $dup);
$pdo->exec("UPDATE facturas SET eliminado_en = '2026-10-01' WHERE id = 1");
comprobar('una factura eliminada no cuenta como reintento', null, fc_factura_de_clave($pdo, 'abcdef0123456789'));

echo "== Pagos: normalizar y conservar en el PUT ==\n";
$n = fc_normalizar_pago(['metodo' => 'Efectivo $', 'monto' => 5, 'es_vuelto' => true], true);
comprobar('vuelto de la app nueva: negativo, USD, es_vuelto 1', [-5.0, 'USD', 1], [$n['monto'], $n['moneda'], $n['es_vuelto']]);
$n = fc_normalizar_pago(['metodo' => 'Pago Móvil', 'monto' => 1000], true);
comprobar('pago normal en Bs', [1000, 'BS', null], [$n['monto'], $n['moneda'], $n['es_vuelto'] ?? null]);
$n = fc_normalizar_pago(['metodo' => 'Divisas', 'monto' => 100], false);
comprobar('a la app vieja no se le agrega nada', ['metodo' => 'Divisas', 'monto' => 100], $n);
$n = fc_normalizar_pago(['metodo' => 'Efectivo $', 'monto' => -5], false);
comprobar('app vieja con negativo: es_vuelto 1', 1, $n['es_vuelto']);

$pdo->exec("INSERT INTO factura_pagos (factura_id, metodo, monto, referencia, moneda, monto_usd, es_vuelto)
            VALUES (7, 'Pago Móvil', 5600, '1234', 'BS', 56, 0), (7, 'Efectivo $', -5, NULL, 'USD', -5, 1)");
$prev = fc_previos($pdo, 'factura_pagos', 7);
$pdo->exec('DELETE FROM factura_pagos WHERE factura_id = 7');
// La 1.0.17 reenvía los pagos sin las columnas nuevas.
foreach ([['metodo' => 'Pago Móvil', 'monto' => 5600, 'referencia' => '1234'],
          ['metodo' => 'Efectivo $', 'monto' => -5]] as $pg) {
    $pg = fc_normalizar_pago($pg, false);
    $pdo->prepare('INSERT INTO factura_pagos (factura_id, metodo, monto, referencia, es_vuelto) VALUES (7, ?, ?, ?, ?)')
        ->execute([$pg['metodo'], $pg['monto'], $pg['referencia'] ?? null, $pg['es_vuelto'] ?? 0]);
    fc_pago_reinsertado($pdo, (int)$pdo->lastInsertId(), $pg, $prev);
}
$filas = $pdo->query('SELECT metodo, moneda, monto_usd, es_vuelto FROM factura_pagos WHERE factura_id = 7 ORDER BY id')
    ->fetchAll(PDO::FETCH_ASSOC);
comprobar('el PUT viejo conserva moneda y monto_usd', ['BS', 56.0], [$filas[0]['moneda'], (float)$filas[0]['monto_usd']]);
comprobar('y el vuelto sigue siendo vuelto', ['USD', 1], [$filas[1]['moneda'], (int)$filas[1]['es_vuelto']]);

$pdo->exec("INSERT INTO factura_items (factura_id, producto_codigo, precio_unitario) VALUES (8, 'FORRO', 5), (8, 'FORRO', 4.5)");
$prev = fc_previos($pdo, 'factura_items', 8);
$pdo->exec('DELETE FROM factura_items WHERE factura_id = 8');
foreach ([['codigo' => 'FORRO'], ['codigo' => 'FORRO']] as $it) {
    $pdo->exec("INSERT INTO factura_items (factura_id, producto_codigo) VALUES (8, 'FORRO')");
    fc_linea_insertada($pdo, 'factura_items', (int)$pdo->lastInsertId(), $it, 'FORRO', $prev);
}
comprobar('el PUT viejo conserva el precio por línea, en orden', [5.0, 4.5],
    array_map('floatval', $pdo->query('SELECT precio_unitario FROM factura_items WHERE factura_id = 8 ORDER BY id')->fetchAll(PDO::FETCH_COLUMN)));
$sinPrev = [];
$pdo->exec("INSERT INTO factura_items (factura_id, producto_codigo) VALUES (9, 'FORRO')");
fc_linea_insertada($pdo, 'factura_items', (int)$pdo->lastInsertId(), ['codigo' => 'FORRO', 'precio_unitario' => 6], 'FORRO', $sinPrev);
comprobar('la app nueva guarda su precio', 6.0, (float)$pdo->query('SELECT precio_unitario FROM factura_items WHERE factura_id = 9')->fetchColumn());

echo "== Búsqueda en todo el historial ==\n";
$pdo->exec("CREATE TABLE fb (id INTEGER PRIMARY KEY, nro_factura TEXT, cliente TEXT, cedula TEXT, vendedor TEXT, telefono TEXT)");
$pdo->exec("INSERT INTO fb (nro_factura, cliente, cedula, vendedor, telefono) VALUES
    ('FAC-0001', 'Ana Pérez', 'V-12.345.678', 'Luis', '0414'), ('1791-22', 'Pedro', '9876543', 'Ana', '0424')");
$buscar = function (string $q) use ($pdo): array {
    [$c, $a] = fc_condicion_busqueda($q);
    $st = $pdo->prepare("SELECT id FROM fb WHERE $c ORDER BY id");
    $st->execute($a);
    return array_map('intval', $st->fetchAll(PDO::FETCH_COLUMN));
};
comprobar('cédula escrita sin puntos halla la guardada con puntos', [1], $buscar('12345678'));
comprobar('cédula con V y puntos', [1], $buscar('V-12.345.678'));
comprobar('por número', [2], $buscar('1791'));
comprobar('por nombre (cliente o vendedor)', [1, 2], $buscar('ana'));
comprobar('dígitos: en todos los campos y el id', [1, 2], $buscar('2'));

echo "\n" . ($fallos === 0 ? "OK" : "FALLAS: $fallos") . " — $pasadas comprobaciones pasadas\n";
exit($fallos === 0 ? 0 : 1);
