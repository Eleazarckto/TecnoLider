part of 'main.dart';

// ════════════════════════════════════════════════════════════════════
//  SERVICIO TÉCNICO — COBROS, COMPROBANTE E INGRESOS
// ════════════════════════════════════════════════════════════════════
//  Antes el servicio solo se marcaba "pagado / no pagado". El dueño
//  quiere facturarlo como un teléfono: cada cobro con su método (Pago
//  Móvil con referencia, cédula y teléfono del pagador, efectivo $,
//  etc.), monto, tasa y estado del pago, más un reporte de ingresos de
//  servicio técnico APARTE del reporte de ventas de teléfonos.
//
//  ¿Dónde se guarda? La tabla `servicios` del backend no tiene columnas
//  para pagos ni para la tienda (revisado con diagnostico_bd y el GET
//  de producción). Para no tocar el servidor, los cobros viajan dentro
//  del bloque __META__ que ya va al inicio de `descripcion` (el mismo
//  mecanismo que guarda cédula, marca, checklist y fotos):
//      __META__{..., "tienda": "...", "pagos": [{...}, ...]}
//  Las columnas `abono` y `pagado` se siguen llenando (abono = suma en
//  USD de los cobros) para que lo viejo (comisiones, rentabilidad,
//  listado) siga funcionando igual.
//
//  Estos cobros NO se mezclan con las facturas: no pasan por
//  `facturas` ni `factura_pagos`, así que el reporte de ventas de
//  teléfonos no los ve. Su reporte propio es VentanaIngresosServicioTecnico.
// ════════════════════════════════════════════════════════════════════

/// Estado del pago de un servicio a partir del monto y lo cobrado.
String estadoPagoServicio(double monto, double cobrado) {
  if (monto > 0 && cobrado >= monto - 0.005) return 'Pagado';
  if (cobrado > 0.005) return 'Abonado';
  return 'Pendiente';
}

Color colorEstadoPagoServicio(String estado) => estado == 'Pagado'
    ? AppColors.statusGreen
    : estado == 'Abonado' ? AppColors.statusOrange : AppColors.statusRed;

/// Un cobro de un servicio técnico.
class PagoServicioTecnico {
  final DateTime fecha;
  final String metodo;
  /// 'Bs' o 'USD' (moneda en la que se recibió [monto]).
  final String moneda;
  /// Monto en la moneda del cobro.
  final double monto;
  /// Tasa Bs/$ usada al cobrar (histórica, no cambia después).
  final double tasa;
  /// Equivalente en USD con [tasa] (lo que se suma al abono).
  final double montoUsd;
  // ── Datos del pago móvil / transferencia (opcionales) ──
  final String referencia;
  final String cedulaPagador;
  final String telefonoPagador;
  final String bancoOrigen;
  final String bancoDestino;
  // ── Quién y dónde ──
  final String usuario;
  final String tienda;
  final String nota;

  const PagoServicioTecnico({
    required this.fecha,
    required this.metodo,
    required this.moneda,
    required this.monto,
    required this.tasa,
    required this.montoUsd,
    this.referencia = '',
    this.cedulaPagador = '',
    this.telefonoPagador = '',
    this.bancoOrigen = '',
    this.bancoDestino = '',
    this.usuario = '',
    this.tienda = '',
    this.nota = '',
  });

  /// Abono que se registró antes de existir los cobros con método: se
  /// conserva como un cobro "Sin detalle" para que la suma no lo pierda.
  factory PagoServicioTecnico.legado(double montoUsd, DateTime fecha,
          {String tienda = ''}) =>
      PagoServicioTecnico(
        fecha: fecha, metodo: 'Sin detalle', moneda: 'USD',
        monto: montoUsd, tasa: 0, montoUsd: montoUsd, tienda: tienda,
        nota: 'Abono registrado antes de los cobros con método');

  bool get esBs => moneda == 'Bs';

  Map<String, dynamic> toMap() => {
        'f': fecha.toIso8601String(),
        'met': metodo,
        'mon': moneda,
        'm': monto,
        't': tasa,
        'usd': montoUsd,
        if (referencia.isNotEmpty) 'ref': referencia,
        if (cedulaPagador.isNotEmpty) 'ced': cedulaPagador,
        if (telefonoPagador.isNotEmpty) 'tel': telefonoPagador,
        if (bancoOrigen.isNotEmpty) 'bo': bancoOrigen,
        if (bancoDestino.isNotEmpty) 'bd': bancoDestino,
        if (usuario.isNotEmpty) 'u': usuario,
        if (tienda.isNotEmpty) 'ti': tienda,
        if (nota.isNotEmpty) 'n': nota,
      };

  factory PagoServicioTecnico.fromMap(Map m) {
    double d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;
    String st(dynamic v) => v?.toString() ?? '';
    final moneda = st(m['mon']).isEmpty ? 'USD' : st(m['mon']);
    final monto = d(m['m']);
    final tasa = d(m['t']);
    return PagoServicioTecnico(
      fecha: DateTime.tryParse(st(m['f'])) ?? DateTime(1900),
      metodo: st(m['met']),
      moneda: moneda,
      monto: monto,
      tasa: tasa,
      montoUsd: m['usd'] != null
          ? d(m['usd'])
          : (moneda == 'Bs' && tasa > 0 ? monto / tasa : monto),
      referencia: st(m['ref']),
      cedulaPagador: st(m['ced']),
      telefonoPagador: st(m['tel']),
      bancoOrigen: st(m['bo']),
      bancoDestino: st(m['bd']),
      usuario: st(m['u']),
      tienda: st(m['ti']),
      nota: st(m['n']),
    );
  }

  /// Lee la lista del META (tolerante a datos corruptos).
  static List<PagoServicioTecnico> listaDesdeMeta(dynamic v) {
    if (v is! List) return [];
    final r = <PagoServicioTecnico>[];
    for (final e in v) {
      if (e is Map) {
        try { r.add(PagoServicioTecnico.fromMap(e)); } catch (_) {}
      }
    }
    return r;
  }

  String get montoTexto =>
      esBs ? formatBolivares(monto) : formatCurrency(monto);

  /// "Pago Móvil · Bs 3.650,00 (≈ $10.00)".
  String get descripcionCorta => esBs
      ? '$metodo · $montoTexto (≈ ${formatCurrency(montoUsd)})'
      : '$metodo · $montoTexto';

  /// Fecha + datos del pagador en una línea.
  String get detalle {
    final f = '${fecha.day.toString().padLeft(2, '0')}/'
        '${fecha.month.toString().padLeft(2, '0')}/${fecha.year} '
        '${fecha.hour.toString().padLeft(2, '0')}:'
        '${fecha.minute.toString().padLeft(2, '0')}';
    return [
      f,
      if (esBs && tasa > 0) 'Tasa ${tasa.toStringAsFixed(2)}',
      if (referencia.isNotEmpty) 'Ref. $referencia',
      if (cedulaPagador.isNotEmpty) 'C.I. $cedulaPagador',
      if (telefonoPagador.isNotEmpty) 'Tel. $telefonoPagador',
      if (bancoOrigen.isNotEmpty) BancosVenezuela.nombre(bancoOrigen),
      if (usuario.isNotEmpty) 'Cobró: $usuario',
    ].join(' · ');
  }
}

/// Suma en USD de los cobros de un servicio (o su abono viejo si no
/// tiene cobros con método).
double cobradoServicioUsd(ServicioTecnico s) => s.pagos.isEmpty
    ? s.abono
    : s.pagos.fold<double>(0, (t, p) => t + p.montoUsd);

extension ServicioTecnicoCobros on ServicioTecnico {
  double get cobradoUsd => cobradoServicioUsd(this);
  String get estadoPago => estadoPagoServicio(monto, cobradoUsd);
}

bool _esPagoMovilServicio(String metodo) {
  final m = metodo.trim().toLowerCase();
  return m.contains('pago móvil') || m.contains('pago movil');
}

/// Métodos que tienen sentido para cobrar un servicio: los configurados
/// en el sistema menos las financiadoras (un servicio no se financia).
List<String> metodosCobroServicio() {
  final l = ConfigSistema.metodossPago.where((m) {
    final x = m.toLowerCase();
    return !(x.contains('cashea') || x.contains('krece') || x.contains('weppa'));
  }).toList();
  return l.isEmpty ? ['Efectivo \$', 'Pago Móvil'] : l;
}

/// Diálogo para registrar un cobro. [resta] (USD) se ofrece como monto
/// sugerido. Devuelve null si se cancela.
Future<PagoServicioTecnico?> mostrarDialogoCobroServicio(BuildContext context,
    {required double resta}) {
  final metodos = metodosCobroServicio();
  String metodo = metodos.firstWhere(
      (m) => m.toLowerCase().contains('efectivo \$'),
      orElse: () => metodos.first);
  final montoCtrl = TextEditingController();
  final tasaCtrl = TextEditingController(
      text: ConfigSistema.tasaCambio > 0
          ? ConfigSistema.tasaCambio.toStringAsFixed(2) : '');
  final refCtrl = TextEditingController();
  final cedCtrl = TextEditingController();
  final telCtrl = TextEditingController();
  final notaCtrl = TextEditingController();
  String letraCedula = 'V';
  String? bancoOrigen;
  String bancoDestino = BancosVenezuela.codigoBDV;
  String? error;

  double num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  return showDialog<PagoServicioTecnico>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final esBs = esMetodoEnBolivares(metodo);
      final esPM = _esPagoMovilServicio(metodo);
      final tasa = num(tasaCtrl);
      final monto = num(montoCtrl);
      final usd = esBs ? (tasa > 0 ? monto / tasa : 0.0) : monto;

      void aceptar() {
        String? falta;
        if (monto <= 0) {
          falta = 'Ingrese un monto mayor a 0';
        } else if (esBs && tasa <= 0) {
          falta = 'Ingrese la tasa del cobro';
        } else if (esPM && refCtrl.text.trim().isEmpty) {
          falta = 'Ingrese la referencia del pago móvil';
        } else if (esPM && cedCtrl.text.trim().isEmpty) {
          falta = 'Ingrese la cédula del pagador del pago móvil';
        } else if (esPM && telCtrl.text.trim().length < 10) {
          falta = 'Ingrese el teléfono afiliado al pago móvil (ej. 04141234567)';
        }
        if (falta != null) {
          setS(() => error = falta);
          return;
        }
        Navigator.pop(ctx, PagoServicioTecnico(
          fecha: DateTime.now(),
          metodo: metodo,
          moneda: esBs ? 'Bs' : 'USD',
          monto: redondearCentavos(monto),
          tasa: esBs ? tasa : ConfigSistema.tasaCambio,
          montoUsd: redondearCentavos(usd),
          referencia: refCtrl.text.trim(),
          cedulaPagador: cedCtrl.text.trim().isEmpty
              ? '' : '$letraCedula${cedCtrl.text.trim()}',
          telefonoPagador: telCtrl.text.trim(),
          bancoOrigen: esPM ? (bancoOrigen ?? '') : '',
          bancoDestino: esPM ? bancoDestino : '',
          usuario: usuarioSesion?.nombre ?? '',
          tienda: tiendaUsuarioActual(),
          nota: notaCtrl.text.trim(),
        ));
      }

      return AlertDialog(
        title: const Row(children: [
          Icon(Icons.point_of_sale, color: AppColors.brandBlue),
          SizedBox(width: 8),
          Text('Registrar cobro'),
        ]),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Resta por cobrar: ${formatCurrency(resta)}'
                   '${ConfigSistema.tasaCambio > 0 ? '  (${formatBolivares(resta * ConfigSistema.tasaCambio)})' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w700,
                  color: AppColors.brandBlue)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: metodo,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Método de pago', border: OutlineInputBorder()),
                items: metodos.map((m) =>
                    DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => setS(() { metodo = v ?? metodo; error = null; }),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(
                  controller: montoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: esBs ? 'Monto en Bs' : 'Monto en \$',
                    border: const OutlineInputBorder()),
                  onChanged: (_) => setS(() {}),
                )),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: resta <= 0 ? null : () => setS(() {
                    final v = esBs ? resta * (tasa > 0 ? tasa : 0) : resta;
                    montoCtrl.text = v.toStringAsFixed(2);
                  }),
                  child: const Text('Cobrar\nresta', textAlign: TextAlign.center)),
              ]),
              if (esBs) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: tasaCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Tasa Bs/\$ (BCV del día)',
                    border: OutlineInputBorder()),
                  onChanged: (_) => setS(() {}),
                ),
                const SizedBox(height: 4),
                Text('Equivale a ${formatCurrency(usd)}',
                  style: const TextStyle(fontSize: 12,
                    color: AppColors.textSecondary)),
              ],
              if (esPM) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: refCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Referencia *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  DropdownButton<String>(
                    value: letraCedula,
                    items: const ['V', 'E', 'J', 'P'].map((l) =>
                        DropdownMenuItem(value: l, child: Text(l))).toList(),
                    onChanged: (v) => setS(() => letraCedula = v ?? 'V'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(
                    controller: cedCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cédula del pagador *',
                      border: OutlineInputBorder()),
                  )),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: telCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono del pagador *',
                    hintText: '04141234567',
                    border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: bancoOrigen,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Banco del pagador (opcional)',
                    border: OutlineInputBorder()),
                  items: BancosVenezuela.listaOrdenada.map((e) =>
                      DropdownMenuItem(value: e.key,
                        child: Text('${e.key} · ${e.value}',
                          overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setS(() => bancoOrigen = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: bancoDestino,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Banco destino (cuenta de la tienda)',
                    border: OutlineInputBorder()),
                  items: BancosVenezuela.listaOrdenada.map((e) =>
                      DropdownMenuItem(value: e.key,
                        child: Text('${e.key} · ${e.value}',
                          overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setS(() => bancoDestino = v ?? bancoDestino),
                ),
              ] else if (!metodo.toLowerCase().contains('efectivo')) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: refCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Referencia (opcional)',
                    border: OutlineInputBorder()),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: notaCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)', border: OutlineInputBorder()),
              ),
              if (usd > resta + 0.009 && resta > 0) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Ojo: el cobro supera lo que resta por '
                    '${formatCurrency(usd - resta)}.',
                  style: const TextStyle(color: AppColors.statusOrange,
                    fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              if (error != null) Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!,
                  style: const TextStyle(color: AppColors.statusRed,
                    fontWeight: FontWeight.w700)),
              ),
            ],
          )),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar')),
          ElevatedButton.icon(
            onPressed: aceptar,
            icon: const Icon(Icons.check),
            label: const Text('Registrar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white),
          ),
        ],
      );
    }),
  );
}

/// Guarda en el backend [s] con [pagos] como cobros (abono y pagado se
/// recalculan). Devuelve el servicio actualizado.
Future<ServicioTecnico> guardarCobrosServicio(
    ServicioTecnico s, List<PagoServicioTecnico> pagos) async {
  if (s.id == null) throw Exception('Servicio sin ID. Recargue la pantalla.');
  // Copia por ida y vuelta del mapa: no se toca el objeto original
  // hasta que el servidor confirme.
  final copia = ServicioTecnico.fromMap({...s.toMap(), 'id': s.id});
  copia.pagos = pagos;
  copia.abono = redondearCentavos(
      pagos.fold<double>(0, (t, p) => t + p.montoUsd));
  copia.pagado = copia.monto > 0 && copia.abono >= copia.monto - 0.005;
  if (copia.tienda.isEmpty) copia.tienda = tiendaUsuarioActual();
  await _Api.put('servicios', s.id!.toString(), copia.toMap());
  return copia;
}

// ════════════════════════════════════════════════════════════════════
//  SECCIÓN "COBROS" DEL DETALLE DEL SERVICIO
// ════════════════════════════════════════════════════════════════════
class SeccionCobrosServicio extends StatefulWidget {
  final ServicioTecnico servicio;
  final ValueChanged<ServicioTecnico> onActualizado;
  const SeccionCobrosServicio(
      {super.key, required this.servicio, required this.onActualizado});
  @override
  State<SeccionCobrosServicio> createState() => _SeccionCobrosServicioState();
}

class _SeccionCobrosServicioState extends State<SeccionCobrosServicio> {
  bool _guardando = false;

  ServicioTecnico get s => widget.servicio;

  bool get _puedeAnular {
    final r = usuarioSesion?.rol ?? '';
    return r == 'Maestro' || r == 'Dueño' || r == 'Administrador' ||
        r == 'Gerente';
  }

  /// Cobros actuales; si solo hay un abono viejo se muestra como cobro
  /// "Sin detalle" para que se vea de dónde sale el abonado.
  List<PagoServicioTecnico> get _cobros => s.pagos.isNotEmpty
      ? s.pagos
      : (s.abono > 0.005
          ? [PagoServicioTecnico.legado(s.abono, s.fecha, tienda: s.tienda)]
          : const []);

  Future<void> _guardar(List<PagoServicioTecnico> pagos, String ok) async {
    setState(() => _guardando = true);
    try {
      final nuevo = await guardarCobrosServicio(s, pagos);
      widget.onActualizado(nuevo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok), backgroundColor: AppColors.statusGreen));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo guardar el cobro: $e'),
          backgroundColor: AppColors.statusRed));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _registrar() async {
    final resta = (s.monto - s.cobradoUsd).clamp(0, double.infinity).toDouble();
    final pago = await mostrarDialogoCobroServicio(context, resta: resta);
    if (pago == null || !mounted) return;
    await _guardar([..._cobros, pago],
        'Cobro registrado: ${pago.descripcionCorta}');
  }

  Future<void> _anular(int i) async {
    final p = _cobros[i];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Anular cobro'),
        content: Text('¿Anular el cobro ${p.descripcionCorta}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
            child: const Text('No')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true),
            child: const Text('Anular')),
        ],
      ),
    );
    if (ok != true) return;
    final lista = [..._cobros]..removeAt(i);
    await _guardar(lista, 'Cobro anulado');
  }

  @override
  Widget build(BuildContext context) {
    final estado = s.estadoPago;
    final color = colorEstadoPagoServicio(estado);
    final cobros = _cobros;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.payments_outlined, color: AppColors.brandBlue),
            const SizedBox(width: 8),
            const Expanded(child: Text('Cobros',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10)),
              child: Text(estado.toUpperCase(),
                style: TextStyle(color: color, fontWeight: FontWeight.w900,
                  fontSize: 11)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('Cobrado ${formatCurrency(s.cobradoUsd)} de '
               '${formatCurrency(s.monto)} · Resta '
               '${formatCurrency((s.monto - s.cobradoUsd).clamp(0, double.infinity).toDouble())}',
            style: const TextStyle(fontSize: 12,
              color: AppColors.textSecondary)),
          if (s.tienda.isNotEmpty)
            Text('Tienda: ${s.tienda}',
              style: const TextStyle(fontSize: 12,
                color: AppColors.textSecondary)),
          const Divider(),
          if (cobros.isEmpty)
            const Text('Sin cobros registrados.',
              style: TextStyle(color: AppColors.textSecondary)),
          for (var i = 0; i < cobros.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(cobros[i].esBs ? Icons.phone_iphone : Icons.attach_money,
                color: AppColors.brandBlue),
              title: Text(cobros[i].descripcionCorta,
                style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(cobros[i].detalle,
                style: const TextStyle(fontSize: 11)),
              trailing: _puedeAnular && !_guardando
                  ? IconButton(
                      tooltip: 'Anular cobro',
                      icon: const Icon(Icons.close, color: AppColors.statusRed),
                      onPressed: () => _anular(i))
                  : null,
            ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ElevatedButton.icon(
              onPressed: _guardando || s.id == null ? null : _registrar,
              icon: _guardando
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.point_of_sale, size: 18),
              label: const Text('Registrar cobro'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white),
            ),
            OutlinedButton.icon(
              onPressed: () => imprimirComprobanteServicio(context, s),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Imprimir comprobante'),
            ),
            OutlinedButton.icon(
              onPressed: () => compartirComprobanteServicio(context, s),
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text('Compartir'),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  COMPROBANTE DEL SERVICIO (PDF)
// ════════════════════════════════════════════════════════════════════

Future<pw.Document> construirComprobanteServicio(
    ServicioTecnico s, FormatoImpresion formato) async {
  final esTermica = ImpresionHelper.esTermica(formato);
  final escala = ImpresionHelper.escalaFuente(formato);
  double fs(double b) => b * escala;
  final sede = s.tienda.isNotEmpty
      ? s.tienda
      : (ConfigSistema.tiendas.isNotEmpty
          ? ConfigSistema.tiendas.first : ConfigSistema.nombreEmpresa);
  final enc = ConfigSistema.encabezadoDe(sede);
  final cobros = s.pagos.isNotEmpty
      ? s.pagos
      : (s.abono > 0.005 ? [PagoServicioTecnico.legado(s.abono, s.fecha)] : const <PagoServicioTecnico>[]);
  final resta = (s.monto - s.cobradoUsd).clamp(0, double.infinity).toDouble();
  String fecha(DateTime f) =>
      '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

  pw.Widget fila(String a, String b, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Expanded(child: pw.Text(a, style: pw.TextStyle(fontSize: fs(10)))),
      pw.Text(b, style: pw.TextStyle(fontSize: fs(10),
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    ]));
  pw.Widget sep() => pw.Container(height: 0.6, color: PdfColors.black,
      margin: const pw.EdgeInsets.symmetric(vertical: 4));

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: ImpresionHelper.formatoPdf(formato),
    margin: esTermica ? const pw.EdgeInsets.all(4) : const pw.EdgeInsets.all(32),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(enc.nombreSede.isNotEmpty ? enc.nombreSede : sede,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: fs(13), fontWeight: pw.FontWeight.bold)),
        if (enc.rif.isNotEmpty)
          pw.Text('RIF ${enc.rif}', textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: fs(9))),
        if (enc.direccion.isNotEmpty)
          pw.Text(enc.direccion, textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: fs(9))),
        if (enc.telefono.isNotEmpty)
          pw.Text('Tel. ${enc.telefono}', textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: fs(9))),
        pw.SizedBox(height: 6),
        pw.Container(
          color: PdfColors.black,
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Text('COMPROBANTE DE SERVICIO TÉCNICO',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: fs(11), color: PdfColors.white,
              fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 6),
        fila('Orden', s.id != null ? '#${s.id}' : '-', bold: true),
        fila('Fecha de recepción', fecha(s.fecha)),
        fila('Emitido', fecha(DateTime.now())),
        sep(),
        fila('Cliente', s.nombreCliente),
        if (s.rifCi.isNotEmpty) fila('C.I. / RIF', s.rifCi),
        if (s.telefono.isNotEmpty) fila('Teléfono', s.telefono),
        fila('Equipo', '${s.marca} ${s.modelo}'.trim()),
        if (s.imei.isNotEmpty) fila('IMEI', s.imei),
        if (s.descripcion.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text('Servicio: ${s.descripcion}',
              style: pw.TextStyle(fontSize: fs(10)))),
        if (s.tecnico.isNotEmpty) fila('Técnico', s.tecnico),
        sep(),
        fila('Monto del servicio', formatCurrency(s.monto), bold: true),
        if (ConfigSistema.tasaCambio > 0)
          fila('Equivalente (tasa ${ConfigSistema.tasaCambio.toStringAsFixed(2)})',
            formatBolivares(s.monto * ConfigSistema.tasaCambio)),
        sep(),
        pw.Text('COBROS', style: pw.TextStyle(fontSize: fs(10),
          fontWeight: pw.FontWeight.bold)),
        if (cobros.isEmpty)
          pw.Text('Sin cobros registrados', style: pw.TextStyle(fontSize: fs(9))),
        ...cobros.map((p) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
          fila('${fecha(p.fecha)}  ${p.metodo}', p.montoTexto, bold: true),
          if (p.esBs && p.tasa > 0)
            fila('   Tasa ${p.tasa.toStringAsFixed(2)}', '= ${formatCurrency(p.montoUsd)}'),
          if (p.referencia.isNotEmpty) fila('   Referencia', p.referencia),
          if (p.cedulaPagador.isNotEmpty) fila('   Cédula pagador', p.cedulaPagador),
          if (p.telefonoPagador.isNotEmpty) fila('   Teléfono pagador', p.telefonoPagador),
        ])),
        sep(),
        fila('Total cobrado', formatCurrency(s.cobradoUsd), bold: true),
        fila('Resta', formatCurrency(resta), bold: true),
        fila('Estado del pago', s.estadoPago.toUpperCase(), bold: true),
        pw.SizedBox(height: 10),
        pw.Text('Gracias por su preferencia', textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: fs(9))),
      ],
    ),
  ));
  return pdf;
}

Future<void> imprimirComprobanteServicio(
    BuildContext context, ServicioTecnico s) =>
    ImpresionHelper.imprimirDocumento(
      context: context,
      construirPdf: (f) => construirComprobanteServicio(s, f),
      nombreArchivo: 'comprobante_servicio_${s.id ?? ''}',
    );

Future<void> compartirComprobanteServicio(
    BuildContext context, ServicioTecnico s) async {
  try {
    final pdf = await construirComprobanteServicio(s, FormatoImpresion.a4);
    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Comprobante_servicio_${s.id ?? ''}.pdf');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo compartir el comprobante: $e'),
        backgroundColor: AppColors.statusRed));
    }
  }
}

// ════════════════════════════════════════════════════════════════════
//  REPORTE DE INGRESOS DE SERVICIO TÉCNICO (separado de ventas)
// ════════════════════════════════════════════════════════════════════

/// Un cobro de servicio listo para el reporte.
class CobroServicioFila {
  final ServicioTecnico servicio;
  final PagoServicioTecnico pago;
  /// Tienda donde se cobró (la del cobro, o la del servicio).
  final String tienda;
  const CobroServicioFila(this.servicio, this.pago, this.tienda);
}

/// Cobros de servicio técnico con fecha en [desde, hasta] (días
/// completos) y de la [tienda] indicada (null = todas; '' = sin tienda).
/// Los servicios viejos con abono pero sin cobros detallados aportan un
/// cobro "Sin detalle" en su fecha de recepción.
List<CobroServicioFila> cobrosServicioEnRango(
    List<ServicioTecnico> servicios, DateTime desde, DateTime hasta,
    {String? tienda}) {
  final ini = DateTime(desde.year, desde.month, desde.day);
  final fin = DateTime(hasta.year, hasta.month, hasta.day + 1);
  final r = <CobroServicioFila>[];
  for (final s in servicios) {
    final pagos = s.pagos.isNotEmpty
        ? s.pagos
        : (s.abono > 0.005
            ? [PagoServicioTecnico.legado(s.abono, s.fecha, tienda: s.tienda)]
            : const <PagoServicioTecnico>[]);
    for (final p in pagos) {
      if (p.fecha.isBefore(ini) || !p.fecha.isBefore(fin)) continue;
      final t = p.tienda.isNotEmpty ? p.tienda : s.tienda;
      if (tienda != null && t != tienda) continue;
      r.add(CobroServicioFila(s, p, t));
    }
  }
  r.sort((a, b) => b.pago.fecha.compareTo(a.pago.fecha));
  return r;
}

class VentanaIngresosServicioTecnico extends StatefulWidget {
  final List<ServicioTecnico> servicios;
  const VentanaIngresosServicioTecnico({super.key, required this.servicios});
  @override
  State<VentanaIngresosServicioTecnico> createState() =>
      _VentanaIngresosServicioTecnicoState();
}

class _VentanaIngresosServicioTecnicoState
    extends State<VentanaIngresosServicioTecnico> {
  late DateTime _desde, _hasta;
  /// null = todas; '' = cobros sin tienda (servicios viejos).
  String? _tienda;

  @override
  void initState() {
    super.initState();
    final h = DateTime.now();
    _desde = DateTime(h.year, h.month, 1);
    _hasta = DateTime(h.year, h.month, h.day);
    // Vendedores/encargados ven su tienda; roles altos, todas.
    if (!puedeVerTodasLasTiendas() && tiendaUsuarioActual().isNotEmpty) {
      _tienda = tiendaUsuarioActual();
    }
  }

  String _f(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _rango() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _desde, end: _hasta),
    );
    if (r != null) setState(() { _desde = r.start; _hasta = r.end; });
  }

  @override
  Widget build(BuildContext context) {
    final filas = cobrosServicioEnRango(widget.servicios, _desde, _hasta,
        tienda: _tienda);
    final totalUsd = filas.fold<double>(0, (t, f) => t + f.pago.montoUsd);
    final porMetodo = <String, ({double usd, double nativo, bool bs})>{};
    for (final f in filas) {
      final k = f.pago.metodo;
      final prev = porMetodo[k];
      porMetodo[k] = (
        usd: (prev?.usd ?? 0) + f.pago.montoUsd,
        nativo: (prev?.nativo ?? 0) + f.pago.monto,
        bs: f.pago.esBs,
      );
    }
    final porTienda = <String, double>{};
    for (final f in filas) {
      final k = f.tienda.isEmpty ? 'Sin tienda' : f.tienda;
      porTienda[k] = (porTienda[k] ?? 0) + f.pago.montoUsd;
    }
    // Pendiente por cobrar de los servicios RECIBIDOS en el rango.
    final recibidos = widget.servicios.where((s) =>
        !s.fecha.isBefore(_desde) &&
        s.fecha.isBefore(DateTime(_hasta.year, _hasta.month, _hasta.day + 1)) &&
        (_tienda == null || s.tienda == _tienda));
    final pendiente = recibidos.fold<double>(0, (t, s) =>
        t + (s.monto - s.cobradoUsd).clamp(0, double.infinity).toDouble());
    final tiendas = <String>{
      ...ConfigSistema.tiendas,
      ...widget.servicios.map((s) => s.tienda).where((t) => t.isNotEmpty),
    }.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ingresos de Servicio Técnico'),
        actions: [
          const BotonCalculadora(),
          IconButton(
            tooltip: 'Compartir PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: filas.isEmpty ? null : () => _compartirPdf(filas, totalUsd,
                porMetodo.map((k, v) => MapEntry(k, v.usd)))),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center,
          children: [
          OutlinedButton.icon(
            onPressed: _rango,
            icon: const Icon(Icons.date_range, size: 18),
            label: Text('${_f(_desde)} – ${_f(_hasta)}')),
          if (puedeVerTodasLasTiendas())
            DropdownButton<String?>(
              value: _tienda,
              hint: const Text('Todas las tiendas'),
              items: [
                const DropdownMenuItem<String?>(value: null,
                  child: Text('Todas las tiendas')),
                ...tiendas.map((t) => DropdownMenuItem<String?>(
                  value: t, child: Text(t))),
                const DropdownMenuItem<String?>(value: '',
                  child: Text('Sin tienda (registros viejos)')),
              ],
              onChanged: (v) => setState(() => _tienda = v),
            )
          else if (_tienda != null)
            Chip(label: Text(_tienda!)),
        ]),
        const SizedBox(height: 10),
        // Indicadores del Panel (estilo Brizuela); antes un bloque azul.
        FilaIndicadores(padding: const EdgeInsets.symmetric(vertical: 4), [
          Indicador('Ingresos cobrados', formatCurrency(totalUsd),
              icono: Icons.payments_rounded, color: AppColors.statusGreen,
              detalle: '${filas.length} cobro(s)'),
          Indicador('Pendiente por cobrar', formatCurrency(pendiente),
              icono: Icons.hourglass_bottom_rounded,
              color: pendiente > 0 ? AppColors.statusOrange : AppColors.azulVivo,
              detalle: '(servicios recibidos en el rango)'),
        ]),
        const SizedBox(height: 10),
        Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Por método de pago',
              style: TextStyle(fontWeight: FontWeight.w800)),
            const Divider(),
            if (porMetodo.isEmpty) const Text('Sin cobros.'),
            ...porMetodo.entries.map((e) => Row(children: [
              Expanded(child: Text(e.key)),
              if (e.value.bs)
                Text('${formatBolivares(e.value.nativo)}  ',
                  style: const TextStyle(fontSize: 12,
                    color: AppColors.textSecondary)),
              Text(formatCurrency(e.value.usd),
                style: const TextStyle(fontWeight: FontWeight.w800)),
            ])),
          ]),
        )),
        if (porTienda.length > 1)
          Card(child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Por tienda',
                style: TextStyle(fontWeight: FontWeight.w800)),
              const Divider(),
              ...porTienda.entries.map((e) => Row(children: [
                Expanded(child: Text(e.key)),
                Text(formatCurrency(e.value),
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              ])),
            ]),
          )),
        const SizedBox(height: 6),
        const Text('Detalle de cobros',
          style: TextStyle(fontWeight: FontWeight.w800)),
        if (filas.isEmpty)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('No hay cobros de servicio técnico en este período.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary))),
        ...filas.map((f) => Card(child: ListTile(
          dense: true,
          leading: Icon(f.pago.esBs ? Icons.phone_iphone : Icons.attach_money,
            color: AppColors.brandBlue),
          title: Text('${f.servicio.nombreCliente} · '
              '${'${f.servicio.marca} ${f.servicio.modelo}'.trim()}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${f.pago.metodo} · ${f.pago.detalle}'
              '${f.tienda.isNotEmpty ? ' · ${f.tienda}' : ''}',
            style: const TextStyle(fontSize: 11)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatCurrency(f.pago.montoUsd),
                style: const TextStyle(fontWeight: FontWeight.w900)),
              if (f.pago.esBs)
                Text(formatBolivares(f.pago.monto),
                  style: const TextStyle(fontSize: 10,
                    color: AppColors.textSecondary)),
            ]),
        ))),
      ]),
    );
  }

  Future<void> _compartirPdf(List<CobroServicioFila> filas, double total,
      Map<String, double> porMetodo) async {
    try {
      final pdf = pw.Document();
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (_) => [
          pw.Text('Ingresos de Servicio Técnico',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text('Del ${_f(_desde)} al ${_f(_hasta)}'
              '${_tienda == null ? ' · Todas las tiendas' : ' · ${_tienda!.isEmpty ? 'Sin tienda' : _tienda}'}'),
          pw.SizedBox(height: 8),
          pw.Text('Total cobrado: ${formatCurrency(total)}',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          ...porMetodo.entries.map((e) =>
              pw.Text('${e.key}: ${formatCurrency(e.value)}')),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['Fecha', 'Cliente', 'Equipo', 'Método', 'Monto', 'USD', 'Tienda'],
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            data: filas.map((f) => [
              _f(f.pago.fecha),
              f.servicio.nombreCliente,
              '${f.servicio.marca} ${f.servicio.modelo}'.trim(),
              f.pago.metodo,
              f.pago.montoTexto,
              formatCurrency(f.pago.montoUsd),
              f.tienda,
            ]).toList(),
          ),
        ],
      ));
      await Printing.sharePdf(bytes: await pdf.save(),
        filename: 'Ingresos_servicio_tecnico_${DateTime.now().millisecondsSinceEpoch}.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo generar el PDF: $e'),
          backgroundColor: AppColors.statusRed));
      }
    }
  }
}
