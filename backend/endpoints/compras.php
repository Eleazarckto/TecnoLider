<?php
// Endpoint: /api.php?resource=compras
// Cada fila representa una entrada de mercancía registrada en la
// pestaña Compras del Panel Administrativo. Es la fuente de verdad
// para las columnas Compras del inventario en costos.
$columnas = [
    'fecha', 'producto', 'cantidad', 'tasa_dia', 'precio_unitario',
];
despachar_crud('compras', $columnas, 'fecha DESC, id DESC');
