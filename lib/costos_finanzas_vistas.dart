part of 'main.dart';

// ════════════════════════════════════════════════════════════════════
//  COSTOS Y FINANZAS — APARTADOS NUEVOS
// ════════════════════════════════════════════════════════════════════
//  Pantallas que el dueño pidió para entender el negocio "como en su
//  Excel" (la aritmética está en lib/finanzas_tienda.dart, con tests):
//
//   · Equilibrio por tienda: ganancia de cada día − gastos, acumulado
//     del período y el día en que cada tienda cubre sus gastos.
//   · Ganancia real: la venta se mide contra el precio de CONTADO; lo
//     que sobra por financiamiento/tasa es DIFERENCIAL CAMBIARIO.
//   · Flujo de caja: entradas y salidas por tienda y consolidado, con
//     $ y Bs SEPARADOS (nunca se suman sin convertir).
//   · Gastos: ahora se guardan (antes se perdían al salir) con tienda y
//     categoría.
//   · Nómina: empleados elegidos de los usuarios del sistema; cada pago
//     guarda a quién se le pagó, quién lo registró y cuándo.
//
//  Persistencia SIN tocar el servidor: gastos, empleados y pagos de
//  nómina viajan como JSON en la tabla `configuracion` (clave/valor),
//  una clave por mes (`cf_gastos_AAAA_MM`, `cf_nomina_pagos_AAAA_MM`).
// ════════════════════════════════════════════════════════════════════

/// Normaliza el nombre de la financiadora de un pago. '' = contado.
String _finNormCF(String? raw) {
  final s = (raw ?? '').toLowerCase().trim();
  if (s.isEmpty) return '';
  if (s.contains('cashea')) return 'Cashea';
  if (s.contains('weppa')) return 'Weppa';
  if (s.contains('krece')) return 'Krece';
  return raw!.trim();
}

String _cfFecha(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String _cfFechaHora(DateTime d) =>
    '${_cfFecha(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _cfMonto(double v, String moneda) =>
    moneda == monedaBs ? formatBolivares(v) : formatCurrency(v);

String _cfTienda(String t) => t.trim().isEmpty ? 'General (sin tienda)' : t;

String _cfIdNuevo() =>
    '${DateTime.now().microsecondsSinceEpoch}${math.Random().nextInt(999)}';

List<dynamic> _cfListaJson(dynamic v) {
  if (v == null) return [];
  if (v is List) return v;
  try {
    final d = jsonDecode(v.toString());
    return d is List ? d : [];
  } catch (_) {
    return [];
  }
}

// ── Datos compartidos por los apartados ─────────────────────────────
/// Carga UNA vez lo que necesitan los apartados de finanzas (facturas,
/// productos, IMEIs, listas, pagos de financiadoras, cuentas por pagar
/// y configuración) para no repetir las mismas descargas en cada tab.
class _DatosFinanzasCF extends ChangeNotifier {
  List<dynamic> facturasRaw = [];
  List<dynamic> productosRaw = [];
  List<dynamic> imeisRaw = [];
  List<dynamic> comprasRaw = [];
  final List<FacturaModel> facturas = [];
  final List<FacturaCF> facturasCF = [];
  final Map<String, Producto> productos = {};
  final Map<String, String> tiendaPorFacturaId = {};
  final Map<String, String> tiendaPorNroFactura = {};
  List<({String nombre, String financiadora, Map<String, double> precios})>
      listas = [];
  List<dynamic> pagosFinanciadora = [];
  List<dynamic> cuentasPagar = [];
  Map<String, dynamic> config = {};

  double tasaBcv = ConfigSistema.tasaCambio;
  double tasaDivisa = ConfigSistema.tasaBinance > 0
      ? ConfigSistema.tasaBinance
      : ConfigSistema.tasaCambio;

  bool cargando = false;
  String? error;
  DateTime? cargadoEn;
  Future<void>? _enCurso;

  TasasCF get tasas => TasasCF(tasaBcv: tasaBcv, tasaDivisa: tasaDivisa);

  void cambiarTasas({double? bcv, double? divisa}) {
    if (bcv != null && bcv > 0) tasaBcv = bcv;
    if (divisa != null && divisa > 0) tasaDivisa = divisa;
    notifyListeners();
  }

  Future<void> cargar({bool forzar = false}) {
    if (!forzar && cargadoEn != null) return Future.value();
    return _enCurso ??= _cargar().whenComplete(() => _enCurso = null);
  }

  Future<void> _cargar() async {
    cargando = true;
    error = null;
    notifyListeners();
    try {
      Future<dynamic> opcional(String r) => _Api.get(r).catchError((e) {
            debugPrint('[FinanzasCF] $r: $e');
            return null;
          });
      final res = await Future.wait([
        _Api.get('productos'),
        _Api.get('facturas'),
        _Api.get('stock_imei'),
        opcional('compras'),
        opcional('listas_precios'),
        opcional('pagos_financiadora'),
        opcional('cuentas_pagar'),
        opcional('configuracion'),
      ]);
      productosRaw = (res[0] as List?) ?? [];
      facturasRaw = (res[1] as List?) ?? [];
      imeisRaw = (res[2] as List?) ?? [];
      comprasRaw = (res[3] as List?) ?? [];
      pagosFinanciadora = (res[5] as List?) ?? [];
      cuentasPagar = (res[6] as List?) ?? [];
      config = res[7] is Map ? Map<String, dynamic>.from(res[7] as Map) : {};

      final prods = productosRaw
          .map((m) => Producto.fromMap(m as Map<String, dynamic>))
          .toList();
      productos
        ..clear()
        ..addEntries(prods.map((p) => MapEntry(p.codigo, p)));
      // Globales que usa construirFacturaModelDesdeJson para resolver
      // el producto de cada IMEI.
      catalogoGlobal = prods;
      stockImeiGlobal = imeisRaw
          .map((i) => ImeiRegistro.fromMap(i as Map<String, dynamic>))
          .toList();

      listas = [];
      for (final l in ((res[4] as List?) ?? [])) {
        if (l is! Map) continue;
        final precios = <String, double>{};
        for (final it in (l['items'] as List? ?? [])) {
          if (it is! Map) continue;
          final vals = it['valores'] as List? ?? [];
          if (vals.isEmpty || vals.first is! Map) continue;
          final p = double.tryParse(
              (vals.first as Map)['precio']?.toString() ?? '');
          if (p != null && p > 0) {
            precios[(it['producto_codigo'] ?? '').toString()] = p;
          }
        }
        listas.add((
          nombre: (l['nombre'] ?? '').toString(),
          financiadora: (l['financiadora'] ?? '').toString(),
          precios: precios,
        ));
      }

      facturas.clear();
      facturasCF.clear();
      tiendaPorFacturaId.clear();
      tiendaPorNroFactura.clear();
      for (final m in facturasRaw) {
        final mp = m as Map<String, dynamic>;
        final f = construirFacturaModelDesdeJson(mp);
        facturas.add(f);
        facturasCF.add(_aFacturaCF(f));
        tiendaPorFacturaId[(mp['id'] ?? '').toString()] = f.tienda;
        tiendaPorNroFactura[f.nroFactura] = f.tienda;
      }
      cargadoEn = DateTime.now();
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  FacturaCF _aFacturaCF(FacturaModel f) {
    final pagos = [
      for (final p in f.pagos)
        PagoClienteCF(
          monto: p.monto,
          enBolivares: esMetodoEnBolivares(p.metodo),
          tasa: p.tasaCambio ?? 0,
          esInicial: p.esInicial,
          financiadora: _finNormCF(p.financiadora),
        ),
    ];
    final fin = pagos
        .map((p) => p.financiadora)
        .firstWhere((x) => x.isNotEmpty, orElse: () => '');
    final lista = f.pagos
        .map((p) => p.nombreLista ?? '')
        .firstWhere((x) => x.isNotEmpty, orElse: () => '');
    EquipoVendidoCF eq(Producto p, String imei) {
      final cat = productos[p.codigo] ?? p;
      return EquipoVendidoCF(
        codigo: p.codigo,
        imei: imei,
        costo: cat.precioCosto,
        precioContado: cat.precioVenta,
        precioFinanciadora: fin.isEmpty
            ? null
            : precioEnListaFinanciadora(listas, fin, p.codigo,
                nombreLista: lista),
      );
    }

    return FacturaCF(
      nroFactura: f.nroFactura,
      tienda: f.tienda,
      fecha: parseFechaFlexible(f.fecha) ?? DateTime(2000),
      equipos: [
        for (final e in f.equipos) eq(e.producto, e.imei),
        for (final p in f.itemsSinImei) eq(p, ''),
      ],
      pagos: pagos,
    );
  }

  /// Ventas del período analizadas con las tasas actuales.
  List<VentaAnalizada> ventasAnalizadas(DateTime desde, DateTime hasta) {
    final t = tasas;
    return [
      for (final f in facturasCF)
        if (enRangoCF(f.fecha, desde, hasta)) analizarFactura(f, t),
    ];
  }

  /// Todos los registros JSON guardados bajo claves con [prefijo].
  Iterable<Map> _registros(String prefijo) sync* {
    for (final e in config.entries) {
      if (!e.key.startsWith(prefijo)) continue;
      for (final x in _cfListaJson(e.value)) {
        if (x is Map) yield x;
      }
    }
  }

  List<GastoCF> gastosEntre(DateTime desde, DateTime hasta) => [
        for (final m in _registros('cf_gastos_'))
          if (enRangoCF(GastoCF.fromJson(m).fecha, desde, hasta))
            GastoCF.fromJson(m),
      ];

  List<PagoNomina> pagosNominaEntre(DateTime desde, DateTime hasta) => [
        for (final m in _registros('cf_nomina_pagos_'))
          if (enRangoCF(PagoNomina.fromJson(m).fechaPago, desde, hasta))
            PagoNomina.fromJson(m),
      ];

  List<EmpleadoNomina> get empleados => [
        for (final m in _cfListaJson(config[claveNominaEmpleados]))
          if (m is Map) EmpleadoNomina.fromJson(m),
      ];

  /// Tiendas a mostrar: las configuradas y las que aparezcan en datos.
  List<String> tiendas(Iterable<String> extra) {
    final r = <String>[];
    for (final t in [...ConfigSistema.tiendas, ...extra]) {
      if (t.trim().isEmpty || r.contains(t)) continue;
      r.add(t);
    }
    return r;
  }

  /// Lee-modifica-escribe una lista JSON en `configuracion`. Se relee
  /// la clave justo antes de guardar para no pisar lo que otro equipo
  /// haya guardado mientras tanto.
  Future<void> modificarListaConfig(
      String clave, List<dynamic> Function(List<dynamic> actual) cambio) async {
    final raw = await _Api.get('configuracion');
    final fresco = raw is Map ? Map<String, dynamic>.from(raw) : config;
    final nuevo = cambio(List<dynamic>.from(_cfListaJson(fresco[clave])));
    final txt = jsonEncode(nuevo);
    await _Api.post('configuracion', {clave: txt});
    config = fresco..[clave] = txt;
    notifyListeners();
  }

  /// Entradas y salidas de dinero del período, por tienda y moneda.
  List<MovimientoCaja> movimientosCaja(DateTime desde, DateTime hasta) {
    final r = <MovimientoCaja>[];
    // Cobros a clientes: cada pago en SU moneda.
    for (final f in facturas) {
      final fecha = parseFechaFlexible(f.fecha);
      if (fecha == null || !enRangoCF(fecha, desde, hasta)) continue;
      for (final p in f.pagos) {
        r.add(MovimientoCaja(
          fecha: fecha,
          tienda: f.tienda,
          concepto: 'Cobros de ventas',
          entrada: true,
          moneda: esMetodoEnBolivares(p.metodo) ? monedaBs : monedaUsd,
          monto: p.monto,
        ));
      }
    }
    // Lo que giran las financiadoras (se registra en $).
    for (final p in pagosFinanciadora) {
      if (p is! Map) continue;
      final fecha = parseFechaFlexible(p['fecha']?.toString());
      if (fecha == null || !enRangoCF(fecha, desde, hasta)) continue;
      final marca = leerMarcaEquipoPago((p['notas'] ?? '').toString());
      final tienda = tiendaPorFacturaId[(p['factura_id'] ?? '').toString()] ??
          tiendaPorNroFactura[marca?.nroFactura ?? ''] ??
          '';
      r.add(MovimientoCaja(
        fecha: fecha,
        tienda: tienda,
        concepto: 'Pagos de financiadoras',
        entrada: true,
        moneda: monedaUsd,
        monto: double.tryParse(p['monto']?.toString() ?? '') ?? 0,
      ));
    }
    for (final g in gastosEntre(desde, hasta)) {
      r.add(MovimientoCaja(
        fecha: g.fecha,
        tienda: g.tienda,
        concepto: 'Gastos: ${g.categoria}',
        entrada: false,
        moneda: g.moneda,
        monto: g.monto,
      ));
    }
    for (final p in pagosNominaEntre(desde, hasta)) {
      r.add(MovimientoCaja(
        fecha: p.fechaPago,
        tienda: p.tienda,
        concepto: 'Nómina',
        entrada: false,
        moneda: p.moneda,
        monto: p.monto,
      ));
    }
    // Abonos a proveedores: el módulo de cuentas por pagar los guarda
    // en $ y sin tienda.
    for (final c in cuentasPagar) {
      if (c is! Map) continue;
      for (final p in (c['pagos'] as List? ?? [])) {
        if (p is! Map) continue;
        final fecha = parseFechaFlexible(p['fecha']?.toString());
        if (fecha == null || !enRangoCF(fecha, desde, hasta)) continue;
        r.add(MovimientoCaja(
          fecha: fecha,
          tienda: '',
          concepto: 'Pagos a proveedores',
          entrada: false,
          moneda: monedaUsd,
          monto: double.tryParse(p['monto']?.toString() ?? '') ?? 0,
        ));
      }
    }
    return r;
  }
}

// ── Piezas de UI comunes ────────────────────────────────────────────

/// Contenedor de un apartado: centrado y con ancho máximo para que en
/// tablet no se estire de borde a borde.
Widget _cfContenedor(List<Widget> children) => LayoutBuilder(
      builder: (context, c) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: EdgeInsets.all(c.maxWidth > 700 ? 16 : 10),
            children: children,
          ),
        ),
      ),
    );

Widget _cfAyuda(String texto) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceTintBlue,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.help_outline, color: AppColors.brandBlue, size: 18),
        const SizedBox(width: 8),
        Expanded(
            child: Text(texto,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textPrimary))),
      ]),
    );

Widget _cfKpi(String label, String valor, Color color, {String? sub}) =>
    Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: color)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(valor,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ),
        if (sub != null)
          Text(sub,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
      ]),
    );

/// Fila de indicadores que se acomoda al ancho (2 por fila en
/// teléfono, 3-4 en tablet) sin desbordar.
Widget _cfKpis(List<Widget> tiles) => LayoutBuilder(builder: (context, c) {
      final n = c.maxWidth > 900 ? 4 : (c.maxWidth > 560 ? 3 : 2);
      const sep = 8.0;
      final w = (c.maxWidth - sep * (n - 1)) / n;
      return Wrap(spacing: sep, runSpacing: sep, children: [
        for (final t in tiles) SizedBox(width: w, child: t),
      ]);
    });

Widget _cfTarjeta(String titulo, IconData icon, Color color, Widget child,
        {Widget? accion}) =>
    Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text(titulo,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 14))),
            if (accion != null) accion,
          ]),
        ),
        Padding(padding: const EdgeInsets.all(10), child: child),
      ]),
    );

/// Tabla que se desplaza horizontalmente si no cabe.
Widget _cfTabla(List<String> columnas, List<List<Widget>> filas,
        {Color color = AppColors.brandBlue, List<int> numericas = const []}) =>
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 30,
        dataRowMaxHeight: 40,
        columnSpacing: 14,
        headingRowColor:
            WidgetStateProperty.all(color.withValues(alpha: 0.08)),
        headingTextStyle: TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: color),
        dataTextStyle:
            const TextStyle(fontSize: 11.5, color: AppColors.textPrimary),
        columns: [
          for (var i = 0; i < columnas.length; i++)
            DataColumn(label: Text(columnas[i]), numeric: numericas.contains(i)),
        ],
        rows: [for (final f in filas) DataRow(cells: [for (final c in f) DataCell(c)])],
      ),
    );

Widget _cfNum(double v, {String moneda = monedaUsd, bool negrita = false}) =>
    Text(_cfMonto(v, moneda),
        style: TextStyle(
            fontWeight: negrita ? FontWeight.bold : FontWeight.normal,
            color: v < -0.004 ? AppColors.statusRed : null));

Widget _cfCargando(_DatosFinanzasCF d, Widget Function() contenido) {
  if (d.cargadoEn == null) {
    if (d.error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No se pudieron cargar los datos:\n${d.error}',
                  textAlign: TextAlign.center)));
    }
    return const Center(child: CircularProgressIndicator());
  }
  return contenido();
}

/// Selector de período desde/hasta.
class _CfSelectorRango extends StatelessWidget {
  final DateTime desde, hasta;
  final void Function(DateTime desde, DateTime hasta) onCambio;
  const _CfSelectorRango(
      {required this.desde, required this.hasta, required this.onCambio});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range, size: 18),
          label: Text('Desde ${_cfFecha(desde)}  hasta ${_cfFecha(hasta)}'),
          onPressed: () async {
            final r = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              initialDateRange: DateTimeRange(start: desde, end: hasta),
              helpText: 'Período a consultar',
            );
            if (r != null) onCambio(r.start, r.end);
          },
        ),
        TextButton(
          onPressed: () {
            final n = DateTime.now();
            onCambio(DateTime(n.year, n.month, n.day),
                DateTime(n.year, n.month, n.day));
          },
          child: const Text('Hoy'),
        ),
        TextButton(
          onPressed: () {
            final n = DateTime.now();
            onCambio(DateTime(n.year, n.month, 1),
                DateTime(n.year, n.month + 1, 0));
          },
          child: const Text('Este mes'),
        ),
      ],
    );
  }
}

/// Tasas BCV / divisa editables (compartidas por los apartados).
class _CfTasasEditor extends StatefulWidget {
  final _DatosFinanzasCF datos;
  const _CfTasasEditor(this.datos);
  @override
  State<_CfTasasEditor> createState() => _CfTasasEditorState();
}

class _CfTasasEditorState extends State<_CfTasasEditor> {
  late final TextEditingController _bcv, _div;

  @override
  void initState() {
    super.initState();
    _bcv = TextEditingController(
        text: widget.datos.tasaBcv.toStringAsFixed(2));
    _div = TextEditingController(
        text: widget.datos.tasaDivisa.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _bcv.dispose();
    _div.dispose();
    super.dispose();
  }

  Widget _campo(TextEditingController c, String label, String ayuda,
          void Function(double) onOk) =>
      SizedBox(
        width: 220,
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: label,
              helperText: ayuda,
              isDense: true,
              border: const OutlineInputBorder()),
          onSubmitted: (v) => onOk(double.tryParse(v.replaceAll(',', '.')) ?? 0),
          onChanged: (v) {
            final x = double.tryParse(v.replaceAll(',', '.'));
            if (x != null && x > 0) onOk(x);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 12, runSpacing: 8, children: [
      _campo(_bcv, 'Tasa BCV (Bs/\$)', 'A la que paga la financiadora',
          (v) => widget.datos.cambiarTasas(bcv: v)),
      _campo(_div, 'Tasa divisa / Binance (Bs/\$)',
          'A la que conviertes los Bs a dólares',
          (v) => widget.datos.cambiarTasas(divisa: v)),
    ]);
  }
}

// ════════════════════════════════════════════════════════════════════
//  EQUILIBRIO POR TIENDA
// ════════════════════════════════════════════════════════════════════
class _PanelEquilibrioCF extends StatefulWidget {
  final _DatosFinanzasCF datos;
  final DateTime desde, hasta;
  const _PanelEquilibrioCF(
      {required this.datos, required this.desde, required this.hasta});
  @override
  State<_PanelEquilibrioCF> createState() => _PanelEquilibrioCFState();
}

class _PanelEquilibrioCFState extends State<_PanelEquilibrioCF> {
  late DateTime _desde = widget.desde, _hasta = widget.hasta;

  @override
  void didUpdateWidget(covariant _PanelEquilibrioCF old) {
    super.didUpdateWidget(old);
    if (old.desde != widget.desde || old.hasta != widget.hasta) {
      _desde = widget.desde;
      _hasta = widget.hasta;
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.datos;
    return AnimatedBuilder(
      animation: d,
      builder: (context, _) => _cfCargando(d, () {
        final ventas = d.ventasAnalizadas(_desde, _hasta);
        final gastos = d.gastosEntre(_desde, _hasta);
        final tiendas = d.tiendas([
          ...ventas.map((v) => v.tienda),
          ...gastos.map((g) => g.tienda),
        ]);
        final total = calcularEquilibrio(
            tienda: 'Todas', ventas: ventas, gastos: gastos);
        final generales = gastos
            .where((g) => g.tienda.trim().isEmpty)
            .fold<double>(0, (s, g) => s + g.montoUsd);
        return _cfContenedor([
          _cfAyuda(
              'Equilibrio = lo que GANAMOS cada día menos lo que GASTAMOS. '
              '"Hoy generamos 200, gastamos 50, quedamos en 150". La ganancia '
              'de cada venta es lo que entró en dólares (cobrado + lo que debe '
              'la financiadora, convertido a divisa) menos el costo del equipo. '
              'Los gastos salen del apartado Gastos. Una tienda está en positivo '
              'cuando su ganancia acumulada cubre todos sus gastos del período.'),
          _CfSelectorRango(
              desde: _desde,
              hasta: _hasta,
              onCambio: (a, b) => setState(() {
                    _desde = a;
                    _hasta = b;
                  })),
          const SizedBox(height: 8),
          _tarjetaTienda('Todas las tiendas (consolidado)', total,
              nota: generales > 0
                  ? 'Incluye ${formatCurrency(generales)} de gastos generales '
                      '(sin tienda asignada).'
                  : null),
          for (final t in tiendas)
            _tarjetaTienda(
                t,
                calcularEquilibrio(
                    tienda: t,
                    ventas: ventas.where((v) => v.tienda == t),
                    gastos: gastos.where((g) => g.tienda == t))),
        ]);
      }),
    );
  }

  Widget _tarjetaTienda(String nombre, EquilibrioTienda e, {String? nota}) {
    final color = e.enPositivo ? AppColors.statusGreen : AppColors.statusRed;
    return _cfTarjeta(
      nombre,
      Icons.storefront,
      AppColors.brandBlue,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _cfKpis([
          _cfKpi('Ventas (en divisa)', formatCurrency(e.totalVentas),
              AppColors.brandBlue),
          _cfKpi('Ganancia', formatCurrency(e.totalGanancia),
              AppColors.statusGreen),
          _cfKpi('Gastos', formatCurrency(e.totalGastos), Colors.deepOrange),
          _cfKpi('Quedamos en', formatCurrency(e.resultado), color),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(e.enPositivo ? Icons.check_circle : Icons.warning_amber,
              color: color, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              e.enPositivo
                  ? (e.diaCubreGastos != null
                      ? 'En positivo: cubrió sus gastos el ${_cfFecha(e.diaCubreGastos!)}.'
                      : 'En positivo.')
                  : 'Todavía no cubre sus gastos: faltan ${formatCurrency(e.faltante)}.',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        if (nota != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(nota,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
          ),
        if (e.dias.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Ver día por día',
                style: TextStyle(fontSize: 13)),
            children: [
              _cfTabla(
                ['Día', 'Ventas', 'Ganancia', 'Gastos', 'Quedamos en',
                  'Acumulado'],
                [
                  for (final x in e.dias)
                    [
                      Text(_cfFecha(x.dia)),
                      _cfNum(x.ventas),
                      _cfNum(x.ganancia),
                      _cfNum(x.gastos),
                      _cfNum(x.resultado, negrita: true),
                      _cfNum(x.acumulado),
                    ],
                ],
                numericas: const [1, 2, 3, 4, 5],
              ),
            ],
          ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  GANANCIA REAL Y DIFERENCIAL CAMBIARIO
// ════════════════════════════════════════════════════════════════════
class _PanelGananciaRealCF extends StatefulWidget {
  final _DatosFinanzasCF datos;
  final DateTime desde, hasta;
  const _PanelGananciaRealCF(
      {required this.datos, required this.desde, required this.hasta});
  @override
  State<_PanelGananciaRealCF> createState() => _PanelGananciaRealCFState();
}

class _PanelGananciaRealCFState extends State<_PanelGananciaRealCF> {
  late DateTime _desde = widget.desde, _hasta = widget.hasta;

  @override
  void didUpdateWidget(covariant _PanelGananciaRealCF old) {
    super.didUpdateWidget(old);
    if (old.desde != widget.desde || old.hasta != widget.hasta) {
      _desde = widget.desde;
      _hasta = widget.hasta;
    }
  }

  List<Widget> _filaResumen(String nombre, ResumenGanancia r) => [
        Text(nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('${r.unidades}'),
        _cfNum(r.cobradoEnDivisa),
        _cfNum(r.financiadoBcv),
        _cfNum(r.financiadoEnDivisa),
        _cfNum(r.valorContado),
        _cfNum(r.diferencialCambiario, negrita: true),
      ];

  @override
  Widget build(BuildContext context) {
    final d = widget.datos;
    return AnimatedBuilder(
      animation: d,
      builder: (context, _) => _cfCargando(d, () {
        final ventas = d.ventasAnalizadas(_desde, _hasta);
        final total = totalGanancias(ventas);
        final porFin = agruparGanancias(
            ventas, (v) => v.esFinanciada ? v.financiadora : 'De contado');
        final financiadas = ventas.where((v) => v.esFinanciada).toList();
        final porDia = agruparGanancias(financiadas, (v) => fechaIsoCF(v.fecha));
        final diasOrden = porDia.keys.toList()..sort();
        final porTienda = agruparGanancias(ventas, (v) => v.tienda);
        final gastos = d.gastosEntre(_desde, _hasta);
        double gastosDe(String t) => gastos
            .where((g) => g.tienda == t)
            .fold<double>(0, (s, g) => s + g.montoUsd);
        final gastosTotal =
            gastos.fold<double>(0, (s, g) => s + g.montoUsd);
        final tiendas = d.tiendas(porTienda.keys);
        const colsDif = [
          '', 'Equipos', 'Cobrado al cliente\n(en divisa)',
          'Debe la financ.\n(\$ BCV)', 'Financiado\n(en divisa)',
          'Valor de\ncontado', 'Diferencial\ncambiario',
        ];

        return _cfContenedor([
          _cfAyuda(
              'GANANCIA REAL = precio de CONTADO − costo, como si toda venta '
              'fuera de contado (equipo de costo 100, de contado 120, vendido '
              'financiado en 140: la ganancia real es 20, no 40).\n'
              'DIFERENCIAL CAMBIARIO = lo que entró de verdad en dólares − el '
              'valor de contado: iniciales convertidas a divisa + lo que paga la '
              'financiadora convertido a divisa (paga en Bs a tasa BCV: \$1000 '
              'pueden ser 850) − valor de contado de esos equipos.\n'
              'Precio de contado y costo salen del inventario; lo que debe la '
              'financiadora sale de su lista de precios (igual que el Reporte '
              'por Financiadora).'),
          _CfSelectorRango(
              desde: _desde,
              hasta: _hasta,
              onCambio: (a, b) => setState(() {
                    _desde = a;
                    _hasta = b;
                  })),
          const SizedBox(height: 8),
          _CfTasasEditor(d),
          const SizedBox(height: 10),
          _cfKpis([
            _cfKpi('Ganancia real (contado − costo)',
                formatCurrency(total.gananciaReal), AppColors.statusGreen,
                sub: '${total.unidades} equipos/artículos'),
            _cfKpi('Diferencial cambiario',
                formatCurrency(total.diferencialCambiario), Colors.indigo,
                sub: 'financiamiento y tasa'),
            _cfKpi('Ganancia total', formatCurrency(total.gananciaTotal),
                AppColors.brandBlue,
                sub: 'real + diferencial'),
            _cfKpi('Costo de lo vendido', formatCurrency(total.costo),
                Colors.deepOrange),
          ]),
          _cfTarjeta(
            'Diferencial por financiadora',
            Icons.currency_exchange,
            Colors.indigo,
            _cfTabla(colsDif, [
              for (final e in porFin.entries) _filaResumen(e.key, e.value),
              _filaResumen('TOTAL', total),
            ], color: Colors.indigo, numericas: const [1, 2, 3, 4, 5, 6]),
          ),
          _cfTarjeta(
            'Diferencial día por día (ventas financiadas)',
            Icons.calendar_view_day,
            Colors.indigo,
            diasOrden.isEmpty
                ? const Text('No hay ventas financiadas en el período.')
                : _cfTabla(colsDif.map((c) => c.isEmpty ? 'Día' : c).toList(), [
                    for (final k in diasOrden)
                      _filaResumen(
                          _cfFecha(parseFechaCF(k) ?? DateTime(2000)),
                          porDia[k]!),
                  ], color: Colors.indigo, numericas: const [1, 2, 3, 4, 5, 6]),
          ),
          _cfTarjeta(
            'Balance neto por tienda',
            Icons.account_balance_wallet,
            AppColors.statusGreen,
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text(
                  'Ventas cobradas en divisa + montos financiados − costo de '
                  'los equipos − gastos de la tienda.',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              _cfTabla(
                ['Tienda', 'Ventas en\ndivisa', '+ Financiado', '− Costo\nequipos',
                  '− Gastos', '= Balance\nneto'],
                [
                  for (final t in tiendas)
                    () {
                      final r = porTienda[t] ?? ResumenGanancia();
                      final g = gastosDe(t);
                      return [
                        Text(t),
                        _cfNum(r.cobradoEnDivisa),
                        _cfNum(r.financiadoEnDivisa),
                        _cfNum(r.costo),
                        _cfNum(g),
                        _cfNum(r.balanceNeto(g), negrita: true),
                      ];
                    }(),
                  if (gastosDe('') > 0)
                    [
                      const Text('Gastos generales'),
                      const Text('-'), const Text('-'), const Text('-'),
                      _cfNum(gastosDe('')),
                      _cfNum(-gastosDe(''), negrita: true),
                    ],
                  [
                    const Text('TODAS', style: TextStyle(fontWeight: FontWeight.bold)),
                    _cfNum(total.cobradoEnDivisa, negrita: true),
                    _cfNum(total.financiadoEnDivisa, negrita: true),
                    _cfNum(total.costo, negrita: true),
                    _cfNum(gastosTotal, negrita: true),
                    _cfNum(total.balanceNeto(gastosTotal), negrita: true),
                  ],
                ],
                color: AppColors.statusGreen,
                numericas: const [1, 2, 3, 4, 5],
              ),
            ]),
          ),
        ]);
      }),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  FLUJO DE CAJA
// ════════════════════════════════════════════════════════════════════
class _PanelFlujoCajaCF extends StatefulWidget {
  final _DatosFinanzasCF datos;
  final DateTime desde, hasta;
  const _PanelFlujoCajaCF(
      {required this.datos, required this.desde, required this.hasta});
  @override
  State<_PanelFlujoCajaCF> createState() => _PanelFlujoCajaCFState();
}

class _PanelFlujoCajaCFState extends State<_PanelFlujoCajaCF> {
  late DateTime _desde = widget.desde, _hasta = widget.hasta;

  @override
  void didUpdateWidget(covariant _PanelFlujoCajaCF old) {
    super.didUpdateWidget(old);
    if (old.desde != widget.desde || old.hasta != widget.hasta) {
      _desde = widget.desde;
      _hasta = widget.hasta;
    }
  }

  List<Widget> _fila(String nombre, TotalesCaja t, {bool negrita = false}) => [
        Text(nombre,
            style: TextStyle(
                fontWeight: negrita ? FontWeight.bold : FontWeight.w600)),
        _cfNum(t.entradasUsd, negrita: negrita),
        _cfNum(t.entradasBs, moneda: monedaBs, negrita: negrita),
        _cfNum(t.salidasUsd, negrita: negrita),
        _cfNum(t.salidasBs, moneda: monedaBs, negrita: negrita),
        _cfNum(t.netoUsd, negrita: true),
        _cfNum(t.netoBs, moneda: monedaBs, negrita: true),
      ];

  static const _cols = [
    '', 'Entradas \$', 'Entradas Bs', 'Salidas \$', 'Salidas Bs',
    'Neto \$', 'Neto Bs',
  ];

  @override
  Widget build(BuildContext context) {
    final d = widget.datos;
    return AnimatedBuilder(
      animation: d,
      builder: (context, _) => _cfCargando(d, () {
        final flujo = calcularFlujoCaja(d.movimientosCaja(_desde, _hasta));
        final c = flujo.consolidado;
        final tiendas = d.tiendas(flujo.porTienda.keys);
        if (flujo.porTienda.containsKey('')) tiendas.add('');
        return _cfContenedor([
          _cfAyuda(
              'Cuánto dinero ENTRÓ y SALIÓ en el período, por tienda y en '
              'total. Los dólares y los bolívares van en columnas separadas '
              '(nunca se suman sin convertir).\n'
              'Entradas: cobros de ventas (cada pago en su moneda) y pagos '
              'que hacen las financiadoras. Salidas: gastos, nómina y abonos a '
              'proveedores (cuentas por pagar, sin tienda: van en "General").'),
          _CfSelectorRango(
              desde: _desde,
              hasta: _hasta,
              onCambio: (a, b) => setState(() {
                    _desde = a;
                    _hasta = b;
                  })),
          const SizedBox(height: 8),
          _cfKpis([
            _cfKpi('Entró en \$', formatCurrency(c.entradasUsd),
                AppColors.statusGreen),
            _cfKpi('Entró en Bs', formatBolivares(c.entradasBs),
                AppColors.statusGreen),
            _cfKpi('Salió en \$', formatCurrency(c.salidasUsd),
                AppColors.statusRed),
            _cfKpi('Salió en Bs', formatBolivares(c.salidasBs),
                AppColors.statusRed),
            _cfKpi('Neto \$', formatCurrency(c.netoUsd), AppColors.brandBlue),
            _cfKpi('Neto Bs', formatBolivares(c.netoBs), AppColors.brandBlue,
                sub: 'Referencia: todo junto ≈ '
                    '${formatCurrency(c.netoEquivUsd(d.tasaBcv))} '
                    '(Bs a tasa ${d.tasaBcv.toStringAsFixed(2)})'),
          ]),
          _cfTarjeta(
            'Por tienda',
            Icons.storefront,
            AppColors.brandBlue,
            _cfTabla(
                _cols.map((x) => x.isEmpty ? 'Tienda' : x).toList(),
                [
                  for (final t in tiendas)
                    _fila(_cfTienda(t), flujo.porTienda[t] ?? TotalesCaja()),
                  _fila('TODAS', c, negrita: true),
                ],
                numericas: const [1, 2, 3, 4, 5, 6]),
          ),
          for (final t in tiendas)
            if (flujo.porTienda[t] != null)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ExpansionTile(
                  title: Text('Detalle: ${_cfTienda(t)}',
                      style: const TextStyle(fontSize: 13)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: _cfTabla(
                        _cols.map((x) => x.isEmpty ? 'Concepto' : x).toList(),
                        [
                          for (final e
                              in flujo.porTienda[t]!.porConcepto.entries)
                            _fila(e.key, e.value),
                        ],
                        numericas: const [1, 2, 3, 4, 5, 6],
                      ),
                    ),
                  ],
                ),
              ),
        ]);
      }),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  GASTOS (guardados por mes, con tienda y categoría)
// ════════════════════════════════════════════════════════════════════
class _PanelGastosCF extends StatefulWidget {
  final _DatosFinanzasCF datos;
  final int anio, mes;
  /// Avisa al padre para que Resultados use los gastos guardados.
  final VoidCallback onCambio;
  const _PanelGastosCF(
      {required this.datos,
      required this.anio,
      required this.mes,
      required this.onCambio});
  @override
  State<_PanelGastosCF> createState() => _PanelGastosCFState();
}

class _PanelGastosCFState extends State<_PanelGastosCF> {
  String? _filtroTienda; // null = todas
  bool _guardando = false;

  DateTime get _desde => DateTime(widget.anio, widget.mes, 1);
  DateTime get _hasta => DateTime(widget.anio, widget.mes + 1, 0);

  Future<void> _guardar(Future<void> Function() accion, String ok) async {
    setState(() => _guardando = true);
    try {
      await accion();
      widget.onCambio();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ok), backgroundColor: AppColors.statusGreen));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo guardar: $e'),
            backgroundColor: AppColors.statusRed));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _dialogoGasto() async {
    final d = widget.datos;
    final hoy = DateTime.now();
    var fecha = (hoy.year == widget.anio && hoy.month == widget.mes)
        ? hoy
        : DateTime(widget.anio, widget.mes, 1);
    var tienda = _filtroTienda ?? tiendaUsuarioActual();
    var categoria = categoriasGastoCF.first;
    var moneda = monedaUsd;
    final concepto = TextEditingController();
    final monto = TextEditingController();
    final tiendas = d.tiendas(const []);
    if (!tiendas.contains(tienda)) tienda = '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Registrar gasto'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: categoria,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Clasificación'),
                  items: [
                    for (final c in categoriasGastoCF)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setD(() => categoria = v ?? categoria),
                ),
                TextField(
                  controller: concepto,
                  decoration: const InputDecoration(
                      labelText: 'Concepto (ej. alquiler, luz, papelería)'),
                ),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: monto,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(labelText: 'Monto'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: moneda,
                    items: const [
                      DropdownMenuItem(value: monedaUsd, child: Text('\$')),
                      DropdownMenuItem(value: monedaBs, child: Text('Bs')),
                    ],
                    onChanged: (v) => setD(() => moneda = v ?? moneda),
                  ),
                ]),
                DropdownButtonFormField<String>(
                  initialValue: tienda,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tienda'),
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text('General (toda la empresa)')),
                    for (final t in tiendas)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => setD(() => tienda = v ?? ''),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 18),
                  label: Text('Fecha: ${_cfFecha(fecha)}'),
                  onPressed: () async {
                    final f = await showDatePicker(
                        context: ctx,
                        initialDate: fecha,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now()
                            .add(const Duration(days: 365)));
                    if (f != null) setD(() => fecha = f);
                  },
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar')),
          ],
        ),
      ),
    );
    final valor = double.tryParse(monto.text.replaceAll(',', '.')) ?? 0;
    if (ok != true || valor <= 0) return;
    final g = GastoCF(
      id: _cfIdNuevo(),
      fecha: fecha,
      tienda: tienda,
      categoria: categoria,
      concepto: concepto.text.trim(),
      monto: valor,
      moneda: moneda,
      tasa: ConfigSistema.tasaCambio,
      registradoPor: usuarioSesion?.nombre ?? '',
      registradoEn: DateTime.now().toIso8601String(),
    );
    await _guardar(
        () => d.modificarListaConfig(claveGastosMes(fecha.year, fecha.month),
            (l) => l..add(g.toJson())),
        'Gasto registrado');
  }

  Future<void> _eliminar(GastoCF g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar gasto'),
        content: Text('¿Eliminar "${g.concepto}" por ${_cfMonto(g.monto, g.moneda)}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    await _guardar(
        () => widget.datos.modificarListaConfig(
            claveGastosMes(g.fecha.year, g.fecha.month),
            (l) => l..removeWhere((x) => x is Map && x['id'] == g.id)),
        'Gasto eliminado');
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.datos;
    return AnimatedBuilder(
      animation: d,
      builder: (context, _) => _cfCargando(d, () {
        final todos = d.gastosEntre(_desde, _hasta)
          ..sort((a, b) => a.fecha.compareTo(b.fecha));
        final gastos = _filtroTienda == null
            ? todos
            : todos.where((g) => g.tienda == _filtroTienda).toList();
        final porCat = gastosPorCategoria(gastos);
        final total = gastos.fold<double>(0, (s, g) => s + g.montoUsd);
        final tiendas = d.tiendas(todos.map((g) => g.tienda));
        return _cfContenedor([
          _cfAyuda(
              'Anota aquí cada gasto del mes (alquiler, luz, sueldos fijos, '
              'papelería...) con su tienda y su clasificación. Se guardan en '
              'el sistema y se usan en Equilibrio, Ganancia real (balance neto), '
              'Resultados y Flujo de caja. Un gasto "General" es de toda la '
              'empresa y solo cuenta en los totales consolidados.'),
          Wrap(spacing: 8, runSpacing: 6, children: [
            ChoiceChip(
              label: const Text('Todas'),
              selected: _filtroTienda == null,
              onSelected: (_) => setState(() => _filtroTienda = null),
            ),
            ChoiceChip(
              label: const Text('General'),
              selected: _filtroTienda == '',
              onSelected: (_) => setState(() => _filtroTienda = ''),
            ),
            for (final t in tiendas)
              ChoiceChip(
                label: Text(t),
                selected: _filtroTienda == t,
                onSelected: (_) => setState(() => _filtroTienda = t),
              ),
          ]),
          const SizedBox(height: 8),
          _cfKpis([
            _cfKpi('Total del mes (en \$)', formatCurrency(total),
                Colors.deepOrange,
                sub: 'Bs convertidos a la tasa del día del gasto'),
            for (final c in categoriasGastoCF)
              _cfKpi(c, formatCurrency(porCat[c] ?? 0), AppColors.brandBlue),
          ]),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              icon: _guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add),
              label: const Text('Registrar gasto'),
              onPressed: _guardando ? null : _dialogoGasto,
            ),
          ),
          for (final c in categoriasGastoCF)
            if (gastos.any((g) => g.categoria == c ||
                (c == 'Otros' && !categoriasGastoCF.contains(g.categoria))))
              _cfTarjeta(
                '$c — ${formatCurrency(porCat[c] ?? 0)}',
                Icons.receipt_long,
                Colors.deepOrange,
                Column(children: [
                  for (final g in gastos.where((g) => g.categoria == c ||
                      (c == 'Otros' &&
                          !categoriasGastoCF.contains(g.categoria))))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(g.concepto.isEmpty ? '(sin concepto)' : g.concepto),
                      subtitle: Text(
                          '${_cfFecha(g.fecha)} · ${_cfTienda(g.tienda)}'
                          '${g.registradoPor.isNotEmpty ? ' · registró ${g.registradoPor}' : ''}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_cfMonto(g.monto, g.moneda),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red, size: 20),
                          onPressed: _guardando ? null : () => _eliminar(g),
                        ),
                      ]),
                    ),
                ]),
              ),
          if (gastos.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                  child: Text('Sin gastos registrados este mes.',
                      style: TextStyle(color: Colors.grey))),
            ),
        ]);
      }),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  NÓMINA: empleados desde los usuarios y pagos con registro
// ════════════════════════════════════════════════════════════════════
class _PanelNominaCF extends StatefulWidget {
  final _DatosFinanzasCF datos;
  final int anio, mes;
  /// Tabla de costo laboral estimado (aportes de ley) que ya existía.
  final Widget pie;
  final VoidCallback onCambio;
  const _PanelNominaCF(
      {required this.datos,
      required this.anio,
      required this.mes,
      required this.pie,
      required this.onCambio});
  @override
  State<_PanelNominaCF> createState() => _PanelNominaCFState();
}

class _PanelNominaCFState extends State<_PanelNominaCF> {
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    // Los usuarios se refrescan para que salgan TODOS (antes en nómina
    // solo aparecían los vendedores que tenían ventas en el mes).
    _Api.get('usuarios').then((raw) {
      if (raw is! List) return;
      usuariosSistema = UsuarioMaestro.ocultar<Usuario>(
          raw.map((m) => Usuario.fromMap(m)).toList(), (u) => u.correo);
      if (mounted) setState(() {});
    }).catchError((e) {
      debugPrint('[NominaCF] usuarios: $e');
    });
  }

  Future<void> _guardar(Future<void> Function() accion, String ok) async {
    setState(() => _guardando = true);
    try {
      await accion();
      widget.onCambio();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ok), backgroundColor: AppColors.statusGreen));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo guardar: $e'),
            backgroundColor: AppColors.statusRed));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Aplica un cambio a la lista de empleados guardada (releída del
  /// servidor justo antes, para no pisar cambios de otro equipo).
  Future<void> _cambiarEmpleados(
      void Function(List<EmpleadoNomina> lista) cambio, String ok) {
    return _guardar(
        () => widget.datos.modificarListaConfig(claveNominaEmpleados, (l) {
              final lista = [
                for (final m in l)
                  if (m is Map) EmpleadoNomina.fromJson(m),
              ];
              cambio(lista);
              return [for (final e in lista) e.toJson()];
            }),
        ok);
  }

  Future<void> _agregarTodos() async {
    var agregados = 0;
    await _cambiarEmpleados((lista) {
      agregados = agregarUsuariosANomina(lista, [
        for (final u in usuariosSistema)
          (id: u.id, nombre: u.nombre, rol: u.rol, tienda: u.tienda,
              sueldo: u.sueldoBase),
      ]);
    }, 'Usuarios agregados a la nómina');
    if (mounted && agregados == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Todos los usuarios ya estaban en la nómina.')));
    }
  }

  Future<void> _dialogoEmpleado({EmpleadoNomina? editar}) async {
    final d = widget.datos;
    final yaEstan = d.empleados;
    Usuario? usuario = editar?.usuarioId == null
        ? null
        : usuariosSistema.where((u) => u.id == editar!.usuarioId).firstOrNull;
    var externo = editar != null && editar.usuarioId == null;
    final nombre = TextEditingController(text: editar?.nombre ?? '');
    final cargo = TextEditingController(text: editar?.cargo ?? '');
    final sueldo = TextEditingController(
        text: editar == null || editar.sueldo == 0
            ? ''
            : editar.sueldo.toStringAsFixed(2));
    var tienda = editar?.tienda ?? '';
    var moneda = editar?.moneda ?? monedaUsd;
    final tiendas = d.tiendas([if (tienda.isNotEmpty) tienda]);
    final disponibles = usuariosSistema
        .where((u) =>
            u.id == editar?.usuarioId ||
            !yaEstan.any((e) => e.esMismo(usuarioId: u.id, nombre: u.nombre)))
        .toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(editar == null ? 'Agregar empleado' : 'Editar empleado'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (editar == null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Persona sin usuario en el sistema'),
                    value: externo,
                    onChanged: (v) => setD(() => externo = v),
                  ),
                if (!externo)
                  DropdownButtonFormField<int>(
                    initialValue: usuario?.id,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Usuario del sistema'),
                    items: [
                      for (final u in disponibles)
                        if (u.id != null)
                          DropdownMenuItem(
                              value: u.id,
                              child: Text('${u.nombre} · ${u.rol}',
                                  overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: editar != null
                        ? null
                        : (id) => setD(() {
                              usuario = usuariosSistema
                                  .where((u) => u.id == id)
                                  .firstOrNull;
                              if (usuario != null) {
                                nombre.text = usuario!.nombre;
                                if (cargo.text.isEmpty) cargo.text = usuario!.rol;
                                if (sueldo.text.isEmpty &&
                                    usuario!.sueldoBase > 0) {
                                  sueldo.text =
                                      usuario!.sueldoBase.toStringAsFixed(2);
                                }
                                if (usuario!.tienda.isNotEmpty &&
                                    tiendas.contains(usuario!.tienda)) {
                                  tienda = usuario!.tienda;
                                }
                              }
                            }),
                  ),
                if (externo)
                  TextField(
                    controller: nombre,
                    decoration:
                        const InputDecoration(labelText: 'Nombre completo'),
                  ),
                TextField(
                  controller: cargo,
                  decoration: const InputDecoration(labelText: 'Cargo'),
                ),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: sueldo,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Sueldo mensual'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: moneda,
                    items: const [
                      DropdownMenuItem(value: monedaUsd, child: Text('\$')),
                      DropdownMenuItem(value: monedaBs, child: Text('Bs')),
                    ],
                    onChanged: (v) => setD(() => moneda = v ?? moneda),
                  ),
                ]),
                DropdownButtonFormField<String>(
                  initialValue: tiendas.contains(tienda) ? tienda : '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Tienda'),
                  items: [
                    const DropdownMenuItem(
                        value: '', child: Text('General (sin tienda)')),
                    for (final t in tiendas)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) => setD(() => tienda = v ?? ''),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final nom = (externo ? nombre.text : (usuario?.nombre ?? nombre.text)).trim();
    if (nom.isEmpty) return;
    final nuevo = EmpleadoNomina(
      usuarioId: externo ? null : usuario?.id,
      nombre: nom,
      cargo: cargo.text.trim(),
      tienda: tienda,
      sueldo: double.tryParse(sueldo.text.replaceAll(',', '.')) ?? 0,
      moneda: moneda,
    );
    await _cambiarEmpleados((lista) {
      if (editar != null) {
        lista.removeWhere((e) => e.esMismo(
            usuarioId: editar.usuarioId, nombre: editar.nombre));
      } else if (lista
          .any((e) => e.esMismo(usuarioId: nuevo.usuarioId, nombre: nom))) {
        return;
      }
      lista.add(nuevo);
    }, editar == null ? 'Empleado agregado' : 'Empleado actualizado');
  }

  Future<void> _quitarEmpleado(EmpleadoNomina e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar de la nómina'),
        content: Text('¿Quitar a ${e.nombre} de la nómina? '
            'Sus pagos ya registrados se conservan en el historial.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Quitar')),
        ],
      ),
    );
    if (ok != true) return;
    await _cambiarEmpleados(
        (l) => l.removeWhere(
            (x) => x.esMismo(usuarioId: e.usuarioId, nombre: e.nombre)),
        'Empleado quitado');
  }

  Future<void> _dialogoPago({EmpleadoNomina? empleado}) async {
    final empleados = widget.datos.empleados;
    if (empleados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Primero agrega empleados a la nómina.')));
      return;
    }
    var emp = empleado ?? empleados.first;
    var concepto = conceptosPagoNomina.first;
    var moneda = emp.moneda;
    final metodos = ConfigSistema.metodossPago;
    var metodo = metodos.isNotEmpty ? metodos.first : '';
    var fecha = DateTime.now();
    final monto = TextEditingController(
        text: emp.sueldo > 0 ? emp.sueldo.toStringAsFixed(2) : '');
    final notas = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Registrar pago de nómina'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<int>(
                  initialValue: empleados.indexOf(
                      empleados.firstWhere((e) => e.esMismo(
                          usuarioId: emp.usuarioId, nombre: emp.nombre),
                          orElse: () => empleados.first)),
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: '¿A quién se le paga?'),
                  items: [
                    for (var i = 0; i < empleados.length; i++)
                      DropdownMenuItem(
                          value: i,
                          child: Text(
                              '${empleados[i].nombre}'
                              '${empleados[i].cargo.isNotEmpty ? ' · ${empleados[i].cargo}' : ''}',
                              overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (i) => setD(() {
                    emp = empleados[i ?? 0];
                    moneda = emp.moneda;
                    if (emp.sueldo > 0) {
                      monto.text = emp.sueldo.toStringAsFixed(2);
                    }
                  }),
                ),
                DropdownButtonFormField<String>(
                  initialValue: concepto,
                  decoration: const InputDecoration(labelText: 'Concepto'),
                  items: [
                    for (final c in conceptosPagoNomina)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setD(() => concepto = v ?? concepto),
                ),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: monto,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(labelText: 'Monto'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: moneda,
                    items: const [
                      DropdownMenuItem(value: monedaUsd, child: Text('\$')),
                      DropdownMenuItem(value: monedaBs, child: Text('Bs')),
                    ],
                    onChanged: (v) => setD(() => moneda = v ?? moneda),
                  ),
                ]),
                if (metodos.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: metodo,
                    isExpanded: true,
                    decoration:
                        const InputDecoration(labelText: 'Método de pago'),
                    items: [
                      for (final m in metodos)
                        DropdownMenuItem(value: m, child: Text(m)),
                    ],
                    onChanged: (v) => setD(() => metodo = v ?? metodo),
                  ),
                TextField(
                  controller: notas,
                  decoration:
                      const InputDecoration(labelText: 'Notas (opcional)'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 18),
                  label: Text('Fecha del pago: ${_cfFecha(fecha)}'),
                  onPressed: () async {
                    final f = await showDatePicker(
                        context: ctx,
                        initialDate: fecha,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now()
                            .add(const Duration(days: 365)));
                    if (f != null) setD(() => fecha = f);
                  },
                ),
                const SizedBox(height: 6),
                Text(
                    'Quedará registrado por: ${usuarioSesion?.nombre ?? '-'}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Registrar pago')),
          ],
        ),
      ),
    );
    final valor = double.tryParse(monto.text.replaceAll(',', '.')) ?? 0;
    if (ok != true || valor <= 0) return;
    final p = PagoNomina(
      id: _cfIdNuevo(),
      empleado: emp.nombre,
      usuarioId: emp.usuarioId,
      tienda: emp.tienda,
      concepto: concepto,
      monto: valor,
      moneda: moneda,
      tasa: ConfigSistema.tasaCambio,
      metodo: metodo,
      fechaPago: fecha,
      registradoPor: usuarioSesion?.nombre ?? '',
      registradoEn: DateTime.now(),
      notas: notas.text.trim(),
    );
    await _guardar(
        () => widget.datos.modificarListaConfig(
            claveNominaPagosMes(fecha.year, fecha.month),
            (l) => l..add(p.toJson())),
        'Pago registrado');
  }

  Future<void> _eliminarPago(PagoNomina p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar pago'),
        content: Text('¿Eliminar el pago de ${_cfMonto(p.monto, p.moneda)} '
            'a ${p.empleado}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    await _guardar(
        () => widget.datos.modificarListaConfig(
            claveNominaPagosMes(p.fechaPago.year, p.fechaPago.month),
            (l) => l..removeWhere((x) => x is Map && x['id'] == p.id)),
        'Pago eliminado');
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.datos;
    return AnimatedBuilder(
      animation: d,
      builder: (context, _) => _cfCargando(d, () {
        final empleados = d.empleados;
        final pagos = d.pagosNominaEntre(DateTime(widget.anio, widget.mes, 1),
            DateTime(widget.anio, widget.mes + 1, 0))
          ..sort((a, b) => b.registradoEn.compareTo(a.registradoEn));
        final pagadoPor = totalPagadoPorEmpleado(pagos);
        final totalPagado =
            pagos.fold<double>(0, (s, p) => s + p.montoUsd);
        final sinNomina = usuariosSistema
            .where((u) => !empleados
                .any((e) => e.esMismo(usuarioId: u.id, nombre: u.nombre)))
            .length;
        return _cfContenedor([
          _cfAyuda(
              'Cómo funciona la nómina:\n'
              '1) "Agregar empleado": elige a la persona de la lista de '
              'USUARIOS del sistema (o márcala como persona sin usuario) y '
              'ponle cargo, tienda y sueldo. "Agregar todos los usuarios" los '
              'trae a todos de una vez.\n'
              '2) "Registrar pago": eliges A QUIÉN le pagas, el monto y la '
              'fecha. El sistema guarda automáticamente QUIÉN registró el pago '
              '(el usuario que inició sesión) y cuándo. Todo queda en el '
              'historial del mes y suma en Flujo de caja.'),
          _cfKpis([
            _cfKpi('Empleados', '${empleados.length}', Colors.purple,
                sub: sinNomina > 0
                    ? '$sinNomina usuario(s) aún sin agregar'
                    : 'todos los usuarios están'),
            _cfKpi('Pagado este mes (en \$)', formatCurrency(totalPagado),
                Colors.purple,
                sub: '${pagos.length} pago(s)'),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Agregar empleado'),
              onPressed: _guardando ? null : () => _dialogoEmpleado(),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.group_add),
              label: const Text('Agregar todos los usuarios'),
              onPressed: _guardando || sinNomina == 0 ? null : _agregarTodos,
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Registrar pago'),
              onPressed: _guardando ? null : () => _dialogoPago(),
            ),
          ]),
          _cfTarjeta(
            'Empleados',
            Icons.badge_outlined,
            Colors.purple,
            empleados.isEmpty
                ? const Text('Todavía no hay empleados en la nómina.')
                : Column(children: [
                    for (final e in empleados)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                            e.usuarioId != null
                                ? Icons.account_circle
                                : Icons.person_outline,
                            color: Colors.purple),
                        title: Text(e.nombre),
                        subtitle: Text(
                            '${e.cargo.isEmpty ? '-' : e.cargo} · ${_cfTienda(e.tienda)}'
                            ' · Sueldo ${_cfMonto(e.sueldo, e.moneda)}'
                            '\nPagado este mes: ${formatCurrency(pagadoPor[e.nombre] ?? 0)}'),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'pagar') _dialogoPago(empleado: e);
                            if (v == 'editar') _dialogoEmpleado(editar: e);
                            if (v == 'quitar') _quitarEmpleado(e);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'pagar', child: Text('Registrar pago')),
                            PopupMenuItem(value: 'editar', child: Text('Editar')),
                            PopupMenuItem(
                                value: 'quitar', child: Text('Quitar')),
                          ],
                        ),
                      ),
                  ]),
          ),
          _cfTarjeta(
            'Historial de pagos del mes',
            Icons.history,
            Colors.purple,
            pagos.isEmpty
                ? const Text('No hay pagos registrados este mes.')
                : Column(children: [
                    for (final p in pagos)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '${p.empleado} — ${p.concepto}: ${_cfMonto(p.monto, p.moneda)}'),
                        subtitle: Text(
                            'Pagado el ${_cfFecha(p.fechaPago)}'
                            '${p.metodo.isNotEmpty ? ' · ${p.metodo}' : ''}'
                            ' · ${_cfTienda(p.tienda)}'
                            '\nRegistrado por ${p.registradoPor.isEmpty ? '-' : p.registradoPor}'
                            ' el ${_cfFechaHora(p.registradoEn)}'
                            '${p.notas.isNotEmpty ? '\n${p.notas}' : ''}'),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red, size: 20),
                          onPressed:
                              _guardando ? null : () => _eliminarPago(p),
                        ),
                      ),
                  ]),
          ),
          widget.pie,
        ]);
      }),
    );
  }
}

/// Solo para pruebas: arma un apartado de finanzas con datos en memoria
/// (sin servidor) para verificar que se dibuja sin desbordes.
@visibleForTesting
Widget panelFinanzasDePrueba(String cual,
    {List<FacturaCF> facturas = const [],
    Map<String, dynamic> config = const {},
    required DateTime desde,
    required DateTime hasta}) {
  final d = _DatosFinanzasCF()
    ..facturasCF.addAll(facturas)
    ..config = Map<String, dynamic>.from(config)
    ..cargadoEn = DateTime.now();
  switch (cual) {
    case 'equilibrio':
      return _PanelEquilibrioCF(datos: d, desde: desde, hasta: hasta);
    case 'ganancia':
      return _PanelGananciaRealCF(datos: d, desde: desde, hasta: hasta);
    case 'flujo':
      return _PanelFlujoCajaCF(datos: d, desde: desde, hasta: hasta);
    case 'gastos':
      return _PanelGastosCF(
          datos: d, anio: desde.year, mes: desde.month, onCambio: () {});
    default:
      return _PanelNominaCF(
          datos: d,
          anio: desde.year,
          mes: desde.month,
          onCambio: () {},
          pie: const SizedBox());
  }
}
