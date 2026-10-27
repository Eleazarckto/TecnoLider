<?php
// Endpoint: /api.php?resource=cierres
//
// La app envía: { uid, tienda, monto_total, usuario_cierre, metodos[] }
// donde metodos = [{metodo, monto}, ...]

$metodo = $_SERVER['REQUEST_METHOD'];
$id     = get_param('id');

// Columnas REALES del schema actual:
//   id (auto), uid, tienda, usuario_cierre, fecha (default NOW), monto_total
$columnasCab = ['uid', 'tienda', 'usuario_cierre', 'fecha', 'monto_total'];

if ($metodo === 'GET') {
    if ($id !== null) {
        // Buscar por id numérico O por uid (string), lo que coincida
        $stmt = db()->prepare(
            "SELECT * FROM cierres
             WHERE (id = :id_n OR uid = :id_s) AND eliminado_en IS NULL
             LIMIT 1"
        );
        $stmt->execute([':id_n' => is_numeric($id) ? (int)$id : 0, ':id_s' => $id]);
        $cab = $stmt->fetch();
        if (!$cab) json_error('No encontrado', 404);

        $stmt = db()->prepare("SELECT * FROM cierres_metodos WHERE cierre_id = ?");
        $stmt->execute([$cab['id']]);
        $cab['metodos'] = $stmt->fetchAll();
        json_response($cab);
    }

    // Listar
    $cierres = db()->query(
        "SELECT * FROM cierres WHERE eliminado_en IS NULL
         ORDER BY fecha DESC LIMIT 500"
    )->fetchAll();

    if (!empty($cierres)) {
        $ids = array_column($cierres, 'id');
        $ph  = implode(',', array_fill(0, count($ids), '?'));
        $stmt = db()->prepare(
            "SELECT * FROM cierres_metodos WHERE cierre_id IN ($ph)"
        );
        $stmt->execute($ids);
        $porCierre = [];
        foreach ($stmt->fetchAll() as $m) {
            $porCierre[$m['cierre_id']][] = $m;
        }
        foreach ($cierres as &$c) {
            $c['metodos'] = $porCierre[$c['id']] ?? [];
        }
    }
    json_response($cierres);
}

if ($metodo === 'POST') {
    $body = json_body();

    if (empty($body['uid']))     json_error('Falta uid (identificador único del cierre)', 400);
    if (empty($body['tienda']))  json_error('Falta tienda', 400);

    db()->beginTransaction();
    try {
        // monto_total como float
        $body['monto_total'] = (float) ($body['monto_total'] ?? 0);
        // usuario_cierre nunca null
        if (empty($body['usuario_cierre'])) $body['usuario_cierre'] = 'Sistema';

        $idDb = insertar('cierres',
            filtrar_columnas($body, $columnasCab),
            $columnasCab
        );

        foreach (($body['metodos'] ?? []) as $m) {
            if (!is_array($m)) continue;
            $m['cierre_id'] = $idDb;
            $m['monto']     = (float) ($m['monto'] ?? 0);
            insertar('cierres_metodos', $m, [
                'cierre_id', 'metodo', 'monto'
            ]);
        }

        db()->commit();
        json_response(['ok' => true, 'id' => $idDb,
                       'uid' => $body['uid']], 201);
    } catch (Throwable $e) {
        db()->rollBack();
        json_error('Error al guardar cierre: ' . $e->getMessage(), 500);
    }
}

if ($metodo === 'DELETE') {
    if ($id === null) json_error('Falta id', 400);
    $stmt = db()->prepare(
        "UPDATE cierres SET eliminado_en = NOW()
         WHERE (id = :id_n OR uid = :id_s) AND eliminado_en IS NULL"
    );
    $stmt->execute([':id_n' => is_numeric($id) ? (int)$id : 0, ':id_s' => $id]);
    json_response(['ok' => true, 'rows' => $stmt->rowCount()]);
}

json_error('Método no permitido', 405);
