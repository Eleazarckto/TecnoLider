part of 'main.dart';

// ════════════════════════════════════════════════════════════════════
//  AUDITORÍA DE FACTURAS
// ════════════════════════════════════════════════════════════════════
//  El dueño recorre las tiendas, recoge los tickets y luego, en la
//  tienda principal, verifica factura por factura:
//    1. que el pago llegó (pago móvil / punto / efectivo), y
//    2. que lo pagado corresponde al equipo: de contado = precio en
//       divisa (o BCV si pagó en bolívares); financiado = la inicial y
//       el precio concuerdan con la lista de la financiadora.
//  Hoy le toma unas 2 horas. Este archivo agrega:
//    · Una verificación AUTOMÁTICA por reglas (sin IA) que compara lo
//      pagado contra las listas de precios y dice "concuerda" o
//      "diferencia de $X" (`auditarFacturaAuto`).
//    · Marcas manuales "Pago recibido" y "Auditoría correcta" (listo /
//      no listo) con quién y cuándo las puso (`MarcaAuditoria`).
//    · Conteo de unidades de contado / financiadas por financiadora para
//      el resumen del reporte de ventas (`contarUnidadesVentas`).
//    · Las líneas de precio de referencia que van en la factura impresa
//      (`lineasPrecioReferencia`).
//
//  Persistencia SIN tocar el servidor: cada factura auditada se guarda
//  como una clave propia en la tabla `configuracion` (clave/valor, el
//  POST hace upsert por clave): `aud_fac_<nro_factura>` → JSON. Una
//  clave por factura (y no un JSON gigante con todas) para que dos
//  personas auditando a la vez no se pisen las marcas.
// ════════════════════════════════════════════════════════════════════

/// Normaliza el nombre de financiadora a una de las oficiales
/// ("Cashea" / "Krece" / "Weppa"); null si no es ninguna.
String? normalizarFinanciadoraAud(String? raw) {
  final s = (raw ?? '').toLowerCase().trim();
  if (s.isEmpty) return null;
  if (s.contains('cashea')) return 'Cashea';
  if (s.contains('krece')) return 'Krece';
  if (s.contains('weppa')) return 'Weppa';
  return null;
}

String _normNombreLista(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9áéíóúñ]'), '');

/// Precios de referencia de UN producto vendido.
class PreciosReferencia {
  /// Precio de contado en divisas (precio de venta del catálogo).
  final double? divisa;
  /// Precio de contado pagando en bolívares (lista o columna "BCV").
  final double? bcv;
  /// Precio en la lista de la financiadora (Cashea / Krece...).
  final double? financiadora;
  /// % de inicial que fija esa lista (0/null si la lista no lo define).
  final double? pctInicial;
  /// Nombre de la lista de donde salió el precio de la financiadora.
  final String? listaFinanciadora;

  const PreciosReferencia({this.divisa, this.bcv, this.financiadora,
      this.pctInicial, this.listaFinanciadora});

  Map<String, dynamic> toMap() => {
    'precio_divisa': divisa,
    'precio_bcv': bcv,
    'precio_financiadora': financiadora,
    'pct_inicial': pctInicial,
    'lista_financiadora': listaFinanciadora,
  };

  static double? _d(dynamic v) =>
      v == null ? null : double.tryParse(v.toString());

  factory PreciosReferencia.fromMap(Map m) => PreciosReferencia(
    divisa: _d(m['precio_divisa']),
    bcv: _d(m['precio_bcv']),
    financiadora: _d(m['precio_financiadora']),
    pctInicial: _d(m['pct_inicial']),
    listaFinanciadora: m['lista_financiadora']?.toString(),
  );
}

/// Busca los precios de referencia de [codigo] en las listas.
///
/// Precio de la financiadora, en este orden (el primero que tenga el
/// producto gana):
///   1. La lista que el vendedor eligió al facturar ([nombreLista]).
///   2. Listas marcadas con esa financiadora (campo `financiadora`,
///      tolerante a "KRECE." / "Krece").
///   3. Listas cuyo NOMBRE contiene la financiadora ("Cashea",
///      "CASHEA TELEFONOS").
///   4. Cualquier lista con una COLUMNA con ese nombre ("CASHEA").
/// Dentro de una lista se usa la columna que se llame como la
/// financiadora y, si no hay, la primera (igual que el Reporte por
/// Financiadora).
///
/// El precio BCV sale de una lista llamada "BCV" o, si no, de una
/// columna "BCV" de cualquier lista.
PreciosReferencia preciosReferenciaDe({
  required String codigo,
  double? precioVenta,
  required List<ListaPrecio> listas,
  String? financiadora,
  String? nombreLista,
}) {
  final cod = codigo.trim().toLowerCase();
  ItemListaPrecio? itemDe(ListaPrecio l) {
    for (final it in l.items) {
      if (it.producto.codigo.trim().toLowerCase() == cod) return it;
    }
    return null;
  }

  double? columna(ItemListaPrecio it, bool Function(String) coincide) {
    for (final e in it.preciosPorColumna.entries) {
      if (coincide(e.key) && e.value > 0) return e.value;
    }
    return null;
  }

  double? primera(ItemListaPrecio it) {
    for (final v in it.preciosPorColumna.values) {
      if (v > 0) return v;
    }
    return null;
  }

  // ── BCV ──
  // Una lista en Bs con vista BCV (23/10/2026) guarda Bs y muestra $ BCV:
  // el precio BCV es el que muestra (`aVista`). En las demás, el guardado.
  double? bcv;
  for (final l in listas) {
    if (_normNombreLista(l.nombre) != 'bcv') continue;
    final it = itemDe(l);
    if (it != null) {
      final v = primera(it);
      bcv = v == null ? null : l.aVista(v);
      if (bcv != null) break;
    }
  }
  if (bcv == null) {
    for (final l in listas) {
      final it = itemDe(l);
      if (it == null) continue;
      final v = columna(it, (c) => _normNombreLista(c) == 'bcv');
      bcv = v == null ? null : l.aVista(v);
      if (bcv != null) break;
    }
  }

  // ── Financiadora ──
  double? fin;
  double? pct;
  String? listaFin;
  final finNorm = normalizarFinanciadoraAud(financiadora);
  if (finNorm != null) {
    final f = finNorm.toLowerCase();
    bool colFin(String c) => c.toLowerCase().contains(f);
    void tomar(ListaPrecio l, ItemListaPrecio it, {bool soloColumna = false}) {
      final v = columna(it, colFin) ?? (soloColumna ? null : primera(it));
      if (v == null) return;
      fin = v;
      listaFin = l.nombre;
      final p = l.pctInicialDe(it);
      pct = p > 0 ? p : null;
    }

    // 1. Lista elegida al facturar.
    final nl = _normNombreLista(nombreLista ?? '');
    if (nl.isNotEmpty) {
      for (final l in listas) {
        if (_normNombreLista(l.nombre) != nl) continue;
        final it = itemDe(l);
        if (it != null) { tomar(l, it); if (fin != null) break; }
      }
    }
    // 2. Listas de la financiadora.
    if (fin == null) {
      for (final l in listas) {
        if (normalizarFinanciadoraAud(l.financiadora) != finNorm) continue;
        final it = itemDe(l);
        if (it != null) { tomar(l, it); if (fin != null) break; }
      }
    }
    // 3. Listas con el nombre de la financiadora.
    if (fin == null) {
      for (final l in listas) {
        if (!l.nombre.toLowerCase().contains(f)) continue;
        final it = itemDe(l);
        if (it != null) { tomar(l, it); if (fin != null) break; }
      }
    }
    // 4. Columna con el nombre de la financiadora en cualquier lista.
    if (fin == null) {
      for (final l in listas) {
        final it = itemDe(l);
        if (it != null) { tomar(l, it, soloColumna: true); if (fin != null) break; }
      }
    }
  }

  return PreciosReferencia(
    divisa: (precioVenta != null && precioVenta > 0) ? precioVenta : null,
    bcv: bcv,
    financiadora: fin,
    pctInicial: pct,
    listaFinanciadora: listaFin,
  );
}

/// Un renglón (producto) de la factura para la auditoría automática.
class RenglonAuditoria {
  final bool financiado;
  final PreciosReferencia precios;
  const RenglonAuditoria({required this.financiado, required this.precios});
}

enum EstadoAuditoriaAuto { concuerda, diferencia, sinDatos }

/// Resultado de la verificación automática de una factura.
class ResultadoAuditoriaAuto {
  final EstadoAuditoriaAuto estado;
  /// Pagado − esperado (en $). Positivo = pagó de más.
  final double? diferencia;
  /// Explicación corta para mostrar debajo del indicador.
  final String detalle;

  const ResultadoAuditoriaAuto(this.estado, {this.diferencia, this.detalle = ''});

  /// "Concuerda" / "Diferencia de $X" / "Sin datos".
  String get titulo {
    switch (estado) {
      case EstadoAuditoriaAuto.concuerda:
        return 'Concuerda';
      case EstadoAuditoriaAuto.diferencia:
        final d = diferencia ?? 0;
        return 'Diferencia de ${d >= 0 ? '+' : '-'}\$${d.abs().toStringAsFixed(2)}';
      case EstadoAuditoriaAuto.sinDatos:
        return 'Sin datos para comparar';
    }
  }

  Map<String, dynamic> toMap() => {
    'estado': estado.name,
    'diferencia': diferencia,
    'detalle': detalle,
  };

  factory ResultadoAuditoriaAuto.fromMap(Map m) => ResultadoAuditoriaAuto(
    EstadoAuditoriaAuto.values.firstWhere(
        (e) => e.name == m['estado']?.toString(),
        orElse: () => EstadoAuditoriaAuto.sinDatos),
    diferencia: m['diferencia'] == null
        ? null : double.tryParse(m['diferencia'].toString()),
    detalle: (m['detalle'] ?? '').toString(),
  );
}

/// Tolerancia: $1 o el 1% de lo esperado (lo que sea mayor). Cubre el
/// redondeo de la tasa en los pagos en bolívares.
double _tolerancia(double esperado) => math.max(1.0, esperado.abs() * 0.01);

String _usd(double v) => '\$${v.toStringAsFixed(2)}';

/// "Inicial $50.00", o "Sin inicial (promoción)" si es 0.
String _txtInicial(double inicial) =>
    esInicialCero(inicial) ? kTextoSinInicial : 'Inicial ${_usd(inicial)}';

/// Verificación automática por reglas de una factura.
///
///  · CONTADO: lo pagado debe ser el precio en divisa si pagó en
///    divisas, o el precio BCV si pagó en bolívares. Si pagó mezclado,
///    la parte en Bs se lleva a "divisa" con la proporción divisa/BCV.
///  · FINANCIADO: a lo pagado se le quita el precio de los renglones de
///    contado (accesorios) y queda la inicial. Concuerda si:
///      - inicial + N° cuotas × cuota = precio de la lista (Cashea), o
///      - inicial = % de inicial de la lista × precio (Krece: sus
///        cuotas llevan recargo y no suman el precio).
///    Si no, informa la diferencia de la inicial contra la esperada (o
///    del plan completo contra el precio, si la lista no fija %).
///    Una inicial de 0 (promoción) cuadra por la regla de las cuotas:
///    N° cuotas × cuota = precio de la lista.
ResultadoAuditoriaAuto auditarFacturaAuto({
  required List<RenglonAuditoria> renglones,
  required double pagadoUsd,
  required double pagadoBsEnUsd,
  int? numeroCuotas,
  double? montoCuota,
  String financiadora = '',
}) {
  if (renglones.isEmpty) {
    return const ResultadoAuditoriaAuto(EstadoAuditoriaAuto.sinDatos,
        detalle: 'La factura no tiene productos');
  }
  final soloBs = pagadoUsd.abs() < 0.005 && pagadoBsEnUsd > 0;
  final soloUsd = pagadoBsEnUsd.abs() < 0.005;
  final contado = renglones.where((r) => !r.financiado).toList();
  final financiados = renglones.where((r) => r.financiado).toList();

  // Precio esperado de los renglones de contado.
  double esperadoContado = 0;
  bool faltaContado = false;
  for (final r in contado) {
    final div = r.precios.divisa;
    if (div == null) { faltaContado = true; continue; }
    esperadoContado += soloBs ? (r.precios.bcv ?? div) : div;
  }

  if (financiados.isEmpty) {
    if (faltaContado) {
      return const ResultadoAuditoriaAuto(EstadoAuditoriaAuto.sinDatos,
          detalle: 'Un producto no tiene precio de referencia');
    }
    double pagado;
    double esperado;
    String base;
    if (soloUsd) {
      pagado = pagadoUsd;
      esperado = esperadoContado;
      base = 'precio en divisa';
    } else if (soloBs) {
      pagado = pagadoBsEnUsd;
      esperado = esperadoContado;
      base = 'precio BCV';
    } else {
      // Mezclado: llevar los Bs a su valor en divisa.
      final divSum = contado.fold<double>(0, (s, r) => s + r.precios.divisa!);
      final bcvSum = contado.fold<double>(
          0, (s, r) => s + (r.precios.bcv ?? r.precios.divisa!));
      final factor = bcvSum > 0 ? divSum / bcvSum : 1.0;
      pagado = pagadoUsd + pagadoBsEnUsd * factor;
      esperado = divSum;
      base = 'precio en divisa (Bs llevados a divisa)';
    }
    final dif = redondearPrecio(pagado - esperado);
    final det = 'Pagó ${_usd(pagado)} · $base ${_usd(esperado)}';
    return dif.abs() <= _tolerancia(esperado)
        ? ResultadoAuditoriaAuto(EstadoAuditoriaAuto.concuerda,
            diferencia: dif, detalle: det)
        : ResultadoAuditoriaAuto(EstadoAuditoriaAuto.diferencia,
            diferencia: dif, detalle: det);
  }

  // ── Financiado ──
  final fin = financiadora.isNotEmpty ? financiadora : 'la financiadora';
  if (financiados.any((r) => r.precios.financiadora == null)) {
    return ResultadoAuditoriaAuto(EstadoAuditoriaAuto.sinDatos,
        detalle: 'No se encontró el precio de $fin en las listas');
  }
  final precioFin = financiados.fold<double>(
      0, (s, r) => s + r.precios.financiadora!);
  final inicial = redondearPrecio(pagadoUsd + pagadoBsEnUsd - esperadoContado);
  final hayCuotas = (numeroCuotas ?? 0) > 0 && (montoCuota ?? 0) > 0;
  final planTotal = hayCuotas ? inicial + numeroCuotas! * montoCuota! : null;
  double? pct;
  for (final r in financiados) {
    final p = r.precios.pctInicial;
    if (p != null && p > 0) { pct = p; break; }
  }
  final extraContado = contado.isNotEmpty
      ? ' (sin ${_usd(esperadoContado)} de contado)' : '';

  // a) Inicial + cuotas = precio de la lista.
  if (planTotal != null &&
      (planTotal - precioFin).abs() <= _tolerancia(precioFin)) {
    return ResultadoAuditoriaAuto(EstadoAuditoriaAuto.concuerda,
        diferencia: redondearPrecio(planTotal - precioFin),
        detalle: '${_txtInicial(inicial)}$extraContado + '
            '$numeroCuotas × ${_usd(montoCuota!)} = precio $fin ${_usd(precioFin)}');
  }
  // b) Inicial = % de la lista.
  if (pct != null) {
    final esperada = redondearPrecio(precioFin * pct / 100);
    final dif = redondearPrecio(inicial - esperada);
    final pctTxt = pct == pct.roundToDouble()
        ? pct.toStringAsFixed(0) : pct.toStringAsFixed(1);
    final det = '${_txtInicial(inicial)}$extraContado · esperada '
        '${_usd(esperada)} ($pctTxt% de ${_usd(precioFin)}, precio $fin)';
    return dif.abs() <= _tolerancia(esperada)
        ? ResultadoAuditoriaAuto(EstadoAuditoriaAuto.concuerda,
            diferencia: dif, detalle: det)
        : ResultadoAuditoriaAuto(EstadoAuditoriaAuto.diferencia,
            diferencia: dif, detalle: det);
  }
  if (planTotal != null) {
    final dif = redondearPrecio(planTotal - precioFin);
    return ResultadoAuditoriaAuto(EstadoAuditoriaAuto.diferencia,
        diferencia: dif,
        detalle: '${_txtInicial(inicial)} + $numeroCuotas × '
            '${_usd(montoCuota!)} = ${_usd(planTotal)} · precio $fin '
            '${_usd(precioFin)}');
  }
  return ResultadoAuditoriaAuto(EstadoAuditoriaAuto.sinDatos,
      detalle: '${_txtInicial(inicial)} · precio $fin ${_usd(precioFin)} '
          '(faltan las cuotas o el % de inicial de la lista)');
}

// ────────────────────────────────────────────────────────────────
//  MARCAS MANUALES (Pago recibido / Auditoría correcta)
// ────────────────────────────────────────────────────────────────

/// Marcas del auditor sobre una factura. `null` = sin revisar,
/// `true` = listo, `false` = no listo (hay un problema).
class MarcaAuditoria {
  bool? pagoRecibido;
  String pagoPor;
  String pagoEn;
  bool? auditoriaOk;
  String auditoriaPor;
  String auditoriaEn;

  MarcaAuditoria({this.pagoRecibido, this.pagoPor = '', this.pagoEn = '',
      this.auditoriaOk, this.auditoriaPor = '', this.auditoriaEn = ''});

  /// Pendiente de auditar mientras alguna de las dos marcas no esté
  /// en "listo".
  bool get pendiente => pagoRecibido != true || auditoriaOk != true;

  /// Alguna marca quedó en "no listo".
  bool get conProblema => pagoRecibido == false || auditoriaOk == false;

  static bool? _b(dynamic v) {
    if (v == null) return null;
    final s = v.toString().toLowerCase();
    if (s == '1' || s == 'true') return true;
    if (s == '0' || s == 'false') return false;
    return null;
  }

  // Claves cortas: se guarda una fila por factura en `configuracion`.
  Map<String, dynamic> toJson() => {
    if (pagoRecibido != null) 'p': pagoRecibido! ? 1 : 0,
    if (pagoPor.isNotEmpty) 'pu': pagoPor,
    if (pagoEn.isNotEmpty) 'pf': pagoEn,
    if (auditoriaOk != null) 'a': auditoriaOk! ? 1 : 0,
    if (auditoriaPor.isNotEmpty) 'au': auditoriaPor,
    if (auditoriaEn.isNotEmpty) 'af': auditoriaEn,
  };

  factory MarcaAuditoria.fromJson(Map m) => MarcaAuditoria(
    pagoRecibido: _b(m['p']),
    pagoPor: (m['pu'] ?? '').toString(),
    pagoEn: (m['pf'] ?? '').toString(),
    auditoriaOk: _b(m['a']),
    auditoriaPor: (m['au'] ?? '').toString(),
    auditoriaEn: (m['af'] ?? '').toString(),
  );
}

/// Clave de `configuracion` para la auditoría de una factura.
String claveAuditoriaFactura(String nroFactura) =>
    'aud_fac_${nroFactura.trim().replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_')}';

/// Lee las marcas de auditoría de la respuesta cruda de `configuracion`
/// (mapa clave → valor). Devuelve clave de config → marca.
Map<String, MarcaAuditoria> marcasDesdeConfiguracion(dynamic raw) {
  final res = <String, MarcaAuditoria>{};
  if (raw is! Map) return res;
  raw.forEach((k, v) {
    final clave = k.toString();
    if (!clave.startsWith('aud_fac_')) return;
    try {
      final j = jsonDecode((v ?? '').toString());
      if (j is Map) res[clave] = MarcaAuditoria.fromJson(j);
    } catch (_) {}
  });
  return res;
}

class AuditoriaFacturas {
  /// Descarga todas las marcas (clave `aud_fac_*` de configuracion).
  static Future<Map<String, MarcaAuditoria>> cargar() async =>
      marcasDesdeConfiguracion(await _Api.get('configuracion'));

  /// Guarda la marca de UNA factura (upsert de su propia clave).
  static Future<void> guardar(String nroFactura, MarcaAuditoria m) async {
    await _Api.post('configuracion', {
      claveAuditoriaFactura(nroFactura): jsonEncode(m.toJson()),
    });
  }
}

String fechaHoraAuditoria(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/'
    '${d.year} ${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';

// ────────────────────────────────────────────────────────────────
//  CONTEO DE UNIDADES (resumen del reporte de ventas)
// ────────────────────────────────────────────────────────────────

/// Unidades vendidas de contado y financiadas (por financiadora). En
/// auditoría el dueño cuenta: "fueron 10 financiados por Krece; si
/// salen 11, algo no facturaron".
class ConteoUnidades {
  int contado = 0;
  int financiado = 0;
  final Map<String, int> porFinanciadora = {};
}

/// Cuenta los renglones de los `detalles` del reporte de ventas. Cada
/// renglón trae `financiado` (lo pone `_asignarMontoRenglones`); la
/// financiadora sale de los pagos de su factura.
ConteoUnidades contarUnidadesVentas(List<Map<String, dynamic>> detalles) {
  final c = ConteoUnidades();
  for (final d in detalles) {
    final productos = (d['productos'] as List?) ?? const [];
    String fin = '';
    for (final p in (d['pagos'] as List?) ?? const []) {
      if (p is! Map) continue;
      final f = normalizarFinanciadoraAud(p['financiadora']?.toString()) ??
          normalizarFinanciadoraAud(p['metodo']?.toString());
      if (f != null) { fin = f; break; }
    }
    for (final p in productos) {
      if (p is! Map) continue;
      if (p['financiado'] == true) {
        c.financiado++;
        final k = fin.isEmpty ? 'Otra / sin indicar' : fin;
        c.porFinanciadora[k] = (c.porFinanciadora[k] ?? 0) + 1;
      } else {
        c.contado++;
      }
    }
  }
  return c;
}

// ────────────────────────────────────────────────────────────────
//  PRECIOS DE REFERENCIA EN LA FACTURA IMPRESA
// ────────────────────────────────────────────────────────────────

/// Líneas de precio de referencia que se imprimen bajo cada producto:
///  · contado:    "Precio ref. divisa: $110.00"
///  · financiado: "Precio base: $110.00" y "Precio Krece: $141.00"
List<String> lineasPrecioReferencia(PreciosReferencia p,
    {required bool financiado, String financiadora = ''}) {
  final lineas = <String>[];
  if (!financiado) {
    if (p.divisa != null) {
      lineas.add('Precio ref. divisa: ${formatCurrency(p.divisa!)}');
    }
    return lineas;
  }
  if (p.divisa != null) lineas.add('Precio base: ${formatCurrency(p.divisa!)}');
  if (p.financiadora != null) {
    final f = financiadora.isNotEmpty ? financiadora : 'financiado';
    lineas.add('Precio $f: ${formatCurrency(p.financiadora!)}');
  }
  return lineas;
}

/// Precios de referencia de un producto de una factura ya armada
/// (usa las listas en memoria). [financiado] decide si se busca el
/// precio de la financiadora.
PreciosReferencia preciosReferenciaFactura(FacturaModel f, Producto p,
    {required bool financiado}) {
  String? fin;
  String? lista;
  if (financiado) {
    for (final pg in f.pagos) {
      fin ??= normalizarFinanciadoraAud(pg.financiadora) ??
          normalizarFinanciadoraAud(pg.metodo);
      if ((pg.nombreLista ?? '').isNotEmpty) lista ??= pg.nombreLista;
    }
  }
  return preciosReferenciaDe(
    codigo: p.codigo,
    precioVenta: p.precioVenta,
    listas: listasPreciosGlobal,
    financiadora: fin,
    nombreLista: lista,
  );
}

/// Mismo criterio que el reporte de ventas: en una venta financiada los
/// equipos con IMEI son los financiados y los items sin IMEI van de
/// contado (si no hay equipos, todos los items son financiados).
bool productoFacturaEsFinanciado(FacturaModel f, {required bool esEquipo,
    required bool ventaFinanciada}) {
  if (!ventaFinanciada) return false;
  if (f.equipos.isEmpty) return true;
  return esEquipo;
}

/// Financiadora de la factura ("Krece"/"Cashea"...) o ''.
String financiadoraDeFactura(FacturaModel f) {
  for (final p in f.pagos) {
    final n = normalizarFinanciadoraAud(p.financiadora) ??
        normalizarFinanciadoraAud(p.metodo);
    if (n != null) return n;
  }
  return '';
}

/// Widgets PDF con las líneas de precio de referencia de un producto.
List<pw.Widget> lineasPrecioReferenciaPdf(FacturaModel f, Producto p,
    {required bool esEquipo, required bool ventaFinanciada,
     required double fontSize}) {
  final financiado = productoFacturaEsFinanciado(f,
      esEquipo: esEquipo, ventaFinanciada: ventaFinanciada);
  final precios = preciosReferenciaFactura(f, p, financiado: financiado);
  return lineasPrecioReferencia(precios,
          financiado: financiado, financiadora: financiadoraDeFactura(f))
      .map((t) => pw.Text(t,
          style: pw.TextStyle(fontSize: fontSize, fontWeight: pw.FontWeight.bold,
              color: PdfColors.black)))
      .toList();
}

// ────────────────────────────────────────────────────────────────
//  UI: panel de auditoría dentro de cada factura del reporte
// ────────────────────────────────────────────────────────────────

/// Indicador de la verificación automática (verde / rojo / gris).
class ChipAuditoriaAuto extends StatelessWidget {
  final ResultadoAuditoriaAuto r;
  final bool compacto;
  const ChipAuditoriaAuto(this.r, {super.key, this.compacto = false});

  @override
  Widget build(BuildContext context) {
    final color = switch (r.estado) {
      EstadoAuditoriaAuto.concuerda => AppColors.statusGreen,
      EstadoAuditoriaAuto.diferencia => AppColors.statusRed,
      EstadoAuditoriaAuto.sinDatos => AppColors.textSecondary,
    };
    final icono = switch (r.estado) {
      EstadoAuditoriaAuto.concuerda => Icons.verified_outlined,
      EstadoAuditoriaAuto.diferencia => Icons.error_outline,
      EstadoAuditoriaAuto.sinDatos => Icons.help_outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icono, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(child: Text(compacto ? r.titulo : 'Auto: ${r.titulo}',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                color: color))),
      ]),
    );
  }
}

/// Panel con la verificación automática y los dos botones manuales
/// (Pago recibido / Auditoría correcta), cada uno listo / no listo.
class PanelAuditoriaFactura extends StatelessWidget {
  final ResultadoAuditoriaAuto? auto;
  final MarcaAuditoria marca;
  final bool puedeMarcar;
  final bool guardando;
  final void Function(MarcaAuditoria nueva) onCambiar;

  const PanelAuditoriaFactura({super.key, required this.auto,
      required this.marca, required this.puedeMarcar,
      required this.onCambiar, this.guardando = false});

  Widget _fila(String titulo, bool? valor, String por, String en,
      void Function(bool? v) set) {
    Widget boton(String texto, bool v, Color color) {
      final activo = valor == v;
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            backgroundColor: activo ? color : null,
            foregroundColor: activo ? Colors.white : color,
            side: BorderSide(color: color),
          ),
          // Tocar el botón activo lo desmarca (vuelve a pendiente).
          onPressed: (!puedeMarcar || guardando)
              ? null : () => set(activo ? null : v),
          child: Text(texto, style: const TextStyle(fontSize: 11.5)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: const TextStyle(fontSize: 12.5,
                fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text(valor == null
                    ? 'Pendiente'
                    : '${valor ? 'Listo' : 'No listo'} · $por · $en',
                style: const TextStyle(fontSize: 10.5,
                    color: AppColors.textSecondary)),
          ],
        )),
        boton('Listo', true, AppColors.statusGreen),
        boton('No listo', false, AppColors.statusRed),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    String quien() => usuarioSesion?.nombre ?? '—';
    String ahora() => fechaHoraAuditoria(DateTime.now());
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('AUDITORÍA', style: TextStyle(fontSize: 11,
            fontWeight: FontWeight.bold, letterSpacing: 1,
            color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        if (auto != null) ...[
          ChipAuditoriaAuto(auto!),
          if (auto!.detalle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 4),
              child: Text(auto!.detalle, style: const TextStyle(
                  fontSize: 11, color: AppColors.textPrimary)),
            ),
        ],
        _fila('Pago recibido', marca.pagoRecibido, marca.pagoPor,
            marca.pagoEn, (v) {
          onCambiar(MarcaAuditoria.fromJson(marca.toJson())
            ..pagoRecibido = v
            ..pagoPor = v == null ? '' : quien()
            ..pagoEn = v == null ? '' : ahora());
        }),
        _fila('Auditoría correcta', marca.auditoriaOk, marca.auditoriaPor,
            marca.auditoriaEn, (v) {
          onCambiar(MarcaAuditoria.fromJson(marca.toJson())
            ..auditoriaOk = v
            ..auditoriaPor = v == null ? '' : quien()
            ..auditoriaEn = v == null ? '' : ahora());
        }),
        if (!puedeMarcar)
          const Text('Solo Dueño, Administrador o Gerente pueden marcar.',
              style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic)),
      ]),
    );
  }
}
