// ════════════════════════════════════════════════════════════════════
//  CUENTA CON LA FINANCIADORA — ARITMÉTICA POR EQUIPO
// ════════════════════════════════════════════════════════════════════
//  Lógica pura (sin UI ni backend) del Reporte por Financiadora, para
//  poder probarla con tests unitarios.
//
//  ¿Por qué existe? El dueño reportó que el sistema "no llevaba bien la
//  cuenta" de lo que cada financiadora (Cashea / Weppa / Krece) le debe
//  a la tienda. La causa: los pagos de la financiadora se restaban según
//  la FECHA DEL PAGO, mientras que la deuda se armaba con las ventas cuya
//  FECHA DE VENTA caía en el rango. Si Cashea pagaba en octubre un equipo
//  vendido en septiembre:
//    · en septiembre el equipo seguía figurando como pendiente completo,
//    · en octubre ese pago se restaba de equipos que NO le correspondían
//      (o aparecía como "sobrepago").
//  Además el abono quedaba atado solo a la factura (nunca al equipo) y
//  la comisión/inicial se calculaba sobre el agregado, así que una
//  factura con inicial mayor a la base "regalaba" saldo negativo a las
//  demás.
//
//  Ahora:
//    1. Cada EQUIPO tiene su propia deuda: su base, su parte de la
//       inicial (proporcional a su base dentro de la factura), su
//       comisión y su deuda neta.
//    2. Cada pago se aplica al equipo (o a la factura) al que fue
//       registrado, SIN IMPORTAR la fecha del pago.
//    3. Solo los pagos viejos sin vínculo (registrados antes de este
//       cambio y sin número de factura) siguen usando la fecha del pago.
//    4. Todo se redondea a centavos para que las sumas cuadren.
// ════════════════════════════════════════════════════════════════════

/// Redondea a centavos (evita residuos tipo 0,0000001 en los saldos).
double redondearCentavos(double v) => (v * 100).roundToDouble() / 100;

/// Resultado del cálculo de comisión de una financiadora.
class ComisionFinanciadora {
  final double comision;
  final double porcentaje;
  final String formula;
  const ComisionFinanciadora(this.comision, this.porcentaje, this.formula);
}

/// Comisión que la financiadora le descuenta a la tienda sobre un monto.
///
///   · KRECE:  sin comisión.
///   · WEPPA:  3.5% del monto financiado (Base − Inicial).
///   · CASHEA: Base × 4% + IVA 16% (= Base × 4.64%) + 4% del financiado.
///   · Otra:   3.5% del financiado (criterio conservador anterior).
///
/// Todas son LINEALES, así que la suma por equipo da lo mismo que el
/// cálculo sobre el total (cuando ningún equipo queda con neto negativo).
ComisionFinanciadora calcularComisionFinanciadora(
    String financiadora, double base, double inicial) {
  final f = financiadora.toLowerCase();
  final neto = (base - inicial).clamp(0.0, double.infinity).toDouble();
  if (f.contains('krece')) {
    return const ComisionFinanciadora(0, 0, 'Sin comisión');
  }
  if (f.contains('weppa')) {
    return ComisionFinanciadora(neto * 0.035, 3.5, '3.5% del monto financiado');
  }
  if (f.contains('cashea')) {
    final comision1 = base * 0.04 * 1.16; // 4% base + IVA
    final comision2 = neto * 0.04;        // 4% del financiado
    final total = comision1 + comision2;
    return ComisionFinanciadora(total, base > 0 ? total / base * 100 : 0,
        '4% base + IVA + 4% del financiado');
  }
  return ComisionFinanciadora(neto * 0.035, 3.5, '3.5% (default)');
}

/// Un equipo (o ítem sin IMEI) vendido con una financiadora, con su
/// propia cuenta: cuánto debe la financiadora por él, cuánto abonó y
/// cuánto falta.
class EquipoFinanciado {
  final String financiadora;
  final String nroFactura;
  final String imei;
  final String codigo;
  final String marca;
  final String modelo;
  final String nombre;
  final String cliente;
  final String fecha;
  /// Nombre de la lista de precios aplicada (normal vs promoción).
  final String listaUsada;
  /// Precio de venta del catálogo (solo informativo).
  final double precioVenta;
  /// Precio según la lista de la financiadora (la "Base").
  final double base;
  /// Parte de la inicial de la factura que le toca a este equipo.
  double inicial = 0;
  double comision = 0;
  /// Lo que la financiadora debe por este equipo (neto − comisión).
  double deuda = 0;
  /// Lo que la financiadora ya pagó por este equipo.
  double abonado = 0;

  EquipoFinanciado({
    required this.financiadora,
    required this.nroFactura,
    required this.base,
    this.imei = '',
    this.codigo = '',
    this.marca = '',
    this.modelo = '',
    this.nombre = '',
    this.cliente = '',
    this.fecha = '',
    this.listaUsada = '',
    this.precioVenta = 0,
  });

  /// Saldo pendiente. Negativo = la financiadora pagó de más.
  double get saldo => redondearCentavos(deuda - abonado);

  /// Descripción legible: "Marca Modelo" o el nombre del producto.
  String get descripcion {
    final mm = '$marca $modelo'.trim();
    return mm.isNotEmpty ? mm : (nombre.isNotEmpty ? nombre : codigo);
  }

  /// Clave única del equipo dentro del reporte.
  String get clave => '$nroFactura|${imei.isNotEmpty ? imei : codigo}';
}

/// Reparte la inicial de UNA factura entre sus equipos (proporcional a
/// la base de cada uno) y calcula comisión y deuda POR EQUIPO.
///
/// [inicialFactura] debe venir ya convertida a USD.
void calcularDeudaFactura(
    List<EquipoFinanciado> equiposFactura, double inicialFactura) {
  if (equiposFactura.isEmpty) return;
  final totalBase =
      equiposFactura.fold<double>(0, (s, e) => s + e.base);
  double repartido = 0;
  for (var i = 0; i < equiposFactura.length; i++) {
    final e = equiposFactura[i];
    double parte;
    if (i == equiposFactura.length - 1) {
      // El último se lleva el resto para que la suma cuadre al centavo.
      parte = inicialFactura - repartido;
    } else if (totalBase > 0) {
      parte = redondearCentavos(inicialFactura * e.base / totalBase);
    } else {
      parte = redondearCentavos(inicialFactura / equiposFactura.length);
    }
    repartido += parte;
    e.inicial = redondearCentavos(parte);
    final com = calcularComisionFinanciadora(e.financiadora, e.base, e.inicial);
    e.comision = redondearCentavos(com.comision);
    final neto = (e.base - e.inicial).clamp(0.0, double.infinity).toDouble();
    e.deuda = redondearCentavos(
        (neto - e.comision).clamp(0.0, double.infinity).toDouble());
  }
}

/// Pago que una financiadora le hizo a la tienda.
class PagoFinanciadora {
  final String financiadora;
  final double monto;
  final DateTime? fecha;
  /// Factura a la que se aplicó (vacío = pago viejo sin vincular).
  final String nroFactura;
  /// IMEI (o código) del equipo al que se aplicó. Vacío = a la factura.
  final String imei;

  const PagoFinanciadora({
    required this.financiadora,
    required this.monto,
    this.fecha,
    this.nroFactura = '',
    this.imei = '',
  });

  bool get vinculado => nroFactura.trim().isNotEmpty;
}

// ── Marca del equipo en las notas del pago ───────────────────
// El backend de `pagos_financiadora` no tiene columna para el IMEI y no
// sabemos si devuelve `nro_factura`, así que el vínculo se anota también
// en `notas` con la marca `[[fin_eq:NRO|IMEI]]` (misma idea que
// `[[favor:N]]` en las cuentas por pagar). La interfaz nunca la muestra.
final RegExp _reEquipoPago = RegExp(r'\[\[fin_eq:([^|\]]*)\|([^\]]*)\]\]');

/// Agrega (o reemplaza) la marca de equipo en las notas de un pago.
String escribirMarcaEquipoPago(String notas, String nroFactura, String imei) {
  final limpio = notas.replaceAll(_reEquipoPago, '').trim();
  final marca = '[[fin_eq:${nroFactura.trim()}|${imei.trim()}]]';
  return limpio.isEmpty ? marca : '$limpio\n$marca';
}

/// Lee la marca `[[fin_eq:NRO|IMEI]]`. Devuelve null si no hay.
({String nroFactura, String imei})? leerMarcaEquipoPago(String notas) {
  final m = _reEquipoPago.firstMatch(notas);
  if (m == null) return null;
  return (nroFactura: (m.group(1) ?? '').trim(), imei: (m.group(2) ?? '').trim());
}

/// Notas del pago sin la marca interna.
String notasPagoVisibles(String notas) =>
    notas.replaceAll(_reEquipoPago, '').trim();

/// Aplica los pagos VINCULADOS a sus equipos (sin importar la fecha del
/// pago). Devuelve los pagos que no se pudieron vincular a ningún equipo
/// de [equipos] (pagos viejos sin factura, o de facturas fuera del
/// rango), para que el llamador decida qué hacer con ellos.
///
/// Reglas:
///   · Pago con IMEI → se suma completo a ese equipo.
///   · Pago solo con factura → llena el saldo de los equipos de esa
///     factura en orden; lo que sobre va al último (queda sobrepago).
List<PagoFinanciadora> aplicarPagosAEquipos(
    List<EquipoFinanciado> equipos, List<PagoFinanciadora> pagos) {
  final sinAplicar = <PagoFinanciadora>[];
  for (final p in pagos) {
    if (!p.vinculado) { sinAplicar.add(p); continue; }
    final fin = p.financiadora.toLowerCase().trim();
    final deFactura = equipos.where((e) =>
        e.nroFactura.trim() == p.nroFactura.trim() &&
        (fin.isEmpty || e.financiadora.toLowerCase().trim() == fin)).toList();
    if (deFactura.isEmpty) { sinAplicar.add(p); continue; }

    if (p.imei.isNotEmpty) {
      final eq = deFactura.where((e) => e.imei == p.imei || e.codigo == p.imei);
      if (eq.isNotEmpty) {
        eq.first.abonado = redondearCentavos(eq.first.abonado + p.monto);
        continue;
      }
      // IMEI no encontrado (equipo cambiado en la factura): cae al
      // reparto por factura en vez de perderse.
    }

    double resto = p.monto;
    for (var i = 0; i < deFactura.length && resto > 0.0001; i++) {
      final e = deFactura[i];
      final esUltimo = i == deFactura.length - 1;
      final aplicar = esUltimo
          ? resto
          : (e.saldo > 0 ? (resto < e.saldo ? resto : e.saldo) : 0.0);
      if (aplicar <= 0) continue;
      e.abonado = redondearCentavos(e.abonado + aplicar);
      resto = redondearCentavos(resto - aplicar);
    }
  }
  return sinAplicar;
}
