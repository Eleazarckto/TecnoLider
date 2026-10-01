<?php
// Endpoint: /api.php?resource=stock_imei
$columnas = [
    'imei', 'producto_codigo', 'fecha_ingreso', 'proveedor',
    'color', 'ubicacion', 'porcentaje_bateria', 'vendido',
    'fecha_venta', 'factura_id'
];

// Para devolver al cliente, hacer un JOIN con productos para incluir datos
// del producto sin pegarse a las columnas. La app espera nombre, marca,
// modelo, precio_costo, precio_venta, categoria, tipo en cada IMEI.
if ($_SERVER['REQUEST_METHOD'] === 'GET' && get_param('id') === null) {
    $sql = "SELECT s.*,
                   p.nombre AS producto_nombre,
                   p.categoria, p.marca, p.modelo, p.tipo,
                   p.precio_costo, p.precio_venta
            FROM stock_imei s
            LEFT JOIN productos p ON p.codigo = s.producto_codigo
            WHERE s.eliminado_en IS NULL
            ORDER BY s.fecha_ingreso DESC";
    $stmt = db()->prepare($sql);
    $stmt->execute();
    json_response($stmt->fetchAll());
}

/**
 * Alta de IMEI, con reutilización de registros borrados.
 *
 * EL PROBLEMA QUE RESUELVE:
 * El borrado de IMEIs es lógico (`eliminado_en = NOW()`), así que la
 * fila sigue en la tabla ocupando el IMEI, que tiene índice UNIQUE.
 * Como el listado filtra por `eliminado_en IS NULL`, el equipo no
 * aparece en la app y parece libre — pero al volver a registrarlo MySQL
 * respondía "Duplicate entry" y la app mostraba "ya existe en la BD".
 * No había forma de reingresar un equipo que se eliminó por error.
 *
 * LA SOLUCIÓN:
 * Si el IMEI pertenece a un registro borrado, se reutiliza esa fila: se
 * sobrescriben los datos con los nuevos, se limpia `eliminado_en` y se
 * quita cualquier rastro de una venta anterior (vendido, fecha_venta,
 * factura_id), porque lo que se está registrando es un ingreso nuevo.
 *
 * Si el IMEI está ACTIVO sí es un duplicado de verdad: se rechaza con
 * un mensaje que dice dónde está el equipo. La palabra "Duplicate" se
 * deja en el texto a propósito: la app instalada la busca para mostrar
 * "ya existe en la BD" en vez del mensaje recortado.
 */
function crear_o_revivir_imei(array $body): int {
    $columnas = [
        'imei', 'producto_codigo', 'fecha_ingreso', 'proveedor',
        'color', 'ubicacion', 'porcentaje_bateria', 'vendido',
        'fecha_venta', 'factura_id'
    ];
    $imei = trim((string)($body['imei'] ?? ''));
    if ($imei === '') json_error('Falta el IMEI', 400);
    $body['imei'] = $imei;

    $stmt = db()->prepare(
        "SELECT id, eliminado_en, ubicacion, producto_codigo, vendido
         FROM stock_imei WHERE imei = ?
         ORDER BY (eliminado_en IS NULL) DESC, id DESC LIMIT 1"
    );
    $stmt->execute([$imei]);
    $fila = $stmt->fetch();

    if ($fila && $fila['eliminado_en'] === null) {
        $donde = trim((string)($fila['ubicacion'] ?? ''));
        json_error(
            "El IMEI $imei ya está registrado"
            . ' (producto ' . $fila['producto_codigo']
            . ($donde !== '' ? ", en $donde" : '')
            . ((int)$fila['vendido'] === 1 ? ', vendido' : '')
            . '). Duplicate',
            400
        );
    }

    if ($fila) {
        $id = (int)$fila['id'];
        // actualizar() ignora las filas con eliminado_en marcado, así
        // que primero hay que revivirla y después escribir los datos.
        restaurar('stock_imei', $id);
        $datos = array_merge(
            ['vendido' => 0, 'fecha_venta' => null, 'factura_id' => null,
             'porcentaje_bateria' => null],
            $body
        );
        actualizar('stock_imei', $id, $datos, $columnas);
        return $id;
    }

    // Alta normal.
    return insertar('stock_imei', $body, $columnas);
}

despachar_crud('stock_imei', $columnas, 'fecha_ingreso DESC', 'crear_o_revivir_imei');
