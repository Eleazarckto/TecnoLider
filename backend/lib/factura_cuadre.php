<?php
// ════════════════════════════════════════════════════════════════════
//  factura_cuadre.php — Facturación: cuadre, moneda por pago, vuelto,
//  FPB en el servidor, reintento sin duplicar y búsqueda en el historial.
// ════════════════════════════════════════════════════════════════════
//  Mejoras de facturación traídas de Brizuela (1.0.72), adaptadas a
//  TecnoLíder con las decisiones del dueño (oct-2026):
//
//  · Se CONSERVA el contado/financiado POR PRODUCTO de TecnoLíder (no
//    hay «modalidad» por factura). El objetivo del cuadre es mixto:
//        Σ precio de contado de las líneas de contado
//      + Σ inicial aprobada de las líneas financiadas.
//  · Tasa como hoy en TecnoLíder: contado pagado en Bs = precio BCV ×
//    tasa BCV; las financiadoras, a BCV. NO la «tasa de divisas».
//  · Cada pago en su moneda (fc_moneda_de_metodo, igual que
//    `esMetodoEnBolivares` de la app). Pago mezclado: ver fc_cuadre
//    (espejo de CuadreFactura de lib/factura_cuadre.dart).
//  · Vuelto solo en efectivo o divisas: pago NEGATIVO con es_vuelto = 1.
//  · FPB: la cuenta por cobrar la crea el servidor en la misma petición,
//    con factura_id, número, tienda y cuotas; es idempotente y se anula
//    al borrar la factura si no tiene abonos (si los tiene, se conserva
//    con un aviso).
//  · clave_idempotencia: un reintento de la MISMA factura devuelve la ya
//    guardada en vez de crear otra.
//
//  ACTIVACIÓN GRADUAL
//  ------------------
//  `configuracion.factura_cuadre_servidor` = '0' (por defecto: no existe
//  la fila). Con '0' el servidor solo GUARDA los datos nuevos que manda
//  la app nueva; no rechaza ninguna factura y la app crea la cuenta FPB
//  como antes (ahora con factura_id). Con '1':
//    · repite el cuadre de la app nueva (la que manda el bloque `cuadre`)
//      y rechaza con 422 la que no cuadra;
//    · crea la cuenta FPB él mismo.
//  La app vieja (1.0.17) nunca manda `cuadre`: con '0' o con '1' factura
//  EXACTAMENTE igual que antes.
//
//  Todo recibe el PDO por parámetro para poder probarlo con SQLite
//  (backend/tests/). El esquema se completa fuera de toda transacción
//  (un ALTER en MySQL cierra la transacción abierta).
// ════════════════════════════════════════════════════════════════════

declare(strict_types=1);

final class FacturaCuadreError extends RuntimeException {}

const FC_FLAG = 'factura_cuadre_servidor';

// ────────────────────────────────────────────────────────────────
//  Esquema
// ────────────────────────────────────────────────────────────────

function fc_driver(PDO $pdo): string {
    return (string)$pdo->getAttribute(PDO::ATTR_DRIVER_NAME);
}

/** Columnas de una tabla ([] si no existe). Cacheado por petición. */
function fc_columnas(PDO $pdo, string $tabla, bool $refrescar = false): array {
    static $cache = [];
    $k = spl_object_id($pdo) . ':' . $tabla;
    if (!$refrescar && isset($cache[$k])) return $cache[$k];
    $cols = [];
    try {
        if (fc_driver($pdo) === 'sqlite') {
            foreach ($pdo->query("PRAGMA table_info(" . $pdo->quote($tabla) . ")")->fetchAll(PDO::FETCH_ASSOC) as $r) {
                $cols[] = (string)$r['name'];
            }
        } else {
            $st = $pdo->prepare('SELECT COLUMN_NAME FROM information_schema.COLUMNS
                                  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?
                                  ORDER BY ORDINAL_POSITION');
            $st->execute([$tabla]);
            $cols = $st->fetchAll(PDO::FETCH_COLUMN);
        }
    } catch (Throwable $e) {
        $cols = [];
    }
    return $cache[$k] = $cols;
}

function fc_tiene(PDO $pdo, string $tabla, string $col): bool {
    return in_array($col, fc_columnas($pdo, $tabla), true);
}

/** Columnas nuevas. Todas NULL o con DEFAULT: no recalculan nada viejo. */
function fc_columnas_nuevas(): array {
    return [
        'facturas' => [
            'inicial'            => 'DECIMAL(14,2) NULL',
            'monto_financiado'   => 'DECIMAL(14,2) NULL',
            'tasa_bcv'           => 'DECIMAL(12,4) NULL',
            'clave_idempotencia' => 'VARCHAR(64) NULL',
            // Dirección del cliente (orden del dueño 23/10/2026).
            'direccion'          => 'VARCHAR(255) NULL',
        ],
        'factura_items' => [
            'precio_unitario' => 'DECIMAL(12,2) NULL',
        ],
        'factura_equipos' => [
            'precio_unitario' => 'DECIMAL(12,2) NULL',
        ],
        'factura_pagos' => [
            'moneda'    => 'VARCHAR(3) NULL',
            'monto_usd' => 'DECIMAL(12,2) NULL',
            'es_vuelto' => 'TINYINT(1) NOT NULL DEFAULT 0',
        ],
        'cuentas_cobrar' => [
            'factura_id'  => 'INT NULL',
            'nro_factura' => 'VARCHAR(80) NULL',
            'tienda'      => 'VARCHAR(100) NULL',
        ],
    ];
}

/**
 * Agrega lo que falte (idempotente). Devuelve [aplicado[], ya_estaba[],
 * errores[]] para el informe de reparar_esquema. NUNCA dentro de una
 * transacción.
 */
function fc_asegurar_esquema(PDO $pdo, bool $forzar = false): array {
    static $hecho = [];
    $k = spl_object_id($pdo);
    if (!$forzar && isset($hecho[$k])) return $hecho[$k];
    $aplicado = [];
    $ya = [];
    $errores = [];
    foreach (fc_columnas_nuevas() as $tabla => $defs) {
        if (fc_columnas($pdo, $tabla) === []) continue;   // tabla inexistente
        foreach ($defs as $col => $def) {
            $titulo = "$tabla.$col";
            if (fc_tiene($pdo, $tabla, $col)) { $ya[] = $titulo; continue; }
            try {
                $pdo->exec(fc_driver($pdo) === 'sqlite'
                    ? "ALTER TABLE $tabla ADD COLUMN $col $def"
                    : "ALTER TABLE `$tabla` ADD COLUMN `$col` $def");
                fc_columnas($pdo, $tabla, true);
                $aplicado[] = $titulo;
            } catch (Throwable $e) {
                $errores[] = "$titulo: " . $e->getMessage();
            }
        }
    }
    // Índice ÚNICO de la clave de idempotencia (los NULL no chocan).
    if (fc_tiene($pdo, 'facturas', 'clave_idempotencia')) {
        $titulo = 'índice facturas.clave_idempotencia';
        try {
            if (fc_driver($pdo) === 'sqlite') {
                $pdo->exec('CREATE UNIQUE INDEX IF NOT EXISTS uk_facturas_clave_idem
                            ON facturas (clave_idempotencia)');
                $ya[] = $titulo;
            } else {
                $st = $pdo->query("SHOW INDEX FROM `facturas` WHERE Key_name = 'uk_facturas_clave_idem'");
                if ($st->fetch()) {
                    $ya[] = $titulo;
                } else {
                    $pdo->exec('ALTER TABLE `facturas`
                                ADD UNIQUE INDEX `uk_facturas_clave_idem` (`clave_idempotencia`)');
                    $aplicado[] = $titulo;
                }
            }
        } catch (Throwable $e) {
            $errores[] = "$titulo: " . $e->getMessage();
        }
    }
    if ($errores) error_log('[factura_cuadre esquema] ' . implode(' | ', $errores));
    return $hecho[$k] = [$aplicado, $ya, $errores];
}

/** ¿Está encendida la validación/creación FPB del servidor? */
function fc_flag_activo(PDO $pdo): bool {
    try {
        $st = $pdo->prepare('SELECT valor FROM configuracion WHERE clave = ? LIMIT 1');
        $st->execute([FC_FLAG]);
        return trim((string)$st->fetchColumn()) === '1';
    } catch (Throwable $e) {
        return false;
    }
}

/** La app nueva manda el bloque `cuadre`; la 1.0.17 no. */
function fc_es_app_nueva(array $body): bool {
    return isset($body['cuadre']) && is_array($body['cuadre']);
}

// ────────────────────────────────────────────────────────────────
//  Monedas, vuelto y cuadre (espejo de lib/factura_cuadre.dart)
// ────────────────────────────────────────────────────────────────

function fc_r2(float $v): float {
    return round($v, 2);
}

/** 'BS' o 'USD'. Misma regla que `esMetodoEnBolivares` de la app. */
function fc_moneda_de_metodo(string $metodo): string {
    $m = mb_strtolower(trim($metodo), 'UTF-8');
    if (in_array($m, ['efectivo bs', 'pago móvil', 'pago movil', 'transferencia', 'punto de venta'], true)) {
        return 'BS';
    }
    if (strpos($m, '$') !== false || strpos($m, 'usd') !== false || strpos($m, 'divisa') !== false) {
        return 'USD';
    }
    $bs = strpos($m, 'pago móvil') !== false || strpos($m, 'pago movil') !== false
        || strpos($m, 'punto') === 0 || strpos($m, 'transferencia') === 0
        || strpos($m, 'efectivo bs') !== false
        || preg_match('/(^|[^a-z])bs\.?$/u', $m) === 1;
    return $bs ? 'BS' : 'USD';
}

/** Vuelto solo en efectivo o divisas (no Pago Móvil, BDV, punto...). */
function fc_metodo_permite_vuelto(string $metodo): bool {
    $m = mb_strtolower(trim($metodo), 'UTF-8');
    return strpos($m, 'efectivo') !== false || strpos($m, 'divisa') !== false;
}

function fc_verdad($v): bool {
    return $v === true || $v === 1 || $v === '1' || $v === 'true';
}

function fc_es_vuelto(array $p): bool {
    return fc_verdad($p['es_vuelto'] ?? 0) || (float)($p['monto'] ?? 0) < 0;
}

function fc_fmt_usd(float $v): string { return '$' . number_format($v, 2, '.', ''); }
function fc_fmt_bs(float $v): string { return 'Bs ' . number_format($v, 2, '.', ''); }

/**
 * Lo que valen $v dólares BCV pagados en Bs, repartidos en los tramos
 * [[tope, valor], ...] en ese orden. Lo que pasa de todos vale $k. Un
 * $v negativo (vuelto en Bs) vale 1 a 1. Espejo de `_valor` de la app.
 */
function fc_valor_bs(float $v, array $tramos, float $k): float {
    if ($v <= 0) return $v;
    $resto = $v; $valor = 0.0;
    foreach ($tramos as [$tope, $val]) {
        if ($tope <= 0 || $val <= 0) continue;
        $usar = min($resto, $tope);
        $valor += $usar * $val;
        $resto -= $usar;
        if ($resto <= 0) return $valor;
    }
    return $valor + $resto * $k;
}

/** Inversa de fc_valor_bs: dólares BCV que hacen falta para valer $x. */
function fc_inverso_bs(float $x, array $tramos, float $k): float {
    if ($x <= 0) return $x;
    $resto = $x; $v = 0.0;
    foreach ($tramos as [$tope, $val]) {
        if ($tope <= 0 || $val <= 0) continue;
        $cabe = $tope * $val;
        if ($resto <= $cabe) return $v + $resto / $val;
        $resto -= $cabe;
        $v += $tope;
    }
    return $v + $resto / $k;
}

/**
 * El cuadre (espejo de CuadreFactura de lib/factura_cuadre.dart).
 * $lineas: [{financiada, precio_divisa, precio_bcv?, precio_financiadora?,
 * inicial?, ref?, nombre?}], $pagos: [{metodo, monto, es_vuelto?}].
 *
 *  · Un dólar vale un dólar. Los Bs se llevan a dólares BCV (÷ tasa): en
 *    la inicial de una financiadora valen 1 a 1; en el contado valen
 *    divisa/BCV (el precio en Bs del contado es el precio BCV).
 *  · Factura mixta pagada en las dos monedas: no se sabe qué pagó cada
 *    una, así que se valora con los Bs pagando primero el contado
 *    (valor_min) y primero la inicial (valor_max). Cuadra si el objetivo
 *    (contado + inicial) cae entre los dos, con 1 Bs o $0,01 de margen.
 *
 * Devuelve el detalle y `problema` (null si cuadra).
 */
function fc_cuadre(array $lineas, array $pagos, float $tasa, bool $fpb = false): array {
    $div = 0.0; $bcv = 0.0; $ini = 0.0; $fin = 0.0;
    $sinInicial = [];
    $hayFin = false;
    foreach ($lineas as $l) {
        $financiada = fc_verdad($l['financiada'] ?? false);
        $d = (float)($l['precio_divisa'] ?? 0);
        $b = (float)($l['precio_bcv'] ?? 0);
        if ($b <= 0) $b = $d;
        if ($financiada) {
            $hayFin = true;
            $tieneIni = isset($l['inicial']) && is_numeric($l['inicial']) && (float)$l['inicial'] >= 0;
            if (!$tieneIni) $sinInicial[] = (string)($l['nombre'] ?? $l['ref'] ?? '?');
            $i = $tieneIni ? (float)$l['inicial'] : 0.0;
            $ini += $i;
            $pf = (float)($l['precio_financiadora'] ?? 0);
            if ($pf <= 0) $pf = $d;
            $fin += max(0.0, fc_r2($pf - $i));
        } else {
            $div += $d;
            $bcv += $b;
        }
    }
    $usd = 0.0; $bs = 0.0; $malos = [];
    foreach ($pagos as $p) {
        if (!is_array($p)) continue;
        $m = abs((float)($p['monto'] ?? 0));
        $metodo = (string)($p['metodo'] ?? '');
        $moneda = fc_moneda_de_metodo($metodo);
        if (fc_es_vuelto($p)) {
            if (!fc_metodo_permite_vuelto($metodo)) $malos[] = $metodo;
            if ($moneda === 'BS') $bs -= $m; else $usd -= $m;
        } else {
            if ($moneda === 'BS') $bs += $m; else $usd += $m;
        }
    }
    $div = fc_r2($div); $bcv = fc_r2($bcv); $ini = fc_r2($ini);
    $usd = fc_r2($usd); $bs = fc_r2($bs);

    $objUsd = fc_r2($div + $ini);
    $objBs = fc_r2(($bcv + $ini) * $tasa);
    $v = $tasa > 0 ? $bs / $tasa : 0.0;
    $k = ($bcv > 0 && $div > 0) ? $div / $bcv : 1.0;
    $contadoPrimero = [[$bcv, $k], [$ini, 1.0]];
    $inicialPrimero = [[$ini, 1.0], [$bcv, $k]];
    $valorMin = fc_r2($usd + fc_valor_bs($v, $contadoPrimero, $k));
    $valorMax = fc_r2($usd + fc_valor_bs($v, $inicialPrimero, $k));
    $tol = $tasa > 0 ? max(0.01, 1 / $tasa) : 0.01;

    $f = $objUsd - $valorMax;
    $faltaUsd = $f > $tol + 1e-9 ? fc_r2($f) : 0.0;
    $faltaBs = $faltaUsd > 0 ? fc_r2((fc_inverso_bs($objUsd - $usd, $contadoPrimero, $k) - $v) * $tasa) : 0.0;
    $s = $valorMin - $objUsd;
    $sobraUsd = $s > $tol + 1e-9 ? fc_r2($s) : 0.0;
    $sobraBs = $sobraUsd > 0 ? fc_r2(($v - fc_inverso_bs($objUsd - $usd, $contadoPrimero, $k)) * $tasa) : 0.0;

    $problema = null;
    if ($sinInicial) {
        $problema = 'Escriba la inicial aprobada por la financiadora de: ' . implode(', ', $sinInicial) . '.';
    } elseif ($malos) {
        $problema = 'El vuelto solo se da en efectivo o divisas (no por '
            . implode(', ', array_unique($malos)) . ').';
    } elseif (abs($bs) > 0.004 && $tasa <= 0) {
        $problema = 'No hay tasa BCV: no se pueden convertir los pagos en Bs.';
    } elseif ($sobraUsd > 0) {
        $problema = 'El cliente pagó ' . fc_fmt_usd($sobraUsd)
            . ($tasa > 0 ? ' (' . fc_fmt_bs($sobraBs) . ')' : '')
            . ' de más: registre el vuelto en efectivo o divisas.';
    } elseif ($faltaUsd > 0 && !$fpb) {
        $problema = 'Falta cobrar ' . fc_fmt_usd($faltaUsd)
            . ($tasa > 0 ? ' o ' . fc_fmt_bs($faltaBs) : '')
            . ($hayFin ? ' (contado + inicial)' : '') . '.';
    }
    return [
        'objetivo_usd' => $objUsd,
        'objetivo_bs' => $objBs,
        'pagado_usd' => $usd,
        'pagado_bs' => $bs,
        'valor_min' => $valorMin,
        'valor_max' => $valorMax,
        'falta_usd' => $faltaUsd,
        'falta_bs' => $faltaBs,
        'sobra_usd' => $sobraUsd,
        'sobra_bs' => $sobraBs,
        'inicial' => $ini,
        'monto_financiado' => fc_r2($fin),
        'deuda_fpb' => $fpb ? $faltaUsd : 0.0,
        'problema' => $problema,
    ];
}

/** Precio de venta del catálogo: la fila de la tienda, la general o cualquiera. */
function fc_precio_catalogo(PDO $pdo, string $codigo, string $tienda): ?float {
    $st = $pdo->prepare('SELECT precio_venta, tienda FROM productos WHERE codigo = ?'
        . (fc_tiene($pdo, 'productos', 'eliminado_en') ? ' AND eliminado_en IS NULL' : ''));
    $st->execute([$codigo]);
    $filas = $st->fetchAll(PDO::FETCH_ASSOC);
    if (!$filas) return null;
    $general = null;
    foreach ($filas as $f) {
        $t = trim((string)($f['tienda'] ?? ''));
        if ($tienda !== '' && $t === $tienda) return (float)$f['precio_venta'];
        if ($t === '' && $general === null) $general = (float)$f['precio_venta'];
    }
    return $general ?? (float)$filas[0]['precio_venta'];
}

/** Código del producto de un IMEI. */
function fc_codigo_de_imei(PDO $pdo, string $imei): ?string {
    $st = $pdo->prepare('SELECT producto_codigo FROM stock_imei WHERE imei = ? LIMIT 1');
    $st->execute([$imei]);
    $c = $st->fetchColumn();
    return $c === false ? null : (string)$c;
}

function fc_ref_de_entrada($e, string $tipo): string {
    if (is_array($e)) {
        return trim((string)($tipo === 'equipo'
            ? ($e['imei'] ?? '')
            : ($e['codigo'] ?? $e['producto_codigo'] ?? '')));
    }
    return trim((string)$e);
}

/**
 * Repite el cuadre de la app nueva. El precio de contado en divisas lo
 * pone el SERVIDOR (precio de venta del catálogo), no la app. Lanza
 * FacturaCuadreError con un mensaje para el vendedor; devuelve el cuadre.
 */
function fc_validar(PDO $pdo, array $body): array {
    $c = (array)($body['cuadre'] ?? []);
    $lineas = array_values(array_filter((array)($c['lineas'] ?? []), 'is_array'));
    $tienda = trim((string)($body['tienda'] ?? ''));

    // Las líneas del cuadre tienen que ser los productos de la factura.
    $esperadas = [];
    foreach ((array)($body['equipos'] ?? []) as $e) {
        $r = fc_ref_de_entrada($e, 'equipo');
        if ($r !== '') $esperadas[] = "equipo|$r";
    }
    foreach ((array)($body['items'] ?? []) as $i) {
        $r = fc_ref_de_entrada($i, 'item');
        if ($r !== '') $esperadas[] = "item|$r";
    }
    if ($esperadas === []) throw new FacturaCuadreError('La factura no tiene productos.');
    $recibidas = array_map(static fn($l) =>
        ((($l['tipo'] ?? '') === 'equipo') ? 'equipo' : 'item') . '|' . trim((string)($l['ref'] ?? '')), $lineas);
    $a = $esperadas; sort($a);
    $b = $recibidas; sort($b);
    if ($a !== $b) {
        throw new FacturaCuadreError('Los productos de la factura no coinciden con su cuadre. '
            . 'Cierre la factura y vuelva a armarla.');
    }

    foreach ($lineas as &$l) {
        $ref = trim((string)$l['ref']);
        $codigo = ($l['tipo'] ?? '') === 'equipo' ? fc_codigo_de_imei($pdo, $ref) : $ref;
        $precio = $codigo === null ? null : fc_precio_catalogo($pdo, $codigo, $tienda);
        if ($precio === null) {
            throw new FacturaCuadreError("El producto $ref no está en el inventario.");
        }
        $l['precio_divisa'] = $precio;
    }
    unset($l);

    $tasa = (float)($c['tasa_bcv'] ?? $body['tasa_bcv'] ?? 0);
    $fpb = fc_verdad($c['fpb'] ?? false);
    $r = fc_cuadre($lineas, (array)($body['pagos'] ?? []), $tasa, $fpb);
    if ($r['problema'] !== null) throw new FacturaCuadreError($r['problema']);
    return $r;
}

// ────────────────────────────────────────────────────────────────
//  Guardado de los datos nuevos
// ────────────────────────────────────────────────────────────────

/** Columnas nuevas de `facturas` que existen y se aceptan del cuerpo. */
function fc_columnas_cabecera(PDO $pdo, bool $conClave): array {
    $cols = [];
    foreach (['inicial', 'monto_financiado', 'tasa_bcv', 'direccion'] as $c) {
        if (fc_tiene($pdo, 'facturas', $c)) $cols[] = $c;
    }
    if ($conClave && fc_tiene($pdo, 'facturas', 'clave_idempotencia')) $cols[] = 'clave_idempotencia';
    return $cols;
}

/** Columnas nuevas de `factura_pagos` que existen. */
function fc_columnas_pagos(PDO $pdo): array {
    return array_values(array_filter(['moneda', 'monto_usd', 'es_vuelto'],
        static fn($c) => fc_tiene($pdo, 'factura_pagos', $c)));
}

/**
 * Pago de la app nueva: moneda por método, es_vuelto 0/1 y el vuelto en
 * negativo (los reportes que suman pagos lo descuentan solos). A la app
 * vieja no se le toca nada salvo marcar es_vuelto si llegó un negativo.
 */
function fc_normalizar_pago(array $pg, bool $appNueva): array {
    $monto = (float)($pg['monto'] ?? 0);
    $vuelto = fc_es_vuelto($pg);
    if ($vuelto || array_key_exists('es_vuelto', $pg)) $pg['es_vuelto'] = $vuelto ? 1 : 0;
    if (!$appNueva) return $pg;
    if ($vuelto && $monto > 0) $pg['monto'] = -$monto;
    if (empty($pg['moneda'])) $pg['moneda'] = fc_moneda_de_metodo((string)($pg['metodo'] ?? ''));
    $pg['moneda'] = strtoupper((string)$pg['moneda']) === 'BS' ? 'BS' : 'USD';
    if (isset($pg['monto_usd']) && is_numeric($pg['monto_usd'])) {
        $mu = abs((float)$pg['monto_usd']);
        $pg['monto_usd'] = $vuelto ? -$mu : $mu;
    }
    return $pg;
}

/** Precio de la línea que manda la app nueva, o null. */
function fc_precio_de_entrada($e): ?float {
    if (!is_array($e) || !isset($e['precio_unitario']) || !is_numeric($e['precio_unitario'])) return null;
    return fc_r2((float)$e['precio_unitario']);
}

/** Filas actuales de una tabla hija (para conservar datos en el PUT). */
function fc_previos(PDO $pdo, string $tabla, int $facturaId): array {
    try {
        $st = $pdo->prepare("SELECT * FROM $tabla WHERE factura_id = ? ORDER BY id");
        $st->execute([$facturaId]);
        return $st->fetchAll(PDO::FETCH_ASSOC);
    } catch (Throwable $e) {
        return [];
    }
}

/**
 * Después de insertar una línea (equipo o ítem): guarda su precio. Si la
 * entrada no trae precio (PUT de la app vieja), conserva el que tenía la
 * misma línea antes del PUT (emparejada por IMEI o código, en orden).
 */
function fc_linea_insertada(PDO $pdo, string $tabla, int $filaId, $entrada, string $ref, array &$previos): void {
    if (!fc_tiene($pdo, $tabla, 'precio_unitario')) return;
    $precio = fc_precio_de_entrada($entrada);
    $campo = $tabla === 'factura_equipos' ? 'imei' : 'producto_codigo';
    // Consumir el previo emparejado aunque traiga precio nuevo, para que
    // los siguientes con el mismo código se emparejen en orden.
    $previo = null;
    foreach ($previos as $i => $p) {
        if (trim((string)($p[$campo] ?? '')) === $ref) { $previo = $p; unset($previos[$i]); break; }
    }
    if ($precio === null && $previo !== null && $previo['precio_unitario'] !== null) {
        $precio = (float)$previo['precio_unitario'];
    }
    if ($precio === null) return;
    $pdo->prepare("UPDATE $tabla SET precio_unitario = ? WHERE id = ?")->execute([$precio, $filaId]);
}

/**
 * Después de insertar un pago en un PUT: si el cuerpo no trae moneda /
 * monto_usd / es_vuelto (app vieja), conserva los del mismo pago de
 * antes (mismo método, monto y referencia). Un monto negativo siempre
 * queda es_vuelto = 1.
 */
function fc_pago_reinsertado(PDO $pdo, int $filaId, array $pg, array &$previos): void {
    $cols = fc_columnas_pagos($pdo);
    if ($cols === []) return;
    $falta = array_values(array_filter($cols, static fn($c) => !array_key_exists($c, $pg)));
    $set = [];
    if ($falta !== []) {
        foreach ($previos as $i => $p) {
            if (trim((string)($p['metodo'] ?? '')) !== trim((string)($pg['metodo'] ?? ''))) continue;
            if (abs((float)($p['monto'] ?? 0) - (float)($pg['monto'] ?? 0)) > 0.005) continue;
            if (trim((string)($p['referencia'] ?? '')) !== trim((string)($pg['referencia'] ?? ''))) continue;
            foreach ($falta as $c) {
                if (array_key_exists($c, $p) && $p[$c] !== null) $set[$c] = $p[$c];
            }
            unset($previos[$i]);
            break;
        }
    }
    if (in_array('es_vuelto', $cols, true) && (float)($pg['monto'] ?? 0) < 0) $set['es_vuelto'] = 1;
    if ($set === []) return;
    $sql = 'UPDATE factura_pagos SET ' . implode(', ', array_map(static fn($c) => "$c = ?", array_keys($set)))
         . ' WHERE id = ?';
    $pdo->prepare($sql)->execute([...array_values($set), $filaId]);
}

// ────────────────────────────────────────────────────────────────
//  Reintento idempotente
// ────────────────────────────────────────────────────────────────

function fc_clave(array $body): ?string {
    $c = trim((string)($body['clave_idempotencia'] ?? ''));
    return preg_match('/^[A-Za-z0-9_-]{8,64}$/', $c) === 1 ? $c : null;
}

/** Id de la factura viva que ya se guardó con esa clave, o null. */
function fc_factura_de_clave(PDO $pdo, ?string $clave): ?int {
    if ($clave === null || !fc_tiene($pdo, 'facturas', 'clave_idempotencia')) return null;
    $st = $pdo->prepare('SELECT id FROM facturas WHERE clave_idempotencia = ?'
        . (fc_tiene($pdo, 'facturas', 'eliminado_en') ? ' AND eliminado_en IS NULL' : '')
        . ' ORDER BY id LIMIT 1');
    $st->execute([$clave]);
    $id = $st->fetchColumn();
    return $id === false ? null : (int)$id;
}

// ────────────────────────────────────────────────────────────────
//  FPB: la cuenta por cobrar en el servidor
// ────────────────────────────────────────────────────────────────

/** Valida y normaliza el bloque `fpb` {deuda, cuotas[]}. */
function fc_fpb_normalizar(array $fpb): array {
    $deuda = fc_r2((float)($fpb['deuda'] ?? 0));
    if (!is_finite($deuda) || $deuda <= 0) {
        throw new FacturaCuadreError('La deuda FPB tiene que ser mayor que 0.');
    }
    $cuotas = [];
    foreach ((array)($fpb['cuotas'] ?? []) as $c) {
        if (!is_array($c)) continue;
        $numero = (int)($c['numero'] ?? 0);
        $monto = fc_r2((float)($c['monto'] ?? 0));
        $fecha = trim((string)($c['fecha'] ?? ''));
        if ($numero <= 0 || $monto <= 0 || preg_match('/^\d{4}-\d{2}-\d{2}$/', $fecha) !== 1) {
            throw new FacturaCuadreError("La cuota $numero del FPB está incompleta.");
        }
        $cuotas[] = ['numero' => $numero, 'monto' => $monto, 'fecha' => $fecha];
    }
    // Si las cuotas no suman la deuda, se reparten de nuevo en partes
    // iguales (mismas fechas; el centavo que sobra en la última).
    $n = count($cuotas);
    if ($n > 0) {
        $suma = fc_r2(array_sum(array_column($cuotas, 'monto')));
        if (abs($suma - $deuda) >= 0.005) {
            $parte = floor($deuda / $n * 100) / 100;
            foreach ($cuotas as $i => &$c) {
                $c['monto'] = $i === $n - 1 ? fc_r2($deuda - $parte * ($n - 1)) : $parte;
            }
            unset($c);
        }
    }
    return ['deuda' => $deuda, 'cuotas' => $cuotas];
}

/** Insert con solo las columnas que existen. */
function fc_insertar(PDO $pdo, string $tabla, array $datos): int {
    $cols = fc_columnas($pdo, $tabla);
    $datos = array_intersect_key($datos, array_flip($cols));
    $nombres = array_keys($datos);
    $sql = "INSERT INTO $tabla (" . implode(', ', $nombres) . ') VALUES ('
         . implode(', ', array_fill(0, count($nombres), '?')) . ')';
    $pdo->prepare($sql)->execute(array_values($datos));
    return (int)$pdo->lastInsertId();
}

/**
 * Crea (si no existe) la cuenta por cobrar FPB de una factura.
 * Idempotente: una factura, una cuenta.
 */
function fc_fpb_asegurar_cuenta(PDO $pdo, int $facturaId, array $factura): array {
    $fpb = fc_fpb_normalizar((array)($factura['fpb'] ?? []));
    $vivas = fc_tiene($pdo, 'cuentas_cobrar', 'eliminado_en') ? ' AND eliminado_en IS NULL' : '';
    $st = $pdo->prepare("SELECT id, monto_total FROM cuentas_cobrar WHERE factura_id = ?$vivas ORDER BY id LIMIT 1");
    $st->execute([$facturaId]);
    if ($ya = $st->fetch(PDO::FETCH_ASSOC)) {
        return ['id' => (int)$ya['id'], 'creada' => false, 'monto' => (float)$ya['monto_total']];
    }
    $nro = trim((string)($factura['nro_factura'] ?? ''));
    $n = count($fpb['cuotas']);
    $propia = $pdo->inTransaction();
    if (!$propia) $pdo->beginTransaction();
    try {
        $id = fc_insertar($pdo, 'cuentas_cobrar', [
            'cedula'       => (string)($factura['cedula'] ?? ''),
            'nombre'       => (string)($factura['cliente'] ?? ''),
            'telefono'     => (string)($factura['telefono'] ?? ''),
            'correo'       => (string)($factura['correo'] ?? ''),
            'monto_total'  => $fpb['deuda'],
            'financiadora' => trim((string)($factura['fpb']['financiadora'] ?? '')) ?: 'FPB',
            'factura_id'   => $facturaId,
            'nro_factura'  => $nro,
            'tienda'       => (string)($factura['tienda'] ?? ''),
            // El mismo texto que ponía la app: hay pantallas que lo leen.
            'notas'        => 'Generado automáticamente desde factura ' . $nro
                              . ($n > 0 ? " · $n cuota(s)" : ''),
        ]);
        foreach ($fpb['cuotas'] as $c) {
            fc_insertar($pdo, 'cuentas_cobrar_cuotas', [
                'cuenta_id' => $id, 'numero' => $c['numero'], 'monto' => $c['monto'],
                'fecha' => $c['fecha'], 'pagada' => 0,
            ]);
        }
        if (!$propia) $pdo->commit();
    } catch (Throwable $e) {
        if (!$propia && $pdo->inTransaction()) $pdo->rollBack();
        throw $e;
    }
    return ['id' => $id, 'creada' => true, 'monto' => $fpb['deuda']];
}

/**
 * Agrega a la respuesta de una factura recién guardada el resultado de
 * su cuenta FPB (`cxc` o `cxc_error`). Nunca lanza: la factura YA está
 * guardada y la app tiene que saberlo para avisar y reintentar.
 */
function fc_con_cuenta_fpb(PDO $pdo, int $facturaId, array $factura, array $respuesta): array {
    if (empty($factura['fpb']) || !is_array($factura['fpb'])) return $respuesta;
    try {
        $respuesta['cxc'] = fc_fpb_asegurar_cuenta($pdo, $facturaId, $factura);
    } catch (Throwable $e) {
        error_log("[fpb] factura $facturaId sin cuenta por cobrar: " . $e->getMessage());
        $respuesta['cxc_error'] = $e instanceof FacturaCuadreError
            ? $e->getMessage()
            : 'No se pudo crear la cuenta por cobrar.';
    }
    return $respuesta;
}

/**
 * Al eliminar una factura: su cuenta por cobrar (la enlazada por
 * factura_id) se anula si no tiene ningún abono ni cuota pagada; si los
 * tiene, se CONSERVA con una nota de aviso — borrar un pago registrado
 * no lo decide el sistema.
 */
function fc_anular_cxc_de_factura(PDO $pdo, int $facturaId): array {
    $r = ['eliminadas' => [], 'conservadas' => []];
    if (!fc_tiene($pdo, 'cuentas_cobrar', 'factura_id')) return $r;
    $vivas = fc_tiene($pdo, 'cuentas_cobrar', 'eliminado_en') ? ' AND eliminado_en IS NULL' : '';
    $st = $pdo->prepare("SELECT id, notas FROM cuentas_cobrar WHERE factura_id = ?$vivas");
    $st->execute([$facturaId]);
    foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $cta) {
        $id = (int)$cta['id'];
        $pagos = $pdo->prepare('SELECT COUNT(*) FROM cuentas_cobrar_pagos WHERE cuenta_id = ?');
        $pagos->execute([$id]);
        $pagadas = $pdo->prepare('SELECT COUNT(*) FROM cuentas_cobrar_cuotas WHERE cuenta_id = ? AND pagada = 1');
        $pagadas->execute([$id]);
        if ((int)$pagos->fetchColumn() + (int)$pagadas->fetchColumn() > 0) {
            $nota = trim((string)($cta['notas'] ?? ''));
            $pdo->prepare('UPDATE cuentas_cobrar SET notas = ? WHERE id = ?')->execute([
                ($nota === '' ? '' : "$nota · ") . 'AVISO: la factura de esta deuda se eliminó el '
                . date('d/m/Y') . '; tiene abonos, revisar a mano', $id]);
            $r['conservadas'][] = $id;
            continue;
        }
        $pdo->prepare('DELETE FROM cuentas_cobrar_cuotas WHERE cuenta_id = ?')->execute([$id]);
        if ($vivas !== '') {
            $pdo->prepare('UPDATE cuentas_cobrar SET eliminado_en = CURRENT_TIMESTAMP WHERE id = ?')->execute([$id]);
        } else {
            $pdo->prepare('DELETE FROM cuentas_cobrar WHERE id = ?')->execute([$id]);
        }
        $r['eliminadas'][] = $id;
    }
    if ($r['eliminadas'] || $r['conservadas']) {
        error_log(sprintf('[fpb] factura %d eliminada: cuentas anuladas [%s], conservadas con aviso [%s]',
            $facturaId, implode(',', $r['eliminadas']), implode(',', $r['conservadas'])));
    }
    return $r;
}

// ────────────────────────────────────────────────────────────────
//  Búsqueda en TODO el historial (GET facturas?q=)
// ────────────────────────────────────────────────────────────────

/**
 * Condición SQL y argumentos para buscar `q` en nro_factura, cliente,
 * cédula (sin V/E, puntos ni guiones), vendedor y teléfono, más el id
 * exacto. Sin límite de fecha: la carga normal trae las 1000 más
 * recientes, la búsqueda mira la tabla completa.
 */
function fc_condicion_busqueda(string $q): array {
    $q = trim($q);
    $cond = [];
    $args = [];
    $like = '%' . $q . '%';
    foreach (['nro_factura', 'cliente', 'cedula', 'vendedor', 'telefono'] as $col) {
        $cond[] = "$col LIKE ?";
        $args[] = $like;
    }
    // Acentos plegados a mano: no depender del cotejamiento de la columna.
    $acentos = ['Á' => 'A', 'É' => 'E', 'Í' => 'I', 'Ó' => 'O', 'Ú' => 'U', 'Ü' => 'U', 'Ñ' => 'N'];
    $plegar = static function (string $col) use ($acentos): string {
        $sql = "UPPER($col)";
        foreach ($acentos as $de => $a) $sql = "REPLACE($sql, '$de', '$a')";
        return $sql;
    };
    $qPlano = strtr(mb_strtoupper($q, 'UTF-8'), $acentos);
    foreach (['cliente', 'vendedor'] as $col) {
        $cond[] = $plegar($col) . ' LIKE ?';
        $args[] = '%' . $qPlano . '%';
    }
    $qCed = strtoupper((string)preg_replace('/[VEve\.\-\s]/', '', $q));
    if ($qCed !== '') {
        $cond[] = "REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(UPPER(cedula), 'V', ''), 'E', ''), '.', ''), '-', ''), ' ', '') LIKE ?";
        $args[] = '%' . $qCed . '%';
    }
    if (ctype_digit($q)) {
        $cond[] = 'id = ?';
        $args[] = (int)$q;
    }
    return ['(' . implode(' OR ', $cond) . ')', $args];
}
