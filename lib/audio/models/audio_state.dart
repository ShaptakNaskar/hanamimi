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
    this.crossfadeIncomingTrack,
    this.crossfadeIncomingPositionMs = 0,
    this.audioSessionId,
  });

  final Track? currentTrack;
  final List<Track> queue;
  final PlaybackStatus status;
  final Duration duration;
  final QueueMode queueMode;

  /// null when idle, 0.0–1.0 while a crossfade is running (M9).
  final double? crossfadeProgress;

  /// The track fading IN during a crossfade — [currentTrack] stays the
  /// outgoing one until the fade completes, so the UI needs both to
  /// dissolve the art and title from one to the other in lockstep with
  /// the audio. Null outside a crossfade.
  final Track? crossfadeIncomingTrack;

  /// The incoming player's live position during a crossfade — it's been
  /// playing since the fade began, so the seek bar can roll smoothly to
  /// where the new song already is instead of snapping at the handoff.
  final int crossfadeIncomingPositionMs;

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
    Track? crossfadeIncomingTrack,
    int? crossfadeIncomingPositionMs,
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
        crossfadeIncomingTrack: clearCrossfade
            ? null
            : crossfadeIncomingTrack ?? this.crossfadeIncomingTrack,
        crossfadeIncomingPositionMs: clearCrossfade
            ? 0
            : crossfadeIncomingPositionMs ?? this.crossfadeIncomingPositionMs,
        audioSessionId: audioSessionId ?? this.audioSessionId,
      );
}
