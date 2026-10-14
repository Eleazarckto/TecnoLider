<?php
// ════════════════════════════════════════════════════════════════════
//  Endpoint: /api.php?resource=stock_ingresar   (POST)
// ════════════════════════════════════════════════════════════════════
//  Ingresa mercancía DIRECTO en una tienda, aunque el producto todavía
//  no tenga fila en ella. La app lo usa desde "Ingreso rápido de
//  stock" y al crear un producto con cantidades en varias tiendas.
//
//  Por qué hace falta: `productos` tiene UNIQUE (codigo, tienda) y
//  borrado lógico. Si el producto ya estuvo en esa tienda y se borró,
//  la fila borrada sigue ocupando el índice y un POST normal a
//  `productos` falla con "Duplicate entry". Acá se revive.
//
//  Body:
//    codigo     SKU del producto
//    tienda     tienda donde entra la mercancía
//    cantidad   unidades a sumar (> 0)
//    producto   datos del producto (nombre, categoria, marca, precios...)
//               para crear la fila si no existe en ninguna tienda
//
//  Responde: { ok, id, stock_manual, creada, revivida }
// ════════════════════════════════════════════════════════════════════

require_once __DIR__ . '/../lib/esquema.php';

$metodo = $_SERVER['REQUEST_METHOD'];
if ($metodo !== 'POST') json_error('Método no permitido, usá POST', 405);

$body     = json_body();
$codigo   = trim((string)($body['codigo'] ?? ''));
$tienda   = trim((string)($body['tienda'] ?? ''));
$cantidad = (int)($body['cantidad'] ?? 0);
$datos    = is_array($body['producto'] ?? null) ? $body['producto'] : [];

if ($codigo === '')  json_error('Falta el código del producto', 400);
if ($cantidad <= 0)  json_error('La cantidad debe ser mayor a 0', 400);

// Columnas descriptivas que viajan con el producto. `id`, `tienda`,
// `stock_manual` y las fechas las decide este endpoint.
$descriptivas = ['nombre', 'categoria', 'marca', 'modelo', 'tipo',
    'precio_costo', 'precio_venta', 'porcentaje_bateria',
    'producto_padre_codigo', 'variante'];

db()->beginTransaction();
try {
    // Sin filtrar `eliminado_en`: una fila borrada también cuenta.
    $stmt = db()->prepare(
        'SELECT * FROM productos WHERE codigo = ? AND tienda = ? FOR UPDATE');
    $stmt->execute([$codigo, $tienda]);
    $fila = $stmt->fetch();

    $creada = false;
    $revivida = false;

    if ($fila) {
        $borrada = array_key_exists('eliminado_en', $fila)
                   && $fila['eliminado_en'] !== null;
        // Viva: se suma. Borrada: vuelve con lo que entra ahora y con
        // los datos actuales del producto (los viejos pueden estar
        // desactualizados, p.ej. el precio).
        $stock = $borrada
            ? $cantidad
            : (int)($fila['stock_manual'] ?? 0) + $cantidad;
        $sets   = ['stock_manual = ?'];
        $params = [$stock];
        if ($borrada) {
            $revivida = true;
            foreach (solo_columnas_reales('productos',
                         array_intersect_key($datos, array_flip($descriptivas)))
                     as $col => $val) {
                $sets[]   = "`$col` = ?";
                $params[] = $val;
            }
            if (tabla_tiene('productos', 'eliminado_en')) {
                $sets[] = 'eliminado_en = NULL';
            }
        }
        if (tabla_tiene('productos', 'actualizado_en')) {
            $sets[] = 'actualizado_en = NOW()';
        }
        $params[] = (int)$fila['id'];
        db()->prepare(
            'UPDATE productos SET ' . implode(', ', $sets) . ' WHERE id = ?'
        )->execute($params);
        $id = (int)$fila['id'];
    } else {
        // No existe en esta tienda: se clona una fila viva del mismo
        // código (trae todas las columnas que la tabla tenga hoy) y, si
        // no hay ninguna, se usan los datos que mandó la app.
        $stmt = db()->prepare('SELECT * FROM productos WHERE codigo = ?'
            . filtro_no_eliminado('productos') . ' ORDER BY id LIMIT 1');
        $stmt->execute([$codigo]);
        $base = $stmt->fetch();
        if ($base) {
            foreach (['id', 'creado_en', 'actualizado_en', 'eliminado_en'] as $c) {
                unset($base[$c]);
            }
            $nueva = $base;
        } else {
            $nueva = array_intersect_key($datos, array_flip($descriptivas));
            if (trim((string)($nueva['nombre'] ?? '')) === '') {
                db()->rollBack();
                json_error("El producto $codigo no existe; faltan sus datos", 400);
            }
        }
        $nueva['codigo']       = $codigo;
        $nueva['tienda']       = $tienda;
        $nueva['stock_manual'] = $cantidad;
        $stock  = $cantidad;
        $id     = insertar_en('productos', $nueva);
        $creada = true;
    }

    db()->commit();

    json_response([
        'ok'           => true,
        'id'           => $id,
        'codigo'       => $codigo,
        'tienda'       => $tienda,
        'stock_manual' => $stock,
        'creada'       => $creada,
        'revivida'     => $revivida,
        'message'      => "$cantidad × $codigo ingresado en "
                          . ($tienda === '' ? 'inventario general' : $tienda),
    ]);
} catch (Throwable $e) {
    if (db()->inTransaction()) db()->rollBack();
    throw $e;
}
