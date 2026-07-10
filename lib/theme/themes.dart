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

/// Theme 3 — Starry Night. Late night.
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

/// Themes 2 & 4 — Adaptive Light / Adaptive Dark (Monet). Their palettes
/// are pulled from the current track's album art at runtime
/// (see adaptive_theme_provider), each pinned to its own brightness so the
/// user picks light or dark and the art only supplies the colours. These
/// consts are the placeholder/neutral values shown before any art
/// resolves; [fromArtScheme] overrides them per track.
const adaptiveLight = neutralAdaptiveLight;
const adaptiveDark = neutralAdaptiveDark;

/// Soft grey-pink fallback for Adaptive Light when there's no art (or
/// extraction hasn't finished / failed) — never a jarring default.
const neutralAdaptiveLight = HanamimiTheme(
  id: 'adaptive_light',
  name: 'Adaptive Light',
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

/// Dusky grey-mauve fallback for Adaptive Dark, same role as
/// [neutralAdaptiveLight].
const neutralAdaptiveDark = HanamimiTheme(
  id: 'adaptive_dark',
  name: 'Adaptive Dark',
  emoji: '🌌',
  background: Color(0xFF201B20),
  surface: Color(0xFF2C252C),
  primary: Color(0xFFC9A9C4),
  secondary: Color(0xFFB79AAE),
  accent: Color(0xFFD9BAD2),
  textPrimary: Color(0xFFEDE4EA),
  textMuted: Color(0xFFA898A4),
  divider: Color(0xFF3C333C),
  visualizerStyle: VisualizerStyle.bars,
  brightness: HanamimiBrightness.dark,
);

/// Theme 5 — Adaptive AMOLED. Pitch-black canvas, art-derived jewelry.
/// The neutral slots (background/surface/text/divider) are pinned — pure
/// black stays pure black on every track — and only primary/secondary/
/// accent follow the album art. These consts double as the no-art
/// fallback, same role as [neutralAdaptiveDark].
const neutralAdaptiveAmoled = HanamimiTheme(
  id: 'adaptive_amoled',
  name: 'Adaptive AMOLED',
  emoji: '🖤',
  background: Color(0xFF000000),
  // Cards need a ~5% lift off true black or the layout dissolves;
  // shadows are invisible here, so this + the hairline divider carry
  // all the separation.
  surface: Color(0xFF0E0D0F),
  primary: Color(0xFFC9A9C4),
  secondary: Color(0xFFB79AAE),
  accent: Color(0xFFD9BAD2),
  // Not pure white — #FFF on #000 halates/smears on OLED panels.
  textPrimary: Color(0xFFEDEDED),
  textMuted: Color(0xFF8F8A93),
  divider: Color(0xFF1C1B1E),
  visualizerStyle: VisualizerStyle.bars,
  brightness: HanamimiBrightness.dark,
);

/// Theme 6 — AMOLED. The non-adaptive sibling of Adaptive AMOLED: the
/// same pitch-black chassis, but a fixed cherry-pink/lavender palette
/// that never follows the art. Midnight kawaii.
const amoled = HanamimiTheme(
  id: 'amoled',
  name: 'AMOLED',
  emoji: '⚫',
  background: Color(0xFF000000),
  surface: Color(0xFF0E0D0F),
  primary: Color(0xFFFF8FAB),
  secondary: Color(0xFFD4A5E8),
  accent: Color(0xFFFFC2D1),
  textPrimary: Color(0xFFEDEDED),
  textMuted: Color(0xFF8F8A93),
  divider: Color(0xFF1C1B1E),
  visualizerStyle: VisualizerStyle.bars,
  brightness: HanamimiBrightness.dark,
);

/// Builds an Adaptive theme from a Material You [ColorScheme] extracted
/// from album art. The scheme is generated at the variant's brightness
/// (see adaptive_theme_provider), so [variant] supplies id/name — and,
/// for AMOLED, the pinned neutral slots: there only the accents follow
/// the art (dark-scheme tones ~80 read well on black), everything else
/// stays black/grey so the colour pops by scarcity.
HanamimiTheme fromArtScheme(ColorScheme s, HanamimiTheme variant) {
  final amoled = variant.id == neutralAdaptiveAmoled.id;
  return HanamimiTheme(
    id: variant.id,
    name: variant.name,
    emoji: variant.emoji,
    background: amoled ? variant.background : s.surface,
    surface: amoled ? variant.surface : s.surfaceContainerHigh,
    primary: s.primary,
    secondary: s.tertiary, // second bar colour / lerp target
    accent: s.secondary,
    textPrimary: amoled ? variant.textPrimary : s.onSurface,
    textMuted: amoled ? variant.textMuted : s.onSurfaceVariant,
    divider: amoled ? variant.divider : s.outlineVariant,
    visualizerStyle: VisualizerStyle.bars,
    brightness: s.brightness == Brightness.dark
        ? HanamimiBrightness.dark
        : HanamimiBrightness.light,
  );
}

const allThemes = [
  cherryBlossom,
  adaptiveLight,
  starryNight,
  adaptiveDark,
  neutralAdaptiveAmoled,
  amoled,
];

HanamimiTheme themeById(String id) {
  // Retired themes land on a sensible survivor rather than a missing one:
  // Rainy Day and Matcha fold into the default; plain "adaptive" (which
  // used to follow the art's brightness) becomes Adaptive Light.
  if (id == 'rainy_day' || id == 'matcha') return cherryBlossom;
  if (id == 'adaptive') return adaptiveLight;
  return allThemes.firstWhere((t) => t.id == id, orElse: () => cherryBlossom);
}
