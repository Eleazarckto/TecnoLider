<?php
// Endpoint: /api.php?resource=listas_precios
// Tabla con columnas y items en JSON (estructura flexible).
// El schema usa nombres `columnas` y `items` (no _json).
//
// 16/10/2026 (mejoras de listas de Brizuela, ver lib/precios_listas.php):
//   · Lista blanca dinámica: solo columnas que la tabla tiene de verdad.
//     Incluye `tiene_cuotas` (la app la mandaba y se perdía) y los campos
//     nuevos del cálculo desde el costo. `actualizado_en` la pone SOLO el
//     servidor.
//   · GET ?solo_marcas=1[&id=N] → [{id, nombre, actualizado_en}] para el
//     sondeo barato de la app.
//   · PUT con fusión en transacción (SELECT … FOR UPDATE): una app vieja
//     (1.0.17) que no manda `es_manual` ni los campos nuevos no los borra.
//   · POST ?accion=precios_costo → ensayo / activar / desactivar el cálculo
//     desde el costo de UNA lista (rol Dueño, Administrador o Gerente).
//   · Enganche dormido tras POST/PUT: si `precios_auto_activo` = 1 y la
//     lista está en modo costo, se recalcula ella y sus dependientes.
// Las formas de respuesta de siempre no cambian.
require_once __DIR__ . '/../lib/precios_listas.php';

$metodo = $_SERVER['REQUEST_METHOD'];

$columnasPermitidas = array_values(array_intersect([
    'nombre', 'fecha_creacion', 'categoria', 'marca_filtro',
    'es_en_bolivares', 'tasa_del_dia', 'porcentaje_adicional',
    'es_financiamiento', 'financiadora', 'porcentaje_inicial',
    'numero_cuotas', 'porcentaje_comision_weppa', 'porcentaje_recargo_cuotas',
    'columnas', 'items',
    // Nuevos (16/10/2026). Si reparar_esquema todavía no los creó, se
    // descartan solos en vez de dar "Unknown column".
    'tiene_cuotas', 'monto_adicional_dolares', 'pct_sobre_costo',
    'tasa_fija', 'tasa_bs', 'redondear_arriba', 'reglas_pct',
    // 19/10/2026: lista en divisas de la que una lista en Bs toma precios.
    'lista_base_id',
    // 23/10/2026: cómo muestra sus precios una lista en Bs (bs/bcv/bcv_bs).
    'vista_bs',
], plColumnasTabla(db(), 'listas_precios') ?: [
    // Sin poder leer el esquema: la lista de siempre.
    'nombre', 'fecha_creacion', 'categoria', 'marca_filtro',
    'es_en_bolivares', 'tasa_del_dia', 'porcentaje_adicional',
    'es_financiamiento', 'financiadora', 'porcentaje_inicial',
    'numero_cuotas', 'porcentaje_comision_weppa', 'porcentaje_recargo_cuotas',
    'columnas', 'items',
]));

// Asegurar que `columnas` e `items` se reciben como string JSON
// (la columna del schema es JSON pero MySQL acepta strings JSON
// directamente y los valida/almacena como JSON nativo).
function _normalizar_lista(array $body): array {
    if (isset($body['columnas']) && !is_string($body['columnas'])) {
        $body['columnas'] = json_encode($body['columnas'], JSON_UNESCAPED_UNICODE);
    }
    if (isset($body['items']) && !is_string($body['items'])) {
        $body['items'] = json_encode($body['items'], JSON_UNESCAPED_UNICODE);
    }
    // Asegurar valores por defecto razonables para columnas obligatorias
    if (!isset($body['nombre']) || $body['nombre'] === '') {
        $body['nombre'] = 'Lista sin nombre';
    }
    return $body;
}

if ($metodo === 'GET') {
    // Sondeo barato: solo la marca de cambio de cada lista.
    if (get_param('solo_marcas') === '1') {
        $hayMarca = plTieneColumna(db(), 'listas_precios', 'actualizado_en');
        $sql = 'SELECT id, nombre' . ($hayMarca ? ', actualizado_en' : '') .
               ' FROM listas_precios WHERE eliminado_en IS NULL';
        $params = [];
        if (get_param('id') !== null) { $sql .= ' AND id = ?'; $params[] = get_param('id'); }
        $st = db()->prepare($sql . ' ORDER BY id');
        $st->execute($params);
        $out = [];
        foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $r) {
            $out[] = ['id' => (int)$r['id'], 'nombre' => (string)$r['nombre'],
                      'actualizado_en' => (string)($r['actualizado_en'] ?? '')];
        }
        json_response($out);
    }
    $id = get_param('id');
    if ($id !== null) {
        $row = obtener('listas_precios', $id);
        if (!$row) json_error('No encontrada', 404);
        // Decodificar JSON antes de enviar (la app espera arrays)
        $row['columnas'] = is_string($row['columnas'] ?? null)
            ? (json_decode($row['columnas'], true) ?: [])
            : ($row['columnas'] ?? []);
        $row['items'] = is_string($row['items'] ?? null)
            ? (json_decode($row['items'], true) ?: [])
            : ($row['items'] ?? []);
        json_response($row);
    }
    $rows = listar('listas_precios', [], 'creado_en DESC');
    foreach ($rows as &$r) {
        $r['columnas'] = is_string($r['columnas'] ?? null)
            ? (json_decode($r['columnas'], true) ?: [])
            : ($r['columnas'] ?? []);
        $r['items'] = is_string($r['items'] ?? null)
            ? (json_decode($r['items'], true) ?: [])
            : ($r['items'] ?? []);
    }
    json_response($rows);
}

// ── Precios desde el costo: ensayo, activar, desactivar ─────────────────
//  POST ?resource=listas_precios&accion=precios_costo
//  { "id": 12, "operacion": "ensayo"|"activar"|"desactivar",
//    "usuario_correo": "...", "config": { pct_sobre_costo, monto_adicional_dolares,
//    tasa_fija, tasa_del_dia, tasa_bs, redondear_arriba, reglas_pct } }
//  El ensayo hace todo dentro de una transacción y la deshace: responde
//  cuántos precios cambiarían en cada lista. Activar guarda antes un
//  respaldo en `listas_precios_respaldos`.
if ($metodo === 'POST' && get_param('accion') === 'precios_costo') {
    $body = json_body();
    $id = (int)($body['id'] ?? 0);
    $op = (string)($body['operacion'] ?? 'ensayo');
    $correo = (string)($body['usuario_correo'] ?? '');
    if ($id <= 0) json_error('Falta id', 400);
    if (!in_array($op, ['ensayo', 'activar', 'desactivar'], true)) json_error('Operación inválida', 400);
    if (!plUsuarioPuedeGestionar(db(), $correo)) {
        json_error('Solo el Dueño, el Administrador o el Gerente pueden cambiar cómo se calculan '
            . 'los precios de una lista.', 400);   // 400: la app 1.0.x muestra este texto (con 403 no)
    }
    if (!plTieneColumna(db(), 'listas_precios', 'modo_precios')) {
        json_error('Falta actualizar la base: abrir ?resource=reparar_esquema', 400);
    }
    if ($op === 'desactivar') {
        plDesactivarCosto(db(), $id);
        audit('listas_precios', $id, 'UPDATE', $correo, null, ['modo_precios' => 'manual']);
        json_response(['ok' => true, 'operacion' => $op]);
    }
    $config = is_array($body['config'] ?? null) ? $body['config'] : [];
    $res = plActivarCosto(db(), $id, $config, $op === 'ensayo', $correo);
    if ($op === 'activar') {
        audit('listas_precios', $id, 'UPDATE', $correo, null,
              ['modo_precios' => 'costo', 'config' => $config, 'respaldos' => $res['respaldos']]);
    }
    $total = 0;
    foreach ($res['informes'] as $inf) $total += (int)$inf['precios'];
    json_response(['ok' => true, 'operacion' => $op, 'precios_cambian' => $total,
                   'listas' => $res['informes']]);
}

if ($metodo === 'POST') {
    $body = json_body();
    // Una lista nace siempre en modo manual: el modo costo se activa
    // con el ensayo de arriba.
    unset($body['modo_precios'], $body['actualizado_en']);
    $body = _normalizar_lista(plNormalizarCamposNuevos($body));
    try {
        $id = insertar('listas_precios', $body, $columnasPermitidas);
    } catch (Throwable $e) {
        json_error('Error al guardar lista de precios: ' . $e->getMessage(), 500);
    }
    json_response(['ok' => true, 'id' => $id], 201);
}

if ($metodo === 'PUT') {
    $id = get_param('id');
    if (!$id) json_error('Falta id', 400);
    $body = json_body();
    $pdo = db();
    try {
        $pdo->beginTransaction();
        $body = _normalizar_lista(plFusionarCuerpoPut($pdo, $id, $body));
        $rows = actualizar('listas_precios', $id, $body, $columnasPermitidas);
        // La marca del sondeo, aunque la columna se haya creado sin ON UPDATE.
        if (plTieneColumna($pdo, 'listas_precios', 'actualizado_en')) {
            $pdo->prepare('UPDATE listas_precios SET actualizado_en = CURRENT_TIMESTAMP WHERE id = ?')
                ->execute([$id]);
        }
        $pdo->commit();
    } catch (Throwable $e) {
        if ($pdo->inTransaction()) $pdo->rollBack();
        json_error('Error al actualizar lista: ' . $e->getMessage(), 500);
    }
    // Dormido salvo precios_auto_activo = 1 y lista en modo costo.
    plEngancheLista($pdo, (int)$id);
    json_response(['ok' => true, 'rows' => $rows]);
}

if ($metodo === 'DELETE') {
    $id = get_param('id');
    if (!$id) json_error('Falta id', 400);
    $rows = eliminar_logico('listas_precios', $id);
    json_response(['ok' => true, 'rows' => $rows]);
}

json_error('Método no permitido', 405);
