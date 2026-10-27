<?php
// Endpoint: /api.php?resource=clientes
$columnas = ['cedula', 'nombre', 'telefono', 'correo', 'direccion',
             'nivel_academico', 'notas'];
despachar_crud('clientes', $columnas, 'nombre ASC');
