<?php
// Endpoint: /api.php?resource=pagos_financiadora
// Registra los pagos que cada financiadora hace a la tienda.

$columnas = [
    'financiadora', 'monto', 'fecha', 'referencia', 'notas', 'factura_id'
];

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    // Permite filtrar por financiadora y/o rango de fechas
    $sql = "SELECT * FROM pagos_financiadora WHERE eliminado_en IS NULL";
    $params = [];

    $financ = get_param('financiadora');
    if ($financ) {
        $sql .= " AND financiadora = ?";
        $params[] = $financ;
    }
    $desde = get_param('desde');
    if ($desde) {
        $sql .= " AND fecha >= ?";
        $params[] = $desde;
    }
    $hasta = get_param('hasta');
    if ($hasta) {
        $sql .= " AND fecha <= ?";
        $params[] = $hasta;
    }
    $sql .= " ORDER BY fecha DESC, id DESC";

    $stmt = db()->prepare($sql);
    $stmt->execute($params);
    json_response($stmt->fetchAll());
}

despachar_crud('pagos_financiadora', $columnas, 'fecha DESC, id DESC');
