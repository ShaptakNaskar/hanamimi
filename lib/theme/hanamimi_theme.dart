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
}
