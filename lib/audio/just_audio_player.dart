import 'package:just_audio/just_audio.dart';

import 'player_port.dart';

/// Android backend: just_audio / ExoPlayer, extracted verbatim from the
/// pre-M31 QueueManager.
class JustAudioPlayer implements AudioPlayerPort {
  // handleInterruptions:false — the engine is the audio session's single
  // owner (see QueueManager); a self-managing player abandons focus when
  // a crossfade player is disposed.
  final _player = AudioPlayer(handleInterruptions: false);

  @override
  Future<void> setSource(PlaybackSource source) async {
    final path = source.filePath;
    if (path != null) {
      // Tracks opened from other apps carry a content:// uri.
      await _player.setAudioSource(path.startsWith('content://')
          ? AudioSource.uri(Uri.parse(path))
          : AudioSource.file(path));
      return;
    }
    final cacheFile = source.cacheFile;
    // Cache-as-you-play: LockCachingAudioSource writes the stream to
    // disk while playing. It also serves through just_audio's proxy
    // (Dart HTTP), which is what lets YouTube URLs past ExoPlayer's 403.
    await _player.setAudioSource(cacheFile != null
        ? LockCachingAudioSource(source.uri!,
            headers: source.headers, cacheFile: cacheFile)
        : AudioSource.uri(source.uri!, headers: source.headers));
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();
  @override
  Future<void> stop() => _player.stop();
  @override
  Future<void> seek(Duration position) => _player.seek(position);
  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);
  @override
  Future<void> dispose() => _player.dispose();

  @override
  bool get playing => _player.playing;
  @override
  Duration get position => _player.position;
  @override
  Duration get bufferedPosition => _player.bufferedPosition;
  @override
  Duration? get duration => _player.duration;
  @override
  PortState get processingState => _map(_player.processingState);

  @override
  Stream<PortState> get processingStateStream =>
      _player.processingStateStream.map(_map);
  @override
  Stream<void> get playerStateStream => _player.playerStateStream;
  @override
  Stream<Duration?> get durationStream => _player.durationStream;
  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<Duration> get bufferedPositionStream =>
      _player.bufferedPositionStream;
  @override
  Stream<int> get audioSessionIdStream => _player.androidAudioSessionIdStream
      .where((id) => id != null)
      .cast<int>();

  static PortState _map(ProcessingState ps) => switch (ps) {
        ProcessingState.idle => PortState.idle,
        ProcessingState.loading => PortState.loading,
        ProcessingState.buffering => PortState.buffering,
        ProcessingState.ready => PortState.ready,
        ProcessingState.completed => PortState.completed,
      };
}
