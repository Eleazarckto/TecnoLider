<?php
// Endpoint: /api.php?resource=facturas
//
// FacturaModel.toApiMap envía:
//   nro_factura, cedula, cliente, telefono, vendedor, tienda, fecha, total
//   equipos[] = puede venir como:
//              · lista de strings (IMEIs)  ← formato viejo
//              · lista de objetos {imei, vendedor}  ← formato nuevo
//   items[]   = puede venir como:
//              · lista de strings (códigos)  ← formato viejo
//              · lista de objetos {codigo, vendedor}  ← formato nuevo
//   pagos[]   = [{metodo, tipo, financiador, monto, numero_cuotas, monto_cuota, ...}]
//
// HISTORIAL DE BUGS RESUELTOS:
//   1) Las cuotas del financiamiento no aparecían en la factura porque
//      la whitelist de columnas de `factura_pagos` no incluía
//      numero_cuotas, monto_cuota, tasa_cambio ni nombre_lista.
//      Los datos que el vendedor tipeaba llegaban al backend pero eran
//      descartados silenciosamente por la función insertar().
//   2) Las comisiones caían al creador de la factura porque el INSERT
//      en factura_equipos y factura_items solo guardaba imei/codigo,
//      descartando el nombre del vendedor asignado a cada producto.
//      La app luego calculaba comisiones con vendedor vacío y caía al
//      creador. Ahora se guarda el vendedor por producto.

//   3) (oct-2026) Cuadre obligatorio, moneda por pago, vuelto, FPB en el
//      servidor, reintento sin duplicar y búsqueda en todo el historial:
//      ver lib/factura_cuadre.php. La app 1.0.17 no manda nada de eso y
//      factura exactamente igual que antes.

require_once __DIR__ . '/../lib/factura_cuadre.php';

$metodo = $_SERVER['REQUEST_METHOD'];
$id     = get_param('id');

$columnasCab = ['nro_factura', 'cedula', 'cliente', 'telefono',
                'vendedor', 'tienda', 'fecha', 'total'];

// ────────────────────────────────────────────────────────────────
//  Whitelist de columnas de la tabla `factura_pagos`.
//  Definida UNA sola vez arriba y reutilizada en POST y PUT
//  para que no se desincronicen (bug histórico: cambiar una lista
//  y olvidarse la otra dejaba pagos rotos según el método).
// ────────────────────────────────────────────────────────────────
$colsPagos = [
    'factura_id', 'metodo', 'tipo', 'financiador', 'financiadora', 'monto',
    'banco_destino', 'banco_origen', 'referencia',
    'cedula_pagador', 'telefono_pagador', 'telefono_destino',
    'fecha_pago', 'es_inicial', 'conciliado_bdv', 'conciliado_codigo',
    'conciliado_mensaje',
    // ── Financiamiento (cuotas) ──
    'numero_cuotas', 'monto_cuota', 'tasa_cambio', 'nombre_lista',
];

// Normaliza un pago: traduce nombres alternativos y convierte tipos
// para que coincida con el schema MySQL.
function _normalizar_pago(array $pg, int $facturaId): array {
    // Mapeo: la app envía codigo_conciliacion / mensaje_conciliacion
    // pero el schema usa conciliado_codigo / conciliado_mensaje
    if (isset($pg['codigo_conciliacion']) && !isset($pg['conciliado_codigo'])) {
        $pg['conciliado_codigo'] = $pg['codigo_conciliacion'];
    }
    if (isset($pg['mensaje_conciliacion']) && !isset($pg['conciliado_mensaje'])) {
        $pg['conciliado_mensaje'] = $pg['mensaje_conciliacion'];
    }
    // Convertir conciliado_bdv (bool) a 1/0/null
    if (isset($pg['conciliado_bdv'])) {
        if (is_bool($pg['conciliado_bdv'])) {
            $pg['conciliado_bdv'] = $pg['conciliado_bdv'] ? 1 : 0;
        } elseif ($pg['conciliado_bdv'] === null) {
            $pg['conciliado_bdv'] = null;
        }
    }
    // conciliado_codigo viene como int desde la app — lo convertimos a string
    if (isset($pg['conciliado_codigo']) && is_numeric($pg['conciliado_codigo'])) {
        $pg['conciliado_codigo'] = (string) $pg['conciliado_codigo'];
    }
    // es_inicial: la app lo envía como booleano — MySQL espera 0/1.
    if (isset($pg['es_inicial'])) {
        $pg['es_inicial'] = ($pg['es_inicial'] === true
            || $pg['es_inicial'] === 1
            || $pg['es_inicial'] === '1'
            || $pg['es_inicial'] === 'true') ? 1 : 0;
    } else {
        $pg['es_inicial'] = 0;
    }

    // ── Normalización de campos de financiamiento (cuotas) ──
    if (isset($pg['numero_cuotas'])) {
        $n = $pg['numero_cuotas'];
        if ($n === '' || $n === null) {
            $pg['numero_cuotas'] = null;
        } else {
            $n = (int) $n;
            $pg['numero_cuotas'] = $n > 0 ? $n : null;
        }
    }
    if (isset($pg['monto_cuota'])) {
        $m = $pg['monto_cuota'];
        if ($m === '' || $m === null) {
            $pg['monto_cuota'] = null;
        } else {
            $m = (float) $m;
            $pg['monto_cuota'] = $m > 0 ? $m : null;
        }
    }
    if (isset($pg['tasa_cambio'])) {
        $t = $pg['tasa_cambio'];
        $pg['tasa_cambio'] = ($t === '' || $t === null) ? null : (float) $t;
    }
    if (isset($pg['nombre_lista'])) {
        $nl = trim((string) $pg['nombre_lista']);
        $pg['nombre_lista'] = $nl === '' ? null : $nl;
    }

    $pg['factura_id'] = $facturaId;
    $pg['monto']      = (float) ($pg['monto'] ?? 0);
    $pg['metodo']     = (string) ($pg['metodo'] ?? '');
    $pg['tipo']       = (string) ($pg['tipo'] ?? '');
    if (!isset($pg['financiador']) || $pg['financiador'] === null) $pg['financiador']  = '';
    if (!isset($pg['financiadora']) || $pg['financiadora'] === null) $pg['financiadora'] = '';
    return $pg;
}

// ────────────────────────────────────────────────────────────────
//  Helpers para extraer imei/codigo + vendedor sin importar si
//  el frontend los envía como string o como objeto.
// ────────────────────────────────────────────────────────────────

/// Devuelve [imei, vendedor]. Si el entrante es string, vendedor = ''.
function _parse_equipo($e): array {
    if (is_array($e)) {
        $imei = trim((string) ($e['imei'] ?? ''));
        $vend = trim((string) ($e['vendedor'] ?? ''));
        return [$imei, $vend];
    }
    return [trim((string) $e), ''];
}

/// Devuelve [codigo, vendedor]. Si el entrante es string, vendedor = ''.
function _parse_item($it): array {
    if (is_array($it)) {
        $cod  = trim((string) ($it['codigo']
                            ?? $it['producto_codigo']
                            ?? ''));
        $vend = trim((string) ($it['vendedor'] ?? ''));
        return [$cod, $vend];
    }
    return [trim((string) $it), ''];
}

if ($metodo === 'GET') {
    if ($id !== null) {
        $stmt = db()->prepare("SELECT * FROM facturas WHERE id = ? AND eliminado_en IS NULL");
        $stmt->execute([$id]);
        $factura = $stmt->fetch();
        if (!$factura) json_error('No encontrada', 404);

        // Devolver equipos e items con TODOS los campos (incluyendo vendedor)
        // para que la app pueda armar los mapas vendedorPorImei /
        // vendedorPorCodigo y calcular comisiones correctas.
        $stmt = db()->prepare("SELECT * FROM factura_equipos WHERE factura_id = ?");
        $stmt->execute([$id]);
        $factura['equipos'] = $stmt->fetchAll();

        $stmt = db()->prepare("SELECT * FROM factura_items WHERE factura_id = ?");
        $stmt->execute([$id]);
        $factura['items'] = $stmt->fetchAll();

        $stmt = db()->prepare("SELECT * FROM factura_pagos WHERE factura_id = ?");
        $stmt->execute([$id]);
        $factura['pagos'] = $stmt->fetchAll();

        json_response($factura);
    }

    // Listar con relaciones hidratadas
    $sql = "SELECT * FROM facturas WHERE eliminado_en IS NULL";
    $params = [];
    foreach (['vendedor', 'tienda', 'cedula', 'nro_factura'] as $col) {
        $val = get_param($col);
        if ($val) { $sql .= " AND $col = ?"; $params[] = $val; }
    }
    $desde = get_param('desde');
    $hasta = get_param('hasta');
    if ($desde) { $sql .= " AND fecha >= ?"; $params[] = $desde; }
    if ($hasta) { $sql .= " AND fecha <= ?"; $params[] = $hasta; }
    // Búsqueda en TODO el historial (?q=texto): la carga normal trae las
    // 1000 más recientes; la búsqueda no tiene límite de fecha.
    $q = get_param('q');
    if ($q !== null && trim((string)$q) !== '') {
        [$condQ, $argsQ] = fc_condicion_busqueda((string)$q);
        $sql .= " AND $condQ";
        $params = array_merge($params, $argsQ);
    }
    $sql .= " ORDER BY id DESC LIMIT 1000";

    $stmt = db()->prepare($sql);
    $stmt->execute($params);
    $facturas = $stmt->fetchAll();

    if (!empty($facturas)) {
        $ids = array_column($facturas, 'id');
        $ph  = implode(',', array_fill(0, count($ids), '?'));

        // TRAER TODAS LAS COLUMNAS (incluye `vendedor`) — antes solo
        // se traía imei / producto_codigo y por eso la comisión caía
        // al creador de la factura al no tener el vendedor por producto.
        $stmt = db()->prepare("SELECT * FROM factura_equipos WHERE factura_id IN ($ph)");
        $stmt->execute($ids);
        $equiposByF = [];
        foreach ($stmt->fetchAll() as $e) { $equiposByF[$e['factura_id']][] = $e; }

        $stmt = db()->prepare("SELECT * FROM factura_items WHERE factura_id IN ($ph)");
        $stmt->execute($ids);
        $itemsByF = [];
        foreach ($stmt->fetchAll() as $it) { $itemsByF[$it['factura_id']][] = $it; }

        $stmt = db()->prepare("SELECT * FROM factura_pagos WHERE factura_id IN ($ph)");
        $stmt->execute($ids);
        $pagosByF = [];
        foreach ($stmt->fetchAll() as $p) { $pagosByF[$p['factura_id']][] = $p; }

        foreach ($facturas as &$f) {
            $f['equipos'] = $equiposByF[$f['id']] ?? [];
            $f['items']   = $itemsByF[$f['id']]   ?? [];
            $f['pagos']   = $pagosByF[$f['id']]   ?? [];
        }
    }

    json_response($facturas);
}

if ($metodo === 'POST') {
    $body = json_body();

    if (empty($body['nro_factura'])) json_error('Falta nro_factura', 400);
    if (empty($body['cliente']))     json_error('Falta nombre del cliente', 400);
    if (empty($body['vendedor']))    json_error('Falta vendedor', 400);
    if (empty($body['tienda']))      json_error('Falta tienda', 400);
    if (empty($body['fecha']))       json_error('Falta fecha', 400);

    // ── Facturación nueva (lib/factura_cuadre.php) ──
    // Esquema FUERA de la transacción: un ALTER en MySQL la cerraría.
    fc_asegurar_esquema(db());
    $appNueva  = fc_es_app_nueva($body);
    $flagFc    = fc_flag_activo(db());
    // Reintento de una factura ya guardada (misma clave): se devuelve la
    // existente en vez de crear otra.
    $claveIdem = fc_clave($body);
    $idPrevio  = fc_factura_de_clave(db(), $claveIdem);
    if ($idPrevio !== null) {
        $resp = ['ok' => true, 'id' => $idPrevio, 'ya_existia' => true];
        if ($flagFc) $resp = fc_con_cuenta_fpb(db(), $idPrevio, $body, $resp);
        json_response($resp, 200);
    }
    if ($claveIdem === null) unset($body['clave_idempotencia']);
    else $body['clave_idempotencia'] = $claveIdem;
    // Cuadre en el servidor: solo con la llave encendida y solo para la
    // app nueva (la que manda el bloque `cuadre`).
    if ($appNueva && $flagFc) {
        try {
            $rc = fc_validar(db(), $body);
            $body['inicial'] = $rc['inicial'];
            $body['monto_financiado'] = $rc['monto_financiado'];
        } catch (FacturaCuadreError $e) {
            json_error($e->getMessage(), 422);
        }
    }
    $colsCabPost   = array_merge($columnasCab, fc_columnas_cabecera(db(), true));
    $colsPagosPost = array_merge($colsPagos, fc_columnas_pagos(db()));
    $sinPrevios    = [];

    db()->beginTransaction();
    try {
        $facturaData = filtrar_columnas($body, $colsCabPost);
        foreach (['cedula', 'telefono'] as $col) {
            if (!isset($facturaData[$col]) || $facturaData[$col] === null) {
                $facturaData[$col] = '';
            }
        }
        $facturaData['total'] = (float) ($facturaData['total'] ?? 0);
        $idF = insertar('facturas', $facturaData, $colsCabPost);

        // ── equipos ──
        // Guardar imei + vendedor asignado. Si el vendedor no vino
        // (formato viejo), se guarda vacío — el módulo de comisiones
        // interpreta vacío como "sin asignación" y NO paga a nadie.
        $stmtEq = db()->prepare(
            "INSERT INTO factura_equipos (factura_id, imei, vendedor) VALUES (?, ?, ?)"
        );
        $stmtSt = db()->prepare(
            "UPDATE stock_imei SET vendido = 1, fecha_venta = NOW(), factura_id = ?
             WHERE imei = ? AND vendido = 0"
        );
        foreach (($body['equipos'] ?? []) as $entrada) {
            [$imei, $vend] = _parse_equipo($entrada);
            if ($imei === '') continue;
            $stmtEq->execute([$idF, $imei, $vend]);
            fc_linea_insertada(db(), 'factura_equipos', (int)db()->lastInsertId(), $entrada, $imei, $sinPrevios);
            $stmtSt->execute([$idF, $imei]);
        }

        // ── items ──
        // Igual que equipos: se guarda vendedor asignado.
        $stmtIt = db()->prepare(
            "INSERT INTO factura_items (factura_id, producto_codigo, cantidad, vendedor)
             VALUES (?, ?, 1, ?)"
        );
        $stmtPr = db()->prepare(
            "UPDATE productos SET stock_manual = GREATEST(0, stock_manual - 1) WHERE codigo = ?"
        );
        foreach (($body['items'] ?? []) as $entrada) {
            [$cod, $vend] = _parse_item($entrada);
            if ($cod === '') continue;
            $stmtIt->execute([$idF, $cod, $vend]);
            fc_linea_insertada(db(), 'factura_items', (int)db()->lastInsertId(), $entrada, $cod, $sinPrevios);
            $stmtPr->execute([$cod]);
        }

        // ── pagos ──
        foreach (($body['pagos'] ?? []) as $pg) {
            if (!is_array($pg)) continue;
            $pg = fc_normalizar_pago(_normalizar_pago($pg, $idF), $appNueva);
            insertar('factura_pagos', $pg, $colsPagosPost);
        }

        db()->commit();
        $resp = ['ok' => true, 'id' => $idF];
        // FPB: la cuenta por cobrar la crea el servidor (con la llave).
        if ($flagFc) $resp = fc_con_cuenta_fpb(db(), $idF, $body, $resp);
        json_response($resp, 201);
    } catch (Throwable $e) {
        if (db()->inTransaction()) db()->rollBack();
        // Dos envíos simultáneos de la MISMA factura: el segundo choca con
        // el índice único de la clave; se devuelve la que ganó.
        $idGanador = fc_factura_de_clave(db(), $claveIdem);
        if ($idGanador !== null) {
            json_response(['ok' => true, 'id' => $idGanador, 'ya_existia' => true], 200);
        }
        json_error(
            'Error al guardar factura: ' . $e->getMessage(),
            500,
            ['sql_state' => method_exists($e, 'errorInfo') ? null : null]
        );
    }
}

if ($metodo === 'PUT') {
    if ($id === null) json_error('Falta id', 400);
    $body = json_body();

    // Esquema fuera de la transacción. El PUT borra y reinserta líneas y
    // pagos: lo que la app vieja no conoce (precio por línea, moneda,
    // monto_usd, es_vuelto) se conserva emparejando con lo de antes.
    fc_asegurar_esquema(db());
    $appNueva   = fc_es_app_nueva($body);
    unset($body['clave_idempotencia']);
    $colsCabPut   = array_merge($columnasCab, fc_columnas_cabecera(db(), false));
    $colsPagosPut = array_merge($colsPagos, fc_columnas_pagos(db()));

    db()->beginTransaction();
    try {
        actualizar('facturas', $id, filtrar_columnas($body, $colsCabPut), $colsCabPut);

        // ── equipos ──
        if (isset($body['equipos'])) {
            $prevEq = fc_previos(db(), 'factura_equipos', (int)$id);
            db()->prepare("DELETE FROM factura_equipos WHERE factura_id = ?")->execute([$id]);
            $stmtEq = db()->prepare(
                "INSERT INTO factura_equipos (factura_id, imei, vendedor) VALUES (?, ?, ?)"
            );
            foreach ($body['equipos'] as $entrada) {
                [$imei, $vend] = _parse_equipo($entrada);
                if ($imei === '') continue;
                $stmtEq->execute([$id, $imei, $vend]);
                fc_linea_insertada(db(), 'factura_equipos', (int)db()->lastInsertId(), $entrada, $imei, $prevEq);
            }
        }

        // ── items ──
        if (isset($body['items'])) {
            $prevIt = fc_previos(db(), 'factura_items', (int)$id);
            db()->prepare("DELETE FROM factura_items WHERE factura_id = ?")->execute([$id]);
            $stmtIt = db()->prepare(
                "INSERT INTO factura_items (factura_id, producto_codigo, cantidad, vendedor)
                 VALUES (?, ?, 1, ?)"
            );
            foreach ($body['items'] as $entrada) {
                [$cod, $vend] = _parse_item($entrada);
                if ($cod === '') continue;
                $stmtIt->execute([$id, $cod, $vend]);
                fc_linea_insertada(db(), 'factura_items', (int)db()->lastInsertId(), $entrada, $cod, $prevIt);
            }
        }

        // ── pagos ──
        if (isset($body['pagos'])) {
            $prevPg = fc_previos(db(), 'factura_pagos', (int)$id);
            db()->prepare("DELETE FROM factura_pagos WHERE factura_id = ?")->execute([$id]);
            foreach ($body['pagos'] as $pg) {
                if (!is_array($pg)) continue;
                $pg = fc_normalizar_pago(_normalizar_pago($pg, (int)$id), $appNueva);
                $idPg = insertar('factura_pagos', $pg, $colsPagosPut);
                fc_pago_reinsertado(db(), $idPg, $pg, $prevPg);
            }
        }

        db()->commit();
        json_response(['ok' => true]);
    } catch (Throwable $e) {
        db()->rollBack();
        json_error('Error al actualizar factura: ' . $e->getMessage(), 500);
    }
}

if ($metodo === 'DELETE') {
    if ($id === null) json_error('Falta id', 400);
    db()->beginTransaction();
    try {
        db()->prepare(
            "UPDATE stock_imei
             SET vendido = 0, fecha_venta = NULL, factura_id = NULL
             WHERE factura_id = ?"
        )->execute([$id]);

        $stmt = db()->prepare(
            "SELECT producto_codigo, SUM(cantidad) AS qty
             FROM factura_items
             WHERE factura_id = ?
             GROUP BY producto_codigo"
        );
        $stmt->execute([$id]);
        $items = $stmt->fetchAll();
        $stmtUp = db()->prepare(
            "UPDATE productos SET stock_manual = stock_manual + ? WHERE codigo = ?"
        );
        foreach ($items as $it) {
            $stmtUp->execute([(int)$it['qty'], $it['producto_codigo']]);
        }

        $rows = eliminar_logico('facturas', $id);

        db()->commit();
        // La deuda FPB no sobrevive a su factura: se anula si no tiene
        // abonos; si los tiene, queda con un aviso. Que falle no impide
        // eliminar la factura (ya está eliminada).
        $cxcAnuladas = null;
        try {
            if ($rows > 0) $cxcAnuladas = fc_anular_cxc_de_factura(db(), (int)$id);
        } catch (Throwable $e) {
            error_log('[fpb] anular cuenta de la factura ' . $id . ': ' . $e->getMessage());
        }
        $respDel = [
            'ok' => true,
            'rows' => $rows,
            'imeis_liberados' => count($items),
            'productos_restaurados' => count($items),
        ];
        if ($cxcAnuladas && ($cxcAnuladas['eliminadas'] || $cxcAnuladas['conservadas'])) {
            $respDel['cuentas_cobrar'] = $cxcAnuladas;
        }
        json_response($respDel);
    } catch (Throwable $e) {
        db()->rollBack();
        json_error('Error al eliminar factura: ' . $e->getMessage(), 500);
    }
}

json_error('Método no permitido', 405);