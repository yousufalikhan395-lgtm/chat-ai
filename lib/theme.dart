import 'package:flutter/material.dart';

/// Design tokens ported from the "Still" landing-page design (nice.html):
/// deep forest background, sage surfaces, warm cream text, pale-lime accent.
class AppColors {
  static const bg = Color(0xFF101711);
  static const surface = Color(0xFF19221B);
  static const surface2 = Color(0xFF243F31);
  static const text = Color(0xFFF3F0E7);
  static const muted = Color(0xFFADB5A6);
  static const accent = Color(0xFFD5ED9C);
  static const onAccent = Color(0xFF101711);
  static const line = Color(0x24F3F0E7); // rgba(243,240,231,.14)
  static const accentSoft = Color(0x1FD5ED9C); // ~12% lime wash
  static const accentGlow = Color(0x66D5ED9C);
}

/// Uppercased, letter-spaced eyebrow label (the `.eyebrow` style).
TextStyle eyebrowStyle(BuildContext context, {Color? color}) => TextStyle(
      fontFamily: 'Inter',
      fontSize: 11,
      height: 1.4,
      fontWeight: FontWeight.w500,
      letterSpacing: 2,
      color: color ?? AppColors.accent,
    );

/// Instrument Serif italic — stands in for the `<em>` accent words.
const TextStyle serifEm = TextStyle(
  fontFamily: 'InstrumentSerif',
  fontStyle: FontStyle.italic,
  fontWeight: FontWeight.w400,
  color: AppColors.accent,
);

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    secondary: AppColors.surface2,
    onSecondary: AppColors.text,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    onSurfaceVariant: AppColors.muted,
    outline: AppColors.muted,
    error: Color(0xFFFFB4A2),
    onError: AppColors.onAccent,
  );

  final textTheme = const TextTheme(
    displaySmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 46,
        height: 1.02,
        letterSpacing: -1.8,
        fontWeight: FontWeight.w500,
        color: AppColors.text),
    headlineSmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 24,
        height: 1.2,
        letterSpacing: -0.7,
        fontWeight: FontWeight.w600,
        color: AppColors.text),
    titleLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 17,
        letterSpacing: -0.3,
        fontWeight: FontWeight.w600,
        color: AppColors.text),
    titleMedium: TextStyle(
        fontFamily: 'Inter',
        fontSize: 15,
        letterSpacing: -0.2,
        fontWeight: FontWeight.w500,
        color: AppColors.text),
    bodyLarge: TextStyle(
        fontFamily: 'Inter', fontSize: 16, height: 1.55, color: AppColors.text),
    bodyMedium: TextStyle(
        fontFamily: 'Inter', fontSize: 14.5, height: 1.5, color: AppColors.text),
    bodySmall: TextStyle(
        fontFamily: 'Inter', fontSize: 13, height: 1.45, color: AppColors.muted),
    labelLarge: TextStyle(
        fontFamily: 'Inter',
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: AppColors.text),
    labelSmall: TextStyle(
        fontFamily: 'Inter',
        fontSize: 10.5,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.6,
        color: AppColors.muted),
  ).apply(bodyColor: AppColors.text, displayColor: AppColors.text);

  const inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(24)),
    borderSide: BorderSide(color: AppColors.line),
  );
  const inputBorderFocused = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(24)),
    borderSide: BorderSide(color: AppColors.accent, width: 1.4),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Inter',
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    splashFactory: InkSparkle.splashFactory,
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: AppColors.muted, size: 22),
      titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 17,
          letterSpacing: -0.3,
          fontWeight: FontWeight.w600,
          color: AppColors.text),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surface2,
      contentTextStyle: textTheme.bodyMedium?.copyWith(fontSize: 14),
      actionTextColor: AppColors.accent,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.line),
      ),
      textStyle: textTheme.bodyMedium,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      showDragHandle: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.line),
      ),
      titleTextStyle: textTheme.headlineSmall?.copyWith(fontSize: 19),
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: AppColors.muted),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: AppColors.text,
      iconColor: AppColors.muted,
      contentPadding: EdgeInsets.symmetric(horizontal: 20),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface2,
      hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorderFocused,
      errorBorder: inputBorder,
      focusedErrorBorder: inputBorder,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        disabledBackgroundColor: AppColors.accentSoft,
        disabledForegroundColor: AppColors.muted,
        textStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        side: BorderSide.none,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        textStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.line),
        textStyle: textTheme.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: AppColors.muted),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith<Color?>((states) =>
          states.contains(WidgetState.selected) ? AppColors.accent : Colors.transparent),
      checkColor: WidgetStatePropertyAll(AppColors.onAccent),
      side: const BorderSide(color: AppColors.muted),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith<Color?>((states) =>
          states.contains(WidgetState.selected) ? AppColors.onAccent : AppColors.muted),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? AppColors.accent : AppColors.surface2),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.accent,
      selectionColor: AppColors.accentGlow,
      selectionHandleColor: AppColors.accent,
    ),
  );
}
