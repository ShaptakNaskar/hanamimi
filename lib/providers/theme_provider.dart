import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/hanamimi_theme.dart';
import '../theme/themes.dart';
import 'adaptive_theme_provider.dart';

/// Injected in main() with the loaded instance.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('overridden in main'),
);

/// The persisted theme *selection* — just an id (may be `adaptive`). Kept
/// separate from the resolved theme so the adaptive palette can be derived
/// downstream and animated without the picker caring.
class SelectedThemeId extends Notifier<String> {
  static const _key = 'theme_id';

  @override
  String build() {
    final saved = ref.watch(sharedPrefsProvider).getString(_key);
    if (saved == null || saved == 'rainy_day') return cherryBlossom.id;
    return saved;
  }

  void setTheme(String id) {
    state = id;
    ref.read(sharedPrefsProvider).setString(_key, id);
  }
}

final selectedThemeIdProvider =
    NotifierProvider<SelectedThemeId, String>(SelectedThemeId.new);

/// The resolved *target* theme: a static one, or — when `adaptive` is
/// selected — the art-derived palette for the current track (neutral until
/// it resolves).
final resolvedThemeProvider = Provider<HanamimiTheme>((ref) {
  final id = ref.watch(selectedThemeIdProvider);
  if (id == 'adaptive') {
    return ref.watch(adaptiveThemeProvider).value ?? neutralAdaptive;
  }
  return themeById(id);
});

/// The theme the UI actually renders. It's seeded from the resolved target
/// and then lerped toward new targets by [ThemeAnimator] (the gentle Monet
/// wash on track changes). Everything watches this.
class DisplayTheme extends Notifier<HanamimiTheme> {
  @override
  HanamimiTheme build() => ref.read(resolvedThemeProvider);

  void set(HanamimiTheme theme) => state = theme;
}

final currentThemeProvider =
    NotifierProvider<DisplayTheme, HanamimiTheme>(DisplayTheme.new);
