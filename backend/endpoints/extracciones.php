<?php
// Endpoint: /api.php?resource=extracciones
$columnas = ['metodo', 'monto', 'motivo', 'fecha',
             'tienda', 'usuario'];
despachar_crud('extracciones', $columnas, 'fecha DESC');
