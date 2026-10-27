part of 'main.dart';

// ============================================================================
//  LISTAS EN Bs QUE TOMAN SUS PRECIOS DE UNA LISTA EN DIVISAS
//
//  Orden del dueño (19/10/2026): «en las listas de precios en bolívares
//  tome el precio de las listas en divisas y sea a esa lista la que se le
//  aumente el porcentaje». Decisiones del dueño:
//
//    · Cada lista en Bs ELIGE su lista base en divisas («Tomar precios
//      de…» en Editar lista). Sin elegir, la lista sigue como siempre.
//    · Precio en Bs = precio del producto en la lista base (su primera
//      columna) × (1 + % adicional de la lista en Bs) × tasa.
//    · Producto que no está en la lista base (o sin precio ahí): precio de
//      venta del inventario × (1 + %) × tasa, como antes.
//    · Al elegir la base la lista se recalcula entera ya, y desde ahí
//      sigue sola a su base: al abrirla, al guardar la lista en divisas,
//      al cambiar la tasa y al cambiar el precio de un producto. Los
//      precios marcados ✎ (escritos a mano) no se tocan.
//    · El servidor hace la misma cuenta en las listas en modo costo
//      (plValores en backend/lib/precios_listas.php).
// ============================================================================

/// Lista en divisas de la que [lista] (en Bs) toma sus precios. null si
/// no es en Bs, no eligió base o la base ya no existe.
ListaPrecio? listaBaseDe(ListaPrecio lista, [List<ListaPrecio>? listas]) {
  final id = lista.listaBaseId;
  if (!lista.esEnBolivares || id == null) return null;
  for (final l in listas ?? listasPreciosGlobal) {
    if (l.id == id && !l.esEnBolivares && !identical(l, lista)) return l;
  }
  return null;
}

/// Precio en $ de [p] en la lista base de [lista] (primera columna).
/// null si no hay base, el producto no está o no tiene precio ahí.
double? precioEnListaBase(ListaPrecio lista, Producto p,
    [List<ListaPrecio>? listas]) {
  final base = listaBaseDe(lista, listas);
  if (base == null || base.columnas.isEmpty) return null;
  final col = base.columnas.first.nombre;
  for (final it in base.items) {
    if (it.producto.codigo != p.codigo) continue;
    final v = it.preciosPorColumna[col];
    return v != null && v > 0 ? v : null;
  }
  return null;
}

/// Listas que una lista en Bs puede elegir como base: las en divisas ya
/// guardadas. La sugerida (misma marca, misma financiadora y la que más
/// categorías comparte) va primero.
List<ListaPrecio> listasBaseElegibles(
    ListaPrecio lb, List<ListaPrecio> listas) {
  final out = [
    for (final l in listas)
      if (!l.esEnBolivares && l.id != null && !identical(l, lb)) l
  ];
  final sug = listaBaseSugerida(lb, out);
  if (sug != null) {
    out
      ..remove(sug)
      ..insert(0, sug);
  }
  return out;
}

/// La lista en divisas que mejor le calza a [lb]: misma marca, mismo tipo
/// (financiamiento o no, y la misma financiadora) y la que más categorías
/// comparte. Solo se muestra como sugerencia: la base la elige la persona.
ListaPrecio? listaBaseSugerida(ListaPrecio lb, List<ListaPrecio> listas) {
  List<String> cats(ListaPrecio l) => l.categoria
      .split(',')
      .map((c) => c.trim().toLowerCase())
      .where((c) => c.isNotEmpty)
      .toList();
  String fin(ListaPrecio l) =>
      l.esFinanciamiento ? (l.financiadora ?? '').trim().toLowerCase() : '';
  final mias = cats(lb);
  ListaPrecio? mejor;
  var puntos = 0;
  for (final l in listas) {
    if (l.esEnBolivares || identical(l, lb)) continue;
    if (l.esFinanciamiento != lb.esFinanciamiento || fin(l) != fin(lb)) continue;
    if (l.marcaFiltro.toLowerCase() != lb.marcaFiltro.toLowerCase()) continue;
    final suyas = cats(l);
    final comunes = mias.where(suyas.contains).length;
    final p = comunes * 1000 - suyas.where((c) => !mias.contains(c)).length;
    if (comunes > 0 && (mejor == null || p > puntos)) {
      mejor = l;
      puntos = p;
    }
  }
  return mejor;
}

/// Pone los precios de [lista] (en Bs, con base) al día con su lista base
/// y la tasa: cada celda de columna sin fórmula que no esté marcada ✎
/// pasa a su precio por defecto, y después se aplican las fórmulas
/// automáticas. Una lista sin base o en modo costo no se toca.
/// Devuelve cuántos valores cambiaron.
int seguirListaBase(ListaPrecio lista, [List<ListaPrecio>? listas]) {
  if (lista.esModoCosto || listaBaseDe(lista, listas) == null) return 0;
  var cambios = 0;
  // La tasa con que se calcula queda a la vista en la lista.
  final tasa = lista.tasaParaPoblar;
  if (tasa > 0 && (lista.tasaDelDia - tasa).abs() >= 0.00005) {
    lista.tasaDelDia = tasa;
    cambios++;
  }
  for (final item in lista.items) {
    if (item.fueraDeCatalogo) continue;
    final porDefecto = lista.precioPorDefecto(item.producto, listas);
    for (final col in lista.columnas) {
      if (!col.formula.esManual || item.esManual(col.nombre)) continue;
      final actual = item.preciosPorColumna[col.nombre];
      if (actual != null && (actual - porDefecto).abs() < 0.0001) continue;
      item.preciosPorColumna[col.nombre] = porDefecto;
      cambios++;
    }
  }
  if (cambios > 0) cambios += lista.aplicarFormulas();
  return cambios;
}

/// Después de guardar la lista en divisas [base]: sus listas en Bs se
/// ponen al día y se guardan (fusión, sin pisar a otros equipos).
/// Devuelve cuántas listas cambiaron.
Future<int> actualizarListasBsDeBase(ListaPrecio base) async {
  if (base.id == null || base.esEnBolivares) return 0;
  var n = 0;
  // La base recién guardada manda sobre la copia que haya en memoria.
  final listas = [
    base,
    for (final l in listasPreciosGlobal)
      if (l.id != base.id) l
  ];
  for (final lb in listas) {
    if (lb.listaBaseId != base.id || lb.id == null) continue;
    final foto = InstantaneaLista.de(lb);
    if (seguirListaBase(lb, listas) == 0) continue;
    try {
      await guardarCambiosDeLista(lb, foto);
      n++;
    } catch (e) {
      debugPrint('[ListasBs] No se pudo guardar "${lb.nombre}": $e');
    }
  }
  if (n > 0) {
    debugPrint('[ListasBs] «${base.nombre}»: $n lista(s) en Bs al día');
  }
  return n;
}

/// Selector «Tomar precios de» de una lista en Bs. [molde] es la lista
/// (o una con la categoría, marca y financiadora de la que se está
/// creando) para sugerir la base; [valor] es el id elegido.
Widget selectorListaBase({
  required ListaPrecio molde,
  required int? valor,
  required ValueChanged<int?> onChanged,
}) {
  final opciones = listasBaseElegibles(molde, listasPreciosGlobal);
  final sugerida = listaBaseSugerida(molde, opciones);
  // Una base que ya no existe se muestra como «ninguna».
  final actual = opciones.any((l) => l.id == valor) ? valor : null;
  return DropdownButtonFormField<int?>(
    value: actual,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: 'Tomar precios de (lista en divisas)',
      prefixIcon: const Icon(Icons.link),
      border: const OutlineInputBorder(),
      isDense: true,
      helperText: actual == null
          ? 'Sin lista base: precio de venta del inventario + % × tasa'
          : 'Precio en esa lista + % de esta lista × tasa. Lo que no '
              'esté ahí sale del precio de venta. Los ✎ no se tocan.',
      helperMaxLines: 3,
    ),
    items: [
      const DropdownMenuItem<int?>(
          value: null,
          child: Text('— Ninguna (precio de venta) —',
              overflow: TextOverflow.ellipsis)),
      for (final l in opciones)
        DropdownMenuItem<int?>(
            value: l.id,
            child: Text(
                '${l.nombre}${identical(l, sugerida) ? '  (sugerida)' : ''}',
                overflow: TextOverflow.ellipsis)),
    ],
    onChanged: onChanged,
  );
}

// ============================================================================
//  VISTA DE LAS LISTAS EN Bs: SOLO BCV, BCV + Bs O SOLO Bs
//
//  Orden del dueño (23/10/2026): «modifica las listas de bolívares para
//  que tenga la opción de mostrar solo el precio BCV deseado usando
//  porcentaje, ejemplo: si el precio en divisas es de 100$ y al BCV le
//  quiero agregar 10% quedaría BCV = 110$ […] o la opción de que sí
//  muestre también el equivalente a Bs».
//
//    · 'bs'     — como siempre: el precio en Bs.
//    · 'bcv'    — solo el precio BCV en $ = base × (1 + % de la lista).
//    · 'bcv_bs' — el precio BCV en $ y al lado su equivalente en Bs.
//
//  Lo guardado sigue en Bs (así la app 1.0.17 y el servidor no cambian
//  nada): el precio BCV es lo guardado ÷ la tasa con que se calculó.
// ============================================================================

const vistasBs = <String, String>{
  'bs': 'Solo bolívares (como siempre)',
  'bcv': 'Solo el precio BCV en \$',
  'bcv_bs': 'Precio BCV en \$ y su equivalente en Bs',
};

/// 'bs', 'bcv' o 'bcv_bs'; cualquier otra cosa (o nada) = 'bs'.
String normalizarVistaBs(Object? v) {
  final s = '${v ?? ''}'.trim().toLowerCase();
  return s == 'bcv' || s == 'bcv_bs' ? s : 'bs';
}

extension VistaListaBs on ListaPrecio {
  /// ¿La lista (en Bs) muestra el precio BCV en $?
  bool get muestraBcv => esEnBolivares && vistaBs != 'bs';

  /// ¿Además del BCV muestra el equivalente en Bs?
  bool get muestraBsAlLado => esEnBolivares && vistaBs == 'bcv_bs';

  /// Moneda de lo que se muestra: 'Bs' solo en la vista de siempre.
  String get monedaVista => esEnBolivares && !muestraBcv ? 'Bs' : '\$';

  /// Rótulo de la moneda para encabezados: 'Bs', '\$ BCV', '\$ BCV y Bs'
  /// o '\$' (lista en divisas).
  String get etiquetaVista => muestraBsAlLado
      ? '\$ BCV y Bs'
      : muestraBcv ? '\$ BCV' : monedaVista;

  /// Un precio guardado (Bs) en lo que se muestra: en vista BCV, $ BCV.
  /// Con «sin decimales hacia arriba» el Bs subió hasta 1 Bs: se vuelve
  /// al dólar entero de partida (110 × 36,57 = 4.022,7 → 4.023 → 110).
  double aVista(double v) {
    if (!muestraBcv) return v;
    final t = tasaEfectiva;
    if (t <= 0) return v;
    final usd = v / t;
    if (redondearArriba && t > 1) {
      final entero = usd.floorToDouble();
      if (usd - entero < 1 / t + 0.000001) return entero;
    }
    return redondearPrecio(usd);
  }

  /// Lo que se escribe en la vista ($ BCV) en lo que se guarda (Bs).
  double desdeVista(double v) =>
      muestraBcv ? redondearPrecioLista(v * tasaEfectiva) : v;

  /// Texto de un precio guardado según la vista: «Bs 4015.00»,
  /// «$ 110.00» o «$ 110.00 · Bs 4015.00».
  String textoPrecio(double v, {int decimales = 2}) {
    if (!muestraBcv) return '$monedaVista ${v.toStringAsFixed(decimales)}';
    final bcv = '\$ ${aVista(v).toStringAsFixed(decimales)}';
    return muestraBsAlLado ? '$bcv · Bs ${v.toStringAsFixed(decimales)}' : bcv;
  }
}

/// Selector «Mostrar precios» de una lista en Bs.
Widget selectorVistaBs({
  required String valor,
  required ValueChanged<String> onChanged,
}) {
  return DropdownButtonFormField<String>(
    value: normalizarVistaBs(valor),
    isExpanded: true,
    decoration: const InputDecoration(
      labelText: 'Mostrar precios',
      prefixIcon: Icon(Icons.visibility_outlined),
      border: OutlineInputBorder(),
      isDense: true,
      helperText: 'Precio BCV = precio en divisas + % de esta lista '
          '(100 \$ + 10 % = 110 \$). El equivalente en Bs es ese × la tasa.',
      helperMaxLines: 3,
    ),
    items: [
      for (final e in vistasBs.entries)
        DropdownMenuItem<String>(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis)),
    ],
    onChanged: (v) => onChanged(normalizarVistaBs(v)),
  );
}
