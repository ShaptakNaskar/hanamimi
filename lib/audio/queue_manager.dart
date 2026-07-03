import 'dart:async';
import 'dart:math';

import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../library/models/track.dart';
import 'models/audio_state.dart';
import 'models/queue_mode.dart';

/// Owns the players and the queue. The two-player field layout exists
/// from day one so the crossfade milestone (M9) can slot in without a
/// rework — until then only [_primary] is used.
class QueueManager {
  QueueManager() {
    _primary = AudioPlayer();
    _wirePlayer(_primary);
  }

  late AudioPlayer _primary;
  AudioPlayer? _incoming; // non-null only during a crossfade (M9)

  final _state = BehaviorSubject<AudioState>.seeded(const AudioState());
  Stream<AudioState> get stateStream => _state.stream;
  AudioState get state => _state.value;

  Stream<Duration> get positionStream => _primary.positionStream;

  /// Fires with a track every time playback of it begins (for play counts).
  final trackStarted = StreamController<Track>.broadcast();

  List<Track> _source = [];
  List<int> _order = [];
  int _cursor = 0;
  final List<Track> _history = [];
  QueueMode _mode = QueueMode.sequential;

  StreamSubscription<ProcessingState>? _completionSub;

  void _wirePlayer(AudioPlayer player) {
    _completionSub?.cancel();
    _completionSub = player.processingStateStream.listen((ps) {
      if (ps == ProcessingState.completed) _onTrackCompleted();
    });

    player.playingStream.listen((_) => _emitStatus(player));
    player.durationStream.listen((d) {
      if (d != null) _state.add(state.copyWith(duration: d));
    });
    player.androidAudioSessionIdStream.listen((id) {
      if (id != null) _state.add(state.copyWith(audioSessionId: id));
    });
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
    _source = List.of(tracks);
    if (mode != null) _mode = mode;
    _rebuildOrder(anchor: startIndex);
    _history.clear();
    await _playCurrent();
  }

  Future<void> play() => _primary.play();

  Future<void> pause() => _primary.pause();

  Future<void> seek(Duration position) => _primary.seek(position);

  Future<void> next({bool byUser = true}) async {
    if (_order.isEmpty) return;
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
    await _primary.stop();
    _state.add(state.copyWith(status: PlaybackStatus.idle));
  }

  Future<void> dispose() async {
    await _completionSub?.cancel();
    await _primary.dispose();
    await _incoming?.dispose();
    await _state.close();
    await trackStarted.close();
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

  Future<void> _onTrackCompleted() => next(byUser: false);

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
      await _primary.play();
      trackStarted.add(track);
    } catch (_) {
      // Unreadable file (deleted, moved) — skip forward.
      await next(byUser: false);
    }
  }
}
