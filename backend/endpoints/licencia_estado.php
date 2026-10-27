<?php
// Endpoint: /api.php?resource=licencia/estado
$metodo = $_SERVER['REQUEST_METHOD'];

if ($metodo === 'GET') {
    $row = db()->query(
        "SELECT bloqueada, motivo, telefono, ultima_sync
         FROM licencia_estado WHERE id = 1"
    )->fetch();

    if (!$row) {
        db()->exec("INSERT INTO licencia_estado (id, bloqueada) VALUES (1, 0)");
        $row = [
            'bloqueada'   => false,
            'motivo'      => 'Servicio suspendido por falta de pago',
            'telefono'    => '0414-XXXXXXX',
            'ultima_sync' => date('Y-m-d H:i:s'),
        ];
    } else {
        $row['bloqueada'] = (bool) $row['bloqueada'];
    }
    json_response($row);
} elseif ($metodo === 'POST') {
    $body = json_body();
    $accionPor = $body['accion_por'] ?? 'desconocido';

    // SEGURIDAD: solo el correo del usuario maestro puede aplicar cambios.
    // Cambia este correo si tu maestro es otro.
    if ($accionPor !== 'eleazarceccato@gmail.com') {
        json_error('No autorizado', 403);
    }

    $stmt = db()->prepare(
        "UPDATE licencia_estado
         SET bloqueada = ?, motivo = ?, telefono = ?,
             ultima_sync = NOW(), accion_por = ?
         WHERE id = 1"
    );
    $stmt->execute([
        !empty($body['bloqueada']) ? 1 : 0,
        $body['motivo']   ?? 'Servicio suspendido por falta de pago',
        $body['telefono'] ?? '0414-XXXXXXX',
        $accionPor,
    ]);
    json_response(['ok' => true]);
} else {
    json_error('Método no permitido', 405);
}
