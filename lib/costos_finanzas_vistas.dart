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

/// Valor de `configuracion` ya decodificado (viene como texto JSON del
/// servidor, o como mapa/lista en las pruebas). null si no es JSON.
dynamic _cfDecodificar(dynamic v) {
  if (v == null || v is Map || v is List) return v;
  try {
    return jsonDecode(v.toString());
  } catch (_) {
    return null;
  }
}

/// Listas de precios crudas del servidor → (nombre, financiadora,
/// código → primer precio), que es lo que usa
/// [precioEnListaFinanciadora].
List<({String nombre, String financiadora, Map<String, double> precios})>
    _cfListasDesdeRaw(List<dynamic>? raw) {
  final r =
      <({String nombre, String financiadora, Map<String, double> precios})>[];
  for (final l in raw ?? const []) {
    if (l is! Map) continue;
    final precios = <String, double>{};
    for (final it in (l['items'] as List? ?? [])) {
      if (it is! Map) continue;
      final vals = it['valores'] as List? ?? [];
      if (vals.isEmpty || vals.first is! Map) continue;
      final p =
          double.tryParse((vals.first as Map)['precio']?.toString() ?? '');
      if (p != null && p > 0) {
        precios[(it['producto_codigo'] ?? '').toString()] = p;
      }
    }
    r.add((
      nombre: (l['nombre'] ?? '').toString(),
      financiadora: (l['financiadora'] ?? '').toString(),
      precios: precios,
    ));
  }
  return r;
}

// ── Historial de precios y foto de precios de cada factura ─────────
//  (lógica en lib/historial_precios.dart). Al cambiar un precio se
//  guarda el ANTERIOR con su vigencia; al facturar, los precios y tasas
//  de ese momento. Así una venta vieja no cambia de ganancia cuando el
//  dueño actualiza el precio del producto.

/// Guarda en `configuracion` el precio ANTERIOR de un producto cuando
/// cambia su costo o su precio de venta. Es el ÚNICO lugar que escribe
/// el historial: lo llama todo el que cambie precios de un producto.
///
/// Corre en la misma cola que la actualización de listas por cambio de
/// precio y ANTES que ella, para leer el precio que cada lista tenía
/// antes de recalcularse. Un fallo solo se registra en el log: nunca
/// impide guardar el producto.
Future<void> registrarCambioDePrecio(Producto anterior, Producto nuevo) {
  final cambio = (anterior.precioVenta - nuevo.precioVenta).abs() > 0.0001 ||
      (anterior.precioCosto - nuevo.precioCosto).abs() > 0.0001;
  if (!cambio || anterior.codigo.trim().isEmpty) return Future.value();
  final momento = DateTime.now();
  final usuario = usuarioSesion?.nombre ?? '';
  return _enColaListasPorPrecio(() async {
    try {
      final listas = <PrecioListaCF>[];
      try {
        final raw = await _Api.get('listas_precios');
        for (final l in _cfListasDesdeRaw(raw is List ? raw : null)) {
          final p = l.precios[anterior.codigo];
          if (p == null) continue;
          listas.add(PrecioListaCF(
              lista: l.nombre, financiadora: l.financiadora, precio: p));
        }
      } catch (e) {
        debugPrint('[HistorialPrecios] listas: $e');
      }
      final clave = claveHistorialPrecio(anterior.codigo);
      final cfg = await _Api.get('configuracion');
      final actual = cfg is Map ? _cfDecodificar(cfg[clave]) : null;
      final hist = agregarCambioPrecio(
          actual,
          CambioPrecioCF(
            vigenteHasta: momento,
            costo: anterior.precioCosto,
            venta: anterior.precioVenta,
            listas: listas,
            usuario: usuario,
          ));
      await _Api.post('configuracion', {clave: jsonEncode(hist)});
    } catch (e) {
      debugPrint('[HistorialPrecios] ${anterior.codigo}: $e');
    }
  });
}

/// Guarda la foto de precios y tasas de una factura recién creada
/// (`snap_fac_<nro>`). Si falla no pasa nada: la factura ya está
/// guardada y finanzas cae al historial de precios.
Future<void> guardarFotoPreciosFactura(FacturaModel f) async {
  try {
    final ahora = DateTime.now();
    final fin = f.pagos
        .map((p) => _finNormCF(p.financiadora))
        .firstWhere((x) => x.isNotEmpty, orElse: () => '');
    final lista = f.pagos
        .map((p) => p.nombreLista ?? '')
        .firstWhere((x) => x.isNotEmpty, orElse: () => '');
    var listas =
        <({String nombre, String financiadora, Map<String, double> precios})>[];
    double divisa = 0;
    try {
      final res = await Future.wait([
        fin.isEmpty
            ? Future<dynamic>.value(null)
            : _Api.get('listas_precios'),
        _Api.get('configuracion'),
      ]);
      listas = _cfListasDesdeRaw(res[0] is List ? res[0] as List : null);
      final cfg = res[1];
      if (cfg is Map) {
        final mes = _cfDecodificar(cfg[claveTasasDiaMes(ahora.year, ahora.month)]);
        if (mes is Map) {
          divisa = RegistroTasaDia.fromJson(mes[fechaIsoCF(ahora)]).divisa;
        }
      }
    } catch (e) {
      debugPrint('[FotoPrecios] lectura: $e');
    }
    ItemSnapshotCF item(Producto p, String imei) {
      // El precio del catálogo (contado en divisa), no el de la línea
      // de la factura, que puede venir de una lista o con descuento.
      final cat = filaProductoParaTienda(p.codigo, f.tienda) ?? p;
      return ItemSnapshotCF(
        codigo: p.codigo,
        imei: imei,
        costo: cat.precioCosto,
        venta: cat.precioVenta,
        precioFinanciadora: fin.isEmpty
            ? null
            : precioEnListaFinanciadora(listas, fin, p.codigo,
                nombreLista: lista),
      );
    }

    final foto = SnapshotFacturaCF(
      momento: ahora,
      tasaBcv: ConfigSistema.tasaCambio,
      tasaDivisa: divisa,
      financiadora: fin,
      lista: lista,
      items: [
        for (final e in f.equipos) item(e.producto, e.imei),
        for (final p in f.itemsSinImei) item(p, ''),
      ],
    );
    await _Api.post('configuracion',
        {claveSnapshotFactura(f.nroFactura): jsonEncode(foto.toJson())});
  } catch (e) {
    debugPrint('[FotoPrecios] ${f.nroFactura}: $e');
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
  /// Fecha y hora de creación de cada factura (`creado_en`), para saber
  /// qué precio estaba vigente en el momento exacto de la venta.
  final Map<String, DateTime> momentoPorNro = {};
  List<({String nombre, String financiadora, Map<String, double> precios})>
      listas = [];
  List<dynamic> pagosFinanciadora = [];
  List<dynamic> cuentasPagar = [];
  Map<String, dynamic> config = {};
  /// BCV de cada día según la tabla `tasa_bcv` ("AAAA-MM-DD" → tasa).
  Map<String, double> bcvTabla = {};

  /// Historial de precios por código y foto de precios por factura
  /// (leídos de `configuracion`).
  final Map<String, List<CambioPrecioCF>> _historial = {};
  final Map<String, SnapshotFacturaCF> _fotos = {};

  /// Tasa BCV actual (referencia del flujo de caja).
  double tasaBcv = ConfigSistema.tasaCambio;

  bool cargando = false;
  String? error;
  DateTime? cargadoEn;
  Future<void>? _enCurso;
  TasasPorDia? _tasasCache;

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
        opcional('tasa_bcv'),
      ]);
      productosRaw = (res[0] as List?) ?? [];
      facturasRaw = (res[1] as List?) ?? [];
      imeisRaw = (res[2] as List?) ?? [];
      comprasRaw = (res[3] as List?) ?? [];
      pagosFinanciadora = (res[5] as List?) ?? [];
      cuentasPagar = (res[6] as List?) ?? [];
      config = res[7] is Map ? Map<String, dynamic>.from(res[7] as Map) : {};
      bcvTabla = _bcvDesdeTabla(res[8]);
      tasaBcv = ConfigSistema.tasaCambio;

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

      listas = _cfListasDesdeRaw(res[4] as List?);
      _leerPreciosGuardados();

      facturas.clear();
      facturasCF.clear();
      tiendaPorFacturaId.clear();
      tiendaPorNroFactura.clear();
      momentoPorNro.clear();
      for (final m in facturasRaw) {
        final mp = m as Map<String, dynamic>;
        final f = construirFacturaModelDesdeJson(mp);
        final creado = DateTime.tryParse((mp['creado_en'] ?? '').toString());
        if (creado != null) momentoPorNro[f.nroFactura] = creado;
        facturas.add(f);
        facturasCF.add(_aFacturaCF(f));
        tiendaPorFacturaId[(mp['id'] ?? '').toString()] = f.tienda;
        tiendaPorNroFactura[f.nroFactura] = f.tienda;
      }
      _tasasCache = null;
      cargadoEn = DateTime.now();
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  /// Filas de la tabla `tasa_bcv` → BCV por día. Se toleran distintos
  /// nombres de columna porque la tabla no está en el esquema conocido.
  static Map<String, double> _bcvDesdeTabla(dynamic raw) {
    final r = <String, double>{};
    if (raw is! List) return r;
    for (final x in raw) {
      if (x is! Map) continue;
      final f = parseFechaCF((x['fecha'] ??
              x['fecha_actualizacion'] ??
              x['creado_en'] ??
              '')
          .toString());
      final v = double.tryParse(
              (x['valor'] ?? x['tasa'] ?? x['tasa_bcv'] ?? x['monto'] ?? '')
                  .toString()) ??
          0;
      if (f != null && v > 0) r[fechaIsoCF(f)] = v;
    }
    return r;
  }

  /// Lee de `configuracion` el historial de precios (`hist_precio_*`) y
  /// las fotos de precios de las facturas (`snap_fac_*`).
  void _leerPreciosGuardados() {
    _historial.clear();
    _fotos.clear();
    for (final e in config.entries) {
      if (e.key.startsWith('hist_precio_')) {
        final h = leerHistorialPrecio(_cfDecodificar(e.value));
        if (h.isNotEmpty) {
          _historial[e.key.substring('hist_precio_'.length)] = h;
        }
      } else if (e.key.startsWith('snap_fac_')) {
        final v = _cfDecodificar(e.value);
        if (v is Map) {
          _fotos[e.key.substring('snap_fac_'.length)] =
              SnapshotFacturaCF.fromJson(v);
        }
      }
    }
  }

  /// Precio de contado y costo de un producto en una venta: los de la
  /// foto de la factura; si no hay, los vigentes en ese momento según
  /// el historial; y si no hay historial, los actuales del catálogo.
  PreciosVigentesCF preciosDeVenta(
      String nroFactura, String codigo, String imei, DateTime momento,
      {Producto? respaldo}) {
    final foto = _fotos[nroFactura]?.item(codigo, imei);
    if (foto != null) {
      return PreciosVigentesCF(
          costo: foto.costo, venta: foto.venta, origen: origenPrecioFactura);
    }
    final cat = productos[codigo] ?? respaldo;
    return preciosVigentesEn(_historial[codigo] ?? const [], momento,
        costoActual: cat?.precioCosto ?? 0,
        ventaActual: cat?.precioVenta ?? 0);
  }

  /// Momento de la venta: la hora de creación si se conoce; si no, el
  /// inicio del día de la factura.
  DateTime momentoDe(String nroFactura, DateTime fecha) =>
      momentoPorNro[nroFactura] ?? fecha;

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
    final fecha = parseFechaFlexible(f.fecha) ?? DateTime(2000);
    final momento = momentoDe(f.nroFactura, fecha);
    final foto = _fotos[f.nroFactura];
    EquipoVendidoCF eq(Producto p, String imei) {
      final pr = preciosDeVenta(f.nroFactura, p.codigo, imei, momento,
          respaldo: p);
      double? pf;
      if (fin.isNotEmpty) {
        // Precio de la lista de la financiadora: el de la foto de la
        // factura; si no, el que la lista tenía antes del siguiente
        // cambio de precio; si no, el de la lista actual.
        pf = foto?.item(p.codigo, imei)?.precioFinanciadora;
        if (pf == null && pr.listas != null) {
          pf = precioEnListaFinanciadora([
            for (final l in pr.listas!)
              (
                nombre: l.lista,
                financiadora: l.financiadora,
                precios: {p.codigo: l.precio},
              ),
          ], fin, p.codigo, nombreLista: lista);
        }
        pf ??= precioEnListaFinanciadora(listas, fin, p.codigo,
            nombreLista: lista);
      }
      return EquipoVendidoCF(
        codigo: p.codigo,
        imei: imei,
        nombre: p.nombre.isEmpty ? p.codigo : p.nombre,
        costo: pr.costo,
        precioContado: pr.venta,
        precioFinanciadora: pf,
        origenPrecio: pr.origen,
      );
    }

    return FacturaCF(
      nroFactura: f.nroFactura,
      tienda: f.tienda,
      fecha: fecha,
      equipos: [
        for (final e in f.equipos) eq(e.producto, e.imei),
        for (final p in f.itemsSinImei) eq(p, ''),
      ],
      pagos: pagos,
    );
  }

  /// Tasas de cada día: las cargadas a mano (`cf_tasas_dia_*`), la
  /// tabla BCV y las tasas con que se cobró cada día.
  TasasPorDia get tasasPorDia => _tasasCache ??= TasasPorDia(
        manuales: TasasPorDia.leerManuales(config, _cfDecodificar),
        bcvTabla: bcvTabla,
        bcvVentas: {
          ...bcvDeLasVentas(facturasCF),
          // La foto de la factura guarda la BCV con que se facturó.
          for (final e in _fotos.entries)
            if (e.value.tasaBcv > 0) fechaIsoCF(e.value.momento): e.value.tasaBcv,
        },
        bcvActual: ConfigSistema.tasaCambio,
        divisaSugeridaHoy: ConfigSistema.tasaBinance,
      );

  /// Ventas del período, cada una con las tasas de SU día.
  List<VentaAnalizada> ventasAnalizadas(DateTime desde, DateTime hasta) {
    final t = tasasPorDia;
    return analizarFacturas(
        facturasCF.where((f) => enRangoCF(f.fecha, desde, hasta)),
        (d) => t.resolver(d).tasas);
  }

  /// Guarda (o borra, con 0) las tasas cargadas a mano para un día.
  Future<void> guardarTasaDia(DateTime dia,
      {required double divisa, required double bcv}) async {
    final clave = claveTasasDiaMes(dia.year, dia.month);
    final raw = await _Api.get('configuracion');
    final fresco = raw is Map ? Map<String, dynamic>.from(raw) : config;
    final actual = _cfDecodificar(fresco[clave]);
    final mapa = actual is Map
        ? Map<String, dynamic>.from(actual)
        : <String, dynamic>{};
    final reg = RegistroTasaDia(divisa: divisa, bcv: bcv).toJson();
    if (reg.isEmpty) {
      mapa.remove(fechaIsoCF(dia));
    } else {
      mapa[fechaIsoCF(dia)] = reg;
    }
    final txt = jsonEncode(mapa);
    await _Api.post('configuracion', {clave: txt});
    config = fresco..[clave] = txt;
    _tasasCache = null;
    notifyListeners();
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
    // Lo releído puede traer tasas del día cargadas en otro equipo.
    _tasasCache = null;
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
/// [colores] (opcional) pinta el fondo de cada fila (null = sin color).
Widget _cfTabla(List<String> columnas, List<List<Widget>> filas,
        {Color color = AppColors.brandBlue,
        List<int> numericas = const [],
        List<Color?>? colores}) =>
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
        rows: [
          for (var i = 0; i < filas.length; i++)
            DataRow(
                color: (colores != null &&
                        i < colores.length &&
                        colores[i] != null)
                    ? WidgetStateProperty.all(colores[i])
                    : null,
                cells: [for (final c in filas[i]) DataCell(c)]),
        ],
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

/// Tasas de cada día del período: la BCV (con su origen) y la divisa
/// (USDT / paralelo) que carga el dueño. Los días con ventas y sin tasa
/// divisa salen en rojo: el sistema no adivina la tasa de un día.
class _CfTasasDelDia extends StatelessWidget {
  final _DatosFinanzasCF datos;
  final DateTime desde, hasta;
  /// "AAAA-MM-DD" → cantidad de ventas de ese día.
  final Map<String, int> ventasPorDia;
  const _CfTasasDelDia({
    required this.datos,
    required this.desde,
    required this.hasta,
    required this.ventasPorDia,
  });

  static String _tasa(double v) => v > 0 ? v.toStringAsFixed(2) : '—';

  Future<void> _editar(BuildContext context, TasaDiaResuelta t) async {
    final manual = TasasPorDia.leerManuales(datos.config, _cfDecodificar)[
        fechaIsoCF(t.dia)];
    final div = TextEditingController(
        text: t.divisa > 0 ? t.divisa.toStringAsFixed(2) : '');
    final bcv = TextEditingController(
        text: (manual?.bcv ?? 0) > 0 ? manual!.bcv.toStringAsFixed(2) : '');
    double leer(TextEditingController c) =>
        double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tasas del ${_cfFecha(t.dia)}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: div,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Tasa divisa del día (Bs por \$)',
                helperText: 'A la que vendiste los Bs (USDT / paralelo)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: bcv,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Tasa BCV del día (opcional)',
                helperText: t.bcv > 0
                    ? 'Vacío = ${t.bcv.toStringAsFixed(2)} (${t.fuenteBcv})'
                    : 'Vacío = la automática',
                border: const OutlineInputBorder(),
              ),
            ),
          ]),
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
    );
    final vDiv = leer(div), vBcv = leer(bcv);
    div.dispose();
    bcv.dispose();
    if (ok != true) return;
    try {
      await datos.guardarTasaDia(t.dia, divisa: vDiv, bcv: vBcv);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo guardar la tasa: $e'),
            backgroundColor: AppColors.statusRed));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // El día más reciente primero: es el que el dueño carga a diario.
    final dias = datos.tasasPorDia.dias(desde, hasta).reversed.toList();
    int ventas(TasaDiaResuelta t) => ventasPorDia[fechaIsoCF(t.dia)] ?? 0;
    final faltan =
        dias.where((t) => t.faltaDivisa && ventas(t) > 0).length;
    final sugeridas =
        dias.where((t) => t.divisaSugerida && ventas(t) > 0).length;
    return _cfTarjeta(
      'Tasas de cada día',
      Icons.calendar_month,
      Colors.teal,
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(
            'Cada venta se calcula con las tasas de SU día. Toca un día para '
            'cargar la tasa divisa (a la que vendiste los Bs). La BCV sale '
            'sola (de la tabla BCV o de las ventas de ese día); puedes '
            'corregirla si hace falta.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        if (faltan > 0 || sugeridas > 0)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.statusRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              [
                if (faltan > 0)
                  'Falta la tasa divisa de $faltan día(s) con ventas: esas '
                      'ventas se cuentan a precio de contado, sin diferencial.',
                if (sugeridas > 0)
                  'Hoy se está usando la tasa Binance configurada como '
                      'sugerida: confírmala tocando el día.',
              ].join('\n'),
              style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.statusRed,
                  fontWeight: FontWeight.w600),
            ),
          ),
        const SizedBox(height: 6),
        _cfTabla(
          ['Día', 'Ventas', 'Tasa BCV', 'Origen BCV', 'Tasa divisa', 'Estado',
            ''],
          [
            for (final t in dias)
              [
                Text(_cfFecha(t.dia)),
                Text('${ventas(t)}'),
                Text(_tasa(t.bcv)),
                Text(t.fuenteBcv.isEmpty ? '—' : t.fuenteBcv,
                    style: const TextStyle(
                        fontSize: 10.5, color: AppColors.textSecondary)),
                Text(_tasa(t.divisa),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  t.faltaDivisa
                      ? (ventas(t) > 0
                          ? 'Falta la tasa de este día'
                          : 'Sin tasa (sin ventas)')
                      : (t.divisaSugerida
                          ? 'Sugerida (Binance): confírmala'
                          : 'Cargada'),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: t.faltaDivisa
                          ? (ventas(t) > 0
                              ? AppColors.statusRed
                              : AppColors.textSecondary)
                          : (t.divisaSugerida
                              ? AppColors.statusOrange
                              : AppColors.statusGreen)),
                ),
                IconButton(
                  tooltip: 'Cargar tasas de este día',
                  icon: const Icon(Icons.edit, size: 18),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _editar(context, t),
                ),
              ],
          ],
          color: Colors.teal,
          numericas: const [1, 2, 4],
          colores: [
            for (final t in dias)
              (t.faltaDivisa && ventas(t) > 0)
                  ? AppColors.statusRed.withValues(alpha: 0.07)
                  : (t.divisaSugerida
                      ? AppColors.statusOrange.withValues(alpha: 0.07)
                      : null),
          ],
        ),
      ]),
    );
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
              'la financiadora, convertido a divisa con las tasas del día de '
              'la venta, ver Ganancia real) menos el costo del equipo. '
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

  static const _colsResumen = [
    '', 'Equipos', 'Cobrado al cliente\n(en divisa)',
    'Debe la financ.\n(\$ BCV)', 'Financiado\n(en divisa)',
    'Ingreso real\n(\$)', 'Valor de\ncontado', 'Diferencial\ncambiario',
    'Ganancia\nreal', 'Comisión financ.\n(informativa)',
  ];
  static const _numResumen = [1, 2, 3, 4, 5, 6, 7, 8, 9];

  List<Widget> _filaResumen(String nombre, ResumenGanancia r,
          {bool negrita = false}) =>
      [
        Text(r.sinTasa > 0 ? '$nombre  (${r.sinTasa} sin tasa)' : nombre,
            style: TextStyle(
                fontWeight: negrita ? FontWeight.bold : FontWeight.w600,
                color: r.sinTasa > 0 ? AppColors.statusRed : null)),
        Text('${r.unidades}'),
        _cfNum(r.cobradoEnDivisa),
        _cfNum(r.financiadoBcv),
        _cfNum(r.financiadoEnDivisa),
        _cfNum(r.ingresoEnDivisa, negrita: negrita),
        _cfNum(r.valorContado),
        _cfNum(r.diferencialCambiario, negrita: true),
        _cfNum(r.gananciaReal, negrita: negrita),
        _cfNum(r.comisionFinanciadora),
      ];

  static String _origen(String o) => switch (o) {
        origenPrecioFactura => 'de la factura',
        origenPrecioHistorial => 'historial',
        _ => 'actual',
      };

  /// Una fila por equipo: lo que el dueño compara con su Excel.
  Widget _ventaPorVenta(List<VentaAnalizada> ventas) {
    final ordenadas = [...ventas]..sort((a, b) => b.fecha.compareTo(a.fecha));
    final filas = <List<Widget>>[];
    final colores = <Color?>[];
    for (final v in ordenadas) {
      for (final e in v.equipos) {
        filas.add([
          Text(_cfFecha(v.fecha)),
          Text(v.nroFactura, style: const TextStyle(fontSize: 10.5)),
          Text(v.tienda),
          Text(v.esFinanciada ? v.financiadora : 'Contado'),
          Text(e.equipo.nombre.isEmpty ? e.equipo.codigo : e.equipo.nombre),
          _cfNum(e.precioContado),
          _cfNum(e.costo),
          Text(e.equipo.precioFinanciadora == null || !v.esFinanciada
              ? '—'
              : formatCurrency(e.equipo.precioFinanciadora!)),
          Text(v.faltaTasa
              ? 'falta'
              : '${v.tasaBcv.toStringAsFixed(2)} / '
                  '${v.tasaDivisa.toStringAsFixed(2)}'),
          _cfNum(e.ingresoEnDivisa),
          _cfNum(e.diferencialCambiario, negrita: true),
          _cfNum(e.gananciaReal),
          _cfNum(e.gananciaTotal),
          Text(_origen(e.equipo.origenPrecio),
              style: TextStyle(
                  fontSize: 10.5,
                  color: e.equipo.origenPrecio == origenPrecioActual
                      ? AppColors.statusOrange
                      : AppColors.textSecondary)),
        ]);
        colores.add(
            v.faltaTasa ? AppColors.statusRed.withValues(alpha: 0.07) : null);
      }
    }
    return _cfTabla(
      ['Día', 'Factura', 'Tienda', 'Financiadora', 'Equipo',
        'Precio\ncontado', 'Costo', 'Precio\nfinanc.', 'Tasa BCV /\ndivisa',
        'Ingreso\nreal \$', 'Diferencial', 'Ganancia\nreal',
        'Ganancia\ntotal', 'Precio'],
      filas,
      color: Colors.indigo,
      numericas: const [5, 6, 7, 9, 10, 11, 12],
      colores: colores,
    );
  }

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
        final porDia = agruparGanancias(ventas, (v) => fechaIsoCF(v.fecha));
        final diasOrden = porDia.keys.toList()..sort();
        final ventasPorDia = {
          for (final e in porDia.entries) e.key: e.value.facturas,
        };
        final porTienda = agruparGanancias(ventas, (v) => v.tienda);
        final gastos = d.gastosEntre(_desde, _hasta);
        double gastosDe(String t) => gastos
            .where((g) => g.tienda == t)
            .fold<double>(0, (s, g) => s + g.montoUsd);
        final gastosTotal =
            gastos.fold<double>(0, (s, g) => s + g.montoUsd);
        final tiendas = d.tiendas(porTienda.keys);
        final sinHistorial = ventas
            .expand((v) => v.equipos)
            .where((e) => e.equipo.origenPrecio == origenPrecioActual)
            .length;

        return _cfContenedor([
          _cfAyuda(
              'Se calcula VENTA POR VENTA con las tasas de SU día, como en tu '
              'Excel.\n'
              'GANANCIA REAL = precio de CONTADO − costo (contado 100, costo 88: '
              'ganancia real 12).\n'
              'INGRESO REAL = lo que de verdad entró en dólares: los Bs cobrados '
              '÷ tasa divisa del día; los \$ tal cual; y lo que debe la '
              'financiadora (su lista − la inicial, en \$ BCV) × BCV del día ÷ '
              'tasa divisa del día. Ej.: lista Krece 127, inicial 38 a 879 = '
              '33.402 Bs ÷ 1015 = 32,91; Krece debe 89 × 879 ÷ 1015 = 77,07; '
              'ingreso real 109,98.\n'
              'DIFERENCIAL CAMBIARIO = ingreso real − precio de contado '
              '(109,98 − 100 = 9,98). La comisión de la financiadora no se '
              'descuenta: sale aparte como dato.\n'
              'Precio y costo son los del DÍA DE LA VENTA (los guardados con la '
              'factura o el historial de precios), no los de hoy.'),
          _CfSelectorRango(
              desde: _desde,
              hasta: _hasta,
              onCambio: (a, b) => setState(() {
                    _desde = a;
                    _hasta = b;
                  })),
          const SizedBox(height: 8),
          _cfKpis([
            _cfKpi('Ganancia real (contado − costo)',
                formatCurrency(total.gananciaReal), AppColors.statusGreen,
                sub: '${total.unidades} equipos/artículos'),
            _cfKpi('Diferencial cambiario',
                formatCurrency(total.diferencialCambiario), Colors.indigo,
                sub: total.sinTasa > 0
                    ? '${total.sinTasa} venta(s) sin tasa del día'
                    : 'financiamiento y tasa'),
            _cfKpi('Ganancia total', formatCurrency(total.gananciaTotal),
                AppColors.brandBlue,
                sub: 'real + diferencial'),
            _cfKpi('Ingreso real en \$', formatCurrency(total.ingresoEnDivisa),
                Colors.teal,
                sub: 'contado: ${formatCurrency(total.valorContado)}'),
            _cfKpi('Costo de lo vendido', formatCurrency(total.costo),
                Colors.deepOrange),
            _cfKpi('Comisión financiadoras',
                formatCurrency(total.comisionFinanciadora),
                AppColors.textSecondary,
                sub: 'informativa: no se descuenta'),
          ]),
          if (sinHistorial > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  '$sinHistorial equipo(s) vendidos antes de que el sistema '
                  'guardara los precios usan el precio ACTUAL del inventario '
                  '(columna "Precio" = actual). Desde ahora cada factura guarda '
                  'sus precios y cada cambio de precio queda en el historial.',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.statusOrange)),
            ),
          if (total.sinTasa > 0)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.statusRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                  '${total.sinTasa} venta(s) son de días sin tasa divisa: van a '
                  'precio de contado, sin diferencial. Carga esas tasas en '
                  '"Tasas de cada día" (más abajo).',
                  style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.statusRed,
                      fontWeight: FontWeight.w600)),
            ),
          _cfTarjeta(
            'Diferencial por financiadora',
            Icons.currency_exchange,
            Colors.indigo,
            _cfTabla(_colsResumen.map((c) => c.isEmpty ? 'Financiadora' : c).toList(), [
              for (final e in porFin.entries) _filaResumen(e.key, e.value),
              _filaResumen('TOTAL', total, negrita: true),
            ], color: Colors.indigo, numericas: _numResumen),
          ),
          _CfTasasDelDia(
              datos: d,
              desde: _desde,
              hasta: _hasta,
              ventasPorDia: ventasPorDia),
          _cfTarjeta(
            'Día por día',
            Icons.calendar_view_day,
            Colors.indigo,
            diasOrden.isEmpty
                ? const Text('No hay ventas en el período.')
                : _cfTabla(_colsResumen.map((c) => c.isEmpty ? 'Día' : c).toList(), [
                    for (final k in diasOrden)
                      _filaResumen(
                          _cfFecha(parseFechaCF(k) ?? DateTime(2000)),
                          porDia[k]!),
                  ], color: Colors.indigo, numericas: _numResumen),
          ),
          _cfTarjeta(
            'Por tienda',
            Icons.storefront,
            Colors.indigo,
            _cfTabla(_colsResumen.map((c) => c.isEmpty ? 'Tienda' : c).toList(), [
              for (final t in tiendas)
                if (porTienda[t] != null) _filaResumen(t, porTienda[t]!),
              _filaResumen('TODAS', total, negrita: true),
            ], color: Colors.indigo, numericas: _numResumen),
          ),
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ExpansionTile(
              leading: const Icon(Icons.receipt_long, color: Colors.indigo),
              title: Text('Venta por venta (${ventas.length} facturas)',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
              subtitle: const Text(
                  'Cada equipo con su precio de contado, costo, ingreso real, '
                  'diferencial y ganancia, para compararlo con tu Excel.',
                  style: TextStyle(fontSize: 11)),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: ventas.isEmpty
                      ? const Text('No hay ventas en el período.')
                      : _ventaPorVenta(ventas),
                ),
              ],
            ),
          ),
          _cfTarjeta(
            'Balance neto por tienda',
            Icons.account_balance_wallet,
            AppColors.statusGreen,
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text(
                  'Ventas cobradas en divisa + montos financiados − costo de '
                  'los equipos − gastos de la tienda. Cada venta se convierte '
                  'con las tasas de su día; las que no tienen tasa van a precio '
                  'de contado.',
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
                        _cfNum(r.cobradoEnDivisa + r.contadoSinTasa),
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
                    _cfNum(total.cobradoEnDivisa + total.contadoSinTasa,
                        negrita: true),
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
