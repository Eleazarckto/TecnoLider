<?php
// Endpoint: /api.php?resource=inventario_inicial
//
// Snapshot del stock al primer día de cada mes, por (año, mes,
// tienda, código de producto). El panel Costos lo usa como referencia
// FIJA del inventario inicial — no se modifica durante el mes.
$columnas = [
    'anio', 'mes', 'tienda', 'codigo_producto',
    'unidades', 'costo_unitario',
];
despachar_crud('inventario_inicial_mensual', $columnas,
    'anio DESC, mes DESC, tienda ASC, codigo_producto ASC');
