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
//      Cómo lo calcula el dueño con Krece:
//        iniciales del día convertidas a divisa
//      + lo que debe la financiadora convertido a divisa (paga en Bs a
//        tasa BCV: "me pagaron $1000, convertido son 850")
//      − valor de contado de los equipos
//      = margen por diferencial cambiario.
//
//   2. BALANCE NETO POR TIENDA
//        ventas cobradas en divisa + montos financiados
//      − costo de los equipos − gastos de la tienda.
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

/// Un equipo o artículo vendido, con los precios del catálogo.
class EquipoVendidoCF {
  final String codigo;
  final String imei;
  /// Costo del producto (precio de costo del catálogo).
  final double costo;
  /// Precio de contado / divisa (precio de venta del catálogo).
  final double precioContado;
  /// Precio en la lista de la financiadora (la "Base" sobre la que la
  /// financiadora le paga a la tienda). null = venta de contado o sin
  /// lista: se usa el de contado.
  final double? precioFinanciadora;
  const EquipoVendidoCF({
    this.codigo = '',
    this.imei = '',
    required this.costo,
    required this.precioContado,
    this.precioFinanciadora,
  });
}

/// Un pago que hizo el CLIENTE en la factura.
class PagoClienteCF {
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

/// Tasas con que se convierte todo a divisa.
///   · [tasaBcv]: la tasa oficial a la que la financiadora paga en Bs.
///   · [tasaDivisa]: la tasa a la que el dueño convierte los Bs a
///     dólares reales (Binance). Si es 0 se usa la del pago (BCV).
class TasasCF {
  final double tasaBcv;
  final double tasaDivisa;
  const TasasCF({required this.tasaBcv, required this.tasaDivisa});

  /// Cuántos dólares reales vale 1 dólar BCV: "me pagaron $1000,
  /// convertido son 850" → 0,85. 1 si falta alguna tasa.
  double get factorBcvADivisa =>
      (tasaBcv > 0 && tasaDivisa > 0) ? tasaBcv / tasaDivisa : 1.0;

  /// Bs → divisa. Usa la tasa divisa; si no hay, la del pago.
  double bsADivisa(double bs, {double tasaPago = 0}) {
    if (tasaDivisa > 0) return bs / tasaDivisa;
    if (tasaPago > 0) return bs / tasaPago;
    if (tasaBcv > 0) return bs / tasaBcv;
    return 0;
  }
}

/// Resultado de analizar una factura.
class VentaAnalizada {
  final String nroFactura;
  final String tienda;
  final DateTime fecha;
  final String financiadora;
  final int unidades;
  /// Σ costo de los equipos.
  final double costo;
  /// Σ precio de contado de los equipos.
  final double valorContado;
  /// Pagos del cliente en $ (sin convertir).
  final double cobradoUsd;
  /// Pagos del cliente en Bs (sin convertir).
  final double cobradoBs;
  /// Pagos del cliente convertidos a divisa.
  final double cobradoEnDivisa;
  /// Lo que debe la financiadora en $ BCV (base − inicial − comisión).
  final double financiadoBcv;
  /// Lo que debe la financiadora convertido a divisa.
  final double financiadoEnDivisa;

  const VentaAnalizada({
    required this.nroFactura,
    required this.tienda,
    required this.fecha,
    required this.financiadora,
    required this.unidades,
    required this.costo,
    required this.valorContado,
    required this.cobradoUsd,
    required this.cobradoBs,
    required this.cobradoEnDivisa,
    required this.financiadoBcv,
    required this.financiadoEnDivisa,
  });

  bool get esFinanciada => financiadora.isNotEmpty;

  /// Todo lo que entra por la venta, en dólares reales.
  double get ingresoEnDivisa => cobradoEnDivisa + financiadoEnDivisa;

  /// Ganancia REAL: como si se hubiera vendido de contado.
  double get gananciaReal => valorContado - costo;

  /// Lo que sobra (o falta) por financiamiento y tasa.
  double get diferencialCambiario => ingresoEnDivisa - valorContado;

  /// Ganancia total = real + diferencial = ingreso real − costo.
  double get gananciaTotal => ingresoEnDivisa - costo;
}

/// Analiza una factura: separa ganancia real y diferencial cambiario.
///
/// La deuda de la financiadora se calcula igual que en el Reporte por
/// Financiadora (`calcularDeudaFactura`): base de su lista − inicial del
/// cliente (en $ BCV) − comisión de la financiadora.
VentaAnalizada analizarFactura(FacturaCF f, TasasCF tasas) {
  double costo = 0, contado = 0, cobUsd = 0, cobBs = 0, cobDiv = 0;
  for (final e in f.equipos) {
    costo += e.costo;
    contado += e.precioContado;
  }
  for (final p in f.pagos) {
    if (p.enBolivares) {
      cobBs += p.monto;
      cobDiv += tasas.bsADivisa(p.monto, tasaPago: p.tasa);
    } else {
      cobUsd += p.monto;
      cobDiv += p.monto;
    }
  }

  double financiadoBcv = 0;
  final fin = f.financiadora;
  if (fin.isNotEmpty && f.equipos.isNotEmpty) {
    // Inicial en $ BCV (tasa histórica de cada pago), como la cuenta
    // con la financiadora: si hay pagos marcados como inicial, solo
    // esos; si no, todos los pagos del cliente son la inicial.
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
    final cuentas = [
      for (final e in f.equipos)
        EquipoFinanciado(
          financiadora: fin,
          nroFactura: f.nroFactura,
          base: e.precioFinanciadora ?? e.precioContado,
          imei: e.imei,
          codigo: e.codigo,
        ),
    ];
    calcularDeudaFactura(cuentas, redondearCentavos(inicial));
    financiadoBcv = cuentas.fold<double>(0, (s, c) => s + c.deuda);
  }

  return VentaAnalizada(
    nroFactura: f.nroFactura,
    tienda: f.tienda,
    fecha: f.fecha,
    financiadora: fin,
    unidades: f.equipos.length,
    costo: costo,
    valorContado: contado,
    cobradoUsd: cobUsd,
    cobradoBs: cobBs,
    cobradoEnDivisa: cobDiv,
    financiadoBcv: financiadoBcv,
    financiadoEnDivisa: financiadoBcv * tasas.factorBcvADivisa,
  );
}

/// Totales de un grupo de ventas (una tienda, una financiadora, todo).
class ResumenGanancia {
  int facturas = 0;
  int unidades = 0;
  double costo = 0;
  double valorContado = 0;
  double cobradoUsd = 0;
  double cobradoBs = 0;
  double cobradoEnDivisa = 0;
  double financiadoBcv = 0;
  double financiadoEnDivisa = 0;

  void sumar(VentaAnalizada v) {
    facturas++;
    unidades += v.unidades;
    costo += v.costo;
    valorContado += v.valorContado;
    cobradoUsd += v.cobradoUsd;
    cobradoBs += v.cobradoBs;
    cobradoEnDivisa += v.cobradoEnDivisa;
    financiadoBcv += v.financiadoBcv;
    financiadoEnDivisa += v.financiadoEnDivisa;
  }

  double get ingresoEnDivisa => cobradoEnDivisa + financiadoEnDivisa;
  double get gananciaReal => valorContado - costo;
  double get diferencialCambiario => ingresoEnDivisa - valorContado;
  double get gananciaTotal => ingresoEnDivisa - costo;

  /// Balance neto del dueño: ventas en divisa + montos financiados −
  /// costo de los equipos − gastos.
  double balanceNeto(double gastosUsd) =>
      balanceNetoTienda(
        ventasDivisa: cobradoEnDivisa,
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

/// Agrupa ventas por una clave (tienda, financiadora…).
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
