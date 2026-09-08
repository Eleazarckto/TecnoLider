<?php
// Endpoint: /api.php?resource=cuentas_cobrar
//
// Tabla con 2 relaciones 1:N (cuotas, pagos).
// El POST acepta TODO en un solo body y lo distribuye en transacción.
//
// Body esperado (POST):
// {
//   "cedula": "V12345678",
//   "nombre": "Juan Pérez",
//   "telefono": "04141234567",
//   "correo": "juan@ejemplo.com",
//   "monto_total_usd": 600,
//   "monto_total_bs": 21600,
//   "factura_id": 42,
//   "financiadora": "Weppa",
//   "notas": "Plan 6 cuotas",
//   "cuotas": [
//     {"numero": 1, "monto_usd": 100, "fecha_vencimiento": "2026-06-09"},
//     ...
//   ],
//   "pagos": [
//     {"metodo": "Efectivo", "monto_usd": 100, "fecha": "2026-05-09"}
//   ]
// }

$metodo = $_SERVER['REQUEST_METHOD'];
$id     = get_param('id');

$columnasCabecera = [
    'cedula', 'nombre', 'telefono', 'correo',
    'monto_total',
    // Excedente cuando el cliente abona MÁS de lo que debe. La app ya
    // lo calcula y lo envía, pero al no estar en esta lista blanca
    // filtrar_columnas() lo descartaba en cada guardado y el saldo a
    // favor volvía a cero. Se consume al aumentarle la deuda
    // (ver endpoints/cuenta_cobrar_aumentar.php).
    'saldo_favor',
    'factura_id', 'financiadora', 'notas'
];

if ($metodo === 'GET') {
    if ($id !== null) {
        $stmt = db()->prepare("SELECT * FROM cuentas_cobrar WHERE id = ? AND eliminado_en IS NULL");
        $stmt->execute([$id]);
        $cab = $stmt->fetch();
        if (!$cab) json_error('No encontrada', 404);

        $stmt = db()->prepare("SELECT * FROM cuentas_cobrar_cuotas WHERE cuenta_id = ? ORDER BY numero");
        $stmt->execute([$id]);
        $cab['cuotas'] = $stmt->fetchAll();

        $stmt = db()->prepare("SELECT * FROM cuentas_cobrar_pagos WHERE cuenta_id = ? ORDER BY fecha DESC");
        $stmt->execute([$id]);
        $cab['pagos'] = $stmt->fetchAll();

        json_response($cab);
    }

    // Listar todas con sus cuotas y pagos (para que la app no haga N+1)
    $cuentas = db()->query(
        "SELECT * FROM cuentas_cobrar WHERE eliminado_en IS NULL ORDER BY creado_en DESC"
    )->fetchAll();

    if (!empty($cuentas)) {
        $ids = array_column($cuentas, 'id');
        $placeholders = implode(',', array_fill(0, count($ids), '?'));

        $stmt = db()->prepare(
            "SELECT * FROM cuentas_cobrar_cuotas WHERE cuenta_id IN ($placeholders) ORDER BY numero"
        );
        $stmt->execute($ids);
        $cuotasPorCuenta = [];
        foreach ($stmt->fetchAll() as $cu) {
            $cuotasPorCuenta[$cu['cuenta_id']][] = $cu;
        }

        $stmt = db()->prepare(
            "SELECT * FROM cuentas_cobrar_pagos WHERE cuenta_id IN ($placeholders) ORDER BY fecha DESC"
        );
        $stmt->execute($ids);
        $pagosPorCuenta = [];
        foreach ($stmt->fetchAll() as $pg) {
            $pagosPorCuenta[$pg['cuenta_id']][] = $pg;
        }

        foreach ($cuentas as &$c) {
            $c['cuotas'] = $cuotasPorCuenta[$c['id']] ?? [];
            $c['pagos']  = $pagosPorCuenta[$c['id']]  ?? [];
        }
    }

    json_response($cuentas);
}

if ($metodo === 'POST') {
    $body = json_body();
    db()->beginTransaction();
    try {
        $idCuenta = insertar('cuentas_cobrar',
            filtrar_columnas($body, $columnasCabecera),
            $columnasCabecera
        );

        foreach (($body['cuotas'] ?? []) as $cu) {
            $cu['cuenta_id'] = $idCuenta;
            insertar('cuentas_cobrar_cuotas', $cu, [
                'cuenta_id', 'numero', 'monto',
                'fecha', 'pagada', 'fecha_pago'
            ]);
        }

        foreach (($body['pagos'] ?? []) as $pg) {
            $pg['cuenta_id'] = $idCuenta;
            insertar('cuentas_cobrar_pagos', $pg, [
                'cuenta_id', 'metodo', 'monto',
                'fecha', 'referencia', 'notas'
            ]);
        }

        db()->commit();
        json_response(['ok' => true, 'id' => $idCuenta], 201);
    } catch (Throwable $e) {
        db()->rollBack();
        throw $e;
    }
}

if ($metodo === 'PUT') {
    if ($id === null) json_error('Falta id', 400);
    $body = json_body();
    db()->beginTransaction();
    try {
        actualizar('cuentas_cobrar', $id,
            filtrar_columnas($body, $columnasCabecera),
            $columnasCabecera
        );

        // Reemplazo completo de cuotas y pagos si vienen en el body.
        // Esto es más simple y robusto que detectar diffs incrementales.
        if (array_key_exists('cuotas', $body)) {
            db()->prepare("DELETE FROM cuentas_cobrar_cuotas WHERE cuenta_id = ?")
                ->execute([$id]);
            foreach (($body['cuotas'] ?? []) as $cu) {
                $cu['cuenta_id'] = $id;
                insertar('cuentas_cobrar_cuotas', $cu, [
                    'cuenta_id', 'numero', 'monto',
                    'fecha', 'pagada', 'fecha_pago'
                ]);
            }
        }
        if (array_key_exists('pagos', $body)) {
            db()->prepare("DELETE FROM cuentas_cobrar_pagos WHERE cuenta_id = ?")
                ->execute([$id]);
            foreach (($body['pagos'] ?? []) as $pg) {
                $pg['cuenta_id'] = $id;
                insertar('cuentas_cobrar_pagos', $pg, [
                    'cuenta_id', 'metodo', 'monto',
                    'fecha', 'referencia', 'notas'
                ]);
            }
        }

        db()->commit();
        json_response(['ok' => true]);
    } catch (Throwable $e) {
        db()->rollBack();
        throw $e;
    }
}

if ($metodo === 'DELETE') {
    if ($id === null) json_error('Falta id', 400);
    $rows = eliminar_logico('cuentas_cobrar', $id);
    json_response(['ok' => true, 'rows' => $rows]);
}

json_error('Método no permitido', 405);
