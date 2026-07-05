import 'package:flutter/material.dart';

import 'hanamimi_theme.dart';

/// Theme 1 — Cherry Blossom (default). Spring afternoon.
const cherryBlossom = HanamimiTheme(
  id: 'cherry_blossom',
  name: 'Cherry Blossom',
  emoji: '🌸',
  background: Color(0xFFFFF5F7),
  surface: Color(0xFFFFFFFF),
  primary: Color(0xFFF4A7B9),
  secondary: Color(0xFFD4A5E8),
  accent: Color(0xFFFF8FAB),
  textPrimary: Color(0xFF4A3040),
  textMuted: Color(0xFF9A7080),
  divider: Color(0xFFF2D8E0),
  visualizerStyle: VisualizerStyle.bars,
  brightness: HanamimiBrightness.light,
);

/// Theme 2 — Rainy Day. Quiet grey afternoon indoors.
const rainyDay = HanamimiTheme(
  id: 'rainy_day',
  name: 'Rainy Day',
  emoji: '🌧️',
  background: Color(0xFFEFF4F9),
  surface: Color(0xFFF8FAFC),
  primary: Color(0xFF7EB8D4),
  secondary: Color(0xFFA8C5D8),
  accent: Color(0xFF4D9EC5),
  textPrimary: Color(0xFF2A3D50),
  textMuted: Color(0xFF6A8599),
  divider: Color(0xFFD0E2ED),
  visualizerStyle: VisualizerStyle.raindrops,
  brightness: HanamimiBrightness.light,
);

/// Theme 3 — Starry Night. Late night; the only dark theme.
const starryNight = HanamimiTheme(
  id: 'starry_night',
  name: 'Starry Night',
  emoji: '🌙',
  background: Color(0xFF1A1A2E),
  surface: Color(0xFF232344),
  primary: Color(0xFFC3A6FF),
  secondary: Color(0xFF7EC8E3),
  accent: Color(0xFFFFD580),
  textPrimary: Color(0xFFE8E8FF),
  textMuted: Color(0xFF8888BB),
  divider: Color(0xFF2E2E50),
  // Uses the Cherry Blossom bars, recoloured night (its own lavender→cyan
  // on the dark background) instead of the radial burst.
  visualizerStyle: VisualizerStyle.bars,
  brightness: HanamimiBrightness.dark,
);

/// Theme 4 — Matcha. Tea house in the morning.
const matcha = HanamimiTheme(
  id: 'matcha',
  name: 'Matcha',
  emoji: '🍵',
  background: Color(0xFFF2F6EE),
  surface: Color(0xFFFAFCF7),
  primary: Color(0xFF7DB87D),
  secondary: Color(0xFFB5D49A),
  accent: Color(0xFF4A7C59),
  textPrimary: Color(0xFF1E3020),
  textMuted: Color(0xFF6A8C6A),
  divider: Color(0xFFD4E4CC),
  visualizerStyle: VisualizerStyle.wave,
  brightness: HanamimiBrightness.light,
);

/// Theme 5 — Adaptive (Monet). Its palette is pulled from the current
/// track's album art at runtime (see adaptive_theme_provider). These are
/// only the placeholder/neutral values shown before any art resolves;
/// [fromArtScheme] overrides them per track.
const adaptive = neutralAdaptive;

/// Soft grey-pink fallback for the Adaptive theme when there's no art (or
/// extraction hasn't finished / failed) — never a jarring default.
const neutralAdaptive = HanamimiTheme(
  id: 'adaptive',
  name: 'Adaptive',
  emoji: '🎨',
  background: Color(0xFFF6F2F4),
  surface: Color(0xFFFFFFFF),
  primary: Color(0xFFB79AAE),
  secondary: Color(0xFFC9A9C4),
  accent: Color(0xFF9E7C96),
  textPrimary: Color(0xFF3A303A),
  textMuted: Color(0xFF8A7A88),
  divider: Color(0xFFE6DCE2),
  visualizerStyle: VisualizerStyle.bars,
  brightness: HanamimiBrightness.light,
);

/// Builds an Adaptive theme from a Material You [ColorScheme] extracted
/// from album art. Follows the scheme's own brightness, so a dark cover
/// yields a dark, readable UI.
HanamimiTheme fromArtScheme(ColorScheme s) => HanamimiTheme(
      id: 'adaptive',
      name: 'Adaptive',
      emoji: '🎨',
      background: s.surface,
      surface: s.surfaceContainerHigh,
      primary: s.primary,
      secondary: s.tertiary, // second bar colour / lerp target
      accent: s.secondary,
      textPrimary: s.onSurface,
      textMuted: s.onSurfaceVariant,
      divider: s.outlineVariant,
      visualizerStyle: VisualizerStyle.bars,
      brightness: s.brightness == Brightness.dark
          ? HanamimiBrightness.dark
          : HanamimiBrightness.light,
    );

/// Adaptive replaces Rainy Day in the picker (it took the "ocean" slot).
const allThemes = [cherryBlossom, adaptive, starryNight, matcha];

HanamimiTheme themeById(String id) {
  // Rainy Day was retired for Adaptive — anyone still on it lands on the
  // default rather than a missing theme.
  if (id == 'rainy_day') return cherryBlossom;
  return allThemes.firstWhere((t) => t.id == id, orElse: () => cherryBlossom);
}
