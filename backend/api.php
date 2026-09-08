<?php
// ════════════════════════════════════════════════════════════════════
//  api.php — Router central de la API Tecno Líder
// ════════════════════════════════════════════════════════════════════
//
//  CONVENCIÓN:
//    GET    /api.php?resource=X           → listar
//    GET    /api.php?resource=X&id=N      → obtener uno
//    POST   /api.php?resource=X           → crear (body JSON)
//    PUT    /api.php?resource=X&id=N      → actualizar (body JSON)
//    DELETE /api.php?resource=X&id=N      → soft-delete
//
//  Recursos disponibles: ver array $endpoints abajo.
// ════════════════════════════════════════════════════════════════════

declare(strict_types=1);

require_once __DIR__ . '/lib/db.php';
require_once __DIR__ . '/lib/response.php';
require_once __DIR__ . '/lib/crud.php';

handle_cors();

// ── Red de seguridad para errores fatales ────────────────────────────
//  `safe_run()` atrapa las excepciones, pero NO los errores fatales de
//  PHP (un archivo que no existe, un método sobre null, memoria
//  agotada). Ante uno de esos, PHP corta la ejecución y nginx devuelve
//  un 500 con el cuerpo VACÍO: la app no encuentra ningún mensaje que
//  mostrar y el usuario solo ve "Error interno del servidor", sin
//  ninguna pista de qué endpoint falló ni por qué.
//
//  Este handler convierte ese caso en un JSON con el archivo y la línea
//  exactos, que la app ya sabe leer del campo `detalles`.
register_shutdown_function(static function (): void {
    $err = error_get_last();
    if ($err === null) return;

    $fatales = E_ERROR | E_PARSE | E_CORE_ERROR | E_CORE_WARNING
             | E_COMPILE_ERROR | E_USER_ERROR;
    if (($err['type'] & $fatales) === 0) return;

    // Si ya se mandó una respuesta buena, un aviso tardío no la pisa.
    if (headers_sent()) return;

    http_response_code(500);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode([
        'error'    => 'Error fatal en el servidor',
        'detalles' => $err['message'] . ' — ' .
                      basename((string)$err['file']) . ':' . $err['line'],
        'resource' => $_GET['resource'] ?? null,
    ], JSON_UNESCAPED_UNICODE);
});

// ── Errores de negocio que la app pueda mostrar ──────────────────────
//  La app instalada (`_Api._parse` en main.dart) trata los códigos 4xx
//  de una forma que hay que tener en cuenta desde acá, porque el
//  cliente ya está compilado y no se puede cambiar:
//
//    · 404 y 409 → DESCARTA el mensaje del servidor y muestra uno
//      genérico. Un "No hay suficiente stock en Principal" llega al
//      usuario como "Recurso no encontrado", que además hace pensar
//      que el endpoint no está instalado.
//    · Cualquier otro 4xx → si el JSON no trae la clave `ok`, la app
//      NI SIQUIERA lo toma como error: devuelve el cuerpo como si
//      fuera un resultado válido y la pantalla muestra que la
//      operación salió bien cuando en realidad falló.
//
//  Con `ok: false` presente, la app lanza el error con el texto de
//  `error`, que es justo lo que queremos mostrar. Así que normalizamos
//  toda respuesta de error acá, una sola vez, para todos los endpoints:
//  se agrega `ok: false` y se bajan 404/409 a 400.
//
//  401 y 403 se dejan como están: sus mensajes genéricos ("Sesión
//  expirada", "No tiene permisos") ya son correctos.
ob_start('respuesta_compatible_con_app');

function respuesta_compatible_con_app(string $cuerpo): string {
    $code = http_response_code();
    if (!is_int($code) || $code < 400 || $code >= 500) return $cuerpo;
    if ($code === 401 || $code === 403) return $cuerpo;

    $json = json_decode($cuerpo, true);
    // Solo tocamos cuerpos de error reconocibles. Cualquier otra cosa
    // (una lista, HTML, texto suelto) se deja intacta.
    if (!is_array($json)) return $cuerpo;
    if (!isset($json['error']) && !isset($json['message'])) return $cuerpo;

    if (!array_key_exists('ok', $json)) $json = ['ok' => false] + $json;
    if ($code === 404 || $code === 409) http_response_code(400);

    $salida = json_encode($json, JSON_UNESCAPED_UNICODE);
    return $salida === false ? $cuerpo : $salida;
}

// El recurso viene en ?resource=...
$resource = get_param('resource');
if ($resource === null) {
    json_error(
        'Falta parámetro `resource`. Ej: ?resource=productos',
        400,
        ['endpoints_disponibles' => array_keys(get_endpoints())]
    );
}

$endpoints = get_endpoints();

if (!isset($endpoints[$resource])) {
    json_error("Recurso '$resource' no existe",
        404, ['endpoints_disponibles' => array_keys($endpoints)]);
}

$handler = __DIR__ . '/endpoints/' . $endpoints[$resource];
if (!file_exists($handler)) {
    json_error("Handler no encontrado: " . $endpoints[$resource], 500);
}

safe_run(function () use ($handler) {
    require $handler;
});


/**
 * Mapa de recursos → archivo handler.
 * Para añadir un endpoint nuevo, crear el archivo en endpoints/ y
 * añadirlo aquí.
 */
function get_endpoints(): array {
    return [
        // ── Core ─────────────────────────────────────────────
        'usuarios'                  => 'usuarios.php',
        'tiendas'                   => 'tiendas.php',
        'configuracion'             => 'configuracion.php',

        // ── Licencia ─────────────────────────────────────────
        'licencia/estado'           => 'licencia_estado.php',
        'licencia/log'              => 'licencia_log.php',

        // ── Catálogo ─────────────────────────────────────────
        'productos'                 => 'productos.php',
        'diagnostico_bd'            => 'diagnostico_bd.php',
        'stock_imei'                => 'stock_imei.php',
        'stock_disponible'          => 'stock_disponible.php',  // vista

        // ── Clientes ─────────────────────────────────────────
        'clientes'                  => 'clientes.php',

        // ── Ventas / Facturación ─────────────────────────────
        'facturas'                  => 'facturas.php',

        // ── Cuentas por Cobrar ───────────────────────────────
        'cuentas_cobrar'            => 'cuentas_cobrar.php',
        // Operaciones que no encajan en el CRUD genérico porque tocan
        // varias tablas a la vez (cabecera + cuotas + pagos +
        // comprobantes) o hacen cálculos con el saldo a favor.
        'cuenta_cobrar_aumentar'    => 'cuenta_cobrar_aumentar.php',
        'cuenta_cobrar_eliminar'    => 'cuenta_cobrar_eliminar.php',
        'abono_eliminar'            => 'abono_eliminar.php',

        // ── Comprobantes (fotos y PDFs adjuntos) ─────────────
        // Un solo handler para las dos operaciones: GET lista,
        // POST guarda. La app usa un nombre distinto para cada una.
        'comprobantes'              => 'comprobantes.php',
        'comprobante_guardar'       => 'comprobantes.php',

        // ── Cuentas por Pagar (empleados) ────────────────────
        'cuentas_pagar'             => 'cuentas_pagar.php',

        // ── Cuentas por Pagar (proveedores) ──────────────────
        // Alias: la app usa "cuentas_proveedor", endpoint real
        // es "cuentas_pagar_proveedor"
        'cuentas_pagar_proveedor'   => 'cuentas_pagar_proveedor.php',
        'cuentas_proveedor'         => 'cuentas_pagar_proveedor.php', // alias compatibilidad

        // ── Servicio Técnico ─────────────────────────────────
        'servicios'                 => 'servicios.php',

        // ── Cierre de caja ───────────────────────────────────
        'cierres'                   => 'cierres.php',
        'extracciones'              => 'extracciones.php',

        // ── Comisiones ───────────────────────────────────────
        'comisiones_categorias'     => 'comisiones_categorias.php',
        'comisiones_historial'      => 'comisiones_historial.php',
        // Alias: la app llama "comisiones" esperando historial completo
        // (lista de períodos calculados con detalle por vendedor)
        'comisiones'                => 'comisiones_historial.php',

        // ── Listas de Precios ────────────────────────────────
        'listas_precios'            => 'listas_precios.php',

        // ── Tasa BCV ─────────────────────────────────────────
        'tasa_bcv'                  => 'tasa_bcv.php',

        // ── Líneas (legacy — la app aún lo carga) ────────────
        // Devolvemos lista vacía para no romper el inicio de sesión
        'lineas'                    => 'lineas.php',

        // ── Mensajería ───────────────────────────────────────
        'mensajes'                  => 'mensajes.php',
        'notificaciones'            => 'notificaciones.php',

        // ── Conciliación BDV ─────────────────────────────────
        'conciliaciones_bdv'        => 'conciliaciones_bdv.php',

        // ── Cashea ───────────────────────────────────────────
        'ordenes_cashea'            => 'ordenes_cashea.php',

        // ── Auditoría ────────────────────────────────────────
        'auditoria'                 => 'auditoria.php',

        // ── Pagos de financiadoras (Weppa/Krece/Cashea → tienda) ──
        'pagos_financiadora'        => 'pagos_financiadora.php',

        // ── Compras (entradas de mercancía, panel Costos) ────
        'compras'                   => 'compras.php',

        // ── Snapshot mensual del inventario inicial (por tienda) ──
        'inventario_inicial'        => 'inventario_inicial.php',

        // ── Traslados entre tiendas ──────────────────────────
        'traslados'                 => 'traslados.php',
        // Traslado atómico: mueve el IMEI o el stock y escribe la
        // bitácora en una sola transacción. La app lo llama al
        // confirmar un traslado; sin él la pantalla falla con
        // "Recurso no encontrado".
        'traslado_aplicar'          => 'traslado_aplicar.php',

        // ── Cotizaciones (presupuestos) ──────────────────────
        // Un solo handler para las cuatro operaciones: comparten las
        // tablas `cotizaciones` y `cotizacion_items`.
        'cotizaciones'              => 'cotizaciones.php',
        'cotizacion_guardar'        => 'cotizaciones.php',
        'cotizacion_cobrar'         => 'cotizaciones.php',
        'cotizacion_eliminar'       => 'cotizaciones.php',

        // ── Imágenes de producto (para el PDF de cotización) ──
        'producto_imagenes'         => 'producto_imagenes.php',
        'producto_imagen_guardar'   => 'producto_imagenes.php',

        // ── Diagnóstico ──────────────────────────────────────
        'diagnostico_factura_cuotas' => 'diagnostico_factura_cuotas.php',
        // Chequeo de salud + reparación idempotente del esquema.
        // Abrirlo en el navegador después de cada despliegue: dice si
        // falta alguna tabla y si algún recurso quedó registrado sin
        // que se subiera su archivo.
        'reparar_esquema'           => 'reparar_esquema.php',
    ];
}
