<?php
// ════════════════════════════════════════════════════════════════════
//  Endpoint: imágenes de producto (para las cotizaciones)
// ════════════════════════════════════════════════════════════════════
//    ?resource=producto_imagenes       (GET)  → listar todas
//    ?resource=producto_imagen_guardar (POST) → guardar / reemplazar
//
//  Cada producto tiene UNA imagen: cuando el usuario elige una foto
//  nueva desde la cotización, reemplaza la anterior. Por eso la tabla
//  lleva UNIQUE (producto_codigo) y el guardado es un upsert.
//
//  La app lee `producto_codigo` e `imagen_base64` — esos dos nombres no
//  se pueden cambiar sin tocar `_cargarImagenesGuardadas` en main.dart.
// ════════════════════════════════════════════════════════════════════

require_once __DIR__ . '/../lib/esquema.php';

$metodo  = $_SERVER['REQUEST_METHOD'];
$recurso = (string) get_param('resource', 'producto_imagenes');

// Tope del base64 aceptado. La app ya reduce a 800 px de ancho con
// calidad 70 (unos 100 KB), así que esto solo frena envíos anómalos
// que harían crecer el listado hasta volverlo inusable.
const MAX_BYTES_IMAGEN = 3 * 1024 * 1024;

// ── GUARDAR ────────────────────────────────────────────────────────
if ($recurso === 'producto_imagen_guardar' || $metodo === 'POST') {
    if ($metodo !== 'POST') json_error('Método no permitido, usá POST', 405);

    $body   = json_body();
    $codigo = trim((string)($body['producto_codigo'] ?? ''));
    $b64    = (string)($body['imagen_base64'] ?? $body['base64'] ?? '');
    $ext    = strtolower(trim((string)($body['imagen_ext'] ?? 'jpg')));

    if ($codigo === '') json_error('Falta producto_codigo', 400);
    if ($b64 === '')    json_error('No se recibió la imagen', 400);
    if (strlen($b64) > MAX_BYTES_IMAGEN) {
        json_error('La imagen es demasiado grande. Máximo 3 MB.', 413);
    }
    if (!in_array($ext, ['jpg', 'jpeg', 'png', 'webp'], true)) $ext = 'jpg';

    asegurar_tabla_producto_imagenes();

    // Upsert: una imagen por producto. Sin el ON DUPLICATE, el segundo
    // guardado del mismo producto chocaría con el UNIQUE y la app
    // mostraría "Conflicto: el recurso ya existe".
    db()->prepare(
        'INSERT INTO producto_imagenes
            (producto_codigo, imagen_base64, imagen_ext)
         VALUES (?, ?, ?)
         ON DUPLICATE KEY UPDATE
            imagen_base64  = VALUES(imagen_base64),
            imagen_ext     = VALUES(imagen_ext),
            actualizado_en = NOW()'
    )->execute([$codigo, $b64, $ext]);

    json_response([
        'ok'              => true,
        'producto_codigo' => $codigo,
        'imagen_ext'      => $ext,
        'bytes'           => strlen($b64),
        'message'         => 'Imagen guardada.',
    ], 201);
}

// ── LISTAR ─────────────────────────────────────────────────────────
if ($metodo === 'GET') {
    // Sin tabla todavía no hay imágenes. Vacío, no un 500: para la app
    // es lo mismo que un catálogo sin fotos cargadas.
    if (!tabla_existe('producto_imagenes')) json_response([]);

    // `codigo` es opcional y la app hoy no lo manda, pero permite pedir
    // una sola imagen en vez de bajar el catálogo entero.
    $codigo = get_param('codigo') ?? get_param('producto_codigo');

    if ($codigo !== null && trim((string)$codigo) !== '') {
        $stmt = db()->prepare(
            'SELECT producto_codigo, imagen_base64, imagen_ext
             FROM producto_imagenes WHERE producto_codigo = ?');
        $stmt->execute([trim((string)$codigo)]);
        json_response($stmt->fetchAll());
    }

    $stmt = db()->query(
        'SELECT producto_codigo, imagen_base64, imagen_ext
         FROM producto_imagenes ORDER BY producto_codigo LIMIT 500');
    json_response($stmt->fetchAll());
}

json_error('Método no permitido', 405);

// ── Helpers ────────────────────────────────────────────────────────

function asegurar_tabla_producto_imagenes(): void {
    if (tabla_existe('producto_imagenes')) return;
    db()->exec(
        "CREATE TABLE IF NOT EXISTS producto_imagenes (
            id              INT AUTO_INCREMENT PRIMARY KEY,
            producto_codigo VARCHAR(60) NOT NULL,
            imagen_base64   LONGTEXT    NOT NULL,
            imagen_ext      VARCHAR(8)  NOT NULL DEFAULT 'jpg',
            creado_en       TIMESTAMP   NULL DEFAULT CURRENT_TIMESTAMP,
            actualizado_en  DATETIME    NULL,
            UNIQUE KEY uk_producto (producto_codigo)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );
    esquema_refrescar();
}
