<?php
// Endpoint: /api.php?resource=diagnostico_bd
//
// Verifica el estado completo de la base de datos. Comprueba:
//   1) Conexión al MySQL
//   2) Base de datos correcta
//   3) Tablas críticas presentes
//   4) Columnas críticas de cada tabla
//   5) Cantidad de filas por tabla
//   6) Constraints UNIQUE que pueden causar bugs
//
// Se puede llamar sin autenticación desde el navegador para verificar
// rápidamente si todo está bien. Solo lectura, no modifica nada.

$pdo = db();
$pdo->setAttribute(PDO::ATTR_DEFAULT_FETCH_MODE, PDO::FETCH_ASSOC);

$resultado = [
    'timestamp'   => date('Y-m-d H:i:s'),
    'conexion'    => 'OK',
    'base_datos'  => null,
    'tablas'      => [],
    'faltantes'   => [],
    'constraints_criticas' => [],
    'resumen'     => [],
];

try {
    $resultado['base_datos'] = $pdo->query('SELECT DATABASE()')->fetchColumn();
} catch (Throwable $e) {
    $resultado['conexion'] = 'ERROR: ' . $e->getMessage();
    json_response($resultado, 500);
}

// Definir las tablas y columnas críticas que deben existir
$esperado = [
    'usuarios'         => ['id', 'nombre', 'correo', 'rol', 'tienda', 'gana_comisiones'],
    'tiendas'          => ['id', 'nombre', 'direccion', 'telefono', 'rif', 'correo', 'logo_base64', 'activa'],
    'productos'        => ['id', 'codigo', 'nombre', 'categoria', 'marca', 'modelo',
                           'precio_costo', 'precio_venta', 'stock_manual', 'tienda',
                           'producto_padre_codigo', 'eliminado_en'],
    'stock_imei'       => ['id', 'imei', 'producto_codigo', 'ubicacion', 'vendido',
                           'factura_id', 'eliminado_en'],
    'facturas'         => ['id', 'nro_factura', 'cliente', 'cedula', 'vendedor',
                           'tienda', 'fecha', 'total', 'eliminado_en'],
    'factura_equipos'  => ['id', 'factura_id', 'imei', 'vendedor'],
    'factura_items'    => ['id', 'factura_id', 'producto_codigo', 'cantidad', 'vendedor'],
    'factura_pagos'    => ['id', 'factura_id', 'metodo', 'tipo', 'financiadora',
                           'monto', 'es_inicial', 'numero_cuotas', 'monto_cuota'],
    'clientes'         => ['id', 'cedula', 'nombre', 'telefono'],
    'listas_precios'   => ['id', 'nombre', 'financiadora'],
    'traslados'        => ['id', 'fecha', 'producto_codigo', 'imei', 'cantidad',
                           'tienda_origen', 'tienda_destino'],
    'cierres'          => ['id', 'fecha', 'tienda'],
    'cuentas_cobrar'   => ['id', 'cliente', 'monto'],
    'configuracion'    => ['id', 'clave', 'valor'],
    'servicios'        => ['id', 'nombre_cliente', 'monto'],
    'comisiones_historial' => ['id', 'periodo', 'vendedor', 'total_pagar'],
    'pagos_financiadora'   => ['id', 'financiadora', 'monto', 'fecha'],
];

// Cargar todas las tablas existentes
$tablasExistentes = [];
try {
    $tablasExistentes = $pdo->query(
        "SELECT TABLE_NAME
         FROM INFORMATION_SCHEMA.TABLES
         WHERE TABLE_SCHEMA = DATABASE()"
    )->fetchAll(PDO::FETCH_COLUMN);
} catch (Throwable $e) {
    $resultado['error'] = 'No se pudo listar tablas: ' . $e->getMessage();
    json_response($resultado, 500);
}
$setTablas = array_flip($tablasExistentes);

// Revisar cada tabla esperada
foreach ($esperado as $tabla => $colsRequeridas) {
    $info = [
        'existe'      => isset($setTablas[$tabla]),
        'columnas_ok' => [],
        'columnas_faltantes' => [],
        'total_filas' => null,
    ];
    if (!$info['existe']) {
        $resultado['faltantes'][] = "Tabla '$tabla' NO existe";
        $resultado['tablas'][$tabla] = $info;
        continue;
    }
    // Traer columnas reales
    $cols = [];
    try {
        $cols = $pdo->query(
            "SELECT COLUMN_NAME
             FROM INFORMATION_SCHEMA.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '$tabla'"
        )->fetchAll(PDO::FETCH_COLUMN);
    } catch (Throwable $e) {
        $info['error'] = $e->getMessage();
    }
    $setCols = array_flip($cols);
    foreach ($colsRequeridas as $c) {
        if (isset($setCols[$c])) {
            $info['columnas_ok'][] = $c;
        } else {
            $info['columnas_faltantes'][] = $c;
            $resultado['faltantes'][] = "Columna '$tabla.$c' NO existe";
        }
    }
    // Contar filas
    try {
        $info['total_filas'] = (int) $pdo->query("SELECT COUNT(*) FROM `$tabla`")->fetchColumn();
    } catch (Throwable $e) {
        $info['total_filas'] = 'error: ' . $e->getMessage();
    }
    $resultado['tablas'][$tabla] = $info;
}

// Revisar constraints UNIQUE críticas que causaron bugs conocidos
// productos.codigo: si es UNIQUE solo, no permite mismo producto en varias tiendas
try {
    $rows = $pdo->query(
        "SELECT INDEX_NAME, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS columnas
         FROM INFORMATION_SCHEMA.STATISTICS
         WHERE TABLE_SCHEMA = DATABASE()
           AND TABLE_NAME = 'productos'
           AND NON_UNIQUE = 0
         GROUP BY INDEX_NAME"
    )->fetchAll();
    $tieneUniqueSoloCodigo = false;
    $tieneUniqueComposite = false;
    foreach ($rows as $r) {
        $cols = $r['columnas'];
        if ($cols === 'codigo') $tieneUniqueSoloCodigo = true;
        if ($cols === 'codigo,tienda' || $cols === 'tienda,codigo') $tieneUniqueComposite = true;
    }
    $resultado['constraints_criticas']['productos'] = [
        'unique_solo_codigo'      => $tieneUniqueSoloCodigo,
        'unique_codigo_tienda'    => $tieneUniqueComposite,
        'estado' => $tieneUniqueSoloCodigo && !$tieneUniqueComposite
            ? 'PROBLEMA: UNIQUE(codigo) impide múltiples tiendas'
            : ($tieneUniqueComposite ? 'OK: permite mismo código en distintas tiendas' : 'Sin UNIQUE'),
        'indices_actuales' => $rows,
    ];
} catch (Throwable $e) {
    $resultado['constraints_criticas']['productos'] = ['error' => $e->getMessage()];
}

// Resumen final
$totalFaltantes = count($resultado['faltantes']);
$resultado['resumen'] = [
    'tablas_verificadas' => count($esperado),
    'tablas_existentes'  => count(array_filter($resultado['tablas'], fn($t) => $t['existe'])),
    'problemas_encontrados' => $totalFaltantes,
    'estado_general' => $totalFaltantes === 0 ? 'TODO OK' : "REVISAR: $totalFaltantes problema(s)",
];

json_response($resultado);
