<?php
// Endpoint: /api.php?resource=abono_eliminar   (POST)
//
// Borra un abono puntual de una cuenta por cobrar. Al desaparecer el
// abono, el saldo de la cuenta vuelve a subir solo, porque la app
// calcula el saldo restando los pagos del monto total.
//
// La app manda { cuenta_id, pago_id, pago_index, monto }. El `pago_id`
// puede venir nulo si el abono se creó antes de que el backend
// devolviera ids, por eso también se acepta la posición en la lista.
//
// IMPORTANTE: el orden de `pago_index` tiene que ser el MISMO con el
// que la app recibió los pagos. En cuentas_cobrar.php se listan con
// `ORDER BY fecha DESC`, así que acá se replica ese orden exacto.

require_once __DIR__ . '/../lib/comprobantes.php';

$metodo = $_SERVER['REQUEST_METHOD'];
if ($metodo !== 'POST') json_error('Método no permitido', 405);

$body     = json_body();
$cuentaId = (int)($body['cuenta_id'] ?? 0);
$pagoId   = isset($body['pago_id']) ? (int)$body['pago_id'] : 0;
$indice   = isset($body['pago_index'])
    ? (int)$body['pago_index']
    : (isset($body['indice']) ? (int)$body['indice'] : -1);

if ($cuentaId <= 0) json_error('Falta cuenta_id', 400);

db()->beginTransaction();
try {
    // Resolver el id real del abono si solo vino la posición.
    if ($pagoId <= 0) {
        if ($indice < 0) {
            db()->rollBack();
            json_error('Indicá pago_id o pago_index del abono a eliminar', 400);
        }
        $stmt = db()->prepare(
            "SELECT id FROM cuentas_cobrar_pagos
             WHERE cuenta_id = ? ORDER BY fecha DESC"
        );
        $stmt->execute([$cuentaId]);
        $ids = $stmt->fetchAll(PDO::FETCH_COLUMN);
        if (!isset($ids[$indice])) {
            db()->rollBack();
            json_error('El abono indicado ya no existe', 404);
        }
        $pagoId = (int)$ids[$indice];
    }

    // Traer el abono antes de borrarlo, para la auditoría.
    $stmt = db()->prepare(
        "SELECT * FROM cuentas_cobrar_pagos WHERE id = ? AND cuenta_id = ?"
    );
    $stmt->execute([$pagoId, $cuentaId]);
    $abono = $stmt->fetch();
    if (!$abono) {
        db()->rollBack();
        json_error('El abono no se encontró en esta cuenta', 404);
    }

    if (tabla_comprobantes_existe()) {
        db()->prepare(
            "DELETE FROM comprobantes WHERE entidad_tipo = 'pago' AND entidad_id = ?"
        )->execute([$pagoId]);
    }

    $stmt = db()->prepare("DELETE FROM cuentas_cobrar_pagos WHERE id = ?");
    $stmt->execute([$pagoId]);
    $rows = $stmt->rowCount();

    db()->commit();

    audit('cuentas_cobrar_pagos', $pagoId, 'DELETE',
          $body['_usuario'] ?? null, $abono, null);

    json_response([
        'ok'      => true,
        'rows'    => $rows,
        'pago_id' => $pagoId,
        'message' => 'Abono eliminado y saldo actualizado.',
    ]);
} catch (Throwable $e) {
    if (db()->inTransaction()) db()->rollBack();
    throw $e;
}
