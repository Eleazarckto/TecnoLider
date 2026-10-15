// ════════════════════════════════════════════════════════════════════
//  FINANZAS POR TIENDA — LÓGICA PURA (sin UI ni backend)
// ════════════════════════════════════════════════════════════════════
//  Cálculos de Costos y Finanzas que el dueño pidió entender "como en
//  su Excel", separados aquí para poder probarlos con tests:
//
//   1. GANANCIA REAL vs DIFERENCIAL CAMBIARIO
//      Antes la ganancia de una venta financiada se medía contra el
//      precio financiado: equipo de costo 100, de contado 120, vendido
//      financiado en 140 → el sistema decía "ganancia 40". La ganancia
//      REAL de la venta es 20 (contado − costo); los otros 20 salen del
//      financiamiento / la tasa y son DIFERENCIAL CAMBIARIO, que se
//      reporta aparte.
//
//      Cómo lo calcula el dueño con Krece, VENTA POR VENTA y con las
//      tasas BCV y divisa DE ESE DÍA (ver sección 1):
//        inicial convertida a divisa
//      + lo que debe la financiadora convertido a divisa (paga en Bs a
//        tasa BCV: "me pagaron $1000, convertido son 850")
//      − valor de contado de los equipos
//      = margen por diferencial cambiario.
//
//   2. BALANCE NETO POR TIENDA
//        ventas cobradas en divisa + montos financiados
//      − costo de los equipos − gastos de la tienda
//      (cada venta convertida con las tasas de su día).
//
//   3. EQUILIBRIO DIARIO ("hoy generamos 200, gastamos 50, quedamos en
//      150") y el día del mes en que cada tienda cubre sus gastos.
//
//   4. FLUJO DE CAJA por tienda y consolidado, SIN mezclar $ con Bs.
//
//   5. Modelos de gastos y nómina que se guardan como JSON en la tabla
//      `configuracion` (clave/valor) para no tocar el servidor.
// ════════════════════════════════════════════════════════════════════

import 'cuenta_financiadora.dart';

/// Moneda de un monto. Nunca se suman Bs con $ sin convertir.
const String monedaUsd = 'USD';
const String monedaBs = 'BS';

double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

/// Fecha "dd/MM/yyyy", "yyyy-MM-dd" o ISO → DateTime (o null).
DateTime? parseFechaCF(String? texto) {
  if (texto == null) return null;
  final s = texto.trim();
  if (s.isEmpty) return null;
  final iso = DateTime.tryParse(s);
  if (iso != null) return iso;
  final m = RegExp(r'^(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})').firstMatch(s);
  if (m == null) return null;
  return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!),
      int.parse(m.group(1)!));
}

/// Solo la fecha (sin hora), para agrupar por día.
DateTime soloDia(DateTime d) => DateTime(d.year, d.month, d.day);

/// true si [d] cae entre [desde] y [hasta] (ambos días incluidos).
bool enRangoCF(DateTime d, DateTime desde, DateTime hasta) {
  final x = soloDia(d);
  return !x.isBefore(soloDia(desde)) && !x.isAfter(soloDia(hasta));
}

String fechaIsoCF(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

// ════════════════════════════════════════════════════════════════════
//  1. VENTAS: GANANCIA REAL Y DIFERENCIAL CAMBIARIO
// ════════════════════════════════════════════════════════════════════
//  Se calcula VENTA POR VENTA con las tasas DEL DÍA de cada venta, como
//  lo hace el dueño en su Excel. Antes se usaba UNA sola tasa divisa
//  (Binance) para todo el período y en ventas de contado salían
//  diferenciales raros (~$7, 12-14 %): una venta de hace tres semanas
//  se convertía con la tasa de hoy.
//
//  Ejemplo del dueño (financiada con Krece): contado $100, costo $88,
//  lista Krece $127. Inicial $38 BCV pagada en Bs a 879 = 33.402 Bs →
//  a la tasa divisa del día (1015) son $32,91 reales. Krece debe
//  127 − 38 = $89 BCV y los paga en Bs a BCV: 89 × 879 = 78.231 Bs →
//  ÷ 1015 = $77,07 reales. Ingreso real $109,98; diferencial
//  109,98 − 100 = $9,98; ganancia real 100 − 88 = $12.
//
//  Contado pagado en Bs: precio BCV $120 cobrado a 879 = 105.480 Bs →
//  ÷ 1015 = $103,92 reales → diferencial $3,92. Contado en $ efectivo:
//  entra lo cobrado tal cual (diferencial normalmente 0).
//
//  Lo que la plataforma debe es la fórmula del dueño: precio de su
//  lista − inicial, SIN descontar comisión. La comisión de la
//  financiadora (Cashea/Weppa) se informa aparte en
//  [VentaAnalizada.comisionFinanciadora] y no se mezcla con el
//  diferencial.
//
//  Si un día no tiene tasa divisa cargada NO se adivina: la venta se
//  marca [VentaAnalizada.faltaTasa] y se cuenta a precio de contado
//  (diferencial 0) hasta que el dueño cargue la tasa de ese día.
// ════════════════════════════════════════════════════════════════════

/// De dónde salió el precio/costo con que se analizó un equipo.
const String origenPrecioFactura = 'factura';
const String origenPrecioHistorial = 'historial';
const String origenPrecioActual = 'actual';

/// Un equipo o artículo vendido, con los precios VIGENTES el día de la
/// venta (los guardados con la factura; si no, los del historial de
/// precios; y si no hay historial, los actuales del catálogo).
class EquipoVendidoCF {
  final String codigo;
  final String imei;
  final String nombre;
  /// Costo del producto el día de la venta.
  final double costo;
  /// Precio de contado / divisa el día de la venta.
  final double precioContado;
  /// Precio en la lista de la financiadora (la "Base" sobre la que la
  /// financiadora le paga a la tienda). null = venta de contado o sin
  /// lista: se usa el de contado.
  final double? precioFinanciadora;
  /// [origenPrecioFactura], [origenPrecioHistorial] u [origenPrecioActual].
  final String origenPrecio;
  const EquipoVendidoCF({
    this.codigo = '',
    this.imei = '',
    this.nombre = '',
    required this.costo,
    required this.precioContado,
    this.precioFinanciadora,
    this.origenPrecio = origenPrecioActual,
  });
}

/// Un pago que hizo el CLIENTE en la factura.
class PagoClienteCF {
  /// Monto en SU moneda: Bs si [enBolivares], si no $.
  final double monto;
  /// true si el método es en bolívares (Pago Móvil, Punto, etc.).
  final bool enBolivares;
  /// Tasa BCV guardada al facturar (0 = desconocida).
  final double tasa;
  final bool esInicial;
  final String financiadora;
  const PagoClienteCF({
    required this.monto,
    required this.enBolivares,
    this.tasa = 0,
    this.esInicial = false,
    this.financiadora = '',
  });
}

/// Factura simplificada para los cálculos de finanzas.
class FacturaCF {
  final String nroFactura;
  final String tienda;
  /// Día de la venta (para agrupar y para buscar las tasas del día).
  final DateTime fecha;
  final List<EquipoVendidoCF> equipos;
  final List<PagoClienteCF> pagos;
  const FacturaCF({
    required this.nroFactura,
    required this.tienda,
    required this.fecha,
    required this.equipos,
    required this.pagos,
  });

  /// Financiadora de la factura ('' = contado). La primera que aparezca.
  String get financiadora {
    for (final p in pagos) {
      if (p.financiadora.trim().isNotEmpty) return p.financiadora.trim();
    }
    return '';
  }

  bool get esFinanciada => financiadora.isNotEmpty;
}

/// Tasas DEL DÍA de una venta.
///   · [tasaBcv]: la oficial, a la que la financiadora paga en Bs.
///   · [tasaDivisa]: a la que el dueño vende los Bs para tener dólares
///     reales (USDT / paralelo). 0 = no se cargó: no se adivina.
class TasasCF {
  final double tasaBcv;
  final double tasaDivisa;
  const TasasCF({required this.tasaBcv, required this.tasaDivisa});

  /// Cuántos dólares reales vale 1 dólar BCV (879 / 1015 = 0,866).
  /// 0 si falta alguna tasa.
  double get factorBcvADivisa =>
      (tasaBcv > 0 && tasaDivisa > 0) ? tasaBcv / tasaDivisa : 0;

  /// Bs → dólares reales con la tasa divisa del día (0 si no hay).
  double bsADivisa(double bs) => tasaDivisa > 0 ? bs / tasaDivisa : 0;
}

/// Un equipo dentro de una venta analizada: lo que el dueño compara
/// renglón por renglón con su Excel.
class EquipoAnalizado {
  final EquipoVendidoCF equipo;
  /// Lo que debe la financiadora por este equipo, en $ BCV.
  final double financiadoBcv;
  /// Parte de la inicial que le toca a este equipo, en $ BCV.
  final double inicialBcv;
  /// Comisión que cobraría la financiadora (solo informativa).
  final double comision;
  /// Lo que entró en dólares reales por este equipo.
  final double ingresoEnDivisa;
  const EquipoAnalizado({
    required this.equipo,
    required this.financiadoBcv,
    required this.inicialBcv,
    required this.comision,
    required this.ingresoEnDivisa,
  });
  double get costo => equipo.costo;
  double get precioContado => equipo.precioContado;
  double get gananciaReal => precioContado - costo;
  double get diferencialCambiario => ingresoEnDivisa - precioContado;
  double get gananciaTotal => ingresoEnDivisa - costo;
}

/// Resultado de analizar una factura con las tasas de su día.
class VentaAnalizada {
  final String nroFactura;
  final String tienda;
  final DateTime fecha;
  final String financiadora;
  final int unidades;
  /// Tasas con que se analizó (las del día de la venta).
  final double tasaBcv;
  final double tasaDivisa;
  /// Σ costo de los equipos.
  final double costo;
  /// Σ precio de contado de los equipos.
  final double valorContado;
  /// Pagos del cliente en $ (sin convertir).
  final double cobradoUsd;
  /// Pagos del cliente en Bs (sin convertir).
  final double cobradoBs;
  /// Pagos del cliente convertidos a dólares reales (0 en la parte Bs
  /// si falta la tasa divisa del día).
  final double cobradoEnDivisa;
  /// Lo que debe la financiadora en $ BCV (precio de su lista − inicial).
  final double financiadoBcv;
  /// Lo que debe la financiadora convertido a dólares reales.
  final double financiadoEnDivisa;
  /// Comisión de la financiadora (Cashea/Weppa). Solo informativa: el
  /// dueño mide el diferencial sin descontarla.
  final double comisionFinanciadora;
  /// true si al día de la venta le falta la tasa divisa (o la BCV para
  /// convertir lo que paga la financiadora): no se calcula diferencial.
  final bool faltaTasa;
  final List<EquipoAnalizado> equipos;

  const VentaAnalizada({
    required this.nroFactura,
    required this.tienda,
    required this.fecha,
    required this.financiadora,
    required this.unidades,
    this.tasaBcv = 0,
    this.tasaDivisa = 0,
    required this.costo,
    required this.valorContado,
    required this.cobradoUsd,
    required this.cobradoBs,
    required this.cobradoEnDivisa,
    required this.financiadoBcv,
    required this.financiadoEnDivisa,
    this.comisionFinanciadora = 0,
    this.faltaTasa = false,
    this.equipos = const [],
  });

  bool get esFinanciada => financiadora.isNotEmpty;

  /// Todo lo que entra por la venta, en dólares reales. Sin tasa del
  /// día se cuenta el valor de contado (no se inventa un diferencial).
  double get ingresoEnDivisa =>
      faltaTasa ? valorContado : cobradoEnDivisa + financiadoEnDivisa;

  /// Ganancia REAL: como si se hubiera vendido de contado.
  double get gananciaReal => valorContado - costo;

  /// Lo que sobra (o falta) por financiamiento y tasa, comparado
  /// SIEMPRE contra el precio de contado en divisa.
  double get diferencialCambiario => ingresoEnDivisa - valorContado;

  /// Ganancia total = real + diferencial = ingreso real − costo.
  double get gananciaTotal => ingresoEnDivisa - costo;
}

/// Analiza una factura con las tasas de SU día: separa ganancia real y
/// diferencial cambiario, y lo reparte por equipo.
VentaAnalizada analizarFactura(FacturaCF f, TasasCF tasas) {
  double costo = 0, contado = 0, cobUsd = 0, cobBs = 0, cobDiv = 0;
  for (final e in f.equipos) {
    costo += e.costo;
    contado += e.precioContado;
  }
  for (final p in f.pagos) {
    if (p.enBolivares) {
      cobBs += p.monto;
      cobDiv += tasas.bsADivisa(p.monto);
    } else {
      cobUsd += p.monto;
      cobDiv += p.monto;
    }
  }

  final fin = f.financiadora;
  final financiada = fin.isNotEmpty && f.equipos.isNotEmpty;
  List<EquipoFinanciado> cuentas = const [];
  if (financiada) {
    // Inicial en $ BCV: los Bs a la tasa con que se cobraron (la BCV de
    // ese momento); los $ tal cual. Si hay pagos marcados como inicial,
    // solo esos; si no, todos los pagos del cliente son la inicial.
    final hayMarcados = f.pagos.any((p) => p.esInicial);
    double inicial = 0;
    for (final p in f.pagos) {
      if (hayMarcados && !p.esInicial) continue;
      if (p.enBolivares) {
        final t = p.tasa > 0 ? p.tasa : tasas.tasaBcv;
        inicial += t > 0 ? p.monto / t : 0;
      } else {
        inicial += p.monto;
      }
    }
    cuentas = [
      for (final e in f.equipos)
        EquipoFinanciado(
          financiadora: fin,
          nroFactura: f.nroFactura,
          base: e.precioFinanciadora ?? e.precioContado,
          imei: e.imei,
          codigo: e.codigo,
        ),
    ];
    // Reparte la inicial por equipo (y calcula la comisión de cada uno,
    // que aquí solo se informa).
    calcularDeudaFactura(cuentas, redondearCentavos(inicial));
  }

  // Fórmula del dueño: lo que debe la plataforma = lista − inicial.
  double netoDe(EquipoFinanciado c) =>
      (c.base - c.inicial).clamp(0.0, double.infinity).toDouble();
  final financiadoBcv = cuentas.fold<double>(0, (s, c) => s + netoDe(c));
  final comision = cuentas.fold<double>(0, (s, c) => s + c.comision);

  // ¿Faltan tasas? Hacen falta si entraron Bs o si la financiadora
  // (que paga en Bs a BCV) debe algo.
  final faltaDivisa =
      (cobBs > 0 || financiadoBcv > 0) && tasas.tasaDivisa <= 0;
  final faltaBcv = financiadoBcv > 0 && tasas.tasaBcv <= 0;
  final faltaTasa = faltaDivisa || faltaBcv;
  final factor = tasas.factorBcvADivisa;

  // Reparto por equipo: lo cobrado al cliente en proporción a la base
  // de cada equipo (lista de la financiadora o precio de contado).
  final pesos = [
    for (var i = 0; i < f.equipos.length; i++)
      financiada ? cuentas[i].base : f.equipos[i].precioContado,
  ];
  final sumaPesos = pesos.fold<double>(0, (s, x) => s + x);
  final equipos = <EquipoAnalizado>[];
  for (var i = 0; i < f.equipos.length; i++) {
    final e = f.equipos[i];
    final parte =
        sumaPesos > 0 ? pesos[i] / sumaPesos : 1 / f.equipos.length;
    final finBcv = financiada ? netoDe(cuentas[i]) : 0.0;
    equipos.add(EquipoAnalizado(
      equipo: e,
      financiadoBcv: finBcv,
      inicialBcv: financiada ? cuentas[i].inicial : 0,
      comision: financiada ? cuentas[i].comision : 0,
      ingresoEnDivisa:
          faltaTasa ? e.precioContado : cobDiv * parte + finBcv * factor,
    ));
  }

  return VentaAnalizada(
    nroFactura: f.nroFactura,
    tienda: f.tienda,
    fecha: f.fecha,
    financiadora: fin,
    unidades: f.equipos.length,
    tasaBcv: tasas.tasaBcv,
    tasaDivisa: tasas.tasaDivisa,
    costo: costo,
    valorContado: contado,
    cobradoUsd: cobUsd,
    cobradoBs: cobBs,
    cobradoEnDivisa: cobDiv,
    financiadoBcv: financiadoBcv,
    financiadoEnDivisa: financiadoBcv * factor,
    comisionFinanciadora: comision,
    faltaTasa: faltaTasa,
    equipos: equipos,
  );
}

/// Analiza cada factura con las tasas de su día ([tasasDe]).
List<VentaAnalizada> analizarFacturas(Iterable<FacturaCF> facturas,
        TasasCF Function(DateTime dia) tasasDe) =>
    [for (final f in facturas) analizarFactura(f, tasasDe(f.fecha))];

/// Totales de un grupo de ventas (una tienda, una financiadora, un día).
class ResumenGanancia {
  int facturas = 0;
  int unidades = 0;
  /// Ventas sin la tasa del día (contadas a precio de contado).
  int sinTasa = 0;
  double costo = 0;
  double valorContado = 0;
  double cobradoUsd = 0;
  double cobradoBs = 0;
  double cobradoEnDivisa = 0;
  double financiadoBcv = 0;
  double financiadoEnDivisa = 0;
  double comisionFinanciadora = 0;
  /// Valor de contado de las ventas sin tasa (entran como ingreso SIN
  /// diferencial hasta que se cargue la tasa del día).
  double contadoSinTasa = 0;

  void sumar(VentaAnalizada v) {
    facturas++;
    unidades += v.unidades;
    costo += v.costo;
    valorContado += v.valorContado;
    cobradoUsd += v.cobradoUsd;
    cobradoBs += v.cobradoBs;
    comisionFinanciadora += v.comisionFinanciadora;
    financiadoBcv += v.financiadoBcv;
    if (v.faltaTasa) {
      sinTasa++;
      contadoSinTasa += v.valorContado;
    } else {
      cobradoEnDivisa += v.cobradoEnDivisa;
      financiadoEnDivisa += v.financiadoEnDivisa;
    }
  }

  double get ingresoEnDivisa =>
      cobradoEnDivisa + financiadoEnDivisa + contadoSinTasa;
  double get gananciaReal => valorContado - costo;
  double get diferencialCambiario => ingresoEnDivisa - valorContado;
  double get gananciaTotal => ingresoEnDivisa - costo;

  /// Balance neto del dueño: ventas en divisa + montos financiados −
  /// costo de los equipos − gastos (cada venta convertida con las
  /// tasas de SU día).
  double balanceNeto(double gastosUsd) => balanceNetoTienda(
        ventasDivisa: cobradoEnDivisa + contadoSinTasa,
        montosFinanciados: financiadoEnDivisa,
        costoEquipos: costo,
        gastos: gastosUsd,
      );
}

/// Fórmula del dueño, tal cual la dictó.
double balanceNetoTienda({
  required double ventasDivisa,
  required double montosFinanciados,
  required double costoEquipos,
  required double gastos,
}) =>
    ventasDivisa + montosFinanciados - costoEquipos - gastos;

/// Agrupa ventas por una clave (tienda, financiadora, día…).
Map<String, ResumenGanancia> agruparGanancias(
    Iterable<VentaAnalizada> ventas, String Function(VentaAnalizada) clave) {
  final r = <String, ResumenGanancia>{};
  for (final v in ventas) {
    r.putIfAbsent(clave(v), () => ResumenGanancia()).sumar(v);
  }
  return r;
}

ResumenGanancia totalGanancias(Iterable<VentaAnalizada> ventas) {
  final r = ResumenGanancia();
  for (final v in ventas) {
    r.sumar(v);
  }
  return r;
}

// ── Tasas de cada día ───────────────────────────────────────────────
//  La tasa divisa (USDT / paralelo) la carga el dueño día por día; se
//  guarda en `configuracion`, una clave por mes (`cf_tasas_dia_AAAA_MM`)
//  con un mapa "AAAA-MM-DD" → {"d": divisa, "b": bcv}. La BCV también
//  se puede corregir a mano; si no, sale de la tabla `tasa_bcv`, de las
//  ventas de ese día (la tasa con que se cobró) o de la más reciente
//  anterior. La divisa NUNCA se arrastra de otro día: si falta, falta.

/// Clave de `configuracion` con las tasas cargadas de un mes.
String claveTasasDiaMes(int anio, int mes) =>
    'cf_tasas_dia_${anio}_${mes.toString().padLeft(2, '0')}';

/// Lo que el dueño cargó a mano para un día (0 = no cargó esa tasa).
class RegistroTasaDia {
  final double divisa;
  final double bcv;
  const RegistroTasaDia({this.divisa = 0, this.bcv = 0});
  factory RegistroTasaDia.fromJson(dynamic m) => m is Map
      ? RegistroTasaDia(divisa: _num(m['d']), bcv: _num(m['b']))
      : RegistroTasaDia(divisa: _num(m));
  Map<String, dynamic> toJson() => {
        if (divisa > 0) 'd': divisa,
        if (bcv > 0) 'b': bcv,
      };
}

const String fuenteBcvManual = 'cargada a mano';
const String fuenteBcvTabla = 'BCV del día';
const String fuenteBcvVentas = 'de las ventas del día';
const String fuenteBcvAnterior = 'la del día anterior';
const String fuenteBcvActual = 'la actual del sistema';

/// Tasas de un día ya resueltas, con su origen.
class TasaDiaResuelta {
  final DateTime dia;
  final double bcv;
  final String fuenteBcv;
  final double divisa;
  /// true = la cargó el dueño; false = sugerida (Binance) o falta.
  final bool divisaConfirmada;
  const TasaDiaResuelta({
    required this.dia,
    required this.bcv,
    required this.fuenteBcv,
    required this.divisa,
    required this.divisaConfirmada,
  });
  bool get faltaDivisa => divisa <= 0;
  bool get divisaSugerida => divisa > 0 && !divisaConfirmada;
  TasasCF get tasas => TasasCF(tasaBcv: bcv, tasaDivisa: divisa);
}

/// Resuelve las tasas de cada día a partir de lo cargado a mano, la
/// tabla BCV y las tasas con que se cobraron las ventas. Las claves de
/// los mapas son fechas "AAAA-MM-DD".
class TasasPorDia {
  final Map<String, RegistroTasaDia> manuales;
  final Map<String, double> bcvTabla;
  final Map<String, double> bcvVentas;
  /// BCV actual del sistema (para hoy, si no hay otra).
  final double bcvActual;
  /// Tasa Binance que el dueño tiene configurada: solo se SUGIERE para
  /// hoy (no se sabe a qué día corresponde una tasa vieja).
  final double divisaSugeridaHoy;
  final DateTime hoy;
  final List<String> _diasBcv;

  TasasPorDia({
    this.manuales = const {},
    this.bcvTabla = const {},
    this.bcvVentas = const {},
    this.bcvActual = 0,
    this.divisaSugeridaHoy = 0,
    DateTime? hoy,
  })  : hoy = soloDia(hoy ?? DateTime.now()),
        _diasBcv = {
          ...bcvTabla.keys,
          ...bcvVentas.keys,
          for (final e in manuales.entries)
            if (e.value.bcv > 0) e.key,
        }.toList()
          ..sort();

  /// Lee todos los meses guardados (`cf_tasas_dia_*`) de `configuracion`.
  /// [decodificar] convierte el valor crudo (texto JSON) en mapa.
  static Map<String, RegistroTasaDia> leerManuales(
      Map<String, dynamic> config, dynamic Function(dynamic) decodificar) {
    final r = <String, RegistroTasaDia>{};
    for (final e in config.entries) {
      if (!e.key.startsWith('cf_tasas_dia_')) continue;
      final v = decodificar(e.value);
      if (v is! Map) continue;
      v.forEach((k, x) {
        final d = parseFechaCF(k.toString());
        if (d != null) r[fechaIsoCF(d)] = RegistroTasaDia.fromJson(x);
      });
    }
    return r;
  }

  double _bcvExacto(String iso) {
    final m = manuales[iso]?.bcv ?? 0;
    if (m > 0) return m;
    return bcvTabla[iso] ?? bcvVentas[iso] ?? 0;
  }

  String _fuenteExacta(String iso) {
    if ((manuales[iso]?.bcv ?? 0) > 0) return fuenteBcvManual;
    if (bcvTabla.containsKey(iso)) return fuenteBcvTabla;
    return fuenteBcvVentas;
  }

  TasaDiaResuelta resolver(DateTime dia) {
    final d = soloDia(dia);
    final iso = fechaIsoCF(d);
    double bcv = _bcvExacto(iso);
    String fuente = bcv > 0 ? _fuenteExacta(iso) : '';
    if (bcv <= 0) {
      // La más reciente anterior (fines de semana y feriados).
      for (var i = _diasBcv.length - 1; i >= 0; i--) {
        if (_diasBcv[i].compareTo(iso) >= 0) continue;
        bcv = _bcvExacto(_diasBcv[i]);
        if (bcv > 0) {
          fuente = fuenteBcvAnterior;
          break;
        }
      }
    }
    // Hoy: la que el sistema acaba de traer del BCV manda sobre la
    // deducida de las ventas (algún equipo pudo cobrar con la de ayer).
    if (d == hoy &&
        bcvActual > 0 &&
        fuente != fuenteBcvManual &&
        fuente != fuenteBcvTabla) {
      bcv = bcvActual;
      fuente = fuenteBcvActual;
    }
    final manualDiv = manuales[iso]?.divisa ?? 0;
    final sugerida = (d == hoy && manualDiv <= 0) ? divisaSugeridaHoy : 0.0;
    return TasaDiaResuelta(
      dia: d,
      bcv: bcv,
      fuenteBcv: fuente,
      divisa: manualDiv > 0 ? manualDiv : sugerida,
      divisaConfirmada: manualDiv > 0,
    );
  }

  /// Todos los días entre [desde] y [hasta] (sin pasar de hoy).
  List<TasaDiaResuelta> dias(DateTime desde, DateTime hasta) {
    final r = <TasaDiaResuelta>[];
    var d = soloDia(desde);
    final fin = soloDia(hasta).isAfter(hoy) ? hoy : soloDia(hasta);
    while (!d.isAfter(fin)) {
      r.add(resolver(d));
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return r;
  }
}

/// BCV de cada día deducida de las ventas: la MAYOR tasa con que se
/// cobró ese día. Un equipo que no actualizó la tasa cobra con la del
/// día anterior (más baja); la mayor es la publicada para ese día.
Map<String, double> bcvDeLasVentas(Iterable<FacturaCF> facturas) {
  final r = <String, double>{};
  for (final f in facturas) {
    final iso = fechaIsoCF(f.fecha);
    for (final p in f.pagos) {
      if (p.tasa <= 0) continue;
      if (p.tasa > (r[iso] ?? 0)) r[iso] = p.tasa;
    }
  }
  return r;
}

/// Precio de un producto en la lista de una financiadora.
///
/// [listas]: nombre de la lista → (financiadora de la lista, mapa
/// código → primer precio). Orden de búsqueda:
///   1. la lista con el nombre exacto usado al facturar ([nombreLista]);
///   2. una lista que se llame igual que la financiadora ("KRECE");
///   3. una lista marcada con esa financiadora;
///   4. una lista cuyo nombre contenga la financiadora ("CASHEA TELÉFONOS").
/// null si ninguna tiene el producto.
double? precioEnListaFinanciadora(
  List<({String nombre, String financiadora, Map<String, double> precios})>
      listas,
  String financiadora,
  String codigo, {
  String? nombreLista,
}) {
  String norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final fin = norm(financiadora);
  final cod = codigo.trim().toLowerCase();
  if (fin.isEmpty || cod.isEmpty) return null;
  double? buscar(bool Function(String nombre, String fin) cond) {
    for (final l in listas) {
      if (!cond(norm(l.nombre), norm(l.financiadora))) continue;
      for (final e in l.precios.entries) {
        if (e.key.trim().toLowerCase() == cod) return e.value;
      }
    }
    return null;
  }

  final nl = norm(nombreLista ?? '');
  return (nl.isNotEmpty ? buscar((n, _) => n == nl) : null) ??
      buscar((n, _) => n == fin) ??
      buscar((_, f) => f.isNotEmpty && (f.contains(fin) || fin.contains(f))) ??
      buscar((n, _) => n.contains(fin));
}

// ════════════════════════════════════════════════════════════════════
//  2. GASTOS
// ════════════════════════════════════════════════════════════════════

/// Clasificación de gastos (las mismas secciones de la hoja de costos).
const List<String> categoriasGastoCF = [
  'Administrativo',
  'Gastos fijos',
  'Operación',
  'Inversión',
  'Otros',
];

/// Un gasto registrado. Se guarda como JSON en `configuracion`
/// (clave `cf_gastos_AAAA_MM`), así que no requiere tabla nueva.
/// tienda vacía = gasto general de la empresa (no de una tienda).
class GastoCF {
  final String id;
  DateTime fecha;
  String tienda;
  String categoria;
  String concepto;
  double monto;
  String moneda;
  /// Tasa Bs/$ del día en que se registró (para convertir a $).
  double tasa;
  final String registradoPor;
  final String registradoEn;

  GastoCF({
    required this.id,
    required this.fecha,
    this.tienda = '',
    this.categoria = 'Otros',
    this.concepto = '',
    this.monto = 0,
    this.moneda = monedaUsd,
    this.tasa = 0,
    this.registradoPor = '',
    this.registradoEn = '',
  });

  double get montoUsd =>
      moneda == monedaBs ? (tasa > 0 ? monto / tasa : 0) : monto;

  factory GastoCF.fromJson(Map m) => GastoCF(
        id: (m['id'] ?? '').toString(),
        fecha: parseFechaCF(m['f']?.toString()) ?? DateTime(2000),
        tienda: (m['t'] ?? '').toString(),
        categoria: (m['c'] ?? 'Otros').toString(),
        concepto: (m['d'] ?? '').toString(),
        monto: _num(m['m']),
        moneda: (m['mo'] ?? monedaUsd).toString(),
        tasa: _num(m['ta']),
        registradoPor: (m['rp'] ?? '').toString(),
        registradoEn: (m['re'] ?? '').toString(),
      );

  // Claves cortas: todo el mes viaja en un solo valor de `configuracion`.
  Map<String, dynamic> toJson() => {
        'id': id,
        'f': fechaIsoCF(fecha),
        't': tienda,
        'c': categoria,
        'd': concepto,
        'm': monto,
        'mo': moneda,
        'ta': tasa,
        'rp': registradoPor,
        're': registradoEn,
      };
}

/// Clave de `configuracion` donde vive un mes de gastos.
String claveGastosMes(int anio, int mes) =>
    'cf_gastos_${anio}_${mes.toString().padLeft(2, '0')}';

/// Total en $ por categoría.
Map<String, double> gastosPorCategoria(Iterable<GastoCF> gastos) {
  final r = <String, double>{for (final c in categoriasGastoCF) c: 0};
  for (final g in gastos) {
    final c = categoriasGastoCF.contains(g.categoria) ? g.categoria : 'Otros';
    r[c] = (r[c] ?? 0) + g.montoUsd;
  }
  return r;
}

// ════════════════════════════════════════════════════════════════════
//  3. EQUILIBRIO DIARIO POR TIENDA
// ════════════════════════════════════════════════════════════════════

class DiaEquilibrio {
  final DateTime dia;
  double ventas = 0;
  double ganancia = 0;
  double gastos = 0;
  /// Ganancia del día − gastos del día ("quedamos en 150").
  double get resultado => ganancia - gastos;
  /// Resultado acumulado desde el primer día del período.
  double acumulado = 0;
  DiaEquilibrio(this.dia);
}

class EquilibrioTienda {
  final String tienda;
  final List<DiaEquilibrio> dias;
  final double totalVentas;
  final double totalGanancia;
  final double totalGastos;
  /// Primer día en que la ganancia acumulada cubre TODOS los gastos del
  /// período (null si todavía no los cubre).
  final DateTime? diaCubreGastos;
  const EquilibrioTienda({
    required this.tienda,
    required this.dias,
    required this.totalVentas,
    required this.totalGanancia,
    required this.totalGastos,
    required this.diaCubreGastos,
  });
  double get resultado => totalGanancia - totalGastos;
  bool get enPositivo => resultado >= 0;
  /// Cuánto falta ganar para cubrir los gastos (0 si ya está cubierto).
  double get faltante => resultado >= 0 ? 0 : -resultado;
}

/// Agrupa por día ventas y gastos de UNA tienda y calcula el
/// acumulado. Solo aparecen los días con movimiento.
EquilibrioTienda calcularEquilibrio({
  required String tienda,
  required Iterable<VentaAnalizada> ventas,
  required Iterable<GastoCF> gastos,
}) {
  final dias = <DateTime, DiaEquilibrio>{};
  DiaEquilibrio d(DateTime f) =>
      dias.putIfAbsent(soloDia(f), () => DiaEquilibrio(soloDia(f)));
  double tv = 0, tg = 0, tgs = 0;
  for (final v in ventas) {
    final x = d(v.fecha);
    x.ventas += v.ingresoEnDivisa;
    x.ganancia += v.gananciaTotal;
    tv += v.ingresoEnDivisa;
    tg += v.gananciaTotal;
  }
  for (final g in gastos) {
    d(g.fecha).gastos += g.montoUsd;
    tgs += g.montoUsd;
  }
  final lista = dias.values.toList()..sort((a, b) => a.dia.compareTo(b.dia));
  double acum = 0, gananciaAcum = 0;
  DateTime? cubre;
  for (final x in lista) {
    acum += x.resultado;
    x.acumulado = acum;
    gananciaAcum += x.ganancia;
    if (cubre == null && tgs > 0 && gananciaAcum >= tgs - 0.005) cubre = x.dia;
  }
  if (tgs <= 0 && lista.isNotEmpty && tg > 0) cubre = lista.first.dia;
  return EquilibrioTienda(
    tienda: tienda,
    dias: lista,
    totalVentas: tv,
    totalGanancia: tg,
    totalGastos: tgs,
    diaCubreGastos: cubre,
  );
}

// ════════════════════════════════════════════════════════════════════
//  4. FLUJO DE CAJA
// ════════════════════════════════════════════════════════════════════

/// Una entrada o salida de dinero. [tienda] vacía = general.
class MovimientoCaja {
  final DateTime fecha;
  final String tienda;
  final String concepto;
  final bool entrada;
  final String moneda;
  final double monto;
  const MovimientoCaja({
    required this.fecha,
    required this.tienda,
    required this.concepto,
    required this.entrada,
    required this.moneda,
    required this.monto,
  });
}

/// Totales de caja separados por moneda.
class TotalesCaja {
  double entradasUsd = 0, entradasBs = 0, salidasUsd = 0, salidasBs = 0;
  /// concepto → (entradas/salidas) por moneda.
  final Map<String, TotalesCaja> porConcepto = {};
  final bool _conDetalle;
  TotalesCaja({bool conDetalle = true}) : _conDetalle = conDetalle;

  double get netoUsd => entradasUsd - salidasUsd;
  double get netoBs => entradasBs - salidasBs;

  void sumar(MovimientoCaja m) {
    _aplicar(m);
    if (!_conDetalle) return;
    porConcepto
        .putIfAbsent(m.concepto, () => TotalesCaja(conDetalle: false))
        ._aplicar(m);
  }

  void _aplicar(MovimientoCaja m) {
    final bs = m.moneda == monedaBs;
    if (m.entrada) {
      if (bs) {
        entradasBs += m.monto;
      } else {
        entradasUsd += m.monto;
      }
    } else {
      if (bs) {
        salidasBs += m.monto;
      } else {
        salidasUsd += m.monto;
      }
    }
  }

  /// Neto convertido a $ con una tasa (solo para mostrar como
  /// referencia, siempre al lado de los montos separados).
  double netoEquivUsd(double tasa) =>
      netoUsd + (tasa > 0 ? netoBs / tasa : 0);
}

/// Flujo de caja por tienda + consolidado ('' en el mapa = general).
({Map<String, TotalesCaja> porTienda, TotalesCaja consolidado}) calcularFlujoCaja(
    Iterable<MovimientoCaja> movimientos) {
  final porTienda = <String, TotalesCaja>{};
  final total = TotalesCaja();
  for (final m in movimientos) {
    if (m.monto == 0) continue;
    porTienda.putIfAbsent(m.tienda, () => TotalesCaja()).sumar(m);
    total.sumar(m);
  }
  return (porTienda: porTienda, consolidado: total);
}

// ════════════════════════════════════════════════════════════════════
//  5. NÓMINA
// ════════════════════════════════════════════════════════════════════

/// Empleado de nómina. Normalmente es un usuario del sistema
/// ([usuarioId] no nulo); también puede ser alguien sin usuario.
class EmpleadoNomina {
  int? usuarioId;
  String nombre;
  String cargo;
  String tienda;
  double sueldo;
  String moneda;
  bool activo;
  EmpleadoNomina({
    this.usuarioId,
    required this.nombre,
    this.cargo = '',
    this.tienda = '',
    this.sueldo = 0,
    this.moneda = monedaUsd,
    this.activo = true,
  });

  factory EmpleadoNomina.fromJson(Map m) => EmpleadoNomina(
        usuarioId: int.tryParse(m['u']?.toString() ?? ''),
        nombre: (m['n'] ?? '').toString(),
        cargo: (m['c'] ?? '').toString(),
        tienda: (m['t'] ?? '').toString(),
        sueldo: _num(m['s']),
        moneda: (m['mo'] ?? monedaUsd).toString(),
        activo: m['a'] != false && m['a']?.toString() != '0',
      );

  Map<String, dynamic> toJson() => {
        if (usuarioId != null) 'u': usuarioId,
        'n': nombre,
        'c': cargo,
        't': tienda,
        's': sueldo,
        'mo': moneda,
        'a': activo,
      };

  /// Misma persona: mismo usuario o, sin usuario, mismo nombre.
  bool esMismo({int? usuarioId, required String nombre}) {
    if (this.usuarioId != null && usuarioId != null) {
      return this.usuarioId == usuarioId;
    }
    return this.nombre.trim().toLowerCase() == nombre.trim().toLowerCase();
  }
}

/// Agrega a [empleados] los usuarios del sistema que todavía no están
/// (antes en nómina solo salían los vendedores con ventas en el mes).
/// Devuelve cuántos se agregaron. No modifica a los que ya estaban.
int agregarUsuariosANomina(
  List<EmpleadoNomina> empleados,
  Iterable<({int? id, String nombre, String rol, String tienda, double sueldo})>
      usuarios,
) {
  var n = 0;
  for (final u in usuarios) {
    if (u.nombre.trim().isEmpty) continue;
    if (empleados.any((e) => e.esMismo(usuarioId: u.id, nombre: u.nombre))) {
      continue;
    }
    empleados.add(EmpleadoNomina(
      usuarioId: u.id,
      nombre: u.nombre.trim(),
      cargo: u.rol,
      tienda: u.tienda,
      sueldo: u.sueldo,
    ));
    n++;
  }
  return n;
}

const List<String> conceptosPagoNomina = [
  'Sueldo',
  'Quincena',
  'Comisión',
  'Bono',
  'Adelanto',
  'Otro',
];

/// Un pago de nómina: A QUIÉN se le pagó y QUIÉN lo registró y cuándo.
class PagoNomina {
  final String id;
  final String empleado;
  final int? usuarioId;
  final String tienda;
  final String concepto;
  final double monto;
  final String moneda;
  final double tasa;
  final String metodo;
  final DateTime fechaPago;
  final String registradoPor;
  final DateTime registradoEn;
  final String notas;
  const PagoNomina({
    required this.id,
    required this.empleado,
    this.usuarioId,
    this.tienda = '',
    this.concepto = 'Sueldo',
    required this.monto,
    this.moneda = monedaUsd,
    this.tasa = 0,
    this.metodo = '',
    required this.fechaPago,
    required this.registradoPor,
    required this.registradoEn,
    this.notas = '',
  });

  double get montoUsd =>
      moneda == monedaBs ? (tasa > 0 ? monto / tasa : 0) : monto;

  factory PagoNomina.fromJson(Map m) => PagoNomina(
        id: (m['id'] ?? '').toString(),
        empleado: (m['e'] ?? '').toString(),
        usuarioId: int.tryParse(m['u']?.toString() ?? ''),
        tienda: (m['t'] ?? '').toString(),
        concepto: (m['c'] ?? 'Sueldo').toString(),
        monto: _num(m['m']),
        moneda: (m['mo'] ?? monedaUsd).toString(),
        tasa: _num(m['ta']),
        metodo: (m['me'] ?? '').toString(),
        fechaPago: parseFechaCF(m['f']?.toString()) ?? DateTime(2000),
        registradoPor: (m['rp'] ?? '').toString(),
        registradoEn:
            DateTime.tryParse(m['re']?.toString() ?? '') ?? DateTime(2000),
        notas: (m['no'] ?? '').toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'e': empleado,
        if (usuarioId != null) 'u': usuarioId,
        't': tienda,
        'c': concepto,
        'm': monto,
        'mo': moneda,
        'ta': tasa,
        'me': metodo,
        'f': fechaIsoCF(fechaPago),
        'rp': registradoPor,
        're': registradoEn.toIso8601String(),
        if (notas.isNotEmpty) 'no': notas,
      };
}

String claveNominaPagosMes(int anio, int mes) =>
    'cf_nomina_pagos_${anio}_${mes.toString().padLeft(2, '0')}';

const String claveNominaEmpleados = 'cf_nomina_empleados';

/// Total pagado a cada empleado (en $), para el resumen de nómina.
Map<String, double> totalPagadoPorEmpleado(Iterable<PagoNomina> pagos) {
  final r = <String, double>{};
  for (final p in pagos) {
    r[p.empleado] = (r[p.empleado] ?? 0) + p.montoUsd;
  }
  return r;
}
