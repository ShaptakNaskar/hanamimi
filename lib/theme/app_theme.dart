import 'package:flutter/material.dart';

import 'hanamimi_theme.dart';
import 'theme_tokens.dart';

const _nunito = 'Nunito';

/// Builds a Flutter [ThemeData] from a [HanamimiTheme].
abstract final class AppTheme {
  static ThemeData from(HanamimiTheme t) {
    final brightness = t.isDark ? Brightness.dark : Brightness.light;

    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final textTheme = base.textTheme.apply(
      fontFamily: _nunito,
      bodyColor: t.textPrimary,
      displayColor: t.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: _nunito,
      scaffoldBackgroundColor: t.background,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: t.primary,
        onPrimary: Colors.white,
        secondary: t.secondary,
        onSecondary: t.textPrimary,
        tertiary: t.accent,
        onTertiary: Colors.white,
        error: const Color(0xFFCF6679),
        onError: Colors.white,
        surface: t.surface,
        onSurface: t.textPrimary,
        onSurfaceVariant: t.textMuted,
        outline: t.divider,
      ),
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      dividerTheme: DividerThemeData(color: t.divider, thickness: 0.5),
      sliderTheme: SliderThemeData(
        activeTrackColor: t.primary,
        inactiveTrackColor: t.divider,
        thumbColor: Colors.white,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : t.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? t.primary : t.divider,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

TextStyle _n(double size, FontWeight weight, Color color,
        {double? height, double? letterSpacing, String family = _nunito}) =>
    TextStyle(
      fontFamily: family,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );

/// Text styles from the DESIGN.md type scale that don't map 1:1 onto
/// Material roles. Always pull from here, never inline sizes.
abstract final class AppText {
  static TextStyle hero(HanamimiTheme t) =>
      _n(TypeScale.hero, FontWeight.w800, t.textPrimary, height: 1.1);

  static TextStyle screenTitle(HanamimiTheme t) =>
      _n(TypeScale.screenTitle, FontWeight.w700, t.textPrimary, height: 1.1);

  static TextStyle npSongTitle(HanamimiTheme t) =>
      _n(TypeScale.npSongTitle, FontWeight.w700, t.textPrimary);

  static TextStyle npArtist(HanamimiTheme t) =>
      _n(TypeScale.npArtist, FontWeight.w400, t.textMuted);

  static TextStyle rowSongTitle(HanamimiTheme t) =>
      _n(TypeScale.rowSongTitle, FontWeight.w600, t.textPrimary);

  static TextStyle rowArtist(HanamimiTheme t) =>
      _n(TypeScale.rowArtist, FontWeight.w400, t.textMuted);

  static TextStyle sectionLabel(HanamimiTheme t) => _n(
      TypeScale.sectionLabel, FontWeight.w600, t.textMuted,
      letterSpacing: TypeScale.sectionLabel * 0.08);

  static TextStyle body(HanamimiTheme t) =>
      _n(TypeScale.body, FontWeight.w400, t.textPrimary, height: 1.65);

  static TextStyle activeLyric(HanamimiTheme t) =>
      _n(TypeScale.activeLyric, FontWeight.w600, t.textPrimary, height: 1.65);

  static TextStyle caption(HanamimiTheme t) =>
      _n(TypeScale.caption, FontWeight.w400, t.textMuted);

  static TextStyle timestamp(HanamimiTheme t) =>
      _n(TypeScale.timestamp, FontWeight.w400, t.textMuted,
          family: 'monospace');

  static TextStyle button(HanamimiTheme t) =>
      _n(TypeScale.button, FontWeight.w600, t.textPrimary);
}
