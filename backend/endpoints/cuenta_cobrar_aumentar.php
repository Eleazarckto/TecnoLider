<?php
// Endpoint: /api.php?resource=cuenta_cobrar_aumentar   (POST)
//
// Aumenta la deuda de una cuenta por cobrar existente. Se usa cuando un
// cliente que ya tiene una cuenta abierta se lleva mercancía nueva: en
// vez de crear una segunda cuenta, se le suma a la que ya tiene.
//
// Si el cliente venía con saldo a favor (pagó de más en algún abono),
// ese saldo se consume primero y solo la diferencia se suma a la deuda.
//
// Body: { cuenta_id, monto, concepto }
// Responde: { ok, nuevo_monto_total, nuevo_saldo_favor, aplicado_de_favor }

$metodo = $_SERVER['REQUEST_METHOD'];
if ($metodo !== 'POST') json_error('Método no permitido', 405);

$body     = json_body();
$cuentaId = (int)($body['cuenta_id'] ?? 0);
$monto    = (float)($body['monto'] ?? 0);
$concepto = trim((string)($body['concepto'] ?? ''));

if ($cuentaId <= 0) json_error('Falta cuenta_id', 400);
if ($monto <= 0)    json_error('El monto a agregar debe ser mayor a cero', 400);

db()->beginTransaction();
try {
    $stmt = db()->prepare(
        "SELECT * FROM cuentas_cobrar WHERE id = ? AND eliminado_en IS NULL FOR UPDATE"
    );
    $stmt->execute([$cuentaId]);
    $cuenta = $stmt->fetch();
    if (!$cuenta) {
        db()->rollBack();
        json_error('La cuenta no existe', 404);
    }

    // El saldo a favor se consume antes de aumentar la deuda.
    $saldoFavor  = (float)($cuenta['saldo_favor'] ?? 0);
    $aplicado    = min($saldoFavor, $monto);
    $aumentoReal = $monto - $aplicado;
    $nuevoFavor  = $saldoFavor - $aplicado;
    $nuevoTotal  = (float)($cuenta['monto_total'] ?? 0) + $aumentoReal;

    // Dejamos rastro del motivo en las notas de la cuenta, para que
    // después se pueda reconstruir de dónde salió cada aumento.
    $notas = trim((string)($cuenta['notas'] ?? ''));
    if ($concepto !== '') {
        $linea = '[' . date('d/m/Y') . '] +' .
                 number_format($monto, 2, ',', '.') . ' — ' . $concepto;
        $notas = $notas === '' ? $linea : ($notas . "\n" . $linea);
    }

    $stmt = db()->prepare(
        "UPDATE cuentas_cobrar
         SET monto_total = ?, saldo_favor = ?, notas = ?
         WHERE id = ?"
    );
    $stmt->execute([$nuevoTotal, $nuevoFavor, $notas, $cuentaId]);

    db()->commit();

    audit('cuentas_cobrar', $cuentaId, 'AUMENTO_DEUDA',
          $body['_usuario'] ?? null,
          ['monto_total' => (float)$cuenta['monto_total'],
           'saldo_favor' => $saldoFavor],
          ['monto_total' => $nuevoTotal,
           'saldo_favor' => $nuevoFavor,
           'concepto'    => $concepto]);

    json_response([
        'ok'                => true,
        'nuevo_monto_total' => round($nuevoTotal, 2),
        'nuevo_saldo_favor' => round($nuevoFavor, 2),
        'aplicado_de_favor' => round($aplicado, 2),
        'message'           => $aplicado > 0
            ? 'Deuda aumentada. Se aplicó el saldo a favor disponible.'
            : 'Deuda aumentada.',
    ]);
} catch (Throwable $e) {
    if (db()->inTransaction()) db()->rollBack();
    throw $e;
}
