<?php
// Endpoint: /api.php?resource=comprobantes         (GET)  → listar
//           /api.php?resource=comprobante_guardar  (POST) → subir
//
// Guarda en base64 las fotos (galería o cámara) y PDFs que el usuario
// adjunta a una cuenta por cobrar, a un abono o a un aumento de deuda.
//
// entidad_tipo usa los valores que ya manda la app:
//   'cuenta'         → la factura o documento original de la cuenta
//   'pago'           → el recibo de un abono
//   'aumento_deuda'  → el respaldo de un aumento de deuda
//
// La app siempre manda además `cuenta_id`, y lista por cuenta_id para
// traer de una todos los comprobantes relacionados con esa cuenta.

require_once __DIR__ . '/../lib/comprobantes.php';

$metodo = $_SERVER['REQUEST_METHOD'];

// Columnas que se devuelven al listar. Los nombres son los que la app
// lee al mostrar la lista de comprobantes, y coinciden con la tabla
// `comprobantes` tal como está en producción (ver lib/comprobantes.php).
$COLUMNAS = 'id, ambito, entidad_tipo, entidad_id, cuenta_id,
             imagen_ext, imagen_base64, created_at';

// ── GUARDAR ────────────────────────────────────────────────────────
if ($metodo === 'POST') {
    $body      = json_body();
    $tipo      = trim((string)($body['entidad_tipo'] ?? ''));
    $entidadId = (int)($body['entidad_id'] ?? 0);
    // `cuenta_id` es NOT NULL en la tabla: si no viene, caemos al
    // entidad_id, que para los tipos 'cuenta' y 'aumento_deuda' ES el
    // id de la cuenta.
    $cuentaId  = (int)($body['cuenta_id'] ?? 0);
    if ($cuentaId <= 0) $cuentaId = $entidadId;
    $ambito    = trim((string)($body['ambito'] ?? 'cuentas_cobrar'));
    $ext       = strtolower(trim((string)(
        $body['imagen_ext'] ?? $body['extension'] ?? 'jpg')));
    $archivo   = (string)(
        $body['imagen_base64'] ?? $body['archivo'] ?? $body['base64'] ?? '');

    if ($tipo === '')    json_error('Falta entidad_tipo', 400);
    if ($archivo === '') json_error('No se recibió el archivo', 400);

    // Solo formatos que la app sabe abrir.
    if (!in_array($ext, ['jpg', 'jpeg', 'png', 'pdf', 'webp'], true)) {
        $ext = 'jpg';
    }

    // La app ya reduce las fotos a 1600px de ancho con calidad 80, así
    // que este tope solo frena casos raros (un PDF pesado, por ejemplo)
    // que reventarían el LONGTEXT o el límite de POST de PHP.
    if (strlen($archivo) > 8 * 1024 * 1024) {
        json_error('El archivo es demasiado grande. Máximo 8 MB.', 413);
    }

    asegurar_tabla_comprobantes();

    $stmt = db()->prepare(
        "INSERT INTO comprobantes
            (ambito, entidad_tipo, entidad_id, cuenta_id, imagen_ext, imagen_base64)
         VALUES (?, ?, ?, ?, ?, ?)"
    );
    $stmt->execute([$ambito, $tipo, $entidadId, $cuentaId, $ext, $archivo]);
    $id = (int) db()->lastInsertId();

    // No guardamos el base64 en la auditoría: son megabytes de ruido.
    audit('comprobantes', $id, 'INSERT', $body['_usuario'] ?? null, null, [
        'ambito'       => $ambito,
        'entidad_tipo' => $tipo,
        'entidad_id'   => $entidadId,
        'cuenta_id'    => $cuentaId,
        'imagen_ext'   => $ext,
        'bytes'        => strlen($archivo),
    ]);

    json_response(['ok' => true, 'id' => $id, 'message' => 'Comprobante guardado.'], 201);
}

// ── LISTAR ─────────────────────────────────────────────────────────
if ($metodo === 'GET') {
    $tipo      = get_param('entidad_tipo');
    $entidadId = (int) get_param('entidad_id', 0);
    $cuentaId  = (int) get_param('cuenta_id', 0);
    $id        = get_param('id');

    // Si la tabla todavía no existe, no hay nada que listar. Devolvemos
    // vacío en vez de un error 500: para la app es lo mismo que una
    // cuenta sin comprobantes.
    if (!tabla_comprobantes_existe()) json_response([]);

    if ($id !== null) {
        $stmt = db()->prepare("SELECT $COLUMNAS FROM comprobantes WHERE id = ?");
        $stmt->execute([$id]);
        $row = $stmt->fetch();
        if (!$row) json_error('No encontrado', 404);
        json_response($row);
    }

    if ($cuentaId > 0) {
        // Todos los comprobantes de la cuenta: los de la cuenta en sí,
        // los de sus abonos y los de sus aumentos de deuda. La app los
        // separa después por entidad_tipo.
        $stmt = db()->prepare(
            "SELECT $COLUMNAS FROM comprobantes
             WHERE cuenta_id = ? ORDER BY id DESC"
        );
        $stmt->execute([$cuentaId]);
        json_response($stmt->fetchAll());
    }

    if ($entidadId > 0) {
        if ($tipo !== null) {
            $stmt = db()->prepare(
                "SELECT $COLUMNAS FROM comprobantes
                 WHERE entidad_tipo = ? AND entidad_id = ? ORDER BY id DESC"
            );
            $stmt->execute([$tipo, $entidadId]);
        } else {
            $stmt = db()->prepare(
                "SELECT $COLUMNAS FROM comprobantes
                 WHERE entidad_id = ? ORDER BY id DESC"
            );
            $stmt->execute([$entidadId]);
        }
        json_response($stmt->fetchAll());
    }

    json_response([]);
}

// ── BORRAR ─────────────────────────────────────────────────────────
if ($metodo === 'DELETE') {
    $id = get_param('id');
    if ($id === null) json_error('Falta id', 400);
    if (!tabla_comprobantes_existe()) json_error('No encontrado', 404);

    $stmt = db()->prepare("DELETE FROM comprobantes WHERE id = ?");
    $stmt->execute([$id]);
    json_response(['ok' => true, 'rows' => $stmt->rowCount()]);
}

json_error('Método no permitido', 405);
