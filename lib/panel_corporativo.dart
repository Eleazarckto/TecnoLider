part of 'main.dart';

// ════════════════════════════════════════════════════════════════════
//  PANEL CORPORATIVO (traído de Brizuela, orden del dueño 16/10/2026:
//  «agrega el panel corporativo tal cual lo tiene Brizuela»)
// ════════════════════════════════════════════════════════════════════
//  Dueño, Gerente, Administrador y el Maestro entran PRIMERO aquí al
//  iniciar sesión (ver el ruteo por rol en `_login`) y desde aquí eligen
//  a qué tienda entrar. Los demás roles siguen eligiendo su tienda y
//  entran directo a vender, como siempre.
//
//  Misma estructura que el de Brizuela: barra superior, saludo,
//  indicadores del grupo, «Tus tiendas» (vista Ciudad o Tarjetas) y la
//  grilla de Administración. Diferencias, todas por lo que Tecno Líder
//  tiene o no tiene:
//    · Sin CRM, sin asistente (botón flotante) y sin los módulos que
//      Tecno Líder no tiene: Activación, Líneas, Movimientos y
//      Financiamiento (no hay pantalla para ninguno).
//    · Los datos salen SOLO de lo que el servidor de Tecno Líder ya
//      tiene: `facturas` (las 1000 más recientes; se filtra el mes en
//      curso aquí, porque el servidor no entiende anio/mes), `traslados`
//      y el catálogo ya cargado al iniciar sesión. Abrir el panel NO
//      escribe nada en el servidor.
//    · Los montos en divisas usan la regla de Tecno Líder
//      (`totalesPagosPorMoneda`: cada pago en Bs con la tasa con que se
//      cobró) y la ganancia la de su Reporte por Vendedor
//      (`precioRealVentaEnFactura` − costo), para que el panel y los
//      reportes den las mismas cifras.
// ════════════════════════════════════════════════════════════════════

class PanelCorporativo extends StatefulWidget {
  const PanelCorporativo({super.key});
  @override
  State<PanelCorporativo> createState() => _PanelCorporativoState();
}

class _PanelCorporativoState extends State<PanelCorporativo> {
  bool _cargando = true;
  // La primera carga muestra la forma del panel; las siguientes (botón,
  // deslizar, refresco automático) refrescan encima sin vaciar la
  // pantalla, para que las cifras CUENTEN hasta el valor nuevo.
  bool _yaCargo = false;
  DateTime? _actualizado;
  Timer? _refresco;
  // tienda → {ventasMes, ventasHoy, ganancia, unidades, facturas, facturasHoy}
  final Map<String, Map<String, double>> _kpisPorTienda = {};
  double _valorInventario = 0; // valor total del inventario del grupo (USD)
  int _unidadesInventario = 0;
  // Traslados de hoy, agrupados por ruta: son los camiones de la ciudad.
  List<RutaCiudad> _rutasHoy = const [];
  // 'ciudad' o 'tarjetas'.
  String _vista = 'ciudad';

  @override
  void initState() {
    super.initState();
    _cargar();
    // Refresco silencioso cada cinco minutos: el panel se deja abierto en
    // la oficina y el indicador «Actualizado» tiene que ser verdad.
    _refresco = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted && !_cargando) _cargar();
    });
    // Comprobar actualización también aquí: estos roles aterrizan en el
    // panel y no en ventas (igual que en Brizuela).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) verificarActualizacionApp(context, silencioso: true);
    });
  }

  @override
  void dispose() {
    _refresco?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() => _cargando = true);
    try {
      // Valor del inventario del grupo (precio de venta × stock).
      _valorInventario = 0;
      _unidadesInventario = 0;
      for (final p in catalogoGlobal) {
        final stock = p.stockTotal < 0 ? 0 : p.stockTotal;
        _valorInventario += p.precioVenta * stock;
        _unidadesInventario += stock;
      }
      // KPIs: las facturas del mes en curso, agrupadas por tienda.
      final ahora = DateTime.now();
      final raw = await _Api.get('facturas');
      _kpisPorTienda.clear();
      for (final f in (raw as List?) ?? const []) {
        if (f is! Map) continue;
        final mapa = Map<String, dynamic>.from(f);
        final tienda = (mapa['tienda'] ?? '').toString();
        if (tienda.isEmpty) continue;
        final fecha = parseFechaFlexible(mapa['fecha']?.toString());
        if (fecha == null ||
            fecha.year != ahora.year ||
            fecha.month != ahora.month) {
          continue;
        }
        final esHoy = fecha.day == ahora.day;
        // Total en divisas: los pagos en Bs con la tasa con que se cobraron.
        final total =
            totalesPagosPorMoneda((mapa['pagos'] as List?) ?? const []).equivUsd;
        final k = _kpisPorTienda.putIfAbsent(tienda, () => {
              'ventasMes': 0, 'ventasHoy': 0, 'facturas': 0,
              'facturasHoy': 0, 'ganancia': 0, 'unidades': 0,
            });
        k['ventasMes'] = k['ventasMes']! + total;
        k['facturas'] = k['facturas']! + 1;
        if (esHoy) {
          k['ventasHoy'] = k['ventasHoy']! + total;
          k['facturasHoy'] = k['facturasHoy']! + 1;
        }
        // Ganancia y unidades, como el Reporte por Vendedor.
        try {
          final fm = construirFacturaModelDesdeJson(mapa);
          for (final eq in fm.equipos) {
            k['ganancia'] = k['ganancia']! +
                precioRealVentaEnFactura(fm, eq.producto) -
                eq.producto.precioCosto;
            k['unidades'] = k['unidades']! + 1;
          }
          for (final p in fm.itemsSinImei) {
            k['ganancia'] = k['ganancia']! +
                precioRealVentaEnFactura(fm, p) - p.precioCosto;
            k['unidades'] = k['unidades']! + 1;
          }
        } catch (_) {}
      }
      _rutasHoy = await _trasladosDeHoy(ahora);
    } catch (e) {
      debugPrint('[PanelCorporativo] Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
          _yaCargo = true;
          _actualizado = DateTime.now();
        });
      }
    }
  }

  /// Traslados registrados hoy, agrupados por (origen, destino).
  /// Si falla, la ciudad simplemente no muestra camiones.
  Future<List<RutaCiudad>> _trasladosDeHoy(DateTime ahora) async {
    try {
      final raw = await _Api.get('traslados');
      final porRuta = <(String, String), int>{};
      for (final m in (raw as List?) ?? const []) {
        if (m is! Map) continue;
        final tr = Traslado.fromMap(Map<String, dynamic>.from(m));
        final f = tr.fecha;
        if (f == null ||
            f.year != ahora.year ||
            f.month != ahora.month ||
            f.day != ahora.day) {
          continue;
        }
        final clave = (tr.tiendaOrigen, tr.tiendaDestino);
        porRuta[clave] = (porRuta[clave] ?? 0) + 1;
      }
      return [
        for (final e in porRuta.entries) RutaCiudad(e.key.$1, e.key.$2, e.value),
      ];
    } catch (e) {
      debugPrint('[PanelCorporativo] Traslados de hoy: $e');
      return const [];
    }
  }

  // «Entra» a una tienda: la pone como activa y abre ventas. Al volver
  // (atrás o el botón del panel), el pop regresa a ESTE panel; se
  // restaura la tienda y se refrescan las cifras.
  Future<void> _entrar(String tienda) async {
    final tiendaPrevia = usuarioSesion?.tienda ?? '';
    usuarioSesion?.tienda = tienda;
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => VentasPrincipal(tienda: tienda, desdePanel: true)));
    usuarioSesion?.tienda = tiendaPrevia;
    _cargar();
  }

  double get _totalMes =>
      _kpisPorTienda.values.fold(0.0, (s, m) => s + (m['ventasMes'] ?? 0));
  double get _totalHoy =>
      _kpisPorTienda.values.fold(0.0, (s, m) => s + (m['ventasHoy'] ?? 0));
  double get _totalGanancia =>
      _kpisPorTienda.values.fold(0.0, (s, m) => s + (m['ganancia'] ?? 0));
  int get _facturasHoy => _kpisPorTienda.values
      .fold(0, (s, m) => s + (m['facturasHoy'] ?? 0).toInt());

  List<SedeCiudad> _sedesCiudad(List<String> tiendas) => [
        for (final t in tiendas)
          SedeCiudad(
            nombre: t,
            ventasHoy: _kpisPorTienda[t]?['ventasHoy'] ?? 0,
            ventasMes: _kpisPorTienda[t]?['ventasMes'] ?? 0,
            ganancia: _kpisPorTienda[t]?['ganancia'] ?? 0,
            facturasHoy: (_kpisPorTienda[t]?['facturasHoy'] ?? 0).toInt(),
            facturasMes: (_kpisPorTienda[t]?['facturas'] ?? 0).toInt(),
            unidades: (_kpisPorTienda[t]?['unidades'] ?? 0).toInt(),
          ),
      ];

  Future<void> _cerrarSesion() async {
    // Cierre completo, igual que «Cerrar Sesión» del menú de ventas:
    // detener servicios, limpiar la sesión y borrar las credenciales
    // guardadas para que NO vuelva a entrar solo.
    NotificacionesService.detener();
    notificacionesGlobal.clear();
    MensajesLeidosService.limpiarCache();
    usuarioSesion = null;
    await SesionPersistente.borrar();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const LoginPage()), (r) => false);
  }

  void _abrir(Widget Function() pantalla) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla()))
        .then((_) => _cargar());
  }

  @override
  Widget build(BuildContext context) {
    final tiendas = ConfigSistema.tiendas;
    final nombre = usuarioSesion?.nombre ?? 'Usuario';
    final ancho = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: AppNeu.base,
      body: AnimatedSwitcher(
        duration: Ritmo.entrada,
        child: !_yaCargo
            ? _esqueletoPanel(ancho)
            : RefreshIndicator(
                onRefresh: _cargar,
                child: CustomScrollView(slivers: [
                  SliverToBoxAdapter(child: Aparecer(
                      desplazamiento: -14, child: _barraSuperior())),
                  SliverToBoxAdapter(child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: Aparecer(child: _saludo(nombre)),
                  )),
                  SliverToBoxAdapter(child: _filaKpis(tiendas.length)),
                  // ── Tiendas: ciudad o tarjetas ──
                  SliverToBoxAdapter(child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 12),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12, runSpacing: 10,
                      children: [
                        _tituloSeccion('Tus tiendas', _vista == 'ciudad'
                            ? 'Toca un edificio para ver su detalle'
                            : 'Rendimiento por sucursal'),
                        SelectorPildoras<String>(
                          seleccionada: _vista,
                          alCambiar: (v) => setState(() => _vista = v),
                          opciones: const [
                            OpcionPildora('ciudad', 'Ciudad', Icons.view_in_ar_rounded),
                            OpcionPildora('tarjetas', 'Tarjetas', Icons.grid_view_rounded),
                          ],
                        ),
                      ],
                    ),
                  )),
                  SliverToBoxAdapter(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: AnimatedSwitcher(
                      duration: Ritmo.entrada,
                      switchInCurve: Ritmo.suave,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (hijo, a) => FadeTransition(
                        opacity: a,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.97, end: 1).animate(a),
                          child: hijo,
                        ),
                      ),
                      layoutBuilder: (actual, previos) => Stack(
                        alignment: Alignment.topCenter,
                        children: [...previos, if (actual != null) actual],
                      ),
                      child: _vista == 'ciudad'
                          ? VistaCiudad(
                              key: const ValueKey('ciudad'),
                              alto: ancho < 600 ? 460 : 580,
                              sedes: _sedesCiudad(tiendas),
                              rutas: _rutasHoy,
                              valorInventario: _valorInventario,
                              unidadesInventario: _unidadesInventario,
                              formatoMoneda: (v) => formatCurrency(v),
                              alEntrar: _entrar,
                              // Tecno Líder no tiene «Almacén central»: el
                              // almacén de la ciudad abre el Inventario.
                              alAbrirAlmacen: () => _abrir(() => const VentanaInventario()),
                            )
                          : Column(
                              key: const ValueKey('tarjetas'),
                              children: [
                                for (var i = 0; i < tiendas.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Aparecer(indice: i,
                                        child: _tarjetaTienda(tiendas[i])),
                                  ),
                              ],
                            ),
                    ),
                  )),
                  // ── Administración (módulos) ──
                  SliverToBoxAdapter(child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 26, 16, 12),
                    child: _tituloSeccion('Administración', 'Gestión de toda la empresa'),
                  )),
                  SliverToBoxAdapter(child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    child: _modulos(),
                  )),
                ]),
              ),
      ),
    );
  }

  /// La forma del panel mientras llega la primera carga.
  Widget _esqueletoPanel(double ancho) => Brillo(
    key: const ValueKey('esqueleto'),
    child: ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        SafeArea(bottom: false, child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.bordeSuave)),
          child: const Row(children: [
            Esqueleto(ancho: 40, alto: 40, radio: 12),
            SizedBox(width: 12),
            Column(mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Esqueleto(ancho: 130, alto: 14),
                SizedBox(height: 6),
                Esqueleto(ancho: 90, alto: 10),
              ]),
          ]),
        )),
        const SizedBox(height: 18),
        const Esqueleto(ancho: 220, alto: 24),
        const SizedBox(height: 8),
        const Esqueleto(ancho: 320, alto: 12),
        const SizedBox(height: 18),
        SizedBox(height: 104, child: ListView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < 5; i++)
              Container(
                width: 196, margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.bordeSuave)),
                child: const Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Esqueleto(ancho: 110, alto: 12),
                    Spacer(),
                    Esqueleto(ancho: 130, alto: 20),
                    SizedBox(height: 6),
                    Esqueleto(ancho: 80, alto: 10),
                  ]),
              ),
          ])),
        const SizedBox(height: 26),
        Esqueleto(alto: ancho < 600 ? 460 : 580, radio: AppRadius.xl),
      ],
    ),
  );

  // Barra superior flotante: marca, estado y acciones.
  Widget _barraSuperior() => SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.bordeSuave),
          boxShadow: AppElevation.tarjeta,
        ),
        child: Row(children: [
          const TecnoLiderLogo(size: 40),
          const SizedBox(width: 12),
          const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tecno Líder', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16,
                  fontWeight: FontWeight.w800, letterSpacing: -0.2)),
              Text('Panel corporativo', style: TextStyle(
                color: AppColors.textSecondary, fontSize: 11.5)),
            ])),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Actualizar', onPressed: _cargar),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Cerrar sesión',
            onPressed: _cerrarSesion),
        ]),
      ),
    ),
  );

  Widget _saludo(String nombre) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 12, runSpacing: 6,
    children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
        children: [
          Text('Hola, $nombre', style: const TextStyle(
            color: AppColors.textPrimary, fontSize: 24,
            fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          const SizedBox(height: 2),
          const Text('Resumen consolidado · montos en divisas',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
        ]),
      if (_actualizado != null)
        EnVivo(texto: 'Actualizado', hora: _actualizado),
    ],
  );

  // Indicadores: tarjetas blancas cuyas cifras suben contando.
  Widget _filaKpis(int numTiendas) {
    final kpis = <(IconData, Color, String, double, String Function(double), String)>[
      (Icons.bolt_rounded, AppColors.azulVivo, 'Ventas de hoy', _totalHoy,
        (v) => formatCurrency(v), '$_facturasHoy factura(s) hoy'),
      (Icons.calendar_month_rounded, AppColors.lila, 'Ventas del mes', _totalMes,
        (v) => formatCurrency(v), 'Mes en curso'),
      (Icons.trending_up_rounded, AppColors.statusGreen, 'Ganancia del mes', _totalGanancia,
        (v) => formatCurrency(v), 'Ganancia real de lo vendido'),
      (Icons.inventory_2_rounded, AppColors.statusOrange, 'Valor inventario', _valorInventario,
        (v) => formatCurrency(v), '$_unidadesInventario unidades'),
      (Icons.storefront_rounded, AppColors.royalBlue, 'Sucursales', numTiendas.toDouble(),
        (v) => v.round().toString(),
        '${_rutasHoy.fold<int>(0, (s, r) => s + r.viajes)} traslado(s) hoy'),
    ];
    return SizedBox(
      height: 128,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        clipBehavior: Clip.none,
        itemCount: kpis.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final k = kpis[i];
          return Aparecer(
            indice: i,
            child: SizedBox(
              width: 196,
              // Al refrescar, la tarjeta cuya cifra cambió destella.
              child: Destello(
                valor: k.$4,
                color: k.$2,
                child: TarjetaViva(
                  acento: k.$2,
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: k.$2.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(9)),
                        child: Icon(k.$1, color: k.$2, size: 17)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(k.$3, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary))),
                    ]),
                    const Spacer(),
                    CifraAnimada(valor: k.$4, formato: k.$5, estilo: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary, letterSpacing: -0.3)),
                    const SizedBox(height: 2),
                    Text(k.$6, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tituloSeccion(String titulo, String subtitulo) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 4, height: 34,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.lila, AppColors.azulVivo],
            begin: Alignment.topCenter, end: Alignment.bottomCenter),
          borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo, style: const TextStyle(fontSize: 18,
          fontWeight: FontWeight.w800, color: AppColors.textPrimary,
          letterSpacing: -0.2)),
        Text(subtitulo, style: const TextStyle(fontSize: 12,
          color: AppColors.textSecondary)),
      ]),
    ]);

  Widget _tarjetaTienda(String tienda) {
    final k = _kpisPorTienda[tienda];
    final ventasMes = k?['ventasMes'] ?? 0;
    final ventasHoy = k?['ventasHoy'] ?? 0;
    final ganancia = k?['ganancia'] ?? 0;
    final numFacturas = (k?['facturas'] ?? 0).toInt();
    final facturasHoy = (k?['facturasHoy'] ?? 0).toInt();
    final maxMes = _kpisPorTienda.values
        .fold<double>(0, (m, v) => math.max(m, v['ventasMes'] ?? 0));
    final participacion = maxMes <= 0 ? 0.0 : ventasMes / maxMes;
    return TarjetaViva(
      acento: AppColors.lila,
      onTap: () => _entrar(tienda),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.lila, AppColors.azulVivo],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 24)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tienda, style: const TextStyle(fontSize: 16,
                fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text('$numFacturas factura(s) este mes · $facturasHoy hoy',
                style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
            ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.azulVivo,
              borderRadius: BorderRadius.circular(AppRadius.full),
              boxShadow: [BoxShadow(
                color: AppColors.azulVivo.withValues(alpha: 0.35),
                blurRadius: 10, offset: const Offset(0, 4))]),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Entrar', style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 13)),
              SizedBox(width: 4),
              Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _chipKpi('Hoy', ventasHoy, AppColors.azulVivo),
          _chipKpi('Mes', ventasMes, AppColors.lila),
          _chipKpi('Ganancia', ganancia, AppColors.statusGreen),
        ]),
        const SizedBox(height: 12),
        // Barra de participación: cuánto vendió frente a la tienda que
        // más vendió este mes. Se llena animada.
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: participacion),
            duration: Ritmo.cifra,
            curve: Ritmo.suave,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v, minHeight: 6,
              backgroundColor: AppNeu.hueco,
              valueColor: const AlwaysStoppedAnimation(AppColors.lila)),
          ),
        ),
      ]),
    );
  }

  Widget _chipKpi(String label, double valor, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppRadius.full)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text('$label ', style: const TextStyle(fontSize: 11.5,
        color: AppColors.textSecondary)),
      CifraAnimada(valor: valor, formato: (v) => formatCurrency(v),
        estilo: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
          color: AppColors.textPrimary)),
    ]),
  );

  /// Los módulos de la grilla. Mismo orden que en Brizuela; cada uno abre
  /// la pantalla de Tecno Líder que hace lo mismo. Brizuela trae además
  /// Activación, Líneas, Movimientos y Financiamiento: Tecno Líder no tiene
  /// esas pantallas, así que no aparecen.
  static final List<(IconData, Color, String, String, Widget Function())>
      modulosPanel = [
    (Icons.inventory_2, AppColors.azulVivo, 'Almacén / Inventario',
        'Stock de todas las tiendas', () => const VentanaInventario()),
    (Icons.receipt_long, AppColors.brandBlue, 'Reportes',
        'Reportes de todas las tiendas', () => const VentanaReportes()),
    (Icons.people_alt, AppColors.lila, 'Reporte Vendedor',
        'Ventas por vendedor', () => const VentanaReporteVendedor()),
    (Icons.paid, AppColors.royalBlue, 'Comisiones',
        'Comisiones del período', () => const VentanaComisiones()),
    (Icons.insights, AppColors.azulVivo, 'Estadística Producto',
        'Ganancias por producto', () => const VentanaEstadisticasProductos()),
    (Icons.account_balance, AppColors.brandBlue, 'Financiadoras',
        'Reporte por financiadora', () => const VentanaReporteFinanciadora()),
    (Icons.manage_accounts, AppColors.lila, 'Usuarios',
        'Gestión de usuarios', () => const VentanaUsuarios()),
    (Icons.money_off, AppColors.royalBlue, 'Cuentas x Cobrar',
        'Créditos de todas las tiendas', () => const VentanaCuentasPorCobrar()),
    (Icons.request_quote, AppColors.azulVivo, 'Cuentas x Pagar',
        'Deudas por pagar', () => const VentanaCuentasPorPagar()),
    (Icons.business, AppColors.brandBlue, 'CxP Proveedores',
        'Deudas a proveedores', () => const VentanaCuentasPorPagarProveedor()),
    (Icons.qr_code_scanner, AppColors.lila, 'Buscador IMEI',
        'Ubicar cualquier equipo', () => const VentanaImei()),
    (Icons.groups, AppColors.royalBlue, 'Clientes',
        'Buscar cliente y ver sus compras', () => const VentanaHistorialClientes()),
    (Icons.format_list_bulleted, AppColors.azulVivo, 'Listas de Precios',
        'Crear y editar listas', () => const VentanaListasPrecios()),
    (Icons.price_check_outlined, AppColors.brandBlue, 'Consulta Rápida',
        'Precio de un producto en todas las listas',
        () => const VentanaConsultaRapidaPrecios()),
    (Icons.local_shipping, AppColors.lila, 'Traslados',
        'Mover mercancía entre tiendas', () => const VentanaTraslados()),
    (Icons.settings, AppColors.textSecondary, 'Configuración',
        'Ajustes de todo el sistema', () => const VentanaConfiguracion()),
  ];

  Widget _modulos() {
    final modulos = modulosPanel;
    // Alto fijo de cada módulo y, en teléfono, una sola columna: con la
    // proporción fija de Brizuela (3,2) dos columnas en 400 px quedaban de
    // 55 px de alto y el texto se desbordaba.
    return LayoutBuilder(builder: (_, caja) => GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: modulos.length,
      clipBehavior: Clip.none,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: caja.maxWidth < 560 ? caja.maxWidth : 320,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 78,
      ),
      itemBuilder: (ctx, i) {
        final (icono, color, titulo, sub, pantalla) = modulos[i];
        return Aparecer(
          indice: i,
          child: TarjetaViva(
            acento: color,
            padding: const EdgeInsets.all(12),
            onTap: () => _abrir(pantalla),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12)),
                child: Icon(icono, color: color, size: 22)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(titulo, style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(sub, style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ]),
          ),
        );
      },
    ));
  }
}
