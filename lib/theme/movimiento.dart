import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

// ============================================================================
//  movimiento.dart — Animaciones del sistema de diseño
//
//  POR QUÉ UN ARCHIVO DE ANIMACIONES
//  ---------------------------------
//  La aplicación tenía cuatro animaciones en total, cada una escrita a mano
//  en su pantalla. El estilo nuevo —el de los tableros «vivos», donde las
//  cifras suben contando, las tarjetas entran escalonadas y lo que se puede
//  tocar responde al pasar el ratón— necesita las mismas piezas en todas
//  partes. Si cada pantalla las escribe por su cuenta, cada una se mueve a
//  un ritmo distinto y el conjunto se ve nervioso.
//
//  Acá están las piezas y, sobre todo, el RITMO: duraciones y curvas
//  acordadas. Todo lo que se mueve en la aplicación sale de `Ritmo`.
//
//  ACCESIBILIDAD
//  -------------
//  Quien activó «reducir movimiento» en su sistema no ve animaciones: cada
//  pieza consulta `MediaQuery.disableAnimations` y, si está activo, muestra
//  el estado final directamente.
// ============================================================================

/// Duraciones y curvas acordadas.
class Ritmo {
  Ritmo._();

  /// Respuesta a un toque o a pasar el ratón: tiene que sentirse inmediata.
  static const Duration toque = Duration(milliseconds: 160);

  /// Entrada de un elemento en pantalla.
  static const Duration entrada = Duration(milliseconds: 460);

  /// Cambio de pantalla.
  static const Duration pagina = Duration(milliseconds: 340);

  /// Una cifra que sube contando.
  static const Duration cifra = Duration(milliseconds: 900);

  /// Separación entre elementos que entran escalonados.
  static const Duration escalon = Duration(milliseconds: 45);

  /// Curva de entrada: arranca rápido y se posa suave.
  static const Curve suave = Curves.easeOutCubic;

  /// Curva con un pequeño rebote al final, para lo que «aterriza».
  static const Curve rebote = Curves.easeOutBack;

  /// ¿El usuario pidió reducir el movimiento?
  static bool reducido(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

// ─────────────────────────────────────────────────────────────────────────
//  Transición entre pantallas
// ─────────────────────────────────────────────────────────────────────────

/// Transición de página de toda la aplicación: la pantalla nueva aparece
/// subiendo un poco y con un leve acercamiento, y la anterior se aparta
/// apenas. Es la misma en Android, Windows y el resto, para que la
/// aplicación se sienta igual en la caja y en el teléfono.
class TransicionSuave extends PageTransitionsBuilder {
  const TransicionSuave();

  @override
  Duration get transitionDuration => Ritmo.pagina;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (Ritmo.reducido(context)) return child;

    final entra = CurvedAnimation(
        parent: animation, curve: Ritmo.suave, reverseCurve: Curves.easeInCubic);
    final sale = CurvedAnimation(parent: secondaryAnimation, curve: Ritmo.suave);

    return FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(
          CurvedAnimation(parent: animation, curve: const Interval(0, 0.7))),
      child: SlideTransition(
        position: Tween<Offset>(
                begin: const Offset(0, 0.035), end: Offset.zero)
            .animate(entra),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(entra),
          child: ScaleTransition(
            // La pantalla de atrás se aleja un poco: da sensación de capas.
            scale: Tween<double>(begin: 1, end: 0.97).animate(sale),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Entrada escalonada
// ─────────────────────────────────────────────────────────────────────────

/// Hace aparecer a su hijo subiendo y desvaneciéndose hacia dentro.
///
/// Con `indice` se escalona: en una lista o una rejilla, cada elemento
/// entra un poco después del anterior. El retraso se topa en 12 escalones
/// para que una lista larga no tarde segundos en terminar de aparecer.
class Aparecer extends StatefulWidget {
  const Aparecer({
    super.key,
    required this.child,
    this.indice = 0,
    this.desplazamiento = 18,
    this.retraso = Duration.zero,
    this.escalonarSolo = false,
  });

  final Widget child;
  final int indice;

  /// Sin conocer su posición, se escalona con los que aparecen junto a él
  /// (ver [Rafaga]). Es lo que usa la `Card` común: una lista de tarjetas
  /// entra una detrás de otra sin que cada pantalla pase el índice.
  final bool escalonarSolo;

  /// Cuántos píxeles sube al entrar.
  final double desplazamiento;
  final Duration retraso;

  @override
  State<Aparecer> createState() => _AparecerState();
}

class _AparecerState extends State<Aparecer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Ritmo.entrada);
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    final escalones =
        math.min(widget.escalonarSolo ? Rafaga.siguiente() : widget.indice, 12);
    final retraso = widget.retraso + Ritmo.escalon * escalones;
    if (retraso == Duration.zero) {
      _c.forward();
    } else {
      _espera = Timer(retraso, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _espera?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Ritmo.reducido(context)) return widget.child;
    final curva = CurvedAnimation(parent: _c, curve: Ritmo.suave);
    return AnimatedBuilder(
      animation: curva,
      child: widget.child,
      builder: (_, hijo) => Opacity(
        opacity: curva.value,
        child: Transform.translate(
          offset: Offset(0, (1 - curva.value) * widget.desplazamiento),
          child: hijo,
        ),
      ),
    );
  }
}

/// Cuenta los elementos que aparecen casi a la vez (una lista que se abre)
/// para escalonarlos: el primero entra enseguida, cada uno de los
/// siguientes un poco después. Una pausa de más de 120 ms empieza otra
/// ráfaga.
class Rafaga {
  Rafaga._();
  static int _n = 0;
  static DateTime _ultima = DateTime.fromMillisecondsSinceEpoch(0);

  static int siguiente() {
    final ahora = DateTime.now();
    _n = ahora.difference(_ultima) < const Duration(milliseconds: 120) ? _n + 1 : 0;
    _ultima = ahora;
    return _n;
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Cifras que cuentan
// ─────────────────────────────────────────────────────────────────────────

/// Un texto ya formateado («\$ 1.234,56», «45 equipos», «Bs 12.500») cuyo
/// número sube contando, como las cifras del Panel Corporativo. Respeta el
/// formato que trae: separador de miles y decimales, cantidad de
/// decimales, lo que va antes y después. Si el texto no tiene un número,
/// se muestra tal cual.
///
/// Sirve para poner la animación en las tarjetas de totales de cada
/// pantalla sin cambiar cómo calculan y formatean su valor.
class TextoQueCuenta extends StatefulWidget {
  const TextoQueCuenta(this.texto,
      {super.key, this.style, this.maxLines, this.overflow, this.textAlign});

  final String texto;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  State<TextoQueCuenta> createState() => _TextoQueCuentaState();
}

/// Número dentro de un texto y cómo volver a escribirlo.
class CifraEnTexto {
  CifraEnTexto._(this.antes, this.despues, this.valor, this.decimales,
      this.sepMiles, this.sepDecimal);

  final String antes, despues;
  final double valor;
  final int decimales;
  final String? sepMiles, sepDecimal;

  static final _patron = RegExp(r'-?\d[\d.,]*');

  static CifraEnTexto? leer(String texto) {
    final m = _patron.firstMatch(texto);
    if (m == null) return null;
    var num = m.group(0)!;
    // Una coma o un punto al final no es parte del número («45,»).
    while (num.endsWith('.') || num.endsWith(',')) {
      num = num.substring(0, num.length - 1);
    }
    final fin = m.start + num.length;
    String? sepDec;
    var decimales = 0;
    final ultimo = num.lastIndexOf(RegExp(r'[.,]'));
    if (ultimo >= 0) {
      final cola = num.length - ultimo - 1;
      final sep = num[ultimo];
      final repetido = sep.allMatches(num).length > 1;
      // «1.234» (3 cifras tras el único separador) se lee como miles; «1,5»
      // o «1.234,56» como decimales.
      if (!repetido && cola != 3) {
        sepDec = sep;
        decimales = cola;
      } else if (!repetido && cola == 3 && num.contains(sep == '.' ? ',' : '.')) {
        sepDec = sep;
        decimales = cola;
      }
    }
    String? sepMil;
    for (final c in ['.', ',']) {
      if (c != sepDec && num.contains(c)) sepMil = c;
    }
    var limpio = num;
    if (sepMil != null) limpio = limpio.replaceAll(sepMil, '');
    if (sepDec != null) limpio = limpio.replaceAll(sepDec, '.');
    final v = double.tryParse(limpio);
    if (v == null) return null;
    return CifraEnTexto._(texto.substring(0, m.start), texto.substring(fin), v,
        decimales, sepMil, sepDec);
  }

  String escribir(double v) {
    final neg = v < 0;
    final fijo = v.abs().toStringAsFixed(decimales);
    final partes = fijo.split('.');
    var entero = partes[0];
    if (sepMiles != null) {
      final b = StringBuffer();
      for (var i = 0; i < entero.length; i++) {
        if (i > 0 && (entero.length - i) % 3 == 0) b.write(sepMiles);
        b.write(entero[i]);
      }
      entero = b.toString();
    }
    final dec = decimales > 0 ? '${sepDecimal ?? '.'}${partes[1]}' : '';
    return '$antes${neg ? '-' : ''}$entero$dec$despues';
  }
}

class _TextoQueCuentaState extends State<TextoQueCuenta> {
  double _desde = 0;
  CifraEnTexto? _cifra;

  @override
  void initState() {
    super.initState();
    _cifra = CifraEnTexto.leer(widget.texto);
  }

  @override
  void didUpdateWidget(TextoQueCuenta viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.texto != widget.texto) {
      _desde = _cifra?.valor ?? 0;
      _cifra = CifraEnTexto.leer(widget.texto);
    }
  }

  Text _texto(String s) => Text(s,
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      textAlign: widget.textAlign);

  @override
  Widget build(BuildContext context) {
    final c = _cifra;
    if (c == null || Ritmo.reducido(context)) return _texto(widget.texto);
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.texto),
      tween: Tween(begin: _desde, end: c.valor),
      duration: Ritmo.cifra,
      curve: Curves.easeOutExpo,
      // Al terminar se muestra el texto original exacto.
      builder: (_, v, __) => _texto(v == c.valor ? widget.texto : c.escribir(v)),
    );
  }
}

/// Muestra una cifra que sube contando hasta su valor. Cuando el valor
/// cambia (al refrescar), cuenta desde el anterior, no desde cero: así se
/// ve CUÁNTO cambió.
class CifraAnimada extends StatefulWidget {
  const CifraAnimada({
    super.key,
    required this.valor,
    required this.formato,
    this.estilo,
    this.maxLines = 1,
  });

  final double valor;

  /// Cómo se escribe la cifra: `formatCurrency`, un entero, un porcentaje…
  final String Function(double) formato;
  final TextStyle? estilo;
  final int maxLines;

  @override
  State<CifraAnimada> createState() => _CifraAnimadaState();
}

class _CifraAnimadaState extends State<CifraAnimada> {
  double _desde = 0;

  @override
  void didUpdateWidget(CifraAnimada viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.valor != widget.valor) _desde = viejo.valor;
  }

  @override
  Widget build(BuildContext context) {
    if (Ritmo.reducido(context)) {
      return Text(widget.formato(widget.valor),
          style: widget.estilo,
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis);
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey(widget.valor),
      tween: Tween(begin: _desde, end: widget.valor),
      duration: Ritmo.cifra,
      curve: Curves.easeOutExpo,
      builder: (_, v, __) => Text(widget.formato(v),
          style: widget.estilo,
          maxLines: widget.maxLines,
          overflow: TextOverflow.ellipsis),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Indicador «en vivo»
// ─────────────────────────────────────────────────────────────────────────

/// Píldora verde con un punto que late y una hora: dice que lo que se
/// está viendo está al día.
///
/// Sin `hora` muestra el reloj (para lo que de verdad se actualiza solo).
/// Con `hora` muestra ESA hora fija —la de la última carga—: un tablero
/// que se refresca cada cinco minutos no puede presumir la hora actual.
class EnVivo extends StatefulWidget {
  const EnVivo(
      {super.key, this.texto = 'En vivo', this.oscuro = false, this.hora});

  final String texto;
  final DateTime? hora;

  /// `true` cuando va sobre un fondo oscuro (un encabezado azul).
  final bool oscuro;

  @override
  State<EnVivo> createState() => _EnVivoState();
}

class _EnVivoState extends State<EnVivo> with SingleTickerProviderStateMixin {
  late final AnimationController _latido = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();
  late Timer _reloj;
  DateTime _ahora = DateTime.now();

  @override
  void initState() {
    super.initState();
    _reloj = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _ahora = DateTime.now());
    });
  }

  @override
  void dispose() {
    _reloj.cancel();
    _latido.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const verde = Color(0xFF16A34A);
    final h = widget.hora ?? _ahora;
    final hora =
        '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';
    final fondo = widget.oscuro
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFE9F8EF);
    final texto = widget.oscuro ? Colors.white : const Color(0xFF166534);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: fondo, borderRadius: BorderRadius.circular(AppRadius.full)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 12,
          height: 12,
          child: Ritmo.reducido(context)
              ? const Center(
                  child: CircleAvatar(radius: 3.5, backgroundColor: verde))
              : AnimatedBuilder(
                  animation: _latido,
                  builder: (_, __) => CustomPaint(
                      painter: _PuntoQueLate(_latido.value, verde)),
                ),
        ),
        const SizedBox(width: 6),
        Text('${widget.texto} $hora',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: texto)),
      ]),
    );
  }
}

class _PuntoQueLate extends CustomPainter {
  _PuntoQueLate(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centro = size.center(Offset.zero);
    canvas.drawCircle(centro, 3.5 + 3 * t,
        Paint()..color = color.withValues(alpha: 0.35 * (1 - t)));
    canvas.drawCircle(centro, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PuntoQueLate viejo) => viejo.t != t;
}

// ─────────────────────────────────────────────────────────────────────────
//  Tarjeta viva
// ─────────────────────────────────────────────────────────────────────────

/// Tarjeta blanca flotante que RESPONDE: al pasar el ratón se eleva y su
/// sombra crece; al tocarla se hunde un poco. Es la tarjeta de todo lo que
/// se puede tocar en los tableros (tiendas, módulos, indicadores).
class TarjetaViva extends StatefulWidget {
  const TarjetaViva({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.color = Colors.white,
    this.radio = AppRadius.lg + 2,
    this.acento,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double radio;

  /// Color con el que se tiñe el resplandor al pasar el ratón.
  final Color? acento;

  @override
  State<TarjetaViva> createState() => _TarjetaVivaState();
}

class _TarjetaVivaState extends State<TarjetaViva> {
  bool _encima = false;
  bool _apretada = false;

  @override
  Widget build(BuildContext context) {
    final reducido = Ritmo.reducido(context);
    final acento = widget.acento ?? AppColors.azulVivo;
    final elevada = _encima && widget.onTap != null;
    final radio = BorderRadius.circular(widget.radio);

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() {
        _encima = false;
        _apretada = false;
      }),
      child: AnimatedScale(
        scale: reducido ? 1 : (_apretada ? 0.98 : 1),
        duration: Ritmo.toque,
        curve: Ritmo.suave,
        child: AnimatedContainer(
          duration: reducido ? Duration.zero : Ritmo.toque,
          curve: Ritmo.suave,
          transform: Matrix4.translationValues(0, elevada && !reducido ? -3 : 0, 0),
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: radio,
            border: Border.all(
                color: elevada
                    ? acento.withValues(alpha: 0.35)
                    : AppColors.bordeSuave),
            boxShadow: elevada
                ? [
                    BoxShadow(
                        color: acento.withValues(alpha: 0.16),
                        blurRadius: 28,
                        offset: const Offset(0, 14)),
                    const BoxShadow(
                        color: Color(0x0F1B2A5A),
                        blurRadius: 4,
                        offset: Offset(0, 1)),
                  ]
                : AppElevation.tarjeta,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radio,
              onTap: widget.onTap,
              onTapDown: widget.onTap == null
                  ? null
                  : (_) => setState(() => _apretada = true),
              onTapUp: (_) => setState(() => _apretada = false),
              onTapCancel: () => setState(() => _apretada = false),
              child: Padding(padding: widget.padding, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Chips con contador
// ─────────────────────────────────────────────────────────────────────────

/// Píldora con un punto de color, una etiqueta y un contador:
/// «● Ventas  12 hoy». Es el resumen de un vistazo de los tableros.
class ChipContador extends StatelessWidget {
  const ChipContador({
    super.key,
    required this.color,
    required this.etiqueta,
    required this.valor,
    this.sufijo,
    this.onTap,
  });

  final Color color;
  final String etiqueta;
  final String valor;
  final String? sufijo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const StadiumBorder(side: BorderSide(color: AppColors.bordeSuave)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Text(etiqueta,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(width: 6),
            Text(sufijo == null ? valor : '$valor $sufijo',
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textSecondary)),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Selector de píldoras
// ─────────────────────────────────────────────────────────────────────────

/// Opción de un [SelectorPildoras].
class OpcionPildora<T> {
  const OpcionPildora(this.valor, this.etiqueta, this.icono);
  final T valor;
  final String etiqueta;
  final IconData icono;
}

/// Grupo de píldoras donde la seleccionada se rellena y el relleno se
/// DESLIZA de una a otra al cambiar («Ciudad · Tabla»).
class SelectorPildoras<T> extends StatelessWidget {
  const SelectorPildoras({
    super.key,
    required this.opciones,
    required this.seleccionada,
    required this.alCambiar,
  });

  final List<OpcionPildora<T>> opciones;
  final T seleccionada;
  final ValueChanged<T> alCambiar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: AppColors.bordeSuave),
        boxShadow: AppElevation.tarjeta,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final o in opciones)
          _Pildora(
            opcion: o,
            activa: o.valor == seleccionada,
            onTap: () => alCambiar(o.valor),
          ),
      ]),
    );
  }
}

class _Pildora<T> extends StatelessWidget {
  const _Pildora({required this.opcion, required this.activa, required this.onTap});
  final OpcionPildora<T> opcion;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = activa ? Colors.white : AppColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: Ritmo.reducido(context) ? Duration.zero : Ritmo.entrada,
          curve: Ritmo.suave,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: activa
                ? const LinearGradient(
                    colors: [AppColors.lila, AppColors.azulVivo])
                : null,
            borderRadius: BorderRadius.circular(AppRadius.full),
            boxShadow: activa
                ? [
                    BoxShadow(
                        color: AppColors.lila.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]
                : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(opcion.icono, size: 16, color: color),
            const SizedBox(width: 6),
            Text(opcion.etiqueta,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Esqueletos de carga
// ─────────────────────────────────────────────────────────────────────────

/// Hace pasar un brillo diagonal sobre sus hijos, una y otra vez. Va
/// encima de los [Esqueleto] mientras llegan los datos: la pantalla
/// muestra su forma desde el primer instante en vez de un círculo
/// girando sobre un fondo vacío.
class Brillo extends StatefulWidget {
  const Brillo({super.key, required this.child});
  final Widget child;

  @override
  State<Brillo> createState() => _BrilloState();
}

class _BrilloState extends State<Brillo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Ritmo.reducido(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, hijo) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (r) {
          final x = -1.5 + 3.0 * _c.value;
          return LinearGradient(
            begin: Alignment(x - 0.6, -0.3),
            end: Alignment(x + 0.6, 0.3),
            colors: const [
              Color(0x00FFFFFF),
              Color(0x99FFFFFF),
              Color(0x00FFFFFF),
            ],
          ).createShader(r);
        },
        child: hijo,
      ),
    );
  }
}

/// Bloque gris con la forma de algo que todavía no llegó.
class Esqueleto extends StatelessWidget {
  const Esqueleto({super.key, this.ancho, this.alto = 14, this.radio = 8});
  final double? ancho;
  final double alto;
  final double radio;

  @override
  Widget build(BuildContext context) => Container(
        width: ancho,
        height: alto,
        decoration: BoxDecoration(
          color: const Color(0xFFE6E9F4),
          borderRadius: BorderRadius.circular(radio),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────
//  Destello al cambiar
// ─────────────────────────────────────────────────────────────────────────

/// Un resplandor breve alrededor de su hijo cada vez que `valor` cambia
/// (no al aparecer). Marca de un vistazo QUÉ cifra se movió al refrescar.
class Destello extends StatefulWidget {
  const Destello({
    super.key,
    required this.valor,
    required this.child,
    this.color = AppColors.azulVivo,
    this.radio = AppRadius.lg + 2,
  });

  final Object valor;
  final Widget child;
  final Color color;
  final double radio;

  @override
  State<Destello> createState() => _DestelloState();
}

class _DestelloState extends State<Destello>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100), value: 1);

  @override
  void didUpdateWidget(Destello viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.valor != widget.valor && !Ritmo.reducido(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, hijo) {
        final v = 1 - Curves.easeOutCubic.transform(_c.value);
        if (v <= 0) return hijo!;
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radio),
            border: Border.all(
                color: widget.color.withValues(alpha: 0.7 * v), width: 2),
            boxShadow: [
              BoxShadow(
                  color: widget.color.withValues(alpha: 0.35 * v),
                  blurRadius: 24 * v,
                  spreadRadius: 1),
            ],
          ),
          child: hijo,
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Fila de indicadores (la del Panel Corporativo, para todas las pantallas)
// ─────────────────────────────────────────────────────────────────────────

/// Un indicador: etiqueta, cifra ya formateada («$ 1.234,56», «45»), ícono
/// y color de acento. `detalle` es la línea chica de abajo.
class Indicador {
  const Indicador(this.titulo, this.valor,
      {required this.icono, this.color = AppColors.azulVivo, this.detalle, this.onTap});

  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;
  final String? detalle;
  final VoidCallback? onTap;
}

/// Las tarjetas de indicadores del Panel Corporativo (pedido del dueño,
/// 10/10/2026: «el estilo del panel en TODA la aplicación»). Cada una es
/// una tarjeta blanca que se eleva, con su ícono en un cuadrito del color
/// de acento, la cifra que sube contando y destella al cambiar, y entrada
/// escalonada. Con espacio se reparten a lo ancho; si no caben, la fila se
/// desliza de lado.
///
/// Reemplaza a los bloques azul marino con cifras blancas que cada
/// pantalla se había hecho a mano.
class FilaIndicadores extends StatelessWidget {
  const FilaIndicadores(this.items,
      {super.key, this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 6)});

  final List<Indicador> items;
  final EdgeInsetsGeometry padding;

  static const double _ancho = 168;

  Widget _tarjeta(Indicador k, int i, double? ancho) {
    final cifra = CifraEnTexto.leer(k.valor);
    final colorCifra =
        k.color == AppColors.azulVivo ? AppColors.textPrimary : k.color;
    return Aparecer(
      indice: i,
      child: SizedBox(
        width: ancho,
        child: Destello(
          valor: cifra?.valor ?? k.valor,
          color: k.color,
          child: TarjetaViva(
            acento: k.color,
            onTap: k.onTap,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: k.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(9)),
                        child: Icon(k.icono, color: k.color, size: 17)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(k.titulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary))),
                  ]),
                  const SizedBox(height: 10),
                  TextoQueCuenta(k.valor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: colorCifra,
                          letterSpacing: -0.3)),
                  if (k.detalle != null) ...[
                    const SizedBox(height: 2),
                    Text(k.detalle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const sep = 12.0;
    return Padding(
      padding: padding,
      child: LayoutBuilder(builder: (context, caja) {
        final cabe = caja.maxWidth >=
            items.length * (_ancho * 0.85) + (items.length - 1) * sep;
        final fila = <Widget>[
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: sep),
            cabe
                ? Expanded(child: _tarjeta(items[i], i, null))
                : _tarjeta(items[i], i, _ancho),
          ],
        ];
        final contenido = IntrinsicHeight(
            child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: fila));
        return cabe
            ? contenido
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: contenido);
      }),
    );
  }
}

/// Título de sección del Panel Corporativo: barra vertical en degradado
/// azul y el título en negrita.
class TituloSeccion extends StatelessWidget {
  const TituloSeccion(this.titulo, {super.key, this.subtitulo, this.accion});

  final String titulo;
  final String? subtitulo;
  final Widget? accion;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Row(children: [
          Container(
              width: 4,
              height: subtitulo == null ? 22 : 34,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.lila, AppColors.azulVivo]))),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(titulo,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3)),
                if (subtitulo != null)
                  Text(subtitulo!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
              ])),
          if (accion != null) accion!,
        ]),
      );
}

/// Una sola tarjeta de indicador del Panel Corporativo, para usar dentro
/// de las filas y rejillas que cada pantalla ya tiene armadas (las
/// funciones `_kpiCard`, `_kpiMini`… de main.dart la devuelven).
class TarjetaIndicador extends StatelessWidget {
  const TarjetaIndicador(this.titulo, this.valor,
      {super.key,
      this.icono = Icons.insights_rounded,
      this.color = AppColors.azulVivo,
      this.detalle,
      this.compacta = false});

  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;
  final String? detalle;
  final bool compacta;

  @override
  Widget build(BuildContext context) {
    final cifra = CifraEnTexto.leer(valor);
    return Destello(
      valor: cifra?.valor ?? valor,
      color: color,
      child: TarjetaViva(
        acento: color,
        padding: EdgeInsets.all(compacta ? 10 : 14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Container(
                    padding: EdgeInsets.all(compacta ? 4 : 6),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9)),
                    child: Icon(icono, color: color, size: compacta ? 14 : 17)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(titulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: compacta ? 11 : 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary))),
              ]),
              SizedBox(height: compacta ? 6 : 10),
              TextoQueCuenta(valor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: compacta ? 16 : 20,
                      fontWeight: FontWeight.w800,
                      color: color == AppColors.azulVivo ? AppColors.textPrimary : color,
                      letterSpacing: -0.3)),
              if (detalle != null) ...[
                const SizedBox(height: 2),
                Text(detalle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ]),
      ),
    );
  }
}
