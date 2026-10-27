<?php
// Endpoint: /api.php?resource=ordenes_cashea
$columnas = ['factura_id', 'id_number', 'order_id', 'monto_total',
             'cuotas', 'inicial_usd', 'delivery_method', 'estado',
             'response_json'];

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $body = json_body();
    if (isset($body['response_json']) && !is_string($body['response_json'])) {
        $body['response_json'] = json_encode($body['response_json'],
            JSON_UNESCAPED_UNICODE);
    }
    $id = insertar('ordenes_cashea', $body, $columnas);
    json_response(['ok' => true, 'id' => $id], 201);
} elseif ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $stmt = db()->query(
        "SELECT * FROM ordenes_cashea ORDER BY fecha DESC LIMIT 500"
    );
    json_response($stmt->fetchAll());
} else {
    json_error('Método no permitido', 405);
}
