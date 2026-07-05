import 'dart:ui';

enum VisualizerStyle { bars, raindrops, radial, wave }

enum HanamimiBrightness { light, dark }

/// One of the four app themes. All colors come from DESIGN.md §3.
class HanamimiTheme {
  const HanamimiTheme({
    required this.id,
    required this.name,
    required this.emoji,
    required this.background,
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.textPrimary,
    required this.textMuted,
    required this.divider,
    required this.visualizerStyle,
    required this.brightness,
  });

  final String id;
  final String name;
  final String emoji;

  final Color background;
  final Color surface;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color textPrimary;
  final Color textMuted;
  final Color divider;

  final VisualizerStyle visualizerStyle;
  final HanamimiBrightness brightness;

  bool get isDark => brightness == HanamimiBrightness.dark;

  /// Interpolates every colour between two themes for the gentle cross-fade
  /// when the adaptive theme recolours per track. Discrete fields
  /// (id/name/visualizerStyle/brightness) snap at the halfway point to the
  /// destination, so the visualizer style and dark/light flip cleanly.
  static HanamimiTheme lerp(HanamimiTheme a, HanamimiTheme b, double t) {
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    final past = t >= 0.5;
    return HanamimiTheme(
      id: past ? b.id : a.id,
      name: past ? b.name : a.name,
      emoji: past ? b.emoji : a.emoji,
      background: c(a.background, b.background),
      surface: c(a.surface, b.surface),
      primary: c(a.primary, b.primary),
      secondary: c(a.secondary, b.secondary),
      accent: c(a.accent, b.accent),
      textPrimary: c(a.textPrimary, b.textPrimary),
      textMuted: c(a.textMuted, b.textMuted),
      divider: c(a.divider, b.divider),
      visualizerStyle: past ? b.visualizerStyle : a.visualizerStyle,
      brightness: past ? b.brightness : a.brightness,
    );
  }
}
