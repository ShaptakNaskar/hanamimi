import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/hanamimi_theme.dart';
import '../theme/themes.dart';

/// Current app theme. Persistence to the prefs store is wired in the
/// data layer milestone; until then this is session-only.
class ThemeNotifier extends Notifier<HanamimiTheme> {
  @override
  HanamimiTheme build() => cherryBlossom;

  void setTheme(String id) => state = themeById(id);
}

final currentThemeProvider =
    NotifierProvider<ThemeNotifier, HanamimiTheme>(ThemeNotifier.new);
