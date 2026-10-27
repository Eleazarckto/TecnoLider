<?php
// ════════════════════════════════════════════════════════════════════
//  facturas_endpoint_test.php — El endpoint `facturas` de verdad (api.php
//  → endpoints/facturas.php) servido por `php -S` sobre SQLite.
//
//  1. La app 1.0.17 contra el backend NUEVO responde y guarda EXACTAMENTE
//     lo mismo que contra el backend VIEJO (con la llave apagada y
//     encendida): se corre la misma secuencia en los dos y se comparan
//     respuestas y filas.
//  2. La app nueva: datos nuevos, cuadre 422, FPB en el servidor,
//     reintento sin duplicar, PUT viejo que conserva, DELETE que anula la
//     deuda y búsqueda en todo el historial.
//
//  Uso (en un directorio TEMPORAL, nunca en el sitio):
//     php facturas_endpoint_test.php <sitio_viejo> <sitio_nuevo>
//  Cada sitio: api.php, endpoints/, lib/ con lib/db.php = db_prueba.php.
// ════════════════════════════════════════════════════════════════════
declare(strict_types=1);
// Solo por consola: si se llega a subir, por la web no hace nada.
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }

[$_, $SITIO_VIEJO, $SITIO_NUEVO] = $argv + [null, null, null];
if (!is_dir((string)$SITIO_VIEJO) || !is_dir((string)$SITIO_NUEVO)) {
    fwrite(STDERR, "uso: php facturas_endpoint_test.php <sitio_viejo> <sitio_nuevo>\n");
    exit(2);
}

$fallos = 0;
$pasadas = 0;
function comprobar(string $nombre, $esperado, $obtenido): void {
    global $fallos, $pasadas;
    if ($esperado === $obtenido) { $pasadas++; return; }
    $fallos++;
    fwrite(STDERR, "  FALLA  $nombre\n         esperado: " . var_export($esperado, true)
                 . "\n         obtenido: " . var_export($obtenido, true) . "\n");
}

/** Base con el esquema de producción ANTES de este cambio. */
function crearBase(string $ruta): PDO {
    @unlink($ruta);
    $pdo = new PDO('sqlite:' . $ruta);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
    $pdo->exec("CREATE TABLE facturas (id INTEGER PRIMARY KEY AUTOINCREMENT, nro_factura TEXT UNIQUE,
        cedula TEXT, cliente TEXT, telefono TEXT, vendedor TEXT, tienda TEXT, fecha TEXT,
        total REAL, creado_en TEXT, eliminado_en TEXT)");
    $pdo->exec("CREATE TABLE factura_equipos (id INTEGER PRIMARY KEY AUTOINCREMENT, factura_id INT, imei TEXT, vendedor TEXT)");
    $pdo->exec("CREATE TABLE factura_items (id INTEGER PRIMARY KEY AUTOINCREMENT, factura_id INT,
        producto_codigo TEXT, cantidad INT, vendedor TEXT)");
    $pdo->exec("CREATE TABLE factura_pagos (id INTEGER PRIMARY KEY AUTOINCREMENT, factura_id INT,
        metodo TEXT, tipo TEXT, financiador TEXT, financiadora TEXT, monto REAL,
        banco_destino TEXT, banco_origen TEXT, referencia TEXT, cedula_pagador TEXT,
        telefono_pagador TEXT, telefono_destino TEXT, fecha_pago TEXT, es_inicial INT,
        conciliado_bdv INT, conciliado_codigo TEXT, conciliado_mensaje TEXT,
        numero_cuotas INT, monto_cuota REAL, tasa_cambio REAL, nombre_lista TEXT)");
    $pdo->exec("CREATE TABLE stock_imei (id INTEGER PRIMARY KEY AUTOINCREMENT, imei TEXT, producto_codigo TEXT,
        vendido INT DEFAULT 0, fecha_venta TEXT, factura_id INT, ubicacion TEXT, eliminado_en TEXT)");
    $pdo->exec("CREATE TABLE productos (id INTEGER PRIMARY KEY AUTOINCREMENT, codigo TEXT, nombre TEXT,
        tienda TEXT, precio_venta REAL, stock_manual INT, eliminado_en TEXT)");
    $pdo->exec("CREATE TABLE cuentas_cobrar (id INTEGER PRIMARY KEY AUTOINCREMENT, cedula TEXT,
        nombre TEXT, telefono TEXT, correo TEXT, monto_total REAL, saldo_favor REAL DEFAULT 0,
        factura_id INT, financiadora TEXT, notas TEXT, creado_en TEXT, eliminado_en TEXT)");
    $pdo->exec("CREATE TABLE cuentas_cobrar_cuotas (id INTEGER PRIMARY KEY AUTOINCREMENT, cuenta_id INT,
        numero INT, monto REAL, fecha TEXT, pagada INT DEFAULT 0, fecha_pago TEXT)");
    $pdo->exec("CREATE TABLE cuentas_cobrar_pagos (id INTEGER PRIMARY KEY AUTOINCREMENT, cuenta_id INT,
        metodo TEXT, monto REAL, fecha TEXT, referencia TEXT, notas TEXT)");
    $pdo->exec("CREATE TABLE configuracion (id INTEGER PRIMARY KEY AUTOINCREMENT, clave TEXT UNIQUE, valor TEXT)");
    $pdo->exec("CREATE TABLE auditoria (id INTEGER PRIMARY KEY AUTOINCREMENT, tabla TEXT, registro_id TEXT,
        accion TEXT, usuario TEXT, datos_antes TEXT, datos_despues TEXT, ip_origen TEXT)");
    $pdo->exec("INSERT INTO productos (codigo, nombre, tienda, precio_venta, stock_manual) VALUES
        ('FORRO', 'Forro', '', 5, 50), ('R13', 'Redmi 13', '', 200, 0), ('TV', 'TV 50', '', 300, 10)");
    $pdo->exec("INSERT INTO stock_imei (imei, producto_codigo, ubicacion) VALUES
        ('351111', 'R13', 'Principal'), ('352222', 'R13', 'Principal'), ('353333', 'R13', 'Principal')");
    return $pdo;
}

function llave(PDO $pdo, string $valor): void {
    $pdo->prepare('INSERT OR REPLACE INTO configuracion (clave, valor) VALUES (?, ?)')
        ->execute(['factura_cuadre_servidor', $valor]);
}

/** Levanta `php -S` para un sitio y devuelve [proceso, puerto]. */
function servidor(string $sitio, string $base, int $puerto): array {
    $env = array_merge(getenv(), ['TL_PRUEBA_SQLITE' => $base]);
    $p = proc_open([PHP_BINARY, '-S', "127.0.0.1:$puerto", '-t', $sitio],
        [1 => ['file', '/dev/null', 'w'], 2 => ['file', '/dev/null', 'w']], $tuberias, $sitio, $env);
    for ($i = 0; $i < 50; $i++) {
        $s = @fsockopen('127.0.0.1', $puerto);
        if ($s) { fclose($s); break; }
        usleep(100000);
    }
    return [$p, $puerto];
}

function http(int $puerto, string $metodo, string $query, ?array $cuerpo = null): array {
    $ctx = stream_context_create(['http' => [
        'method' => $metodo,
        'header' => "Content-Type: application/json\r\n",
        'content' => $cuerpo === null ? '' : json_encode($cuerpo),
        'ignore_errors' => true,
        'timeout' => 20,
    ]]);
    $txt = file_get_contents("http://127.0.0.1:$puerto/api.php?$query", false, $ctx);
    preg_match('#HTTP/\S+ (\d+)#', $http_response_header[0] ?? '', $m);
    return [(int)($m[1] ?? 0), json_decode((string)$txt, true), (string)$txt];
}

/** Filas de una tabla con SOLO las columnas que existían antes del cambio. */
function volcar(PDO $pdo, string $tabla, array $cols): array {
    $filas = $pdo->query("SELECT " . implode(', ', $cols) . " FROM $tabla ORDER BY id")->fetchAll();
    return array_map(static function ($f) {
        unset($f['fecha_venta'], $f['eliminado_en']);   // la hora del reloj
        return $f;
    }, $filas);
}

// ── Lo que manda la 1.0.17 (FacturaModel.toApiMap) ──
function facturaVieja(string $nro, array $pagos, array $items = [], array $equipos = []): array {
    return ['nro_factura' => $nro, 'cedula' => '12345678', 'cliente' => 'Ana Pérez',
        'telefono' => '04141234567', 'vendedor' => 'Luis', 'tienda' => 'Principal',
        'fecha' => '16/10/2026', 'total' => array_sum(array_column($pagos, 'monto')),
        'creador_rol' => 'Vendedor',
        'equipos' => array_map(static fn($i) => ['imei' => $i, 'vendedor' => ''], $equipos),
        'items' => array_map(static fn($c) => ['codigo' => $c, 'vendedor' => ''], $items),
        'pagos' => $pagos];
}
function pagoViejo(string $metodo, float $monto, array $extra = []): array {
    return ['metodo' => $metodo, 'tipo' => 'Contado', 'financiador' => null, 'monto' => $monto,
            'financiadora' => null, 'es_inicial' => false, 'tasa_cambio' => 100.0] + $extra;
}

$secuenciaVieja = static function (int $puerto): array {
    $r = [];
    $r[] = http($puerto, 'POST', 'resource=facturas', facturaVieja('V-1', [pagoViejo('Divisas', 5)], ['FORRO']));
    // La 1.0.17 deja pasar «Diferencia en totales» con Continuar: el
    // servidor no la frena.
    $r[] = http($puerto, 'POST', 'resource=facturas', facturaVieja('V-2',
        [pagoViejo('Pago Móvil', 1000, ['referencia' => '777', 'cedula_pagador' => 'V1'])], ['FORRO'], ['351111']));
    $r[] = http($puerto, 'POST', 'resource=facturas', facturaVieja('V-1', [pagoViejo('Divisas', 5)], ['FORRO']));
    $r[] = http($puerto, 'PUT', 'resource=facturas&id=2', facturaVieja('V-2',
        [pagoViejo('Pago Móvil', 1000, ['referencia' => '777']), pagoViejo('Divisas', 3)], ['FORRO'], ['351111']));
    $r[] = http($puerto, 'GET', 'resource=facturas');
    $r[] = http($puerto, 'GET', 'resource=facturas&id=2');
    $r[] = http($puerto, 'GET', 'resource=facturas&cedula=12345678');
    $r[] = http($puerto, 'DELETE', 'resource=facturas&id=1');
    return array_map(static fn($x) => [$x[0], $x[1]], $r);
};

$tablas = [
    'facturas' => ['id', 'nro_factura', 'cedula', 'cliente', 'telefono', 'vendedor', 'tienda', 'fecha', 'total', 'eliminado_en'],
    'factura_items' => ['id', 'factura_id', 'producto_codigo', 'cantidad', 'vendedor'],
    'factura_equipos' => ['id', 'factura_id', 'imei', 'vendedor'],
    'factura_pagos' => ['id', 'factura_id', 'metodo', 'tipo', 'financiador', 'financiadora', 'monto',
        'referencia', 'cedula_pagador', 'es_inicial', 'tasa_cambio'],
    'stock_imei' => ['id', 'imei', 'vendido', 'factura_id'],
    'productos' => ['id', 'codigo', 'stock_manual'],
    'cuentas_cobrar' => ['id', 'monto_total', 'factura_id'],
];

/** Quita de las respuestas GET las columnas nuevas (la vieja no las tiene). */
function sinColumnasNuevas($v) {
    if (!is_array($v)) return $v;
    foreach (['inicial', 'monto_financiado', 'tasa_bcv', 'clave_idempotencia', 'precio_unitario',
              'moneda', 'monto_usd', 'es_vuelto'] as $k) unset($v[$k]);
    return array_map('sinColumnasNuevas', $v);
}

$PUERTO = 18765;
foreach (['0', '1'] as $valorLlave) {
    echo "== App 1.0.17: backend viejo vs nuevo (llave = $valorLlave) ==\n";
    $resultados = [];
    $volcados = [];
    foreach (['viejo' => $SITIO_VIEJO, 'nuevo' => $SITIO_NUEVO] as $cual => $sitio) {
        $base = "$sitio/prueba_$cual.sqlite";
        $pdo = crearBase($base);
        llave($pdo, $valorLlave);
        [$proc, $puerto] = servidor($sitio, $base, $PUERTO++);
        $resultados[$cual] = $secuenciaVieja($puerto);
        proc_terminate($proc);
        proc_close($proc);
        $pdo = new PDO('sqlite:' . $base);
        $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
        foreach ($tablas as $t => $cols) $volcados[$cual][$t] = volcar($pdo, $t, $cols);
    }
    $nombres = ['POST contado', 'POST que no cuadra', 'POST número repetido', 'PUT', 'GET lista',
                'GET id', 'GET por cédula', 'DELETE'];
    foreach ($nombres as $i => $n) {
        comprobar("$n: mismo código HTTP", $resultados['viejo'][$i][0], $resultados['nuevo'][$i][0]);
        comprobar("$n: misma respuesta", $resultados['viejo'][$i][1], sinColumnasNuevas($resultados['nuevo'][$i][1]));
    }
    comprobar('el POST sigue respondiendo {ok, id}', ['ok' => true, 'id' => 1], $resultados['nuevo'][0][1]);
    comprobar('el que no cuadra se guarda igual (201)', 201, $resultados['nuevo'][1][0]);
    foreach ($tablas as $t => $_) {
        comprobar("tabla $t: mismas filas", $volcados['viejo'][$t], $volcados['nuevo'][$t]);
    }
}

echo "== App nueva ==\n";
$base = "$SITIO_NUEVO/prueba_app_nueva.sqlite";
$pdo = crearBase($base);
[$proc, $p] = servidor($SITIO_NUEVO, $base, $PUERTO++);

function facturaNueva(string $nro, string $clave, array $pagos, array $lineas, bool $fpb = false, ?array $bloqueFpb = null): array {
    $equipos = []; $items = [];
    foreach ($lineas as $l) {
        if ($l['tipo'] === 'equipo') $equipos[] = ['imei' => $l['ref'], 'vendedor' => '', 'precio_unitario' => $l['precio_divisa']];
        else $items[] = ['codigo' => $l['ref'], 'vendedor' => '', 'precio_unitario' => $l['precio_divisa']];
    }
    $f = ['nro_factura' => $nro, 'cedula' => '9.876.543', 'cliente' => 'José Muñoz', 'telefono' => '0424',
        'vendedor' => 'Luis', 'tienda' => 'Principal', 'fecha' => '16/10/2026',
        'total' => 0, 'creador_rol' => 'Vendedor', 'equipos' => $equipos, 'items' => $items,
        'pagos' => $pagos, 'clave_idempotencia' => $clave, 'tasa_bcv' => 100,
        'inicial' => 0, 'monto_financiado' => 0,
        'cuadre' => ['version' => 1, 'tasa_bcv' => 100, 'fpb' => $fpb, 'lineas' => $lineas]];
    if ($bloqueFpb !== null) $f['fpb'] = $bloqueFpb;
    return $f;
}
$forro = ['ref' => 'FORRO', 'tipo' => 'item', 'financiada' => false, 'precio_divisa' => 5, 'precio_bcv' => 6];
$tel = static fn(string $imei, ?float $inicial) => ['ref' => $imei, 'tipo' => 'equipo', 'financiada' => true,
    'precio_divisa' => 200, 'precio_financiadora' => 260] + ($inicial === null ? [] : ['inicial' => $inicial]);
$pg = static fn(string $m, float $monto, array $x = []) => ['metodo' => $m, 'tipo' => 'Contado', 'monto' => $monto,
    'es_inicial' => false, 'tasa_cambio' => 100, 'moneda' => (in_array($m, ['Pago Móvil', 'Efectivo Bs'], true) ? 'BS' : 'USD')] + $x;

// Llave apagada: guarda los datos nuevos, no valida, no crea la deuda.
llave($pdo, '0');
[$c, $j] = http($p, 'POST', 'resource=facturas', facturaNueva('N-1', 'clave-n1-0000000001',
    [$pg('Divisas', 5)], [$tel('351111', 50), $forro], false));
comprobar('llave apagada: no valida (falta la inicial y se guarda)', 201, $c);
$f = $pdo->query("SELECT * FROM facturas WHERE nro_factura = 'N-1'")->fetch();
comprobar('guarda la clave y la tasa', ['clave-n1-0000000001', 100.0], [$f['clave_idempotencia'], (float)$f['tasa_bcv']]);
$precios = $pdo->query('SELECT precio_unitario FROM factura_items WHERE factura_id = ' . (int)$f['id'])->fetchAll(PDO::FETCH_COLUMN);
comprobar('guarda el precio por línea', [5.0], array_map('floatval', $precios));
[$c, $j] = http($p, 'POST', 'resource=facturas', facturaNueva('N-1b', 'clave-n1b-000000001',
    [$pg('Divisas', 100)], [['ref' => 'TV', 'tipo' => 'item', 'financiada' => false, 'precio_divisa' => 300]], true,
    ['deuda' => 200, 'cuotas' => []]));
comprobar('llave apagada: la deuda FPB la crea la app (el servidor no responde cxc)', false, isset($j['cxc']));

// Llave encendida.
llave($pdo, '1');
[$c, $j] = http($p, 'POST', 'resource=facturas', facturaNueva('N-2', 'clave-n2-0000000001',
    [$pg('Divisas', 50)], [$tel('352222', 50), $forro]));
comprobar('no cuadra: 422', 422, $c);
comprobar('con ok:false y el motivo', [false, 'Falta cobrar $5.00 o Bs 600.00 (contado + inicial).'], [$j['ok'] ?? null, $j['error'] ?? null]);
comprobar('y no se guardó', 0, (int)$pdo->query("SELECT COUNT(*) FROM facturas WHERE nro_factura = 'N-2'")->fetchColumn());

[$c, $j] = http($p, 'POST', 'resource=facturas', facturaNueva('N-2', 'clave-n2-0000000001',
    [$pg('Divisas', 50), $pg('Pago Móvil', 1000), $pg('Efectivo Bs', 400, ['es_vuelto' => true])], [$tel('352222', 50), $forro]));
comprobar('mixto con vuelto en efectivo Bs: 201', 201, $c);
$idN2 = (int)($j['id'] ?? 0);
$f = $pdo->query("SELECT * FROM facturas WHERE id = $idN2")->fetch();
comprobar('inicial y financiado calculados por el servidor', [50.0, 210.0], [(float)$f['inicial'], (float)$f['monto_financiado']]);
$pagos = $pdo->query("SELECT metodo, monto, moneda, es_vuelto FROM factura_pagos WHERE factura_id = $idN2 ORDER BY id")->fetchAll();
comprobar('el vuelto queda negativo y marcado', ['Efectivo Bs', -400.0, 'BS', 1],
    [$pagos[2]['metodo'], (float)$pagos[2]['monto'], $pagos[2]['moneda'], (int)$pagos[2]['es_vuelto']]);

[$c, $j] = http($p, 'POST', 'resource=facturas', facturaNueva('N-2-otro-numero', 'clave-n2-0000000001',
    [$pg('Divisas', 50), $pg('Pago Móvil', 1000), $pg('Efectivo Bs', 400, ['es_vuelto' => true])], [$tel('352222', 50), $forro]));
comprobar('reintento con la misma clave: la misma factura', [200, $idN2, true], [$c, $j['id'] ?? null, $j['ya_existia'] ?? null]);
comprobar('sin duplicar', 1, (int)$pdo->query("SELECT COUNT(*) FROM facturas WHERE clave_idempotencia = 'clave-n2-0000000001'")->fetchColumn());

[$c, $j] = http($p, 'POST', 'resource=facturas', facturaNueva('N-3', 'clave-n3-0000000001',
    [$pg('Pago Móvil', 500, ['es_vuelto' => true]), $pg('Divisas', 10)], [$forro]));
comprobar('vuelto por Pago Móvil: 422', [422, 'El vuelto solo se da en efectivo o divisas (no por Pago Móvil).'], [$c, $j['error'] ?? null]);

$tv = ['ref' => 'TV', 'tipo' => 'item', 'financiada' => false, 'precio_divisa' => 999];   // la app manda otro precio
[$c, $j] = http($p, 'POST', 'resource=facturas', facturaNueva('N-4', 'clave-n4-0000000001',
    [$pg('Divisas', 100)], [$tv], true, ['deuda' => 200, 'cuotas' => [
        ['numero' => 1, 'monto' => 100, 'fecha' => '2026-11-16'], ['numero' => 2, 'monto' => 100, 'fecha' => '2026-12-16']]]));
comprobar('FPB con pago parcial: 201', 201, $c);
$idN4 = (int)($j['id'] ?? 0);
comprobar('el servidor crea la deuda y la devuelve', [true, 200.0], [$j['cxc']['creada'] ?? null, (float)($j['cxc']['monto'] ?? 0)]);
$cta = $pdo->query("SELECT * FROM cuentas_cobrar WHERE factura_id = $idN4")->fetch();
comprobar('enlazada a la factura con número y tienda', ['N-4', 'Principal'], [$cta['nro_factura'], $cta['tienda']]);
comprobar('con sus cuotas', 2, (int)$pdo->query('SELECT COUNT(*) FROM cuentas_cobrar_cuotas WHERE cuenta_id = ' . (int)$cta['id'])->fetchColumn());
[$c, $j] = http($p, 'POST', 'resource=facturas', facturaNueva('N-4', 'clave-n4-0000000001',
    [$pg('Divisas', 100)], [$tv], true, ['deuda' => 200]));
comprobar('reintento FPB: la misma cuenta, sin duplicar', [false, (int)$cta['id']], [$j['cxc']['creada'] ?? null, $j['cxc']['id'] ?? null]);
[$c, $j] = http($p, 'POST', 'resource=facturas', facturaNueva('N-5', 'clave-n5-0000000001',
    [$pg('Divisas', 350)], [['ref' => 'TV', 'tipo' => 'item', 'financiada' => false, 'precio_divisa' => 300]], true));
comprobar('FPB que paga de más: 422', 422, $c);

echo "== La 1.0.17 edita una factura de la app nueva ==\n";
$vieja = facturaVieja('N-2', [
    pagoViejo('Divisas', 50), pagoViejo('Pago Móvil', 1000), pagoViejo('Efectivo Bs', -400)], ['FORRO'], ['352222']);
[$c, $j] = http($p, 'PUT', "resource=facturas&id=$idN2", $vieja);
comprobar('PUT viejo: ok', [200, ['ok' => true]], [$c, $j]);
$pagos = $pdo->query("SELECT metodo, monto, moneda, es_vuelto FROM factura_pagos WHERE factura_id = $idN2 ORDER BY id")->fetchAll();
comprobar('conserva la moneda de cada pago', ['USD', 'BS', 'BS'], array_column($pagos, 'moneda'));
comprobar('el vuelto sigue marcado', 1, (int)$pagos[2]['es_vuelto']);
$f = $pdo->query("SELECT * FROM facturas WHERE id = $idN2")->fetch();
comprobar('conserva inicial, financiado y clave', [50.0, 210.0, 'clave-n2-0000000001'],
    [(float)$f['inicial'], (float)$f['monto_financiado'], $f['clave_idempotencia']]);
comprobar('conserva el precio de las líneas', [5.0, 200.0], [
    (float)$pdo->query("SELECT precio_unitario FROM factura_items WHERE factura_id = $idN2")->fetchColumn(),
    (float)$pdo->query("SELECT precio_unitario FROM factura_equipos WHERE factura_id = $idN2")->fetchColumn()]);

echo "== Eliminar la factura anula su deuda FPB ==\n";
[$c, $j] = http($p, 'DELETE', "resource=facturas&id=$idN4");
comprobar('DELETE ok y dice qué deuda anuló', [200, [(int)$cta['id']]], [$c, $j['cuentas_cobrar']['eliminadas'] ?? null]);
comprobar('la deuda quedó anulada', 1, (int)$pdo->query('SELECT COUNT(*) FROM cuentas_cobrar WHERE eliminado_en IS NOT NULL AND id = ' . (int)$cta['id'])->fetchColumn());

echo "== Búsqueda en todo el historial ==\n";
for ($i = 0; $i < 3; $i++) {
    $pdo->exec("INSERT INTO facturas (nro_factura, cedula, cliente, vendedor, tienda, fecha, total)
                VALUES ('H-$i', '1111', 'Otro', 'X', 'Sucursal', '01/01/2020', 1)");
}
[$c, $j] = http($p, 'GET', 'resource=facturas&q=' . urlencode('V-9.876.543'));
// (N-2 ya no: la 1.0.17 la editó con otra cédula; N-4 está eliminada.)
comprobar('por cédula escrita distinto', ['N-1b', 'N-1'], array_column($j, 'nro_factura'));
[$c, $j] = http($p, 'GET', 'resource=facturas&q=H-&tienda=Sucursal');
comprobar('respeta el filtro de tienda', 3, count($j));
comprobar('trae pagos e items hidratados', true, isset($j[0]['pagos'], $j[0]['items']));

proc_terminate($proc);
proc_close($proc);

echo "\n" . ($fallos === 0 ? "OK" : "FALLAS: $fallos") . " — $pasadas comprobaciones pasadas\n";
exit($fallos === 0 ? 0 : 1);
