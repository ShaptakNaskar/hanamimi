import '../../library/models/track.dart';
import 'queue_mode.dart';

enum PlaybackStatus { idle, loading, playing, paused, completed }

/// Snapshot of the audio engine, emitted on every meaningful change.
/// Position is deliberately NOT here — it ticks continuously and is
/// exposed as its own stream so the whole UI doesn't rebuild per frame.
/// Crossfade progress is excluded for the same reason: this carries only
/// the fade's start/end edges via [crossfadeIncomingTrack]; the per-tick
/// 0–1 progress rides QueueManager.crossfadeT.
class AudioState {
  const AudioState({
    this.currentTrack,
    this.queue = const [],
    this.status = PlaybackStatus.idle,
    this.duration = Duration.zero,
    this.queueMode = QueueMode.sequential,
    this.crossfadeIncomingTrack,
    this.audioSessionId,
  });

  final Track? currentTrack;
  final List<Track> queue;
  final PlaybackStatus status;
  final Duration duration;
  final QueueMode queueMode;

  /// The track fading IN during a crossfade — [currentTrack] stays the
  /// outgoing one until the fade completes, so the UI needs both to
  /// dissolve the art and title from one to the other in lockstep with
  /// the audio. Null outside a crossfade (this doubles as the
  /// "crossfade running" flag).
  final Track? crossfadeIncomingTrack;

  /// Android audio session id, consumed by the visualizer channel (M8).
  final int? audioSessionId;

  bool get isPlaying => status == PlaybackStatus.playing;

  AudioState copyWith({
    Track? currentTrack,
    bool clearCurrentTrack = false,
    List<Track>? queue,
    PlaybackStatus? status,
    Duration? duration,
    QueueMode? queueMode,
    Track? crossfadeIncomingTrack,
    bool clearCrossfade = false,
    int? audioSessionId,
  }) =>
      AudioState(
        currentTrack:
            clearCurrentTrack ? null : currentTrack ?? this.currentTrack,
        queue: queue ?? this.queue,
        status: status ?? this.status,
        duration: duration ?? this.duration,
        queueMode: queueMode ?? this.queueMode,
        crossfadeIncomingTrack: clearCrossfade
            ? null
            : crossfadeIncomingTrack ?? this.crossfadeIncomingTrack,
        audioSessionId: audioSessionId ?? this.audioSessionId,
      );
}
