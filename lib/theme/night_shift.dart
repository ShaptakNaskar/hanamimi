import 'dart:ui';

import 'package:flutter/painting.dart' show HSLColor;

import 'hanamimi_theme.dart';

/// The Night Mode palette shift (3.0 — "After Midnight, It Whispers").
///
/// Reuses the visualizer meter zones' "unlit = dark embers" treatment
/// (lightness ×~0.4, saturation eased) on the whole theme: accents get
/// warmed toward ember orange and dimmed, canvases sink toward black,
/// text glows a little less. Light themes are first flipped dark —
/// 2am is not a white-background hour.
HanamimiTheme nightShift(HanamimiTheme t) {
  const emberSeed = Color(0xFFCC5A2E);

  Color ember(Color c) {
    // Warm first, then apply the meters' dim formula (lightness kept
    // above a floor so accents stay legible as accents).
    final warmed = Color.lerp(c, emberSeed, 0.30)!;
    final hsl = HSLColor.fromColor(warmed);
    final l = (hsl.lightness * 0.72).clamp(0.30, 1.0);
    return hsl
        .withLightness(l)
        .withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0))
        .toColor();
  }

  Color sink(Color c, {required double darkFactor, required double lightTo}) {
    final hsl = HSLColor.fromColor(c);
    return t.isDark
        // Already-black AMOLED canvases stay pinned at black.
        ? hsl.withLightness(hsl.lightness * darkFactor).toColor()
        : hsl
            .withLightness(lightTo)
            .withSaturation((hsl.saturation * 0.5).clamp(0.0, 1.0))
            .toColor();
  }

  Color text(Color c, {required double lightTo}) {
    final hsl = HSLColor.fromColor(c);
    return t.isDark
        ? hsl.withLightness((hsl.lightness * 0.88).clamp(0.0, 1.0)).toColor()
        : hsl.withLightness(lightTo).toColor();
  }

  return HanamimiTheme(
    id: t.id,
    name: t.name,
    emoji: '🌙',
    background: sink(t.background, darkFactor: 0.45, lightTo: 0.06),
    surface: sink(t.surface, darkFactor: 0.55, lightTo: 0.10),
    primary: ember(t.primary),
    secondary: ember(t.secondary),
    accent: ember(t.accent),
    textPrimary: text(t.textPrimary, lightTo: 0.88),
    textMuted: text(t.textMuted, lightTo: 0.60),
    divider: sink(t.divider, darkFactor: 0.6, lightTo: 0.16),
    visualizerStyle: t.visualizerStyle,
    brightness: HanamimiBrightness.dark,
  );
}
