import 'dart:async';
import 'dart:math';

import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../library/models/track.dart';
import 'models/audio_state.dart';
import 'models/queue_mode.dart';

/// Owns the players and the queue. Crossfade uses the two-player model
/// from ARCHITECTURE.md §6.1: [_primary] is audible; [_incoming] exists
/// only while a crossfade is running, then becomes the new primary.
class QueueManager {
  QueueManager() {
    _primary = AudioPlayer();
    _wirePlayer(_primary);
  }

  late AudioPlayer _primary;
  AudioPlayer? _incoming;

  /// User setting; Duration.zero = crossfade off.
  Duration crossfadeDuration = Duration.zero;

  /// Sleep timer "end of track" mode: finish the current song, then
  /// pause instead of advancing.
  bool pauseAtTrackEnd = false;

  Timer? _crossfadeTimer;
  int? _pendingCursor;
  Track? _pendingTrack;
  bool get _crossfading => _incoming != null;

  final _state = BehaviorSubject<AudioState>.seeded(const AudioState());
  Stream<AudioState> get stateStream => _state.stream;
  AudioState get state => _state.value;

  /// Stable across player swaps (a raw player stream would go dead when
  /// the primary is disposed after a crossfade).
  final _position = BehaviorSubject<Duration>.seeded(Duration.zero);
  Stream<Duration> get positionStream => _position.stream;

  /// Fires with a track every time playback of it begins (for play counts).
  final trackStarted = StreamController<Track>.broadcast();

  List<Track> _source = [];
  List<int> _order = [];
  int _cursor = 0;
  final List<Track> _history = [];
  QueueMode _mode = QueueMode.sequential;

  List<StreamSubscription> _subs = [];

  void _wirePlayer(AudioPlayer player) {
    for (final s in _subs) {
      s.cancel();
    }
    _subs = [
      player.processingStateStream.listen((ps) {
        if (ps == ProcessingState.completed) _onTrackCompleted();
      }),
      player.playingStream.listen((_) => _emitStatus(player)),
      player.durationStream.listen((d) {
        if (d != null) _state.add(state.copyWith(duration: d));
      }),
      player.androidAudioSessionIdStream.listen((id) {
        if (id != null) _state.add(state.copyWith(audioSessionId: id));
      }),
      player.positionStream.listen((pos) {
        _position.add(pos);
        _maybeStartCrossfade(pos);
      }),
    ];
  }

  void _emitStatus(AudioPlayer player) {
    final ps = player.processingState;
    final status = switch (ps) {
      ProcessingState.idle => PlaybackStatus.idle,
      ProcessingState.loading ||
      ProcessingState.buffering =>
        PlaybackStatus.loading,
      ProcessingState.completed => PlaybackStatus.completed,
      ProcessingState.ready =>
        player.playing ? PlaybackStatus.playing : PlaybackStatus.paused,
    };
    _state.add(state.copyWith(status: status));
  }

  Track? get _currentTrack =>
      _order.isEmpty ? null : _source[_order[_cursor]];

  // --- Public API ---

  Future<void> loadQueue(
    List<Track> tracks, {
    int startIndex = 0,
    QueueMode? mode,
  }) async {
    await _abortCrossfade();
    _source = List.of(tracks);
    if (mode != null) _mode = mode;
    _rebuildOrder(anchor: startIndex);
    _history.clear();
    await _playCurrent();
  }

  Future<void> play() => _primary.play();

  Future<void> pause() async {
    await _abortCrossfade();
    await _primary.pause();
  }

  Future<void> seek(Duration position) async {
    await _abortCrossfade();
    await _primary.seek(position);
  }

  Future<void> next({bool byUser = true}) async {
    if (_order.isEmpty) return;
    await _abortCrossfade();
    final current = _currentTrack;
    if (current != null) _history.add(current);

    if (!byUser && _mode == QueueMode.repeatOne) {
      await _primary.seek(Duration.zero);
      await _primary.play();
      return;
    }

    if (_cursor + 1 >= _order.length) {
      switch (_mode) {
        case QueueMode.sequential:
          if (!byUser) {
            _state.add(state.copyWith(status: PlaybackStatus.completed));
            return;
          }
          _cursor = 0;
        case QueueMode.repeatAll || QueueMode.repeatOne:
          _cursor = 0;
        case QueueMode.shuffle:
          _rebuildOrder(); // reshuffle, start over
          _cursor = 0;
      }
    } else {
      _cursor++;
    }
    await _playCurrent();
  }

  /// Pops history when available (correct for shuffle); restarts the
  /// track when it's more than 3 seconds in.
  Future<void> previous() async {
    await _abortCrossfade();
    if (_primary.position > const Duration(seconds: 3) || _history.isEmpty) {
      await _primary.seek(Duration.zero);
      return;
    }
    final target = _history.removeLast();
    final sourceIndex = _source.indexWhere((t) => t.id == target.id);
    if (sourceIndex == -1) return;
    final orderIndex = _order.indexOf(sourceIndex);
    if (orderIndex != -1) {
      _cursor = orderIndex;
    }
    await _playCurrent();
  }

  void setMode(QueueMode mode) {
    if (mode == _mode) return;
    final wasShuffle = _mode == QueueMode.shuffle;
    _mode = mode;
    if (mode == QueueMode.shuffle || wasShuffle) {
      _rebuildOrder(anchor: _order.isEmpty ? 0 : _order[_cursor]);
    }
    _state.add(state.copyWith(queueMode: mode));
  }

  Future<void> stop() async {
    await _abortCrossfade();
    await _primary.stop();
    _state.add(state.copyWith(status: PlaybackStatus.idle));
  }

  /// For the sleep timer's fade-out (M11).
  Future<void> setVolume(double volume) => _primary.setVolume(volume);

  Future<void> dispose() async {
    _crossfadeTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    await _primary.dispose();
    await _incoming?.dispose();
    await _state.close();
    await _position.close();
    await trackStarted.close();
  }

  // --- Crossfade ---

  void _maybeStartCrossfade(Duration pos) {
    if (_crossfading ||
        crossfadeDuration == Duration.zero ||
        !_primary.playing ||
        pauseAtTrackEnd ||
        _mode == QueueMode.repeatOne) {
      return;
    }
    final duration = _primary.duration;
    if (duration == null || duration == Duration.zero) return;
    if (duration - pos > crossfadeDuration) return;

    // Where would we land? Only crossfade when there's a definite next.
    int? nextCursor;
    if (_cursor + 1 < _order.length) {
      nextCursor = _cursor + 1;
    } else if (_mode == QueueMode.repeatAll) {
      nextCursor = 0;
    }
    if (nextCursor == null) return;

    _startCrossfade(nextCursor);
  }

  Future<void> _startCrossfade(int nextCursor) async {
    final track = _source[_order[nextCursor]];
    final incoming = AudioPlayer();
    _incoming = incoming; // claims the crossfade slot immediately
    _pendingCursor = nextCursor;
    _pendingTrack = track;

    try {
      await incoming.setFilePath(track.filePath);
    } catch (_) {
      await incoming.dispose();
      _incoming = null;
      return;
    }
    await incoming.setVolume(0);
    unawaited(incoming.play());

    final total = crossfadeDuration.inMilliseconds;
    final stopwatch = Stopwatch()..start();
    _crossfadeTimer =
        Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final t =
          (stopwatch.elapsedMilliseconds / total).clamp(0.0, 1.0);
      // Smoothstep — equal-power feel, no mid-fade loudness bump.
      final e = t * t * (3 - 2 * t);
      _primary.setVolume(1 - e);
      incoming.setVolume(e);
      _state.add(state.copyWith(crossfadeProgress: t));
      if (t >= 1) _finishCrossfade();
    });
  }

  /// The incoming player takes over as primary.
  void _finishCrossfade() {
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
    final old = _primary;
    final track = _pendingTrack!;

    final current = _currentTrack;
    if (current != null) _history.add(current);

    _primary = _incoming!;
    _incoming = null;
    _cursor = _pendingCursor!;
    _pendingCursor = null;
    _pendingTrack = null;

    _wirePlayer(_primary);
    old.dispose();
    _primary.setVolume(1);

    _state.add(state.copyWith(
      currentTrack: track,
      queue: [for (final i in _order) _source[i]],
      status: PlaybackStatus.playing,
      duration: _primary.duration ?? track.duration,
      clearCrossfade: true,
    ));
    trackStarted.add(track);
  }

  /// Any manual action cancels an in-flight crossfade.
  Future<void> _abortCrossfade() async {
    if (!_crossfading) return;
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
    final incoming = _incoming;
    _incoming = null;
    _pendingCursor = null;
    _pendingTrack = null;
    await incoming?.dispose();
    await _primary.setVolume(1);
    _state.add(state.copyWith(clearCrossfade: true));
  }

  // --- Internals ---

  /// Builds [_order]. [anchor] is an index into [_source] that must end
  /// up at the cursor (the track the user tapped).
  void _rebuildOrder({int? anchor}) {
    final indices = List.generate(_source.length, (i) => i);
    if (_mode == QueueMode.shuffle) {
      indices.shuffle(Random());
      if (anchor != null) {
        indices.remove(anchor);
        indices.insert(0, anchor);
      }
      _cursor = 0;
    } else {
      _cursor = anchor ?? 0;
    }
    _order = indices;
  }

  Future<void> _onTrackCompleted() async {
    // The old track can run out a beat before the crossfade ramp ends —
    // hand over immediately instead of double-advancing.
    if (_crossfading) {
      _finishCrossfade();
      return;
    }
    if (pauseAtTrackEnd) {
      pauseAtTrackEnd = false;
      await _primary.pause();
      await _primary.seek(Duration.zero);
      _state.add(state.copyWith(status: PlaybackStatus.paused));
      onSleepTimerFired?.call();
      return;
    }
    await next(byUser: false);
  }

  /// Notifies the sleep timer that end-of-track mode completed.
  void Function()? onSleepTimerFired;

  Future<void> _playCurrent() async {
    final track = _currentTrack;
    if (track == null) return;
    _state.add(state.copyWith(
      currentTrack: track,
      queue: [for (final i in _order) _source[i]],
      status: PlaybackStatus.loading,
    ));
    try {
      await _primary.setFilePath(track.filePath);
      await _primary.setVolume(1);
      await _primary.play();
      trackStarted.add(track);
    } catch (_) {
      // Unreadable file (deleted, moved) — skip forward.
      await next(byUser: false);
    }
  }
}
