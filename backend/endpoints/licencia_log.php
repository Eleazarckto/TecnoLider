<?php
// Endpoint: /api.php?resource=licencia/log
$metodo = $_SERVER['REQUEST_METHOD'];

if ($metodo === 'GET') {
    $stmt = db()->query(
        "SELECT id, evento, motivo, usuario, fecha
         FROM licencia_log ORDER BY fecha DESC LIMIT 200"
    );
    json_response($stmt->fetchAll());
} elseif ($metodo === 'POST') {
    $body = json_body();
    $stmt = db()->prepare(
        "INSERT INTO licencia_log (evento, motivo, usuario)
         VALUES (?, ?, ?)"
    );
    $stmt->execute([
        $body['evento']  ?? 'DESCONOCIDO',
        $body['motivo']  ?? '',
        $body['usuario'] ?? 'desconocido',
    ]);
    json_response(['ok' => true, 'id' => db()->lastInsertId()], 201);
} else {
    json_error('Método no permitido', 405);
}
