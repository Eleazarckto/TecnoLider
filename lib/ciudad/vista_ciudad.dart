import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/movimiento.dart';

// ============================================================================
//  vista_ciudad.dart — El negocio visto como una ciudad
//
//  QUÉ ES
//  ------
//  Una maqueta isométrica y animada de la empresa: el almacén central en el
//  medio, cada tienda como un edificio en su isla y calles que las unen.
//  La idea viene de los tableros «gamificados» de operación: en vez de leer
//  una tabla, el dueño VE dónde hay movimiento.
//
//  NADA ES DECORACIÓN: CADA COSA QUE SE MUEVE ES UN DATO
//  -----------------------------------------------------
//    · La ALTURA de cada edificio es lo vendido en el mes, relativo a la
//      tienda que más vendió. La que más vende es la torre más alta.
//    · Las PERSONITAS que caminan hacia la puerta son las ventas de hoy
//      (una por factura, hasta siete para que no se amontonen). Una tienda
//      sin ventas hoy está quieta.
//    · Los CAMIONES son los traslados de hoy, sobre la ruta real de origen
//      a destino. Sin traslados, no circula ninguno.
//    · El letrero de cada tienda dice cuántas facturas lleva hoy.
//
//  Si el usuario pidió «reducir movimiento» en su sistema, la maqueta se
//  dibuja quieta: los datos siguen ahí, solo no se animan.
//
//  CÓMO SE MUEVE
//  -------------
//    · AL ABRIR, la ciudad se CONSTRUYE (1,8 s): aparece el terreno, las
//      calles se trazan desde el almacén, el almacén y luego cada tienda
//      suben desde el suelo con un pequeño rebote, los letreros caen en su
//      lugar y recién entonces arranca la vida (gente, camiones). La cámara
//      entra con un acercamiento suave.
//    · CUANDO CAMBIAN LOS DATOS (el panel se refresca), la cámara NO se
//      mueve y cada edificio crece o baja animado hasta su altura nueva: una
//      venta nueva se ve como el edificio que sube. Solo si cambian las
//      tiendas (una nueva, una menos) se rearma la ciudad.
//    · FUERA DE LA PANTALLA (el panel se bajó hasta los módulos) el reloj se
//      detiene: no se gasta batería dibujando algo que nadie ve.
//
//  CÓMO SE DIBUJA
//  --------------
//  Todo es un `CustomPainter` sobre una cuadrícula en el plano (x, y) con
//  altura z, proyectada en isométrico. Las piezas se ordenan por
//  profundidad (x + y) para que lo de adelante tape a lo de atrás. La
//  maqueta se arma UNA vez por cambio de datos (`_Maqueta`); cada cuadro
//  de animación solo vuelve a pintar, sin reconstruir widgets.
// ============================================================================

/// Lo que la ciudad necesita saber de una tienda.
class SedeCiudad {
  const SedeCiudad({
    required this.nombre,
    this.ventasHoy = 0,
    this.ventasMes = 0,
    this.ganancia = 0,
    this.facturasHoy = 0,
    this.facturasMes = 0,
    this.unidades = 0,
  });

  final String nombre;
  final double ventasHoy;
  final double ventasMes;
  final double ganancia;
  final int facturasHoy;
  final int facturasMes;
  final int unidades;
}

/// Un traslado (o varios) de hoy entre dos puntos de la ciudad.
class RutaCiudad {
  const RutaCiudad(this.origen, this.destino, this.viajes);
  final String origen;
  final String destino;
  final int viajes;
}

/// Nombre con el que se identifica el almacén dentro de la maqueta.
const String kAlmacenCiudad = '__almacen__';

class VistaCiudad extends StatefulWidget {
  const VistaCiudad({
    super.key,
    required this.sedes,
    required this.rutas,
    required this.formatoMoneda,
    required this.alEntrar,
    this.valorInventario = 0,
    this.unidadesInventario = 0,
    this.alAbrirAlmacen,
    this.alto = 540,
  });

  final List<SedeCiudad> sedes;
  final List<RutaCiudad> rutas;
  final String Function(double) formatoMoneda;
  final void Function(String sede) alEntrar;
  final double valorInventario;
  final int unidadesInventario;
  final VoidCallback? alAbrirAlmacen;
  final double alto;

  @override
  State<VistaCiudad> createState() => _VistaCiudadState();
}

class _VistaCiudadState extends State<VistaCiudad>
    with TickerProviderStateMixin {
  /// Reloj de la ciudad: una vuelta cada 16 s. Todo lo que se mueve
  /// calcula su posición a partir de este único valor.
  late final AnimationController _reloj = AnimationController(
      vsync: this, duration: const Duration(seconds: 16));

  final TransformationController _camara = TransformationController();
  late final AnimationController _vuelo = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
  Animation<Matrix4>? _trayecto;

  /// La construcción al abrir: de 0 (terreno vacío) a 1 (ciudad viva).
  late final AnimationController _entrada = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));

  /// El paso de las alturas viejas a las nuevas cuando llegan datos.
  late final AnimationController _crecer = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900), value: 1);
  Map<String, double> _altosAntes = const {};

  late _Maqueta _maqueta;
  String? _seleccion;
  String? _encima;
  Size _ultimoTamano = Size.zero;
  bool _encuadrada = false;
  bool _arrancada = false;
  bool _conIntro = false;
  bool _visible = true;
  ScrollPosition? _scroll;

  @override
  void initState() {
    super.initState();
    _maqueta = _Maqueta.armar(widget.sedes, widget.rutas);
    _vuelo.addListener(() {
      final t = _trayecto;
      if (t != null) _camara.value = t.value;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reducido = Ritmo.reducido(context);
    if (!_arrancada) {
      _arrancada = true;
      if (reducido) {
        _entrada.value = 1;
      } else {
        _entrada.forward();
        _conIntro = true;
      }
    }
    // Se escucha el desplazamiento de la pantalla que la contiene para
    // detener el reloj cuando la ciudad queda fuera de la vista.
    final scroll = Scrollable.maybeOf(context)?.position;
    if (scroll != _scroll) {
      _scroll?.removeListener(_revisarVisibilidad);
      _scroll = scroll?..addListener(_revisarVisibilidad);
    }
    _ajustarReloj();
  }

  /// Corre el reloj solo si se puede ver y el usuario no pidió quietud.
  void _ajustarReloj() {
    final debe = _visible && !Ritmo.reducido(context);
    if (debe && !_reloj.isAnimating) {
      _reloj.repeat();
    } else if (!debe && _reloj.isAnimating) {
      _reloj.stop();
    }
  }

  void _revisarVisibilidad() {
    final caja = context.findRenderObject();
    if (caja is! RenderBox || !caja.hasSize || !mounted) return;
    final arriba = caja.localToGlobal(Offset.zero).dy;
    final pantalla = MediaQuery.sizeOf(context).height;
    final visible = arriba < pantalla && arriba + caja.size.height > 0;
    if (visible != _visible) {
      _visible = visible;
      _ajustarReloj();
    }
  }

  /// Qué tiendas hay (si cambia, se rearma la ciudad).
  static String _estructura(List<SedeCiudad> sedes) =>
      sedes.map((s) => s.nombre).join('|');

  /// Los datos que se dibujan (si solo cambian estos, se anima el cambio).
  static String _datos(List<SedeCiudad> sedes, List<RutaCiudad> rutas) =>
      '${sedes.map((s) => '${s.nombre}:${s.ventasMes}:${s.facturasHoy}').join('|')}'
      '#${rutas.map((r) => '${r.origen}>${r.destino}:${r.viajes}').join('|')}';

  @override
  void didUpdateWidget(VistaCiudad viejo) {
    super.didUpdateWidget(viejo);
    // Se compara el CONTENIDO, no la lista: el panel arma una lista nueva
    // en cada redibujado, y compararlas por referencia rearmaba la ciudad
    // y devolvía la cámara a la vista general cada vez que el panel se
    // refrescaba, aunque el usuario estuviera mirando una tienda de cerca.
    final mismaEstructura =
        _estructura(viejo.sedes) == _estructura(widget.sedes);
    if (mismaEstructura &&
        _datos(viejo.sedes, viejo.rutas) == _datos(widget.sedes, widget.rutas)) {
      return;
    }
    final antes = {for (final e in _maqueta.edificios) e.id: e.alto};
    _maqueta = _Maqueta.armar(widget.sedes, widget.rutas);
    if (_seleccion != null &&
        _seleccion != kAlmacenCiudad &&
        !widget.sedes.any((s) => s.nombre == _seleccion)) {
      _seleccion = null;
    }
    if (mismaEstructura) {
      // Solo cambiaron las cifras: la cámara se queda y los edificios
      // crecen (o bajan) hasta su altura nueva.
      _altosAntes = antes;
      if (Ritmo.reducido(context)) {
        _crecer.value = 1;
      } else {
        _crecer.forward(from: 0);
      }
    } else {
      _altosAntes = const {};
      _encuadrada = false;
    }
  }

  @override
  void dispose() {
    _scroll?.removeListener(_revisarVisibilidad);
    _reloj.dispose();
    _entrada.dispose();
    _crecer.dispose();
    _vuelo.dispose();
    _camara.dispose();
    super.dispose();
  }

  /// Matriz que hace caber la maqueta entera en el recuadro.
  Matrix4 _encuadre(Size recuadro) {
    final m = _maqueta.tamano;
    final escala = math.min(recuadro.width / m.width, recuadro.height / m.height)
        .clamp(0.35, 1.6);
    final dx = (recuadro.width - m.width * escala) / 2;
    final dy = (recuadro.height - m.height * escala) / 2;
    return Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(escala, escala, 1, 1);
  }

  void _volarA(Matrix4 destino,
      {Duration duracion = const Duration(milliseconds: 650),
      Curve curva = Curves.easeInOutCubic}) {
    if (Ritmo.reducido(context)) {
      _camara.value = destino;
      return;
    }
    _vuelo.duration = duracion;
    _trayecto = Matrix4Tween(begin: _camara.value, end: destino)
        .animate(CurvedAnimation(parent: _vuelo, curve: curva));
    _vuelo.forward(from: 0);
  }

  /// La cámara empieza un poco más lejos y se acerca hasta el encuadre:
  /// la sensación de «entrar» a la ciudad.
  Matrix4 _alejada(Matrix4 destino, Size recuadro) {
    const f = 0.78;
    final c = Offset(recuadro.width / 2, recuadro.height / 2);
    return Matrix4.identity()
      ..translateByDouble(c.dx, c.dy, 0, 1)
      ..scaleByDouble(f, f, 1, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1)
      ..multiply(destino);
  }

  void _vistaGeneral() {
    setState(() => _seleccion = null);
    _volarA(_encuadre(_ultimoTamano));
  }

  /// Acerca la cámara a una pieza, dejándola en el centro.
  void _enfocar(String id) {
    final centro = _maqueta.centroDe(id);
    if (centro == null) return;
    final actual = _camara.value.getMaxScaleOnAxis();
    final escala = math.max(actual, 1.05).clamp(0.35, 2.2);
    final r = _ultimoTamano;
    final destino = Matrix4.identity()
      ..translateByDouble(r.width / 2 - centro.dx * escala,
          r.height / 2 - centro.dy * escala, 0, 1)
      ..scaleByDouble(escala, escala, 1, 1);
    _volarA(destino);
  }

  void _tocar(Offset punto) {
    final id = _maqueta.piezaEn(punto);
    if (id == null) {
      if (_seleccion != null) setState(() => _seleccion = null);
      return;
    }
    setState(() => _seleccion = id);
    _enfocar(id);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.alto,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF1F5FF), Color(0xFFE3EAFB)],
            ),
          ),
          child: LayoutBuilder(builder: (context, cons) {
            final tamano = Size(cons.maxWidth, cons.maxHeight);
            if (!_encuadrada || tamano != _ultimoTamano) {
              _ultimoTamano = tamano;
              _encuadrada = true;
              final destino = _encuadre(tamano);
              if (_conIntro) {
                _conIntro = false;
                _camara.value = _alejada(destino, tamano);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _volarA(destino,
                        duracion: const Duration(milliseconds: 1500),
                        curva: Curves.easeOutCubic);
                  }
                });
              } else {
                _camara.value = destino;
              }
            }
            return Stack(children: [
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _camara,
                  constrained: false,
                  minScale: 0.35,
                  maxScale: 2.5,
                  boundaryMargin: const EdgeInsets.all(400),
                  child: MouseRegion(
                    onHover: (e) {
                      final id = _maqueta.piezaEn(e.localPosition);
                      if (id != _encima) setState(() => _encima = id);
                    },
                    onExit: (_) => setState(() => _encima = null),
                    cursor: _encima != null
                        ? SystemMouseCursors.click
                        : SystemMouseCursors.grab,
                    child: GestureDetector(
                      onTapUp: (d) => _tocar(d.localPosition),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          size: _maqueta.tamano,
                          painter: _PintorCiudad(
                            maqueta: _maqueta,
                            reloj: _reloj,
                            entrada: _entrada,
                            crecer: _crecer,
                            altosAntes: _altosAntes,
                            seleccion: _seleccion,
                            encima: _encima,
                            unidadesInventario: widget.unidadesInventario,
                            // Los letreros se pintan a mano (TextPainter):
                            // sin esto no heredan la fuente de la app.
                            familia: DefaultTextStyle.of(context).style.fontFamily,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // ── Controles flotantes ──
              Positioned(
                left: 14,
                top: 14,
                child: _BotonFlotante(
                  icono: Icons.center_focus_strong_outlined,
                  texto: 'Vista general',
                  onTap: _vistaGeneral,
                ),
              ),
              Positioned(left: 14, bottom: 14, child: _Leyenda()),
              // ── Ficha de lo seleccionado ──
              Positioned(
                right: 14,
                bottom: 14,
                child: AnimatedSwitcher(
                  duration: Ritmo.entrada,
                  switchInCurve: Ritmo.suave,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (hijo, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween<Offset>(
                              begin: const Offset(0.15, 0), end: Offset.zero)
                          .animate(a),
                      child: hijo,
                    ),
                  ),
                  child: _ficha(cons.maxWidth),
                ),
              ),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _ficha(double anchoDisponible) {
    final id = _seleccion;
    if (id == null) return const SizedBox.shrink(key: ValueKey('nada'));
    final ancho = math.min(300.0, anchoDisponible - 28);

    if (id == kAlmacenCiudad) {
      return _FichaFlotante(
        key: const ValueKey(kAlmacenCiudad),
        ancho: ancho,
        icono: Icons.warehouse_rounded,
        color: AppColors.azulVivo,
        etiqueta: 'ALMACÉN',
        titulo: 'Inventario del grupo',
        filas: [
          ('Valor en venta', widget.formatoMoneda(widget.valorInventario)),
          ('Unidades', '${widget.unidadesInventario}'),
          ('Traslados hoy',
              '${widget.rutas.fold<int>(0, (s, r) => s + r.viajes)}'),
        ],
        accion: widget.alAbrirAlmacen == null ? null : 'Abrir almacén',
        alAccion: widget.alAbrirAlmacen,
        alCerrar: () => setState(() => _seleccion = null),
      );
    }

    final sede = widget.sedes.firstWhere((s) => s.nombre == id,
        orElse: () => SedeCiudad(nombre: id));
    return _FichaFlotante(
      key: ValueKey(id),
      ancho: ancho,
      icono: Icons.storefront_rounded,
      color: AppColors.lila,
      etiqueta: 'TIENDA',
      titulo: sede.nombre,
      progreso: sede.facturasHoy > 0 ? 'Vendiendo hoy' : 'Sin ventas hoy',
      filas: [
        ('Ventas de hoy', widget.formatoMoneda(sede.ventasHoy)),
        ('Facturas de hoy', '${sede.facturasHoy}'),
        ('Ventas del mes', widget.formatoMoneda(sede.ventasMes)),
        ('Ganancia del mes', widget.formatoMoneda(sede.ganancia)),
        ('Unidades del mes', '${sede.unidades}'),
      ],
      accion: 'Entrar a la tienda',
      alAccion: () => widget.alEntrar(sede.nombre),
      alCerrar: () => setState(() => _seleccion = null),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Piezas flotantes de la interfaz
// ─────────────────────────────────────────────────────────────────────────

class _BotonFlotante extends StatelessWidget {
  const _BotonFlotante(
      {required this.icono, required this.texto, required this.onTap});
  final IconData icono;
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        elevation: 0,
        shape: const StadiumBorder(
            side: BorderSide(color: AppColors.bordeSuave)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icono, size: 16, color: AppColors.textPrimary),
              const SizedBox(width: 6),
              Text(texto,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ]),
          ),
        ),
      );
}

class _Leyenda extends StatefulWidget {
  @override
  State<_Leyenda> createState() => _LeyendaState();
}

class _LeyendaState extends State<_Leyenda> {
  bool _abierta = false;

  @override
  Widget build(BuildContext context) {
    Widget fila(IconData i, Color c, String t) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 15, color: c),
            const SizedBox(width: 6),
            Text(t,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ]),
        );
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.bordeSuave)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _abierta = !_abierta),
        child: AnimatedSize(
          duration: Ritmo.toque,
          curve: Ritmo.suave,
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    AnimatedRotation(
                      turns: _abierta ? 0.25 : 0,
                      duration: Ritmo.toque,
                      child: const Icon(Icons.play_arrow_rounded,
                          size: 16, color: AppColors.textPrimary),
                    ),
                    const SizedBox(width: 4),
                    const Text('Leyenda',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                  ]),
                  if (_abierta) ...[
                    fila(Icons.apartment_rounded, AppColors.lila,
                        'Altura = ventas del mes'),
                    fila(Icons.directions_walk_rounded, AppColors.azulVivo,
                        'Personas = facturas de hoy'),
                    fila(Icons.local_shipping_rounded, AppColors.azulVivo,
                        'Camiones = traslados de hoy'),
                    fila(Icons.touch_app_rounded, AppColors.textSecondary,
                        'Toca un edificio para ver detalle'),
                  ],
                ]),
          ),
        ),
      ),
    );
  }
}

class _FichaFlotante extends StatelessWidget {
  const _FichaFlotante({
    super.key,
    required this.ancho,
    required this.icono,
    required this.color,
    required this.etiqueta,
    required this.titulo,
    required this.filas,
    required this.alCerrar,
    this.progreso,
    this.accion,
    this.alAccion,
  });

  final double ancho;
  final IconData icono;
  final Color color;
  final String etiqueta;
  final String titulo;
  final String? progreso;
  final List<(String, String)> filas;
  final String? accion;
  final VoidCallback? alAccion;
  final VoidCallback alCerrar;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: ancho,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.bordeSuave),
        boxShadow: AppElevation.flotante,
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icono, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(etiqueta,
                        style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary)),
                    Text(titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ])),
              IconButton(
                  tooltip: 'Cerrar',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: alCerrar),
            ]),
            if (progreso != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.lilaTenue,
                    borderRadius: BorderRadius.circular(AppRadius.full)),
                child: Text(progreso!,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.lila)),
              ),
            ],
            const SizedBox(height: 8),
            for (final f in filas)
              Padding(
                padding: const EdgeInsets.only(top: 5, right: 4),
                child: Row(children: [
                  Expanded(
                      child: Text(f.$1,
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.textSecondary))),
                  Text(f.$2,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ]),
              ),
            if (accion != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: alAccion,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: Text(accion!),
                ),
              ),
            ],
          ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  La maqueta: geometría calculada una vez por cambio de datos
// ─────────────────────────────────────────────────────────────────────────

/// Píxeles por unidad de cuadrícula.
const double _s = 30;

/// Alto de la tienda que más vende (0,9 de base + 2,3 por ventas).
const double _altoMaximo = 3.2;
const double _cos30 = 0.8660254;

/// Proyección isométrica sin desplazar.
Offset _iso(double x, double y, [double z = 0]) =>
    Offset((x - y) * _cos30 * _s, (x + y) * 0.5 * _s - z * _s);

class _Edificio {
  _Edificio({
    required this.id,
    required this.titulo,
    required this.cx,
    required this.cy,
    required this.ancho,
    required this.fondo,
    required this.alto,
    required this.contador,
    required this.esAlmacen,
    required this.gente,
  });

  final String id;
  final String titulo;
  final double cx, cy, ancho, fondo, alto;
  final String contador;
  final bool esAlmacen;

  /// Personitas caminando hacia la puerta (facturas de hoy, topado).
  final int gente;

  double get x0 => cx - ancho / 2;
  double get y0 => cy - fondo / 2;

  /// Silueta en pantalla, para saber si un toque cayó encima.
  late Path silueta;
}

class _Camion {
  _Camion(this.desde, this.hasta, this.fase);
  final Offset desde; // en cuadrícula
  final Offset hasta;
  final double fase;
}

class _Arbol {
  _Arbol(this.x, this.y, this.tamano, this.dueno);
  final double x, y, tamano;

  /// Índice del edificio junto al que está: brota cuando ese se construye.
  final int dueno;
}

class _Maqueta {
  _Maqueta._(this.edificios, this.camiones, this.arboles, this.origen,
      this.tamano, this.radio);

  final List<_Edificio> edificios;
  final List<_Camion> camiones;
  final List<_Arbol> arboles;

  /// Desplazamiento que lleva la proyección al lienzo (todo en positivo).
  final Offset origen;
  final Size tamano;

  /// Radio del anillo de tiendas, en cuadrícula.
  final double radio;

  Offset p(double x, double y, [double z = 0]) => _iso(x, y, z) + origen;

  _Edificio get almacen => edificios.firstWhere((e) => e.esAlmacen);

  static _Maqueta armar(List<SedeCiudad> sedes, List<RutaCiudad> rutas) {
    final n = sedes.length;
    final radio = math.max(9.0, n * 1.7);
    final maxMes = sedes.fold<double>(0, (m, s) => math.max(m, s.ventasMes));

    final edificios = <_Edificio>[
      _Edificio(
        id: kAlmacenCiudad,
        titulo: 'ALMACÉN',
        cx: 0,
        cy: 0,
        ancho: 4.4,
        fondo: 3.2,
        alto: 1.7,
        contador: 'central',
        esAlmacen: true,
        gente: 0,
      ),
    ];
    final posiciones = <String, Offset>{kAlmacenCiudad: Offset.zero};

    for (var i = 0; i < n; i++) {
      final s = sedes[i];
      // Repartidas en anillo. Se empieza en -45°, que en isométrico cae a
      // la DERECHA del almacén: con dos tiendas quedan a izquierda y
      // derecha y aprovechan el ancho del panel (empezando arriba quedaban
      // en una columna, una encima y otra debajo del almacén).
      final ang = -math.pi / 4 + i * 2 * math.pi / math.max(n, 1);
      final cx = math.cos(ang) * radio;
      final cy = math.sin(ang) * radio;
      final relativo = maxMes <= 0 ? 0.0 : (s.ventasMes / maxMes);
      edificios.add(_Edificio(
        id: s.nombre,
        titulo: s.nombre.toUpperCase(),
        cx: cx,
        cy: cy,
        ancho: 2.4,
        fondo: 2.4,
        alto: 0.9 + 2.3 * relativo,
        contador: '${s.facturasHoy} hoy',
        esAlmacen: false,
        gente: math.min(s.facturasHoy, 7),
      ));
      posiciones[s.nombre] = Offset(cx, cy);
    }

    // Camiones: hasta tres por ruta. Un nombre que no es una tienda de la
    // lista (p. ej. el propio almacén o una sede vieja) sale del almacén.
    final camiones = <_Camion>[];
    var k = 0;
    for (final r in rutas) {
      if (r.viajes <= 0) continue;
      final a = posiciones[r.origen] ?? Offset.zero;
      final b = posiciones[r.destino] ?? Offset.zero;
      if ((a - b).distance < 0.5) continue;
      final cuantos = math.min(r.viajes, 3);
      for (var j = 0; j < cuantos; j++) {
        camiones.add(_Camion(a, b, (j / cuantos + k * 0.137) % 1));
      }
      k++;
    }

    // Árboles: posiciones fijas por tienda (semilla = índice), para que
    // no «salten» al refrescar.
    final arboles = <_Arbol>[];
    for (var i = 0; i < edificios.length; i++) {
      final e = edificios[i];
      final rnd = math.Random(17 + i * 31);
      final cuantos = e.esAlmacen ? 4 : 3;
      for (var j = 0; j < cuantos; j++) {
        final ang = rnd.nextDouble() * math.pi * 2;
        final d = (e.esAlmacen ? 3.6 : 2.2) + rnd.nextDouble() * 0.6;
        arboles.add(_Arbol(e.cx + math.cos(ang) * d, e.cy + math.sin(ang) * d,
            0.8 + rnd.nextDouble() * 0.5, i));
      }
    }

    // Límites del lienzo: las islas con un poco de aire y lo alto de los
    // letreros. El suelo se dibuja más grande y sobra por los bordes, a
    // propósito: el encuadre inicial va a los EDIFICIOS, no al terreno
    // vacío, para que se vean grandes como en un tablero de juego.
    final puntos = <Offset>[
      for (final e in edificios) ...[
        _iso(e.cx - 3.6, e.cy - 3.6),
        _iso(e.cx + 3.6, e.cy - 3.6),
        _iso(e.cx + 3.6, e.cy + 3.6),
        _iso(e.cx - 3.6, e.cy + 3.6),
        // La altura MÁXIMA posible y no la de hoy: así el lienzo solo
        // depende de cuántas tiendas hay, y cuando un edificio crece con
        // una venta la ciudad no se desplaza bajo la cámara.
        _iso(e.cx, e.cy, (e.esAlmacen ? e.alto : _altoMaximo) + 2.4),
      ],
    ];
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final q in puntos) {
      minX = math.min(minX, q.dx);
      minY = math.min(minY, q.dy);
      maxX = math.max(maxX, q.dx);
      maxY = math.max(maxY, q.dy);
    }
    const margen = 40.0;
    final origen = Offset(-minX + margen, -minY + margen);
    final tamano = Size(maxX - minX + margen * 2, maxY - minY + margen * 2);

    final m = _Maqueta._(edificios, camiones, arboles, origen, tamano, radio);
    for (final e in edificios) {
      e.silueta = m._silueta(e);
    }
    return m;
  }

  Path _silueta(_Edificio e) {
    final x0 = e.x0, y0 = e.y0, x1 = e.x0 + e.ancho, y1 = e.y0 + e.fondo;
    final h = e.alto;
    final contorno = Path()
      ..addPolygon([
        p(x0, y0, h),
        p(x1, y0, h),
        p(x1, y0, 0),
        p(x1, y1, 0),
        p(x0, y1, 0),
        p(x0, y1, h),
      ], true);
    // El letrero también cuenta como parte del edificio.
    final ancla = p(e.cx, e.cy, h + 1.2);
    contorno.addRect(Rect.fromCenter(center: ancla, width: 150, height: 44));
    return contorno;
  }

  String? piezaEn(Offset punto) {
    // De adelante hacia atrás: si dos se tapan, gana la que se ve.
    final orden = [...edificios]
      ..sort((a, b) => (b.cx + b.cy).compareTo(a.cx + a.cy));
    for (final e in orden) {
      if (e.silueta.contains(punto)) return e.id;
    }
    return null;
  }

  Offset? centroDe(String id) {
    for (final e in edificios) {
      if (e.id == id) return p(e.cx, e.cy, e.alto / 2);
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  El pintor
// ─────────────────────────────────────────────────────────────────────────

class _PintorCiudad extends CustomPainter {
  _PintorCiudad({
    required this.maqueta,
    required this.reloj,
    required this.entrada,
    required this.crecer,
    required this.altosAntes,
    required this.seleccion,
    required this.encima,
    required this.unidadesInventario,
    this.familia,
  }) : super(repaint: Listenable.merge([reloj, entrada, crecer]));

  final _Maqueta maqueta;
  final Animation<double> reloj;
  final Animation<double> entrada;
  final Animation<double> crecer;
  final Map<String, double> altosAntes;
  final String? seleccion;
  final String? encima;
  final int unidadesInventario;
  final String? familia;

  // Paleta de la maqueta.
  static const _suelo = Color(0xFFE8EEFC);
  static const _lineaSuelo = Color(0xFFDCE5F8);
  static const _calle = Color(0xFF3B5BDB);
  static const _islaTapa = Color(0xFFD9E8FF);
  static const _islaLado = Color(0xFFB8CCF4);
  static const _muroClaro = Color(0xFFFFFFFF);
  static const _muroMedio = Color(0xFFE6EBFB);
  static const _muroOscuro = Color(0xFFD3DFFA);
  static const _azul = AppColors.azulVivo;
  static const _verde = Color(0xFF34C38F);
  static const _verdeOscuro = Color(0xFF1F9D6E);

  double get t => reloj.value;

  // ── Construcción ──
  //  Todo sale de `entrada` (0 → 1). Cada pieza tiene su tramo: el terreno
  //  primero, las calles, el almacén, cada tienda en orden, los letreros
  //  un poco después de su edificio y la vida al final.

  double get _e => entrada.value;

  static double _tramo(double v, double desde, double hasta) =>
      ((v - desde) / (hasta - desde)).clamp(0.0, 1.0);

  /// Cuándo empieza a subir el edificio `i` (el almacén es el 0).
  double _inicio(int i) {
    final n = maqueta.edificios.length;
    return 0.15 + (n <= 1 ? 0 : i * 0.40 / (n - 1));
  }

  int _indice(_Edificio e) => maqueta.edificios.indexOf(e);

  /// Avance de la subida de un edificio, de 0 a 1.
  double _subida(_Edificio e) {
    final i = _inicio(_indice(e));
    return _tramo(_e, i, i + 0.35);
  }

  /// Altura que se dibuja: la del dato (pasando de la vieja a la nueva si
  /// cambió) por cuánto subió ya el edificio. El rebote de easeOutBack hace
  /// que pase un poco de su altura y se asiente.
  double _alto(_Edificio e) {
    final antes = altosAntes[e.id];
    final dato = antes == null
        ? e.alto
        : antes + (e.alto - antes) * Curves.easeInOutCubic.transform(crecer.value);
    final s = _subida(e);
    return dato * (s >= 1 ? 1 : Curves.easeOutBack.transform(s));
  }

  /// La vida (gente, camiones, montacargas) arranca al final.
  double get _vida => _tramo(_e, 0.72, 1.0);

  Offset p(double x, double y, [double z = 0]) => maqueta.p(x, y, z);

  @override
  void paint(Canvas canvas, Size size) {
    final suelo = _tramo(_e, 0, 0.18);
    if (suelo <= 0) return;
    _pintarSuelo(canvas, suelo);
    _pintarCalles(canvas);
    for (final e in maqueta.edificios) {
      _pintarIsla(canvas, e);
    }

    // Todo lo que tiene altura se ordena por profundidad.
    final piezas = <(double, void Function())>[];
    final vida = _vida;
    for (final e in maqueta.edificios) {
      piezas.add((e.cx + e.cy, () => _pintarEdificio(canvas, e)));
      // La gente aparece de a poco cuando la ciudad cobra vida.
      final gente = vida <= 0 ? 0 : (e.gente * vida).ceil();
      for (var g = 0; g < gente; g++) {
        final pos = _posicionPersona(e, g);
        if (pos != null) {
          piezas.add((pos.dx + pos.dy, () => _pintarPersona(canvas, pos, g)));
        }
      }
    }
    for (final a in maqueta.arboles) {
      piezas.add((a.x + a.y, () => _pintarArbol(canvas, a)));
    }
    for (final c in vida <= 0 ? const <_Camion>[] : maqueta.camiones) {
      final pos = _posicionCamion(c);
      piezas.add((pos.$1.dx + pos.$1.dy, () => _pintarCamion(canvas, pos.$1, pos.$2)));
    }
    if (unidadesInventario > 0 && vida > 0) {
      final pos = _posicionMontacargas();
      piezas.add((pos.dx + pos.dy, () => _pintarMontacargas(canvas, pos)));
    }
    piezas.sort((a, b) => a.$1.compareTo(b.$1));
    for (final pz in piezas) {
      pz.$2();
    }

    // Los letreros van al final: siempre por encima.
    for (final e in maqueta.edificios) {
      _pintarLetrero(canvas, e);
    }
  }

  // ── Suelo y calles ──

  void _pintarSuelo(Canvas canvas, double opacidad) {
    final b = maqueta.radio + 4.5;
    final suelo = Path()
      ..addPolygon([p(-b, -b), p(b, -b), p(b, b), p(-b, b)], true);
    canvas.drawPath(suelo, Paint()..color = _suelo.withValues(alpha: opacidad));
    final linea = Paint()
      ..color = _lineaSuelo.withValues(alpha: opacidad)
      ..strokeWidth = 1;
    for (var i = -b; i <= b; i += 2) {
      canvas.drawLine(p(i, -b), p(i, b), linea);
      canvas.drawLine(p(-b, i), p(b, i), linea);
    }
  }

  void _pintarCalles(Canvas canvas) {
    final alm = maqueta.almacen;
    // Las calles se trazan desde el almacén hacia cada tienda.
    final trazo = Curves.easeOutCubic.transform(_tramo(_e, 0.08, 0.5));
    if (trazo <= 0) return;
    for (final e in maqueta.edificios) {
      if (e.esAlmacen) continue;
      final a = Offset(alm.cx, alm.cy);
      final b = a + (Offset(e.cx, e.cy) - a) * trazo;
      final d = b - a;
      final largo = d.distance;
      if (largo == 0) continue;
      final u = d / largo;
      final n = Offset(-u.dy, u.dx) * 0.55;
      final calle = Path()
        ..addPolygon([
          p(a.dx + n.dx, a.dy + n.dy),
          p(b.dx + n.dx, b.dy + n.dy),
          p(b.dx - n.dx, b.dy - n.dy),
          p(a.dx - n.dx, a.dy - n.dy),
        ], true);
      canvas.drawPath(calle, Paint()..color = _calle.withValues(alpha: 0.85));

      // Flechas que avanzan hacia la tienda: el sentido del flujo de
      // mercancía, del almacén a la venta.
      final flecha = Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      if (trazo < 1) continue;   // las flechas, con la calle terminada
      const paso = 1.4;
      final desfase = (t * 6) % paso;
      for (var s = 2.2 + desfase; s < largo - 1.6; s += paso) {
        final c = a + u * s;
        final punta = c + u * 0.25;
        final ala1 = c - u * 0.15 + n * 0.45;
        final ala2 = c - u * 0.15 - n * 0.45;
        final path = Path()
          ..moveTo(p(ala1.dx, ala1.dy).dx, p(ala1.dx, ala1.dy).dy)
          ..lineTo(p(punta.dx, punta.dy).dx, p(punta.dx, punta.dy).dy)
          ..lineTo(p(ala2.dx, ala2.dy).dx, p(ala2.dx, ala2.dy).dy);
        canvas.drawPath(path, flecha);
      }
    }
  }

  void _pintarIsla(Canvas canvas, _Edificio e) {
    // La isla aparece un instante antes que su edificio, con un rebote.
    final i = _inicio(_indice(e));
    final aparece = _tramo(_e, i - 0.08, i + 0.12);
    if (aparece <= 0) return;
    final r = (e.esAlmacen ? 3.4 : 2.0) *
        (aparece >= 1 ? 1 : 0.4 + 0.6 * Curves.easeOutBack.transform(aparece));
    _caja(canvas, e.cx - r, e.cy - r, 2 * r, 2 * r, 0.22,
        tapa: _islaTapa, izq: _islaLado, der: const Color(0xFFA9BEEB));
    final activo = e.id == seleccion || e.id == encima;
    if (activo) {
      // Halo que late bajo lo seleccionado.
      final latido = 0.5 + 0.5 * math.sin(t * math.pi * 2 * 4);
      final halo = Path()
        ..addPolygon([
          p(e.cx - r, e.cy - r, 0.22),
          p(e.cx + r, e.cy - r, 0.22),
          p(e.cx + r, e.cy + r, 0.22),
          p(e.cx - r, e.cy + r, 0.22),
        ], true);
      canvas.drawPath(
          halo,
          Paint()
            ..color = (e.esAlmacen ? _azul : AppColors.lila)
                .withValues(alpha: e.id == seleccion ? 0.18 + 0.12 * latido : 0.12));
      canvas.drawPath(
          halo,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = (e.esAlmacen ? _azul : AppColors.lila).withValues(alpha: 0.6));
    }
  }

  // ── Edificios ──

  /// Caja isométrica: dibuja las dos caras visibles y la tapa.
  void _caja(Canvas canvas, double x, double y, double w, double d, double h,
      {required Color tapa,
      required Color izq,
      required Color der,
      double z = 0}) {
    final caraIzq = Path()
      ..addPolygon([
        p(x, y + d, z),
        p(x + w, y + d, z),
        p(x + w, y + d, z + h),
        p(x, y + d, z + h),
      ], true);
    final caraDer = Path()
      ..addPolygon([
        p(x + w, y, z),
        p(x + w, y + d, z),
        p(x + w, y + d, z + h),
        p(x + w, y, z + h),
      ], true);
    final caraTapa = Path()
      ..addPolygon([
        p(x, y, z + h),
        p(x + w, y, z + h),
        p(x + w, y + d, z + h),
        p(x, y + d, z + h),
      ], true);
    canvas.drawPath(caraIzq, Paint()..color = izq);
    canvas.drawPath(caraDer, Paint()..color = der);
    canvas.drawPath(caraTapa, Paint()..color = tapa);
  }

  void _pintarEdificio(Canvas canvas, _Edificio e) {
    if (e.esAlmacen) {
      _pintarAlmacen(canvas, e);
      return;
    }
    final x = e.x0, y = e.y0, w = e.ancho, d = e.fondo, h = _alto(e);
    if (h < 0.02) return;   // todavía bajo tierra
    _caja(canvas, x, y, w, d, h,
        tapa: _muroClaro, izq: _muroMedio, der: _muroOscuro);

    // Franja de color en lo alto (el toldo de la tienda).
    _caja(canvas, x - 0.05, y - 0.05, w + 0.1, d + 0.1, 0.22,
        z: h,
        tapa: AppColors.lila,
        izq: const Color(0xFF1C3A78),
        der: const Color(0xFF122654));

    // Ventanas por piso en las dos caras visibles.
    final ventana = Paint()..color = const Color(0xFFB7C8FF);
    final pisos = math.max(1, (h / 0.75).floor());
    for (var f = 0; f < pisos; f++) {
      final z0 = 0.25 + f * 0.75;
      if (z0 + 0.4 > h) break;
      for (var c = 0; c < 3; c++) {
        final x0 = x + 0.3 + c * 0.7;
        canvas.drawPath(
            Path()
              ..addPolygon([
                p(x0, y + d, z0),
                p(x0 + 0.4, y + d, z0),
                p(x0 + 0.4, y + d, z0 + 0.4),
                p(x0, y + d, z0 + 0.4),
              ], true),
            ventana);
        final y0 = y + 0.3 + c * 0.7;
        if (f == 0 && c == 1) continue; // ahí va la puerta
        canvas.drawPath(
            Path()
              ..addPolygon([
                p(x + w, y0, z0),
                p(x + w, y0 + 0.4, z0),
                p(x + w, y0 + 0.4, z0 + 0.4),
                p(x + w, y0, z0 + 0.4),
              ], true),
            Paint()..color = const Color(0xFF9DB2F5));
      }
    }
    // Puerta, en la cara que mira al almacén.
    canvas.drawPath(
        Path()
          ..addPolygon([
            p(x + w, y + d / 2 - 0.3, 0),
            p(x + w, y + d / 2 + 0.3, 0),
            p(x + w, y + d / 2 + 0.3, 0.6),
            p(x + w, y + d / 2 - 0.3, 0.6),
          ], true),
        Paint()..color = AppColors.lila);
  }

  void _pintarAlmacen(Canvas canvas, _Edificio e) {
    final x = e.x0, y = e.y0, w = e.ancho, d = e.fondo, h = _alto(e);
    if (h < 0.02) return;
    _caja(canvas, x, y, w, d, h,
        tapa: const Color(0xFFF4F6FF),
        izq: const Color(0xFFFFFFFF),
        der: const Color(0xFFE6EBFB));
    // Marco azul en el borde superior, como los galpones del video.
    _caja(canvas, x, y, w, d, 0.16,
        z: h,
        tapa: const Color(0xFFF4F6FF),
        izq: _azul,
        der: const Color(0xFF1F43C4));
    // Portones y cajas, cuando el galpón ya está en pie (si no, quedarían
    // flotando por encima del techo mientras sube).
    if (h < e.alto * 0.95) return;
    // Portones de carga con cajas.
    for (var i = 0; i < 4; i++) {
      final x0 = x + 0.35 + i * 1.0;
      final porton = Path()
        ..addPolygon([
          p(x0, y + d, 0),
          p(x0 + 0.65, y + d, 0),
          p(x0 + 0.65, y + d, 0.9),
          p(x0, y + d, 0.9),
        ], true);
      canvas.drawPath(porton, Paint()..color = const Color(0xFFDDE5FB));
      canvas.drawPath(
          porton,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = _azul);
      _caja(canvas, x0 + 0.15, y + d - 0.4, 0.35, 0.3, 0.3,
          tapa: const Color(0xFFDDE8FF),
          izq: const Color(0xFFB9CCF5),
          der: const Color(0xFF9DB2F5));
    }
    // Palets de cajas azules frente a la cara derecha.
    _caja(canvas, x + w + 0.5, y + 0.4, 0.6, 0.6, 0.5,
        tapa: const Color(0xFF5B7CF0), izq: _azul, der: const Color(0xFF1F43C4));
    _caja(canvas, x + w + 0.5, y + 1.2, 0.6, 0.6, 0.35,
        tapa: const Color(0xFFDDE8FF),
        izq: const Color(0xFFB9CCF5),
        der: const Color(0xFF9DB2F5));
  }

  // ── Letreros ──

  void _pintarLetrero(Canvas canvas, _Edificio e) {
    // El letrero cae en su lugar poco después de que sube el edificio.
    final i = _inicio(_indice(e));
    final cae = _tramo(_e, i + 0.22, i + 0.5);
    if (cae <= 0) return;
    final enCapa = cae < 1;
    if (enCapa) {
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, cae));
    }
    final color = e.esAlmacen ? _azul : AppColors.lila;
    final ancla = p(e.cx, e.cy, _alto(e) + 1.0) +
        Offset(0, -34 * (1 - Curves.easeOutBack.transform(cae)));
    final activo = e.id == seleccion || e.id == encima;

    final titulo = TextPainter(
      text: TextSpan(
          text: e.titulo,
          style: TextStyle(
              fontFamily: familia,
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 120);
    final cuenta = TextPainter(
      text: TextSpan(
          text: e.contador,
          style: TextStyle(
              fontFamily: familia,
              color: color, fontSize: 10, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();

    final anchoTitulo = titulo.width + 16;
    final anchoCuenta = cuenta.width + 12;
    final total = anchoTitulo + anchoCuenta + 6;
    const alto = 22.0;

    canvas.save();
    canvas.translate(ancla.dx - total * _cos30 / 2, ancla.dy - total * 0.25);
    // El letrero se inclina siguiendo el eje x de la cuadrícula, como los
    // carteles pintados sobre la maqueta.
    canvas.transform(Float64List.fromList([
      _cos30, 0.5, 0, 0, //
      0, 1, 0, 0, //
      0, 0, 1, 0, //
      0, 0, 0, 1,
    ]));
    final sube = activo ? -4.0 : 0.0;
    final cuerpo = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, -alto + sube, total, alto), const Radius.circular(5));
    canvas.drawRRect(
        cuerpo.shift(const Offset(0, 3)),
        Paint()..color = const Color(0xFF1B2A5A).withValues(alpha: 0.18));
    canvas.drawRRect(cuerpo, Paint()..color = color);
    titulo.paint(canvas, Offset(8, -alto + sube + (alto - titulo.height) / 2));
    final chip = RRect.fromRectAndRadius(
        Rect.fromLTWH(anchoTitulo, -alto + sube + 4, anchoCuenta, alto - 8),
        const Radius.circular(8));
    canvas.drawRRect(chip, Paint()..color = Colors.white);
    cuenta.paint(canvas,
        Offset(anchoTitulo + 6, -alto + sube + (alto - cuenta.height) / 2));
    canvas.restore();

    // Mástil del letrero hasta el techo.
    final base = p(e.cx, e.cy, _alto(e) + 0.22);
    canvas.drawLine(
        base,
        Offset(base.dx, ancla.dy + sube),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..strokeWidth = 2);
    if (enCapa) canvas.restore();
  }

  // ── Lo que se mueve ──

  /// Posición (en cuadrícula) de la persona `g` de una tienda: camina por
  /// la calle hacia la puerta y «entra». Devuelve null mientras está
  /// adentro, para que no se dibuje.
  Offset? _posicionPersona(_Edificio e, int g) {
    final alm = maqueta.almacen;
    final destino = Offset(e.cx, e.cy);
    final d = Offset(alm.cx, alm.cy) - destino;
    final u = d / d.distance;
    final lado = Offset(-u.dy, u.dx) * (((g % 3) - 1) * 0.25);
    final ciclo = (t * 3 + g / math.max(e.gente, 1)) % 1;
    if (ciclo > 0.92) return null;
    final avance = 1 - ciclo / 0.92; // 1 = lejos, 0 = en la puerta
    return destino + u * (1.35 + avance * 2.6) + lado;
  }

  void _pintarPersona(Canvas canvas, Offset pos, int g) {
    const colores = [
      Color(0xFF3B5BDB),
      Color(0xFF2952E3),
      Color(0xFF00A3FF),
      Color(0xFF1C7ED6),
      Color(0xFF1F43C4),
    ];
    final paso = math.sin(t * math.pi * 2 * 24 + g) * 0.6;
    final pie = p(pos.dx, pos.dy);
    canvas.drawOval(Rect.fromCenter(center: pie, width: 9, height: 4),
        Paint()..color = const Color(0x221B2A5A));
    final cuerpo = RRect.fromRectAndRadius(
        Rect.fromCenter(center: pie + Offset(0, -9 + paso), width: 6, height: 12),
        const Radius.circular(3));
    canvas.drawRRect(cuerpo, Paint()..color = colores[g % colores.length]);
    canvas.drawCircle(pie + Offset(0, -17.5 + paso), 3.2,
        Paint()..color = const Color(0xFF2B2B40));
  }

  /// Posición y sentido de un camión: va de origen a destino y vuelve.
  (Offset, Offset) _posicionCamion(_Camion c) {
    final ciclo = (t * 1.5 + c.fase) % 1;
    final ida = ciclo < 0.5;
    final u = ida ? ciclo * 2 : (1 - ciclo) * 2;
    final suave = Curves.easeInOut.transform(u);
    final d = c.hasta - c.desde;
    final dir = d / d.distance;
    // Por su carril: la ida y la vuelta no se pisan.
    final carril = Offset(-dir.dy, dir.dx) * (ida ? 0.22 : -0.22);
    return (c.desde + d * suave + carril, ida ? dir : -dir);
  }

  void _pintarCamion(Canvas canvas, Offset pos, Offset dir) {
    // El camión se alinea con el eje dominante de su recorrido.
    final enX = dir.dx.abs() >= dir.dy.abs();
    final largo = 1.1, ancho = 0.5;
    final w = enX ? largo : ancho, d = enX ? ancho : largo;
    final x = pos.dx - w / 2, y = pos.dy - d / 2;
    canvas.drawOval(
        Rect.fromCenter(center: p(pos.dx, pos.dy), width: 34, height: 14),
        Paint()..color = const Color(0x221B2A5A));
    // Contenedor blanco…
    _caja(canvas, x, y, w, d, 0.5,
        z: 0.08,
        tapa: Colors.white,
        izq: const Color(0xFFF1F3FA),
        der: const Color(0xFFE1E6F5));
    // …y cabina azul delante, del lado hacia el que avanza.
    final adelante = enX ? dir.dx > 0 : dir.dy > 0;
    const cab = 0.3;
    if (enX) {
      final cx = adelante ? x + w : x - cab;
      _caja(canvas, cx, y, cab, d, 0.4,
          z: 0.08, tapa: const Color(0xFF5B7CF0), izq: _azul, der: const Color(0xFF1F43C4));
    } else {
      final cy = adelante ? y + d : y - cab;
      _caja(canvas, x, cy, w, cab, 0.4,
          z: 0.08, tapa: const Color(0xFF5B7CF0), izq: _azul, der: const Color(0xFF1F43C4));
    }
  }

  Offset _posicionMontacargas() {
    // Va y viene frente a los portones del almacén, cargando cajas.
    final alm = maqueta.almacen;
    final u = Curves.easeInOut.transform(((t * 4) % 1) < 0.5
        ? ((t * 4) % 1) * 2
        : (1 - (t * 4) % 1) * 2);
    return Offset(alm.x0 + 0.6 + u * (alm.ancho - 1.2), alm.y0 + alm.fondo + 1.0);
  }

  void _pintarMontacargas(Canvas canvas, Offset pos) {
    canvas.drawOval(
        Rect.fromCenter(center: p(pos.dx, pos.dy), width: 22, height: 10),
        Paint()..color = const Color(0x221B2A5A));
    _caja(canvas, pos.dx - 0.25, pos.dy - 0.2, 0.5, 0.4, 0.3,
        z: 0.05,
        tapa: const Color(0xFFB9CCF5),
        izq: const Color(0xFF5B7CF0),
        der: const Color(0xFF3B5BDB));
    _caja(canvas, pos.dx - 0.05, pos.dy - 0.15, 0.25, 0.3, 0.25,
        z: 0.35,
        tapa: const Color(0xFFDDE8FF),
        izq: const Color(0xFFB9CCF5),
        der: const Color(0xFF9DB2F5));
  }

  void _pintarArbol(Canvas canvas, _Arbol a) {
    // Brota junto con su edificio.
    final i = _inicio(a.dueno);
    final brota = _tramo(_e, i + 0.15, i + 0.4);
    if (brota <= 0) return;
    final tam = a.tamano * (brota >= 1 ? 1 : Curves.easeOutBack.transform(brota));
    if (tam <= 0) return;
    final base = p(a.x, a.y);
    canvas.drawOval(Rect.fromCenter(center: base, width: 16 * tam, height: 7 * tam),
        Paint()..color = const Color(0x1F1B2A5A));
    canvas.drawLine(base, base + Offset(0, -10 * tam),
        Paint()
          ..color = const Color(0xFF8D6E63)
          ..strokeWidth = 2.5);
    final copa = base + Offset(0, -16 * tam);
    canvas.drawCircle(copa, 8 * tam, Paint()..color = _verdeOscuro);
    canvas.drawCircle(copa + Offset(-1.5 * tam, -1.5 * tam),
        6.5 * tam, Paint()..color = _verde);
  }

  @override
  bool shouldRepaint(_PintorCiudad viejo) =>
      viejo.maqueta != maqueta ||
      viejo.altosAntes != altosAntes ||
      viejo.seleccion != seleccion ||
      viejo.encima != encima ||
      viejo.unidadesInventario != unidadesInventario ||
      viejo.familia != familia;
}
