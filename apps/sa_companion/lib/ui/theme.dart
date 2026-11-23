import 'package:material_ui/material_ui.dart';

/// Colours from the original design: a pause menu / HUD look with black
/// glass panels, gold selection, money green and health red.
abstract final class SaColors {
  static const bg = Color(0xFF0A0C0B);
  static const p1 = Color(0xFF171C19);
  static const p2 = Color(0xFF121614);
  static const line = Color(0xFF2A332F);
  static const line2 = Color(0xFF3A4640);
  static const ink = Color(0xFFF4F1E8);
  static const dim = Color(0xFF98A39D);
  static const body = Color(0xFFDDD6C4);
  static const gold = Color(0xFFF3B93A);
  static const goldDark = Color(0xFFC88B17);
  static const money = Color(0xFF5FCF5A);
  static const grove = Color(0xFF2F8F3A);
  static const red = Color(0xFFD03232);
  static const redDark = Color(0xFF8F1B1B);
  static const field = Color(0xFF0D100F);

  /// Story chapter colours.
  static const regions = {
    'Los Santos': Color(0xFF3F9F45),
    'Badlands': Color(0xFFC27A2C),
    'San Fierro': Color(0xFF4F93BD),
    'Desert': Color(0xFFD8B23F),
    'Las Venturas': Color(0xFFD94A9C),
    'Return to Los Santos': Color(0xFF8C63CC),
    // Place areas.
    'Countryside': Color(0xFFC27A2C),
  };

  static Color region(String name) => regions[name] ?? const Color(0xFF999999);
}

abstract final class SaFonts {
  static const display = 'BowlbyOne';
  static const condensed = 'BarlowCondensed';
  static const body = 'Barlow';
}

/// Condensed upper-case label style used for small headings.
TextStyle condensed({
  double size = 13,
  Color color = SaColors.dim,
  FontWeight weight = FontWeight.w700,
  double spacing = 1.3,
}) => TextStyle(
  fontFamily: SaFonts.condensed,
  fontWeight: weight,
  fontSize: size,
  letterSpacing: spacing,
  color: color,
);

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: SaColors.bg,
    fontFamily: SaFonts.body,
    colorScheme: const ColorScheme.dark(
      primary: SaColors.gold,
      onPrimary: Color(0xFF1A1203),
      secondary: SaColors.money,
      surface: SaColors.p1,
      onSurface: SaColors.ink,
      error: SaColors.red,
    ),
    splashFactory: InkRipple.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: SaColors.ink,
      displayColor: SaColors.ink,
      fontFamily: SaFonts.body,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: SaColors.gold,
      selectionColor: Color(0x66F3B93A),
      selectionHandleColor: SaColors.gold,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: SaColors.p1,
      contentTextStyle: TextStyle(color: SaColors.ink, fontSize: 15),
    ),
  );
}
