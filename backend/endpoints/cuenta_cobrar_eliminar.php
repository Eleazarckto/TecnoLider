<?php
// Endpoint: /api.php?resource=cuenta_cobrar_eliminar   (POST)
//
// Borra una cuenta por cobrar completa: la cabecera (soft-delete) y sus
// cuotas, abonos y comprobantes (borrado real, porque no tienen sentido
// sin la cuenta y no se listan por separado en ningún lado).
//
// Existe como POST y no como DELETE ?resource=cuentas_cobrar&id=N porque
// la app necesita arrastrar también las tablas hijas, cosa que el
// soft-delete genérico de crud.php no hace.
//
// Body: { id }   (se acepta cuenta_id como alias)

require_once __DIR__ . '/../lib/comprobantes.php';

$metodo = $_SERVER['REQUEST_METHOD'];
if ($metodo !== 'POST') json_error('Método no permitido', 405);

$body     = json_body();
$cuentaId = (int)($body['id'] ?? $body['cuenta_id'] ?? 0);
if ($cuentaId <= 0) json_error('Falta id de la cuenta', 400);

$antes = obtener('cuentas_cobrar', $cuentaId);
if (!$antes) json_error('La cuenta no existe', 404);

db()->beginTransaction();
try {
    db()->prepare("DELETE FROM cuentas_cobrar_cuotas WHERE cuenta_id = ?")
        ->execute([$cuentaId]);

    // Los comprobantes de los abonos cuelgan del id del abono, así que
    // hay que resolverlos ANTES de borrar los abonos.
    $stmt = db()->prepare("SELECT id FROM cuentas_cobrar_pagos WHERE cuenta_id = ?");
    $stmt->execute([$cuentaId]);
    $idsPagos = $stmt->fetchAll(PDO::FETCH_COLUMN);

    if (tabla_comprobantes_existe()) {
        if (!empty($idsPagos)) {
            $ph = implode(',', array_fill(0, count($idsPagos), '?'));
            db()->prepare(
                "DELETE FROM comprobantes
                 WHERE entidad_tipo = 'pago' AND entidad_id IN ($ph)"
            )->execute($idsPagos);
        }
        db()->prepare("DELETE FROM comprobantes WHERE cuenta_id = ?")
            ->execute([$cuentaId]);
    }

    db()->prepare("DELETE FROM cuentas_cobrar_pagos WHERE cuenta_id = ?")
        ->execute([$cuentaId]);

    $rows = eliminar_logico('cuentas_cobrar', $cuentaId);

    db()->commit();

    audit('cuentas_cobrar', $cuentaId, 'DELETE',
          $body['_usuario'] ?? null, $antes, null);

    json_response(['ok' => true, 'rows' => $rows, 'message' => 'Cuenta eliminada.']);
} catch (Throwable $e) {
    if (db()->inTransaction()) db()->rollBack();
    throw $e;
}
