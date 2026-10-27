<?php
// Endpoint: /api.php?resource=lineas
$columnas = [
    'fecha', 'tipo', 'cedula', 'nombre', 'telefono', 'correo',
    'direccion', 'direccion2', 'asignado', 'patc', 'modelo',
    'imei1', 'imei2', 'plan', 'chip', 'vendedor', 'esim',
    'nivel_academico', 'codigo_solicitado', 'numero_asignado',
    'patch_path', 'cedula_foto_path', 'patc_foto_path',
    'activada', 'recargada', 'solicitando_codigo', 'es_cliente_movistar'
];
despachar_crud('lineas', $columnas, 'fecha DESC, id DESC');
