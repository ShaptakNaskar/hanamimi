import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_provider.dart';

/// Cat Mode easter egg (ARCHITECTURE.md §16): tap the mascot 7× to
/// unlock. Once unlocked, a hidden toggle appears in the You tab.
class CatModeNotifier extends Notifier<({bool unlocked, bool enabled})> {
  static const _unlockedKey = 'cat_unlocked';
  static const _enabledKey = 'cat_mode';

  int _taps = 0;

  @override
  ({bool unlocked, bool enabled}) build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return (
      unlocked: prefs.getBool(_unlockedKey) ?? false,
      enabled: prefs.getBool(_enabledKey) ?? false,
    );
  }

  /// Returns true when this tap unlocks Cat Mode.
  bool registerMascotTap() {
    if (state.unlocked) return false;
    _taps++;
    if (_taps < 7) return false;
    final prefs = ref.read(sharedPrefsProvider);
    prefs.setBool(_unlockedKey, true);
    prefs.setBool(_enabledKey, true);
    state = (unlocked: true, enabled: true);
    return true;
  }

  void setEnabled(bool on) {
    ref.read(sharedPrefsProvider).setBool(_enabledKey, on);
    state = (unlocked: state.unlocked, enabled: on);
  }
}

final catModeProvider =
    NotifierProvider<CatModeNotifier, ({bool unlocked, bool enabled})>(
        CatModeNotifier.new);
