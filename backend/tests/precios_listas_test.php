<?php
// ============================================================================
//  precios_listas_test.php — Listas de precios desde el costo (Tecno Líder)
//
//      php backend/tests/precios_listas_test.php
//
//  SQLite en memoria (necesita pdo_sqlite y mbstring); nunca toca una base
//  real. Portado de Brizuela (backen/tests/precios_auto_test.php y
//  listas_auto_test.php) y adaptado a las listas de Tecno Líder, que viven
//  en UNA fila con `columnas` e `items` en JSON. Casos propios:
//    · con los interruptores en 0 o las listas en manual: 0 cambios;
//    · una app vieja (1.0.17) no borra los campos nuevos ni `es_manual`.
// ============================================================================

declare(strict_types=1);

require __DIR__ . '/../lib/precios_listas.php';

$fallos = 0;
$pasadas = 0;
function comprobar(string $nombre, $esperado, $obtenido): void {
    global $fallos, $pasadas;
    if ($esperado === $obtenido) { $pasadas++; return; }
    $fallos++;
    fwrite(STDERR, "  FALLA  $nombre\n         esperado: " . var_export($esperado, true)
                 . "\n         obtenido: " . var_export($obtenido, true) . "\n");
}

const BCV = 876.80;

/** Columnas de una lista como las manda la app: nombre + fórmula JSON. */
function cols(array $nombres): string {
    $out = [];
    foreach ($nombres as $n => $f) {
        if (is_int($n)) { $n = $f; $f = ['modo' => 'manual']; }
        $out[] = ['nombre' => $n, 'formula' => json_encode($f)];
    }
    return json_encode($out);
}

/** Ítems: [codigo => [columna => precio | [precio, es_manual]]] */
function items(array $porCodigo): string {
    $out = [];
    foreach ($porCodigo as $c => $vals) {
        $valores = [];
        foreach ($vals as $col => $p) {
            $v = ['columna_nombre' => $col, 'precio' => is_array($p) ? $p[0] : $p];
            if (is_array($p)) $v['es_manual'] = $p[1];
            $valores[] = $v;
        }
        $out[] = ['producto_codigo' => $c, 'stock_disponible' => 1, 'valores' => $valores];
    }
    return json_encode($out);
}

function base(): PDO {
    $pdo = new PDO('sqlite::memory:');
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->exec("CREATE TABLE configuracion (id INTEGER PRIMARY KEY AUTOINCREMENT, clave TEXT UNIQUE, valor TEXT)");
    $pdo->exec("INSERT INTO configuracion (clave, valor) VALUES ('cfg_categorias_productos',
        '[{\"nombre\":\"Telefono\",\"usa_imei\":true},{\"nombre\":\"Accesorio\",\"usa_imei\":false}]')");
    $pdo->exec("CREATE TABLE tasa_bcv (id INTEGER PRIMARY KEY AUTOINCREMENT, valor REAL, fuente TEXT,
        es_actual INT, fecha TEXT DEFAULT CURRENT_TIMESTAMP)");
    $pdo->exec("INSERT INTO tasa_bcv (valor, es_actual) VALUES (800, 0), (" . BCV . ", 1)");
    $pdo->exec("CREATE TABLE usuarios (id INTEGER PRIMARY KEY, correo TEXT, rol TEXT, activo INT, eliminado_en TEXT)");
    $pdo->exec("INSERT INTO usuarios VALUES (1,'dueno@x.com','Dueño',1,NULL),(2,'vende@x.com','Vendedor',1,NULL),
        (3,'viejo@x.com','Administrador',0,NULL),(4,'gerente@x.com','Gerente',1,NULL)");
    $pdo->exec("CREATE TABLE productos (id INTEGER PRIMARY KEY AUTOINCREMENT, codigo TEXT, nombre TEXT,
        categoria TEXT, marca TEXT, precio_costo REAL, precio_venta REAL, stock_manual INT DEFAULT 0,
        producto_padre_codigo TEXT DEFAULT '', tienda TEXT DEFAULT '', eliminado_en TEXT)");
    $pdo->exec("INSERT INTO productos (codigo, nombre, categoria, marca, precio_costo, precio_venta, stock_manual, tienda) VALUES
        ('RED13', 'Redmi 13', 'Telefono',  'Xiaomi', 100, 125, 0, 'Principal'),
        ('RED13', 'Redmi 13', 'Telefono',  'Xiaomi', 90,  125, 0, 'Sucursal'),
        ('FORRO', 'Forro',    'Accesorio', '',       5,   9,   10, 'Principal'),
        ('SIM',   'Linea',    'Linea',     '',       2,   3,   50, 'Principal')");
    $pdo->exec("CREATE TABLE stock_imei (id INTEGER PRIMARY KEY AUTOINCREMENT, imei TEXT, producto_codigo TEXT,
        ubicacion TEXT, vendido INT DEFAULT 0, eliminado_en TEXT)");
    $pdo->exec("INSERT INTO stock_imei (imei, producto_codigo, vendido) VALUES ('1','RED13',0),('2','RED13',1)");
    $pdo->exec("CREATE TABLE listas_precios (id INTEGER PRIMARY KEY, nombre TEXT, fecha_creacion TEXT,
        categoria TEXT, marca_filtro TEXT, es_en_bolivares INT, tasa_del_dia REAL, porcentaje_adicional REAL,
        es_financiamiento INT, financiadora TEXT, porcentaje_inicial REAL, numero_cuotas INT,
        porcentaje_comision_weppa REAL, porcentaje_recargo_cuotas REAL, columnas TEXT, items TEXT,
        creado_en TEXT, eliminado_en TEXT,
        tiene_cuotas INT NOT NULL DEFAULT 1, actualizado_en TEXT,
        monto_adicional_dolares REAL NOT NULL DEFAULT 0, modo_precios TEXT NOT NULL DEFAULT 'manual',
        pct_sobre_costo REAL NOT NULL DEFAULT 0, tasa_fija INT NOT NULL DEFAULT 0,
        tasa_bs REAL NOT NULL DEFAULT 0, redondear_arriba INT NOT NULL DEFAULT 0, reglas_pct TEXT,
        lista_base_id INT NOT NULL DEFAULT 0)");
    $L = [
        // id, nombre, categoria, bs, tasa, % venta (app), fin, financiadora, columnas, items
        [58, 'Equipos Divisas', 'Telefono', 0, 1, 25, 0, null, cols(['Precio']),
            items(['RED13' => ['Precio' => [77, 1]]])],
        [65, 'Equipos Bs', 'Telefono', 1, 798.33, 25, 0, null, cols(['Precio']),
            items(['RED13' => ['Precio' => 125000]])],
        [59, 'Cashea', 'Telefono', 0, 1, 40, 1, 'Cashea', cols(['Precio']),
            json_encode([['producto_codigo' => 'RED13', 'stock_disponible' => 1, 'valores' => [
                ['columna_nombre' => 'Precio', 'precio' => 175],
                ['columna_nombre' => '__inicial_manual__', 'precio' => 50],
                ['columna_nombre' => '__pct_inicial__', 'precio' => 30]]]])],
        [66, 'Accesorios Divisas', 'Accesorio', 0, 1, 20, 0, null,
            cols(['Precio', 'Mayor' => ['modo' => 'porcentaje', 'valor' => -10]]),
            items(['FORRO' => ['Precio' => 10.8, 'Mayor' => 9.72]])],
        [69, 'Accesorios Bs', 'Accesorio', 1, 798.33, 25, 0, null, cols(['Precio']),
            items(['FORRO' => ['Precio' => 8980]])],
    ];
    foreach ($L as [$id, $n, $cat, $bs, $tasa, $pct, $fin, $fd, $c, $i]) {
        $pdo->prepare("INSERT INTO listas_precios (id, nombre, categoria, marca_filtro, es_en_bolivares,
            tasa_del_dia, porcentaje_adicional, es_financiamiento, financiadora, columnas, items)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)")
            ->execute([$id, $n, $cat, 'Todas', $bs, $tasa, $pct, $fin, $fd, $c, $i]);
    }
    return $pdo;
}

function fila(PDO $pdo, int $id): array {
    $st = $pdo->prepare('SELECT * FROM listas_precios WHERE id = ?');
    $st->execute([$id]);
    return $st->fetch(PDO::FETCH_ASSOC);
}
function precio(PDO $pdo, int $lista, string $c, string $col = 'Precio'): ?float {
    foreach (plJson(fila($pdo, $lista)['items']) as $it) {
        if ($it['producto_codigo'] !== $c) continue;
        foreach ($it['valores'] as $v) if ($v['columna_nombre'] === $col) return (float)$v['precio'];
    }
    return null;
}
function manual(PDO $pdo, int $lista, string $c, string $col = 'Precio'): ?int {
    foreach (plJson(fila($pdo, $lista)['items']) as $it) {
        if ($it['producto_codigo'] !== $c) continue;
        foreach ($it['valores'] as $v) {
            if ($v['columna_nombre'] === $col) return array_key_exists('es_manual', $v) ? (int)$v['es_manual'] : null;
        }
    }
    return null;
}
function enLista(PDO $pdo, int $lista, string $c): bool {
    foreach (plJson(fila($pdo, $lista)['items']) as $it) if ($it['producto_codigo'] === $c) return true;
    return false;
}
function foto(PDO $pdo): string {
    return json_encode([
        $pdo->query('SELECT * FROM listas_precios ORDER BY id')->fetchAll(PDO::FETCH_ASSOC),
        $pdo->query('SELECT codigo, tienda, precio_venta FROM productos ORDER BY id')->fetchAll(PDO::FETCH_ASSOC),
    ]);
}
function costo(PDO $pdo, int $id, array $cfg = []): void {
    $sets = ["modo_precios = 'costo'"];
    foreach ($cfg as $k => $v) $sets[] = "$k = " . (is_string($v) ? $pdo->quote($v) : $v);
    $pdo->exec('UPDATE listas_precios SET ' . implode(', ', $sets) . " WHERE id = $id");
}
function venta(PDO $pdo, string $c): float {
    return (float)$pdo->query("SELECT MAX(precio_venta) FROM productos WHERE codigo = " . $pdo->quote($c))->fetchColumn();
}

// ════ 1. APAGADO: al desplegar no cambia ningún precio ════
$pdo = base();
$antes = foto($pdo);
comprobar('interruptor ausente = apagado', false, plInterruptor($pdo, 'precios_auto_activo'));
plEngancheProducto($pdo, 'RED13');
plEngancheLista($pdo, 58);
plEngancheTasaBcv($pdo, 999);
$b = plEnganchePrepararProducto($pdo, ['precio_costo' => 1, 'precio_venta' => 7], 'RED13');
comprobar('apagado: preparar producto no toca la venta', 7, $b['precio_venta']);
comprobar('apagado: los enganches no cambian nada', $antes, foto($pdo));
comprobar('todas en manual: recalcular todo = 0 listas', [], plRecalcularTodas($pdo));
comprobar('todas en manual: nada cambió', $antes, foto($pdo));

// Interruptores ENCENDIDOS pero las listas en manual: tampoco cambia nada.
foreach (PL_INTERRUPTORES as $k) plPonerInterruptor($pdo, $k, true);
comprobar('interruptor encendido', true, plInterruptor($pdo, 'precios_auto_activo'));
$antes = foto($pdo);
plEngancheProducto($pdo, 'RED13');
plEngancheProducto($pdo, 'FORRO');
plEngancheLista($pdo, 58);
plEngancheTasaBcv($pdo, 999);
comprobar('encendido + listas en manual: 0 cambios', $antes, foto($pdo));
comprobar('recalcular una lista manual no la toca', 0, plRecalcularLista($pdo, 58)['precios']);

// ════ 2. Fórmulas (como Brizuela, con % sobre costo propio) ════
$pdo = base();
costo($pdo, 58, ['pct_sobre_costo' => 8]);
costo($pdo, 59, ['pct_sobre_costo' => 40]);
costo($pdo, 65);
costo($pdo, 66, ['pct_sobre_costo' => 20]);
costo($pdo, 69);
$listas = plListas($pdo);
$porNombre = [];
foreach ($listas as $l) $porNombre[$l['nombre']] = $l;
comprobar('Divisas: costo 100 + 8 %', 108.0, plPrecioUsd($porNombre['Equipos Divisas'], 100));
comprobar('el % de la app (porcentaje_adicional, sobre venta) no se usa', 108.0,
    plPrecioUsd($porNombre['Equipos Divisas'] + ['porcentaje_adicional' => 99], 100));
$v = plValores($porNombre['Cashea'], $listas, 100, BCV, ['categoria' => 'Telefono', 'marca' => 'X', 'nombre' => 'X']);
comprobar('financiadora: % sobre el precio de venta (108 × 1,40)', 151.2, $v['precio']);
$v = plValores($porNombre['Cashea'], $listas, 100, BCV, ['categoria' => 'Drones', 'marca' => 'X']);
comprobar('financiadora sin lista Divisas: sobre el costo', 140.0, $v['precio']);
comprobar('Equipos Bs se empareja con Equipos Divisas', 58, (int)plParDivisas($porNombre['Equipos Bs'], $listas)['id']);
comprobar('una lista en $ no tiene par', null, plParDivisas($porNombre['Cashea'], $listas));
$sinCosto = $listas;
foreach ($sinCosto as &$l) if ((int)$l['id'] === 58) $l['modo_precios'] = 'manual';
unset($l);
comprobar('una Divisas en manual no es par de nadie', null, plParDivisas($porNombre['Equipos Bs'], $sinCosto));
$v = plValores($porNombre['Equipos Bs'], $listas, 100, BCV);
comprobar('Bs sin tasa manual: 108 × BCV', plRedondear2(108 * BCV), $v['precio']);
comprobar('y $BCV = precio Divisas', 108.0, $v['bcv']);
comprobar('venta de un teléfono = lista Divisas', 108.0,
    plVentaDe(['categoria' => 'Telefono', 'marca' => 'Xiaomi', 'precio_costo' => 100], $listas));
comprobar('sin lista Divisas: null', null, plVentaDe(['categoria' => 'Linea', 'marca' => '', 'precio_costo' => 2], $listas));

// Tasa manual de la lista Divisas y tasa fija de la lista Bs.
costo($pdo, 58, ['pct_sobre_costo' => 8, 'tasa_bs' => 950]);
$listas = plListas($pdo);
foreach ($listas as $l) $porNombre[$l['nombre']] = $l;
$v = plValores($porNombre['Equipos Bs'], $listas, 100, BCV);
comprobar('Bs = 108 × 950 (tasa manual de su Divisas)', 102600.0, $v['precio']);
comprobar('$BCV = 102.600 ÷ 876,80', 117.02, $v['bcv']);
$fija = $porNombre['Equipos Bs'];
$fija['tasa_fija'] = 1; $fija['tasa_del_dia'] = 1000;
comprobar('tasa fija de la lista Bs manda', 108000.0, plValores($fija, $listas, 100, BCV)['precio']);

// ════ 3. Recalcular: costo = el MAYOR de las tiendas; columnas con fórmula y virtuales ════
$pdo = base();
costo($pdo, 58, ['pct_sobre_costo' => 8]);
$inf = plRecalcularLista($pdo, 58);
comprobar('RED13: el mayor costo de sus filas (100, no 90) + 8 %', 108.0, precio($pdo, 58, 'RED13'));
comprobar('pisa el 77 manual y le quita la marca', 0, manual($pdo, 58, 'RED13'));
comprobar('informe: 1 precio', 1, $inf['precios']);
comprobar('la tasa y los demás campos de la lista no cambian', 25.0, (float)fila($pdo, 58)['porcentaje_adicional']);
comprobar('segunda pasada no cambia nada', 0, plRecalcularLista($pdo, 58)['precios']);

costo($pdo, 59, ['pct_sobre_costo' => 40]);
plRecalcularLista($pdo, 59);
comprobar('Cashea: 108 + 40 % = 151,20', 151.2, precio($pdo, 59, 'RED13'));
comprobar('inicial fijada a mano se borra', null, precio($pdo, 59, 'RED13', '__inicial_manual__'));
comprobar('el % de inicial propio se conserva', 30.0, precio($pdo, 59, 'RED13', '__pct_inicial__'));

costo($pdo, 66, ['pct_sobre_costo' => 20]);
plRecalcularLista($pdo, 66);
comprobar('Accesorios: 5 + 20 %', 6.0, precio($pdo, 66, 'FORRO'));
comprobar('la columna con fórmula de la app no la toca el servidor', 9.72, precio($pdo, 66, 'FORRO', 'Mayor'));

costo($pdo, 65);
plRecalcularLista($pdo, 65);
comprobar('Equipos Bs: columna $BCV creada', 108.0, precio($pdo, 65, 'RED13', '$BCV'));
comprobar('Equipos Bs: 108 × BCV', plRedondear2(108 * BCV), precio($pdo, 65, 'RED13'));
comprobar('Equipos Bs: muestra la tasa con la que quedó', BCV, (float)fila($pdo, 65)['tasa_del_dia']);
$colsBs = plColumnas(plJson(fila($pdo, 65)['columnas']))[0];
comprobar('$BCV queda después de Precio', ['Precio', '$BCV'], $colsBs);

// Un producto sin costo conserva su precio.
$pdo->exec("INSERT INTO productos (codigo, nombre, categoria, marca, precio_costo, precio_venta, stock_manual)
    VALUES ('SINC', 'Sin costo', 'Accesorio', '', 0, 4, 1)");
$f = fila($pdo, 66);
$it = plJson($f['items']);
$it[] = ['producto_codigo' => 'SINC', 'stock_disponible' => 1, 'valores' => [['columna_nombre' => 'Precio', 'precio' => 4]]];
$pdo->prepare('UPDATE listas_precios SET items = ? WHERE id = 66')->execute([json_encode($it)]);
plRecalcularLista($pdo, 66);
comprobar('sin costo: conserva su precio', 4.0, precio($pdo, 66, 'SINC'));

// Producto de otra categoría agregado a mano: se queda y se le pone precio.
$f = fila($pdo, 58);
$it = plJson($f['items']);
$it[] = ['producto_codigo' => 'FORRO', 'stock_disponible' => 1, 'valores' => [['columna_nombre' => 'Precio', 'precio' => 1]]];
$it[] = ['producto_codigo' => 'BORRADO', 'stock_disponible' => 1, 'valores' => [['columna_nombre' => 'Precio', 'precio' => 3]]];
$pdo->prepare('UPDATE listas_precios SET items = ? WHERE id = 58')->execute([json_encode($it)]);
plRecalcularLista($pdo, 58);
comprobar('el forro sigue en Equipos Divisas', true, enLista($pdo, 58, 'FORRO'));
comprobar('y con el precio de la lista: 5 + 8 %', 5.4, precio($pdo, 58, 'FORRO'));
comprobar('un producto que ya no está en el catálogo no se saca', 3.0, precio($pdo, 58, 'BORRADO'));

// ════ 4. Altas automáticas (listas_auto_agregar) ════
$pdo = base();
costo($pdo, 66, ['pct_sobre_costo' => 20]);
$pdo->exec("INSERT INTO productos (codigo, nombre, categoria, marca, precio_costo, precio_venta, stock_manual) VALUES
    ('CARG', 'Cargador', 'Accesorio', '', 4, 0, 3),
    ('AGOT', 'Agotado', 'Accesorio', '', 4, 0, 0)");
$pdo->exec("INSERT INTO productos (codigo, nombre, categoria, marca, precio_costo, precio_venta, stock_manual, producto_padre_codigo)
    VALUES ('CARG-B', 'Cargador blanco', 'Accesorio', '', 4, 0, 5, 'CARG')");
plRecalcularLista($pdo, 66);
comprobar('sin listas_auto_agregar no entra nada', false, enLista($pdo, 66, 'CARG'));
plPonerInterruptor($pdo, 'listas_auto_agregar', true);
$inf = plRecalcularLista($pdo, 66);
comprobar('con listas_auto_agregar entra el que tiene stock', 4.8, precio($pdo, 66, 'CARG'));
comprobar('el agotado no entra', false, enLista($pdo, 66, 'AGOT'));
comprobar('el subproducto no entra', false, enLista($pdo, 66, 'CARG-B'));
comprobar('informe: 1 agregado', 1, $inf['agregados']);
comprobar('nunca entra en una lista manual', false, enLista($pdo, 69, 'CARG'));
$st = json_decode(json_encode(plJson(fila($pdo, 66)['items'])), true);
$stockCarg = null;
foreach ($st as $x) if ($x['producto_codigo'] === 'CARG') $stockCarg = $x['stock_disponible'];
comprobar('stock = el suyo más el de sus variantes', 8, $stockCarg);

// Teléfono: el stock son los IMEI no vendidos.
costo($pdo, 58, ['pct_sobre_costo' => 8]);
$pdo->exec("INSERT INTO productos (codigo, nombre, categoria, marca, precio_costo, precio_venta, stock_manual)
    VALUES ('A15', 'Galaxy A15', 'Telefono', 'Samsung', 120, 0, 9)");
plPonerInterruptor($pdo, 'precios_auto_activo', true);
plEngancheProducto($pdo, 'A15');
comprobar('teléfono sin IMEI cargados no entra (aunque tenga stock_manual)', false, enLista($pdo, 58, 'A15'));
$pdo->exec("INSERT INTO stock_imei (imei, producto_codigo) VALUES ('9','A15')");
plEngancheProducto($pdo, 'A15');
comprobar('con un IMEI disponible entra: 120 + 8 %', 129.6, precio($pdo, 58, 'A15'));

// ════ 5. Enganches encendidos ════
$pdo = base();
plPonerInterruptor($pdo, 'precios_auto_activo', true);
costo($pdo, 58, ['pct_sobre_costo' => 8]);
costo($pdo, 65);
$pdo->exec("UPDATE productos SET precio_costo = 120 WHERE codigo = 'RED13' AND tienda = 'Principal'");
plEngancheProducto($pdo, 'RED13');
comprobar('producto: su lista Divisas en costo: 129,60', 129.6, precio($pdo, 58, 'RED13'));
comprobar('producto: su lista Bs en costo', plRedondear2(129.6 * BCV), precio($pdo, 65, 'RED13'));
comprobar('producto: Cashea (manual) no se toca', 175.0, precio($pdo, 59, 'RED13'));
comprobar('sin precio_venta_desde_lista la venta no cambia', 125.0, venta($pdo, 'RED13'));
plPonerInterruptor($pdo, 'precio_venta_desde_lista', true);
plEngancheProducto($pdo, 'RED13');
comprobar('con precio_venta_desde_lista: venta = lista Divisas', 129.6, venta($pdo, 'RED13'));
$b = plEnganchePrepararProducto($pdo, ['precio_costo' => 50, 'categoria' => 'Telefono', 'marca' => 'X', 'precio_venta' => 1]);
comprobar('POST: la venta la pone la lista (50 + 8 %)', 54.0, $b['precio_venta']);
$b = plEnganchePrepararProducto($pdo, ['precio_venta' => 3.5], 'SIM');
comprobar('categoría sin lista en costo: se respeta', 3.5, $b['precio_venta']);

// Guardar la Divisas mueve sus dependientes en costo.
$pdo->exec('UPDATE listas_precios SET tasa_bs = 1000 WHERE id = 58');
plEngancheLista($pdo, 58);
comprobar('lista: Equipos Bs con la tasa manual nueva: 129,60 × 1000', 129600.0, precio($pdo, 65, 'RED13'));
// Tasa BCV nueva.
$cambiadas = plAplicarTasaBcv($pdo, 900);
comprobar('tasa BCV: la lista Bs con tasa manual no cambia de precio', 129600.0, precio($pdo, 65, 'RED13'));
comprobar('pero su $BCV sí: 129.600 ÷ 900', 144.0, precio($pdo, 65, 'RED13', '$BCV'));
comprobar('una lista Bs cambió', 1, $cambiadas);
$pdo->exec('UPDATE listas_precios SET tasa_bs = 0 WHERE id = 58');
plEngancheTasaBcv($pdo, 910);
comprobar('sin tasa manual la lista Bs sigue la BCV', plRedondear2(129.6 * 910), precio($pdo, 65, 'RED13'));
comprobar('la lista Bs manual (Accesorios Bs) no se toca', 8980.0, precio($pdo, 69, 'FORRO'));

// ════ 6. % especial por tipo de producto y redondeo (Brizuela 1.0.70) ════
$pdo = base();
$pdo->exec("INSERT INTO productos (codigo, nombre, categoria, marca, precio_costo, precio_venta, stock_manual) VALUES
    ('CORN', 'Corneta JBL Go 3', 'Accesorio', 'JBL', 13.15, 0, 4),
    ('VID',  'Vidrio Templado iPhone 14', 'Accesorio', '', 1.5, 0, 30),
    ('IPH',  'iPhone 15 128GB', 'Telefono', 'Apple', 700, 0, 0)");
$f = fila($pdo, 66);
$it = plJson($f['items']);
foreach (['CORN', 'VID'] as $c) $it[] = ['producto_codigo' => $c, 'stock_disponible' => 1, 'valores' => []];
$pdo->prepare('UPDATE listas_precios SET items = ? WHERE id = 66')->execute([json_encode($it)]);
$it = plJson(fila($pdo, 58)['items']);
$it[] = ['producto_codigo' => 'IPH', 'stock_disponible' => 1, 'valores' => []];
$pdo->prepare('UPDATE listas_precios SET items = ? WHERE id = 58')->execute([json_encode($it)]);
costo($pdo, 66, ['pct_sobre_costo' => 70, 'reglas_pct' => json_encode([
    ['nombre' => 'Cornetas', 'palabras' => ['corneta', 'parlante'], 'marca' => '', 'pct' => 100],
    ['nombre' => 'Vidrios', 'palabras' => 'VIDRIO, Templado', 'marca' => '', 'pct' => 150]])]);
costo($pdo, 58, ['pct_sobre_costo' => 8, 'reglas_pct' => json_encode([
    ['nombre' => 'iPhone', 'palabras' => [], 'marca' => 'apple', 'pct' => 12]])]);
plRecalcularTodas($pdo);
comprobar('accesorio sin regla: el % de la lista (5 + 70 %)', 8.5, precio($pdo, 66, 'FORRO'));
comprobar('corneta por palabra: 13,15 + 100 %', 26.3, precio($pdo, 66, 'CORN'));
comprobar('vidrio: palabras en texto: 1,5 + 150 %', 3.75, precio($pdo, 66, 'VID'));
comprobar('iPhone por marca: 700 + 12 %', 784.0, precio($pdo, 58, 'IPH'));
comprobar('otro teléfono con el 8 % de la lista', 108.0, precio($pdo, 58, 'RED13'));
$pdo->exec('UPDATE listas_precios SET redondear_arriba = 1 WHERE id = 66');
plRecalcularTodas($pdo);
comprobar('26,30 → 27', 27.0, precio($pdo, 66, 'CORN'));
comprobar('3,75 → 4', 4.0, precio($pdo, 66, 'VID'));
comprobar('8,50 → 9', 9.0, precio($pdo, 66, 'FORRO'));
comprobar('lista sin la opción no se redondea', 784.0, precio($pdo, 58, 'IPH'));
comprobar('un entero exacto no sube', 23.0, plAEnteroArriba(23.0000001));
comprobar('22,01 → 23', 23.0, plAEnteroArriba(22.01));
comprobar('un JSON roto no rompe el cálculo', 70.0,
    plPctPara(['pct_sobre_costo' => 70, 'reglas_pct' => '{roto'], ['nombre' => 'Corneta']));
comprobar('tildes: «Cornéta» calza con «corneta»', 100.0,
    plPctPara(['pct_sobre_costo' => 70, 'reglas_pct' => json_encode([
        ['nombre' => 'C', 'palabras' => ['corneta'], 'pct' => 100]])], ['nombre' => 'CORNÉTA Xtreme']));
$n = plNormalizarCamposNuevos(['reglas_pct' => json_encode([
    ['nombre' => 'Vacía', 'palabras' => [' ', ''], 'marca' => '', 'pct' => 50],
    ['nombre' => 'Cargadores', 'palabras' => ['Cargador'], 'pct' => '90']]), 'redondear_arriba' => false]);
$r = json_decode((string)$n['reglas_pct'], true);
comprobar('la regla vacía se descarta', 1, count($r));
comprobar('palabras normalizadas', ['cargador'], $r[0]['palabras']);
comprobar('el redondeo se apaga', 0, $n['redondear_arriba']);
comprobar('sin reglas válidas: NULL', null, plNormalizarCamposNuevos(['reglas_pct' => '[]'])['reglas_pct']);

// ════ 7. Una app vieja (1.0.17) guarda: no borra campos nuevos ni es_manual ════
$pdo = base();
$pdo->exec("UPDATE listas_precios SET redondear_arriba = 1, pct_sobre_costo = 33, tasa_bs = 950,
    reglas_pct = '[{\"nombre\":\"X\",\"palabras\":[\"x\"],\"marca\":\"\",\"pct\":5}]', tiene_cuotas = 0 WHERE id = 58");
// Lo que manda la 1.0.17: cabecera vieja y valores sin es_manual.
$cuerpoViejo = ['nombre' => 'Equipos Divisas', 'porcentaje_adicional' => 25, 'modo_precios' => 'costo',
    'actualizado_en' => '2099-01-01',
    'items' => [['producto_codigo' => 'RED13', 'stock_disponible' => 2,
                 'valores' => [['columna_nombre' => 'Precio', 'precio' => 80]]],
                ['producto_codigo' => 'NUEVO', 'stock_disponible' => 1,
                 'valores' => [['columna_nombre' => 'Precio', 'precio' => 5]]]]];
$pdo->beginTransaction();
$cuerpo = plFusionarCuerpoPut($pdo, 58, $cuerpoViejo);
$pdo->commit();
comprobar('modo_precios no cambia por un PUT normal', false, array_key_exists('modo_precios', $cuerpo));
comprobar('actualizado_en no la pone el cliente', false, array_key_exists('actualizado_en', $cuerpo));
comprobar('es_manual guardado se conserva', 1, $cuerpo['items'][0]['valores'][0]['es_manual']);
comprobar('el precio nuevo sí se toma', 80, $cuerpo['items'][0]['valores'][0]['precio']);
comprobar('un ítem nuevo no inventa marca', false, array_key_exists('es_manual', $cuerpo['items'][1]['valores'][0]));
foreach (['redondear_arriba', 'pct_sobre_costo', 'tasa_bs', 'reglas_pct', 'tiene_cuotas'] as $k) {
    comprobar("la app vieja no manda $k: el UPDATE no lo toca", false, array_key_exists($k, $cuerpo));
}
// Lo mismo con la app nueva: manda es_manual y gana lo suyo.
$pdo->beginTransaction();
$cuerpo = plFusionarCuerpoPut($pdo, 58, ['items' => [['producto_codigo' => 'RED13',
    'valores' => [['columna_nombre' => 'Precio', 'precio' => 81, 'es_manual' => 0]]]],
    'redondear_arriba' => '0', 'reglas_pct' => null, 'tiene_cuotas' => true]);
$pdo->commit();
comprobar('la app nueva desmarca una celda', 0, $cuerpo['items'][0]['valores'][0]['es_manual']);
comprobar('la app nueva apaga el redondeo', 0, $cuerpo['redondear_arriba']);
comprobar('la app nueva borra las reglas', null, $cuerpo['reglas_pct']);
comprobar('tiene_cuotas llega como 0/1', 1, $cuerpo['tiene_cuotas']);
// Ítem con una clave por ítem que la app vieja no conoce: se conserva.
$it = plJson(fila($pdo, 58)['items']);
$it[0]['clave_futura'] = 'x';
$pdo->prepare('UPDATE listas_precios SET items = ? WHERE id = 58')->execute([json_encode($it)]);
$pdo->beginTransaction();
$cuerpo = plFusionarCuerpoPut($pdo, 58, $cuerpoViejo);
$pdo->commit();
comprobar('una clave nueva por ítem se conserva', 'x', $cuerpo['items'][0]['clave_futura'] ?? null);

// ════ 8. Ensayo, activación y vuelta atrás ════
$pdo = base();
$antes = foto($pdo);
$res = plActivarCosto($pdo, 58, ['pct_sobre_costo' => 8], true);
comprobar('ensayo: informa el cambio', 1, $res['informes'][0]['precios']);
comprobar('ensayo: no guarda nada', $antes, foto($pdo));
comprobar('ensayo: sigue en manual', 'manual', fila($pdo, 58)['modo_precios']);
comprobar('ensayo: no enciende nada', false, plInterruptor($pdo, 'precios_auto_activo'));
$res = plActivarCosto($pdo, 58, ['pct_sobre_costo' => 8, 'redondear_arriba' => 1, 'tasa_bs' => 900], false, 'dueno@x.com');
comprobar('activar: en modo costo', 'costo', fila($pdo, 58)['modo_precios']);
comprobar('activar: precio 108', 108.0, precio($pdo, 58, 'RED13'));
comprobar('activar: guarda la configuración', 900.0, (float)fila($pdo, 58)['tasa_bs']);
comprobar('activar: enciende los enganches', true, plInterruptor($pdo, 'precios_auto_activo'));
comprobar('activar: un respaldo', 1, count($res['respaldos']));
comprobar('activar: las demás listas (manuales) no se tocan', 125000.0, precio($pdo, 65, 'RED13'));
comprobar('revertir', true, plRevertir($pdo, 58));
comprobar('revertir: el precio de antes', 77.0, precio($pdo, 58, 'RED13'));
comprobar('revertir: la marca de manual de antes', 1, manual($pdo, 58, 'RED13'));
comprobar('revertir: en manual', 'manual', fila($pdo, 58)['modo_precios']);
comprobar('revertir: la configuración de antes', 0.0, (float)fila($pdo, 58)['tasa_bs']);
plActivarCosto($pdo, 58, ['pct_sobre_costo' => 8], false);
plDesactivarCosto($pdo, 58);
comprobar('desactivar: a manual sin tocar precios', [108.0, 'manual'],
    [precio($pdo, 58, 'RED13'), fila($pdo, 58)['modo_precios']]);
$falla = null;
try { plActivarCosto($pdo, 12345, [], true); } catch (Throwable $e) { $falla = $e->getMessage(); }
comprobar('lista inexistente: error', true, $falla !== null);

// ════ 9. Quién puede ensayar o activar ════
$pdo = base();
comprobar('Dueño', true, plUsuarioPuedeGestionar($pdo, 'DUENO@x.com'));
comprobar('Gerente', true, plUsuarioPuedeGestionar($pdo, 'gerente@x.com'));
comprobar('Vendedor no', false, plUsuarioPuedeGestionar($pdo, 'vende@x.com'));
comprobar('Administrador inactivo no', false, plUsuarioPuedeGestionar($pdo, 'viejo@x.com'));
comprobar('sin correo no', false, plUsuarioPuedeGestionar($pdo, ''));
comprobar('correo desconocido no', false, plUsuarioPuedeGestionar($pdo, 'nadie@x.com'));

// ════ 10. Columnas virtuales y fórmulas en __fx__ ════
$fx = '__fx__' . rtrim(strtr(base64_encode(json_encode(['c' => 'Mayor', 'f' => ['modo' => 'monto', 'valor' => 2]])), '+/', '-_'), '');
[$reales, $conF] = plColumnas([['nombre' => 'Precio'], ['nombre' => 'Mayor'], ['nombre' => $fx],
    ['nombre' => '__pct_inicial__']]);
comprobar('reales sin virtuales', ['Precio', 'Mayor'], $reales);
comprobar('fórmula leída de la columna virtual __fx__', true, isset($conF['mayor']));
comprobar('nombre virtual', true, plEsNombreVirtual('__inicial_manual__'));
comprobar('nombre real', false, plEsNombreVirtual('$BCV'));
comprobar('filtro de la app: categoría Todos', true, plLeCorresponde(['categoria' => 'Todos', 'marca_filtro' => 'Todas'], 'X', 'Y'));
comprobar('filtro de la app: marca sin mayúsculas', true, plLeCorresponde(['categoria' => 'Telefono', 'marca_filtro' => 'samsung'], 'Telefono', 'Samsung'));
comprobar('filtro de la app: otra categoría', false, plLeCorresponde(['categoria' => 'Telefono', 'marca_filtro' => 'Todas'], 'Accesorio', ''));

// ════ 11. Lista en Bs con lista base en divisas (orden del dueño 19/10/2026) ════
//  Precio en Bs = precio en la lista en divisas + % de la lista en Bs, × tasa.
$pdo = base();
$pdo->exec('UPDATE listas_precios SET lista_base_id = 58, pct_sobre_costo = 10 WHERE id = 65');
$listas = plListas($pdo);
$porId = [];
foreach ($listas as $l) $porId[(int)$l['id']] = $l;
comprobar('la base elegida manda aunque esté a mano', 58, (int)plBaseDeBs($porId[65], $listas)['id']);
comprobar('base a mano: su precio guardado (77)', 77.0,
    plPrecioEnBase($porId[58], $listas, 100, ['codigo' => 'RED13']));
comprobar('base a mano sin el producto: null', null,
    plPrecioEnBase($porId[58], $listas, 5, ['codigo' => 'FORRO']));
$red = ['codigo' => 'RED13', 'nombre' => 'Redmi 13', 'marca' => 'Xiaomi', 'categoria' => 'Telefono',
        'precio_venta' => 125.0];
$v = plValores($porId[65], $listas, 100, BCV, $red);
comprobar('Bs = (77 + 10 %) × BCV', plRedondear2(84.7 * BCV), $v['precio']);
$v = plValores($porId[65], $listas, 100, BCV, ['codigo' => 'OTRO', 'precio_venta' => 50.0] + $red);
comprobar('sin precio en la base: venta (50) + 10 %, × BCV', plRedondear2(55 * BCV), $v['precio']);
costo($pdo, 58, ['pct_sobre_costo' => 8]);
$listas = plListas($pdo);
foreach ($listas as $l) $porId[(int)$l['id']] = $l;
$v = plValores($porId[65], $listas, 100, BCV, $red);
comprobar('base en costo: (108 + 10 %) × BCV', plRedondear2(118.8 * BCV), $v['precio']);
$sinPct = $porId[65]; $sinPct['pct_sobre_costo'] = 0;
comprobar('con 0 % en la lista Bs da lo de antes (108 × BCV)', plRedondear2(108 * BCV),
    plValores($sinPct, $listas, 100, BCV, $red)['precio']);
// Una lista Bs en costo cuya base está A MANO se recalcula al guardar la base.
$pdo = base();
$pdo->exec('UPDATE listas_precios SET lista_base_id = 58 WHERE id = 65');
costo($pdo, 65, ['pct_sobre_costo' => 10]);
$inf = plRecalcularConDependientes($pdo, 58);
comprobar('guardar la base a mano recalcula su lista Bs en costo', [65], array_column($inf, 'lista_id'));
comprobar('y su precio = (77 + 10 %) × BCV', plRedondear2(84.7 * BCV), precio($pdo, 65, 'RED13'));
comprobar('la base a mano no se toca', 77.0, precio($pdo, 58, 'RED13'));
comprobar('una base manual sin listas Bs que la elijan: nada', [], plRecalcularConDependientes($pdo, 66));
// PUT de la app: el campo se normaliza; la app vieja (sin el campo) no lo borra.
comprobar('lista_base_id se guarda como entero', ['lista_base_id' => 58],
    plNormalizarCamposNuevos(['lista_base_id' => '58']));
comprobar('vacío o basura = 0 (ninguna)', ['lista_base_id' => 0],
    plNormalizarCamposNuevos(['lista_base_id' => 'x']));
comprobar('es un campo nuevo (la 1.0.17 no lo manda)', true, in_array('lista_base_id', PL_CAMPOS_NUEVOS, true));

// ── Vista de las listas en Bs (23/10/2026): bs / bcv / bcv_bs ──
comprobar('vista_bs bcv se guarda', ['vista_bs' => 'bcv'], plNormalizarCamposNuevos(['vista_bs' => 'BCV']));
comprobar('vista_bs bcv_bs se guarda', ['vista_bs' => 'bcv_bs'], plNormalizarCamposNuevos(['vista_bs' => 'bcv_bs']));
comprobar('vista_bs basura = bs (como siempre)', ['vista_bs' => 'bs'], plNormalizarCamposNuevos(['vista_bs' => 'x']));
comprobar('vista_bs es un campo nuevo (la 1.0.17 no lo manda)', true, in_array('vista_bs', PL_CAMPOS_NUEVOS, true));

echo $fallos === 0
    ? "precios_listas: $pasadas comprobaciones OK\n"
    : "precios_listas: $fallos FALLAS de " . ($fallos + $pasadas) . "\n";
exit($fallos === 0 ? 0 : 1);
