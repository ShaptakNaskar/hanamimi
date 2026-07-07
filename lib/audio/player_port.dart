import 'dart:io';

import 'just_audio_player.dart';
import 'media_kit_player.dart';

/// Processing state of a player, platform-neutral. Mirrors just_audio's
/// ProcessingState; the media_kit backend maps onto it.
enum PortState { idle, loading, buffering, ready, completed }

/// What to play, resolved but not yet bound to an engine. Each backend
/// turns this into its native source type: just_audio builds a
/// (LockCaching)AudioSource, media_kit a Media with http headers.
class PlaybackSource {
  const PlaybackSource.file(String this.filePath)
      : uri = null,
        headers = const {},
        cacheFile = null;

  const PlaybackSource.remote(Uri this.uri,
      {this.headers = const {}, this.cacheFile})
      : filePath = null;

  /// Local file path — may be a content:// uri on Android (open-with).
  final String? filePath;

  /// Remote stream URL.
  final Uri? uri;
  final Map<String, String> headers;

  /// Cache-as-you-play target. just_audio streams through its proxy
  /// into this file; the media_kit backend ignores it (mpv buffers its
  /// own way, and downloads cover the offline case).
  final File? cacheFile;
}

/// The engine-facing player contract (ARCHITECTURE-DESKTOP.md §2).
/// QueueManager owns two of these for the crossfade model and never
/// touches just_audio or media_kit directly.
abstract class AudioPlayerPort {
  /// Android keeps ExoPlayer (battery-friendly, audio-focus native);
  /// desktop runs libmpv via media_kit.
  factory AudioPlayerPort.create() =>
      Platform.isAndroid ? JustAudioPlayer() : MediaKitPlayer();

  Future<void> setSource(PlaybackSource source);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> dispose();

  bool get playing;
  Duration get position;
  Duration? get duration;
  PortState get processingState;

  Stream<PortState> get processingStateStream;

  /// Fires on ANY player-state change (playing or processing state) —
  /// the engine recomputes its status from the getters on each event.
  Stream<void> get playerStateStream;
  Stream<Duration?> get durationStream;
  Stream<Duration> get positionStream;

  /// Android audio session id (equalizer hooks); never fires on desktop.
  Stream<int> get audioSessionIdStream;
}
