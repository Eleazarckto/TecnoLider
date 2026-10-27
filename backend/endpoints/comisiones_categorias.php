<?php
// Endpoint: /api.php?resource=comisiones_categorias
// La PK es `id` (string, no autoincrement).
$metodo = $_SERVER['REQUEST_METHOD'];

if ($metodo === 'GET') {
    $rows = db()->query(
        "SELECT * FROM comisiones_categorias ORDER BY orden ASC, nombre ASC"
    )->fetchAll();
    json_response($rows);
} elseif ($metodo === 'POST') {
    $body = json_body();
    if (empty($body['id'])) json_error('Falta `id`', 400);
    $stmt = db()->prepare(
        "INSERT INTO comisiones_categorias
         (id, nombre, tarifa_usd, tipo_conteo, valor_conteo,
          icono_key, color_hex, protegida, orden)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE
            nombre = VALUES(nombre),
            tarifa_usd = VALUES(tarifa_usd),
            tipo_conteo = VALUES(tipo_conteo),
            valor_conteo = VALUES(valor_conteo),
            icono_key = VALUES(icono_key),
            color_hex = VALUES(color_hex),
            orden = VALUES(orden)"
    );
    $stmt->execute([
        $body['id'],
        $body['nombre']       ?? '',
        (float) ($body['tarifa_usd'] ?? 0),
        $body['tipo_conteo']  ?? 'categoriaProducto',
        $body['valor_conteo'] ?? '',
        $body['icono_key']    ?? '',
        $body['color_hex']    ?? '#2E3192',
        !empty($body['protegida']) ? 1 : 0,
        (int) ($body['orden'] ?? 0),
    ]);
    json_response(['ok' => true, 'id' => $body['id']]);
} elseif ($metodo === 'DELETE') {
    $id = get_param('id');
    if (!$id) json_error('Falta id', 400);
    // No permitir borrar protegidas
    $stmt = db()->prepare("SELECT protegida FROM comisiones_categorias WHERE id = ?");
    $stmt->execute([$id]);
    $row = $stmt->fetch();
    if ($row && $row['protegida']) {
        json_error('Esta categoría está protegida y no puede eliminarse', 403);
    }
    $stmt = db()->prepare("DELETE FROM comisiones_categorias WHERE id = ?");
    $stmt->execute([$id]);
    json_response(['ok' => true]);
} else {
    json_error('Método no permitido', 405);
}
