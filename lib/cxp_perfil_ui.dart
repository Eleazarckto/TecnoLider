part of 'main.dart';

// ════════════════════════════════════════════════════════════════════
//  CUENTAS POR PAGAR — PERFIL FIJO POR ACREEDOR Y ADJUNTOS
// ════════════════════════════════════════════════════════════════════
//  Lo pidió el dueño:
//   1. Una sola entrada por proveedor/persona aunque tenga varias
//      cuentas abiertas (antes "Maxi 2005" salía dos veces). Al tocarla
//      se ve el historial de facturas, el de pagos y el saldo a favor.
//   2. Arriba, el total que se debe Y el total que se tiene a favor
//      entre todos los acreedores.
//   3. Poder adjuntar la foto o el PDF de la factura del proveedor y el
//      comprobante de cada pago, y abrirlos desde el perfil.
//
//  La lógica sin interfaz (agrupar, reconstruir facturas, repartir un
//  pago) está en `cxp_perfil.dart` y tiene pruebas propias.
//
//  Las dos pantallas (proveedores y personas) usan modelos distintos
//  con los mismos campos; `CuentaCxp` los envuelve para no duplicar
//  toda la interfaz.
// ════════════════════════════════════════════════════════════════════

/// Envoltorio común de [CuentaPorPagar] y [CuentaPorPagarProveedor].
class CuentaCxp {
  final CuentaPorPagar? persona;
  final CuentaPorPagarProveedor? proveedor;

  CuentaCxp.persona(CuentaPorPagar c) : persona = c, proveedor = null;
  CuentaCxp.proveedor(CuentaPorPagarProveedor c)
      : persona = null, proveedor = c;

  bool get esProveedor => proveedor != null;

  /// Recurso del backend. También se usa como `ambito` de los
  /// comprobantes, para que no se mezclen con los de cuentas por cobrar
  /// (los ids de cuenta se repiten entre tablas).
  String get recurso =>
      esProveedor ? 'cuentas_pagar_proveedor' : 'cuentas_pagar';

  int get id => (proveedor?.id ?? persona?.id) ?? 0;
  String get nombre => proveedor?.nombre ?? persona!.nombre;
  String get rif => proveedor?.rif ?? persona!.rif;
  String get telefono => proveedor?.telefono ?? persona!.telefono;
  String get correo => proveedor?.correo ?? persona!.correo;
  String get fechaLimite => proveedor?.fechaLimite ?? '';

  double get montoTotal => proveedor?.montoTotal ?? persona!.montoTotal;
  set montoTotal(double v) {
    if (proveedor != null) {
      proveedor!.montoTotal = v;
    } else {
      persona!.montoTotal = v;
    }
  }

  String get notas => proveedor?.notas ?? persona!.notas;
  set notas(String v) {
    if (proveedor != null) {
      proveedor!.notas = v;
    } else {
      persona!.notas = v;
    }
  }

  double get favorApartado =>
      proveedor?.favorApartado ?? persona!.favorApartado;
  set favorApartado(double v) {
    if (proveedor != null) {
      proveedor!.favorApartado = v;
    } else {
      persona!.favorApartado = v;
    }
  }

  List<Map<String, dynamic>> get pagos => proveedor?.pagos ?? persona!.pagos;
  List<CuotaCobrar> get cuotas => proveedor?.cuotas ?? persona!.cuotas;
  double get totalPagado => proveedor?.totalPagado ?? persona!.totalPagado;
  double get totalCuotasPagadas =>
      proveedor?.totalCuotasPagadas ?? persona!.totalCuotasPagadas;
  double get saldoRestante =>
      proveedor?.saldoRestante ?? persona!.saldoRestante;
  double get saldoFavor => proveedor?.saldoFavor ?? persona!.saldoFavor;
  CuotaCobrar? get proximaCuota =>
      esProveedor ? proveedor!.proximaCuota : persona!.proximaCuota;

  /// Cabecera completa (incluye `notas`, que guarda el saldo apartado:
  /// todo PUT debe llevarla o se pierde).
  Map<String, dynamic> toMap() => proveedor?.toMap() ?? persona!.toMap();

  /// Notas sin la marca del saldo apartado pero CON las marcas de
  /// adjunto, para reescribirlas sin perder el vínculo con las facturas.
  String get notasSinFavor => notas.replaceAll(_reFavorApartado, '').trim();
}

bool get _puedeEditarCxp =>
    usuarioSesion?.rol == "Administrador" ||
    usuarioSesion?.rol == "Maestro" ||
    usuarioSesion?.rol == "Dueño";

// ── Adjuntos ──────────────────────────────────────────────────────

class _AdjuntoCxp {
  final int id;
  final String tipo; // 'factura' | 'aumento_deuda' | 'pago'
  final int cuentaId;
  final String ext;
  final String base64;
  final String fecha;
  const _AdjuntoCxp({
    required this.id,
    required this.tipo,
    required this.cuentaId,
    required this.ext,
    required this.base64,
    required this.fecha,
  });

  bool get esPdf => ext == 'pdf';

  String get etiqueta {
    switch (tipo) {
      case 'factura': return 'Factura inicial';
      case 'aumento_deuda': return 'Factura';
      case 'pago': return 'Comprobante de pago';
      default: return tipo;
    }
  }
}

int _aInt(dynamic v) => v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

/// Trae los adjuntos de todas las cuentas del acreedor.
///
/// Se filtra por `ambito` también acá: si el servidor todavía tiene el
/// `comprobantes.php` viejo (que ignora ese parámetro) devolvería
/// mezclados los de la cuenta por cobrar con el mismo id.
Future<List<_AdjuntoCxp>> _cargarAdjuntosCxp(List<CuentaCxp> cuentas) async {
  final respuestas = await Future.wait(cuentas.map((c) => _Api.get(
      'comprobantes', {'cuenta_id': '${c.id}', 'ambito': c.recurso})));
  final out = <_AdjuntoCxp>[];
  for (var i = 0; i < cuentas.length; i++) {
    final lista = respuestas[i];
    if (lista is! List) continue;
    for (final raw in lista) {
      if (raw is! Map) continue;
      final ambito = (raw['ambito'] ?? 'cuentas_cobrar').toString();
      if (ambito != cuentas[i].recurso) continue;
      out.add(_AdjuntoCxp(
        id: _aInt(raw['id']),
        tipo: (raw['entidad_tipo'] ?? '').toString(),
        cuentaId: _aInt(raw['cuenta_id']),
        ext: (raw['imagen_ext'] ?? 'jpg').toString().toLowerCase(),
        base64: (raw['imagen_base64'] ?? '').toString(),
        fecha: (raw['created_at'] ?? '').toString(),
      ));
    }
  }
  return out;
}

/// Límite del archivo antes de pasarlo a base64. El servidor corta en
/// 8 MB de base64 (≈ 6 MB reales); dejamos margen.
const int _maxBytesAdjuntoCxp = 5 * 1024 * 1024 + 512 * 1024;

/// Pide una foto (cámara o galería) o un PDF. Devuelve (bytes, ext) o
/// null si el usuario cancela.
///
/// La cámara sólo se ofrece en Android/iOS: en Windows `image_picker`
/// no la soporta. La galería y el PDF funcionan en las tres.
Future<(Uint8List, String)?> _seleccionarAdjuntoCxp(BuildContext context) async {
  final hayCamara = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  final origen = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(child: Wrap(children: [
      if (hayCamara)
        ListTile(
          leading: const Icon(Icons.camera_alt_outlined),
          title: const Text('Tomar foto (cámara)'),
          onTap: () => Navigator.pop(ctx, 'camara'),
        ),
      ListTile(
        leading: const Icon(Icons.photo_library_outlined),
        title: const Text('Elegir imagen'),
        onTap: () => Navigator.pop(ctx, 'galeria'),
      ),
      ListTile(
        leading: const Icon(Icons.picture_as_pdf_outlined),
        title: const Text('Elegir PDF'),
        onTap: () => Navigator.pop(ctx, 'archivo'),
      ),
    ])),
  );
  if (origen == null) return null;
  try {
    Uint8List? bytes;
    String ext = 'jpg';
    if (origen == 'archivo') {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return null;
      final f = res.files.first;
      bytes = f.bytes;
      // En algunos escritorios `withData` llega vacío: leemos la ruta.
      if (bytes == null && !kIsWeb && f.path != null) {
        bytes = await File(f.path!).readAsBytes();
      }
      ext = (f.extension ?? 'pdf').toLowerCase();
    } else {
      final xf = await ImagePicker().pickImage(
        source: origen == 'camara' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (xf == null) return null;
      bytes = await xf.readAsBytes();
      final e = xf.name.contains('.')
          ? xf.name.split('.').last.toLowerCase() : 'jpg';
      ext = const ['jpg', 'jpeg', 'png', 'webp'].contains(e) ? e : 'jpg';
    }
    if (bytes == null) return null;
    if (bytes.length > _maxBytesAdjuntoCxp) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('El archivo pesa más de 5 MB. Si es una foto, '
              'tómala de nuevo o elige una más liviana.'),
          backgroundColor: AppColors.statusRed));
      }
      return null;
    }
    return (bytes, ext);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No se pudo leer el archivo: $e'),
        backgroundColor: AppColors.statusRed));
    }
    return null;
  }
}

/// Sube el adjunto y devuelve su id. Lanza excepción si falla.
Future<int> _subirAdjuntoCxp({
  required CuentaCxp cuenta,
  required String tipo,
  required Uint8List bytes,
  required String ext,
}) async {
  final r = await _Api.post('comprobante_guardar', {
    'ambito'       : cuenta.recurso,
    'entidad_tipo' : tipo,
    'entidad_id'   : cuenta.id,
    'cuenta_id'    : cuenta.id,
    'imagen_ext'   : ext,
    'imagen_base64': base64Encode(bytes),
  });
  final id = r is Map ? _aInt(r['id']) : 0;
  if (r is Map && r['ok'] == false) {
    throw Exception((r['error'] ?? r['message'] ?? 'rechazado').toString());
  }
  if (id <= 0) throw Exception('El servidor no devolvió el id del adjunto');
  return id;
}

/// Muestra la imagen dentro de la app (sirve igual en Android, iPad y
/// Windows) o abre el PDF con el visor del sistema.
Future<void> _abrirAdjuntoCxp(BuildContext context, _AdjuntoCxp a) async {
  Uint8List bytes;
  try {
    bytes = base64Decode(a.base64);
  } catch (_) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('El adjunto está dañado y no se puede abrir.')));
    return;
  }
  Future<void> abrirExterno() async {
    try {
      final tmp = await getTemporaryDirectory();
      final f = File('${tmp.path}/adjunto_cxp_${a.id}.${a.ext}');
      await f.writeAsBytes(bytes, flush: true);
      final res = await OpenFilex.open(f.path);
      if (res.type != ResultType.done && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo abrir: ${res.message}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo abrir: $e')));
      }
    }
  }

  if (a.esPdf) return abrirExterno();
  await showDialog(
    context: context,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.image_outlined),
          title: Text(a.etiqueta),
          subtitle: Text(a.fecha),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Abrir con otra aplicación',
              icon: const Icon(Icons.open_in_new),
              onPressed: abrirExterno,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
          ]),
        ),
        Flexible(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.memory(bytes,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No se pudo mostrar la imagen'))),
          ),
        ),
      ]),
    ),
  );
}

/// Si hay un solo adjunto lo abre; si hay varios, deja elegir.
Future<void> _verAdjuntosCxp(
    BuildContext context, List<_AdjuntoCxp> lista, {String titulo = 'Adjuntos'}) async {
  if (lista.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay adjuntos cargados.')));
    return;
  }
  if (lista.length == 1) return _abrirAdjuntoCxp(context, lista.first);
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final a in lista)
              ListTile(
                leading: Icon(
                    a.esPdf ? Icons.picture_as_pdf : Icons.image_outlined,
                    color: a.esPdf ? AppColors.statusRed : AppColors.royalBlue),
                title: Text(a.etiqueta),
                subtitle: Text('${a.fecha} · .${a.ext}'),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => _abrirAdjuntoCxp(ctx, a),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
      ],
    ),
  );
}

// ── Lista de perfiles (pantalla principal) ─────────────────────────

/// Cuerpo de las pantallas "Cuentas por Pagar" y "CxP Proveedores":
/// resumen general arriba y una tarjeta por acreedor.
class VistaPerfilesCxp extends StatefulWidget {
  final List<CuentaCxp> cuentas;
  final bool esProveedor;
  final bool cargando;
  final Future<void> Function() onRecargar;
  const VistaPerfilesCxp({
    super.key,
    required this.cuentas,
    required this.esProveedor,
    required this.cargando,
    required this.onRecargar,
  });

  @override
  State<VistaPerfilesCxp> createState() => _VistaPerfilesCxpState();
}

class _VistaPerfilesCxpState extends State<VistaPerfilesCxp> {
  String _query = '';

  List<GrupoAcreedor<CuentaCxp>> get _grupos => agruparPorAcreedor(
        widget.cuentas,
        nombre: (c) => c.nombre,
        id: (c) => c.id,
        saldoRestante: (c) => c.saldoRestante,
        saldoFavor: (c) => c.saldoFavor,
      );

  @override
  Widget build(BuildContext context) {
    final grupos = _grupos;
    // El resumen es SIEMPRE de todos los acreedores; la búsqueda sólo
    // filtra la lista de abajo.
    final resumen = resumirAcreedores(grupos);
    final q = normalizarNombreAcreedor(_query);
    final visibles = q.isEmpty
        ? grupos
        : grupos.where((g) => g.clave.contains(q) ||
            g.cuentas.any((c) => c.rif.toLowerCase()
                .contains(_query.trim().toLowerCase()))).toList();

    return Column(children: [
      _resumen(resumen),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: TextField(
          decoration: InputDecoration(
            hintText: widget.esProveedor
                ? 'Buscar proveedor o RIF...'
                : 'Buscar por nombre o RIF...',
            prefixIcon: const Icon(Icons.search, color: AppColors.primaryBlue),
            filled: true, fillColor: Colors.white,
            isDense: true,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      if (widget.cargando)
        const Expanded(child: Center(child: CircularProgressIndicator()))
      else if (visibles.isEmpty)
        Expanded(child: EmptyState(
          mensaje: grupos.isEmpty
              ? 'No hay cuentas por pagar registradas.'
              : 'Ningún acreedor coincide con la búsqueda.',
          icono: Icons.business_outlined))
      else
        Expanded(child: RefreshIndicator(
          onRefresh: widget.onRecargar,
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
            itemCount: visibles.length,
            itemBuilder: (_, i) => _tarjeta(visibles[i]),
          ),
        )),
    ]);
  }

  Widget _resumen(ResumenAcreedores r) {
    Widget bloque(String titulo, double monto, String detalle, Color color,
        IconData icono) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icono, size: 14, color: Colors.white70),
            const SizedBox(width: 4),
            Flexible(child: Text(titulo,
                style: const TextStyle(color: Colors.white70,
                    fontSize: 11, letterSpacing: 0.8))),
          ]),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatCurrency(monto),
                style: const TextStyle(color: Colors.white,
                    fontSize: 24, fontWeight: FontWeight.bold)),
          ),
          Text(detalle,
              style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ]),
      ),
    );

    final quien = widget.esProveedor ? 'proveedor' : 'acreedor';
    String plural(int n) => '$n $quien${n == 1 ? '' : 'es'}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.royalBlue, Color(0xFF003580)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          bloque('DEUDA TOTAL', r.deudaTotal,
              'con ${plural(r.conDeuda)}',
              AppColors.statusRed, Icons.trending_down),
          const SizedBox(width: 10),
          bloque('SALDO A FAVOR', r.favorTotal,
              'con ${plural(r.conFavor)}',
              AppColors.statusGreen, Icons.savings_outlined),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text(
            r.favorTotal > 0.005
                ? 'Neto (deuda − a favor): ${formatCurrency(r.neto)}'
                : '${plural(r.acreedores)} en total',
            style: const TextStyle(color: Colors.white, fontSize: 12,
                fontWeight: FontWeight.w600))),
          if (r.favorTotal > 0.005)
            Text(plural(r.acreedores),
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _tarjeta(GrupoAcreedor<CuentaCxp> g) {
    final saldado = !g.tieneDeuda;
    final facturas = g.cuentas.fold<int>(0, (s, c) => s + extraerFacturas(
        cuentaId: c.id, montoTotal: c.montoTotal, notas: c.notas).length);
    // Próximo vencimiento entre las cuentas que aún deben algo.
    String vence = '';
    DateTime? venceFecha;
    CuotaCobrar? cuota;
    for (final c in g.cuentas.where((c) => c.saldoRestante > 0.005)) {
      final f = parsearFechaDMY(c.fechaLimite);
      if (f != null && (venceFecha == null || f.isBefore(venceFecha))) {
        venceFecha = f;
        vence = c.fechaLimite;
      }
      cuota ??= c.proximaCuota;
    }
    final vencida = venceFecha != null &&
        venceFecha.isBefore(DateTime.now().subtract(const Duration(days: 1)));
    final rif = g.cuentas.last.rif;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: saldado
            ? BorderSide(color: AppColors.statusGreen.withValues(alpha: 0.6))
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => PerfilAcreedorCxp(
                cuentas: g.cuentas, esProveedor: widget.esProveedor)))
            .then((_) => widget.onRecargar()),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: (saldado ? AppColors.statusGreen
                  : AppColors.statusRed).withValues(alpha: 0.12),
              child: Text(
                g.nombre.isEmpty ? '?' : g.nombre[0].toUpperCase(),
                style: TextStyle(fontWeight: FontWeight.bold,
                    color: saldado ? AppColors.statusGreen
                        : AppColors.statusRed)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.nombre, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600,
                      fontSize: 15)),
              Text([
                if (rif.isNotEmpty) 'RIF: $rif',
                '$facturas factura${facturas == 1 ? '' : 's'}',
              ].join(' · '),
                  style: const TextStyle(fontSize: 11,
                      color: AppColors.textSecondary)),
              if (vence.isNotEmpty)
                Text('Vence: $vence${vencida ? ' (vencida)' : ''}',
                    style: TextStyle(fontSize: 11,
                        color: vencida ? AppColors.statusRed
                            : AppColors.statusOrange,
                        fontWeight: vencida ? FontWeight.bold
                            : FontWeight.normal)),
              if (cuota != null)
                Text('Cuota ${cuota.numero}: ${formatCurrency(cuota.monto)}'
                    ' · ${cuota.fecha}',
                    style: const TextStyle(fontSize: 11,
                        color: AppColors.statusOrange)),
            ])),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(saldado ? 'SALDADO' : 'DEBES',
                  style: TextStyle(fontSize: 9, letterSpacing: 0.5,
                      fontWeight: FontWeight.bold,
                      color: saldado ? AppColors.statusGreen
                          : AppColors.statusRed)),
              if (!saldado)
                Text(formatCurrency(g.deuda),
                    style: const TextStyle(fontWeight: FontWeight.bold,
                        fontSize: 16, color: AppColors.statusRed)),
              if (g.tieneFavor) ...[
                const SizedBox(height: 2),
                ChipSaldoFavor(saldoFavor: g.favor),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

// ── Perfil del acreedor ───────────────────────────────────────────

class PerfilAcreedorCxp extends StatefulWidget {
  /// Cuentas del acreedor, de la más antigua a la más nueva.
  final List<CuentaCxp> cuentas;
  final bool esProveedor;
  const PerfilAcreedorCxp(
      {super.key, required this.cuentas, required this.esProveedor});

  @override
  State<PerfilAcreedorCxp> createState() => _PerfilAcreedorCxpState();
}

class _PerfilAcreedorCxpState extends State<PerfilAcreedorCxp> {
  List<_AdjuntoCxp> _adjuntos = [];
  bool _cargandoAdjuntos = true;
  String? _errorAdjuntos;
  bool _ocupado = false;

  List<CuentaCxp> get _cuentas => widget.cuentas;
  /// Las facturas nuevas y el excedente de los pagos van a la cuenta
  /// más reciente del acreedor.
  CuentaCxp get _principal => _cuentas.last;
  CuentaCxp _cuentaPorId(int id) =>
      _cuentas.firstWhere((c) => c.id == id, orElse: () => _principal);

  double get _deuda => _cuentas.fold(0.0, (s, c) => s + c.saldoRestante);
  double get _favor => _cuentas.fold(0.0, (s, c) => s + c.saldoFavor);

  @override
  void initState() {
    super.initState();
    _recargarAdjuntos();
  }

  Future<void> _recargarAdjuntos() async {
    setState(() { _cargandoAdjuntos = true; _errorAdjuntos = null; });
    try {
      final l = await _cargarAdjuntosCxp(_cuentas);
      if (!mounted) return;
      setState(() => _adjuntos = l);
    } catch (e) {
      debugPrint('[PerfilAcreedorCxp] adjuntos: $e');
      if (mounted) setState(() => _errorAdjuntos = '$e');
    } finally {
      if (mounted) setState(() => _cargandoAdjuntos = false);
    }
  }

  void _aviso(String msg, {bool error = false, int segundos = 4}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: Duration(seconds: segundos),
      backgroundColor: error ? AppColors.statusRed : AppColors.statusGreen));
  }

  // ── Datos derivados ──

  List<FacturaAcreedor> get _facturas => ordenarPorFechaDesc(
      [for (final c in _cuentas)
        ...extraerFacturas(
            cuentaId: c.id, montoTotal: c.montoTotal, notas: c.notas)],
      (f) => f.fecha);

  List<PagoAcreedor> get _pagos => ordenarPorFechaDesc(
      [for (final c in _cuentas)
        ...extraerPagos(
          cuentaId: c.id,
          pagos: c.pagos,
          cuotasPagadas: [
            for (final q in c.cuotas.where((q) => q.pagada))
              (q.numero, q.monto, q.fechaPago ?? ''),
          ],
        )],
      (p) => p.fecha);

  List<_AdjuntoCxp> _adjuntosDeFactura(FacturaAcreedor f) => f.esOriginal
      ? _adjuntos.where((a) =>
          a.tipo == 'factura' && a.cuentaId == f.cuentaId).toList()
      : _adjuntos.where((a) => f.comprobantes.contains(a.id)).toList();

  List<_AdjuntoCxp> _adjuntosDePago(PagoAcreedor p) =>
      _adjuntos.where((a) => p.comprobantes.contains(a.id)).toList();

  /// Adjuntos que no quedaron enlazados a ninguna factura ni pago (por
  /// ejemplo si falló el guardado del vínculo). Se muestran aparte para
  /// que no se pierdan.
  List<_AdjuntoCxp> get _adjuntosSueltos {
    final usados = <int>{
      for (final f in _facturas) ..._adjuntosDeFactura(f).map((a) => a.id),
      for (final p in _pagos) ...p.comprobantes,
    };
    return _adjuntos.where((a) => !usados.contains(a.id)).toList();
  }

  // ── Acciones ──

  /// Pregunta si se quiere adjuntar algo. Devuelve null si no.
  Future<(Uint8List, String)?> _ofrecerAdjunto(String pregunta) async {
    final si = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.attach_file, color: AppColors.royalBlue),
          SizedBox(width: 8),
          Expanded(child: Text('Adjuntar')),
        ]),
        content: Text(pregunta),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Ahora no')),
          ElevatedButton.icon(
            icon: const Icon(Icons.attach_file, size: 18),
            label: const Text('Foto o PDF'),
            onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (si != true || !mounted) return null;
    return _seleccionarAdjuntoCxp(context);
  }

  /// Sube el adjunto; si falla avisa y devuelve null para que la
  /// operación principal (factura o pago) se guarde igual.
  Future<int?> _subirOAvisar(CuentaCxp c, String tipo,
      (Uint8List, String)? archivo) async {
    if (archivo == null) return null;
    try {
      return await _subirAdjuntoCxp(
          cuenta: c, tipo: tipo, bytes: archivo.$1, ext: archivo.$2);
    } catch (e) {
      _aviso('No se pudo subir el adjunto: $e', error: true, segundos: 6);
      return null;
    }
  }

  Future<void> _agregarFactura() async {
    final c = _principal;
    final res = await pedirAgregarDeuda(
      context,
      nombreAcreedor: c.nombre,
      montoTotal    : c.montoTotal,
      pagado        : c.totalPagado + c.totalCuotasPagadas,
      favorApartado : c.favorApartado,
      saldoFavor    : c.saldoFavor,
    );
    if (res == null || !mounted) return;
    final archivo = await _ofrecerAdjunto(
        '¿Quieres adjuntar la foto o el PDF de esta factura?');
    setState(() => _ocupado = true);
    final compId = await _subirOAvisar(c, 'aumento_deuda', archivo);

    final montoAnterior = c.montoTotal;
    final notasAnteriores = c.notas;
    var linea = lineaNotaAumento(res);
    if (compId != null) linea = agregarMarcaComprobante(linea, compId);
    final base = c.notasSinFavor;
    c.montoTotal = res.nuevoMontoTotal;
    c.notas = base.isEmpty ? linea : '$base\n$linea';
    c.favorApartado = res.nuevoFavorApartado;
    try {
      await _Api.put(c.recurso, '${c.id}', c.toMap());
      _aviso(res.aplicadoDeFavor > 0.001
          ? 'Factura agregada. Se aplicaron '
            '${formatCurrency(res.aplicadoDeFavor)} de saldo a favor; '
            'quedan ${formatCurrency(res.pendienteDeEstaFactura)} pendientes.'
          : 'Factura de ${formatCurrency(res.monto)} agregada.',
          segundos: 6);
    } catch (e) {
      c.montoTotal = montoAnterior;
      c.notas = notasAnteriores;
      _aviso('No se pudo guardar la factura: $e', error: true);
    }
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (compId != null) _recargarAdjuntos();
  }

  Future<void> _adjuntarAFactura(FacturaAcreedor f) async {
    final archivo = await _seleccionarAdjuntoCxp(context);
    if (archivo == null || !mounted) return;
    final c = _cuentaPorId(f.cuentaId);
    setState(() => _ocupado = true);
    final compId = await _subirOAvisar(
        c, f.esOriginal ? 'factura' : 'aumento_deuda', archivo);
    if (compId != null && !f.esOriginal && f.lineaNotas != null) {
      // La factura agregada se identifica por su línea en la bitácora:
      // ahí se anota el id del adjunto.
      final anteriores = c.notas;
      final lineas = c.notas.split('\n');
      if (f.lineaNotas! < lineas.length) {
        lineas[f.lineaNotas!] =
            agregarMarcaComprobante(lineas[f.lineaNotas!], compId);
        c.notas = lineas.join('\n');
        try {
          await _Api.put(c.recurso, '${c.id}', c.toMap());
        } catch (e) {
          c.notas = anteriores;
          _aviso('El archivo se subió pero no se pudo enlazar a la '
              'factura: $e. Queda en "Otros adjuntos".', error: true);
        }
      }
    }
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (compId != null) {
      _aviso('Adjunto guardado.');
      _recargarAdjuntos();
    }
  }

  Future<void> _adjuntarAPago(PagoAcreedor p) async {
    if (p.esCuota || p.indice < 0) return;
    final archivo = await _seleccionarAdjuntoCxp(context);
    if (archivo == null || !mounted) return;
    final c = _cuentaPorId(p.cuentaId);
    if (p.indice >= c.pagos.length) return;
    setState(() => _ocupado = true);
    final compId = await _subirOAvisar(c, 'pago', archivo);
    if (compId != null) {
      final pago = c.pagos[p.indice];
      final notasAnt = pago['notas'];
      pago['notas'] = agregarMarcaComprobante(pago['notas']?.toString(), compId);
      try {
        // Los pagos se mandan completos: el backend los reemplaza todos.
        await _Api.put(c.recurso, '${c.id}', {
          ...c.toMap(),
          'pagos': c.pagos.map((m) => Map<String, dynamic>.from(m)).toList(),
        });
      } catch (e) {
        pago['notas'] = notasAnt;
        _aviso('El archivo se subió pero no se pudo enlazar al pago: $e. '
            'Queda en "Otros adjuntos".', error: true);
      }
    }
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (compId != null) {
      _aviso('Comprobante guardado.');
      _recargarAdjuntos();
    }
  }

  void _registrarPago() {
    final montoCtrl = TextEditingController();
    final tasaCtrl = TextEditingController(
        text: ConfigSistema.tasaCambio.toStringAsFixed(2));
    final refCtrl = TextEditingController();
    final metodos = ConfigSistema.metodossPago.isNotEmpty
        ? ConfigSistema.metodossPago
        : const ["Efectivo \$", "Efectivo Bs", "Pago móvil",
            "Transferencia", "Zelle", "Punto"];
    String metodo = metodos.contains("Efectivo \$") ? "Efectivo \$" : metodos.first;
    (Uint8List, String)? archivo;
    bool guardando = false;
    final formKey = GlobalKey<FormState>();
    final pendientes = _cuentas.where((c) => c.saldoRestante > 0.005).length;

    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final enBs = esMetodoEnBolivares(metodo);
        return AlertDialog(
          title: const Row(children: [
            Icon(Icons.attach_money, color: AppColors.statusGreen),
            SizedBox(width: 8),
            Expanded(child: Text('Registrar pago')),
          ]),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(child: Column(
                mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.statusRed.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                    const Text('Pendiente:', style: TextStyle(fontSize: 13,
                        color: AppColors.textSecondary)),
                    Text(formatCurrency(_deuda), style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold,
                        color: AppColors.statusRed)),
                  ]),
                  if (_favor > 0.005)
                    Text('Ya tienes ${formatCurrency(_favor)} a favor',
                        style: const TextStyle(fontSize: 11,
                            color: AppColors.statusGreen)),
                  if (pendientes > 1)
                    const Text('Se abona primero a las facturas más '
                        'antiguas.', style: TextStyle(fontSize: 11,
                        color: AppColors.textSecondary)),
                ]),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: metodo,
                isExpanded: true,
                items: metodos.map((e) =>
                    DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) { if (v != null) setS(() => metodo = v); },
                decoration: const InputDecoration(labelText: 'Método de pago',
                    prefixIcon: Icon(Icons.payment_outlined)),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: montoCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: enBs ? 'Monto en Bolívares (Bs)'
                      : 'Monto en Dólares (\$)',
                  prefixIcon: const Icon(Icons.attach_money)),
                validator: (v) {
                  final d = double.tryParse(
                      (v ?? '').trim().replaceAll(',', '.'));
                  return (d == null || d <= 0) ? 'Ingrese un monto válido' : null;
                },
              ),
              if (enBs) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: tasaCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Tasa de cambio (Bs/\$)',
                      prefixIcon: Icon(Icons.currency_exchange)),
                  validator: (v) {
                    final d = double.tryParse(
                        (v ?? '').trim().replaceAll(',', '.'));
                    return (d == null || d <= 0) ? 'Ingrese una tasa válida' : null;
                  },
                ),
              ],
              const SizedBox(height: 10),
              TextFormField(
                controller: refCtrl,
                decoration: const InputDecoration(
                    labelText: 'Referencia (opcional)',
                    prefixIcon: Icon(Icons.tag)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: Icon(archivo == null ? Icons.attach_file
                    : Icons.check_circle,
                    color: archivo == null ? AppColors.royalBlue
                        : AppColors.statusGreen),
                label: Text(archivo == null
                    ? 'Adjuntar comprobante (opcional)'
                    : 'Comprobante listo (${archivo!.$1.length ~/ 1024} KB)'),
                onPressed: () async {
                  final r = await _seleccionarAdjuntoCxp(ctx);
                  if (r != null) setS(() => archivo = r);
                },
              ),
            ])),
          ),
          actions: [
            TextButton(onPressed: guardando ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton.icon(
              icon: guardando
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 18),
              label: const Text('Registrar'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.statusGreen),
              onPressed: guardando ? null : () async {
                if (!formKey.currentState!.validate()) return;
                final monto = double.tryParse(
                    montoCtrl.text.trim().replaceAll(',', '.')) ?? 0;
                final tasa = double.tryParse(
                    tasaCtrl.text.trim().replaceAll(',', '.')) ?? 0;
                final montoUsd = enBs ? (tasa > 0 ? monto / tasa : 0.0) : monto;
                if (montoUsd <= 0) return;
                setS(() => guardando = true);
                final ok = await _guardarPago(
                    montoUsd: montoUsd, metodo: metodo,
                    referencia: refCtrl.text.trim(), archivo: archivo);
                if (ok && ctx.mounted) {
                  Navigator.pop(ctx);
                } else {
                  setS(() => guardando = false);
                }
              },
            ),
          ],
        );
      },
    ));
  }

  /// Guarda el pago repartido entre las cuentas del acreedor. Devuelve
  /// true si al menos una parte quedó registrada (el diálogo se cierra
  /// y la pantalla muestra lo que realmente se guardó).
  Future<bool> _guardarPago({
    required double montoUsd,
    required String metodo,
    required String referencia,
    (Uint8List, String)? archivo,
  }) async {
    final tramos = repartirPago(
      [for (final c in _cuentas) (c.id, c.saldoRestante)],
      montoUsd,
      idExcedente: _principal.id,
    );
    if (tramos.isEmpty) return false;
    final compId = await _subirOAvisar(
        _cuentaPorId(tramos.first.cuentaId), 'pago', archivo);
    final fecha = obtenerFechaActual();
    var hechos = 0;
    for (final t in tramos) {
      final c = _cuentaPorId(t.cuentaId);
      final nuevo = <String, dynamic>{
        'monto' : t.monto,
        'fecha' : fecha,
        'metodo': metodo,
        if (referencia.isNotEmpty) 'referencia': referencia,
        'notas' : compId != null ? agregarMarcaComprobante('', compId) : '',
      };
      try {
        // Igual que en el detalle de la cuenta: se manda el estado
        // completo de los pagos porque el backend los reemplaza.
        await _Api.put(c.recurso, '${c.id}', {
          ...c.toMap(),
          'pago': nuevo,
          'pagos': [
            ...c.pagos.map((p) => Map<String, dynamic>.from(p)),
            nuevo,
          ],
        });
        c.pagos.add(nuevo);
        hechos++;
      } catch (e) {
        if (mounted) setState(() {});
        _aviso(hechos == 0
            ? 'No se pudo registrar el pago: $e'
            : 'Sólo se registró una parte del pago ($hechos de '
              '${tramos.length}). Revisa el historial. Error: $e',
            error: true, segundos: 8);
        if (compId != null) _recargarAdjuntos();
        return hechos > 0;
      }
    }
    if (!mounted) return true;
    setState(() {});
    final favor = _favor;
    _aviso(favor > 0.005
        ? 'Pago de ${formatCurrency(montoUsd)} registrado. '
          'Quedan ${formatCurrency(favor)} a favor.'
        : 'Pago de ${formatCurrency(montoUsd)} registrado.',
        segundos: favor > 0.005 ? 6 : 4);
    if (compId != null) _recargarAdjuntos();
    return true;
  }

  void _abrirCuenta(CuentaCxp c) {
    final Widget pagina = c.esProveedor
        ? DetalleCuentaProveedor(cuenta: c.proveedor!)
        : DetalleCuentaPorPagar(cuenta: c.persona!);
    Navigator.push(context, MaterialPageRoute(builder: (_) => pagina))
        .then((_) { if (mounted) setState(() {}); });
  }

  // ── Interfaz ──

  @override
  Widget build(BuildContext context) {
    final p = _principal;
    final facturas = _facturas;
    final pagos = _pagos;
    final deuda = _deuda;
    final favor = _favor;
    final totalFacturado = _cuentas.fold(0.0, (s, c) => s + c.montoTotal);
    final totalPagado = pagos.fold(0.0, (s, x) => s + x.monto);
    final saldado = deuda <= 0.005;
    final sueltos = _cargandoAdjuntos ? <_AdjuntoCxp>[] : _adjuntosSueltos;

    return Scaffold(
      appBar: AppBar(
        title: Text(p.nombre),
        actions: [
          IconButton(
            icon: const Icon(Icons.attach_file),
            tooltip: 'Ver todos los adjuntos',
            onPressed: () => _verAdjuntosCxp(context, _adjuntos,
                titulo: 'Adjuntos de ${p.nombre}')),
          if (_puedeEditarCxp)
            IconButton(
              icon: const Icon(Icons.add_shopping_cart),
              tooltip: 'Agregar factura',
              onPressed: _ocupado ? null : _agregarFactura),
        ],
        bottom: _ocupado
            ? const PreferredSize(preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3))
            : null,
      ),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        // ── Resumen del acreedor ──
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Icon(widget.esProveedor ? Icons.business_outlined
                    : Icons.person_outline, color: AppColors.royalBlue),
                const SizedBox(width: 8),
                Expanded(child: Text(p.nombre, style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16))),
                if (saldado)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.statusGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20)),
                    child: const Text('SALDADO', style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.bold,
                        color: AppColors.statusGreen)),
                  ),
              ]),
              const Divider(height: 18),
              if (p.rif.isNotEmpty) _dato(Icons.receipt_outlined, 'RIF', p.rif),
              if (p.telefono.isNotEmpty)
                _dato(Icons.phone_outlined, 'Teléfono', p.telefono),
              if (p.correo.isNotEmpty)
                _dato(Icons.email_outlined, 'Correo', p.correo),
              const SizedBox(height: 10),
              Row(children: [
                _cifra('Facturado', totalFacturado, AppColors.textPrimary),
                _cifra('Pagado', totalPagado, AppColors.statusGreen),
              ]),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (saldado ? AppColors.statusGreen : AppColors.statusRed)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10)),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                  Text('SALDO PENDIENTE', style: TextStyle(
                      color: saldado ? AppColors.statusGreen
                          : AppColors.statusRed,
                      fontWeight: FontWeight.w600, fontSize: 12,
                      letterSpacing: 0.5)),
                  Text(formatCurrency(deuda), style: TextStyle(
                      color: saldado ? AppColors.statusGreen
                          : AppColors.statusRed,
                      fontWeight: FontWeight.bold, fontSize: 22)),
                ]),
              ),
              BannerSaldoFavor(
                saldoFavor: favor,
                nota: 'Pagaste de más. Al agregar la próxima factura '
                    'puedes descontarlo.',
              ),
            ]),
          ),
        ),
        const SizedBox(height: 14),

        // ── Facturas ──
        _titulo('Facturas', facturas.length, Icons.receipt_long_outlined),
        if (facturas.isEmpty)
          const Padding(padding: EdgeInsets.all(8),
              child: Text('Sin facturas.',
                  style: TextStyle(color: AppColors.textSecondary)))
        else
          ...facturas.map(_filaFactura),
        const SizedBox(height: 14),

        // ── Pagos ──
        _titulo('Pagos', pagos.length, Icons.payments_outlined),
        if (pagos.isEmpty)
          const Padding(padding: EdgeInsets.all(8),
              child: Text('Sin pagos registrados.',
                  style: TextStyle(color: AppColors.textSecondary)))
        else
          ...pagos.map(_filaPago),
        const SizedBox(height: 14),

        // ── Otros adjuntos ──
        if (_errorAdjuntos != null)
          Card(
            color: AppColors.statusOrange.withValues(alpha: 0.08),
            child: ListTile(
              leading: const Icon(Icons.cloud_off, color: AppColors.statusOrange),
              title: const Text('No se pudieron cargar los adjuntos'),
              subtitle: Text(_errorAdjuntos!, maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11)),
              trailing: IconButton(icon: const Icon(Icons.refresh),
                  onPressed: _recargarAdjuntos),
            ),
          ),
        if (sueltos.isNotEmpty) ...[
          _titulo('Otros adjuntos', sueltos.length, Icons.attach_file),
          ...sueltos.map((a) => Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              leading: Icon(a.esPdf ? Icons.picture_as_pdf : Icons.image_outlined,
                  color: a.esPdf ? AppColors.statusRed : AppColors.royalBlue),
              title: Text(a.etiqueta),
              subtitle: Text(a.fecha),
              onTap: () => _abrirAdjuntoCxp(context, a),
            ),
          )),
          const SizedBox(height: 14),
        ],

        // ── Cuentas individuales (cuotas, fecha límite, eliminar…) ──
        _titulo(_cuentas.length == 1 ? 'Cuenta' : 'Cuentas',
            _cuentas.length, Icons.folder_open_outlined),
        ..._cuentas.reversed.map((c) => Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.description_outlined),
            title: Text('Cuenta #${c.id} · ${formatCurrency(c.montoTotal)}'),
            subtitle: Text([
              c.saldoRestante > 0.005
                  ? 'Pendiente ${formatCurrency(c.saldoRestante)}'
                  : 'Saldada',
              if (c.fechaLimite.isNotEmpty) 'Vence ${c.fechaLimite}',
              if (c.cuotas.isNotEmpty)
                '${c.cuotas.where((q) => !q.pagada).length} cuota(s) pendiente(s)',
            ].join(' · ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _abrirCuenta(c),
          ),
        )),
        const SizedBox(height: 90),
      ]),
      floatingActionButton: _puedeEditarCxp
          ? FloatingActionButton.extended(
              onPressed: _ocupado ? null : _registrarPago,
              icon: const Icon(Icons.attach_money),
              label: const Text('Registrar pago'),
            )
          : null,
    );
  }

  Widget _titulo(String texto, int n, IconData icono) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(children: [
      Icon(icono, size: 18, color: AppColors.royalBlue),
      const SizedBox(width: 6),
      Text(texto, style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.primaryBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10)),
        child: Text('$n', style: const TextStyle(fontSize: 11,
            color: AppColors.primaryBlue, fontWeight: FontWeight.w600)),
      ),
    ]),
  );

  Widget _dato(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Icon(icon, size: 15, color: AppColors.textSecondary),
      const SizedBox(width: 6),
      Text('$label: ', style: const TextStyle(
          color: AppColors.textSecondary, fontSize: 13)),
      Expanded(child: Text(value, style: const TextStyle(
          fontWeight: FontWeight.w500, fontSize: 13))),
    ]),
  );

  Widget _cifra(String label, double monto, Color color) => Expanded(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
          fontSize: 11, color: AppColors.textSecondary)),
      Text(formatCurrency(monto), style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold, color: color)),
    ]),
  );

  /// Botón del clip: abre los adjuntos si hay, si no permite agregar.
  Widget _botonAdjunto(List<_AdjuntoCxp> lista, VoidCallback? adjuntar) {
    if (_cargandoAdjuntos) {
      return const SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (lista.isNotEmpty)
        IconButton(
          tooltip: 'Ver adjunto',
          icon: Badge(
            isLabelVisible: lista.length > 1,
            label: Text('${lista.length}'),
            child: Icon(lista.first.esPdf ? Icons.picture_as_pdf
                : Icons.image_outlined, color: AppColors.royalBlue),
          ),
          onPressed: () => _verAdjuntosCxp(context, lista),
        ),
      if (adjuntar != null && _puedeEditarCxp)
        IconButton(
          tooltip: 'Adjuntar foto o PDF',
          icon: const Icon(Icons.attach_file, color: AppColors.textSecondary),
          onPressed: _ocupado ? null : adjuntar,
        ),
    ]);
  }

  Widget _filaFactura(FacturaAcreedor f) {
    final adj = _adjuntosDeFactura(f);
    final titulo = f.concepto.isNotEmpty ? f.concepto
        : (f.esOriginal ? 'Factura inicial' : 'Factura');
    final sub = <String>[
      f.fecha.isNotEmpty ? f.fecha
          : (f.esOriginal ? 'Al abrir la cuenta' : ''),
      if (_cuentas.length > 1) 'cuenta #${f.cuentaId}',
      if (f.aplicadoDeFavor > 0.001)
        'se aplicó ${formatCurrency(f.aplicadoDeFavor)} a favor',
    ].where((s) => s.isNotEmpty).join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.statusRed.withValues(alpha: 0.1),
          child: const Icon(Icons.receipt_outlined,
              size: 18, color: AppColors.statusRed)),
        title: Text(formatCurrency(f.monto),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(sub.isEmpty ? titulo : '$titulo\n$sub',
            style: const TextStyle(fontSize: 12)),
        isThreeLine: sub.isNotEmpty,
        trailing: _botonAdjunto(adj, () => _adjuntarAFactura(f)),
      ),
    );
  }

  Widget _filaPago(PagoAcreedor x) {
    final adj = _adjuntosDePago(x);
    final sub = [
      x.fecha,
      if (x.referencia.isNotEmpty) 'Ref. ${x.referencia}',
      if (_cuentas.length > 1) 'cuenta #${x.cuentaId}',
    ].where((s) => s.isNotEmpty).join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.statusGreen.withValues(alpha: 0.12),
          child: Icon(x.esCuota ? Icons.event_available : Icons.payments_outlined,
              size: 18, color: AppColors.statusGreen)),
        title: Text(formatCurrency(x.monto), style: const TextStyle(
            fontWeight: FontWeight.bold, color: AppColors.statusGreen)),
        subtitle: Text('${x.metodo}${sub.isEmpty ? '' : ' · $sub'}',
            style: const TextStyle(fontSize: 12)),
        trailing: _botonAdjunto(adj,
            x.esCuota ? null : () => _adjuntarAPago(x)),
      ),
    );
  }
}
