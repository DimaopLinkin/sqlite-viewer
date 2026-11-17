import 'package:flutter/material.dart';

/// Colors used by the viewer chrome that `ColorScheme` does not cover.
@immutable
class ViewerColors extends ThemeExtension<ViewerColors> {
  const ViewerColors({
    required this.sidebar,
    required this.toolbar,
    required this.header,
    required this.gridLine,
    required this.rowAlt,
    required this.rowHover,
    required this.selection,
    required this.muted,
    required this.nullValue,
    required this.number,
    required this.input,
    required this.dialog,
  });

  final Color sidebar;
  final Color toolbar;
  final Color header;
  final Color gridLine;
  final Color rowAlt;
  final Color rowHover;
  final Color selection;
  final Color muted;
  final Color nullValue;
  final Color number;
  final Color input;

  /// Background of the row dialog, kept darker (lighter in the light theme)
  /// than [input] so the value fields stand out.
  final Color dialog;

  static const dark = ViewerColors(
    sidebar: Color(0xFF181818),
    toolbar: Color(0xFF1F1F1F),
    header: Color(0xFF1F1F1F),
    gridLine: Color(0xFF2B2B2B),
    rowAlt: Color(0xFF1C1C1C),
    rowHover: Color(0xFF2A2D2E),
    selection: Color(0xFF04395E),
    muted: Color(0xFF8B8B8B),
    nullValue: Color(0xFF6B6B6B),
    number: Color(0xFFB5CEA8),
    input: Color(0xFF2D2D2D),
    dialog: Color(0xFF141414),
  );

  static const light = ViewerColors(
    sidebar: Color(0xFFF3F3F3),
    toolbar: Color(0xFFF8F8F8),
    header: Color(0xFFF3F3F3),
    gridLine: Color(0xFFE2E2E2),
    rowAlt: Color(0xFFFAFAFA),
    rowHover: Color(0xFFE8F0FB),
    selection: Color(0xFFCCE4FA),
    muted: Color(0xFF6F6F6F),
    nullValue: Color(0xFFA0A0A0),
    number: Color(0xFF098658),
    input: Color(0xFFFFFFFF),
    dialog: Color(0xFFEBEBEB),
  );

  static ViewerColors of(BuildContext context) =>
      Theme.of(context).extension<ViewerColors>()!;

  @override
  ViewerColors copyWith() => this;

  @override
  ViewerColors lerp(ViewerColors? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors = dark ? ViewerColors.dark : ViewerColors.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF0078D4),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFF3794FF) : const Color(0xFF005FB8),
        surface: dark ? const Color(0xFF1E1E1E) : Colors.white,
        onSurface: dark ? const Color(0xFFCCCCCC) : const Color(0xFF1F1F1F),
        outlineVariant: colors.gridLine,
      );
  return ThemeData(
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.compact,
    extensions: [colors],
    dividerTheme: DividerThemeData(color: colors.gridLine, space: 1),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: colors.input,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      hintStyle: TextStyle(color: colors.muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(color: colors.gridLine),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(color: colors.gridLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(3),
        borderSide: BorderSide(color: scheme.primary),
      ),
    ),
  );
}
