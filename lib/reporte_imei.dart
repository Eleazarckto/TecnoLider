part of 'main.dart';

// ============================================================================
//  REPORTE DE IMEIs POR TIENDA, MARCA Y MODELO
//
//  Pedido del dueño (19/10/2026): el reporte de IMEIs se puede sacar por
//  tienda, por marca y por modelo. Decisión del dueño: filtros + resumen.
//
//    · Antes de generar se elige tienda, marca y modelo (o «Todas»/«Todos»).
//      El reporte trae solo los equipos que cumplen los tres.
//    · El reporte trae además los totales por tienda, por marca y por
//      modelo (disponibles y vendidos), en pantalla y en una hoja propia
//      del Excel.
//    · Tienda = `ubicacion` del IMEI (vacía = «Sin asignar»). Modelo = el
//      modelo del producto; si no tiene, el nombre del equipo.
// ============================================================================

const String kImeiTodas = 'Todas';
const String kImeiTodos = 'Todos';
const String kImeiSinAsignar = 'Sin asignar';

/// Tienda de un IMEI tal como se agrupa y filtra.
String tiendaDeImei(String ubicacion) =>
    ubicacion.trim().isEmpty ? kImeiSinAsignar : ubicacion.trim();

/// Modelo de un IMEI para agrupar y filtrar: el modelo; si no tiene, el
/// nombre del equipo; si tampoco, «N/D».
String modeloDeImei(String modelo, String nombre) {
  final m = modelo.trim();
  if (m.isNotEmpty && m != 'N/D') return m;
  return nombre.trim().isEmpty ? 'N/D' : nombre.trim();
}

/// Filtro elegido antes de generar el reporte.
class FiltroReporteImei {
  final String tienda;
  final String marca;
  final String modelo;
  const FiltroReporteImei(
      {this.tienda = kImeiTodas,
      this.marca = kImeiTodas,
      this.modelo = kImeiTodos});

  static bool _igual(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  bool get esTodo =>
      tienda == kImeiTodas && marca == kImeiTodas && modelo == kImeiTodos;

  /// ¿El equipo entra? [tienda] y [modelo] ya normalizados con
  /// `tiendaDeImei` y `modeloDeImei`.
  bool acepta({
    required String tienda,
    required String marca,
    required String modelo,
  }) =>
      (this.tienda == kImeiTodas || _igual(this.tienda, tienda)) &&
      (this.marca == kImeiTodas || _igual(this.marca, marca)) &&
      (this.modelo == kImeiTodos || _igual(this.modelo, modelo));

  /// Para el nombre del archivo: « — Tienda X · Samsung · A15».
  String get sufijo {
    final partes = [
      if (tienda != kImeiTodas) tienda,
      if (marca != kImeiTodas) marca,
      if (modelo != kImeiTodos) modelo,
    ];
    return partes.isEmpty ? '' : ' — ${partes.join(' · ')}';
  }
}

/// Disponibles y vendidos de un grupo.
class ConteoImei {
  int disponibles = 0;
  int vendidos = 0;
  int get total => disponibles + vendidos;
  String get texto => '$disponibles disp. · $vendidos vend.';
}

/// Totales por tienda, por marca y por modelo de una lista de equipos
/// (cada uno con 'tienda', 'marca', 'grupo_modelo' y 'vendido').
class ResumenImei {
  final Map<String, ConteoImei> porTienda = {};
  final Map<String, ConteoImei> porMarca = {};
  final Map<String, ConteoImei> porModelo = {};

  void sumar(
      {required String tienda,
      required String marca,
      required String modelo,
      required bool vendido}) {
    for (final par in [
      MapEntry(porTienda, tienda),
      MapEntry(porMarca, marca),
      MapEntry(porModelo, modelo),
    ]) {
      final c = par.key.putIfAbsent(par.value, ConteoImei.new);
      if (vendido) {
        c.vendidos++;
      } else {
        c.disponibles++;
      }
    }
  }

  /// Ordenado de mayor a menor total (a igual total, por nombre).
  static List<MapEntry<String, ConteoImei>> ordenado(
      Map<String, ConteoImei> m) =>
      m.entries.toList()
        ..sort((a, b) {
          final t = b.value.total.compareTo(a.value.total);
          return t != 0 ? t : a.key.compareTo(b.key);
        });

  /// Mapa para el resumen guardado: nombre → «N disp. · M vend.».
  static Map<String, String> comoTexto(Map<String, ConteoImei> m) => {
        for (final e in ordenado(m)) e.key: e.value.texto,
      };

  /// Desde los `detalles` de un reporte ya guardado (para el Excel).
  static ResumenImei deDetalles(List<Map<String, dynamic>> detalles) {
    final r = ResumenImei();
    for (final d in detalles) {
      final marca = (d['marca'] ?? '').toString();
      r.sumar(
        tienda: tiendaDeImei((d['ubicacion'] ?? '').toString()),
        marca: marca.trim().isEmpty ? 'N/D' : marca,
        modelo: (d['grupo_modelo'] ??
                modeloDeImei((d['modelo'] ?? '').toString(),
                    (d['nombre'] ?? '').toString()))
            .toString(),
        vendido: d['vendido'] == true,
      );
    }
    return r;
  }
}

/// Opciones de los filtros: tiendas de la configuración y marcas/modelos
/// de los productos de categorías con IMEI. [productos] son los mapas del
/// API (`productos`).
class OpcionesFiltroImei {
  final List<String> tiendas;
  final List<String> marcas;

  /// marca → modelos (y kImeiTodas → todos los modelos).
  final Map<String, List<String>> modelosPorMarca;

  const OpcionesFiltroImei(this.tiendas, this.marcas, this.modelosPorMarca);

  factory OpcionesFiltroImei.desde({
    required List<String> tiendasConfig,
    required List<Map> productos,
    required bool Function(String categoria) usaImei,
  }) {
    final tiendas = <String>{
      for (final t in tiendasConfig)
        if (t.trim().isNotEmpty) t.trim()
    };
    final porMarca = <String, Set<String>>{};
    for (final p in productos) {
      if (!usaImei((p['categoria'] ?? '').toString())) continue;
      final marca = (p['marca'] ?? '').toString().trim();
      final modelo = modeloDeImei((p['modelo'] ?? '').toString(),
          (p['nombre'] ?? '').toString());
      final m = marca.isEmpty ? 'N/D' : marca;
      porMarca.putIfAbsent(m, () => <String>{}).add(modelo);
    }
    List<String> ord(Iterable<String> s) =>
        s.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return OpcionesFiltroImei(
      [kImeiTodas, ...ord(tiendas), kImeiSinAsignar],
      [kImeiTodas, ...ord(porMarca.keys)],
      {
        kImeiTodas: [
          kImeiTodos,
          ...ord({for (final s in porMarca.values) ...s})
        ],
        for (final e in porMarca.entries) e.key: [kImeiTodos, ...ord(e.value)],
      },
    );
  }

  List<String> modelosDe(String marca) =>
      modelosPorMarca[marca] ?? modelosPorMarca[kImeiTodas] ?? [kImeiTodos];
}
