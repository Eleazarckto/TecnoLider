import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sistema de diseño profesional para YJ Delivery
/// Filosofía: logística refinada — tipografía editorial, paleta disciplinada,
/// espaciado generoso, micro-detalles cuidados.
class DS {
  DS._();

  // ============ COLOR TOKENS ============
  // Neutrals (the foundation - 90% of the UI)
  static const ink = Color(0xFF0F1419);          // primary text, headers
  static const inkSecondary = Color(0xFF4A5560); // body text
  static const inkMuted = Color(0xFF8693A1);     // secondary, captions
  static const inkSubtle = Color(0xFFB5BFCB);    // disabled, dividers

  static const surface = Color(0xFFFAFAF7);      // page background (warm off-white)
  static const surfaceRaised = Color(0xFFFFFFFF); // cards
  static const surfaceMuted = Color(0xFFF1EFE9);  // input backgrounds, hover
  static const border = Color(0xFFE6E2D8);        // borders (warm)
  static const borderStrong = Color(0xFFD3CDBE);

  // Brand accents (use sparingly - status, calls to action)
  static const brandOrange = Color(0xFFEF9F27);
  static const brandOrangeDeep = Color(0xFFC97F0E);
  static const brandBlue = Color(0xFF2563B5);
  static const brandBlueDeep = Color(0xFF154283);

  // Semantic colors (status badges, alerts)
  static const success = Color(0xFF0E7A5F);
  static const successBg = Color(0xFFE8F4EE);
  static const warning = Color(0xFF9A6411);
  static const warningBg = Color(0xFFFAF1DD);
  static const danger = Color(0xFFA93030);
  static const dangerBg = Color(0xFFFAE8E8);
  static const info = Color(0xFF2563B5);
  static const infoBg = Color(0xFFE5EEF8);
  static const accent = Color(0xFF5B4FBC);
  static const accentBg = Color(0xFFEEEBF8);

  // Dark surface (login, header)
  static const dark = Color(0xFF12161C);
  static const darkRaised = Color(0xFF1B2027);
  static const darkBorder = Color(0xFF2A3038);

  // ============ SPACING (4px base) ============
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space5 = 20.0;
  static const space6 = 24.0;
  static const space8 = 32.0;
  static const space10 = 40.0;
  static const space12 = 48.0;
  static const space16 = 64.0;

  // ============ RADIUS ============
  static const radiusSm = 6.0;
  static const radiusMd = 10.0;
  static const radiusLg = 14.0;
  static const radiusXl = 20.0;

  // ============ ELEVATION (subtle, layered) ============
  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: ink.withValues(alpha: 0.04),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: ink.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: ink.withValues(alpha: 0.03),
          blurRadius: 1,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get shadowLg => [
        BoxShadow(
          color: ink.withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: ink.withValues(alpha: 0.04),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  // ============ TYPOGRAPHY ============
  // Fraunces: distinctive editorial serif for display
  // Inter: refined sans-serif for UI/data, with tabular numbers

  static TextStyle display(double size, {Color? color, FontWeight? weight}) {
    return GoogleFonts.fraunces(
      fontSize: size,
      fontWeight: weight ?? FontWeight.w500,
      color: color ?? ink,
      letterSpacing: -0.02 * size,
      height: 1.1,
    );
  }

  static TextStyle ui(double size,
      {Color? color, FontWeight? weight, double? height, double? spacing}) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight ?? FontWeight.w400,
      color: color ?? ink,
      letterSpacing: spacing ?? 0,
      height: height ?? 1.4,
    );
  }

  /// For monetary values & numbers - uses tabular figures (aligned digits)
  static TextStyle numeric(double size,
      {Color? color, FontWeight? weight}) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight ?? FontWeight.w500,
      color: color ?? ink,
      letterSpacing: -0.005 * size,
      fontFeatures: const [FontFeature.tabularFigures()],
      height: 1.2,
    );
  }

  /// All-caps eyebrow labels (KPI headers, section markers)
  static TextStyle eyebrow({Color? color}) {
    return GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: color ?? inkMuted,
      letterSpacing: 1.2,
    );
  }

  // ============ THEME ============
  static ThemeData buildTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: surface,
      colorScheme: const ColorScheme.light(
        primary: ink,
        onPrimary: Colors.white,
        secondary: brandOrange,
        onSecondary: Colors.white,
        surface: surfaceRaised,
        onSurface: ink,
        error: danger,
        onError: Colors.white,
      ),
      textTheme: GoogleFonts.interTextTheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: dark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: ui(15, color: Colors.white, weight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceRaised,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: space4, vertical: 14),
        hintStyle: ui(14, color: inkSubtle),
        labelStyle: ui(13, color: inkSecondary, weight: FontWeight.w500),
        floatingLabelStyle: ui(13, color: ink, weight: FontWeight.w600),
        prefixIconColor: inkMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: ink, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: danger, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
        errorStyle: ui(12, color: danger),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (s.contains(WidgetState.disabled)) return inkSubtle;
            if (s.contains(WidgetState.hovered)) return const Color(0xFF1B2027);
            return ink;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          elevation: const WidgetStatePropertyAll(0),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: space5, vertical: 14)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd))),
          textStyle: WidgetStatePropertyAll(
              ui(14, weight: FontWeight.w600, color: Colors.white)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(ink),
          side: const WidgetStatePropertyAll(
              BorderSide(color: borderStrong, width: 1)),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: space5, vertical: 13)),
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusMd))),
          textStyle:
              WidgetStatePropertyAll(ui(14, weight: FontWeight.w600)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(ink),
          textStyle: WidgetStatePropertyAll(ui(14, weight: FontWeight.w500)),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: ink,
        unselectedLabelColor: inkMuted,
        labelStyle: ui(13, weight: FontWeight.w600),
        unselectedLabelStyle: ui(13, weight: FontWeight.w500),
        indicatorColor: brandOrange,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: border,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        contentTextStyle: ui(13, color: Colors.white, weight: FontWeight.w500),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceRaised,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surfaceRaised,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusXl)),
        ),
      ),
    );
  }
}
