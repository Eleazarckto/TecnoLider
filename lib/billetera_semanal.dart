part of 'main.dart';

// ════════════════════════════════════════════════════════════════════
//  BILLETERA DE COMISIONES — VISTA SEMANAL
// ════════════════════════════════════════════════════════════════════
//  El pago a los vendedores es SEMANAL. Antes la billetera agrupaba por
//  mes y el vendedor no podía cuadrar lo que le pagaban cada semana ni
//  ver de qué venta salía cada comisión. Ahora:
//    · por defecto muestra la semana en curso (lunes a domingo), con
//      flechas para ir a semanas anteriores;
//    · opción "Rango" para elegir varias semanas/días (subtotal por
//      semana);
//    · cada comisión aparece con su FECHA exacta y el detalle de los
//      equipos/artículos vendidos.
//
//  Los montos siguen saliendo de `_VentanaComisionesState
//  .calcularComisiones` (mismas reglas que la ventana Comisiones al
//  generar el pago), así ambos números coinciden.
// ════════════════════════════════════════════════════════════════════

/// Día en que arranca la semana de pago de comisiones (lunes). Si el
/// dueño paga con otro corte, basta cambiar esta constante.
const int kPrimerDiaSemanaComisiones = DateTime.monday;

/// Primer día (00:00) de la semana a la que pertenece [d].
DateTime inicioSemanaComisiones(DateTime d,
    {int primerDia = kPrimerDiaSemanaComisiones}) {
  final dia = DateTime(d.year, d.month, d.day);
  final retroceso = (dia.weekday - primerDia + 7) % 7;
  // Se resta con el constructor (no con Duration) para no tropezar con
  // cambios de horario: siempre queda a las 00:00.
  return DateTime(dia.year, dia.month, dia.day - retroceso);
}

/// Último día (fecha a las 00:00) de la semana a la que pertenece [d].
DateTime finSemanaComisiones(DateTime d,
    {int primerDia = kPrimerDiaSemanaComisiones}) {
  final ini = inicioSemanaComisiones(d, primerDia: primerDia);
  return DateTime(ini.year, ini.month, ini.day + 6);
}

/// Agrupa [items] por semana de pago (clave = inicio de la semana). Las
/// claves salen ordenadas de la más reciente a la más vieja y, dentro
/// de cada semana, los ítems de más reciente a más viejo. Los ítems sin
/// fecha se descartan.
Map<DateTime, List<T>> agruparPorSemana<T>(
    Iterable<T> items, DateTime? Function(T) fechaDe,
    {int primerDia = kPrimerDiaSemanaComisiones}) {
  final grupos = <DateTime, List<T>>{};
  for (final it in items) {
    final f = fechaDe(it);
    if (f == null) continue;
    grupos.putIfAbsent(inicioSemanaComisiones(f, primerDia: primerDia),
        () => <T>[]).add(it);
  }
  final claves = grupos.keys.toList()..sort((a, b) => b.compareTo(a));
  return {
    for (final k in claves)
      k: grupos[k]!
        ..sort((a, b) => fechaDe(b)!.compareTo(fechaDe(a)!)),
  };
}

const _diasCortos = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

String _dosDig(int n) => n.toString().padLeft(2, '0');

/// "Lun 06/10 – Dom 12/10/2026".
String etiquetaSemanaComisiones(DateTime inicio) {
  final fin = DateTime(inicio.year, inicio.month, inicio.day + 6);
  return '${_diasCortos[inicio.weekday - 1]} ${_dosDig(inicio.day)}/${_dosDig(inicio.month)}'
      ' – ${_diasCortos[fin.weekday - 1]} ${_dosDig(fin.day)}/${_dosDig(fin.month)}/${fin.year}';
}

/// Fecha legible de un movimiento: con hora solo si la fecha la trae.
String _fechaMovimiento(DateTime f) {
  final base = '${_diasCortos[f.weekday - 1]} ${_dosDig(f.day)}/${_dosDig(f.month)}/${f.year}';
  if (f.hour == 0 && f.minute == 0) return base;
  return '$base ${_dosDig(f.hour)}:${_dosDig(f.minute)}';
}

/// Una comisión individual del vendedor: una venta, un servicio técnico
/// o una línea activada.
class MovimientoComision {
  final DateTime fecha;
  final String tipo;        // 'Venta' | 'Servicio técnico' | 'Línea'
  final String referencia;  // Nro. de factura, orden o teléfono
  final String cliente;
  final String tienda;
  /// Detalle legible de lo vendido ("Samsung A15 · IMEI 35…").
  final List<String> articulos;
  final double comision;
  const MovimientoComision({
    required this.fecha,
    required this.tipo,
    required this.referencia,
    required this.comision,
    this.cliente = '',
    this.tienda = '',
    this.articulos = const [],
  });
}

/// Comisiones del usuario [nombre] en [inicio, fin], una por venta /
/// servicio / línea. La comisión de cada venta se calcula pasando ESA
/// factura sola por `calcularComisiones` (mismas reglas); las fechas de
/// filtro van al año 9999 para que en ese cálculo no entren servicios
/// ni líneas (que se agregan aparte, uno por uno).
List<MovimientoComision> movimientosComisionDe(
    String nombre, List<FacturaModel> ventas, DateTime inicio, DateTime fin) {
  final clave = nombre.trim().toLowerCase();
  bool esDel(String n) => n.trim().toLowerCase() == clave;
  final lejos = DateTime(9999);
  final movs = <MovimientoComision>[];

  for (final v in _VentanaComisionesState.filtrarVentasPorRango(
      ventas, inicio, fin)) {
    final r = _VentanaComisionesState.calcularComisiones([v],
        fechaInicio: lejos, fechaFin: lejos);
    ResumenComision? mio;
    for (final x in r) {
      if (esDel(x.vendedor)) { mio = x; break; }
    }
    final articulos = <String>[];
    for (final e in v.equipos) {
      if (!esDel(v.vendedorDeEquipo(e.imei))) continue;
      final p = e.producto;
      final desc = '${p.marca} ${p.modelo}'.trim();
      articulos.add('${desc.isNotEmpty ? desc : p.nombre}'
          '${e.imei.isNotEmpty ? ' · IMEI ${e.imei}' : ''}'
          ' · ${formatCurrency(p.precioVenta)}');
    }
    for (final p in v.itemsSinImei) {
      if (!esDel(v.vendedorDeItem(p.codigo))) continue;
      articulos.add('${p.nombre.isNotEmpty ? p.nombre : p.codigo}'
          ' · ${formatCurrency(p.precioVenta)}');
    }
    final comision = mio?.totalComision ?? 0;
    if (articulos.isEmpty && comision.abs() < 0.005) continue;
    if (articulos.isEmpty) {
      // Comisión que no viene de un producto propio (p. ej. venta
      // financiada donde figura como financiador).
      articulos.add('Venta financiada (comisión por financiamiento)');
    }
    movs.add(MovimientoComision(
      fecha: parseFecha(v.fecha),
      tipo: 'Venta',
      referencia: 'Fact. ${v.nroFactura}',
      cliente: v.cliente,
      tienda: v.tienda,
      articulos: articulos,
      comision: comision,
    ));
  }

  final cats = ConfigSistema.categoriasComision;
  double tarifa(TipoConteoComision t) => cats
      .where((c) => c.tipoConteo == t)
      .fold<double>(0, (s, c) => s + c.tarifaUSD);
  final finIncl = fin.add(const Duration(days: 1));

  // Servicios técnicos cobrados/entregados (mismo criterio que
  // calcularComisiones).
  final tarifaServ = tarifa(TipoConteoComision.servicioTecnico);
  if (tarifaServ > 0) {
    for (final st in serviciosGlobal) {
      if (!esDel(st.tecnico)) continue;
      if (st.fecha.isBefore(inicio) || st.fecha.isAfter(finIncl)) continue;
      if (!(st.pagado || st.estado.toLowerCase() == 'entregado')) continue;
      movs.add(MovimientoComision(
        fecha: st.fecha,
        tipo: 'Servicio técnico',
        referencia: st.id != null ? 'Orden #${st.id}' : 'Servicio',
        cliente: st.nombreCliente,
        tienda: st.tienda,
        articulos: ['${st.marca} ${st.modelo}'.trim().isEmpty
            ? 'Servicio técnico'
            : 'Reparación ${st.marca} ${st.modelo}'.trim()],
        comision: tarifaServ,
      ));
    }
  }

  // Líneas activadas.
  final tarifaLinea = tarifa(TipoConteoComision.lineaTelefonica);
  if (tarifaLinea > 0) {
    for (final ln in lineasGlobal) {
      if (!ln.activada || !esDel(ln.vendedor)) continue;
      final f = DateTime.tryParse(ln.fecha);
      if (f == null || f.isBefore(inicio) || f.isAfter(finIncl)) continue;
      movs.add(MovimientoComision(
        fecha: f,
        tipo: 'Línea',
        referencia: ln.telefono.isNotEmpty ? 'Línea ${ln.telefono}' : 'Línea',
        cliente: ln.nombre,
        articulos: ['Activación de línea ${ln.plan}'.trim()],
        comision: tarifaLinea,
      ));
    }
  }

  movs.sort((a, b) => b.fecha.compareTo(a.fecha));
  return movs;
}

// ════════════════════════════════════════════════════════════════════
//  PANTALLA
// ════════════════════════════════════════════════════════════════════
//  Se abre desde el menú ("Mi billetera de comisiones") para el usuario
//  logueado, o desde Usuarios (botón de billetera) para ver la de otro.
class VentanaBilleteraComisiones extends StatefulWidget {
  /// Usuario cuya billetera se muestra. null = el usuario logueado.
  final Usuario? usuario;
  const VentanaBilleteraComisiones({super.key, this.usuario});
  @override
  State<VentanaBilleteraComisiones> createState() =>
      _VentanaBilleteraComisionesState();
}

class _VentanaBilleteraComisionesState
    extends State<VentanaBilleteraComisiones> {
  bool _cargando = true;
  String? _error;
  List<FacturaModel> _ventas = [];
  /// Inicio de la semana elegida (modo semanal).
  late DateTime _semana;
  /// Rango libre elegido (modo rango). null = modo semanal.
  DateTimeRange? _rango;
  DateTime? _actualizado;

  Usuario? get _usuario => widget.usuario ?? usuarioSesion;

  @override
  void initState() {
    super.initState();
    _semana = inicioSemanaComisiones(DateTime.now());
    _cargar();
  }

  /// Recarga ventas, usuarios, servicios y líneas desde el backend.
  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = null; });
    try {
      // Usuarios frescos: el cálculo necesita `ganaComisiones` y el
      // sueldo base actualizados.
      try {
        final rawU = await _Api.get('usuarios');
        final todos = ((rawU as List?) ?? [])
            .map((m) => Usuario.fromMap(m)).toList();
        if (todos.isNotEmpty) {
          usuariosSistema = UsuarioMaestro.ocultar<Usuario>(
              todos, (u) => u.correo);
        }
      } catch (e) {
        debugPrint('[Billetera] No se pudo refrescar usuarios: $e');
      }
      // Servicios técnicos (categoría de comisión por servicio).
      try {
        final rawS = await _Api.get('servicios');
        serviciosGlobal = ((rawS as List?) ?? [])
            .map((m) => ServicioTecnico.fromMap(m)).toList();
      } catch (e) {
        debugPrint('[Billetera] No se pudo refrescar servicios: $e');
      }
      _ventas = await _VentanaComisionesState._cargarVentasApi();
      _actualizado = DateTime.now();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  DateTime get _hoy {
    final h = DateTime.now();
    return DateTime(h.year, h.month, h.day);
  }

  DateTime get _inicio => _rango?.start ?? _semana;

  /// Fin del período (inclusive, fecha a las 00:00). Nunca pasa de hoy.
  DateTime get _fin {
    final f = _rango?.end ?? finSemanaComisiones(_semana);
    final fd = DateTime(f.year, f.month, f.day);
    return fd.isAfter(_hoy) ? _hoy : fd;
  }

  bool _esDelUsuario(String nombre) =>
      nombre.trim().toLowerCase() ==
      (_usuario?.nombre ?? '').trim().toLowerCase();

  /// Resumen de comisión del usuario en [inicio, fin] usando las MISMAS
  /// reglas de la ventana Comisiones. null si no generó nada.
  ResumenComision? _resumen(DateTime inicio, DateTime fin) {
    final ventas = _VentanaComisionesState.filtrarVentasPorRango(
        _ventas, inicio, fin);
    final todos = _VentanaComisionesState.calcularComisiones(ventas,
        fechaInicio: inicio, fechaFin: fin);
    for (final r in todos) {
      if (_esDelUsuario(r.vendedor)) return r;
    }
    return null;
  }

  Future<void> _elegirRango() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: _hoy,
      initialDateRange: _rango ??
          DateTimeRange(start: _semana, end: _fin),
      helpText: 'Rango de comisiones',
    );
    if (r != null) setState(() => _rango = r);
  }

  @override
  Widget build(BuildContext context) {
    final u = _usuario;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.usuario == null
            ? 'Mi billetera de comisiones'
            : 'Billetera — ${u?.nombre ?? ''}'),
        actions: [
          const BotonCalculadora(),
          IconButton(
            tooltip: 'Recargar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar),
        ],
      ),
      body: u == null
          ? const Center(child: Text('No hay un usuario en sesión.'))
          : _cargando
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Error al cargar: $_error',
                        style: const TextStyle(color: AppColors.statusRed))))
                  : RefreshIndicator(
                      onRefresh: _cargar,
                      child: _contenido(u)),
    );
  }

  Widget _selectorPeriodo() {
    final esSemanaActual = _rango == null &&
        _semana == inicioSemanaComisiones(DateTime.now());
    return Column(children: [
      Row(children: [
        Expanded(child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Semana'),
                icon: Icon(Icons.view_week_outlined)),
            ButtonSegment(value: true, label: Text('Rango'),
                icon: Icon(Icons.date_range)),
          ],
          selected: {_rango != null},
          onSelectionChanged: (s) {
            if (s.first) {
              _elegirRango();
            } else {
              setState(() => _rango = null);
            }
          },
        )),
      ]),
      const SizedBox(height: 8),
      if (_rango == null)
        Row(children: [
          IconButton(
            tooltip: 'Semana anterior',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _semana =
                DateTime(_semana.year, _semana.month, _semana.day - 7))),
          Expanded(child: InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _semana.isAfter(_hoy) ? _hoy : _semana,
                firstDate: DateTime(2020),
                lastDate: _hoy,
                helpText: 'Elige un día de la semana',
              );
              if (d != null) {
                setState(() => _semana = inicioSemanaComisiones(d));
              }
            },
            child: Column(children: [
              Text(etiquetaSemanaComisiones(_semana),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 15)),
              Text(esSemanaActual ? 'Semana en curso' : 'Toca para elegir otra',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary)),
            ]),
          )),
          IconButton(
            tooltip: 'Semana siguiente',
            icon: const Icon(Icons.chevron_right),
            onPressed: esSemanaActual ? null : () => setState(() => _semana =
                DateTime(_semana.year, _semana.month, _semana.day + 7))),
        ])
      else
        InkWell(
          onTap: _elegirRango,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Del ${_fechaCorta(_rango!.start)} al ${_fechaCorta(_rango!.end)}'
              '  (cambiar)',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ),
    ]);
  }

  String _fechaCorta(DateTime d) =>
      '${_dosDig(d.day)}/${_dosDig(d.month)}/${d.year}';

  Widget _contenido(Usuario u) {
    final inicio = _inicio;
    final fin = _fin;
    final r = _resumen(inicio, fin);
    final movs = movimientosComisionDe(u.nombre, _ventas, inicio, fin);
    final unidades = movs
        .where((m) => m.tipo == 'Venta')
        .fold<int>(0, (s, m) => s + m.articulos.length);
    final facturas = movs.where((m) => m.tipo == 'Venta').length;
    final mesIni = DateTime(fin.year, fin.month, 1);
    final rMes = _resumen(mesIni, fin);
    final tasa = ConfigSistema.tasaCambio;
    final porSemana = agruparPorSemana<MovimientoComision>(movs, (m) => m.fecha);

    return ListView(padding: const EdgeInsets.all(14), children: [
      _selectorPeriodo(),
      const SizedBox(height: 8),
      if (!u.ganaComisiones)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.statusOrange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8)),
          child: const Text(
            'Este usuario está configurado para NO generar comisiones.',
            style: TextStyle(color: AppColors.statusOrange,
              fontWeight: FontWeight.w600)),
        ),
      // ── Tarjeta principal: comisión del período ──
      // Tarjeta blanca del Panel (estilo Brizuela); antes azul.
      Container(
        padding: const EdgeInsets.all(18),
        decoration: AppNeu.relieve(borde: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.brandYellow,
                borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.account_balance_wallet,
                color: AppColors.brandBlueDeeper, size: 20)),
            const SizedBox(width: 10),
            Expanded(child: Text(u.nombre,
              style: const TextStyle(color: AppColors.textPrimary,
                fontWeight: FontWeight.w800, fontSize: 15))),
          ]),
          const SizedBox(height: 12),
          Text(_rango == null
              ? 'Comisiones de la semana'
              : 'Comisiones del rango',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          TextoQueCuenta(formatCurrency(r?.totalComision ?? 0),
            style: const TextStyle(color: AppColors.statusGreen,
              fontWeight: FontWeight.w900, fontSize: 30)),
          if (tasa > 0)
            Text('≈ ${formatBolivares((r?.totalComision ?? 0) * tasa)}'
                 '  (tasa ${tasa.toStringAsFixed(2)})',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 10),
          Text('Base ${formatCurrency(r?.base ?? 0)}  ·  '
               'Total estimado a cobrar ${formatCurrency(r?.totalPagar() ?? 0)}',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _kpi('Artículos vendidos', '$unidades',
            Icons.phone_android, AppColors.statusGreen)),
        const SizedBox(width: 8),
        Expanded(child: _kpi('Facturas', '$facturas',
            Icons.receipt_long, AppColors.statusOrange)),
        const SizedBox(width: 8),
        Expanded(child: _kpi('Movimientos', '${movs.length}',
            Icons.list_alt, AppColors.brandBlue)),
      ]),
      const SizedBox(height: 12),
      // ── Detalle: cada comisión con su fecha y lo vendido ──
      Card(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Detalle de comisiones',
            style: TextStyle(fontWeight: FontWeight.w800)),
          const Divider(),
          if (movs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Aún no hay comisiones en este período.',
                style: TextStyle(color: AppColors.textSecondary)))
          else
            for (final g in porSemana.entries) ...[
              // En modo rango se separa por semana con su subtotal.
              if (_rango != null)
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Expanded(child: Text(etiquetaSemanaComisiones(g.key),
                      style: const TextStyle(fontWeight: FontWeight.w800,
                        color: AppColors.brandBlueDark))),
                    Text(formatCurrency(g.value.fold<double>(
                        0, (s, m) => s + m.comision)),
                      style: const TextStyle(fontWeight: FontWeight.w900,
                        color: AppColors.brandBlueDark)),
                  ]),
                ),
              ...g.value.map(_filaMovimiento),
            ],
        ]),
      )),
      const SizedBox(height: 8),
      // ── Desglose por categoría (las tarifas aplicadas) ──
      if (r != null && r.totalComision.abs() >= 0.005)
        Card(child: ExpansionTile(
          title: const Text('Desglose por categoría',
            style: TextStyle(fontWeight: FontWeight.w800)),
          children: [
            ...r.conteos.entries.where((e) => e.value > 0).map((e) {
              final tarifa = r.tarifasUsadas[e.key] ?? 0;
              return ListTile(
                dense: true,
                title: Text(r.nombresCategorias[e.key] ?? e.key),
                subtitle: Text('${e.value} × ${formatCurrency(tarifa)}'),
                trailing: Text(formatCurrency(e.value * tarifa),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              );
            }),
            if (r.comisionWeppa.abs() > 0.005)
              ListTile(
                dense: true,
                title: const Text('Comisión Weppa (%)'),
                trailing: Text(formatCurrency(r.comisionWeppa),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            if (r.ajusteComisionUSD.abs() > 0.005)
              ListTile(
                dense: true,
                title: const Text('Ajustes'),
                trailing: Text(formatCurrency(r.ajusteComisionUSD),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ],
        )),
      // ── Acumulado del mes (referencia) ──
      Card(child: ListTile(
        leading: const Icon(Icons.calendar_month, color: AppColors.brandBlue),
        title: Text('Acumulado del mes hasta ${_fechaCorta(fin)}'),
        subtitle: const Text('Comisiones sin incluir la base'),
        trailing: Text(formatCurrency(rMes?.totalComision ?? 0),
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16,
            color: AppColors.brandBlueDark)),
      )),
      const SizedBox(height: 8),
      Text(
        'Montos estimados con las reglas vigentes de Comisiones. '
        'El pago final lo genera Administración.'
        '${_actualizado != null ? '\nActualizado: ${_dosDig(_actualizado!.hour)}:${_dosDig(_actualizado!.minute)}' : ''}',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
    ]);
  }

  Widget _filaMovimiento(MovimientoComision m) {
    final icono = m.tipo == 'Venta'
        ? Icons.shopping_bag_outlined
        : m.tipo == 'Línea' ? Icons.sim_card_outlined : Icons.build_outlined;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icono, size: 20, color: AppColors.brandBlue),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_fechaMovimiento(m.fecha),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          Text([m.referencia, if (m.cliente.isNotEmpty) m.cliente,
                if (m.tienda.isNotEmpty) m.tienda].join(' · '),
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ...m.articulos.map((a) => Text('• $a',
            style: const TextStyle(fontSize: 12))),
        ])),
        const SizedBox(width: 8),
        Text(formatCurrency(m.comision),
          style: TextStyle(fontWeight: FontWeight.w900,
            color: m.comision >= 0 ? AppColors.statusGreen : AppColors.statusRed)),
      ]),
    );
  }

  // Tarjeta del Panel (TarjetaIndicador, theme/movimiento.dart).
  Widget _kpi(String label, String valor, IconData icon, Color color) =>
      TarjetaIndicador(label, valor, icono: icon, color: color, compacta: true);
}
