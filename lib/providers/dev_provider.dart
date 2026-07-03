import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_provider.dart';

/// Developer options, unlocked by tapping the About row 7 times.
class DevModeNotifier
    extends Notifier<({bool enabled, bool allAccessories})> {
  static const _enabledKey = 'dev_mode';
  static const _accessoriesKey = 'dev_all_accessories';

  int _taps = 0;

  @override
  ({bool enabled, bool allAccessories}) build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return (
      enabled: prefs.getBool(_enabledKey) ?? false,
      allAccessories: prefs.getBool(_accessoriesKey) ?? false,
    );
  }

  /// Returns true when this tap flips dev mode on.
  bool registerAboutTap() {
    if (state.enabled) return false;
    _taps++;
    if (_taps < 7) return false;
    ref.read(sharedPrefsProvider).setBool(_enabledKey, true);
    state = (enabled: true, allAccessories: state.allAccessories);
    return true;
  }

  void setAllAccessories(bool on) {
    ref.read(sharedPrefsProvider).setBool(_accessoriesKey, on);
    state = (enabled: state.enabled, allAccessories: on);
  }

  void disable() {
    _taps = 0;
    final prefs = ref.read(sharedPrefsProvider);
    prefs.setBool(_enabledKey, false);
    prefs.setBool(_accessoriesKey, false);
    state = (enabled: false, allAccessories: false);
  }
}

final devModeProvider = NotifierProvider<DevModeNotifier,
    ({bool enabled, bool allAccessories})>(DevModeNotifier.new);
