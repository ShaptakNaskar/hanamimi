import 'dart:async';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../library/models/track.dart';
import 'models/audio_state.dart';
import 'models/playback_session.dart';
import 'models/queue_mode.dart';

/// Owns the players and the queue. Crossfade uses the two-player model
/// from ARCHITECTURE.md §6.1: [_primary] is audible; [_incoming] exists
/// only while a crossfade is running, then becomes the new primary.
class QueueManager {
  QueueManager() {
    // handleInterruptions:false — with the default (true), every player
    // manages the shared audio_session singleton itself, and disposing a
    // crossfade player deactivates the session, ABANDONING the app's
    // audio focus while music still plays. From then on calls never
    // paused us (the bug). The session must have exactly one owner: the
    // engine.
    _primary = AudioPlayer(handleInterruptions: false);
    _wirePlayer(_primary);
    unawaited(_initAudioSession());
  }

  AudioSession? _session;

  /// Whether playback was ongoing when an interruption (call) began, so
  /// we only auto-resume something we actually paused.
  bool _interrupted = false;

  /// One central audio-focus owner. audio_service activates the session
  /// when playback starts; we listen on the same singleton for the
  /// interruption events the OS sends the focus holder.
  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      _session = session;
      await session.configure(const AudioSessionConfiguration.music());
      session.interruptionEventStream.listen(_onInterruption);
      // Headphones unplugged / BT disconnect → pause (don't blast the
      // speaker), the standard "becoming noisy" behaviour.
      session.becomingNoisyEventStream.listen((_) {
        if (_primary.playing) pause();
      });
    } catch (_) {
      // Focus config failed — playback still works, calls just won't
      // auto-pause. Nothing sensible to do about it here.
    }
  }

  /// Ensures the session (and with it the app's audio focus request) is
  /// active before playback starts. Same singleton audio_service uses,
  /// so this never fights it. Idempotent.
  Future<void> _activateFocus() async {
    try {
      await _session?.setActive(true);
    } catch (_) {}
  }

  void _onInterruption(AudioInterruptionEvent event) {
    if (event.begin) {
      switch (event.type) {
        case AudioInterruptionType.duck:
          // Nav prompt / notification — duck rather than silence.
          if (!_crossfading) _primary.setVolume(0.3);
        case AudioInterruptionType.pause:
        case AudioInterruptionType.unknown:
          // A call or another media app took focus — pause, remember.
          _interrupted = _primary.playing;
          if (_interrupted) pause();
      }
    } else {
      switch (event.type) {
        case AudioInterruptionType.duck:
          if (!_crossfading) _primary.setVolume(1);
        case AudioInterruptionType.pause:
          // Transient loss ended (call over) — resume what we paused.
          if (_interrupted) play();
          _interrupted = false;
        case AudioInterruptionType.unknown:
          // Permanent loss — stay paused.
          _interrupted = false;
      }
    }
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
  Duration get position => _position.value;

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
      // playerStateStream fires on BOTH playing and processingState
      // changes. playingStream alone misses track switches while already
      // playing (playing stays true), leaving the UI stuck on "paused".
      player.playerStateStream.listen((_) => _emitStatus(player)),
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

  Future<void> play() async {
    await _activateFocus();
    await _primary.play();
  }

  Future<void> pause() async {
    await _abortCrossfade();
    await _primary.pause();
  }

  /// Snapshot of the current queue + position for resume-on-launch.
  /// Null when nothing is loaded (so persistence never clobbers a saved
  /// session with an empty startup state).
  PlaybackSession? snapshotSession() {
    if (_order.isEmpty || _crossfading) return null;
    return PlaybackSession(
      queue: [for (final i in _order) _source[i]],
      index: _cursor,
      position: position,
      mode: _mode,
    );
  }

  /// Reloads a saved session at [position]. The queue is restored in the
  /// exact order it was saved (identity order over the persisted list),
  /// so a shuffled queue comes back as-heard. [autoPlay] starts playback
  /// (the ticker's PLAY action); otherwise it's held paused.
  Future<void> restoreSession(PlaybackSession session,
      {bool autoPlay = false}) async {
    await _abortCrossfade();
    _source = List.of(session.queue);
    _order = List.generate(_source.length, (i) => i);
    _mode = session.mode;
    _cursor = session.index.clamp(0, _order.length - 1);
    _history.clear();

    final track = _currentTrack;
    if (track == null) return;
    _state.add(state.copyWith(
      currentTrack: track,
      queue: [for (final i in _order) _source[i]],
      queueMode: _mode,
      status: PlaybackStatus.loading,
    ));
    try {
      await _setSource(_primary, track);
      await _primary.setVolume(1);
      if (session.position > Duration.zero) {
        await _primary.seek(session.position);
      }
      _position.add(session.position);
      if (autoPlay) {
        await _activateFocus();
        await _primary.play();
      }
      // Without autoPlay, _emitStatus (from the ready event) settles on
      // paused since we never call play().
    } catch (_) {
      // File gone/moved — leave it idle; the user can retry.
      _state.add(state.copyWith(status: PlaybackStatus.idle));
    }
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

  /// Restarts the track when it's more than 3 seconds in. Otherwise:
  /// shuffle retraces the actual play history (so "previous" undoes
  /// the random order you heard); every other mode steps back through
  /// the queue itself — including songs before the one you started
  /// from, which history alone can never reach.
  Future<void> previous() async {
    await _abortCrossfade();
    if (_primary.position > const Duration(seconds: 3)) {
      await _primary.seek(Duration.zero);
      return;
    }

    if (_mode == QueueMode.shuffle && _history.isNotEmpty) {
      final target = _history.removeLast();
      final sourceIndex = _source.indexWhere((t) => t.id == target.id);
      final orderIndex =
          sourceIndex == -1 ? -1 : _order.indexOf(sourceIndex);
      if (orderIndex != -1) {
        _cursor = orderIndex;
        await _playCurrent();
        return;
      }
      // Track vanished from the queue — fall through to queue order.
    }

    if (_cursor > 0) {
      _cursor--;
    } else if (_mode == QueueMode.repeatAll ||
        _mode == QueueMode.repeatOne) {
      _cursor = _order.length - 1; // wrap like next() does
    } else {
      await _primary.seek(Duration.zero); // start of the queue
      return;
    }
    await _playCurrent();
  }

  /// Appends a track to the end of the play order (swipe action).
  /// With nothing loaded, starts playing it instead.
  Future<void> addToQueue(Track track) async {
    if (_source.isEmpty) {
      await loadQueue([track]);
      return;
    }
    _source.add(track);
    _order.add(_source.length - 1);
    _state.add(state.copyWith(queue: [for (final i in _order) _source[i]]));
  }

  /// Jump straight to a position in the play order (queue sheet).
  Future<void> jumpToQueueIndex(int index) async {
    if (index < 0 || index >= _order.length) return;
    await _abortCrossfade();
    final current = _currentTrack;
    if (current != null) _history.add(current);
    _cursor = index;
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
    try {
      await _session?.setActive(false); // release focus — we're done
    } catch (_) {}
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
    final incoming = AudioPlayer(handleInterruptions: false);
    _incoming = incoming; // claims the crossfade slot immediately
    _pendingCursor = nextCursor;
    _pendingTrack = track;

    try {
      await _setSource(incoming, track);
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
      await _setSource(_primary, track);
      await _primary.setVolume(1);
      await _activateFocus();
      await _primary.play();
      trackStarted.add(track);
    } catch (_) {
      // Unreadable file (deleted, moved) — skip forward.
      await next(byUser: false);
    }
  }

  /// Tracks opened from other apps carry a content:// uri instead of a
  /// filesystem path.
  static Future<Duration?> _setSource(AudioPlayer player, Track track) =>
      track.filePath.startsWith('content://')
          ? player.setAudioSource(
              AudioSource.uri(Uri.parse(track.filePath)))
          : player.setFilePath(track.filePath);
}
