<?php
// Endpoint READ-ONLY: /api.php?resource=auditoria
// Solo SELECT — la auditoría se crea por triggers o vía función audit().
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    json_error('Solo soporta GET', 405);
}

$tabla   = get_param('tabla');
$usuario = get_param('usuario');
$desde   = get_param('desde');
$hasta   = get_param('hasta');
$limit   = (int) (get_param('limit', 200));
if ($limit > 1000) $limit = 1000;

$sql = "SELECT * FROM auditoria WHERE 1=1";
$params = [];
if ($tabla)   { $sql .= " AND tabla = ?";     $params[] = $tabla; }
if ($usuario) { $sql .= " AND usuario = ?";   $params[] = $usuario; }
if ($desde)   { $sql .= " AND fecha >= ?";    $params[] = $desde; }
if ($hasta)   { $sql .= " AND fecha <= ?";    $params[] = $hasta; }
$sql .= " ORDER BY fecha DESC LIMIT $limit";

$stmt = db()->prepare($sql);
$stmt->execute($params);
json_response($stmt->fetchAll());
