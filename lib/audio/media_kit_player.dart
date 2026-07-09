import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:rxdart/rxdart.dart';

import 'player_port.dart';

/// Desktop backend: libmpv via media_kit (ARCHITECTURE-DESKTOP.md §2).
/// media_kit has no processing-state concept, so this synthesizes one:
/// setSource holds `loading` until mpv reports a duration (or errors),
/// `buffering` follows mpv's buffering flag, and the playlist-end event
/// maps to `completed`.
class MediaKitPlayer implements AudioPlayerPort {
  MediaKitPlayer() {
    _subs = [
      _player.stream.playing.listen((_) => _playerState.add(null)),
      _player.stream.buffering.listen((buffering) {
        // Only meaningful mid-playback; the load phase owns `loading`.
        if (_state == PortState.ready && buffering) {
          _setState(PortState.buffering);
        } else if (_state == PortState.buffering && !buffering) {
          _setState(PortState.ready);
        }
      }),
      _player.stream.completed.listen((completed) {
        if (completed) _setState(PortState.completed);
      }),
      _player.stream.duration.listen((d) {
        if (d > Duration.zero) _duration.add(d);
      }),
      _player.stream.position.listen((p) {
        _position = p;
        // A position tick after `completed` means playback restarted
        // (repeat-one seeks back and plays the same media).
        if (_state == PortState.completed && _player.state.playing) {
          _setState(PortState.ready);
        }
      }),
      _player.stream.error.listen((message) => _lastError = message),
    ];
  }

  final _player = Player(
    configuration: const PlayerConfiguration(
      title: 'Hanamimi',
      logLevel: MPVLogLevel.error,
    ),
  );

  late final List<StreamSubscription> _subs;

  PortState _state = PortState.idle;
  final _processingState = BehaviorSubject<PortState>.seeded(PortState.idle);
  final _playerState = StreamController<void>.broadcast();
  final _duration = BehaviorSubject<Duration?>.seeded(null);
  Duration _position = Duration.zero;
  String? _lastError;

  void _setState(PortState next) {
    if (next == _state) return;
    _state = next;
    _processingState.add(next);
    _playerState.add(null);
  }

  @override
  Future<void> setSource(PlaybackSource source) async {
    _setState(PortState.loading);
    _duration.add(null);
    _position = Duration.zero;
    _lastError = null;

    final target = source.filePath ?? source.uri!.toString();
    await _player.open(
      Media(target,
          httpHeaders: source.headers.isEmpty ? null : source.headers),
      play: false,
    );

    // mpv probes asynchronously; a duration is the "this will play"
    // signal (subscribe before checking state to close the race with a
    // fast local load). An mpv error or a dead timeout throws, so the
    // engine's skip-on-failure cascade sees it like an unreadable file.
    final loaded = Completer<void>();
    final durSub = _player.stream.duration.listen((d) {
      if (d > Duration.zero && !loaded.isCompleted) loaded.complete();
    });
    final errSub = _player.stream.error.listen((message) {
      if (!loaded.isCompleted) {
        loaded.completeError(Exception('mpv: $message'));
      }
    });
    try {
      if (_player.state.duration > Duration.zero && !loaded.isCompleted) {
        loaded.complete();
      }
      if (_lastError != null && !loaded.isCompleted) {
        loaded.completeError(Exception('mpv: $_lastError'));
      }
      await loaded.future.timeout(const Duration(seconds: 30));
      _setState(PortState.ready);
    } catch (_) {
      _setState(PortState.idle);
      rethrow;
    } finally {
      await durSub.cancel();
      await errSub.cancel();
    }
  }

  @override
  Future<void> play() => _player.play();
  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    _position = Duration.zero;
    _duration.add(null);
    _setState(PortState.idle);
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _position = position;
  }

  // media_kit volume is 0–100; the port speaks 0–1 like just_audio.
  @override
  Future<void> setVolume(double volume) =>
      _player.setVolume((volume * 100).clamp(0, 100).toDouble());

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await _processingState.close();
    await _playerState.close();
    await _duration.close();
    await _player.dispose();
  }

  @override
  bool get playing => _player.state.playing;
  @override
  Duration get position => _position;
  @override
  Duration get bufferedPosition => _player.state.buffer;
  @override
  Duration? get duration => _duration.value;
  @override
  PortState get processingState => _state;

  @override
  Stream<PortState> get processingStateStream => _processingState.stream;
  @override
  Stream<void> get playerStateStream => _playerState.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;
  @override
  Stream<Duration> get positionStream => _player.stream.position;
  @override
  Stream<Duration> get bufferedPositionStream => _player.stream.buffer;
  @override
  Stream<int> get audioSessionIdStream => const Stream.empty();
}
