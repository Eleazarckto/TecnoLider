<?php
// Endpoint READ-ONLY: /api.php?resource=stock_disponible
// Vista calculada (productos + stock real desde IMEIs).
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    json_error('Solo soporta GET', 405);
}
$rows = db()->query("SELECT * FROM v_stock_disponible ORDER BY nombre")->fetchAll();
json_response($rows);
