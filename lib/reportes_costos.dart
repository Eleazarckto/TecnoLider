// ============================================================================
//  reportes_costos.dart — El costo y la ganancia, solo para la administración
//
//  Traído de Brizuela (pedido del 15/10/2026): el costo de los productos
//  (y lo que se deduce de él: ganancia, margen, utilidad) solo lo ven
//  Dueño, Administrador, Gerente y Maestro. En Tecno Líder, Reportes está
//  abierto también al Encargado, y sus reportes de Ventas e Inventario
//  traían «Precio Costo», «Costo USD» y «Ganancia USD».
//
//  Los reportes se guardan en el equipo (HistorialReportes) y desde ahí se
//  ven y se exportan. Por eso se filtran en los dos extremos: al guardarlos
//  —así el costo ni siquiera queda en el equipo de un encargado— y al leerlos,
//  para el reporte que generó el dueño en una PC que después usa otro.
// ============================================================================

/// Palabras que delatan un dato de costo en un encabezado o una clave.
const _kPalabrasCosto = ['costo', 'ganancia', 'margen', 'utilidad'];

String _normalizar(String t) {
  const tildes = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u'};
  final b = StringBuffer();
  for (final ch in t.toLowerCase().split('')) {
    b.write(tildes[ch] ?? ch);
  }
  return b.toString();
}

/// ¿Este encabezado o clave es un dato de costo? («Precio Costo»,
/// `precio_costo`, `valor_total_costo`, «Ganancia bruta», «Margen %»…)
bool esDatoDeCosto(String nombre) {
  final n = _normalizar(nombre);
  return _kPalabrasCosto.any(n.contains);
}

/// Copia de un valor (mapa, lista o escalar) sin las claves de costo, a
/// cualquier profundidad: el detalle de una factura trae sus productos
/// anidados, cada uno con su `precio_costo`.
dynamic quitarClavesDeCosto(dynamic v) {
  if (v is Map) {
    return {
      for (final e in v.entries)
        if (!esDatoDeCosto('${e.key}')) e.key: quitarClavesDeCosto(e.value),
    };
  }
  if (v is List) return [for (final x in v) quitarClavesDeCosto(x)];
  return v;
}

/// Tabla sin las columnas de costo. Devuelve los encabezados y las filas
/// nuevas; una fila más corta que los encabezados se recorta igual.
({List<String> encabezados, List<List<dynamic>> filas}) quitarColumnasDeCosto(
    List<String> encabezados, List<List<dynamic>> filas) {
  final quedan = [
    for (int i = 0; i < encabezados.length; i++)
      if (!esDatoDeCosto(encabezados[i])) i
  ];
  if (quedan.length == encabezados.length) {
    return (encabezados: encabezados, filas: filas);
  }
  return (
    encabezados: [for (final i in quedan) encabezados[i]],
    filas: [
      for (final f in filas) [for (final i in quedan) if (i < f.length) f[i]]
    ],
  );
}
