<?php
// ============================================================================
//  precios_listas.php — Listas de precios: precios desde el costo (APAGADO)
//
//  Portado de Brizuela (backen/precios_auto.php y backen/listas_auto.php,
//  hasta su versión 1.0.72) y adaptado a cómo guarda las listas Tecno Líder:
//  UNA fila por lista en `listas_precios`, con `columnas` e `items` en JSON
//  (items[].valores[] = {columna_nombre, precio, es_manual?}).
//
//  DECISIÓN DEL DUEÑO (16/10/2026)
//  -------------------------------
//  Todo esto viene APAGADO. Cada lista sigue exactamente como hoy (precios a
//  mano, `modo_precios = 'manual'`) hasta que la administración la pase a
//  «desde el costo». Antes de activar hay un ENSAYO que dice cuántos precios
//  cambiarían. Al desplegar este archivo NINGÚN precio cambia:
//
//    · Los enganches (productos, listas, tasa BCV) salen enseguida si el
//      interruptor `precios_auto_activo` (tabla configuracion) no vale 1, y
//      aun encendidos solo tocan listas con `modo_precios = 'costo'`.
//    · Hoy ninguna lista está en modo costo (la columna nace en 'manual').
//
//  LA CUENTA (igual que Brizuela; la app hace la misma en
//  lib/reglas_porcentaje.dart y ListaPrecio.porcentajePara)
//  ------------------------------------------------------------------
//    · Lista Divisas (en $, no de financiamiento):
//          (costo + monto fijo $) × (1 + % sobre costo)
//    · Lista de financiadora (Cashea, Krece, Weppa…): el % va sobre el
//      PRECIO DE VENTA del producto = su precio en la lista Divisas (en modo
//      costo) que le corresponde. Sin esa lista, sobre el costo.
//    · Lista en Bs: el precio del producto en su lista base en divisas
//      MÁS EL % DE LA LISTA EN Bs, × tasa (orden del dueño 19/10/2026:
//      «tome el precio de las listas en divisas y sea a esa lista la que
//      se le aumente el porcentaje»). La base es la que la lista eligió
//      (`lista_base_id`); si no eligió, su lista Divisas pareja (en modo
//      costo, misma marca, la que más categorías comparte). Una base a
//      mano aporta el precio guardado en su primera columna; si el
//      producto no está ahí, vale su precio de venta. Sin base, el % de
//      la lista va sobre el costo. La tasa: la propia de la lista si tiene
//      «tasa fija»; si no, la «tasa manual para llevar a Bs» de su base;
//      si no, la BCV del día. Su columna «$BCV» = Bs ÷ BCV.
//    · % especial por tipo de producto (`reglas_pct`): por palabras del
//      nombre o por marca; gana la primera regla que calce.
//    · `redondear_arriba` = 1: sin decimales y siempre hacia arriba.
//
//  QUÉ COSTO VALE CUANDO HAY VARIAS FILAS (una por tienda)
//  -------------------------------------------------------
//  `productos` tiene UNIQUE(codigo, tienda): el mismo código puede tener un
//  costo distinto en cada tienda. Vale el MAYOR costo de las filas vivas
//  (eliminado_en IS NULL) con costo > 0. Así ninguna tienda vende por debajo
//  de lo que le costó el equipo. Sin costo cargado, el producto conserva el
//  precio que tenga en la lista (no queda en 0).
//
//  LO QUE NO TOCA
//  --------------
//    · Columnas con fórmula de la app (modo distinto de manual, guardada en
//      `formula` o en una columna virtual `__fx__…`): las sigue calculando la
//      app al abrir la lista, como hoy.
//    · Columnas virtuales `__x__` (inicial/cuota por producto…). En modo
//      costo sí se borran `__inicial_manual__` y `__cuota_manual__` del ítem
//      (montos escritos a mano con el precio viejo, como hace Brizuela);
//      `__pct_inicial__` y `__n_cuotas__` (condiciones) se conservan.
//    · Nunca saca un producto de una lista (Brizuela 1d32008).
//    · Nunca agrega subproductos (variantes) ni productos nuevos sin stock
//      (reglas de Tecno Líder), y solo agrega si `listas_auto_agregar` = 1.
//
//  INTERRUPTORES (tabla configuracion, clave/valor; ausentes = 0)
//  --------------------------------------------------------------
//    precios_auto_activo      enganches encendidos (solo listas en costo)
//    listas_auto_agregar      un producto nuevo entra solo en sus listas
//    precio_venta_desde_lista el precio de venta del producto = su lista
//                             Divisas en modo costo
//
//  Compatible con PHP 7.4 (sin str_contains ni match).
// ============================================================================

declare(strict_types=1);

const PL_COLUMNA_BCV = '$BCV';
const PL_INTERRUPTORES = ['precios_auto_activo', 'listas_auto_agregar', 'precio_venta_desde_lista'];
/** Roles que pueden ensayar y activar precios desde el costo (sin el Maestro, que no está en la base). */
const PL_ROLES_GESTION = ['dueño', 'dueno', 'administrador', 'gerente'];

// ── Utilidades ──────────────────────────────────────────────────────────

/**
 * Redondeo a 2 decimales igual que `redondearPrecio` de la app
 * (`(v * 100).round() / 100`, mitad hacia afuera). No se usa round($v, 2)
 * porque PHP pre-redondea a 15 cifras y en los casos límite daría un
 * centavo distinto que la app.
 */
function plRedondear2(float $v): float {
    if (is_nan($v) || is_infinite($v)) return 0.0;
    $x = $v * 100;
    $piso = floor(abs($x));
    $entero = (abs($x) - $piso) >= 0.5 ? $piso + 1 : $piso;
    return ($x < 0 ? -$entero : $entero) / 100;
}

/** Sin decimales y hacia arriba; primero a centavos (23,0000001 → 23). */
function plAEnteroArriba(float $v): float {
    return (float)ceil(plRedondear2($v) - 0.000001);
}

function plMinusculas(string $t): string {
    return function_exists('mb_strtolower') ? mb_strtolower($t, 'UTF-8') : strtolower($t);
}

/** Minúsculas y sin tildes, para comparar nombres. */
function plNormalizarTexto(string $t): string {
    $t = plMinusculas(trim($t));
    return strtr($t, ['á' => 'a', 'é' => 'e', 'í' => 'i', 'ó' => 'o', 'ú' => 'u',
                      'ü' => 'u', 'ñ' => 'n']);
}

function plEsMysql(PDO $pdo): bool {
    return $pdo->getAttribute(PDO::ATTR_DRIVER_NAME) === 'mysql';
}

/** Columnas reales de una tabla (MySQL o SQLite). [] si no existe. */
function plColumnasTabla(PDO $pdo, string $tabla): array {
    // La caché guarda también el PDO: así su hash no se reutiliza para otra
    // conexión (las pruebas abren una base por caso).
    static $cache = [];
    $k = spl_object_hash($pdo) . '|' . $tabla;
    if (isset($cache[$k]) && $cache[$k][0] === $pdo) return $cache[$k][1];
    try {
        if (plEsMysql($pdo)) {
            $st = $pdo->prepare('SELECT COLUMN_NAME FROM information_schema.COLUMNS
                                  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
                                  ORDER BY ORDINAL_POSITION');
            $st->execute([$tabla]);
            $cols = $st->fetchAll(PDO::FETCH_COLUMN);
        } else {
            $cols = [];
            foreach ($pdo->query('PRAGMA table_info(' . $tabla . ')')->fetchAll(PDO::FETCH_ASSOC) as $r) {
                $cols[] = $r['name'];
            }
        }
    } catch (Throwable $e) {
        $cols = [];
    }
    $cache[$k] = [$pdo, $cols];
    return $cols;
}

function plTieneColumna(PDO $pdo, string $tabla, string $col): bool {
    return in_array($col, plColumnasTabla($pdo, $tabla), true);
}

/** Valor de un interruptor de `configuracion` (ausente o sin tabla = false). */
function plInterruptor(PDO $pdo, string $clave): bool {
    try {
        $st = $pdo->prepare('SELECT valor FROM configuracion WHERE clave = ? LIMIT 1');
        $st->execute([$clave]);
        $v = $st->fetchColumn();
        return $v !== false && trim((string)$v) === '1';
    } catch (Throwable $e) {
        return false;
    }
}

function plAsegurarConfiguracion(PDO $pdo): void {
    if (plEsMysql($pdo)) {
        $pdo->exec("CREATE TABLE IF NOT EXISTS configuracion (
            id INT AUTO_INCREMENT PRIMARY KEY,
            clave VARCHAR(120) NOT NULL UNIQUE,
            valor TEXT NULL,
            actualizado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    } else {
        $pdo->exec('CREATE TABLE IF NOT EXISTS configuracion (id INTEGER PRIMARY KEY AUTOINCREMENT,
            clave TEXT NOT NULL UNIQUE, valor TEXT NULL)');
    }
}

function plPonerInterruptor(PDO $pdo, string $clave, bool $valor): void {
    if (!in_array($clave, PL_INTERRUPTORES, true)) {
        throw new InvalidArgumentException("Interruptor desconocido: $clave");
    }
    $v = $valor ? '1' : '0';
    $st = $pdo->prepare('UPDATE configuracion SET valor = ? WHERE clave = ?');
    $st->execute([$v, $clave]);
    if ($st->rowCount() === 0) {
        $ya = $pdo->prepare('SELECT COUNT(*) FROM configuracion WHERE clave = ?');
        $ya->execute([$clave]);
        if ((int)$ya->fetchColumn() === 0) {
            $pdo->prepare('INSERT INTO configuracion (clave, valor) VALUES (?, ?)')->execute([$clave, $v]);
        }
    }
}

/** Tasa BCV vigente (la marcada es_actual; si no, la última). 0 si no hay. */
function plTasaBcvActual(PDO $pdo): float {
    try {
        $v = $pdo->query('SELECT valor FROM tasa_bcv WHERE es_actual = 1 ORDER BY id DESC LIMIT 1')
            ->fetchColumn();
        if ($v === false || (float)$v <= 0) {
            $v = $pdo->query('SELECT valor FROM tasa_bcv ORDER BY id DESC LIMIT 1')->fetchColumn();
        }
        return (float)($v ?: 0);
    } catch (Throwable $e) {
        return 0.0;
    }
}

/** ¿El correo es de un usuario activo con rol de Dueño, Administrador o Gerente? */
function plUsuarioPuedeGestionar(PDO $pdo, ?string $correo): bool {
    $correo = trim((string)$correo);
    if ($correo === '') return false;
    try {
        $sql = 'SELECT rol FROM usuarios WHERE LOWER(correo) = LOWER(?)';
        if (plTieneColumna($pdo, 'usuarios', 'activo')) $sql .= ' AND activo = 1';
        if (plTieneColumna($pdo, 'usuarios', 'eliminado_en')) $sql .= ' AND eliminado_en IS NULL';
        $st = $pdo->prepare($sql . ' LIMIT 1');
        $st->execute([$correo]);
        $rol = $st->fetchColumn();
        return $rol !== false && in_array(plMinusculas(trim((string)$rol)), PL_ROLES_GESTION, true);
    } catch (Throwable $e) {
        return false;
    }
}

// ── Lectura de listas ───────────────────────────────────────────────────

function plEsBs(array $l): bool { return (int)($l['es_en_bolivares'] ?? 0) === 1; }
function plEsFinanciamiento(array $l): bool { return (int)($l['es_financiamiento'] ?? 0) === 1; }
function plEsCosto(array $l): bool { return trim((string)($l['modo_precios'] ?? 'manual')) === 'costo'; }
function plRedondeaArriba(array $l): bool { return (int)($l['redondear_arriba'] ?? 0) === 1; }

/** Decodifica un campo JSON de la fila (texto o arreglo). */
function plJson($crudo): array {
    if (is_array($crudo)) return $crudo;
    $d = json_decode((string)$crudo, true);
    return is_array($d) ? $d : [];
}

function plListas(PDO $pdo, bool $soloCosto = false): array {
    $sql = 'SELECT * FROM listas_precios';
    if (plTieneColumna($pdo, 'listas_precios', 'eliminado_en')) $sql .= ' WHERE eliminado_en IS NULL';
    $rows = $pdo->query($sql . ' ORDER BY id')->fetchAll(PDO::FETCH_ASSOC);
    if ($soloCosto) $rows = array_values(array_filter($rows, 'plEsCosto'));
    return $rows;
}

/** Categorías de una lista. La app usa una sola; se admiten varias con coma. */
function plCategoriasLista(array $l): array {
    return array_values(array_filter(array_map('trim',
        explode(',', (string)($l['categoria'] ?? ''))), static function ($c) { return $c !== ''; }));
}

/** ¿El producto (categoría, marca) entra en el filtro de la lista? (= la app) */
function plLeCorresponde(array $lista, string $categoria, string $marca): bool {
    $cats = plCategoriasLista($lista);
    $okCategoria = $cats === [] || in_array('Todos', $cats, true) || in_array($categoria, $cats, true);
    $filtroMarca = (string)($lista['marca_filtro'] ?? 'Todas');
    $okMarca = $filtroMarca === '' || $filtroMarca === 'Todas'
        || plMinusculas($marca) === plMinusculas($filtroMarca);
    return $okCategoria && $okMarca;
}

/** ¿El nombre es de una columna virtual (__x__ o __fx__…)? Igual que la app. */
function plEsNombreVirtual(string $n): bool {
    return strpos($n, '__fx__') === 0
        || (strlen($n) >= 4 && substr($n, 0, 2) === '__' && substr($n, -2) === '__');
}

/**
 * Columnas de una lista: [nombresReales, nombresConFormula].
 * La fórmula viaja en `formula` (JSON) o en una columna virtual `__fx__`
 * (base64url de {"c": columna, "f": fórmula}).
 */
function plColumnas(array $columnas): array {
    $reales = [];
    $conFormula = [];
    foreach ($columnas as $c) {
        if (!is_array($c)) continue;
        $n = (string)($c['nombre'] ?? '');
        if ($n === '') continue;
        if (strpos($n, '__fx__') === 0) {
            $raw = substr($n, 6);
            $dec = base64_decode(strtr($raw, '-_', '+/'), true);
            $j = $dec === false ? null : json_decode($dec, true);
            if (is_array($j) && isset($j['c'], $j['f']) && is_array($j['f'])
                && ($j['f']['modo'] ?? 'manual') !== 'manual') {
                $conFormula[plMinusculas((string)$j['c'])] = true;
            }
            continue;
        }
        if (plEsNombreVirtual($n)) continue;
        $reales[] = $n;
        $f = $c['formula'] ?? null;
        $f = is_array($f) ? $f : json_decode((string)$f, true);
        if (is_array($f) && ($f['modo'] ?? 'manual') !== 'manual') $conFormula[plMinusculas($n)] = true;
    }
    return [$reales, $conFormula];
}

// ── % especial por tipo de producto ─────────────────────────────────────

/** Reglas de % de una lista, ya limpias. Un JSON roto = sin reglas. */
function plReglas(array $lista): array {
    $crudo = $lista['reglas_pct'] ?? null;
    $datos = is_array($crudo) ? $crudo : json_decode((string)$crudo, true);
    if (!is_array($datos)) return [];
    $reglas = [];
    foreach ($datos as $r) {
        if (!is_array($r) || !is_numeric($r['pct'] ?? null)) continue;
        $palabras = is_array($r['palabras'] ?? null) ? $r['palabras']
            : explode(',', (string)($r['palabras'] ?? ''));
        $palabras = array_values(array_unique(array_filter(array_map(
            static function ($p) { return plNormalizarTexto((string)$p); }, $palabras),
            static function ($p) { return $p !== ''; })));
        $marca = plNormalizarTexto((string)($r['marca'] ?? ''));
        if ($palabras === [] && $marca === '') continue;   // no calzaría con nada
        $nombre = trim((string)($r['nombre'] ?? ''));
        $reglas[] = [
            'nombre'   => function_exists('mb_substr') ? mb_substr($nombre, 0, 60) : substr($nombre, 0, 60),
            'palabras' => array_slice($palabras, 0, 30),
            'marca'    => $marca,
            'pct'      => max(-99.0, min(10000.0, (float)$r['pct'])),
        ];
    }
    return array_slice($reglas, 0, 50);
}

/** La regla que le toca a un producto (null si ninguna). */
function plReglaPara(array $lista, ?array $prod): ?array {
    if ($prod === null) return null;
    $nombre = plNormalizarTexto((string)($prod['nombre'] ?? ''));
    $marca  = plNormalizarTexto((string)($prod['marca'] ?? ''));
    foreach (plReglas($lista) as $r) {
        if ($r['marca'] !== '' && $r['marca'] === $marca) return $r;
        foreach ($r['palabras'] as $p) {
            if ($nombre !== '' && strpos($nombre, $p) !== false) return $r;
        }
    }
    return null;
}

/**
 * % que la lista le suma a un producto en modo costo: el de su regla o el
 * `pct_sobre_costo` de la lista. NO es `porcentaje_adicional`: ese es el %
 * sobre el precio de venta que usa la app 1.0.17 al poblar, y se deja tal cual.
 */
function plPctPara(array $lista, ?array $prod): float {
    $r = plReglaPara($lista, $prod);
    return $r !== null ? (float)$r['pct'] : (float)($lista['pct_sobre_costo'] ?? 0);
}

/** Precio en $ de una lista desde una base (costo, o venta en financiamiento). */
function plPrecioUsd(array $lista, float $base, ?array $prod = null): float {
    $v = plRedondear2(($base + (float)($lista['monto_adicional_dolares'] ?? 0))
        * (1 + plPctPara($lista, $prod) / 100));
    return plRedondeaArriba($lista) ? plAEnteroArriba($v) : $v;
}

/**
 * Lista Divisas pareja de una lista en Bs: en $, no de financiamiento, EN
 * MODO COSTO, misma marca y la que más categorías comparte (Brizuela bfa88b9).
 */
function plParDivisas(array $listaBs, array $listas): ?array {
    if (!plEsBs($listaBs) || plEsFinanciamiento($listaBs)) return null;
    $cats = static function (array $l): array {
        return array_map('plMinusculas', plCategoriasLista($l));
    };
    $marca = static function (array $l): string {
        return plMinusculas(trim((string)($l['marca_filtro'] ?? 'Todas')));
    };
    $mias = $cats($listaBs);
    $mejor = null; $puntos = 0;
    foreach ($listas as $l) {
        if (plEsBs($l) || plEsFinanciamiento($l) || !plEsCosto($l)) continue;
        if ($marca($l) !== $marca($listaBs)) continue;
        $comunes = count(array_intersect($mias, $cats($l)));
        $p = $comunes * 1000 - count(array_diff($cats($l), $mias));
        if ($comunes > 0 && ($mejor === null || $p > $puntos)) { $mejor = $l; $puntos = $p; }
    }
    return $mejor;
}

/**
 * Lista base de una lista en Bs: la que eligió (`lista_base_id`, en $, de
 * cualquier modo) o, si no eligió, su lista Divisas pareja en modo costo.
 */
function plBaseDeBs(array $listaBs, array $listas): ?array {
    if (!plEsBs($listaBs)) return null;
    $id = (int)($listaBs['lista_base_id'] ?? 0);
    if ($id > 0) {
        foreach ($listas as $l) {
            if ((int)$l['id'] === $id && !plEsBs($l)) return $l;
        }
    }
    return plParDivisas($listaBs, $listas);
}

/**
 * Precio en $ de un producto en la lista base de una lista en Bs: en modo
 * costo se calcula; a mano, el guardado en su primera columna. null si la
 * base a mano no lo tiene (o lo tiene en 0).
 */
function plPrecioEnBase(array $base, array $listas, float $costo, ?array $prod): ?float {
    if (plEsCosto($base)) {
        if (plEsFinanciamiento($base) && $prod !== null) {
            $venta = plVentaDe($prod + ['precio_costo' => $costo], $listas);
            if ($venta !== null) return plPrecioUsd($base, $venta, $prod);
        }
        return plPrecioUsd($base, $costo, $prod);
    }
    $codigo = (string)($prod['codigo'] ?? '');
    [$reales] = plColumnas(plJson($base['columnas'] ?? '[]'));
    if ($codigo === '' || $reales === []) return null;
    foreach (plJson($base['items'] ?? '[]') as $it) {
        if ((string)($it['producto_codigo'] ?? '') !== $codigo) continue;
        foreach ((is_array($it['valores'] ?? null) ? $it['valores'] : []) as $v) {
            if ((string)($v['columna_nombre'] ?? '') === $reales[0] && (float)($v['precio'] ?? 0) > 0) {
                return (float)$v['precio'];
            }
        }
        return null;
    }
    return null;
}

/** Tasa con la que una lista en Bs lleva los precios a Bs. */
function plTasaBs(array $listaBs, array $listas, float $bcv): float {
    if ((int)($listaBs['tasa_fija'] ?? 0) === 1 && (float)($listaBs['tasa_del_dia'] ?? 0) > 0) {
        return (float)$listaBs['tasa_del_dia'];
    }
    $par = plBaseDeBs($listaBs, $listas);
    if ($par !== null && (float)($par['tasa_bs'] ?? 0) > 0) return (float)$par['tasa_bs'];
    return $bcv > 0 ? $bcv : (float)($listaBs['tasa_del_dia'] ?? 0);
}

/** Precio de venta: el de su lista Divisas en modo costo (null si no hay). */
function plVentaDe(array $prod, array $listas): ?float {
    $cands = array_values(array_filter($listas, static function ($l) use ($prod) {
        return plEsCosto($l) && !plEsBs($l) && !plEsFinanciamiento($l)
            && plLeCorresponde($l, (string)($prod['categoria'] ?? ''), (string)($prod['marca'] ?? ''));
    }));
    if ($cands === [] || (float)($prod['precio_costo'] ?? 0) <= 0) return null;
    // Una lista filtrada por marca manda sobre la de «Todas».
    usort($cands, static function ($a, $b) {
        return ((($a['marca_filtro'] ?? 'Todas') === 'Todas') <=> (($b['marca_filtro'] ?? 'Todas') === 'Todas'));
    });
    return plPrecioUsd($cands[0], (float)$prod['precio_costo'], $prod);
}

/**
 * Precios de un producto en una lista: ['precio' => …, 'bcv' => …|null].
 * `precio` en la moneda de la lista; `bcv` solo en las listas en Bs.
 */
function plValores(array $lista, array $listas, float $costo, float $bcv, ?array $prod = null): array {
    if (!plEsBs($lista)) {
        if (plEsFinanciamiento($lista) && $prod !== null) {
            $venta = plVentaDe($prod + ['precio_costo' => $costo], $listas);
            if ($venta !== null) return ['precio' => plPrecioUsd($lista, $venta, $prod), 'bcv' => null];
        }
        return ['precio' => plPrecioUsd($lista, $costo, $prod), 'bcv' => null];
    }
    $base = plBaseDeBs($lista, $listas);
    $tasa = plTasaBs($lista, $listas, $bcv);
    if ($base === null) {
        // Sin lista base: su propio % sobre el costo.
        $usd = plPrecioUsd($lista, $costo, $prod);
    } else {
        // Precio en la base (o, si no está ahí, la venta) + el % de ESTA
        // lista. El redondeo hacia arriba se hace en Bs, más abajo.
        $partida = plPrecioEnBase($base, $listas, $costo, $prod)
            ?? (float)($prod['precio_venta'] ?? 0);
        $usd = plRedondear2(($partida + (float)($lista['monto_adicional_dolares'] ?? 0))
            * (1 + plPctPara($lista, $prod) / 100));
    }
    $bs = plRedondear2($usd * $tasa);
    if (plRedondeaArriba($lista)) $bs = plAEnteroArriba($bs);
    return ['precio' => $bs, 'bcv' => $bcv > 0 ? plRedondear2($bs / $bcv) : null];
}

// ── Catálogo ────────────────────────────────────────────────────────────

/**
 * Catálogo por código: una entrada por código con el MAYOR costo de sus
 * filas vivas (una por tienda), nombre/categoría/marca de la primera fila,
 * si es subproducto y el stock sumado (stock_manual de todas las tiendas).
 */
function plCatalogo(PDO $pdo): array {
    $sql = 'SELECT codigo, nombre, categoria, marca, precio_costo, precio_venta, stock_manual'
        . (plTieneColumna($pdo, 'productos', 'producto_padre_codigo') ? ', producto_padre_codigo' : '')
        . ' FROM productos'
        . (plTieneColumna($pdo, 'productos', 'eliminado_en') ? ' WHERE eliminado_en IS NULL' : '')
        . ' ORDER BY ' . (plTieneColumna($pdo, 'productos', 'id') ? 'id' : 'codigo');
    $cat = [];
    foreach ($pdo->query($sql)->fetchAll(PDO::FETCH_ASSOC) as $r) {
        $c = (string)$r['codigo'];
        if ($c === '') continue;
        if (!isset($cat[$c])) {
            $cat[$c] = [
                'codigo' => $c, 'nombre' => (string)$r['nombre'],
                'categoria' => (string)$r['categoria'], 'marca' => (string)$r['marca'],
                'precio_costo' => 0.0, 'precio_venta' => (float)$r['precio_venta'],
                'stock_manual' => 0,
                'padre' => trim((string)($r['producto_padre_codigo'] ?? '')),
            ];
        }
        $cat[$c]['precio_costo'] = max($cat[$c]['precio_costo'], (float)$r['precio_costo']);
        $cat[$c]['stock_manual'] += (int)$r['stock_manual'];
    }
    return $cat;
}

/** Categorías que usan IMEI (configuracion cfg_categorias_productos; si no, solo «Telefono»). */
function plCategoriasConImei(PDO $pdo): array {
    $res = ['telefono' => true];
    try {
        $st = $pdo->prepare('SELECT valor FROM configuracion WHERE clave = ? LIMIT 1');
        $st->execute(['cfg_categorias_productos']);
        $v = json_decode((string)$st->fetchColumn(), true);
        if (is_array($v)) {
            $res = [];
            foreach ($v as $c) {
                if (!is_array($c)) continue;
                $n = plMinusculas(trim((string)($c['nombre'] ?? '')));
                $u = $c['usa_imei'] ?? $c['usaImei'] ?? false;
                if ($n !== '' && ($u === true || $u === 1 || $u === '1' || $u === 'true')) $res[$n] = true;
            }
        }
    } catch (Throwable $e) { /* sin configuración: lo histórico */ }
    return $res;
}

/** Stock global de un código (todas las tiendas + variantes), como la app. */
function plStockDe(PDO $pdo, array $prod, array $catalogo, array $conImei): int {
    $codigos = [$prod['codigo']];
    foreach ($catalogo as $c => $p) if ($p['padre'] === $prod['codigo']) $codigos[] = $c;
    if (isset($conImei[plMinusculas(trim($prod['categoria']))])) {
        try {
            $ph = implode(',', array_fill(0, count($codigos), '?'));
            $sql = "SELECT COUNT(*) FROM stock_imei WHERE producto_codigo IN ($ph)
                      AND (vendido = 0 OR vendido IS NULL)";
            if (plTieneColumna($pdo, 'stock_imei', 'eliminado_en')) $sql .= ' AND eliminado_en IS NULL';
            $st = $pdo->prepare($sql);
            $st->execute($codigos);
            return (int)$st->fetchColumn();
        } catch (Throwable $e) {
            return 0;
        }
    }
    $n = 0;
    foreach ($codigos as $c) $n += (int)($catalogo[$c]['stock_manual'] ?? 0);
    return max(0, $n);
}

// ── Escritura en el JSON de una lista ───────────────────────────────────

/**
 * Escribe los precios de un ítem (por referencia): `precio` en cada columna
 * real sin fórmula, salvo «$BCV», que lleva `bcv`. Crea las celdas que
 * falten, quita la marca de manual y borra inicial/cuota fijadas a mano.
 * Devuelve ['precios' => celdas cuyo precio cambia o se crea,
 *           'tocado' => si cambió algo (también marcas o montos fijos),
 *           'montos' => inicial/cuota fijadas a mano que se borran].
 */
function plEscribirItem(array &$item, array $reales, array $conFormula, array $v): array {
    $valores = is_array($item['valores'] ?? null) ? $item['valores'] : [];
    $cambios = 0;
    $montos = 0;
    $tocado = false;
    $limpios = [];
    foreach ($valores as $val) {
        $n = (string)($val['columna_nombre'] ?? '');
        if ($n === '__inicial_manual__' || $n === '__cuota_manual__') { $montos++; $tocado = true; continue; }
        $limpios[] = $val;
    }
    $valores = $limpios;
    foreach ($reales as $col) {
        if (isset($conFormula[plMinusculas($col)])) continue;
        $precio = $col === PL_COLUMNA_BCV ? $v['bcv'] : $v['precio'];
        if ($precio === null) continue;
        $precio = (float)$precio;
        $hallado = false;
        foreach ($valores as &$val) {
            if ((string)($val['columna_nombre'] ?? '') !== $col) continue;
            $hallado = true;
            if (abs((float)($val['precio'] ?? 0) - $precio) >= 0.005) { $cambios++; $tocado = true; }
            elseif ((int)($val['es_manual'] ?? 0) !== 0) $tocado = true;
            $val['precio'] = $precio;
            $val['es_manual'] = 0;
        }
        unset($val);
        if (!$hallado) {
            $valores[] = ['columna_nombre' => $col, 'precio' => $precio, 'es_manual' => 0];
            $cambios++;
            $tocado = true;
        }
    }
    $item['valores'] = $valores;
    return ['precios' => $cambios, 'tocado' => $tocado, 'montos' => $montos];
}

function plGuardarFila(PDO $pdo, int $id, array $campos): void {
    $sets = [];
    $vals = [];
    foreach ($campos as $k => $v) { $sets[] = "`$k` = ?"; $vals[] = $v; }
    if (plTieneColumna($pdo, 'listas_precios', 'actualizado_en')) $sets[] = '`actualizado_en` = CURRENT_TIMESTAMP';
    $vals[] = $id;
    $pdo->prepare('UPDATE listas_precios SET ' . implode(', ', $sets) . ' WHERE id = ?')->execute($vals);
}

function plJsonTexto(array $v): string {
    return json_encode($v, JSON_UNESCAPED_UNICODE | JSON_PRESERVE_ZERO_FRACTION);
}

/**
 * Recalcula UNA lista en modo costo desde el catálogo y la guarda.
 * Devuelve el informe: ['lista_id','nombre','precios'=>celdas que cambian,
 * 'items'=>ítems que cambian,'agregados'=>productos nuevos,'ejemplos'=>[…]].
 * Una lista en modo manual no se toca (informe en cero).
 *
 * No mira el interruptor general: eso lo hacen los enganches (plEnganche*).
 */
function plRecalcularLista(PDO $pdo, int $listaId, ?array $listas = null, ?float $bcv = null,
                           ?array $catalogo = null): array {
    $listas = $listas ?? plListas($pdo);
    $bcv = $bcv ?? plTasaBcvActual($pdo);
    $lista = null;
    foreach ($listas as $l) if ((int)$l['id'] === $listaId) $lista = $l;
    $inf = ['lista_id' => $listaId, 'nombre' => (string)($lista['nombre'] ?? ''),
            'precios' => 0, 'items' => 0, 'agregados' => 0, 'montos_fijos' => 0, 'ejemplos' => []];
    if ($lista === null || !plEsCosto($lista)) return $inf;

    $catalogo = $catalogo ?? plCatalogo($pdo);
    $columnas = plJson($lista['columnas'] ?? '[]');
    $items = plJson($lista['items'] ?? '[]');
    $campos = [];

    // Lista en Bs: columna «$BCV» y la tasa con la que quedó, a la vista.
    if (plEsBs($lista)) {
        [$reales] = plColumnas($columnas);
        if (!in_array(PL_COLUMNA_BCV, $reales, true)) {
            $columnas[] = ['nombre' => PL_COLUMNA_BCV,
                           'formula' => json_encode(['modo' => 'manual'])];
            $campos['columnas'] = true;
        }
        $tasa = plTasaBs($lista, $listas, $bcv);
        if ($tasa > 0 && abs((float)($lista['tasa_del_dia'] ?? 0) - $tasa) >= 0.00005) {
            $campos['tasa_del_dia'] = $tasa;
        }
    }
    [$reales, $conFormula] = plColumnas($columnas);
    if ($reales === []) return $inf;   // sin columnas no hay dónde poner el precio

    // Productos que le corresponden y no están (solo con listas_auto_agregar).
    if (plInterruptor($pdo, 'listas_auto_agregar')) {
        $presentes = [];
        foreach ($items as $it) $presentes[(string)($it['producto_codigo'] ?? '')] = true;
        $conImei = plCategoriasConImei($pdo);
        foreach ($catalogo as $c => $p) {
            if (isset($presentes[$c]) || $p['padre'] !== '') continue;
            if (!plLeCorresponde($lista, $p['categoria'], $p['marca'])) continue;
            $stock = plStockDe($pdo, $p, $catalogo, $conImei);
            if ($stock <= 0) continue;   // regla de Tecno Líder: nuevos sin stock no entran
            $items[] = ['producto_codigo' => $c, 'stock_disponible' => $stock, 'valores' => []];
            $inf['agregados']++;
        }
    }

    $tocado = false;
    foreach ($items as &$it) {
        $c = (string)($it['producto_codigo'] ?? '');
        $p = $catalogo[$c] ?? null;
        if ($p === null) continue;                    // producto borrado: conserva
        if ($p['precio_costo'] <= 0) continue;        // sin costo: conserva su precio
        $antes = $it['valores'] ?? [];
        $v = plValores($lista, $listas, $p['precio_costo'], $bcv, $p);
        $r = plEscribirItem($it, $reales, $conFormula, $v);
        if ($r['tocado']) $tocado = true;
        $inf['montos_fijos'] += $r['montos'];
        if ($r['precios'] > 0) {
            $inf['precios'] += $r['precios'];
            $inf['items']++;
            if (count($inf['ejemplos']) < 5) {
                $viejo = null;
                foreach ($antes as $a) {
                    if ((string)($a['columna_nombre'] ?? '') === $reales[0]) $viejo = (float)$a['precio'];
                }
                $inf['ejemplos'][] = ['codigo' => $c, 'nombre' => $p['nombre'],
                                      'antes' => $viejo, 'despues' => $v['precio']];
            }
        }
    }
    unset($it);

    if ($tocado || $inf['agregados'] > 0 || $campos !== []) {
        $guardar = ['items' => plJsonTexto($items)];
        if (isset($campos['columnas'])) $guardar['columnas'] = plJsonTexto($columnas);
        if (isset($campos['tasa_del_dia'])) $guardar['tasa_del_dia'] = $campos['tasa_del_dia'];
        plGuardarFila($pdo, $listaId, $guardar);
    }
    return $inf;
}

/**
 * Una lista y las que dependen de ella. Si es una Divisas en modo costo,
 * de ella salen sus listas en Bs y las financiadoras: se recalculan todas
 * las listas en modo costo que sean en Bs o de financiamiento. Si no, solo
 * ella. Devuelve los informes por lista.
 */
function plRecalcularConDependientes(PDO $pdo, int $listaId): array {
    $listas = plListas($pdo);
    $bcv = plTasaBcvActual($pdo);
    $catalogo = plCatalogo($pdo);
    $lista = null;
    foreach ($listas as $l) if ((int)$l['id'] === $listaId) $lista = $l;
    if ($lista === null) return [];
    $ids = plEsCosto($lista) ? [$listaId] : [];
    // Listas en Bs en modo costo que eligieron esta lista como base
    // (aunque la base esté a mano).
    if (!plEsBs($lista)) {
        foreach ($listas as $l) {
            if (plEsCosto($l) && plEsBs($l) && (int)($l['lista_base_id'] ?? 0) === $listaId) {
                $ids[] = (int)$l['id'];
            }
        }
    }
    if ($ids === []) return [];
    if (plEsCosto($lista) && !plEsBs($lista) && !plEsFinanciamiento($lista)) {
        foreach ($listas as $l) {
            if ((int)$l['id'] !== $listaId && plEsCosto($l) && (plEsBs($l) || plEsFinanciamiento($l))) {
                $ids[] = (int)$l['id'];
            }
        }
    }
    $ids = array_values(array_unique($ids));
    $informes = [];
    foreach ($ids as $id) {
        $informes[] = plRecalcularLista($pdo, $id, $listas, $bcv, $catalogo);
        $listas = plListas($pdo);   // la siguiente ve lo que se acaba de guardar
    }
    return $informes;
}

/** Todas las listas en modo costo. */
function plRecalcularTodas(PDO $pdo): array {
    $listas = plListas($pdo, true);
    // Primero las Divisas (de ellas dependen las demás).
    usort($listas, static function ($a, $b) {
        $pa = (plEsBs($a) || plEsFinanciamiento($a)) ? 1 : 0;
        $pb = (plEsBs($b) || plEsFinanciamiento($b)) ? 1 : 0;
        return $pa <=> $pb ?: ((int)$a['id'] <=> (int)$b['id']);
    });
    $bcv = plTasaBcvActual($pdo);
    $catalogo = plCatalogo($pdo);
    $informes = [];
    foreach ($listas as $l) {
        $informes[] = plRecalcularLista($pdo, (int)$l['id'], plListas($pdo), $bcv, $catalogo);
    }
    return $informes;
}

/** Precio de venta de un código desde su lista Divisas en modo costo. Devuelve filas cambiadas. */
function plActualizarVentaProducto(PDO $pdo, string $codigo, ?array $listas = null, ?array $catalogo = null): int {
    $catalogo = $catalogo ?? plCatalogo($pdo);
    $p = $catalogo[$codigo] ?? null;
    if ($p === null || $p['precio_costo'] <= 0) return 0;
    $venta = plVentaDe($p, $listas ?? plListas($pdo));
    if ($venta === null) return 0;
    $st = $pdo->prepare('UPDATE productos SET precio_venta = ? WHERE codigo = ? AND ABS(precio_venta - ?) >= 0.005');
    $st->execute([number_format($venta, 2, '.', ''), $codigo, $venta]);
    return $st->rowCount();
}

/**
 * Un producto cambió (alta, costo, categoría, marca): sus listas en modo
 * costo y, si se pidió, su precio de venta. Devuelve celdas cambiadas.
 */
function plSincronizarProducto(PDO $pdo, string $codigo): int {
    $catalogo = plCatalogo($pdo);
    $p = $catalogo[$codigo] ?? null;
    if ($p === null) return 0;
    $listas = plListas($pdo);
    $bcv = plTasaBcvActual($pdo);
    $agregar = plInterruptor($pdo, 'listas_auto_agregar') && $p['padre'] === '';
    $stock = null;
    $total = 0;
    foreach ($listas as $lista) {
        if (!plEsCosto($lista)) continue;
        $items = plJson($lista['items'] ?? '[]');
        $idx = null;
        foreach ($items as $i => $it) if ((string)($it['producto_codigo'] ?? '') === $codigo) $idx = $i;
        if ($idx === null) {
            if (!$agregar || !plLeCorresponde($lista, $p['categoria'], $p['marca'])) continue;
            $stock = $stock ?? plStockDe($pdo, $p, $catalogo, plCategoriasConImei($pdo));
            if ($stock <= 0) continue;
            $items[] = ['producto_codigo' => $codigo, 'stock_disponible' => $stock, 'valores' => []];
            $idx = count($items) - 1;
        }
        if ($p['precio_costo'] <= 0) {
            if (count($items) !== count(plJson($lista['items'] ?? '[]'))) {
                plGuardarFila($pdo, (int)$lista['id'], ['items' => plJsonTexto($items)]);
            }
            continue;
        }
        $columnas = plJson($lista['columnas'] ?? '[]');
        [$reales, $conFormula] = plColumnas($columnas);
        if ($reales === []) continue;
        $v = plValores($lista, $listas, $p['precio_costo'], $bcv, $p);
        $r = plEscribirItem($items[$idx], $reales, $conFormula, $v);
        $nuevo = count($items) !== count(plJson($lista['items'] ?? '[]'));
        if ($r['tocado'] || $nuevo) {
            plGuardarFila($pdo, (int)$lista['id'], ['items' => plJsonTexto($items)]);
            $total += $r['precios'];
        }
    }
    if (plInterruptor($pdo, 'precio_venta_desde_lista')) {
        plActualizarVentaProducto($pdo, $codigo, $listas, $catalogo);
    }
    return $total;
}

/** Tasa BCV nueva: las listas en Bs en modo costo (su $BCV, y su precio si no tienen tasa propia). */
function plAplicarTasaBcv(PDO $pdo, float $tasa): int {
    if ($tasa <= 0) return 0;
    $listas = plListas($pdo);
    $catalogo = plCatalogo($pdo);
    $n = 0;
    foreach ($listas as $l) {
        if (!plEsCosto($l) || !plEsBs($l)) continue;
        $inf = plRecalcularLista($pdo, (int)$l['id'], $listas, $tasa, $catalogo);
        if ($inf['precios'] > 0) $n++;
    }
    return $n;
}

// ── PUT de una lista: fusión con lo guardado ────────────────────────────

/** Campos de cabecera nuevos (los que la app 1.0.17 no conoce). */
const PL_CAMPOS_NUEVOS = ['tiene_cuotas', 'monto_adicional_dolares', 'modo_precios', 'pct_sobre_costo',
    'tasa_fija', 'tasa_bs', 'redondear_arriba', 'reglas_pct', 'lista_base_id', 'vista_bs'];

/** Limpia los campos nuevos de un cuerpo (tipos y reglas). */
function plNormalizarCamposNuevos(array $body): array {
    foreach (['tiene_cuotas', 'tasa_fija', 'redondear_arriba'] as $k) {
        if (array_key_exists($k, $body)) $body[$k] = !empty($body[$k]) && $body[$k] !== '0' ? 1 : 0;
    }
    foreach (['monto_adicional_dolares', 'pct_sobre_costo', 'tasa_bs'] as $k) {
        if (array_key_exists($k, $body)) $body[$k] = is_numeric($body[$k]) ? (float)$body[$k] : 0.0;
    }
    if (array_key_exists('lista_base_id', $body)) {
        $b = is_numeric($body['lista_base_id']) ? (int)$body['lista_base_id'] : 0;
        $body['lista_base_id'] = $b > 0 ? $b : 0;
    }
    // Vista de una lista en Bs (23/10/2026): solo cambia cómo se muestra.
    if (array_key_exists('vista_bs', $body)) {
        $v = strtolower(trim((string)$body['vista_bs']));
        $body['vista_bs'] = in_array($v, ['bcv', 'bcv_bs'], true) ? $v : 'bs';
    }
    if (array_key_exists('reglas_pct', $body)) {
        $reglas = plReglas(['reglas_pct' => $body['reglas_pct']]);
        $body['reglas_pct'] = $reglas === [] ? null : json_encode($reglas, JSON_UNESCAPED_UNICODE);
    }
    return $body;
}

/**
 * Antes de un PUT normal de lista. Lee la fila guardada (FOR UPDATE en
 * MySQL; hay que estar dentro de una transacción) y:
 *
 *   · Ítems: un valor que llega sin `es_manual` (app 1.0.17) conserva la
 *     marca guardada de esa celda; una clave por ítem que la app vieja no
 *     manda (cualquiera que no sea código, stock o valores) se conserva.
 *   · Cabecera: lo que no viene no se toca (el UPDATE solo pone lo que
 *     llega), así que una app vieja no borra los campos nuevos.
 *   · `modo_precios` NUNCA cambia por un PUT normal: se activa y desactiva
 *     con el ensayo (accion=precios_costo) o por la línea de comandos.
 *
 * Devuelve el cuerpo listo para guardar (columnas/items aún como arreglos).
 */
function plFusionarCuerpoPut(PDO $pdo, $id, array $body): array {
    unset($body['modo_precios'], $body['actualizado_en'], $body['id'], $body['creado_en'], $body['eliminado_en']);
    $sql = 'SELECT items FROM listas_precios WHERE id = ?' . (plEsMysql($pdo) ? ' FOR UPDATE' : '');
    $st = $pdo->prepare($sql);
    $st->execute([$id]);
    $fila = $st->fetch(PDO::FETCH_ASSOC);
    $body = plNormalizarCamposNuevos($body);
    if (!$fila || !array_key_exists('items', $body)) return $body;

    $entrantes = is_array($body['items']) ? $body['items'] : json_decode((string)$body['items'], true);
    if (!is_array($entrantes)) return $body;
    $guardados = [];
    foreach (plJson($fila['items']) as $it) {
        if (is_array($it) && isset($it['producto_codigo'])) $guardados[(string)$it['producto_codigo']] = $it;
    }
    $basicos = ['producto_codigo' => true, 'stock_disponible' => true, 'valores' => true];
    foreach ($entrantes as &$it) {
        if (!is_array($it)) continue;
        $g = $guardados[(string)($it['producto_codigo'] ?? '')] ?? null;
        if ($g === null) continue;
        foreach ($g as $k => $v) {
            if (!isset($basicos[$k]) && !array_key_exists($k, $it)) $it[$k] = $v;
        }
        $marcas = [];
        foreach ((is_array($g['valores'] ?? null) ? $g['valores'] : []) as $gv) {
            if (is_array($gv) && array_key_exists('es_manual', $gv)) {
                $marcas[(string)($gv['columna_nombre'] ?? '')] = (int)$gv['es_manual'];
            }
        }
        if (!is_array($it['valores'] ?? null)) continue;
        foreach ($it['valores'] as &$val) {
            if (!is_array($val) || array_key_exists('es_manual', $val)) continue;
            $n = (string)($val['columna_nombre'] ?? '');
            if (isset($marcas[$n])) $val['es_manual'] = $marcas[$n];
        }
        unset($val);
    }
    unset($it);
    $body['items'] = $entrantes;
    return $body;
}

// ── Ensayo, activación y vuelta atrás ───────────────────────────────────

function plAsegurarTablaRespaldos(PDO $pdo): void {
    if (plEsMysql($pdo)) {
        $pdo->exec("CREATE TABLE IF NOT EXISTS listas_precios_respaldos (
            id INT AUTO_INCREMENT PRIMARY KEY,
            lista_id INT NOT NULL,
            motivo VARCHAR(60) NOT NULL DEFAULT '',
            usuario VARCHAR(160) NOT NULL DEFAULT '',
            datos LONGTEXT NOT NULL,
            creado_en TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_lista (lista_id, id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4");
    } else {
        $pdo->exec("CREATE TABLE IF NOT EXISTS listas_precios_respaldos (
            id INTEGER PRIMARY KEY AUTOINCREMENT, lista_id INT NOT NULL, motivo TEXT DEFAULT '',
            usuario TEXT DEFAULT '', datos TEXT NOT NULL, creado_en TEXT DEFAULT CURRENT_TIMESTAMP)");
    }
}

/** Guarda la fila entera de cada lista en listas_precios_respaldos. Devuelve los ids. */
function plRespaldar(PDO $pdo, array $listaIds, string $motivo, string $usuario = ''): array {
    $ids = [];
    $st = $pdo->prepare('SELECT * FROM listas_precios WHERE id = ?');
    $ins = $pdo->prepare('INSERT INTO listas_precios_respaldos (lista_id, motivo, usuario, datos) VALUES (?, ?, ?, ?)');
    foreach (array_unique($listaIds) as $id) {
        $st->execute([$id]);
        $fila = $st->fetch(PDO::FETCH_ASSOC);
        if (!$fila) continue;
        $ins->execute([(int)$id, $motivo, $usuario, json_encode($fila, JSON_UNESCAPED_UNICODE)]);
        $ids[] = (int)$pdo->lastInsertId();
    }
    return $ids;
}

/** Ids de las listas que puede mover una lista (ella y, si es Divisas, las Bs/financiadoras en costo). */
function plIdsAfectados(array $listas, int $listaId, bool $tambienManualesBs = false): array {
    $lista = null;
    foreach ($listas as $l) if ((int)$l['id'] === $listaId) $lista = $l;
    if ($lista === null) return [];
    $ids = [$listaId];
    if (!plEsBs($lista) && !plEsFinanciamiento($lista)) {
        foreach ($listas as $l) {
            if ((int)$l['id'] !== $listaId && plEsCosto($l) && (plEsBs($l) || plEsFinanciamiento($l))) {
                $ids[] = (int)$l['id'];
            }
        }
    }
    return $ids;
}

/** Campos de configuración del cálculo que se pueden mandar al ensayar o activar. */
const PL_CAMPOS_CONFIG = ['pct_sobre_costo', 'monto_adicional_dolares', 'tasa_fija', 'tasa_del_dia',
    'tasa_bs', 'redondear_arriba', 'reglas_pct'];

/**
 * Pone una lista en modo costo con `config` y la recalcula (con sus
 * dependientes). Con `$ensayo` todo se deshace al final. Abre su propia
 * transacción. Devuelve ['ok','ensayo','informes','respaldos'].
 */
function plActivarCosto(PDO $pdo, int $listaId, array $config, bool $ensayo, string $usuario = ''): array {
    $listas = plListas($pdo);
    $existe = false;
    foreach ($listas as $l) if ((int)$l['id'] === $listaId) $existe = true;
    if (!$existe) throw new RuntimeException("La lista $listaId no existe");

    // DDL fuera de la transacción: en MySQL un CREATE cierra la transacción abierta.
    if (!$ensayo) {
        plAsegurarTablaRespaldos($pdo);
        plAsegurarConfiguracion($pdo);
    }
    $pdo->beginTransaction();
    try {
        $respaldos = [];
        if (!$ensayo) {
            // Respaldo de la lista y de todas las listas en costo que puede mover.
            $respaldos = plRespaldar($pdo, plIdsAfectados($listas, $listaId), 'activar_costo', $usuario);
        }
        $campos = ['modo_precios' => 'costo'];
        foreach (plNormalizarCamposNuevos(array_intersect_key($config, array_flip(PL_CAMPOS_CONFIG))) as $k => $v) {
            if ($k === 'tasa_del_dia') { if (is_numeric($v) && (float)$v > 0) $campos[$k] = (float)$v; continue; }
            $campos[$k] = $v;
        }
        $campos = array_intersect_key($campos, array_flip(plColumnasTabla($pdo, 'listas_precios')));
        plGuardarFila($pdo, $listaId, $campos);
        $informes = plRecalcularConDependientes($pdo, $listaId);
        if (!$ensayo && plInterruptor($pdo, 'precio_venta_desde_lista')) {
            $listasAhora = plListas($pdo);
            $cat = plCatalogo($pdo);
            foreach (array_keys($cat) as $c) plActualizarVentaProducto($pdo, $c, $listasAhora, $cat);
        }
        if ($ensayo) {
            $pdo->rollBack();
        } else {
            // Activar una lista enciende los enganches (que solo tocan listas en costo).
            plPonerInterruptor($pdo, 'precios_auto_activo', true);
            $pdo->commit();
        }
        return ['ok' => true, 'ensayo' => $ensayo, 'informes' => $informes, 'respaldos' => $respaldos];
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        throw $e;
    }
}

/** Vuelve una lista a modo manual SIN tocar sus precios. */
function plDesactivarCosto(PDO $pdo, int $listaId): void {
    $pdo->prepare("UPDATE listas_precios SET modo_precios = 'manual' WHERE id = ?")->execute([$listaId]);
}

/**
 * Restaura una lista desde su respaldo (el último, o `$respaldoId`):
 * columnas, ítems, tasa y configuración del cálculo, y la deja en manual.
 */
function plRevertir(PDO $pdo, int $listaId, ?int $respaldoId = null): bool {
    plAsegurarTablaRespaldos($pdo);
    if ($respaldoId !== null) {
        $st = $pdo->prepare('SELECT datos FROM listas_precios_respaldos WHERE id = ? AND lista_id = ?');
        $st->execute([$respaldoId, $listaId]);
    } else {
        $st = $pdo->prepare('SELECT datos FROM listas_precios_respaldos WHERE lista_id = ? ORDER BY id DESC LIMIT 1');
        $st->execute([$listaId]);
    }
    $datos = json_decode((string)$st->fetchColumn(), true);
    if (!is_array($datos)) return false;
    $campos = array_intersect_key($datos, array_flip(array_merge(
        ['columnas', 'items', 'tasa_del_dia'], PL_CAMPOS_CONFIG)));
    $campos['modo_precios'] = 'manual';
    $campos = array_intersect_key($campos, array_flip(plColumnasTabla($pdo, 'listas_precios')));
    plGuardarFila($pdo, $listaId, $campos);
    return true;
}

// ── Enganches (dormidos: salen si precios_auto_activo no es 1) ──────────

/** Después de un POST/PUT de productos. Nunca lanza. */
function plEngancheProducto(PDO $pdo, string $codigo): void {
    try {
        if ($codigo === '' || !plInterruptor($pdo, 'precios_auto_activo')) return;
        plSincronizarProducto($pdo, $codigo);
    } catch (Throwable $e) {
        error_log("[precios_listas] producto $codigo: " . $e->getMessage());
    }
}

/** Antes de escribir un producto: venta desde su lista (solo con los dos interruptores). */
function plEnganchePrepararProducto(PDO $pdo, array $body, ?string $codigo = null): array {
    try {
        if (!plInterruptor($pdo, 'precios_auto_activo') || !plInterruptor($pdo, 'precio_venta_desde_lista')) {
            return $body;
        }
        $actual = [];
        if ($codigo !== null && $codigo !== '') $actual = plCatalogo($pdo)[$codigo] ?? [];
        $costo = array_key_exists('precio_costo', $body) ? (float)$body['precio_costo'] : (float)($actual['precio_costo'] ?? 0);
        $prod = [
            'nombre' => (string)($body['nombre'] ?? $actual['nombre'] ?? ''),
            'categoria' => (string)($body['categoria'] ?? $actual['categoria'] ?? ''),
            'marca' => (string)($body['marca'] ?? $actual['marca'] ?? ''),
            'precio_costo' => $costo,
        ];
        $venta = plVentaDe($prod, plListas($pdo));
        if ($venta !== null) $body['precio_venta'] = $venta;
    } catch (Throwable $e) {
        error_log('[precios_listas] preparar producto: ' . $e->getMessage());
    }
    return $body;
}

/** Después de un POST/PUT de listas_precios. Nunca lanza. */
function plEngancheLista(PDO $pdo, int $listaId): void {
    try {
        if (!plInterruptor($pdo, 'precios_auto_activo')) return;
        plRecalcularConDependientes($pdo, $listaId);
    } catch (Throwable $e) {
        error_log("[precios_listas] lista $listaId: " . $e->getMessage());
    }
}

/** Después de cargar una tasa BCV nueva. Nunca lanza. */
function plEngancheTasaBcv(PDO $pdo, float $tasa): void {
    try {
        if (!plInterruptor($pdo, 'precios_auto_activo')) return;
        plAplicarTasaBcv($pdo, $tasa);
    } catch (Throwable $e) {
        error_log('[precios_listas] tasa BCV: ' . $e->getMessage());
    }
}
