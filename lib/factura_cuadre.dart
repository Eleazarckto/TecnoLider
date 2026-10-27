// ════════════════════════════════════════════════════════════════════
//  CUADRE DE LA FACTURA — LÓGICA PURA (sin UI ni backend)
// ════════════════════════════════════════════════════════════════════
//  Pedido del dueño (oct-2026, mejoras de facturación traídas de
//  Brizuela 1.0.72 y adaptadas a TecnoLíder):
//
//   · La factura NO se emite si lo que paga el cliente no cuadra. Ya no
//     existe el aviso «Diferencia en totales» con «Continuar».
//   · TecnoLíder conserva el contado / financiado POR PRODUCTO (chip
//     F/D): una factura puede llevar un teléfono por Krece y un forro de
//     contado. Por eso el objetivo es MIXTO:
//
//         objetivo = Σ precio de contado de las líneas de contado
//                  + Σ inicial aprobada de las líneas financiadas
//
//   · Cada pago va en SU moneda (la decide el método, ver
//     [monedaDeMetodo]) y nunca se suman $ y Bs crudos.
//   · Tasa (decisión del dueño, «como hoy en TecnoLíder»): el contado
//     pagado en Bs es el PRECIO BCV (lista o columna «BCV», ver
//     auditoria_facturas.dart) × la tasa BCV; la inicial de una
//     financiadora se paga a BCV. No se usa la «tasa de divisas» de
//     Brizuela.
//   · Pago mezclado ($ y Bs): los Bs se llevan a dólares BCV; en el
//     contado valen divisa/BCV (la regla que la auditoría ya usaba para
//     el contado mezclado) y en la inicial 1 a 1. Ver [CuadreFactura]
//     (valorMin / valorMax). Tolerancia: 1 Bs, o $0,01 — igual que
//     Brizuela.
//   · El vuelto (solo en efectivo o divisas) es un pago que resta; se
//     guarda en la factura como pago NEGATIVO con es_vuelto = 1.
//   · FPB sale con lo que pague el cliente (nada, una parte o todo): la
//     deuda propuesta es lo que falta, en $ (total − pagado), y el
//     vendedor la puede cambiar. Pagar MÁS que el total es un vuelto.
//
//  El servidor repite este mismo cálculo (backend/lib/factura_cuadre.php,
//  función fc_cuadre) cuando `factura_cuadre_servidor` = '1'. Si cambia
//  una regla, cambia en los dos lados.
// ════════════════════════════════════════════════════════════════════

const String kMonedaUsd = 'USD';
const String kMonedaBs = 'BS';

/// Redondeo a centavos (igual que `redondearPrecio` de main.dart).
double redondear2(double v) => (v * 100).roundToDouble() / 100;

/// Moneda de un método de pago: 'BS' o 'USD'. Es la MISMA regla que
/// `esMetodoEnBolivares` de main.dart (la prueba lo comprueba) y que
/// `fc_moneda_de_metodo` del servidor.
String monedaDeMetodo(String metodo) {
  final m = metodo.trim().toLowerCase();
  const exactos = ['efectivo bs', 'pago móvil', 'pago movil',
      'transferencia', 'punto de venta'];
  if (exactos.contains(m)) return kMonedaBs;
  if (m.contains('\$') || m.contains('usd') || m.contains('divisa')) {
    return kMonedaUsd;
  }
  final bs = m.contains('pago móvil') || m.contains('pago movil') ||
      m.startsWith('punto') || m.startsWith('transferencia') ||
      m.contains('efectivo bs') ||
      RegExp(r'(^|[^a-z])bs\.?$').hasMatch(m);
  return bs ? kMonedaBs : kMonedaUsd;
}

/// ¿Se puede dar el vuelto por este método? Solo en efectivo ($ o Bs) o
/// en divisas (decisión del dueño: NO por Pago Móvil, BDV, punto ni
/// transferencia). El servidor aplica la misma regla
/// (`fc_metodo_permite_vuelto`).
bool metodoPermiteVuelto(String metodo) {
  final m = metodo.trim().toLowerCase();
  return m.contains('efectivo') || m.contains('divisa');
}

/// Un producto de la factura, tal como entra al cuadre.
class LineaCuadre {
  /// IMEI (equipos) o código (productos sin IMEI).
  final String ref;
  final String nombre;
  final bool esEquipo;
  /// Cashea / Weppa / Krece (chip F/D distinto de Contado y FPB).
  final bool financiada;
  /// Precio de contado en divisas (precio de venta del catálogo).
  final double precioDivisa;
  /// Precio de contado pagando en Bs, en $ a tasa BCV (lista o columna
  /// «BCV»). null o 0 = el mismo de divisas.
  final double? precioBcv;
  /// Precio en la lista de la financiadora (solo para calcular lo
  /// financiado; no entra en lo que paga el cliente).
  final double? precioFinanciadora;
  /// Inicial aprobada por la financiadora, en $ (solo financiadas).
  /// null = el vendedor todavía no la escribió.
  final double? inicial;

  const LineaCuadre({
    required this.ref,
    this.nombre = '',
    this.esEquipo = false,
    this.financiada = false,
    required this.precioDivisa,
    this.precioBcv,
    this.precioFinanciadora,
    this.inicial,
  });

  double get precioBcvEfectivo =>
      (precioBcv != null && precioBcv! > 0) ? precioBcv! : precioDivisa;

  /// Lo que paga el cliente por esta línea si paga en $.
  double get objetivoUsd => financiada ? (inicial ?? 0) : precioDivisa;

  /// Lo que paga el cliente por esta línea si paga en Bs ($ a tasa BCV).
  double get objetivoBcvUsd => financiada ? (inicial ?? 0) : precioBcvEfectivo;

  /// Lo que cubre la financiadora (precio de su lista − inicial).
  double get financiado {
    if (!financiada) return 0;
    final p = (precioFinanciadora != null && precioFinanciadora! > 0)
        ? precioFinanciadora!
        : precioDivisa;
    final f = p - (inicial ?? 0);
    return f > 0 ? redondear2(f) : 0;
  }

  /// Lo que viaja al servidor en el bloque `cuadre` de la factura.
  Map<String, dynamic> toMap() => {
    'ref': ref,
    'tipo': esEquipo ? 'equipo' : 'item',
    'financiada': financiada,
    'precio_divisa': redondear2(precioDivisa),
    if (precioBcv != null) 'precio_bcv': redondear2(precioBcv!),
    if (precioFinanciadora != null)
      'precio_financiadora': redondear2(precioFinanciadora!),
    if (inicial != null) 'inicial': redondear2(inicial!),
  };
}

/// Un pago, tal como entra al cuadre. Un vuelto puede venir con
/// [esVuelto] o con monto negativo (así lo guarda el servidor).
class PagoCuadre {
  final double monto;
  final String moneda;
  final bool esVuelto;
  final String metodo;
  const PagoCuadre({required this.monto, required this.moneda,
      this.esVuelto = false, this.metodo = ''});

  bool get restaComoVuelto => esVuelto || monto < 0;
}

/// Un tramo de lo que se paga en Bs: hasta [tope] dólares BCV, cada uno
/// vale [valor] dólares de la factura.
class _Tramo {
  final double tope;
  final double valor;
  const _Tramo(this.tope, this.valor);
}

/// Estado del cobro de una factura: cuánto se debe, cuánto se pagó y si
/// se puede emitir.
///
/// CÓMO VALEN LOS PAGOS
///   · Un dólar vale un dólar de la factura.
///   · Un bolívar se lleva a dólares BCV (÷ tasa). Pagando la INICIAL de
///     una financiadora, un dólar BCV vale un dólar (financiadoras a BCV).
///     Pagando CONTADO, el precio en Bs es el precio BCV, así que un dólar
///     BCV vale divisa/BCV (la proporción que ya usaba la auditoría).
///   · En una factura mixta pagada parte en $ y parte en Bs no se sabe
///     qué pagó cada moneda (¿los Bs fueron la inicial o el forro?). Por
///     eso el pago se valora de las dos maneras: [valorMin] (los Bs
///     pagan primero el contado) y [valorMax] (los Bs pagan primero la
///     inicial). La factura cuadra si el objetivo cae entre las dos.
///     Sin líneas financiadas, o sin pagos en Bs, las dos son iguales.
class CuadreFactura {
  /// Tasa BCV (Bs por $).
  final double tasa;
  final bool fpb;
  /// Σ precio en divisas de las líneas de contado.
  final double contadoDivisa;
  /// Σ precio BCV (en $) de las líneas de contado.
  final double contadoBcv;
  /// Σ inicial aprobada de las líneas financiadas.
  final double inicialTotal;
  /// Σ (precio de la financiadora − inicial) de las líneas financiadas.
  final double montoFinanciado;
  /// Netos de vuelto, cada uno en su moneda.
  final double pagadoUsd;
  final double pagadoBs;
  final double vueltoUsd;
  final double vueltoBs;
  /// Líneas financiadas a las que les falta la inicial.
  final List<String> sinInicial;
  /// Vueltos registrados por un método que no los permite.
  final List<String> vueltosNoPermitidos;
  final bool hayFinanciadas;

  const CuadreFactura._({
    required this.tasa,
    required this.fpb,
    required this.contadoDivisa,
    required this.contadoBcv,
    required this.inicialTotal,
    required this.montoFinanciado,
    required this.pagadoUsd,
    required this.pagadoBs,
    required this.vueltoUsd,
    required this.vueltoBs,
    required this.sinInicial,
    required this.vueltosNoPermitidos,
    required this.hayFinanciadas,
  });

  factory CuadreFactura.calcular({
    required List<LineaCuadre> lineas,
    required List<PagoCuadre> pagos,
    required double tasa,
    bool fpb = false,
  }) {
    double div = 0, bcv = 0, ini = 0, fin = 0;
    final sinIni = <String>[];
    var hayFin = false;
    for (final l in lineas) {
      if (l.financiada) {
        hayFin = true;
        final i = l.inicial;
        if (i == null || i < 0) {
          sinIni.add(l.nombre.isNotEmpty ? l.nombre : l.ref);
        } else {
          ini += i;
        }
        fin += l.financiado;
      } else {
        div += l.precioDivisa;
        bcv += l.precioBcvEfectivo;
      }
    }
    double usd = 0, bs = 0, vUsd = 0, vBs = 0;
    final malos = <String>[];
    for (final p in pagos) {
      final m = p.monto.abs();
      if (p.restaComoVuelto) {
        if (p.metodo.isNotEmpty && !metodoPermiteVuelto(p.metodo)) {
          malos.add(p.metodo);
        }
        if (p.moneda == kMonedaBs) { bs -= m; vBs += m; } else { usd -= m; vUsd += m; }
      } else {
        if (p.moneda == kMonedaBs) { bs += m; } else { usd += m; }
      }
    }
    return CuadreFactura._(
      tasa: tasa,
      fpb: fpb,
      contadoDivisa: redondear2(div),
      contadoBcv: redondear2(bcv),
      inicialTotal: redondear2(ini),
      montoFinanciado: redondear2(fin),
      pagadoUsd: redondear2(usd),
      pagadoBs: redondear2(bs),
      vueltoUsd: redondear2(vUsd),
      vueltoBs: redondear2(vBs),
      sinInicial: sinIni,
      vueltosNoPermitidos: malos,
      hayFinanciadas: hayFin,
    );
  }

  /// Lo que paga el cliente si paga TODO en $: contado + inicial.
  double get objetivoUsd => redondear2(contadoDivisa + inicialTotal);

  /// Lo mismo pagando todo en Bs: (precio BCV del contado + inicial) × tasa.
  double get objetivoBs => redondear2((contadoBcv + inicialTotal) * tasa);

  /// Lo pagado en Bs, en dólares BCV.
  double get _v => tasa > 0 ? pagadoBs / tasa : 0;

  /// Cuánto vale un dólar BCV pagando contado.
  double get _k =>
      (contadoBcv > 0 && contadoDivisa > 0) ? contadoDivisa / contadoBcv : 1;

  List<_Tramo> get _contadoPrimero =>
      [_Tramo(contadoBcv, _k), _Tramo(inicialTotal, 1)];
  List<_Tramo> get _inicialPrimero =>
      [_Tramo(inicialTotal, 1), _Tramo(contadoBcv, _k)];

  /// Lo que valen [v] dólares BCV repartidos en ese orden. Lo que pasa de
  /// todos los tramos vale como el contado (o 1 si no hay contado). Un
  /// vuelto en Bs que deja [v] negativo vale 1 a 1.
  double _valor(double v, List<_Tramo> orden) {
    if (v <= 0) return v;
    var resto = v, valor = 0.0;
    for (final t in orden) {
      if (t.tope <= 0 || t.valor <= 0) continue;
      final usar = resto < t.tope ? resto : t.tope;
      valor += usar * t.valor;
      resto -= usar;
      if (resto <= 0) return valor;
    }
    return valor + resto * _k;
  }

  /// Inversa de [_valor]: cuántos dólares BCV hacen falta para valer [x].
  double _inverso(double x, List<_Tramo> orden) {
    if (x <= 0) return x;
    var resto = x, v = 0.0;
    for (final t in orden) {
      if (t.tope <= 0 || t.valor <= 0) continue;
      final cabe = t.tope * t.valor;
      if (resto <= cabe) return v + resto / t.valor;
      resto -= cabe;
      v += t.tope;
    }
    return v + resto / _k;
  }

  /// Valor de lo pagado si los Bs pagaron primero el contado.
  double get valorMin => redondear2(pagadoUsd + _valor(_v, _contadoPrimero));

  /// Valor de lo pagado si los Bs pagaron primero la inicial.
  double get valorMax => redondear2(pagadoUsd + _valor(_v, _inicialPrimero));

  /// Tolerancia en $: 1 Bs, o $0,01.
  double get tolerancia {
    if (tasa <= 0) return 0.01;
    final unBs = 1 / tasa;
    return unBs > 0.01 ? unBs : 0.01;
  }

  bool get _faltaTasa => pagadoBs.abs() > 0.004 && tasa <= 0;

  /// Lo que falta (0 si no falta), en $ y en Bs. En Bs, al precio BCV del
  /// contado: es lo que hay que cobrarle.
  double get faltaUsd {
    final f = objetivoUsd - valorMax;
    return f > tolerancia + 1e-9 ? redondear2(f) : 0;
  }

  double get faltaBs => faltaUsd <= 0
      ? 0
      : redondear2(
          (_inverso(objetivoUsd - pagadoUsd, _contadoPrimero) - _v) * tasa);

  /// Lo pagado de más (0 si no sobra): el vuelto, en $ o en Bs.
  double get sobraUsd {
    final s = valorMin - objetivoUsd;
    return s > tolerancia + 1e-9 ? redondear2(s) : 0;
  }

  double get sobraBs => sobraUsd <= 0
      ? 0
      : redondear2(
          (_v - _inverso(objetivoUsd - pagadoUsd, _contadoPrimero)) * tasa);

  /// Deuda FPB propuesta: lo que el cliente no pagó, en $. El vendedor
  /// la puede cambiar.
  double get deudaFpbPropuesta => fpb ? faltaUsd : 0;

  /// Por qué no se puede emitir, o null si cuadra.
  String? get problema {
    if (sinInicial.isNotEmpty) {
      return 'Escriba la inicial aprobada por la financiadora de: '
          '${sinInicial.join(', ')}.';
    }
    if (vueltosNoPermitidos.isNotEmpty) {
      return 'El vuelto solo se da en efectivo o divisas '
          '(no por ${vueltosNoPermitidos.toSet().join(', ')}).';
    }
    if (_faltaTasa) {
      return 'No hay tasa BCV: no se pueden convertir los pagos en Bs.';
    }
    if (sobraUsd > 0) {
      return 'El cliente pagó ${fmtUsd(sobraUsd)}'
          '${tasa > 0 ? ' (${fmtBs(sobraBs)})' : ''} de más: '
          'registre el vuelto en efectivo o divisas.';
    }
    if (faltaUsd > 0 && !fpb) {
      final que = hayFinanciadas ? ' (contado + inicial)' : '';
      return 'Falta cobrar ${fmtUsd(faltaUsd)}'
          '${tasa > 0 ? ' o ${fmtBs(faltaBs)}' : ''}$que.';
    }
    return null;
  }

  bool get cuadra => problema == null;

  /// Vuelto sugerido en la moneda pedida.
  double vueltoSugerido(String moneda) =>
      moneda == kMonedaBs ? sobraBs : sobraUsd;

  /// Resumen que viaja con la factura en el bloque `cuadre` (el servidor
  /// repite la cuenta; ver backend/lib/factura_cuadre.php).
  Map<String, dynamic> resumen() => {
    'version': 1,
    'tasa_bcv': tasa,
    'fpb': fpb,
    'objetivo_usd': objetivoUsd,
    'objetivo_bs': objetivoBs,
    'pagado_usd': pagadoUsd,
    'pagado_bs': pagadoBs,
    'inicial': inicialTotal,
    'monto_financiado': montoFinanciado,
  };

  static String fmtUsd(double v) => '\$${v.toStringAsFixed(2)}';
  static String fmtBs(double v) => 'Bs ${v.toStringAsFixed(2)}';
}

/// Precio en $ de una línea para `precio_unitario`: el de contado, o en
/// una financiada el de la lista de su financiadora (si no hay, el de
/// contado).
double precioUnitarioDeLinea(LineaCuadre l) => redondear2(l.financiada &&
        (l.precioFinanciadora ?? 0) > 0
    ? l.precioFinanciadora!
    : l.precioDivisa);

/// Agrega al cuerpo de la factura (el `toApiMap` de siempre) lo nuevo:
/// `precio_unitario` en cada equipo e ítem, `tasa_bcv`, `inicial`,
/// `monto_financiado` y el bloque `cuadre` con las líneas. Las líneas van
/// en el MISMO orden que `equipos` y luego `items`. Devuelve un mapa
/// nuevo (las listas de `toApiMap` son `Map<String, String>` y no
/// admiten un número).
Map<String, dynamic> agregarCuadreAlCuerpo(Map<String, dynamic> cuerpo,
    List<LineaCuadre> lineas, CuadreFactura c) {
  final m = Map<String, dynamic>.from(cuerpo);
  final eq = (m['equipos'] as List?) ?? const [];
  final it = (m['items'] as List?) ?? const [];
  Map<String, dynamic> conPrecio(dynamic e, String clave, int i) {
    final base = e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{clave: e};
    if (i < lineas.length) base['precio_unitario'] = precioUnitarioDeLinea(lineas[i]);
    return base;
  }
  m['equipos'] = [for (var i = 0; i < eq.length; i++) conPrecio(eq[i], 'imei', i)];
  m['items'] = [
    for (var i = 0; i < it.length; i++) conPrecio(it[i], 'codigo', eq.length + i)
  ];
  m['tasa_bcv'] = c.tasa;
  m['inicial'] = c.inicialTotal;
  m['monto_financiado'] = c.montoFinanciado;
  m['cuadre'] = {...c.resumen(), 'lineas': [for (final l in lineas) l.toMap()]};
  return m;
}

/// Monto en $ de un pago para guardarlo en `factura_pagos.monto_usd`:
/// los Bs a tasa BCV. Conserva el signo (vuelto negativo).
double montoUsdDePago(double monto, String moneda, double tasa) {
  if (moneda != kMonedaBs) return redondear2(monto);
  return tasa > 0 ? redondear2(monto / tasa) : 0;
}

/// Número de la factura de una cuenta por cobrar: el que guarda el
/// servidor (`nro_factura`) o, en las cuentas viejas, el que figura en
/// la nota «Generado automáticamente desde factura N». '' si la cuenta
/// se cargó a mano.
String nroFacturaDeNotas(String nroFactura, String notas) {
  if (nroFactura.trim().isNotEmpty) return nroFactura.trim();
  final m = RegExp(r'desde factura\s+([A-Za-z0-9._-]+)').firstMatch(notas);
  return m?.group(1) ?? '';
}

/// Clave de idempotencia de un intento de factura: 32 hex. Se genera al
/// abrir el formulario y solo cambia después de guardar con éxito.
String nuevaClaveIdempotencia(int Function(int max) azar) =>
    List.generate(32, (_) => azar(16).toRadixString(16)).join();
