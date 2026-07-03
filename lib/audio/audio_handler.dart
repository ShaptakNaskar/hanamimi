import 'package:audio_service/audio_service.dart';

import '../library/models/track.dart';
import 'models/audio_state.dart';
import 'models/queue_mode.dart';
import 'queue_manager.dart';

/// Bridges [QueueManager] to audio_service: lock screen / notification
/// controls, media buttons, Bluetooth.
class HanamimiAudioHandler extends BaseAudioHandler {
  HanamimiAudioHandler(this.engine) {
    engine.stateStream.listen(_broadcast);
  }

  final QueueManager engine;

  void _broadcast(AudioState s) {
    final track = s.currentTrack;
    if (track != null) {
      mediaItem.add(MediaItem(
        id: track.filePath,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: s.duration,
        artUri: track.albumArtPath == null
            ? null
            : Uri.file(track.albumArtPath!),
      ));
    }

    // One snapshot per state transition. The OS extrapolates the live
    // position from updatePosition + updateTime + speed, so forwarding
    // every position tick here would rebuild the media notification
    // many times a second — which can wedge the main thread while the
    // notification shade is open.
    playbackState.add(playbackState.value.copyWith(
      updatePosition: engine.position,
      controls: [
        MediaControl.skipToPrevious,
        s.isPlaying ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (s.status) {
        PlaybackStatus.idle => AudioProcessingState.idle,
        PlaybackStatus.loading => AudioProcessingState.loading,
        PlaybackStatus.playing ||
        PlaybackStatus.paused =>
          AudioProcessingState.ready,
        PlaybackStatus.completed => AudioProcessingState.completed,
      },
      playing: s.isPlaying,
      repeatMode: switch (s.queueMode) {
        QueueMode.repeatOne => AudioServiceRepeatMode.one,
        QueueMode.repeatAll => AudioServiceRepeatMode.all,
        _ => AudioServiceRepeatMode.none,
      },
      shuffleMode: s.queueMode == QueueMode.shuffle
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    ));
  }

  // Convenience for the UI layer.
  Future<void> playTracks(List<Track> tracks,
          {int startIndex = 0, QueueMode? mode}) =>
      engine.loadQueue(tracks, startIndex: startIndex, mode: mode);

  @override
  Future<void> play() => engine.play();

  @override
  Future<void> pause() => engine.pause();

  @override
  Future<void> seek(Duration position) async {
    await engine.seek(position);
    // Re-anchor the system's extrapolated position after a jump.
    playbackState.add(playbackState.value.copyWith(
      updatePosition: position,
    ));
  }

  @override
  Future<void> skipToNext() => engine.next();

  @override
  Future<void> skipToPrevious() => engine.previous();

  @override
  Future<void> stop() => engine.stop();
}
