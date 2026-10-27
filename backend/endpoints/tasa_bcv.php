<?php
// Endpoint: /api.php?resource=tasa_bcv
// Histórico de tasas + getter especial: ?actual=1 devuelve la tasa vigente
if ($_SERVER['REQUEST_METHOD'] === 'GET' && get_param('actual') === '1') {
    $row = db()->query(
        "SELECT * FROM tasa_bcv WHERE es_actual = 1 ORDER BY fecha DESC LIMIT 1"
    )->fetch();
    json_response($row ?: ['valor' => 0, 'fuente' => 'sin_dato']);
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $body = json_body();
    $valor = (float) ($body['valor'] ?? 0);
    if ($valor <= 0) json_error('Valor inválido', 400);

    db()->beginTransaction();
    try {
        // Marcar todas las anteriores como no actuales
        db()->exec("UPDATE tasa_bcv SET es_actual = 0 WHERE es_actual = 1");
        // Insertar nueva
        $stmt = db()->prepare(
            "INSERT INTO tasa_bcv (valor, fuente, es_actual) VALUES (?, ?, 1)"
        );
        $stmt->execute([$valor, $body['fuente'] ?? 'BCV']);
        $id = (int) db()->lastInsertId();
        db()->commit();
        // Listas en Bs en modo costo (16/10/2026). DORMIDO: sale enseguida
        // si `precios_auto_activo` no vale 1; nunca rompe la carga de la tasa.
        require_once __DIR__ . '/../lib/precios_listas.php';
        plEngancheTasaBcv(db(), $valor);
        json_response(['ok' => true, 'id' => $id], 201);
    } catch (Throwable $e) {
        db()->rollBack();
        throw $e;
    }
}

// Resto de operaciones: comportamiento estándar
$columnas = ['valor', 'fuente', 'es_actual'];
despachar_crud('tasa_bcv', $columnas, 'fecha DESC', null, null, function($id) {
    // tasa_bcv no tiene soft-delete (no es transaccional)
    $stmt = db()->prepare("DELETE FROM tasa_bcv WHERE id = ?");
    $stmt->execute([$id]);
    return $stmt->rowCount();
});
