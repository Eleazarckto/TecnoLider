// ============================================================================
//  reglas_porcentaje.dart — % especial por tipo de producto y redondeo
//
//  Pedido del 15/10/2026. Una lista de precios tiene UN % («Accesorios
//  Divisas»: 70 %), pero dentro de ella unos productos llevan otro: las
//  cornetas o los vidrios al 100 %, los iPhone distinto que el resto de los
//  teléfonos. En el inventario no son categorías aparte —todo es
//  «Accesorio» o «Telefono»—, así que cada regla los reconoce por PALABRAS
//  del nombre o por la MARCA. Gana la primera que calce; sin ninguna, el %
//  de la lista.
//
//  Y una lista puede redondear sus precios hacia arriba, sin decimales
//  (22,30 → 23), para que la factura no dé vueltos con céntimos.
//
//  Traído de Brizuela (1.0.70) a Tecno Líder el 16/10/2026. El cálculo que
//  vale es el del servidor (backend/lib/precios_listas.php: plReglas,
//  plPctPara, plAEnteroArriba), y solo en las listas en modo «desde el
//  costo». Esto es la misma cuenta del lado de la app, para la vista previa
//  y las explicaciones. Si cambia una, cambia la otra.
// ============================================================================

import 'dart:convert';

/// Roles que ven y cambian los porcentajes de las listas. A los demás
/// (vendedor, cajero, encargado…) no se les muestra cuánto se le suma al
/// costo.
const Set<String> kRolesVenPorcentajesListas = {
  'Dueño',
  'Dueno',
  'Administrador',
  'Gerente',
  'Maestro',
};

/// ¿Este rol puede ver el % que una lista le suma al costo (o a la venta)?
///
/// Es la misma lista de roles que gestiona las listas de precios en Tecno
/// Líder (`puedeGestionarListasPrecios` en lib/listas_precios_motor.dart).
bool puedeVerPorcentajesListas(String? rol, {bool esMaestro = false}) {
  if (esMaestro) return true;
  final r = (rol ?? '').trim().toLowerCase();
  return kRolesVenPorcentajesListas.any((x) => x.toLowerCase() == r);
}

/// Minúsculas y sin tildes, igual que preciosNormalizarTexto del servidor.
String normalizarTextoRegla(String t) {
  const tildes = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
  final b = StringBuffer();
  for (final ch in t.trim().toLowerCase().split('')) {
    b.write(tildes[ch] ?? ch);
  }
  return b.toString();
}

class ReglaPorcentaje {
  /// Cómo se llama el grupo en pantalla: «Cornetas», «Vidrios», «iPhone».
  String nombre;

  /// Palabras que, si aparecen en el nombre del producto, aplican la regla.
  List<String> palabras;

  /// Marca exacta (sin importar mayúsculas). Vacía = no se mira la marca.
  String marca;

  /// % que se suma al costo (o a la venta, en una lista de financiamiento)
  /// en lugar del de la lista.
  double pct;

  ReglaPorcentaje({
    this.nombre = '',
    List<String>? palabras,
    this.marca = '',
    this.pct = 0,
  }) : palabras = palabras ?? [];

  /// Sin palabras ni marca no calzaría con nada: el servidor la descarta.
  bool get esValida =>
      palabras.any((p) => p.trim().isNotEmpty) || marca.trim().isNotEmpty;

  bool calzaCon(String nombreProducto, String marcaProducto) {
    final m = normalizarTextoRegla(marca);
    if (m.isNotEmpty && m == normalizarTextoRegla(marcaProducto)) return true;
    final n = normalizarTextoRegla(nombreProducto);
    if (n.isEmpty) return false;
    for (final p in palabras) {
      final q = normalizarTextoRegla(p);
      if (q.isNotEmpty && n.contains(q)) return true;
    }
    return false;
  }

  Map<String, dynamic> toMap() => {
        'nombre': nombre.trim(),
        'palabras': [
          for (final p in palabras)
            if (normalizarTextoRegla(p).isNotEmpty) normalizarTextoRegla(p)
        ],
        'marca': marca.trim(),
        'pct': pct,
      };

  factory ReglaPorcentaje.fromMap(Map m) {
    final crudo = m['palabras'];
    final palabras = crudo is List
        ? crudo.map((e) => '$e')
        : '${crudo ?? ''}'.split(',');
    return ReglaPorcentaje(
      nombre: '${m['nombre'] ?? ''}',
      palabras: palabras.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      marca: '${m['marca'] ?? ''}',
      pct: double.tryParse('${m['pct']}') ?? 0,
    );
  }

  ReglaPorcentaje copia() =>
      ReglaPorcentaje(nombre: nombre, palabras: [...palabras], marca: marca, pct: pct);
}

/// Lee `reglas_pct` tal como lo devuelve el servidor (texto JSON, lista o
/// null). Un valor roto se toma como «sin reglas», igual que el servidor.
List<ReglaPorcentaje> reglasDesdeJson(dynamic crudo) {
  dynamic datos = crudo;
  if (crudo is String) {
    if (crudo.trim().isEmpty) return [];
    try {
      datos = jsonDecode(crudo);
    } catch (_) {
      return [];
    }
  }
  if (datos is! List) return [];
  return [
    for (final r in datos)
      if (r is Map && double.tryParse('${r['pct']}') != null) ReglaPorcentaje.fromMap(r)
  ].where((r) => r.esValida).toList();
}

/// `reglas_pct` para mandar al servidor: null si no hay ninguna válida.
String? reglasAJson(List<ReglaPorcentaje> reglas) {
  final validas = reglas.where((r) => r.esValida).map((r) => r.toMap()).toList();
  return validas.isEmpty ? null : jsonEncode(validas);
}

/// La regla que le toca a un producto (null si ninguna).
ReglaPorcentaje? reglaPara(
    List<ReglaPorcentaje> reglas, String nombreProducto, String marcaProducto) {
  for (final r in reglas) {
    if (r.esValida && r.calzaCon(nombreProducto, marcaProducto)) return r;
  }
  return null;
}

/// Redondeo a centavos idéntico al de la app (`(v * 100).round() / 100`).
double _a2(double v) => (v * 100).round() / 100;

/// Sin decimales y siempre hacia arriba: 22,30 → 23 y 22,01 → 23. Primero
/// a centavos, para que un 23,0000001 que en realidad es 23,00 no suba a 24.
double aEnteroArriba(double v) => (_a2(v) - 0.000001).ceilToDouble();
