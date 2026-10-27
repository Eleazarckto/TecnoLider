<?php
// Endpoint: /api.php?resource=conciliaciones_bdv (registro de auditoría)
$metodo = $_SERVER['REQUEST_METHOD'];

if ($metodo === 'GET') {
    $stmt = db()->query(
        "SELECT * FROM conciliaciones_bdv ORDER BY fecha_consulta DESC LIMIT 500"
    );
    json_response($stmt->fetchAll());
} elseif ($metodo === 'POST') {
    $body = json_body();
    $stmt = db()->prepare(
        "INSERT INTO conciliaciones_bdv
         (factura_pago_id, referencia, cedula_pagador, telefono_pagador,
          telefono_destino, monto_bs, fecha_pago, codigo, mensaje, response_json)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    );
    $stmt->execute([
        $body['factura_pago_id'] ?? null,
        $body['referencia'] ?? '',
        $body['cedula_pagador'] ?? '',
        $body['telefono_pagador'] ?? '',
        $body['telefono_destino'] ?? null,
        (float) ($body[] ?? 0),
        $body['fecha_pago'] ?? date('Y-m-d'),
        $body['codigo'] ?? '',
        $body['mensaje'] ?? null,
        isset($body['response_json'])
            ? json_encode($body['response_json'], JSON_UNESCAPED_UNICODE)
            : null,
    ]);
    json_response(['ok' => true, 'id' => db()->lastInsertId()], 201);
} else {
    json_error('Método no permitido', 405);
}
