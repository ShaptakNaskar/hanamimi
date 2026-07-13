import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/models/audio_state.dart';
import '../ui/components/mascot/hanamimi_widget.dart';
import 'audio_provider.dart';
import 'sleep_timer_provider.dart';

/// Derives the mascot's state from playback, holding a transient
/// [MascotState.changing] head-tilt for 1.2s on every track change.
class MascotNotifier extends Notifier<MascotState> {
  int? _lastTrackId;
  Timer? _changingTimer;

  @override
  MascotState build() {
    ref.onDispose(() => _changingTimer?.cancel());

    // Fading out to sleep trumps everything — she's dozing off.
    if (ref.watch(sleepTimerProvider).isFading) return MascotState.sleeping;

    final audio = ref.watch(audioStateProvider).value;
    if (audio == null) return MascotState.idle;

    // A crossfade is audibly playing (the outgoing track's player is
    // still going) — never flash the loading face while it runs, even if
    // the incoming stream is buffering underneath.
    if (audio.crossfadeIncomingTrack != null) return MascotState.playing;

    final trackId = audio.currentTrack?.id;
    final trackChanged = trackId != null &&
        _lastTrackId != null &&
        trackId != _lastTrackId;
    _lastTrackId = trackId;

    if (trackChanged) {
      _changingTimer?.cancel();
      _changingTimer = Timer(const Duration(milliseconds: 1200), () {
        ref.invalidateSelf();
      });
      return MascotState.changing;
    }
    if (_changingTimer?.isActive ?? false) return MascotState.changing;

    return switch (audio.status) {
      PlaybackStatus.playing => MascotState.playing,
      PlaybackStatus.loading => MascotState.loading,
      PlaybackStatus.paused ||
      PlaybackStatus.completed =>
        MascotState.paused,
      PlaybackStatus.idle => MascotState.idle,
    };
  }
}

final mascotStateProvider =
    NotifierProvider<MascotNotifier, MascotState>(MascotNotifier.new);
