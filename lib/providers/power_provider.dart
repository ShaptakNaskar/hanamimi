import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/web/web_media.dart';

/// Screen-awake plumbing, web edition: the browser Wake Lock API where
/// the Android edition uses a window flag. Best-effort — an unsupported
/// browser just lets the screen dim, nothing breaks.
class PowerChannel {
  static Future<void> setKeepScreenOn(bool on) =>
      WebMedia.setKeepScreenOn(on);
}

/// Caffeine ☕ — keeps the screen awake for staring at the visualizer.
/// Deliberately not persisted: like real caffeine it wears off (next
/// visit starts fresh).
class CaffeineNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() {
    state = !state;
    PowerChannel.setKeepScreenOn(state);
  }
}

final caffeineProvider =
    NotifierProvider<CaffeineNotifier, bool>(CaffeineNotifier.new);
