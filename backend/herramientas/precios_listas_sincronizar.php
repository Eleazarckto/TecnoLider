<?php
// ============================================================================
//  precios_listas_sincronizar.php — Precios desde el costo, por consola
//
//  SOLO línea de comandos (desde la web responde 404). Se corre en el
//  servidor, desde esta carpeta, y usa la conexión del backend
//  (../lib/db.php):
//
//    php precios_listas_sincronizar.php --estado
//        Listas, su modo (manual/costo), su % y los interruptores.
//
//    php precios_listas_sincronizar.php --prueba
//        Recalcula TODAS las listas en modo costo dentro de una transacción
//        y la DESHACE: dice cuántos precios cambiarían en cada una. Con
//        todas las listas en manual (como queda al desplegar) da 0.
//
//    php precios_listas_sincronizar.php --sugeridos
//        El % sobre el costo (y la tasa de las listas en Bs) que mantiene
//        los precios de HOY: la mediana de cada lista. No cambia nada.
//
//    php precios_listas_sincronizar.php --activar --lista 12 --pct 25 [--prueba]
//        [--tasa 950] [--monto 0] [--redondear] [--sin-redondear]
//        Pone la lista 12 en modo costo con 25 % y la recalcula (con las
//        listas que dependen de ella). --tasa: en una lista en Bs es su
//        tasa fija; en una lista en $ es la «tasa manual para llevar a Bs»
//        de sus listas en Bs. Con --prueba es un ENSAYO: informa y deshace.
//        Sin --prueba guarda antes un respaldo (tabla
//        listas_precios_respaldos y ~/respaldo_listas_<fecha>.json, fuera
//        de la web) y enciende `precios_auto_activo`.
//
//    php precios_listas_sincronizar.php --revertir --lista 12 [--respaldo N]
//        Deja la lista como estaba antes de su última activación (o la del
//        respaldo N) y en modo manual.
//
//    php precios_listas_sincronizar.php --desactivar --lista 12
//        Vuelve la lista a manual SIN tocar sus precios.
//
//    php precios_listas_sincronizar.php --interruptor precios_auto_activo=0
//        Enciende/apaga un interruptor (precios_auto_activo,
//        listas_auto_agregar, precio_venta_desde_lista).
//
//  Pruebas: PRECIOS_SQLITE=archivo.db usa SQLite en vez de la base real.
// ============================================================================
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }

require __DIR__ . '/../lib/precios_listas.php';

$sqlite = getenv('PRECIOS_SQLITE') ?: '';
if ($sqlite !== '') {
    $pdo = new PDO('sqlite:' . $sqlite);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);
} else {
    require __DIR__ . '/../lib/db.php';
    $pdo = db();
}

$arg = static function (string $op) use ($argv): ?string {
    $i = array_search($op, $argv, true);
    return ($i === false || !isset($argv[$i + 1])) ? null : (string)$argv[$i + 1];
};
$hay = static function (string $op) use ($argv): bool { return in_array($op, $argv, true); };
$fmt = static function ($v): string { return $v === null ? '—' : number_format((float)$v, 2, ',', '.'); };

function mediana(array $v): ?float {
    if (!$v) return null;
    sort($v);
    $n = count($v);
    return $n % 2 ? $v[intdiv($n, 2)] : ($v[$n / 2 - 1] + $v[$n / 2]) / 2;
}

/** Primer precio real (columna no virtual) de cada producto de una lista. */
function preciosDeLista(array $lista): array {
    [$reales] = plColumnas(plJson($lista['columnas'] ?? '[]'));
    $out = [];
    if ($reales === []) return $out;
    foreach (plJson($lista['items'] ?? '[]') as $it) {
        foreach ((array)($it['valores'] ?? []) as $v) {
            if ((string)($v['columna_nombre'] ?? '') === $reales[0]) {
                $out[(string)$it['producto_codigo']] = (float)$v['precio'];
            }
        }
    }
    return $out;
}

function imprimirInformes(array $informes, callable $fmt): int {
    $total = 0;
    foreach ($informes as $inf) {
        $total += (int)$inf['precios'];
        printf("  [%d] %s: %d precio(s) cambian en %d producto(s) · %d entran · %d inicial/cuota fijas se borran\n",
            $inf['lista_id'], $inf['nombre'], $inf['precios'], $inf['items'], $inf['agregados'], $inf['montos_fijos']);
        foreach ($inf['ejemplos'] as $e) {
            printf("      %-14s %-30s %12s → %12s\n", $e['codigo'],
                function_exists('mb_substr') ? mb_substr((string)$e['nombre'], 0, 30) : substr((string)$e['nombre'], 0, 30),
                $fmt($e['antes']), $fmt($e['despues']));
        }
    }
    return $total;
}

$listaId = (int)($arg('--lista') ?? 0);

try {
    // ── Interruptor ──
    if (($i = $arg('--interruptor')) !== null) {
        [$clave, $valor] = array_pad(explode('=', $i, 2), 2, '');
        plAsegurarConfiguracion($pdo);
        plPonerInterruptor($pdo, trim($clave), trim($valor) === '1');
        echo "Interruptor $clave = " . (trim($valor) === '1' ? '1' : '0') . "\n";
        exit(0);
    }

    // ── Estado ──
    if ($hay('--estado')) {
        foreach (PL_INTERRUPTORES as $k) echo "  $k = " . (plInterruptor($pdo, $k) ? '1' : '0') . "\n";
        foreach (plListas($pdo) as $l) {
            printf("  [%d] %-28s %-4s %-6s modo=%-6s %% venta (app)=%s  %% costo=%s  monto=%s  tasa=%s%s  tasa_bs=%s  redondeo=%s  reglas=%d\n",
                $l['id'], $l['nombre'], plEsBs($l) ? 'Bs' : '$', plEsFinanciamiento($l) ? 'financ' : '',
                $l['modo_precios'] ?? 'manual', $fmt($l['porcentaje_adicional'] ?? 0), $fmt($l['pct_sobre_costo'] ?? 0),
                $fmt($l['monto_adicional_dolares'] ?? 0), $fmt($l['tasa_del_dia'] ?? 0),
                (int)($l['tasa_fija'] ?? 0) === 1 ? ' (fija)' : '', $fmt($l['tasa_bs'] ?? 0),
                plRedondeaArriba($l) ? 'sí' : 'no', count(plReglas($l)));
        }
        exit(0);
    }

    // ── Sugeridos ──
    if ($hay('--sugeridos')) {
        $listas = plListas($pdo);
        $cat = plCatalogo($pdo);
        $precios = [];
        foreach ($listas as $l) $precios[(int)$l['id']] = preciosDeLista($l);
        // Lista Divisas pareja sin exigir modo costo (para comparar precios de hoy).
        $parDe = static function (array $lb) use ($listas): ?array {
            $todas = array_map(static function ($l) { $l['modo_precios'] = 'costo'; return $l; }, $listas);
            $lb['modo_precios'] = 'costo';
            return plParDivisas($lb, $todas);
        };
        echo "Lo que mantiene los precios de hoy (mediana de cada lista):\n";
        foreach ($listas as $l) {
            $id = (int)$l['id'];
            $monto = (float)($l['monto_adicional_dolares'] ?? 0);
            if (plEsBs($l) && !plEsFinanciamiento($l)) {
                $par = $parDe($l);
                if ($par === null) { echo "  [$id] {$l['nombre']}: sin lista Divisas pareja\n"; continue; }
                $tasas = [];
                foreach ($precios[$id] as $c => $p) {
                    $d = $precios[(int)$par['id']][$c] ?? 0;
                    if ($d > 0 && $p > 0) $tasas[] = $p / $d;
                }
                $m = mediana($tasas);
                printf("  [%d] %s = «%s» × %s  → tasa manual sugerida (--tasa en la lista %d): %s (%d productos)\n",
                    $id, $l['nombre'], $par['nombre'], $fmt($m), (int)$par['id'], $fmt($m), count($tasas));
                continue;
            }
            $ratios = [];
            foreach ($precios[$id] as $c => $p) {
                $prod = $cat[$c] ?? null;
                if ($prod === null || $p <= 0) continue;
                if (plEsFinanciamiento($l)) {
                    // Sobre el precio de venta: su precio en la lista Divisas que le toca.
                    $venta = null;
                    foreach ($listas as $d) {
                        if (plEsBs($d) || plEsFinanciamiento($d)) continue;
                        if (!plLeCorresponde($d, $prod['categoria'], $prod['marca'])) continue;
                        if (isset($precios[(int)$d['id']][$c])) { $venta = $precios[(int)$d['id']][$c]; break; }
                    }
                    $base = $venta ?? $prod['precio_costo'];
                } else {
                    $base = $prod['precio_costo'];
                }
                if ($base + $monto > 0) $ratios[] = $p / ($base + $monto);
            }
            $m = mediana($ratios);
            if ($m === null) { echo "  [$id] {$l['nombre']}: sin productos con costo\n"; continue; }
            sort($ratios);
            $q1 = $ratios[intdiv(count($ratios), 4)];
            $q3 = $ratios[intdiv(count($ratios) * 3, 4)];
            printf("  [%d] %s: --pct %s  (la mitad entre %s %% y %s %%; %d productos; %s)\n",
                $id, $l['nombre'], number_format(($m - 1) * 100, 2, '.', ''), $fmt(($q1 - 1) * 100),
                $fmt(($q3 - 1) * 100), count($ratios),
                plEsFinanciamiento($l) ? 'sobre el precio de venta' : 'sobre el costo');
        }
        echo "\nNo se cambió nada. Para probar: --activar --lista ID --pct X --prueba\n";
        exit(0);
    }

    // ── Revertir / desactivar ──
    if ($hay('--revertir')) {
        if ($listaId <= 0) throw new RuntimeException('Falta --lista ID');
        $r = $arg('--respaldo');
        $ok = plRevertir($pdo, $listaId, $r === null ? null : (int)$r);
        echo $ok ? "Lista $listaId restaurada desde su respaldo y en modo manual.\n"
                 : "No hay respaldo para la lista $listaId.\n";
        exit($ok ? 0 : 1);
    }
    if ($hay('--desactivar')) {
        if ($listaId <= 0) throw new RuntimeException('Falta --lista ID');
        plDesactivarCosto($pdo, $listaId);
        echo "Lista $listaId en modo manual (sus precios quedan como están).\n";
        exit(0);
    }

    // ── Activar (o ensayar la activación) ──
    if ($hay('--activar')) {
        if ($listaId <= 0) throw new RuntimeException('Falta --lista ID');
        $pct = $arg('--pct');
        if ($pct === null || !is_numeric($pct)) throw new RuntimeException('Falta --pct X');
        $lista = null;
        foreach (plListas($pdo) as $l) if ((int)$l['id'] === $listaId) $lista = $l;
        if ($lista === null) throw new RuntimeException("La lista $listaId no existe");
        $config = ['pct_sobre_costo' => (float)$pct];
        if (($t = $arg('--tasa')) !== null && is_numeric($t)) {
            if (plEsBs($lista)) { $config['tasa_fija'] = 1; $config['tasa_del_dia'] = (float)$t; }
            else $config['tasa_bs'] = (float)$t;
        }
        if (($m = $arg('--monto')) !== null && is_numeric($m)) $config['monto_adicional_dolares'] = (float)$m;
        if ($hay('--redondear')) $config['redondear_arriba'] = 1;
        if ($hay('--sin-redondear')) $config['redondear_arriba'] = 0;
        $prueba = $hay('--prueba');
        if (!$prueba) {
            // Respaldo en archivo, fuera de la web (además de la tabla).
            $dir = getenv('HOME') ?: sys_get_temp_dir();
            $archivo = $dir . '/respaldo_listas_' . date('Ymd_His') . '.json';
            file_put_contents($archivo, json_encode(plListas($pdo), JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
            echo "Respaldo de todas las listas en $archivo\n";
        }
        $res = plActivarCosto($pdo, $listaId, $config, $prueba, 'consola');
        echo ($prueba ? "ENSAYO" : "ACTIVADA") . ": «{$lista['nombre']}» desde el costo con " . json_encode($config) . "\n";
        $total = imprimirInformes($res['informes'], $fmt);
        echo "Total: $total precio(s) " . ($prueba ? "cambiarían. No se guardó nada.\n"
            : "cambiaron. Respaldo(s) en la tabla: " . implode(', ', $res['respaldos']) . "\n");
        exit(0);
    }

    // ── Prueba / recálculo de todas las listas en modo costo ──
    if ($hay('--prueba') || $hay('--recalcular')) {
        $prueba = !$hay('--recalcular') || $hay('--prueba');
        $pdo->beginTransaction();
        $informes = plRecalcularTodas($pdo);
        echo ($prueba ? "ENSAYO" : "RECALCULADO") . ': ' . count($informes) . " lista(s) en modo costo.\n";
        $total = imprimirInformes($informes, $fmt);
        if ($prueba) { $pdo->rollBack(); echo "Total: $total precio(s) cambiarían. No se guardó nada.\n"; }
        else { $pdo->commit(); echo "Total: $total precio(s) cambiaron.\n"; }
        exit(0);
    }

    fwrite(STDERR, "Uso: ver el encabezado de este archivo (--estado, --prueba, --sugeridos, --activar, --revertir).\n");
    exit(2);
} catch (Throwable $e) {
    if ($pdo->inTransaction()) $pdo->rollBack();
    fwrite(STDERR, 'ERROR, no se cambió nada: ' . $e->getMessage() . "\n");
    exit(1);
}
