import 'dart:ui';

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
  visualizerStyle: VisualizerStyle.radial,
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

const allThemes = [cherryBlossom, rainyDay, starryNight, matcha];

HanamimiTheme themeById(String id) =>
    allThemes.firstWhere((t) => t.id == id, orElse: () => cherryBlossom);
