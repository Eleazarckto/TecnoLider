<?php
// Endpoint: /api.php?resource=servicios
//
// Servicios técnicos. La app envía los campos checklist SIN prefijo `chk_`
// (la columna se llama tal cual: chip, memoria, etc.) y el costo_repuestos
// real va empaquetado en META dentro del campo `descripcion` — pero la
// columna física también existe como respaldo.

$columnas = [
    'fecha', 'hora_recibido', 'fecha_entrega',
    'nombre_cliente', 'nombre', 'cliente', 'telefono',
    'rif_ci', 'cedula',
    'marca', 'modelo', 'imei', 'contrasena', 'password',
    'descripcion', 'nota', 'observacion',
    // Checklist (sin prefijo chk_)
    'chip', 'memoria', 'bateria', 'tapa',
    'encendido', 'apagado', 'camara', 'corneta',
    'flash', 'flash_con_defecto',
    'tactil_partido', 'auricular', 'microfono', 'contrasena_chk',
    'track', 'boton_volumen', 'teclado',
    'boton_encendido', 'pantalla_con_defecto',
    // Montos
    'monto', 'abono', 'costo_repuestos', 'pagado',
    // Asignación
    'tecnico', 'estado',
];

$metodo = $_SERVER['REQUEST_METHOD'];

if ($metodo === 'GET') {
    $id = get_param('id');
    if ($id !== null) {
        $row = obtener('servicios', $id);
        if (!$row) json_error('No encontrado', 404);
        json_response($row);
    }

    $sql = "SELECT * FROM servicios WHERE eliminado_en IS NULL";
    $params = [];
    foreach (['estado', 'tecnico'] as $col) {
        $val = get_param($col);
        if ($val) { $sql .= " AND $col = ?"; $params[] = $val; }
    }
    $desde = get_param('desde');
    $hasta = get_param('hasta');
    if ($desde) { $sql .= " AND fecha >= ?"; $params[] = $desde; }
    if ($hasta) { $sql .= " AND fecha <= ?"; $params[] = $hasta; }
    $sql .= " ORDER BY fecha DESC, id DESC LIMIT 2000";

    $stmt = db()->prepare($sql);
    $stmt->execute($params);
    json_response($stmt->fetchAll());
}

despachar_crud('servicios', $columnas, 'fecha DESC, id DESC');
