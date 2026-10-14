part of 'main.dart';

// ============================================================
//  LISTAS DE PRECIOS — utilidades de exportación y propagación
//  de precios (orden de columnas, imagen sin franjas negras,
//  cambios de precio en serie, ajustes a mano que siguen al
//  precio del producto).
// ============================================================

/// Marcadores del bloque de financiamiento dentro del orden de
/// columnas de los documentos. Llevan `__` como las columnas
/// virtuales, así que nunca chocan con una columna real.
const String kColExportInicial = '__inicial__';
const String kColExportNCuotas = '__n_cuotas__';
const String kColExportMontoCuota = '__monto_cuota__';

/// Orden de las columnas del PDF y la imagen de [lista].
///
/// Devuelve los NOMBRES de las columnas de precio y, en las listas de
/// financiamiento, los marcadores [kColExportInicial],
/// [kColExportNCuotas] y [kColExportMontoCuota].
///
/// Regla: el mismo orden de la pantalla y de la lista.
///   · Lista normal: las columnas en el orden en que están en la lista.
///   · Financiamiento: primero el precio base (la primera columna, el
///     precio de venta de la financiadora), después la inicial y las
///     cuotas, y después el resto de las columnas (Divisas, BCV,
///     Cashea…) en el orden de la lista. El admin cambia ese orden con
///     "Mover a la izquierda / derecha" en el menú de cada columna.
///
/// Antes el bloque de inicial/cuotas salía al FINAL de todas las
/// columnas, así que el documento no coincidía con la pantalla.
///
/// [incluirColumnas] = false deja sólo el bloque de financiamiento
/// (opción "Mostrar las columnas de precio" desmarcada).
List<String> ordenColumnasExport(ListaPrecio lista,
    {bool incluirColumnas = true}) {
  final reales = lista.columnas
      .where((c) => !FormulaColumna.esNombreVirtual(c.nombre))
      .map((c) => c.nombre)
      .toList();
  if (!lista.esFinanciamiento) return reales;
  final bloque = <String>[
    kColExportInicial,
    if (lista.tieneCuotas) ...[kColExportNCuotas, kColExportMontoCuota],
  ];
  if (!incluirColumnas || reales.isEmpty) return bloque;
  return [reales.first, ...bloque, ...reales.skip(1)];
}

/// Mueve la columna [indice] de [lista] una posición ([delta] = -1 a
/// la izquierda, +1 a la derecha). La PRIMERA columna es el precio
/// base (sobre ella se calculan inicial y cuotas), así que no se mueve
/// ni se puede poner otra en su lugar. Devuelve true si se movió.
bool moverColumnaLista(ListaPrecio lista, int indice, int delta) {
  final destino = indice + delta;
  if (indice < 1 || destino < 1) return false;
  if (indice >= lista.columnas.length || destino >= lista.columnas.length) {
    return false;
  }
  final col = lista.columnas.removeAt(indice);
  lista.columnas.insert(destino, col);
  return true;
}

/// Pinta sobre fondo BLANCO una imagen RGBA (en el lugar).
///
/// Por qué: el rasterizador de `printing` arranca de un lienzo
/// TRANSPARENTE (en Windows rellena con 0x00FFFFFF, en Android usa un
/// Bitmap ARGB vacío). Todo lo que el PDF no pinta —las filas pares de
/// la tabla, los márgenes— quedaba con alfa 0 en el PNG. WhatsApp y
/// muchos visores muestran lo transparente en NEGRO: de ahí las franjas
/// negras alternadas con las grises de la imagen de la lista.
void aplanarSobreBlanco(Uint8List rgba) {
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    final a = rgba[i + 3];
    if (a == 255) continue;
    if (a == 0) {
      rgba[i] = 255;
      rgba[i + 1] = 255;
      rgba[i + 2] = 255;
    } else {
      // El rasterizador entrega color sin premultiplicar.
      final inv = 255 - a;
      rgba[i] = (rgba[i] * a + 255 * inv) ~/ 255;
      rgba[i + 1] = (rgba[i + 1] * a + 255 * inv) ~/ 255;
      rgba[i + 2] = (rgba[i + 2] * a + 255 * inv) ~/ 255;
    }
    rgba[i + 3] = 255;
  }
}

/// Redondea [valor] con la misma "granularidad" que tenía [referencia]:
/// si el admin había dejado el precio en múltiplo de 10, de 5 o en
/// entero, el precio nuevo queda igual de "redondo".
double redondearComo(double valor, double referencia) {
  bool multiplo(double m) =>
      (referencia / m - (referencia / m).roundToDouble()).abs() < 1e-6;
  if (referencia >= 10 && multiplo(10)) {
    return (valor / 10).roundToDouble() * 10;
  }
  if (referencia >= 5 && multiplo(5)) {
    return (valor / 5).roundToDouble() * 5;
  }
  if (multiplo(1)) return valor.roundToDouble();
  return redondearPrecio(valor);
}

/// Margen dentro del cual un precio MANUAL se considera "el precio
/// calculado, retocado a mano" (ej. 165,10 → 168). Esos precios siguen
/// al precio del producto en proporción; los que se alejan más son
/// precios especiales y se respetan.
const double kMargenAjusteManualLista = 0.05;

/// Precio nuevo de una columna MANUAL cuando el precio por defecto pasó
/// de [defViejo] a [defNuevo]. null = la columna no seguía al precio
/// del producto (precio especial): se respeta.
///
///   · Igual al defecto viejo (± [tolerancia]) → el defecto nuevo.
///   · Retocado a mano dentro de [kMargenAjusteManualLista] → se mueve
///     en la misma proporción y con el mismo redondeo.
///
/// Antes sólo existía el primer caso: en la lista de Krece, donde el
/// admin redondea cada precio (165,10 → 168), un cambio de precio en
/// el inventario NO llegaba nunca a la lista.
double? precioManualSegunDefecto(
    double actual, double defViejo, double defNuevo,
    {double tolerancia = 0.01}) {
  if ((actual - defViejo).abs() <= tolerancia) return defNuevo;
  if (defViejo <= 0 || actual <= 0) return null;
  if ((actual / defViejo - 1).abs() > kMargenAjusteManualLista) return null;
  return redondearComo(actual * defNuevo / defViejo, actual);
}

/// Copia de [p] con otros precios (Producto tiene precios `final`).
Producto _productoConPrecios(Producto p, double venta, double costo) {
  final c = Producto(
    id: p.id,
    codigo: p.codigo,
    nombre: p.nombre,
    categoria: p.categoria,
    marca: p.marca,
    modelo: p.modelo,
    tipo: p.tipo,
    precioCosto: costo,
    precioVenta: venta,
    stockManual: p.stockManual,
    porcentajeBateria: p.porcentajeBateria,
    productoPadreCodigo: p.productoPadreCodigo,
    variante: p.variante,
    tienda: p.tienda,
  );
  c.stockTotal = p.stockTotal;
  return c;
}

/// Pone el precio nuevo de un producto en el catálogo EN MEMORIA.
///
/// Las listas resuelven cada item contra `catalogoGlobal` y las
/// columnas con función calculan desde `producto.precioVenta`. Si el
/// catálogo en memoria todavía tenía el precio viejo, al abrir la lista
/// (o en el siguiente cambio de precio) las funciones se recalculaban
/// con el precio VIEJO y se guardaban: el cambio "no se aplicaba".
/// Sólo se tocan las filas que tenían el precio anterior.
void sincronizarPrecioEnCatalogo(Producto anterior, Producto nuevo) {
  for (var i = 0; i < catalogoGlobal.length; i++) {
    final p = catalogoGlobal[i];
    if (p.codigo != nuevo.codigo) continue;
    final eraViejo =
        (p.precioVenta - anterior.precioVenta).abs() < 0.0001 &&
            (p.precioCosto - anterior.precioCosto).abs() < 0.0001;
    if (!eraViejo) continue;
    catalogoGlobal[i] =
        _productoConPrecios(p, nuevo.precioVenta, nuevo.precioCosto);
  }
}

/// Cola de actualizaciones de listas por cambio de precio. Cada
/// actualización lee TODAS las listas del servidor y guarda las que
/// cambian; si el admin cambiaba dos precios seguidos, la segunda leía
/// la lista ANTES de que se guardara la primera y al guardar la pisaba
/// (el primer cambio se perdía). En cola, una espera a la otra.
Future<void> _colaListasPorPrecio = Future<void>.value();

Future<T> _enColaListasPorPrecio<T>(Future<T> Function() tarea) {
  final c = Completer<T>();
  _colaListasPorPrecio = _colaListasPorPrecio.then((_) async {
    try {
      c.complete(await tarea());
    } catch (e, st) {
      c.completeError(e, st);
    }
  });
  return c.future;
}

/// Momento en que `cargarStockParaListas` trajo el catálogo del
/// servidor por última vez.
DateTime ultimaCargaCatalogoListas = DateTime(2000);

/// Vuelve a enlazar cada item de [lista] con el producto ACTUAL del
/// catálogo (mismo código). Los items guardan el `Producto` con que se
/// armó la lista; si después se recargó el catálogo (con precios
/// nuevos), las funciones de columna seguirían usando el precio viejo.
/// Devuelve cuántos items se reenlazaron.
int refrescarProductosDeLista(ListaPrecio lista) {
  if (catalogoGlobal.isEmpty) return 0;
  final porCodigo = <String, Producto>{};
  for (final p in catalogoGlobal) {
    porCodigo.putIfAbsent(p.codigo, () => p);
  }
  var n = 0;
  for (var i = 0; i < lista.items.length; i++) {
    final it = lista.items[i];
    final p = porCodigo[it.producto.codigo];
    if (p == null || identical(p, it.producto)) continue;
    lista.items[i] = ItemListaPrecio(
      producto: p,
      preciosPorColumna: it.preciosPorColumna,
      stockDisponible: it.stockDisponible,
      inicialManual: it.inicialManual,
      cuotaManual: it.cuotaManual,
      pctInicialOverride: it.pctInicialOverride,
      cuotasOverride: it.cuotasOverride,
    );
    n++;
  }
  return n;
}

/// Fija el N° de cuotas propio de [it] dentro de [lista] (null = usar
/// las de la lista). Si coincide con el general se guarda como null,
/// así un cambio posterior del general también le llega.
///
/// Si el producto tenía el monto de la cuota escrito a mano, ese monto
/// era para el número de cuotas anterior: se libera para que la cuota
/// se recalcule sola. Devuelve true si algo cambió.
bool fijarCuotasDeItem(ListaPrecio lista, ItemListaPrecio it, int? n) {
  final nuevo = (n == null || n <= 0 || n == lista.numeroCuotas) ? null : n;
  if (nuevo == it.cuotasOverride) return false;
  it.cuotasOverride = nuevo;
  it.cuotaManual = null;
  return true;
}
