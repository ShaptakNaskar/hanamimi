import '../../library/models/track.dart';
import 'queue_mode.dart';

enum PlaybackStatus { idle, loading, playing, paused, completed }

/// Snapshot of the audio engine, emitted on every meaningful change.
/// Position is deliberately NOT here — it ticks continuously and is
/// exposed as its own stream so the whole UI doesn't rebuild per frame.
class AudioState {
  const AudioState({
    this.currentTrack,
    this.queue = const [],
    this.status = PlaybackStatus.idle,
    this.duration = Duration.zero,
    this.queueMode = QueueMode.sequential,
    this.crossfadeProgress,
    this.audioSessionId,
  });

  final Track? currentTrack;
  final List<Track> queue;
  final PlaybackStatus status;
  final Duration duration;
  final QueueMode queueMode;

  /// null when idle, 0.0–1.0 while a crossfade is running (M9).
  final double? crossfadeProgress;

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
    double? crossfadeProgress,
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
        crossfadeProgress: clearCrossfade
            ? null
            : crossfadeProgress ?? this.crossfadeProgress,
        audioSessionId: audioSessionId ?? this.audioSessionId,
      );
}
