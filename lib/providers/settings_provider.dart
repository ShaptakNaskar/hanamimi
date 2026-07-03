import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_provider.dart';
import 'theme_provider.dart';

/// Crossfade duration in seconds; 0 = off. Persisted, and pushed into
/// the QueueManager whenever it changes.
class CrossfadeNotifier extends Notifier<int> {
  static const _key = 'crossfade_seconds';

  @override
  int build() {
    final seconds = ref.watch(sharedPrefsProvider).getInt(_key) ?? 0;
    _push(seconds);
    return seconds;
  }

  void set(int seconds) {
    state = seconds;
    ref.read(sharedPrefsProvider).setInt(_key, seconds);
    _push(seconds);
  }

  void _push(int seconds) {
    ref.read(audioHandlerProvider).engine.crossfadeDuration =
        Duration(seconds: seconds);
  }
}

final crossfadeProvider =
    NotifierProvider<CrossfadeNotifier, int>(CrossfadeNotifier.new);
