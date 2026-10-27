// Se importa Material sin prefijo aunque este archivo declare su propia
// `Card`: en Dart lo declarado en la biblioteca actual tiene prioridad
// sobre lo importado, así que dentro de este archivo `Card` es la de
// abajo y el resto de Material sigue disponible con su nombre normal.
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'movimiento.dart';

// ============================================================================
//  neu.dart — Material de las superficies del sistema de diseño
//
//  OCTUBRE 2026: DEL RELIEVE A LA TARJETA FLOTANTE
//  -----------------------------------------------
//  La aplicación pasó del neomorfismo (tarjeta del color del fondo con dos
//  sombras opuestas) al estilo de «tablero vivo»: tarjetas BLANCAS que
//  flotan sobre un fondo lavanda claro, con un contorno casi invisible y
//  una única sombra azulada, ancha y hacia abajo. Es el lenguaje de los
//  paneles de operación modernos y se lleva mejor con las animaciones de
//  `movimiento.dart`: una tarjeta que flota puede elevarse; un relieve
//  moldeado en el fondo, no.
//
//  Los nombres (`AppNeu`, `NeuPanel`, `relieve`, `hundido`) se conservan
//  porque hay cientos de llamadas; lo que cambió es lo que dibujan. Lo de
//  abajo es la explicación original del neomorfismo, que sigue valiendo
//  para entender por qué `Card` vive en este archivo.
//
// ----------------------------------------------------------------------------
//
//  QUÉ ES EL NEOMORFISMO Y POR QUÉ ESTÁ AQUÍ
//  -----------------------------------------
//  En el neomorfismo los elementos no se apoyan SOBRE el fondo: salen
//  DEL fondo. Una tarjeta es del mismo color que la pantalla y lo que la
//  separa son dos sombras opuestas — una luz arriba a la izquierda y una
//  sombra abajo a la derecha—, como si la superficie estuviera moldeada.
//  Lo hundido es lo mismo al revés: sombra arriba, luz abajo.
//
//  De ahí salen las tres reglas que sigue este archivo:
//    1. Tarjeta y fondo comparten color. Si la tarjeta es blanca sobre
//       gris, el efecto no aparece: se ve una tarjeta plana normal.
//    2. Las sombras son de baja opacidad y radio grande. Duras, el
//       resultado parece un botón de plástico de los años noventa.
//    3. Las esquinas son generosas. Un relieve con esquina viva no se
//       lee como relieve.
//
//  LA PALETA NO CAMBIA. Los azules de la marca (`royalBlue`,
//  `primaryBlue`), el dorado y los cuatro colores de estado son los
//  mismos y con los mismos contrastes medidos. Lo que cambia es el
//  MATERIAL sobre el que se apoyan: un gris azulado suave en lugar del
//  blanco plano, dentro de la misma familia que ya tenía `grupoFondo`.
//
//  POR QUÉ `Card` VIVE ACÁ
//  -----------------------
//  La aplicación construye casi todas sus superficies con `Card`, casi
//  200 veces. Reescribir esas llamadas una a una era el camino largo y
//  el que deja mitad de las pantallas sin convertir. En su lugar,
//  `main.dart` importa Material ocultando `Card` y toma el de este
//  archivo, que acepta exactamente los mismos parámetros y dibuja el
//  relieve. Ninguna llamada existente se tocó y todas cambiaron de
//  aspecto a la vez.
// ============================================================================

/// Tokens y decoraciones del relieve.
class AppNeu {
  AppNeu._();

  // ── Material base ────────────────────────────────────────────────
  //
  //  El mismo tono para el fondo y para las superficies: es lo que hace
  //  que una tarjeta parezca moldeada en la pantalla en vez de pegada
  //  encima. En Tecno Líder es el lavanda #F2F3FA, del mismo tinte azul
  //  que el logo (antes `surfaceTintBlue` #F4F5FB, un punto más claro).
  //
  //  NO SE PUEDE OSCURECER MUCHO. Cada punto que baja se lo come el
  //  contraste del texto de estado (naranja, ámbar) sobre el fondo.

  /// Fondo de pantalla y color por defecto de las superficies.
  static const Color base = Color(0xFFF2F3FA);

  /// Superficie de algo que flota: blanco. Contra el lavanda de `base`
  /// es lo que hace que la tarjeta se separe del fondo.
  static const Color superficie = Color(0xFFFFFFFF);

  /// Relleno de lo que va «por dentro» de una tarjeta blanca: campos de
  /// texto, pistas de interruptores, huecos de listas. Un gris lavanda
  /// apenas más oscuro que el blanco, con su contorno suave.
  static const Color hueco = Color(0xFFF4F5FB);

  /// La luz. Va arriba a la izquierda de lo que sobresale.
  static const Color luz = Color(0xFFFFFFFF);

  /// La sombra. Es el azul de la marca desaturado, no un gris neutro:
  /// así queda dentro de la misma familia de color que el resto.
  static const Color sombra = Color(0xFFC9CCE3);

  /// Tinte de las sombras flotantes (el navy a muy baja opacidad).
  static const Color tinteSombra = Color(0xFF1A1D5C);

  /// Contorno casi invisible de una tarjeta blanca.
  static const Color contorno = AppColors.bordeSuave;

  /// Separación estándar entre superficies. En neomorfismo el aire
  /// entre elementos es parte del efecto: dos tarjetas pegadas comen
  /// sus sombras mutuas y el relieve desaparece.
  static const double aire = AppSpacing.md;

  /// Radio por defecto de una superficie en relieve.
  static const double radio = AppRadius.lg;

  // ── Decoraciones ─────────────────────────────────────────────────

  /// Superficie que FLOTA: blanca, con contorno suave y sombra azulada
  /// hacia abajo.
  ///
  /// `intensidad` escala la sombra. Por debajo de 1 la tarjeta apenas se
  /// despega —útil para elementos repetidos muchas veces en una lista,
  /// donde una sombra grande satura—; por encima, flota más alto.
  static BoxDecoration relieve({
    Color? color,
    BorderRadius? borde,
    double intensidad = 1,
    Gradient? degradado,
    BorderSide? lado,
  }) {
    final i = intensidad.clamp(0.3, 2.0);
    return BoxDecoration(
      color: degradado == null ? (color ?? superficie) : null,
      gradient: degradado,
      borderRadius: borde ?? BorderRadius.circular(radio),
      // `lado` es un contorno propio (el de una tarjeta marcada: vendido,
      // saldado, preferida). Sin él, el contorno suave del sistema.
      border: lado != null && lado.style != BorderStyle.none
          ? Border.fromBorderSide(lado)
          : Border.all(color: contorno),
      boxShadow: [
        // La sombra ancha que la hace flotar…
        BoxShadow(
          color: tinteSombra.withValues(alpha: 0.07 * i),
          offset: Offset(0, 8 * i),
          blurRadius: 22 * i,
        ),
        // …y una línea fina pegada al borde inferior que la asienta.
        BoxShadow(
          color: tinteSombra.withValues(alpha: 0.04),
          offset: const Offset(0, 1),
          blurRadius: 3,
        ),
      ],
    );
  }

  /// Superficie HUNDIDA. La sombra interior de verdad no existe en
  /// Flutter (`BoxShadow` solo dibuja hacia fuera), así que se imita
  /// con lo que sí se puede: un tono más oscuro que el fondo y un
  /// degradado diagonal que oscurece el borde superior izquierdo — que
  /// es exactamente la pista visual que da una cavidad.
  ///
  /// Se usa en campos de texto, barras de búsqueda y cualquier hueco
  /// donde el usuario escribe o selecciona.
  static BoxDecoration hundido({
    Color? color,
    BorderRadius? borde,
  }) {
    return BoxDecoration(
      color: color ?? hueco,
      borderRadius: borde ?? BorderRadius.circular(AppRadius.md),
      border: Border.all(color: contorno),
    );
  }

  /// Relieve TEÑIDO de un color de la paleta (un aviso verde, un
  /// distintivo rojo). Mantiene el color de estado tal cual y solo le
  /// pone el relieve alrededor, para que el significado del color no
  /// cambie.
  static BoxDecoration relieveDeColor(Color c,
      {BorderRadius? borde, double intensidad = 0.8}) {
    // El halo es del mismo color: un aviso verde flota sobre un
    // resplandor verde, no sobre una sombra gris.
    return BoxDecoration(
      color: c,
      borderRadius: borde ?? BorderRadius.circular(AppRadius.md),
      boxShadow: [
        BoxShadow(
          color: c.withValues(alpha: 0.30 * intensidad),
          offset: Offset(0, 6 * intensidad),
          blurRadius: 16 * intensidad,
        ),
      ],
    );
  }

  /// Círculo en relieve, para avatares e iconos sueltos.
  static BoxDecoration circulo({Color? color, double intensidad = 0.7}) {
    return BoxDecoration(
      color: color ?? superficie,
      shape: BoxShape.circle,
      border: Border.all(color: contorno),
      boxShadow: [
        BoxShadow(
          color: tinteSombra.withValues(alpha: 0.08),
          offset: Offset(0, 6 * intensidad),
          blurRadius: 14 * intensidad,
        ),
      ],
    );
  }

  /// Sombra suelta para lo que flota de verdad (menús, diálogos,
  /// hojas). Aquí sí hay una fuente de luz única: no es relieve, es un
  /// objeto por encima de la superficie.
  static List<BoxShadow> get flotante => AppElevation.flotante;
}

/// Superficie neomórfica reutilizable.
///
/// Es lo que hay que usar al escribir una pantalla nueva. `Card` (abajo)
/// se apoya en esta misma clase, así que lo viejo y lo nuevo salen
/// idénticos.
class NeuPanel extends StatelessWidget {
  const NeuPanel({
    super.key,
    this.child,
    this.color,
    this.margin,
    this.padding,
    this.borderRadius,
    this.intensidad = 1,
    this.hundida = false,
    this.clipBehavior,
    this.lado,
  });

  final Widget? child;
  final Color? color;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  /// Cuánto relieve. 0,6 para elementos repetidos en una lista larga;
  /// 1 para paneles sueltos.
  final double intensidad;

  /// `true` dibuja una cavidad en vez de un bulto.
  final bool hundida;

  final Clip? clipBehavior;

  /// Contorno propio; null = el suave del sistema.
  final BorderSide? lado;

  @override
  Widget build(BuildContext context) {
    final radio = borderRadius ?? BorderRadius.circular(AppNeu.radio);
    return Container(
      margin: margin,
      padding: padding,
      clipBehavior: clipBehavior ?? Clip.none,
      decoration: hundida
          ? AppNeu.hundido(color: color, borde: radio)
          : AppNeu.relieve(
              color: color, borde: radio, intensidad: intensidad, lado: lado),
      // Sin este Material, las ondas de InkWell y ListTile se pintarían
      // en el Material del Scaffold, o sea DEBAJO de esta decoración
      // opaca: el toque funcionaría pero no se vería nada. Transparente
      // no pinta fondo, solo ofrece superficie de tinta.
      child: child == null
          ? null
          : Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// Reemplazo neomórfico de `Card` de Material.
///
/// Acepta los mismos parámetros con nombre que el original, así que las
/// casi 200 llamadas que ya había en la aplicación siguen compilando sin
/// tocarlas — `main.dart` importa Material con `hide Card` y se queda
/// con esta.
///
/// Diferencias deliberadas con el original:
///   · `elevation: 0` no significa "sin sombra" sino "sombra suave": la
///     tarjeta blanca sigue separándose del fondo lavanda.
///   · El `shape` aporta su radio y, si trae `side`, su contorno (las
///     tarjetas marcadas de Tecno Líder: vendido, saldado, impresora
///     preferida). Sin `side`, el contorno suave del sistema.
///   · `margin` por defecto es CERO, como el `cardTheme` que tenía Tecno
///     Líder: las pantallas ya ponen su propio espacio alrededor.
class Card extends StatelessWidget {
  const Card({
    super.key,
    this.color,
    this.shadowColor,
    this.surfaceTintColor,
    this.elevation,
    this.shape,
    this.borderOnForeground = true,
    this.margin,
    this.clipBehavior,
    this.semanticContainer = true,
    this.child,
  });

  final Color? color;
  final Color? shadowColor;
  final Color? surfaceTintColor;
  final double? elevation;
  final ShapeBorder? shape;
  final bool borderOnForeground;
  final EdgeInsetsGeometry? margin;
  final Clip? clipBehavior;
  final bool semanticContainer;
  final Widget? child;

  /// Radio declarado en el `shape` de la llamada, si lo hay.
  ///
  /// Muchas pantallas pasan `RoundedRectangleBorder(borderRadius: ...)`
  /// para redondear una tarjeta concreta; ese radio se respeta, porque
  /// suele ir coordinado con lo que la tarjeta contiene.
  BorderRadius? get _radioDelShape {
    final s = shape;
    if (s is RoundedRectangleBorder) {
      final r = s.borderRadius;
      if (r is BorderRadius) return r;
    }
    return null;
  }

  /// Contorno declarado en el `shape` de la llamada, si lo hay.
  BorderSide? get _ladoDelShape {
    final s = shape;
    if (s is OutlinedBorder && s.side != BorderSide.none) return s.side;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Una tarjeta muy plana (elevation 0) se insinúa; una muy elevada
    // sobresale más. El rango se acota para que ninguna pantalla que
    // pidiera `elevation: 12` acabe con una sombra desproporcionada.
    final e = elevation ?? 1;
    final intensidad = e <= 0 ? 0.65 : (0.8 + (e * 0.08)).clamp(0.65, 1.6);

    // Como las tarjetas de Brizuela (Panel Corporativo): entran subiendo
    // y se elevan al pasar el ratón.
    return Aparecer(
      desplazamiento: 10,
      escalonarSolo: true,
      child: _TarjetaQueSeEleva(
        builder: (encima) => NeuPanel(
          margin: margin ?? EdgeInsets.zero,
          color: color ?? AppNeu.superficie,
          borderRadius: _radioDelShape ?? BorderRadius.circular(AppNeu.radio),
          intensidad: (encima ? intensidad * 1.6 : intensidad).toDouble(),
          clipBehavior: clipBehavior ?? Clip.none,
          lado: _ladoDelShape,
          child: child,
        ),
      ),
    );
  }
}

/// Sube la tarjeta 2 px y le da más sombra mientras el ratón está encima.
/// En el teléfono no hay «encima» y no hace nada.
class _TarjetaQueSeEleva extends StatefulWidget {
  const _TarjetaQueSeEleva({required this.builder});
  final Widget Function(bool encima) builder;

  @override
  State<_TarjetaQueSeEleva> createState() => _TarjetaQueSeElevaState();
}

class _TarjetaQueSeElevaState extends State<_TarjetaQueSeEleva> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final mover = _encima && !Ritmo.reducido(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: AnimatedContainer(
        transform: Matrix4.translationValues(0, mover ? -2 : 0, 0),
        duration: Ritmo.toque,
        curve: Ritmo.suave,
        child: widget.builder(mover),
      ),
    );
  }
}

/// Envoltura hundida para un campo de formulario suelto.
///
/// El tema ya deja los `TextField` con el fondo del hueco y sin borde
/// duro; esto es para los sitios donde el campo va dentro de una
/// tarjeta del mismo color y hace falta marcar la cavidad.
class NeuCampo extends StatelessWidget {
  const NeuCampo({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
        decoration: AppNeu.hundido(),
        child: Padding(
          padding: padding ??
              const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          child: Material(type: MaterialType.transparency, child: child),
        ),
      );
}
