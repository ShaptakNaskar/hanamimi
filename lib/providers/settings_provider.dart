import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/slow_dance.dart';
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
    // Crossfade and Slow Dance are two flavours of the same handoff —
    // only one runs at a time. Turning this on switches the other off.
    if (seconds > 0 && ref.read(slowDanceProvider)) {
      ref.read(slowDanceProvider.notifier).set(false);
    }
  }

  void _push(int seconds) {
    ref.read(audioHandlerProvider).engine.crossfadeDuration =
        Duration(seconds: seconds);
  }
}

final crossfadeProvider =
    NotifierProvider<CrossfadeNotifier, int>(CrossfadeNotifier.new);

/// Slow Dance (3.0 #4): sighted crossfade. A separate toggle from
/// Crossfade — that one blends on a blind timer, this one reads the
/// outgoing track's cached loudness frames and starts the next song
/// where the energy actually dies. Persisted, pushed as a planner
/// function into the QueueManager (same pattern as autoplayFetcher).
class SlowDanceNotifier extends Notifier<bool> {
  static const _key = 'slow_dance';

  @override
  bool build() {
    final on = ref.watch(sharedPrefsProvider).getBool(_key) ?? false;
    _push(on);
    return on;
  }

  void toggle() => set(!state);

  void set(bool on) {
    state = on;
    ref.read(sharedPrefsProvider).setBool(_key, on);
    _push(on);
    // Mutually exclusive with the blind-timer Crossfade (see
    // CrossfadeNotifier.set) — turning Slow Dance on switches it off.
    if (on && ref.read(crossfadeProvider) > 0) {
      ref.read(crossfadeProvider.notifier).set(0);
    }
  }

  void _push(bool on) {
    ref.read(audioHandlerProvider).engine.slowDancePlanner =
        on ? planSlowDance : null;
  }
}

final slowDanceProvider =
    NotifierProvider<SlowDanceNotifier, bool>(SlowDanceNotifier.new);

/// "Melt away" (3.0 #6): idle listening fades Now Playing's chrome —
/// controls first, then labels — until it's art + visualizer + mascot.
/// On by default; a toggle because an interface that quietly hides its
/// buttons should always be declinable.
class MeltAwayNotifier extends Notifier<bool> {
  static const _key = 'melt_away';

  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(_key) ?? true;

  void toggle() {
    state = !state;
    ref.read(sharedPrefsProvider).setBool(_key, state);
  }
}

final meltAwayProvider =
    NotifierProvider<MeltAwayNotifier, bool>(MeltAwayNotifier.new);
