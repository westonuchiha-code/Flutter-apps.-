import 'package:material_ui/material_ui.dart';

/// Plain, flat studio-app styling: dark greys and one accent colour.
abstract final class Ui {
  static const bg = Color(0xFF121417);
  static const panel = Color(0xFF1A1D21);
  static const raised = Color(0xFF23272D);
  static const line = Color(0xFF2E333A);
  static const text = Color(0xFFE6E8EB);
  static const dim = Color(0xFF8A9099);
  static const accent = Color(0xFFFFA53D);
}

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Ui.accent,
        brightness: Brightness.dark,
      ).copyWith(
        primary: Ui.accent,
        onPrimary: const Color(0xFF1A1206),
        surface: Ui.panel,
        onSurface: Ui.text,
        secondaryContainer: Ui.raised,
        onSecondaryContainer: Ui.text,
        outline: Ui.line,
        outlineVariant: Ui.line,
      );
  return ThemeData(
    fontFamily: 'Roboto',
    colorScheme: scheme,
    scaffoldBackgroundColor: Ui.bg,
    dividerColor: Ui.line,
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      inactiveTrackColor: Ui.line,
      activeTrackColor: Ui.accent,
      thumbColor: Ui.text,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Ui.text,
      unselectedLabelColor: Ui.dim,
      indicatorColor: Ui.accent,
      dividerColor: Ui.line,
      labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 13),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13, fontFamily: 'Roboto'),
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: Ui.line)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? Ui.raised : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Ui.accent : Ui.dim,
        ),
      ),
    ),
  );
}
