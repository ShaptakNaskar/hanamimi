import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/hanamimi_theme.dart';
import '../theme/themes.dart';

/// Injected in main() with the loaded instance.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('overridden in main'),
);

class ThemeNotifier extends Notifier<HanamimiTheme> {
  static const _key = 'theme_id';

  @override
  HanamimiTheme build() {
    final saved = ref.watch(sharedPrefsProvider).getString(_key);
    return saved == null ? cherryBlossom : themeById(saved);
  }

  void setTheme(String id) {
    state = themeById(id);
    ref.read(sharedPrefsProvider).setString(_key, id);
  }
}

final currentThemeProvider =
    NotifierProvider<ThemeNotifier, HanamimiTheme>(ThemeNotifier.new);
