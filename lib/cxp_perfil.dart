// ════════════════════════════════════════════════════════════════════
//  cxp_perfil.dart — Lógica pura del "perfil por acreedor" de las
//  cuentas por pagar (proveedores y personas).
// ════════════════════════════════════════════════════════════════════
//  Antes cada cuenta era una tarjeta suelta: si al proveedor "Maxi" se
//  le abría una cuenta nueva por otra factura, aparecía dos veces y el
//  saldo a favor de una no se veía junto a la deuda de la otra. Ahora
//  la pantalla agrupa todas las cuentas de un mismo acreedor (por
//  nombre normalizado) en un único perfil con su historial de
//  facturas y de pagos.
//
//  Este archivo no depende de Flutter ni de main.dart para poder
//  probarlo con `flutter test` sin levantar la app. La interfaz está en
//  `cxp_perfil_ui.dart`.
// ════════════════════════════════════════════════════════════════════

/// Clave con la que se agrupan las cuentas de un mismo acreedor:
/// minúsculas, sin acentos, sin signos y con los espacios colapsados.
/// Así "Maxi 2005", "MAXI 2005 " y "Maxí-2005" caen en el mismo perfil.
String normalizarNombreAcreedor(String nombre) {
  const conAcento = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const sinAcento = 'aaaaaeeeeiiiiooooouuuunc';
  final buf = StringBuffer();
  for (final ch in nombre.toLowerCase().split('')) {
    final i = conAcento.indexOf(ch);
    buf.write(i >= 0 ? sinAcento[i] : ch);
  }
  return buf
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}

/// Convierte "dd/mm/aaaa" (formato que usa toda la app) en fecha.
/// Devuelve null si el texto no tiene ese formato.
DateTime? parsearFechaDMY(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^\s*(\d{1,2})/(\d{1,2})/(\d{4})').firstMatch(s);
  if (m != null) {
    return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!),
        int.parse(m.group(1)!));
  }
  // Por si el backend devuelve una fecha ISO (aaaa-mm-dd).
  return DateTime.tryParse(s.trim());
}

// ── Marcas de adjunto ─────────────────────────────────────────────
//  Los adjuntos (foto o PDF) viven en la tabla `comprobantes`. Para
//  saber a QUÉ factura o a QUÉ pago pertenece cada uno, el id del
//  comprobante se anota con la marca `[[comp:N]]`:
//    • en la línea de bitácora de la factura (dentro de `notas` de la
//      cuenta), y
//    • en el campo `notas` del pago.
//  No se usa el id del pago porque el backend borra y vuelve a insertar
//  todos los pagos en cada PUT: el id cambia y el vínculo se perdería.
//  Las marcas nunca se muestran (ver `quitarMarcasComprobante`).
final RegExp reMarcaComprobante = RegExp(r'\s*\[\[comp:(\d+)\]\]');

/// Ids de comprobante anotados en el texto.
List<int> leerMarcasComprobante(String? texto) {
  if (texto == null || texto.isEmpty) return const [];
  return reMarcaComprobante
      .allMatches(texto)
      .map((m) => int.parse(m.group(1)!))
      .toList();
}

/// Agrega la marca del comprobante [id] al final del texto.
String agregarMarcaComprobante(String? texto, int id) {
  final t = (texto ?? '').trimRight();
  final marca = '[[comp:$id]]';
  return t.isEmpty ? marca : '$t $marca';
}

String quitarMarcasComprobante(String texto) =>
    texto.replaceAll(reMarcaComprobante, '').trim();

// ── Facturas ──────────────────────────────────────────────────────

/// Una factura del acreedor: la que abrió la cuenta, o cada una de las
/// que se le fueron sumando con "Agregar deuda".
class FacturaAcreedor {
  final int cuentaId;
  final String fecha;
  final double monto;
  final String concepto;
  /// Cuánto de esta factura se cubrió con saldo a favor al cargarla.
  final double aplicadoDeFavor;
  /// true = monto con el que se abrió la cuenta (no sale de la bitácora).
  final bool esOriginal;
  /// Índice de la línea dentro de `notas` (null para la original).
  final int? lineaNotas;
  /// Ids de comprobantes anotados en la línea.
  final List<int> comprobantes;

  const FacturaAcreedor({
    required this.cuentaId,
    required this.fecha,
    required this.monto,
    required this.concepto,
    this.aplicadoDeFavor = 0,
    this.esOriginal = false,
    this.lineaNotas,
    this.comprobantes = const [],
  });
}

// Línea que escribe `lineaNotaAumento()` en main.dart:
//   [03/09/2026] +$3,450.00 — mercancía (aplicado $493.75 de saldo a favor)
final RegExp _reLineaAumento =
    RegExp(r'^\s*\[([^\[\]]+)\]\s*\+\s*\$?\s*([0-9][0-9,]*(?:\.[0-9]+)?)(.*)$');
final RegExp _reAplicado =
    RegExp(r'\(aplicado\s*\$?\s*([0-9][0-9,]*(?:\.[0-9]+)?)\s*de saldo a favor\)');
final RegExp _reMarcaFavor = RegExp(r'\[\[favor:[0-9.]+\]\]');

double _numero(String s) => double.tryParse(s.replaceAll(',', '')) ?? 0;

/// Reconstruye las facturas de UNA cuenta a partir de su monto total y
/// de la bitácora que queda en `notas` cada vez que se agrega deuda.
///
/// La factura original es lo que queda al restarle al total todos los
/// aumentos; su concepto es el texto libre de las notas.
List<FacturaAcreedor> extraerFacturas({
  required int cuentaId,
  required double montoTotal,
  required String notas,
  String fechaOriginal = '',
}) {
  final aumentos = <FacturaAcreedor>[];
  final libres = <String>[];
  final lineas = notas.split('\n');
  for (var i = 0; i < lineas.length; i++) {
    final linea = lineas[i];
    final m = _reLineaAumento.firstMatch(linea);
    if (m == null) {
      final limpia = quitarMarcasComprobante(
          linea.replaceAll(_reMarcaFavor, '')).trim();
      if (limpia.isNotEmpty) libres.add(limpia);
      continue;
    }
    var resto = m.group(3) ?? '';
    final comps = leerMarcasComprobante(resto);
    resto = quitarMarcasComprobante(resto);
    double aplicado = 0;
    final ma = _reAplicado.firstMatch(resto);
    if (ma != null) {
      aplicado = _numero(ma.group(1)!);
      resto = resto.replaceAll(_reAplicado, '');
    }
    final concepto = resto.trim().replaceFirst(RegExp(r'^[—–-]\s*'), '').trim();
    aumentos.add(FacturaAcreedor(
      cuentaId: cuentaId,
      fecha: m.group(1)!.trim(),
      monto: _numero(m.group(2)!),
      concepto: concepto,
      aplicadoDeFavor: aplicado,
      lineaNotas: i,
      comprobantes: comps,
    ));
  }
  final sumaAumentos = aumentos.fold(0.0, (s, f) => s + f.monto);
  final original = montoTotal - sumaAumentos;
  return [
    if (original > 0.005 || aumentos.isEmpty)
      FacturaAcreedor(
        cuentaId: cuentaId,
        fecha: fechaOriginal,
        monto: original < 0 ? 0 : original,
        concepto: libres.join(' · '),
        esOriginal: true,
      ),
    ...aumentos,
  ];
}

// ── Pagos ─────────────────────────────────────────────────────────

class PagoAcreedor {
  final int cuentaId;
  /// Posición en `cuenta.pagos` (−1 si es una cuota pagada).
  final int indice;
  final String fecha;
  final double monto;
  final String metodo;
  final String referencia;
  /// Número de cuota si el pago es una cuota del plan.
  final int? numeroCuota;
  final List<int> comprobantes;

  const PagoAcreedor({
    required this.cuentaId,
    required this.indice,
    required this.fecha,
    required this.monto,
    required this.metodo,
    this.referencia = '',
    this.numeroCuota,
    this.comprobantes = const [],
  });

  bool get esCuota => numeroCuota != null;
}

/// Pagos de una cuenta: abonos libres más cuotas ya pagadas.
/// [cuotasPagadas] son tuplas (número, monto, fecha de pago).
List<PagoAcreedor> extraerPagos({
  required int cuentaId,
  required List<Map<String, dynamic>> pagos,
  List<(int, double, String)> cuotasPagadas = const [],
}) {
  return [
    for (var i = 0; i < pagos.length; i++)
      PagoAcreedor(
        cuentaId: cuentaId,
        indice: i,
        fecha: (pagos[i]['fecha'] ?? '').toString(),
        monto: double.tryParse(pagos[i]['monto']?.toString() ?? '') ?? 0,
        metodo: (pagos[i]['metodo'] ?? '').toString(),
        referencia: (pagos[i]['referencia'] ?? '').toString(),
        comprobantes:
            leerMarcasComprobante(pagos[i]['notas']?.toString()),
      ),
    for (final c in cuotasPagadas)
      PagoAcreedor(
        cuentaId: cuentaId,
        indice: -1,
        fecha: c.$3,
        monto: c.$2,
        metodo: 'Cuota ${c.$1}',
        numeroCuota: c.$1,
      ),
  ];
}

/// Ordena de más reciente a más antiguo; lo que no tiene fecha va al
/// final. Sirve para facturas y para pagos.
List<T> ordenarPorFechaDesc<T>(Iterable<T> items, String Function(T) fecha) {
  final lista = items.toList();
  final indices = {for (var i = 0; i < lista.length; i++) lista[i]: i};
  lista.sort((a, b) {
    final fa = parsearFechaDMY(fecha(a));
    final fb = parsearFechaDMY(fecha(b));
    if (fa == null && fb == null) return indices[a]!.compareTo(indices[b]!);
    if (fa == null) return 1;
    if (fb == null) return -1;
    final c = fb.compareTo(fa);
    return c != 0 ? c : indices[b]!.compareTo(indices[a]!);
  });
  return lista;
}

// ── Reparto de un pago entre varias cuentas del mismo acreedor ─────

class TramoPago {
  final int cuentaId;
  final double monto;
  const TramoPago(this.cuentaId, this.monto);
  @override
  String toString() => 'TramoPago($cuentaId, $monto)';
}

/// Reparte un pago entre las cuentas pendientes del acreedor, de la más
/// antigua a la más nueva ([pendientes] ya viene en ese orden). Lo que
/// sobra después de cubrirlas todas va a [idExcedente] (la cuenta más
/// reciente), donde queda como saldo a favor.
List<TramoPago> repartirPago(
  List<(int, double)> pendientes,
  double monto, {
  required int idExcedente,
}) {
  final tramos = <int, double>{};
  var resto = monto;
  for (final (id, pendiente) in pendientes) {
    if (resto <= 0.005) break;
    if (pendiente <= 0.005) continue;
    final parte = resto < pendiente ? resto : pendiente;
    tramos[id] = (tramos[id] ?? 0) + parte;
    resto -= parte;
  }
  if (resto > 0.005) {
    tramos[idExcedente] = (tramos[idExcedente] ?? 0) + resto;
  }
  return [
    for (final e in tramos.entries)
      TramoPago(e.key, double.parse(e.value.toStringAsFixed(2))),
  ];
}

// ── Agrupación por acreedor ───────────────────────────────────────

class GrupoAcreedor<T> {
  final String clave;
  final String nombre;
  final List<T> cuentas;
  /// Suma de lo pendiente en todas sus cuentas.
  final double deuda;
  /// Suma del saldo a favor en todas sus cuentas.
  final double favor;

  const GrupoAcreedor({
    required this.clave,
    required this.nombre,
    required this.cuentas,
    required this.deuda,
    required this.favor,
  });

  bool get tieneDeuda => deuda > 0.005;
  bool get tieneFavor => favor > 0.005;
}

/// Junta las cuentas de un mismo acreedor en un solo grupo. Las cuentas
/// de cada grupo quedan de la más antigua a la más nueva (por id) y el
/// nombre mostrado es el de la más nueva.
///
/// Orden de los grupos: primero los que tienen deuda (mayor a menor),
/// después los que sólo tienen saldo a favor, y al final los saldados;
/// dentro de cada bloque, por nombre.
List<GrupoAcreedor<T>> agruparPorAcreedor<T>(
  Iterable<T> cuentas, {
  required String Function(T) nombre,
  required int Function(T) id,
  required double Function(T) saldoRestante,
  required double Function(T) saldoFavor,
}) {
  final porClave = <String, List<T>>{};
  for (final c in cuentas) {
    var clave = normalizarNombreAcreedor(nombre(c));
    if (clave.isEmpty) clave = '#${id(c)}';
    porClave.putIfAbsent(clave, () => []).add(c);
  }
  final grupos = [
    for (final e in porClave.entries)
      () {
        final lista = e.value..sort((a, b) => id(a).compareTo(id(b)));
        return GrupoAcreedor<T>(
          clave: e.key,
          nombre: nombre(lista.last).trim(),
          cuentas: lista,
          deuda: lista.fold(0.0, (s, c) => s + saldoRestante(c)),
          favor: lista.fold(0.0, (s, c) => s + saldoFavor(c)),
        );
      }(),
  ];
  int bloque(GrupoAcreedor<T> g) => g.tieneDeuda ? 0 : (g.tieneFavor ? 1 : 2);
  grupos.sort((a, b) {
    final c = bloque(a).compareTo(bloque(b));
    if (c != 0) return c;
    if (a.tieneDeuda && (b.deuda - a.deuda).abs() > 0.005) {
      return b.deuda.compareTo(a.deuda);
    }
    if (!a.tieneDeuda && a.tieneFavor && (b.favor - a.favor).abs() > 0.005) {
      return b.favor.compareTo(a.favor);
    }
    return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
  });
  return grupos;
}

/// Totales para el resumen de arriba de la pantalla.
class ResumenAcreedores {
  final double deudaTotal;
  final double favorTotal;
  final int conDeuda;
  final int conFavor;
  final int acreedores;
  const ResumenAcreedores({
    required this.deudaTotal,
    required this.favorTotal,
    required this.conDeuda,
    required this.conFavor,
    required this.acreedores,
  });

  /// Deuda menos saldo a favor: lo que realmente falta pagar si se
  /// usara todo el saldo a favor.
  double get neto => deudaTotal - favorTotal;
}

ResumenAcreedores resumirAcreedores<T>(List<GrupoAcreedor<T>> grupos) =>
    ResumenAcreedores(
      deudaTotal: grupos.fold(0.0, (s, g) => s + g.deuda),
      favorTotal: grupos.fold(0.0, (s, g) => s + g.favor),
      conDeuda: grupos.where((g) => g.tieneDeuda).length,
      conFavor: grupos.where((g) => g.tieneFavor).length,
      acreedores: grupos.length,
    );
