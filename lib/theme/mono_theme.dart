import 'package:flutter/material.dart';
import 'encorr_brand.dart';
import 'gapped_track_shape.dart';
import 'mono_tokens.dart';

ThemeData monoTheme({required bool dark, bool oled = false}) {
  final ({Color bg, Color surface, Color outline, Color text, Color textMuted, Color accent, Color accentSecondary}) c;
  if (oled) {
    c = (
      bg: EncorrBrand.oledBg,
      surface: EncorrBrand.oledSurface,
      outline: const Color(0x24FFFFFF),
      text: const Color(0xFFF5F5F7),
      textMuted: const Color(0x99F5F5F7),
      accent: EncorrBrand.orange,
      accentSecondary: EncorrBrand.magenta,
    );
  } else if (dark) {
    c = (
      bg: EncorrBrand.darkBg,
      surface: EncorrBrand.darkSurface,
      outline: const Color(0x24FFFFFF),
      text: const Color(0xFFF5F5F7),
      textMuted: const Color(0x99F5F5F7),
      accent: EncorrBrand.orange,
      accentSecondary: EncorrBrand.magenta,
    );
  } else {
    c = (
      bg: EncorrBrand.lightBg,
      surface: EncorrBrand.lightSurface,
      outline: const Color(0x19000000),
      text: const Color(0xFF111018),
      textMuted: const Color(0x99111018),
      accent: EncorrBrand.orange,
      accentSecondary: EncorrBrand.magenta,
    );
  }

  final isDark = dark || oled;

  final glassSurface = oled
      ? const Color(0x990A0810)
      : dark
      ? const Color(0x9912101A)
      : const Color(0xB3FFFFFF);
  final glassBorder = isDark ? const Color(0x33FFFFFF) : const Color(0x14000000);
  final scrimStrong = isDark ? const Color(0xCC000000) : const Color(0x8C000000);
  const scrimSoft = Color(0x00000000);
  final clickableCursor = WidgetStateProperty.resolveWith<MouseCursor>(
    (states) => states.contains(WidgetState.disabled) ? MouseCursor.defer : SystemMouseCursors.click,
  );

  final buttonStyle = ButtonStyle(
    mouseCursor: clickableCursor,
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
    elevation: const WidgetStatePropertyAll(0),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return c.text.withValues(alpha: 0.18);
      return c.accent;
    }),
    foregroundColor: const WidgetStatePropertyAll(Colors.white),
    overlayColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.12)),
    shape: const WidgetStatePropertyAll(StadiumBorder()),
  );

  final outlinedButtonStyle = ButtonStyle(
    mouseCursor: clickableCursor,
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 14)),
    foregroundColor: WidgetStatePropertyAll(c.text),
    side: WidgetStateProperty.resolveWith((states) {
      final color = states.contains(WidgetState.focused) ? c.accent : c.outline;
      return BorderSide(color: color, width: states.contains(WidgetState.focused) ? 1.5 : 1);
    }),
    shape: const WidgetStatePropertyAll(StadiumBorder()),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: isDark ? Brightness.dark : Brightness.light,
    colorScheme: ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: c.accent,
      onPrimary: Colors.white,
      secondary: c.accentSecondary,
      onSecondary: Colors.white,
      surface: c.surface,
      onSurface: c.text,
      error: const Color(0xFFFF4D6D),
      onError: Colors.white,
      tertiary: EncorrBrand.purple,
      onTertiary: Colors.white,
      primaryContainer: c.accent.withValues(alpha: isDark ? 0.18 : 0.12),
      onPrimaryContainer: c.text,
      secondaryContainer: c.accentSecondary.withValues(alpha: isDark ? 0.16 : 0.1),
      onSecondaryContainer: c.text,
      surfaceContainerHighest: c.surface,
      surfaceContainerLow: c.bg,
      surfaceDim: c.bg,
      surfaceBright: c.surface,
      outline: c.outline,
      shadow: Colors.transparent,
      scrim: Colors.black,
      inverseSurface: c.text,
      onInverseSurface: c.bg,
      inversePrimary: c.bg,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: c.outline,
    scaffoldBackgroundColor: c.bg,
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent, linearTrackColor: c.outline),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: c.text,
      titleTextStyle: TextStyle(
        color: c.text,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
      ),
    ),
    textTheme: Typography.englishLike2021
        .apply(bodyColor: c.text, displayColor: c.text)
        .copyWith(
          displayLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2, color: c.text),
          displaySmall: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8, color: c.text),
          headlineMedium: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.text),
          titleLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.4, color: c.text),
          titleMedium: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2, color: c.text),
          bodyMedium: TextStyle(color: c.text),
          bodySmall: TextStyle(color: c.textMuted),
          labelLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.4, color: c.text),
        ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    inputDecorationTheme: _inputDecorationTheme(c.text, c.textMuted, c.accent),
    elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        mouseCursor: clickableCursor,
        foregroundColor: WidgetStatePropertyAll(c.accent),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: outlinedButtonStyle),
    iconButtonTheme: IconButtonThemeData(style: ButtonStyle(mouseCursor: clickableCursor)),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.accent,
      inactiveTrackColor: c.outline,
      thumbColor: c.accent,
      overlayColor: c.accent.withValues(alpha: 0.12),
      trackHeight: 16,
      trackGap: 6,
      thumbSize: const WidgetStatePropertyAll(Size(4, 20)),
      thumbShape: const HandleThumbShape(),
      trackShape: const GappedTrackShape(),
      tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
      // ignore: deprecated_member_use — opting into the 2024 slider appearance until the default flips
      year2023: false,
    ),
    dividerTheme: DividerThemeData(space: 0, thickness: 1, color: c.outline),
    listTileTheme: ListTileThemeData(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      iconColor: c.text,
      textColor: c.text,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.bg,
      elevation: 0,
      indicatorColor: c.accent.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final active = states.contains(WidgetState.selected);
        return TextStyle(
          color: active ? c.accent : c.textMuted,
          fontSize: 11,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final active = states.contains(WidgetState.selected);
        return IconThemeData(opacity: active ? 1 : 0.6, size: 22, color: active ? c.accent : c.text);
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surface,
      contentTextStyle: TextStyle(color: c.text),
      actionTextColor: c.accent,
      elevation: 6,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
      insetPadding: const EdgeInsets.all(16),
    ),
  );

  return base.copyWith(
    extensions: [
      MonoTokens(
        radiusSm: 10,
        radiusMd: 14,
        space: 12,
        fast: const Duration(milliseconds: 120),
        normal: const Duration(milliseconds: 200),
        slow: const Duration(milliseconds: 300),
        bg: c.bg,
        surface: c.surface,
        outline: c.outline,
        text: c.text,
        textMuted: c.textMuted,
        accent: c.accent,
        accentSecondary: c.accentSecondary,
        splashFactory: NoSplash.splashFactory,
        glassSurface: glassSurface,
        glassBlurSigma: 20,
        glassBorder: glassBorder,
        scrimStrong: scrimStrong,
        scrimSoft: scrimSoft,
      ),
    ],
  );
}

InputDecorationTheme _inputDecorationTheme(Color text, Color textMuted, Color accent) {
  final unfocusedFill = text.withValues(alpha: 0.08);
  final focusedFill = accent.withValues(alpha: 0.12);
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none);
  final focusedBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: accent.withValues(alpha: 0.55), width: 1.5),
  );
  return InputDecorationTheme(
    filled: true,
    fillColor: WidgetStateColor.resolveWith(
      (states) => states.contains(WidgetState.focused) ? focusedFill : unfocusedFill,
    ),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: border,
    enabledBorder: border,
    focusedBorder: focusedBorder,
    hintStyle: TextStyle(color: textMuted),
  );
}
