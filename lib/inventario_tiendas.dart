part of 'main.dart';

// ════════════════════════════════════════════════════════════
//  INVENTARIO Y ACCESO POR TIENDA
// ════════════════════════════════════════════════════════════
//  Tres cosas que pidió el dueño y que comparten la misma idea de
//  "cada tienda es dueña de su stock":
//   1. Ingresar mercancía DIRECTO en la tienda elegida, aunque el
//      producto todavía no tenga fila en esa tienda (antes se sumaba
//      a la fila de otra tienda, normalmente la principal, y había que
//      hacer un traslado a mano).
//   2. Filtros (categoría, marca, modelo, texto) al exportar el
//      inventario a Excel o PDF.
//   3. Un vendedor sólo factura en su tienda asignada; puede consultar
//      el inventario de las otras, pero no venderlo ni cambiarse.
// ════════════════════════════════════════════════════════════

// ── 3. ACCESO POR TIENDA ────────────────────────────────────

/// Roles que pueden trabajar en cualquier tienda. El resto (Vendedor,
/// Activador, Encargado...) queda atado a la tienda de su ficha de
/// usuario. Gerente se mantiene libre porque el resto del sistema ya
/// lo trata como rol alto (`puedeVerTodasLasTiendas`).
const Set<String> kRolesSinRestriccionDeTienda = {
  'Dueño', 'Administrador', 'Gerente', 'Maestro',
};

/// true si [rol] sólo puede facturar en su tienda asignada.
bool rolRestringidoATienda(String? rol) =>
    !kRolesSinRestriccionDeTienda.contains((rol ?? '').trim());

/// Tienda que figura en la ficha del usuario (tabla `usuarios`), tal
/// como vino del servidor al iniciar sesión. Hace falta guardarla
/// aparte porque `usuarioSesion.tienda` se pisa con la tienda que se
/// elige en el login, y así se perdía cuál era la asignada.
String tiendaAsignadaSesion = '';

/// Tienda en la que DEBE abrir la sesión un usuario, o null si puede
/// elegir libremente.
///
/// Sólo se fuerza si el rol está restringido y tiene tienda asignada.
/// Si la tienda asignada ya no existe en la lista (la renombraron o la
/// borraron) no se fuerza, para no dejar al vendedor sin poder entrar;
/// el administrador debe corregirle la ficha. Se compara sin mayúsculas
/// ni espacios y se devuelve el nombre tal como está en [tiendas].
String? tiendaForzadaParaLogin({
  required String rol,
  required String tiendaAsignada,
  required List<String> tiendas,
}) {
  final asignada = tiendaAsignada.trim();
  if (!rolRestringidoATienda(rol) || asignada.isEmpty) return null;
  if (tiendas.isEmpty) return asignada;
  final clave = asignada.toLowerCase();
  for (final t in tiendas) {
    if (t.trim().toLowerCase() == clave) return t;
  }
  return null;
}

/// Mensaje de por qué [rol] NO puede facturar en [tiendaVenta], o null
/// si puede. Lógica pura para poder probarla sin sesión.
String? motivoNoPuedeFacturar({
  required String rol,
  required String tiendaAsignada,
  required String tiendaVenta,
}) {
  if (!rolRestringidoATienda(rol)) return null;
  final asignada = tiendaAsignada.trim();
  if (asignada.isEmpty) return null; // sin tienda en la ficha: no se ata
  if (tiendaVenta.trim().toLowerCase() == asignada.toLowerCase()) return null;
  return 'Tu usuario está asignado a "$asignada": sólo puedes facturar '
      'ahí. Puedes consultar el inventario de "${tiendaVenta.trim()}", '
      'pero la venta la debe hacer esa tienda.';
}

/// [motivoNoPuedeFacturar] con el usuario de la sesión actual.
String? motivoNoPuedeFacturarEnSesion(String tiendaVenta) =>
    motivoNoPuedeFacturar(
      rol: usuarioSesion?.rol ?? '',
      tiendaAsignada: tiendaAsignadaSesion,
      tiendaVenta: tiendaVenta,
    );

// ── Asignar la tienda desde la ficha del usuario ────────────
// Las reglas de arriba usan `usuarios.tienda`, pero la ventana de
// Usuarios no tenía dónde elegirla (y al editar la ponía en ''), así
// que en producción ningún vendedor tenía tienda y la restricción no
// se aplicaba a nadie.

/// Texto de la opción "sin tienda" del selector de la ficha.
const String kTextoSinTiendaUsuario = 'Sin tienda (todas)';

/// Valores del selector de tienda de la ficha de un usuario: '' (sin
/// tienda) + las tiendas configuradas. Si la tienda guardada ya no está
/// en la lista (la renombraron o la borraron) se agrega igual, para que
/// el selector no se rompa y el administrador vea qué tenía.
List<String> opcionesTiendaUsuario(List<String> tiendas, String actual) {
  final opciones = <String>[''];
  for (final t in tiendas) {
    final limpia = t.trim();
    if (limpia.isNotEmpty && !opciones.contains(limpia)) opciones.add(limpia);
  }
  final a = actual.trim();
  if (a.isNotEmpty && !opciones.contains(a)) opciones.add(a);
  return opciones;
}

/// Etiqueta de la tienda de un usuario para mostrar en su tarjeta.
String etiquetaTiendaUsuario(String tienda) =>
    tienda.trim().isEmpty ? kTextoSinTiendaUsuario : tienda.trim();

/// Cuántos usuarios de rol restringido (Vendedor, Activador,
/// Encargado...) no tienen tienda en su ficha: esos pueden facturar en
/// cualquier tienda.
int contarSinTiendaAsignada(Iterable<Usuario> usuarios) => usuarios
    .where((u) => rolRestringidoATienda(u.rol) && u.tienda.trim().isEmpty)
    .length;

/// Aviso para la ventana de Usuarios, o null si no falta ninguno.
String? avisoSinTiendaAsignada(Iterable<Usuario> usuarios) {
  final n = contarSinTiendaAsignada(usuarios);
  if (n == 0) return null;
  return n == 1
      ? '1 vendedor sin tienda asignada'
      : '$n vendedores sin tienda asignada';
}

// ── 1. INGRESO DE STOCK DIRECTO EN LA TIENDA ────────────────

/// Qué hay que hacer para sumar stock de un código en una tienda.
enum AccionIngresoStock {
  /// La tienda ya tiene su fila: se le suma.
  sumarFila,
  /// Sólo existe la fila general ('') y está vacía: se le asigna la
  /// tienda (no se pierde nada y no queda una fila huérfana).
  asignarFilaGeneral,
  /// La tienda no tiene fila: se crea (o revive) con los datos del
  /// producto.
  crearFila,
}

class PlanIngresoStock {
  final AccionIngresoStock accion;
  /// Fila sobre la que se opera (sumar/asignar) o que sirve de
  /// plantilla para crear la nueva (null si no hay ninguna fila).
  final Producto? fila;
  const PlanIngresoStock(this.accion, this.fila);
}

/// Decide cómo sumar stock de un código en [tienda] a partir de las
/// filas vivas de ese código ([filas], una por tienda).
///
/// ANTES el ingreso tomaba "la primera fila con ese código", que en la
/// práctica era la de la tienda principal: cargar 10 cargadores en la
/// sucursal los sumaba a la principal. Ahora nunca se toca la fila de
/// OTRA tienda.
PlanIngresoStock planIngresoStock(List<Producto> filas, String tienda) {
  final t = tienda.trim();
  final propia = filas.where((p) => p.tienda.trim() == t).firstOrNull;
  if (propia != null) return PlanIngresoStock(AccionIngresoStock.sumarFila, propia);
  final general = filas.where((p) => p.tienda.trim().isEmpty).firstOrNull;
  if (t.isNotEmpty && general != null && general.stockManual <= 0) {
    return PlanIngresoStock(AccionIngresoStock.asignarFilaGeneral, general);
  }
  return PlanIngresoStock(
      AccionIngresoStock.crearFila, general ?? filas.firstOrNull);
}

/// Copia de [p] (mismos datos) para la fila de otra tienda.
Producto copiaProductoParaTienda(Producto p, String tienda, int stock) =>
    Producto(
      codigo: p.codigo, nombre: p.nombre, categoria: p.categoria,
      marca: p.marca, modelo: p.modelo, tipo: p.tipo,
      precioCosto: p.precioCosto, precioVenta: p.precioVenta,
      stockManual: stock < 0 ? 0 : stock,
      porcentajeBateria: p.porcentajeBateria,
      productoPadreCodigo: p.productoPadreCodigo,
      variante: p.variante,
      tienda: tienda.trim(),
    );

/// true si el error dice que el endpoint no está instalado en el
/// servidor (registrado sin archivo, o directamente no registrado).
bool esErrorEndpointFaltante(String mensaje) =>
    mensaje.contains('Handler no encontrado') ||
    mensaje.contains('Recurso no encontrado') ||
    RegExp(r"Recurso '[^']*' no existe").hasMatch(mensaje);

/// true si el error es el choque con el UNIQUE (codigo, tienda).
bool esErrorDuplicado(String mensaje) =>
    mensaje.contains('Duplicate') ||
    mensaje.contains('1062') ||
    mensaje.contains('duplicado') ||
    mensaje.contains('UNIQUE');

/// Crea (o revive) la fila de [plantilla] en [tienda] con [cantidad]
/// unidades. Devuelve la fila nueva ya agregada a `catalogoGlobal`.
///
/// Primero usa el endpoint `stock_ingresar`, que lo hace en una
/// transacción y sabe revivir una fila borrada lógicamente (el UNIQUE
/// la sigue contando y un INSERT fallaría con "Duplicate entry"). Si el
/// servidor todavía no tiene ese endpoint, cae al POST normal de
/// `productos`, que sirve siempre que la fila no haya existido antes.
Future<(Producto?, String)> crearFilaProductoEnTienda(
    Producto plantilla, String tienda, int cantidad) async {
  final nueva = copiaProductoParaTienda(plantilla, tienda, cantidad);
  try {
    final r = await _Api.post('stock_ingresar', {
      'codigo': nueva.codigo,
      'tienda': nueva.tienda,
      'cantidad': cantidad,
      'producto': nueva.toMap(),
    });
    if (r is Map) {
      final id = r['id'];
      nueva.id = id is int ? id : int.tryParse('${id ?? ''}');
      final st = int.tryParse('${r['stock_manual'] ?? ''}');
      if (st != null) nueva.stockManual = st;
    }
    catalogoGlobal.add(nueva);
    return (nueva, 'Creado en ${nombreTiendaStock(tienda)}');
  } catch (e) {
    final msg = e.toString();
    if (!esErrorEndpointFaltante(msg)) {
      return (null, 'No se pudo crear en ${nombreTiendaStock(tienda)}: $msg');
    }
    debugPrint('[stock_ingresar] no instalado, uso POST productos: $msg');
  }
  try {
    final r = await _Api.post('productos', nueva.toMap());
    if (r is Map && r['id'] != null) {
      nueva.id = r['id'] is int ? r['id'] as int : int.tryParse('${r['id']}');
    }
    catalogoGlobal.add(nueva);
    return (nueva, 'Creado en ${nombreTiendaStock(tienda)}');
  } catch (e) {
    final msg = e.toString();
    if (esErrorDuplicado(msg)) {
      return (null,
          '"${plantilla.nombre}" ya estuvo registrado en '
          '${nombreTiendaStock(tienda)} y fue borrado; el servidor no deja '
          'volver a crearlo. Hay que subir al servidor el archivo '
          'backend/endpoints/stock_ingresar.php (y registrarlo en api.php). '
          'Mientras tanto, cárgalo en otra tienda y trasládalo.');
    }
    return (null, 'No se pudo crear en ${nombreTiendaStock(tienda)}: $msg');
  }
}

/// Suma [cantidad] unidades de [producto] en [tienda], creando la fila
/// de esa tienda si no existe. [filas] = filas vivas del código (por
/// defecto, las de `catalogoGlobal`).
Future<ResultadoAjusteStock> ingresarStockEnTienda(
    Producto producto, String tienda, int cantidad,
    {List<Producto>? filas}) async {
  final lista = (filas ?? catalogoGlobal)
      .where((p) => p.codigo == producto.codigo)
      .toList();
  final plan = planIngresoStock(lista, tienda);
  switch (plan.accion) {
    case AccionIngresoStock.sumarFila:
      return ajustarStockManual(plan.fila!, cantidad);
    case AccionIngresoStock.asignarFilaGeneral:
      final fila = plan.fila!;
      fila.tienda = tienda.trim();
      final res = await ajustarStockManual(fila, cantidad);
      if (!res.ok) fila.tienda = ''; // no quedó guardado: se revierte
      return res;
    case AccionIngresoStock.crearFila:
      if (cantidad <= 0) {
        return ResultadoAjusteStock(false,
            '${producto.nombre}: no hay stock en '
            '${nombreTiendaStock(tienda)} para descontar.', 0);
      }
      final (nueva, msg) = await crearFilaProductoEnTienda(
          plan.fila ?? producto, tienda, cantidad);
      if (nueva == null) return ResultadoAjusteStock(false, msg, 0);
      return ResultadoAjusteStock(true,
          '${producto.nombre}: 0 → ${nueva.stockManual} '
          '(nuevo en ${nombreTiendaStock(tienda)})', nueva.stockManual);
  }
}

// ── 2. FILTROS AL EXPORTAR EL INVENTARIO ────────────────────

/// Filtros del diálogo "Descargar inventario". Vacío = no filtra.
class FiltroExportInventario {
  final String categoria, marca, modelo, texto;
  const FiltroExportInventario({
    this.categoria = '', this.marca = '', this.modelo = '', this.texto = '',
  });

  bool get vacio =>
      categoria.isEmpty && marca.isEmpty && modelo.isEmpty &&
      texto.trim().isEmpty;

  /// Texto corto para el nombre del archivo / título del PDF.
  String get descripcion => [
        if (categoria.isNotEmpty) categoria,
        if (marca.isNotEmpty) marca,
        if (modelo.isNotEmpty) modelo,
        if (texto.trim().isNotEmpty) '"${texto.trim()}"',
      ].join(' · ');
}

String _normFiltro(String s) => s.trim().toLowerCase();

/// Modelos que no son un modelo real (los accesorios guardan "N/A").
bool esModeloVacio(String m) {
  final n = _normFiltro(m);
  return n.isEmpty || n == 'n/a' || n == 'na';
}

/// true si [p] pasa los filtros. Marca/modelo/categoría se comparan
/// sin mayúsculas; [texto] busca dentro del nombre, código, marca y
/// modelo (p.ej. "forro" dentro de Accesorios).
bool coincideFiltroExport(Producto p, FiltroExportInventario f) {
  if (f.categoria.isNotEmpty &&
      _normFiltro(p.categoria) != _normFiltro(f.categoria)) {
    return false;
  }
  if (f.marca.isNotEmpty && _normFiltro(p.marca) != _normFiltro(f.marca)) {
    return false;
  }
  if (f.modelo.isNotEmpty && _normFiltro(p.modelo) != _normFiltro(f.modelo)) {
    return false;
  }
  final q = _normFiltro(f.texto);
  if (q.isNotEmpty) {
    final hay = '${p.nombre} ${p.codigo} ${p.marca} ${p.modelo} ${p.tipo}'
        .toLowerCase();
    // Todas las palabras tienen que aparecer ("forro iphone").
    for (final palabra in q.split(RegExp(r'\s+'))) {
      if (!hay.contains(palabra)) return false;
    }
  }
  return true;
}

/// Valores distintos (ordenados, sin vacíos) de un campo, para armar
/// los desplegables del diálogo de exportación.
List<String> valoresDistintos(
    Iterable<Producto> productos, String Function(Producto) campo) {
  final vistos = <String, String>{};
  for (final p in productos) {
    final v = campo(p).trim();
    if (v.isEmpty) continue;
    vistos.putIfAbsent(v.toLowerCase(), () => v);
  }
  return vistos.values.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

/// Fila del inventario exportado.
class FilaExportInventario {
  final Producto producto;
  final int stock;
  const FilaExportInventario(this.producto, this.stock);
  double get valor => stock * producto.precioCosto;
}

/// PDF del inventario exportado (misma información que el Excel).
Future<Uint8List> generarPdfInventario({
  required List<FilaExportInventario> filas,
  required String tienda,
  required FiltroExportInventario filtro,
}) async {
  final doc = pw.Document();
  final total = filas.fold<double>(0, (s, f) => s + f.valor);
  final unidades = filas.fold<int>(0, (s, f) => s + f.stock);
  String usd(double v) => v.toStringAsFixed(2);
  final ahora = DateTime.now();
  final fecha = '${ahora.day.toString().padLeft(2, '0')}/'
      '${ahora.month.toString().padLeft(2, '0')}/${ahora.year} '
      '${ahora.hour.toString().padLeft(2, '0')}:'
      '${ahora.minute.toString().padLeft(2, '0')}';
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4.landscape,
    margin: const pw.EdgeInsets.all(24),
    build: (_) => [
      pw.Text('Inventario · ${tienda.isEmpty ? "Todas las tiendas" : tienda}',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      if (!filtro.vacio)
        pw.Text('Filtro: ${filtro.descripcion}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.Text('${filas.length} productos · $unidades unidades · '
          'Generado: $fecha',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      pw.SizedBox(height: 10),
      pw.TableHelper.fromTextArray(
        headers: const ['Código', 'Producto', 'Categoría', 'Marca', 'Modelo',
            'Stock', 'Costo \$', 'Venta \$', 'Valor \$'],
        data: [
          for (final f in filas)
            [
              f.producto.codigo, f.producto.nombre, f.producto.categoria,
              f.producto.marca,
              esModeloVacio(f.producto.modelo) ? '' : f.producto.modelo,
              '${f.stock}', usd(f.producto.precioCosto),
              usd(f.producto.precioVenta), usd(f.valor),
            ],
          ['', 'TOTAL', '', '', '', '$unidades', '', '', usd(total)],
        ],
        columnWidths: const {
          0: pw.FlexColumnWidth(1.4), 1: pw.FlexColumnWidth(3.2),
          2: pw.FlexColumnWidth(1.4), 3: pw.FlexColumnWidth(1.3),
          4: pw.FlexColumnWidth(1.4), 5: pw.FlexColumnWidth(0.7),
          6: pw.FlexColumnWidth(0.9), 7: pw.FlexColumnWidth(0.9),
          8: pw.FlexColumnWidth(1),
        },
        cellAlignments: const {
          5: pw.Alignment.centerRight, 6: pw.Alignment.centerRight,
          7: pw.Alignment.centerRight, 8: pw.Alignment.centerRight,
        },
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold,
            fontSize: 9, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
        cellStyle: const pw.TextStyle(fontSize: 8),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      ),
    ],
  ));
  return doc.save();
}
