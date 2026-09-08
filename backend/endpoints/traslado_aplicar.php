<?php
// ════════════════════════════════════════════════════════════════════
//  Endpoint: /api.php?resource=traslado_aplicar   (POST)
// ════════════════════════════════════════════════════════════════════
//  Mueve mercancía de una tienda a otra en UNA sola transacción: el
//  cambio físico (IMEI o stock) y la bitácora se guardan juntos o no se
//  guarda nada. Antes la app hacía dos o tres PUT seguidos y, si el
//  segundo fallaba, quedaba stock descontado en el origen que nunca
//  llegaba al destino.
//
//  Body:
//    tipo             'imei' | 'producto'
//    producto_codigo  SKU del producto
//    imei             solo si tipo = 'imei'
//    cantidad         unidades a mover (1 si es IMEI)
//    tienda_origen    de dónde sale
//    tienda_destino   a dónde va
//    nota, usuario    para la bitácora
//
//  Responde: { ok, traslado_id, stock_origen, stock_destino, ... }
//
//  ── Los dos casos ──────────────────────────────────────────────
//  · IMEI: cada teléfono es una fila de `stock_imei` con su
//    `ubicacion`. Trasladar = cambiar esa ubicación. `productos` no se
//    toca: el listado de IMEIs ya trae el nombre y la categoría del
//    producto por JOIN.
//  · Producto suelto: `productos` tiene UNIQUE (codigo, tienda), o sea
//    una fila de stock por tienda. Trasladar = restar en la fila del
//    origen y sumar en la del destino, creándola si todavía no existe.
// ════════════════════════════════════════════════════════════════════

require_once __DIR__ . '/../lib/esquema.php';

$metodo = $_SERVER['REQUEST_METHOD'];
if ($metodo !== 'POST') json_error('Método no permitido, usá POST', 405);

$body = json_body();

$tipo     = strtolower(trim((string)($body['tipo'] ?? '')));
$codigo   = trim((string)($body['producto_codigo'] ?? ''));
$imei     = trim((string)($body['imei'] ?? ''));
$origen   = trim((string)($body['tienda_origen'] ?? ''));
$destino  = trim((string)($body['tienda_destino'] ?? ''));
$nota     = trim((string)($body['nota'] ?? ''));
$usuario  = trim((string)($body['usuario'] ?? ''));
$cantidad = (int)($body['cantidad'] ?? 0);

// Si no vino `tipo`, lo deducimos: con IMEI es un teléfono.
if ($tipo === '') $tipo = $imei !== '' ? 'imei' : 'producto';
if ($tipo === 'imei') $cantidad = 1;

// ── Validaciones que no necesitan tocar la base ──────────────────
if ($codigo === '' && $imei === '') {
    json_error('Falta el código del producto', 400);
}
if ($destino === '') json_error('Falta la tienda de destino', 400);
if ($tipo === 'imei' && $imei === '') {
    json_error('Falta el IMEI a trasladar', 400);
}
if ($tipo !== 'imei' && $cantidad <= 0) {
    json_error('La cantidad debe ser mayor a 0', 400);
}
if ($origen !== '' && $origen === $destino) {
    json_error('Origen y destino son la misma tienda', 400);
}

db()->beginTransaction();
try {
    $nombreProducto = '';
    $stockOrigen    = null;
    $stockDestino   = null;

    if ($tipo === 'imei') {
        // ── Caso teléfono: mover la ubicación del IMEI ────────────
        $sql = 'SELECT * FROM stock_imei WHERE imei = ?'
             . filtro_no_eliminado('stock_imei')
             . ' FOR UPDATE';
        $stmt = db()->prepare($sql);
        $stmt->execute([$imei]);
        $fila = $stmt->fetch();

        if (!$fila) {
            db()->rollBack();
            json_error("IMEI $imei no encontrado en el inventario", 404);
        }
        if (!empty($fila['vendido'])) {
            db()->rollBack();
            json_error("El IMEI $imei ya está vendido, no se puede trasladar", 409);
        }

        // La ubicación guardada manda sobre la que mandó la app: si
        // otro usuario ya lo movió, la bitácora tiene que reflejar de
        // dónde salió de verdad.
        $origenReal = trim((string)($fila['ubicacion'] ?? ''));
        if ($origenReal !== '' && $origenReal === $destino) {
            db()->rollBack();
            json_error("El IMEI $imei ya está en $destino", 409);
        }
        if ($origenReal !== '') $origen = $origenReal;

        $sets   = ['ubicacion = ?'];
        $params = [$destino];
        if (tabla_tiene('stock_imei', 'actualizado_en')) {
            $sets[] = 'actualizado_en = NOW()';
        }
        $params[] = (int)$fila['id'];
        db()->prepare(
            'UPDATE stock_imei SET ' . implode(', ', $sets) . ' WHERE id = ?'
        )->execute($params);

        if ($codigo === '') $codigo = (string)($fila['producto_codigo'] ?? '');
        $nombreProducto = trim((string)($fila['producto_nombre'] ?? ''));
        if ($nombreProducto === '') $nombreProducto = traslado_nombre_producto($codigo);

        traslado_audit('stock_imei', (int)$fila['id'], 'TRASLADO', $usuario,
            ['ubicacion' => $origen], ['ubicacion' => $destino]);

    } else {
        // ── Caso producto suelto: mover unidades entre dos filas ──
        if ($origen === '') {
            db()->rollBack();
            json_error('Falta la tienda de origen', 400);
        }

        $sql = 'SELECT * FROM productos WHERE codigo = ? AND tienda = ?'
             . filtro_no_eliminado('productos')
             . ' FOR UPDATE';
        $stmt = db()->prepare($sql);
        $stmt->execute([$codigo, $origen]);
        $filaOrigen = $stmt->fetch();

        if (!$filaOrigen) {
            db()->rollBack();
            json_error("El producto $codigo no existe en $origen", 404);
        }

        $disponible = (int)($filaOrigen['stock_manual'] ?? 0);
        if ($disponible < $cantidad) {
            db()->rollBack();
            json_error(
                "No hay suficiente stock en $origen. Disponible: $disponible", 409);
        }

        $stockOrigen = $disponible - $cantidad;
        db()->prepare('UPDATE productos SET stock_manual = ? WHERE id = ?')
            ->execute([$stockOrigen, (int)$filaOrigen['id']]);

        // La fila del destino se busca SIN filtrar por `eliminado_en`.
        // El UNIQUE (codigo, tienda) también cuenta las filas borradas
        // lógicamente, así que si existe una hay que revivirla: un
        // INSERT chocaría con "Duplicate entry" y el traslado fallaría
        // sin motivo aparente para el usuario.
        $stmt = db()->prepare(
            'SELECT * FROM productos WHERE codigo = ? AND tienda = ? FOR UPDATE');
        $stmt->execute([$codigo, $destino]);
        $filaDestino = $stmt->fetch();

        if ($filaDestino) {
            // Si estaba borrada, vuelve con el stock trasladado y nada
            // más; si estaba viva, se le suman las unidades.
            $borrada = array_key_exists('eliminado_en', $filaDestino)
                       && $filaDestino['eliminado_en'] !== null;
            $stockDestino = $borrada
                ? $cantidad
                : (int)($filaDestino['stock_manual'] ?? 0) + $cantidad;

            $sets   = ['stock_manual = ?'];
            $params = [$stockDestino];
            if (tabla_tiene('productos', 'eliminado_en')) {
                $sets[] = 'eliminado_en = NULL';
            }
            if (tabla_tiene('productos', 'actualizado_en')) {
                $sets[] = 'actualizado_en = NOW()';
            }
            $params[] = (int)$filaDestino['id'];
            db()->prepare(
                'UPDATE productos SET ' . implode(', ', $sets) . ' WHERE id = ?'
            )->execute($params);
        } else {
            // No hay ficha en el destino: se clona la del origen con el
            // stock trasladado. Se copian todas las columnas descriptivas
            // que la tabla tenga hoy, así el precio, la marca y la
            // categoría viajan con el producto sin listar campo por campo.
            $nueva = $filaOrigen;
            foreach (['id', 'creado_en', 'actualizado_en', 'eliminado_en'] as $c) {
                unset($nueva[$c]);
            }
            $nueva['tienda']       = $destino;
            $nueva['stock_manual'] = $cantidad;
            $stockDestino = $cantidad;
            insertar_en('productos', $nueva);
        }

        $nombreProducto = (string)($filaOrigen['nombre'] ?? '');

        traslado_audit('productos', (int)$filaOrigen['id'], 'TRASLADO', $usuario,
            ['tienda' => $origen,  'stock_manual' => $disponible],
            ['tienda' => $destino, 'cantidad' => $cantidad,
             'stock_origen' => $stockOrigen, 'stock_destino' => $stockDestino]);
    }

    // ── Bitácora ─────────────────────────────────────────────────
    // Se arma con las columnas que `traslados` tenga realmente, para
    // que un cambio de esquema no tire abajo el traslado entero.
    $trasladoId = insertar_en('traslados', [
        'fecha'           => date('Y-m-d H:i:s'),
        'producto_codigo' => $codigo,
        'producto_nombre' => $nombreProducto,
        'imei'            => $tipo === 'imei' ? $imei : '',
        'cantidad'        => $cantidad,
        'tienda_origen'   => $origen,
        'tienda_destino'  => $destino,
        'nota'            => $nota,
        'usuario'         => $usuario,
    ]);

    db()->commit();

    json_response([
        'ok'              => true,
        'traslado_id'     => $trasladoId,
        'tipo'            => $tipo,
        'producto_codigo' => $codigo,
        'producto_nombre' => $nombreProducto,
        'imei'            => $tipo === 'imei' ? $imei : '',
        'cantidad'        => $cantidad,
        'tienda_origen'   => $origen,
        'tienda_destino'  => $destino,
        'stock_origen'    => $stockOrigen,
        'stock_destino'   => $stockDestino,
        'message'         => $tipo === 'imei'
            ? "IMEI $imei trasladado a $destino"
            : "$cantidad × $codigo trasladado de $origen a $destino",
    ]);

} catch (Throwable $e) {
    if (db()->inTransaction()) db()->rollBack();
    throw $e;
}

// ── Helpers locales ─────────────────────────────────────────────

/** Nombre del producto por código, o '' si no se encuentra. */
function traslado_nombre_producto(string $codigo): string {
    if ($codigo === '') return '';
    $stmt = db()->prepare(
        'SELECT nombre FROM productos WHERE codigo = ? ORDER BY id LIMIT 1');
    $stmt->execute([$codigo]);
    return (string)($stmt->fetchColumn() ?: '');
}

/**
 * Llama a `audit()` solo si el proyecto la tiene cargada, y nunca deja
 * que falle hacia afuera: la auditoría es un extra, que se rompa no
 * puede impedir un traslado válido ni revertir la transacción.
 */
function traslado_audit(string $tabla, int $id, string $accion,
                        ?string $usuario, $antes, $despues): void {
    if (!function_exists('audit')) return;
    try {
        audit($tabla, $id, $accion,
              ($usuario ?? '') !== '' ? $usuario : null, $antes, $despues);
    } catch (Throwable $e) {
        // Silencio deliberado.
    }
}
