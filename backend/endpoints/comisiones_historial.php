<?php
// Endpoint: /api.php?resource=comisiones_historial
// Snapshot de cálculos de comisiones por período.
//
// Schema real:
//   - fecha_inicio (VARCHAR)
//   - fecha_fin    (VARCHAR)
//   - tasa         (DECIMAL)   ← NO 'tasa_bcv'
//   - detalle      (JSON)      ← NO 'data_json'
//
// La app envía: 'tasa_bcv' y 'data'. Aceptamos ambos nombres.

$metodo = $_SERVER['REQUEST_METHOD'];

if ($metodo === 'GET') {
    $stmt = db()->query(
        "SELECT * FROM comisiones_historial ORDER BY fecha_inicio DESC LIMIT 200"
    );
    $rows = $stmt->fetchAll();
    // Decodificar JSON antes de devolver
    foreach ($rows as &$r) {
        if (isset($r['detalle']) && is_string($r['detalle'])) {
            $decoded = json_decode($r['detalle'], true);
            $r['detalle'] = $decoded ?: [];
        }
    }
    json_response($rows);
} elseif ($metodo === 'POST') {
    $body = json_body();

    // Aceptar nombres alternativos
    $tasa    = (float) ($body['tasa'] ?? $body['tasa_bcv'] ?? 0);
    $detalle = $body['detalle'] ?? $body['data'] ?? null;
    if (is_array($detalle)) {
        $detalle = json_encode($detalle, JSON_UNESCAPED_UNICODE);
    }
    if (!$detalle) $detalle = '[]';

    try {
        $stmt = db()->prepare(
            "INSERT INTO comisiones_historial
             (fecha_inicio, fecha_fin, tasa, detalle)
             VALUES (?, ?, ?, ?)"
        );
        $stmt->execute([
            $body['fecha_inicio'] ?? '',
            $body['fecha_fin']    ?? '',
            $tasa,
            $detalle,
        ]);
        json_response(['ok' => true, 'id' => db()->lastInsertId()], 201);
    } catch (Throwable $e) {
        json_error('Error al guardar comisiones: ' . $e->getMessage(), 500);
    }
} elseif ($metodo === 'DELETE') {
    $id = get_param('id');
    if (!$id) json_error('Falta id', 400);
    $stmt = db()->prepare("DELETE FROM comisiones_historial WHERE id = ?");
    $stmt->execute([$id]);
    json_response(['ok' => true]);
} else {
    json_error('Método no permitido', 405);
}
