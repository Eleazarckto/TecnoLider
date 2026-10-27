<?php
// Endpoint: /api.php?resource=traslados
//
// Bitácora de movimientos de producto entre tiendas. Cada fila es un
// envío. El cliente Dart aplica el efecto físico (cambia ubicación
// del IMEI o ajusta stock_manual del producto) por separado.
$columnas = [
    'fecha', 'producto_codigo', 'producto_nombre',
    'imei', 'cantidad',
    'tienda_origen', 'tienda_destino',
    'nota', 'usuario',
];
despachar_crud('traslados', $columnas, 'fecha DESC, id DESC');
