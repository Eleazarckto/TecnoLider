<?php
// Endpoint: /api.php?resource=notificaciones
// Sin soft-delete (las notificaciones se borran/limpian)
$metodo = $_SERVER['REQUEST_METHOD'];

if ($metodo === 'GET') {
    $usuario = get_param('usuario_correo');
    if ($usuario) {
        $stmt = db()->prepare(
            "SELECT * FROM notificaciones
             WHERE usuario_correo = ? OR usuario_correo IS NULL
             ORDER BY fecha DESC LIMIT 200"
        );
        $stmt->execute([$usuario]);
    } else {
        $stmt = db()->query(
            "SELECT * FROM notificaciones ORDER BY fecha DESC LIMIT 200"
        );
    }
    json_response($stmt->fetchAll());
} elseif ($metodo === 'POST') {
    $body = json_body();
    $stmt = db()->prepare(
        "INSERT INTO notificaciones (usuario_correo, titulo, mensaje, leida)
         VALUES (?, ?, ?, ?)"
    );
    $stmt->execute([
        $body['usuario_correo'] ?? null,
        $body['titulo'] ?? '',
        $body['mensaje'] ?? '',
        !empty($body['leida']) ? 1 : 0,
    ]);
    json_response(['ok' => true, 'id' => db()->lastInsertId()], 201);
} elseif ($metodo === 'PUT') {
    $id = get_param('id');
    if (!$id) json_error('Falta id', 400);
    $body = json_body();
    $stmt = db()->prepare("UPDATE notificaciones SET leida = ? WHERE id = ?");
    $stmt->execute([!empty($body['leida']) ? 1 : 0, $id]);
    json_response(['ok' => true]);
} elseif ($metodo === 'DELETE') {
    $id = get_param('id');
    if (!$id) json_error('Falta id', 400);
    $stmt = db()->prepare("DELETE FROM notificaciones WHERE id = ?");
    $stmt->execute([$id]);
    json_response(['ok' => true]);
} else {
    json_error('Método no permitido', 405);
}
