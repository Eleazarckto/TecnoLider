<?php
// ════════════════════════════════════════════════════════════════════
//  Endpoint: cotizaciones — presupuestos para clientes
// ════════════════════════════════════════════════════════════════════
//  Un solo handler para las cuatro operaciones que usa la app, porque
//  todas trabajan sobre el mismo par de tablas (cabecera + items):
//
//    ?resource=cotizaciones        (GET)  → listar con sus items
//    ?resource=cotizacion_guardar  (POST) → crear
//    ?resource=cotizacion_cobrar   (POST) → marcar como cobrada
//    ?resource=cotizacion_eliminar (POST) → borrar
//
//  Los nombres de campo son EXACTAMENTE los que lee
//  `CotizacionRegistro.fromMap` en la app (cliente_tel, monto_iva,
//  fecha_vence, …). Renombrar cualquiera deja la pantalla en blanco.
// ════════════════════════════════════════════════════════════════════

require_once __DIR__ . '/../lib/esquema.php';

$metodo  = $_SERVER['REQUEST_METHOD'];
$recurso = (string) get_param('resource', 'cotizaciones');

asegurar_tablas_cotizaciones();

// ── LISTAR ─────────────────────────────────────────────────────────
if ($recurso === 'cotizaciones' && $metodo === 'GET') {
    $id = get_param('id');

    $where  = 'WHERE eliminado_en IS NULL';
    $params = [];
    if ($id !== null) {
        $where   .= ' AND id = ?';
        $params[] = (int)$id;
    }

    $stmt = db()->prepare(
        "SELECT * FROM cotizaciones $where ORDER BY id DESC LIMIT 500");
    $stmt->execute($params);
    $filas = $stmt->fetchAll();

    // Los items se traen de una sola consulta para todas las
    // cotizaciones listadas. Con una consulta por cotización, un
    // historial de 300 presupuestos serían 301 viajes a MySQL.
    $items = items_por_cotizacion(array_map(
        static fn(array $f): int => (int)$f['id'], $filas));

    foreach ($filas as &$f) {
        $f['id']          = (int)$f['id'];
        $f['incluye_iva'] = (int)$f['incluye_iva'];
        $f['items']       = $items[(int)$f['id']] ?? [];
    }
    unset($f);

    json_response($id !== null ? ($filas[0] ?? null) : $filas);
}

// De acá para abajo, todo es POST.
if ($metodo !== 'POST') json_error('Método no permitido', 405);

$body = json_body();

// ── GUARDAR ────────────────────────────────────────────────────────
if ($recurso === 'cotizacion_guardar' || $recurso === 'cotizaciones') {
    $cliente = trim((string)($body['cliente_nombre'] ?? ''));
    if ($cliente === '') json_error('El nombre del cliente es obligatorio', 400);

    $items = $body['items'] ?? [];
    if (!is_array($items) || !$items) {
        json_error('La cotización no tiene productos', 400);
    }

    db()->beginTransaction();
    try {
        $cotizacionId = insertar_en('cotizaciones', [
            'cliente_nombre' => $cliente,
            'cliente_cedula' => trim((string)($body['cliente_cedula'] ?? '')),
            'cliente_tel'    => trim((string)($body['cliente_tel'] ?? '')),
            'cliente_correo' => trim((string)($body['cliente_correo'] ?? '')),
            'moneda'         => ($body['moneda'] ?? 'USD') === 'Bs' ? 'Bs' : 'USD',
            'incluye_iva'    => !empty($body['incluye_iva']) ? 1 : 0,
            'tasa'           => (float)($body['tasa'] ?? 0),
            'subtotal'       => (float)($body['subtotal'] ?? 0),
            'monto_iva'      => (float)($body['monto_iva'] ?? 0),
            'total'          => (float)($body['total'] ?? 0),
            'fecha_creacion' => fecha_o_null($body['fecha_creacion'] ?? null),
            'fecha_vence'    => fecha_o_null($body['fecha_vence'] ?? null),
            'estado'         => 'pendiente',
            'nro_factura'    => '',
            'usuario'        => trim((string)($body['usuario'] ?? $body['_usuario'] ?? '')),
        ]);

        $stmt = db()->prepare(
            'INSERT INTO cotizacion_items
                (cotizacion_id, producto_codigo, producto_nombre,
                 marca, modelo, cantidad, precio_unitario)
             VALUES (?, ?, ?, ?, ?, ?, ?)'
        );
        foreach ($items as $it) {
            if (!is_array($it)) continue;
            $stmt->execute([
                $cotizacionId,
                trim((string)($it['producto_codigo'] ?? '')),
                trim((string)($it['producto_nombre'] ?? '')),
                trim((string)($it['marca'] ?? '')),
                trim((string)($it['modelo'] ?? '')),
                max(1, (int)($it['cantidad'] ?? 1)),
                (float)($it['precio_unitario'] ?? 0),
            ]);
        }

        db()->commit();
    } catch (Throwable $e) {
        if (db()->inTransaction()) db()->rollBack();
        throw $e;
    }

    cotizacion_audit($cotizacionId, 'INSERT', $body, null,
        ['cliente' => $cliente, 'total' => (float)($body['total'] ?? 0)]);

    json_response([
        'ok'      => true,
        'id'      => $cotizacionId,
        'message' => 'Cotización guardada.',
    ], 201);
}

// ── COBRAR ─────────────────────────────────────────────────────────
if ($recurso === 'cotizacion_cobrar') {
    $id  = (int)($body['id'] ?? 0);
    $nro = trim((string)($body['nro_factura'] ?? ''));
    if ($id <= 0)   json_error('Falta el id de la cotización', 400);
    if ($nro === '') json_error('Falta el número de factura', 400);

    $cot = cotizacion_viva($id);

    db()->prepare(
        "UPDATE cotizaciones
         SET estado = 'cobrada', nro_factura = ?, fecha_cobro = NOW()
         WHERE id = ?"
    )->execute([$nro, $id]);

    cotizacion_audit($id, 'COBRADA', $body,
        ['estado' => $cot['estado']],
        ['estado' => 'cobrada', 'nro_factura' => $nro]);

    json_response([
        'ok'          => true,
        'id'          => $id,
        'estado'      => 'cobrada',
        'nro_factura' => $nro,
        'message'     => 'Cotización marcada como cobrada.',
    ]);
}

// ── ELIMINAR ───────────────────────────────────────────────────────
// Borrado lógico, igual que el resto del sistema: la cotización
// desaparece de la app pero queda el rastro para auditoría. Los items
// se conservan colgando de la cabecera.
if ($recurso === 'cotizacion_eliminar') {
    $id = (int)($body['id'] ?? 0);
    if ($id <= 0) json_error('Falta el id de la cotización', 400);

    $cot = cotizacion_viva($id);

    db()->prepare('UPDATE cotizaciones SET eliminado_en = NOW() WHERE id = ?')
        ->execute([$id]);

    cotizacion_audit($id, 'DELETE', $body, $cot, null);

    json_response(['ok' => true, 'id' => $id, 'message' => 'Cotización eliminada.']);
}

json_error("Operación de cotizaciones no reconocida: $recurso", 404);

// ── Helpers ────────────────────────────────────────────────────────

/**
 * Trae la cotización viva o corta con 404. Devuelve la fila para poder
 * dejar en la auditoría cómo estaba antes del cambio.
 */
function cotizacion_viva(int $id): array {
    $stmt = db()->prepare(
        'SELECT * FROM cotizaciones WHERE id = ? AND eliminado_en IS NULL');
    $stmt->execute([$id]);
    $fila = $stmt->fetch();
    if (!$fila) json_error("La cotización #$id no existe o ya fue eliminada", 404);
    return $fila;
}

/**
 * Items de varias cotizaciones a la vez, indexados por cotizacion_id.
 * @param int[] $ids
 * @return array<int, array<int, array>>
 */
function items_por_cotizacion(array $ids): array {
    if (!$ids) return [];
    $marks = implode(',', array_fill(0, count($ids), '?'));
    $stmt  = db()->prepare(
        "SELECT cotizacion_id, producto_codigo, producto_nombre,
                marca, modelo, cantidad, precio_unitario
         FROM cotizacion_items
         WHERE cotizacion_id IN ($marks)
         ORDER BY id"
    );
    $stmt->execute($ids);

    $out = [];
    foreach ($stmt->fetchAll() as $it) {
        $cid = (int)$it['cotizacion_id'];
        unset($it['cotizacion_id']);
        $it['cantidad'] = (int)$it['cantidad'];
        $out[$cid][]    = $it;
    }
    return $out;
}

/**
 * Normaliza una fecha a 'YYYY-MM-DD'. La app manda ISO recortado a 10
 * caracteres, pero aceptamos también dd/mm/yyyy por si algún día se
 * llama al endpoint desde otro lado. Si no se entiende, NULL: es
 * preferible una fecha vacía a un 500 por formato inválido.
 */
function fecha_o_null($valor): ?string {
    $s = trim((string)$valor);
    if ($s === '') return null;
    if (preg_match('/^(\d{4})-(\d{2})-(\d{2})/', $s, $m)) {
        return "$m[1]-$m[2]-$m[3]";
    }
    if (preg_match('#^(\d{2})/(\d{2})/(\d{4})$#', $s, $m)) {
        return "$m[3]-$m[2]-$m[1]";
    }
    $ts = strtotime($s);
    return $ts === false ? null : date('Y-m-d', $ts);
}

/** Auditoría best-effort: que falte o falle no invalida la operación. */
function cotizacion_audit(int $id, string $accion, array $body,
                          $antes, $despues): void {
    if (!function_exists('audit')) return;
    try {
        $usuario = trim((string)($body['usuario'] ?? $body['_usuario'] ?? ''));
        audit('cotizaciones', $id, $accion,
              $usuario !== '' ? $usuario : null, $antes, $despues);
    } catch (Throwable $e) {
        // Silencio deliberado.
    }
}

/**
 * Crea las dos tablas si la instalación todavía no las tiene. El módulo
 * de cotizaciones se programó en la app antes de que existieran del
 * lado del servidor, así que en producción hay que crearlas de cero.
 */
function asegurar_tablas_cotizaciones(): void {
    if (tabla_existe('cotizaciones') && tabla_existe('cotizacion_items')) return;

    db()->exec(
        "CREATE TABLE IF NOT EXISTS cotizaciones (
            id             INT AUTO_INCREMENT PRIMARY KEY,
            cliente_nombre VARCHAR(160)  NOT NULL DEFAULT '',
            cliente_cedula VARCHAR(40)   NOT NULL DEFAULT '',
            cliente_tel    VARCHAR(40)   NOT NULL DEFAULT '',
            cliente_correo VARCHAR(160)  NOT NULL DEFAULT '',
            moneda         VARCHAR(8)    NOT NULL DEFAULT 'USD',
            incluye_iva    TINYINT(1)    NOT NULL DEFAULT 0,
            tasa           DECIMAL(18,4) NOT NULL DEFAULT 0,
            subtotal       DECIMAL(14,2) NOT NULL DEFAULT 0,
            monto_iva      DECIMAL(14,2) NOT NULL DEFAULT 0,
            total          DECIMAL(14,2) NOT NULL DEFAULT 0,
            fecha_creacion DATE          NULL,
            fecha_vence    DATE          NULL,
            estado         VARCHAR(20)   NOT NULL DEFAULT 'pendiente',
            nro_factura    VARCHAR(80)   NOT NULL DEFAULT '',
            fecha_cobro    DATETIME      NULL,
            usuario        VARCHAR(160)  NOT NULL DEFAULT '',
            creado_en      TIMESTAMP     NULL DEFAULT CURRENT_TIMESTAMP,
            eliminado_en   DATETIME      NULL,
            INDEX idx_estado (estado),
            INDEX idx_cedula (cliente_cedula),
            INDEX idx_vivas  (eliminado_en, id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );

    db()->exec(
        "CREATE TABLE IF NOT EXISTS cotizacion_items (
            id              INT AUTO_INCREMENT PRIMARY KEY,
            cotizacion_id   INT           NOT NULL,
            producto_codigo VARCHAR(60)   NOT NULL DEFAULT '',
            producto_nombre VARCHAR(200)  NOT NULL DEFAULT '',
            marca           VARCHAR(80)   NOT NULL DEFAULT '',
            modelo          VARCHAR(80)   NOT NULL DEFAULT '',
            cantidad        INT           NOT NULL DEFAULT 1,
            precio_unitario DECIMAL(14,2) NOT NULL DEFAULT 0,
            INDEX idx_cotizacion (cotizacion_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );

    // `insertar_en()` mira el esquema cacheado: sin este refresco vería
    // las tablas como si todavía no existieran y no insertaría nada.
    esquema_refrescar();
}
