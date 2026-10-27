import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'movimiento.dart';
import 'neu.dart';

// ============================================================================
//  app_theme.dart — Sistema de diseño de Tecno Líder
//
//  QUÉ ES ESTO Y POR QUÉ ESTÁ SEPARADO
//  -----------------------------------
//  Es el mismo sistema de diseño de la app de Brizuela (tarjetas blancas
//  que flotan sobre un fondo lavanda, barra superior blanca, cifras que
//  suben contando), portado con la MARCA de Tecno Líder: el azul royal
//  del logo (#2E3192) y el amarillo dorado (#FFC20E).
//
//  Acá se define en un solo lugar:
//    · La paleta. `AppColors` vivía en main.dart; se movió aquí con TODOS
//      sus nombres de siempre (brand*, alias, surfaceTintBlue*, dark*,
//      degradados y sombras) más los del sistema nuevo (azulVivo, lila,
//      bordeSuave, tonos tenues…).
//    · Una escala de espaciado y de radios.
//    · El tema de todos los componentes de Material que usa la aplicación.
//
//  SOBRE EL AMARILLO
//  -----------------
//  El amarillo de la marca es de RELLENO: botón principal del login, FAB,
//  avatar, la línea bajo la barra de inicio. Nunca como texto sobre
//  blanco (CR 1,6:1, no se lee). Por eso `statusYellow` ya no es el
//  amarillo del logo sino un ámbar oscuro legible.
// ============================================================================

/// Paleta de Tecno Líder.
class AppColors {
  AppColors._();

  // ── Marca (logo) ─────────────────────────────────────────────────
  static const Color brandBlue       = Color(0xFF2E3192); // azul logo
  static const Color brandBlueDark   = Color(0xFF1F2270); // azul oscuro
  static const Color brandBlueDeeper = Color(0xFF15184F); // casi negro azul
  static const Color brandYellow     = Color(0xFFFFC20E); // amarillo logo
  static const Color brandYellowDark = Color(0xFFE5A800); // hover/pressed

  // ── Aliases por compatibilidad con código existente ───────────
  static const Color primaryBlue      = brandBlue;
  /// Azul principal: títulos de barra, iconos de barra. CR 13:1 sobre blanco.
  static const Color royalBlue        = brandBlueDark;
  static const Color accentYellow     = brandYellow;
  static const Color accentYellowDark = brandYellowDark;

  // Nombres del sistema de Brizuela, con los colores de Tecno Líder.
  static const Color grupoAzul        = brandBlueDeeper;
  static const Color grupoAzulMedio   = brandBlue;
  static const Color grupoDorado      = brandYellow;
  static const Color grupoDoradoClaro = Color(0xFFFFD95A);
  static const Color grupoFondo       = Color(0xFFF2F3FA);
  static const Color grupoBorde       = Color(0xFFE2E4F0);

  // ── Acentos vivos (estilo «tablero vivo») ────────────────────────
  /// Azul de acción: botones, enlaces, selección, iconos de menú.
  /// El mismo tono del logo con más luz. Se lee con texto blanco encima
  /// y como texto sobre el fondo de la aplicación.
  static const Color azulVivo         = Color(0xFF3B41C5);

  /// Acento de realce (barra de los títulos de sección, degradados
  /// «lila → azulVivo»). En Tecno Líder es el azul oscuro de la marca.
  static const Color lila             = Color(0xFF1F2270);
  static const Color lilaTenue        = Color(0xFFE9EAF8);

  /// Contorno casi invisible de las tarjetas blancas.
  static const Color bordeSuave       = Color(0xFFE3E5F3);

  // ── Estados ──────────────────────────────────────────────────────
  //  Se usan como TEXTO sobre fondo claro y como FONDO con texto blanco
  //  encima: tonos con contraste suficiente para las dos cosas.
  static const Color statusGreen      = Color(0xFF2E7D32);
  /// Ámbar legible (antes era el amarillo del logo: invisible como texto).
  static const Color statusYellow     = Color(0xFF8D6708);
  static const Color statusRed        = Color(0xFFC62828);
  static const Color statusOrange     = Color(0xFFB3541E);

  // ── Superficies y texto (modo claro) ─────────────────────────────
  static const Color backgroundWhite  = Color(0xFFFFFFFF);
  /// Relleno de lo que va «por dentro» (campos, bloques hundidos). Vale
  /// lo mismo que `AppNeu.hueco`.
  static const Color surfaceGrey      = Color(0xFFF4F5FB);
  static const Color surfaceCard      = Color(0xFFFFFFFF);
  /// Fondo de pantalla con tinte azul Tecno Líder. Vale lo mismo que
  /// `AppNeu.base`.
  static const Color surfaceTintBlue  = Color(0xFFF2F3FA);
  /// Fondo de cards "destacados" con tinte azul aún más leve.
  static const Color surfaceTintBlueSoft = Color(0xFFFAFBFE);
  static const Color textPrimary      = Color(0xFF1A1A2E);
  /// Texto secundario: 5,4:1 sobre el fondo lavanda.
  static const Color textSecondary    = Color(0xFF5C6472);
  static const Color cardBorder       = Color(0xFFDDE0EF);
  /// Borde con tinte azul para cards/inputs.
  static const Color cardBorderTinted = Color(0xFFDDE0EF);
  static const Color iconMuted        = Color(0xFF9CA3AF);

  // ── Tonos derivados ──────────────────────────────────────────────
  static const Color verdeTenue   = Color(0xFFE8F5E9);
  static const Color ambarTenue   = Color(0xFFFFF8E1);
  static const Color rojoTenue    = Color(0xFFFDECEA);
  static const Color naranjaTenue = Color(0xFFFFF3E0);
  static const Color azulTenue    = Color(0xFFEEEFFB);

  // ── Modo OSCURO (la app no lo usa; se conserva por compatibilidad) ──
  static const Color darkBackground  = Color(0xFF0F1117); // fondo principal
  static const Color darkSurface     = Color(0xFF181B23); // cards
  static const Color darkSurfaceAlt  = Color(0xFF1F232D); // cards alternativos
  static const Color darkBorder      = Color(0xFF2A2F3A);
  static const Color darkTextPrimary   = Color(0xFFF3F4F6);
  static const Color darkTextSecondary = Color(0xFF9CA3AF);

  // ── Gradientes pre-armados ───────────────────────────────────
  /// Gradiente principal para fondos premium (splash, hero).
  static const LinearGradient gradientHero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandBlue, brandBlueDark, brandBlueDeeper],
    stops: [0.0, 0.55, 1.0],
  );

  /// Gradiente para el botón principal (CTA amarillo).
  static const LinearGradient gradientCTA = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [brandYellow, brandYellowDark],
  );

  /// Gradiente azul (cabeceras que todavía lo usan).
  static const LinearGradient gradientAppBar = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandBlueDark, brandBlue],
  );

  // ── Sombras estandarizadas ───────────────────────────────────
  static List<BoxShadow> shadowCard({bool dark = false}) => [
    BoxShadow(
      color: dark
          ? Colors.black.withValues(alpha: 0.40)
          : AppNeu.tinteSombra.withValues(alpha: 0.07),
      blurRadius: 22, offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> shadowElevated({bool dark = false}) => [
    BoxShadow(
      color: dark
          ? Colors.black.withValues(alpha: 0.55)
          : AppNeu.tinteSombra.withValues(alpha: 0.12),
      blurRadius: 40, offset: const Offset(0, 16),
    ),
  ];

  static List<BoxShadow> shadowYellowGlow() => [
    BoxShadow(
      color: brandYellow.withValues(alpha: 0.35),
      blurRadius: 20, offset: const Offset(0, 6),
    ),
  ];
}

/// Escala de espaciado.
///
/// Todos los márgenes y rellenos salen de estos siete valores. Antes se
/// elegían a ojo —hay 6, 7, 9, 11, 13 y 14 píxeles repartidos por la
/// aplicación—, y esa irregularidad es lo que hace que una interfaz se
/// vea descuidada aunque cada pantalla por separado parezca correcta.
class AppSpacing {
  AppSpacing._();
  static const double xs  = 4;
  static const double sm  = 8;
  static const double md  = 12;
  static const double lg  = 16;
  static const double xl  = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

/// Radios de esquina.
class AppRadius {
  AppRadius._();
  static const double sm   = 8;
  static const double md   = 12;
  static const double lg   = 16;
  static const double xl   = 24;
  static const double full = 999;

  static BorderRadius get rSm => BorderRadius.circular(sm);
  static BorderRadius get rMd => BorderRadius.circular(md);
  static BorderRadius get rLg => BorderRadius.circular(lg);
  static BorderRadius get rXl => BorderRadius.circular(xl);
}

/// Sombras.
///
/// Dos niveles y nada más. Las sombras son azuladas (el navy de la marca a
/// muy baja opacidad), anchas y hacia abajo: es lo que hace que una
/// tarjeta blanca parezca flotar sobre el fondo lavanda en vez de estar
/// pegada.
class AppElevation {
  AppElevation._();

  static List<BoxShadow> get tarjeta => const [
    BoxShadow(color: Color(0x121A1D5C), blurRadius: 22, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x0A1A1D5C), blurRadius: 3,  offset: Offset(0, 1)),
  ];

  static List<BoxShadow> get flotante => const [
    BoxShadow(color: Color(0x1F1A1D5C), blurRadius: 40, offset: Offset(0, 16)),
    BoxShadow(color: Color(0x0D1A1D5C), blurRadius: 6,  offset: Offset(0, 2)),
  ];
}

/// Construcción del tema de la aplicación.
class AppTheme {
  AppTheme._();

  /// Cuánto se deja crecer el texto cuando el usuario sube el tamaño de
  /// letra del sistema.
  ///
  /// La aplicación tiene más de 1.300 tamaños de fuente escritos como
  /// números fijos, dentro de filas y tarjetas de alto acotado. Sin
  /// límite, un usuario con la letra al 200 % vería los textos cortados
  /// en el punto de venta. Sin escalado ninguno —que es como estaba—,
  /// quien necesita letra grande sencillamente no puede usar el sistema.
  ///
  /// El intervalo 0,9–1,3 es el compromiso: se nota de verdad y no
  /// rompe ninguna pantalla.
  static const double escalaTextoMinima = 0.9;
  static const double escalaTextoMaxima = 1.3;

  static TextTheme _tipografia(ColorScheme c) {
    // Escala tipográfica con una progresión regular. El peso y el
    // interletrado bajan a medida que sube el tamaño, que es lo que hace
    // que un título se lea como título sin necesidad de gritar.
    return TextTheme(
      displayLarge:  TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: c.onSurface),
      displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: c.onSurface),
      displaySmall:  TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: c.onSurface),
      headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: c.onSurface),
      headlineMedium:TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.onSurface),
      headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.onSurface),
      titleLarge:    TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.onSurface),
      titleMedium:   TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.onSurface),
      titleSmall:    TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.onSurface),
      bodyLarge:     TextStyle(fontSize: 15, height: 1.45, color: c.onSurface),
      bodyMedium:    TextStyle(fontSize: 14, height: 1.45, color: c.onSurface),
      bodySmall:     const TextStyle(fontSize: 12, height: 1.40, color: AppColors.textSecondary),
      labelLarge:    TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: c.onSurface),
      labelMedium:   TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: c.onSurface),
      labelSmall:    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: AppColors.textSecondary),
    );
  }

  static ThemeData claro() {
    const c = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.royalBlue,
      onPrimary: Colors.white,
      primaryContainer: AppColors.azulTenue,
      onPrimaryContainer: AppColors.royalBlue,
      secondary: AppColors.azulVivo,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.azulTenue,
      onSecondaryContainer: AppColors.royalBlue,
      tertiary: AppColors.brandYellow,
      onTertiary: AppColors.brandBlueDeeper,
      error: AppColors.statusRed,
      onError: Colors.white,
      errorContainer: AppColors.rojoTenue,
      onErrorContainer: AppColors.statusRed,
      // La superficie del esquema es el material neomórfico, no blanco:
      // así los componentes de Material que se pintan solos (menús de
      // fecha, selectores) nacen del mismo tono que el resto.
      surface: AppNeu.superficie,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppNeu.hueco,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.cardBorder,
      outlineVariant: AppColors.grupoBorde,
      shadow: Color(0x1A101828),
      scrim: Color(0x99000000),
      inverseSurface: AppColors.textPrimary,
      onInverseSurface: Colors.white,
      inversePrimary: AppColors.primaryBlue,
    );

    final texto = _tipografia(c);

    return ThemeData(
      useMaterial3: true,
      colorScheme: c,
      textTheme: texto,
      // El fondo y las superficies comparten tono: es la condición
      // para que el relieve neomórfico se vea (ver `neu.dart`). Una
      // tarjeta blanca sobre gris se lee como tarjeta plana.
      scaffoldBackgroundColor: AppNeu.base,
      canvasColor: AppNeu.base,
      // Densidad ligeramente compacta: es un sistema de gestión con
      // mucha información por pantalla, no una app de consumo.
      visualDensity: VisualDensity.compact,
      splashFactory: InkSparkle.splashFactory,

      // ── Cambio de pantalla ──
      // La misma transición suave en todas las plataformas (ver
      // `movimiento.dart`): cada `Navigator.push` de la aplicación la
      // hereda sin tocar ninguna pantalla.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: TransicionSuave(),
        TargetPlatform.iOS: TransicionSuave(),
        TargetPlatform.windows: TransicionSuave(),
        TargetPlatform.macOS: TransicionSuave(),
        TargetPlatform.linux: TransicionSuave(),
        TargetPlatform.fuchsia: TransicionSuave(),
      }),

      // ── Barra superior ──
      // Blanca y flotante, como en Brizuela (estilo del Panel
      // Corporativo): esquinas de abajo redondeadas, sombra suave
      // azulada y título en azul marino.
      appBarTheme: AppBarTheme(
        backgroundColor: AppNeu.superficie,
        foregroundColor: AppColors.royalBlue,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        scrolledUnderElevation: 4,
        shadowColor: const Color(0x331A1D5C),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppRadius.lg + 4)),
        ),
        centerTitle: false,
        titleSpacing: AppSpacing.lg,
        titleTextStyle: texto.titleLarge?.copyWith(
          color: AppColors.royalBlue,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
        ),
        iconTheme: const IconThemeData(color: AppColors.royalBlue, size: 22),
        actionsIconTheme: const IconThemeData(color: AppColors.royalBlue, size: 22),
        // Íconos de la barra de estado oscuros sobre el blanco.
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),

      // ── Botones ──
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.azulVivo,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppNeu.hueco,
          disabledForegroundColor: AppColors.textSecondary,
          // Píldora con un halo del mismo azul debajo: el botón principal
          // flota sobre la tarjeta, igual que la tarjeta sobre el fondo.
          elevation: 3,
          shadowColor: AppColors.azulVivo.withValues(alpha: 0.45),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl, vertical: AppSpacing.md + 2),
          minimumSize: const Size(0, 46),   // objetivo táctil cómodo
          shape: const StadiumBorder(),
          textStyle: texto.labelLarge,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.azulVivo,
          foregroundColor: Colors.white,
          elevation: 3,
          shadowColor: AppColors.azulVivo.withValues(alpha: 0.45),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl, vertical: AppSpacing.md + 2),
          minimumSize: const Size(0, 46),
          shape: const StadiumBorder(),
          textStyle: texto.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.azulVivo,
          backgroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl, vertical: AppSpacing.md + 2),
          minimumSize: const Size(0, 46),
          side: const BorderSide(color: AppColors.bordeSuave, width: 1.2),
          shape: const StadiumBorder(),
          textStyle: texto.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.azulVivo,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.rSm),
          textStyle: texto.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          minimumSize: const Size(40, 40),   // accesible al toque
          shape: RoundedRectangleBorder(borderRadius: AppRadius.rSm),
        ),
      ),
      // FAB en el amarillo de la marca: es el botón de acción principal.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.brandYellow,
        foregroundColor: AppColors.brandBlueDeeper,
        elevation: 6,
        focusElevation: 8,
        highlightElevation: 10,
        hoverElevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll(texto.labelMedium),
          // Selector en píldora: píldora, y la opción
          // elegida se rellena del azul de acción.
          backgroundColor: WidgetStateProperty.resolveWith((e) =>
              e.contains(WidgetState.selected) ? AppColors.azulVivo : Colors.white),
          foregroundColor: WidgetStateProperty.resolveWith((e) =>
              e.contains(WidgetState.selected) ? Colors.white : AppColors.textPrimary),
          side: const WidgetStatePropertyAll(
              BorderSide(color: AppColors.bordeSuave)),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
        ),
      ),

      // ── Campos de formulario ──
      // Los campos van HUNDIDOS: fondo un punto más oscuro que la
      // superficie y sin borde duro. Un rectángulo con contorno de un
      // píxel sobre una pantalla en relieve se lee como un parche.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppNeu.hueco,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md + 2),
        labelStyle: texto.bodyMedium?.copyWith(color: AppColors.textSecondary),
        floatingLabelStyle: texto.bodyMedium?.copyWith(
            color: AppColors.azulVivo, fontWeight: FontWeight.w600),
        hintStyle: texto.bodyMedium?.copyWith(color: AppColors.textSecondary),
        helperStyle: texto.bodySmall,
        // El error se muestra en dos líneas si hace falta: cortarlo a una
        // sola dejaba mensajes truncados que no decían qué corregir.
        errorStyle: texto.bodySmall?.copyWith(color: AppColors.statusRed),
        errorMaxLines: 2,
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
        border: OutlineInputBorder(
          borderRadius: AppRadius.rLg,
          borderSide: BorderSide.none,
        ),
        // Un contorno muy suave, como la barra de búsqueda de los
        // tableros: el campo se distingue de la tarjeta blanca sin gritar.
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.rLg,
          borderSide: const BorderSide(color: AppColors.bordeSuave),
        ),
        // El foco sí se marca con una línea: sin borde, en un formulario
        // largo no hay forma de saber en qué campo se está escribiendo.
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.rLg,
          borderSide: const BorderSide(color: AppColors.azulVivo, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.rLg,
          borderSide: const BorderSide(color: AppColors.statusRed, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.rLg,
          borderSide: const BorderSide(color: AppColors.statusRed, width: 2),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.rLg,
          borderSide: BorderSide.none,
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: texto.bodyMedium,
        menuStyle: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(AppNeu.superficie),
          elevation: const WidgetStatePropertyAll(8),
          shadowColor: const WidgetStatePropertyAll(AppNeu.sombra),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.rLg),
          ),
        ),
      ),

      // ── Contenedores ──
      // Las tarjetas de la aplicación NO pasan por aquí: `main.dart`
      // importa Material con `hide Card` y usa la de `neu.dart`, que
      // dibuja el relieve de dos sombras que Material no sabe hacer.
      // Este tema cubre las tarjetas que crean los paquetes de terceros,
      // y está igualado para que no desentonen.
      cardTheme: CardThemeData(
        color: AppNeu.superficie,
        elevation: 4,
        shadowColor: AppNeu.sombra,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs + 2),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rLg),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rMd),
        iconColor: AppColors.textSecondary,
        titleTextStyle: texto.titleSmall,
        subtitleTextStyle: texto.bodySmall,
        minVerticalPadding: AppSpacing.sm,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: AppColors.royalBlue,
        collapsedIconColor: AppColors.textSecondary,
        textColor: AppColors.royalBlue,
        collapsedTextColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rSm),
        collapsedShape: RoundedRectangleBorder(borderRadius: AppRadius.rSm),
      ),
      // La línea divisoria se aclara casi hasta desaparecer: en
      // neomorfismo el corte entre bloques lo hace el aire, no una raya.
      dividerTheme: DividerThemeData(
        color: AppNeu.sombra.withValues(alpha: 0.35),
        space: 1,
        thickness: 1,
      ),

      // ── Diálogos y avisos ──
      dialogTheme: DialogThemeData(
        backgroundColor: AppNeu.superficie,
        elevation: 12,
        shadowColor: AppNeu.sombra,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rXl),
        titleTextStyle: texto.headlineSmall,
        contentTextStyle: texto.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: texto.bodyMedium?.copyWith(color: Colors.white),
        actionTextColor: AppColors.brandYellow,
        elevation: 8,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rLg),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppNeu.superficie,
        elevation: 12,
        shadowColor: AppNeu.sombra,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppNeu.sombra,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.textPrimary,
          borderRadius: AppRadius.rSm,
        ),
        textStyle: texto.bodySmall?.copyWith(color: Colors.white),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        waitDuration: const Duration(milliseconds: 400),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppNeu.superficie,
        elevation: 10,
        shadowColor: AppNeu.sombra,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.rLg),
        textStyle: texto.bodyMedium,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(AppNeu.superficie),
          elevation: const WidgetStatePropertyAll(10),
          shadowColor: const WidgetStatePropertyAll(AppNeu.sombra),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadius.rLg),
          ),
        ),
      ),

      // ── Navegación ──
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.royalBlue,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: texto.labelLarge,
        unselectedLabelStyle: texto.labelLarge?.copyWith(
            fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.azulVivo, width: 3),
          borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
        ),
        dividerColor: Colors.transparent,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppNeu.superficie,
        selectedItemColor: AppColors.royalBlue,
        unselectedItemColor: AppColors.textSecondary,
        selectedLabelStyle: texto.labelSmall?.copyWith(
            color: AppColors.royalBlue),
        unselectedLabelStyle: texto.labelSmall,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppNeu.superficie,
        selectedIconTheme: const IconThemeData(color: AppColors.royalBlue),
        unselectedIconTheme: const IconThemeData(color: AppColors.textSecondary),
        selectedLabelTextStyle: texto.labelMedium?.copyWith(
            color: AppColors.royalBlue),
        unselectedLabelTextStyle: texto.labelMedium,
        indicatorColor: AppColors.lilaTenue,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppNeu.superficie,
        elevation: 12,
        shadowColor: AppNeu.sombra,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(AppRadius.xl)),
        ),
      ),

      // ── Controles ──
      chipTheme: ChipThemeData(
        backgroundColor: AppNeu.superficie,
        selectedColor: AppColors.lilaTenue,
        labelStyle: texto.labelMedium,
        secondaryLabelStyle: texto.labelMedium,
        // Píldora blanca con contorno suave: los chips de contador de
        // los tableros («● Ventas 12 hoy»).
        side: const BorderSide(color: AppColors.bordeSuave),
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: Colors.transparent,
        checkmarkColor: AppColors.lila,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
        shape: const StadiumBorder(),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((estados) =>
            estados.contains(WidgetState.selected) ? Colors.white : Colors.white),
        // La pista apagada es el hueco; encendida, el azul de la marca.
        trackColor: WidgetStateProperty.resolveWith((estados) =>
            estados.contains(WidgetState.selected)
                ? AppColors.azulVivo
                : AppNeu.hueco),
        trackOutlineColor: WidgetStateProperty.resolveWith((estados) =>
            estados.contains(WidgetState.selected)
                ? AppColors.azulVivo
                : AppNeu.sombra),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((estados) =>
            estados.contains(WidgetState.selected)
                ? AppColors.azulVivo
                : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: AppColors.textSecondary, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((estados) =>
            estados.contains(WidgetState.selected)
                ? AppColors.royalBlue
                : AppColors.textSecondary),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.azulVivo,
        inactiveTrackColor: AppNeu.hueco,
        thumbColor: AppColors.azulVivo,
        overlayColor: Color(0x1A1F2270),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.azulVivo,
        linearTrackColor: AppNeu.hueco,
        circularTrackColor: AppNeu.hueco,
      ),

      // ── Datos ──
      dataTableTheme: DataTableThemeData(
        headingRowColor: const WidgetStatePropertyAll(AppNeu.hueco),
        headingTextStyle: texto.labelMedium?.copyWith(
            color: AppColors.textPrimary),
        dataTextStyle: texto.bodyMedium,
        dividerThickness: 1,
        horizontalMargin: AppSpacing.lg,
        columnSpacing: AppSpacing.xl,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
            AppColors.textSecondary.withValues(alpha: 0.35)),
        radius: const Radius.circular(AppRadius.full),
        thickness: const WidgetStatePropertyAll(6),
        // El indicador de desplazamiento siempre visible: en pantallas
        // con tablas largas, no saber que hay más contenido debajo es
        // una de las quejas más habituales.
        thumbVisibility: const WidgetStatePropertyAll(true),
      ),

      // ── Iconos y texto sueltos ──
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 22),
      primaryIconTheme: const IconThemeData(color: Colors.white, size: 22),
      dividerColor: AppColors.cardBorder,
    );
  }

  /// Envoltorio que aplica el límite de escalado de texto.
  ///
  /// Se coloca en `MaterialApp.builder`, así cubre toda la aplicación
  /// —incluidos los diálogos, que se dibujan fuera del árbol de la
  /// pantalla y por eso se quedan fuera si el ajuste se hace en el
  /// `Scaffold`—.
  static Widget escalarTexto(BuildContext context, Widget? hijo) {
    final medios = MediaQuery.of(context);
    return MediaQuery(
      data: medios.copyWith(
        textScaler: medios.textScaler.clamp(
          minScaleFactor: escalaTextoMinima,
          maxScaleFactor: escalaTextoMaxima,
        ),
      ),
      child: hijo ?? const SizedBox.shrink(),
    );
  }
}
