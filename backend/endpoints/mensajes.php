<?php
// Endpoint: /api.php?resource=mensajes
$columnas = ['emisor', 'receptor', 'contenido', 'hora', 'fecha_envio',
             'imagen_path', 'audio_path', 'reply_a', 'estado'];
despachar_crud('mensajes', $columnas, 'fecha_envio DESC');
