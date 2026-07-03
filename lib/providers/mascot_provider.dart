import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/models/audio_state.dart';
import '../ui/components/mascot/hanamimi_widget.dart';
import 'audio_provider.dart';

/// Derives the mascot's state from playback, holding a transient
/// [MascotState.changing] head-tilt for 1.2s on every track change.
class MascotNotifier extends Notifier<MascotState> {
  int? _lastTrackId;
  Timer? _changingTimer;

  @override
  MascotState build() {
    ref.onDispose(() => _changingTimer?.cancel());

    final audio = ref.watch(audioStateProvider).value;
    if (audio == null) return MascotState.idle;

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
