import 'package:flutter/material.dart';

/// Actra's palette. Screens use these names, never raw colour values.
abstract final class AppColors {
  static const primary = Color(0xFF10B560);
  static const primaryDark = Color(0xFF0A8A49);
  static const primarySoft = Color(0xFFE2F7EB);
  static const ink = Color(0xFF1D2A2F);
  static const muted = Color(0xFF6B7A80);
  static const faint = Color(0xFFA3AEB2);
  static const page = Color(0xFFF1F3F2);
  static const card = Colors.white;
  static const line = Color(0xFFE5EAE8);
  static const field = Color(0xFFEDF1EF);
  static const blue = Color(0xFF1F6BFF);
  static const amber = Color(0xFFFFB020);
  static const amberSoft = Color(0xFFFFF1D1);
  static const lime = Color(0xFFC8F542);
  static const error = Color(0xFFE5484D);
  static const errorSoft = Color(0xFFFDE8E8);
}

/// Manrope at an explicit weight.
///
/// The font file is variable, so the weight is set on the `wght` axis as well
/// as through [FontWeight]; that keeps it correct on every platform.
TextStyle manrope(
  double size,
  int weight, {
  Color color = AppColors.ink,
  double? height,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: 'Manrope',
  fontSize: size,
  fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
  fontVariations: [FontVariation('wght', weight.toDouble())],
  color: color,
  height: height,
  letterSpacing: letterSpacing,
);

/// Named text styles, so the type scale stays the same on every screen.
abstract final class AppText {
  static final greeting = manrope(21, 800, height: 1.15);
  static final title = manrope(22, 800, height: 1.2);
  static final sectionTitle = manrope(14, 800, letterSpacing: 0.5);
  static final cardTitle = manrope(17, 800, height: 1.25);
  static final body = manrope(14, 500, height: 1.4);
  static final bodyStrong = manrope(14, 700, height: 1.4);
  static final muted = manrope(13.5, 500, color: AppColors.muted, height: 1.35);
  static final caption = manrope(12, 600, color: AppColors.muted);
  static final button = manrope(15, 800, letterSpacing: 0.2);
}

const _radius = 20.0;

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    primaryContainer: AppColors.primarySoft,
    onPrimaryContainer: AppColors.primaryDark,
    secondaryContainer: AppColors.field,
    onSecondaryContainer: AppColors.ink,
    tertiaryContainer: AppColors.amberSoft,
    onTertiaryContainer: const Color(0xFF7A4B00),
    error: AppColors.error,
    errorContainer: AppColors.errorSoft,
    onErrorContainer: const Color(0xFFA1272B),
    surface: AppColors.page,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.muted,
    surfaceContainerLowest: AppColors.card,
    surfaceContainerLow: AppColors.card,
    surfaceContainer: AppColors.card,
    surfaceContainerHigh: AppColors.card,
    surfaceContainerHighest: AppColors.field,
    outline: AppColors.faint,
    outlineVariant: AppColors.line,
  );

  final text = TextTheme(
    headlineMedium: manrope(26, 800, height: 1.2),
    headlineSmall: manrope(22, 800, height: 1.2),
    titleLarge: manrope(19, 800, height: 1.25),
    titleMedium: manrope(16, 700, height: 1.3),
    titleSmall: manrope(14, 700),
    bodyLarge: manrope(15, 500, height: 1.45),
    bodyMedium: manrope(14, 500, height: 1.4),
    bodySmall: manrope(12.5, 500, color: AppColors.muted),
    labelLarge: manrope(14.5, 700),
    labelMedium: manrope(12, 700),
    labelSmall: manrope(11, 700),
  );

  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Manrope',
    textTheme: text,
    scaffoldBackgroundColor: AppColors.page,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: AppColors.page,
      foregroundColor: AppColors.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: manrope(19, 800),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: AppColors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: buttonShape,
        textStyle: AppText.button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: buttonShape,
        side: const BorderSide(color: AppColors.line, width: 1.5),
        foregroundColor: AppColors.ink,
        textStyle: AppText.button,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(textStyle: manrope(14, 700), foregroundColor: AppColors.primaryDark),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.card,
      hintStyle: manrope(15, 500, color: AppColors.muted),
      labelStyle: manrope(15, 500, color: AppColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.card,
      selectedColor: AppColors.primarySoft,
      side: const BorderSide(color: AppColors.line),
      labelStyle: manrope(13.5, 700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: manrope(19, 800),
      contentTextStyle: manrope(14.5, 500, color: AppColors.muted, height: 1.45),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: manrope(14, 600, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: AppColors.ink,
      titleTextStyle: manrope(15.5, 700),
      subtitleTextStyle: manrope(13.5, 500, color: AppColors.muted),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.field,
    ),
  );
}

/// Soft colour pair for an avatar or tile, chosen from a name so it is stable.
({Color background, Color foreground}) tintFor(String seed) {
  const hues = [150.0, 215.0, 28.0, 280.0, 190.0, 340.0, 48.0];
  final hue = hues[seed.runes.fold(0, (a, b) => a + b) % hues.length];
  return (
    background: HSLColor.fromAHSL(1, hue, 0.70, 0.90).toColor(),
    foreground: HSLColor.fromAHSL(1, hue, 0.55, 0.30).toColor(),
  );
}
