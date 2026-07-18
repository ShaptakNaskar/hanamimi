import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../library/models/track.dart';
import 'models/audio_state.dart';
import 'models/playback_session.dart';
import 'models/queue_mode.dart';
import 'slow_dance.dart';

/// Owns the players and the queue. Crossfade uses the two-player model
/// from ARCHITECTURE.md §6.1: [_primary] is audible; [_incoming] exists
/// only while a crossfade is running, then becomes the new primary.
class QueueManager {
  QueueManager() {
    // handleInterruptions:false — same engine-owns-everything stance as
    // the Android edition; the browser has no audio-focus arbitration
    // for us to manage anyway.
    _primary = AudioPlayer(handleInterruptions: false);
    _wirePlayer(_primary);
    _startPositionHeartbeat();
  }

  /// Self-healing seek bar. just_audio's positionStream can go stale after
  /// the process is frozen/backgrounded (OEM battery managers) and then
  /// resumed — audio keeps playing but the stream stops ticking, so the
  /// bar freezes (sometimes stuck at the end). This independent 250 ms
  /// heartbeat republishes the player's own computed position while
  /// playing, so the bar stays live regardless of the plugin stream's
  /// health. `player.position` self-advances from the last update, so this
  /// is cheap and accurate.
  Timer? _posHeartbeat;
  void _startPositionHeartbeat() {
    _posHeartbeat = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_crossfading) {
        if (_primary.playing) _position.add(_primary.position);
        // A file on disk has nothing to buffer, but just_audio still
        // reports a partial decode-ahead as "buffered", which drew a
        // pointless buffer overlay on the seek bar. Base Hanamimi is
        // local-only, so zero it whenever a track is loaded.
        _buffered.add(_currentTrack?.filePath != null
            ? Duration.zero
            : _primary.bufferedPosition);
      }
    });
  }

  /// Called when the app returns to the foreground. Snaps the seek bar to
  /// the player's true position immediately (it may have drifted or stalled
  /// while backgrounded) so the UI reflects reality without waiting for the
  /// next heartbeat.
  void onAppResumed() {
    _position.add(_primary.position);
    _emitStatus(_primary);
  }

  late AudioPlayer _primary;
  AudioPlayer? _incoming;

  /// User setting; Duration.zero = crossfade off.
  Duration crossfadeDuration = Duration.zero;

  /// Slow Dance (3.0 #4): when set, crossfades are *sighted* — the
  /// planner reads the outgoing track's cached loudness frames and says
  /// where its energy dies and how long the fade should be. Null plan
  /// (no cache yet) falls back to the classic timer. Pushed by the
  /// slow-dance provider; null = feature off.
  Future<SlowDancePlan?> Function(Track track)? slowDancePlanner;
  SlowDancePlan? _dancePlan;
  int? _dancePlanTrackId;
  bool _dancePlanLoading = false;

  /// Night Mode's gentler master gain (3.0). Every volume write — sleep
  /// fade, ducking, crossfade ramps — is a 0–1 *intent*; the gain scales
  /// it at the port boundary so the systems compose instead of fighting
  /// over the knob.
  double _gainScale = 1.0;
  double _volumeIntent = 1.0;

  Future<void> setGainScale(double gain) async {
    if (gain == _gainScale) return;
    _gainScale = gain;
    if (!_crossfading) await _primary.setVolume(_volumeIntent * gain);
  }

  Future<void> _setPrimaryVolume(double intent) {
    _volumeIntent = intent;
    return _primary.setVolume(intent * _gainScale);
  }

  /// Smart shuffle (M38c): when set, shuffle orders are sampled with
  /// probability ∝ weight(track) instead of uniformly — favorites come
  /// up sooner, skipped tracks later, nothing is excluded. Pushed by
  /// the reco provider; null = classic uniform shuffle.
  double Function(Track track)? shuffleWeight;

  /// Sleep timer "end of track" mode: finish the current song, then
  /// pause instead of advancing.
  bool pauseAtTrackEnd = false;

  Timer? _crossfadeTimer;
  int? _pendingCursor;
  Track? _pendingTrack;
  bool get _crossfading => _incoming != null;

  /// Live crossfade progress, raw 0–1, updated by the ramp timer.
  /// Deliberately NOT part of [AudioState]: pushing per-tick progress
  /// through the state stream re-emitted the whole snapshot at 60 Hz for
  /// the entire fade, rebuilding every stateStream listener — all
  /// screens, the app-wide theme lerp, the Android media notification —
  /// and froze the UI around every transition. The few widgets that
  /// animate the dissolve listen to this directly; everyone else only
  /// sees the start/end state emissions.
  final ValueNotifier<double> crossfadeT = ValueNotifier(0.0);

  /// The incoming player's live position during a crossfade (it's been
  /// playing since the fade began) — for the seek bar's roll toward the
  /// new song and the visualizer's blend. Zero outside a fade.
  Duration get crossfadeIncomingPosition =>
      _incoming?.position ?? Duration.zero;

  final _state = BehaviorSubject<AudioState>.seeded(const AudioState());
  Stream<AudioState> get stateStream => _state.stream;
  AudioState get state => _state.value;

  /// Stable across player swaps (a raw player stream would go dead when
  /// the primary is disposed after a crossfade).
  final _position = BehaviorSubject<Duration>.seeded(Duration.zero);
  Stream<Duration> get positionStream => _position.stream;
  Duration get position => _position.value;

  /// Buffered position of the primary player, for the seek bar's buffer
  /// overlay.
  final _buffered = BehaviorSubject<Duration>.seeded(Duration.zero);
  Stream<Duration> get bufferedStream => _buffered.stream;

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
    ProcessingState? lastPs;
    _subs = [
      // Transition-edge only: the backend can re-emit `completed` on
      // unrelated player events while still sitting at the end, and
      // each duplicate used to re-run the completion path.
      player.processingStateStream.listen((ps) {
        if (ps == ProcessingState.completed &&
            lastPs != ProcessingState.completed) {
          _onTrackCompleted();
        }
        lastPs = ps;
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

  Future<void> play() => _primary.play();

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
      await _replacePrimary();
      await _setSource(_primary, track);
      await _setPrimaryVolume(1);
      if (session.position > Duration.zero) {
        await _primary.seek(session.position);
      }
      _position.add(session.position);
      if (autoPlay) {
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
      _repeatRestartedAt
        ..reset()
        ..start();
      await _primary.seek(Duration.zero);
      await _primary.play();
      // Each loop is a fresh listen: without this, a song on repeat for
      // an hour counted as ONE song in stats/history (the restart path
      // skips _playCurrent, which normally announces the start).
      if (current != null) trackStarted.add(current);
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

  /// Drag-reorder in the queue sheet: moves the play-order entry at
  /// [oldIndex] to [newIndex]. The current track stays current — the
  /// cursor is re-found by its entry, since _order is a permutation of
  /// distinct source indices.
  void moveInQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _order.length) return;
    newIndex = newIndex.clamp(0, _order.length - 1);
    if (oldIndex == newIndex) return;
    final currentEntry = _order.isEmpty ? null : _order[_cursor];
    final entry = _order.removeAt(oldIndex);
    _order.insert(newIndex, entry);
    if (currentEntry != null) _cursor = _order.indexOf(currentEntry);
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
    _state.add(state.copyWith(status: PlaybackStatus.idle));
  }

  /// Stop AND forget what was playing — empties the queue and clears the
  /// current track, so the mini player dismisses and the mascot returns
  /// to her eyes-open idle. The saved-session pref is cleared separately
  /// by the caller so a cleared player doesn't re-offer resume.
  Future<void> clear() async {
    await _abortCrossfade();
    await _primary.stop();
    _source = [];
    _order = [];
    _cursor = 0;
    _history.clear();
    _position.add(Duration.zero);
    _state.add(state.copyWith(
      clearCurrentTrack: true,
      queue: const [],
      status: PlaybackStatus.idle,
      duration: Duration.zero,
      clearCrossfade: true,
    ));
  }

  /// For the sleep timer's fade-out (M11).
  Future<void> setVolume(double volume) => _setPrimaryVolume(volume);

  Future<void> dispose() async {
    _crossfadeTimer?.cancel();
    crossfadeT.dispose();
    _posHeartbeat?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    await _primary.dispose();
    await _incoming?.dispose();
    await _state.close();
    await _position.close();
    await _buffered.close();
    await trackStarted.close();
  }

  // --- Crossfade ---

  void _maybeStartCrossfade(Duration pos) {
    final sighted = slowDancePlanner != null;
    if (_crossfading ||
        (!sighted && crossfadeDuration == Duration.zero) ||
        !_primary.playing ||
        pauseAtTrackEnd ||
        _mode == QueueMode.repeatOne) {
      return;
    }
    final duration = _primary.duration;
    if (duration == null || duration == Duration.zero) return;

    // Slow Dance: read the plan for the current track ahead of the
    // window so it's ready by the time the fade could start.
    final current = _currentTrack;
    if (sighted &&
        current != null &&
        _dancePlanTrackId != current.id &&
        !_dancePlanLoading &&
        duration - pos < const Duration(seconds: 60)) {
      _dancePlanLoading = true;
      slowDancePlanner!(current).then((plan) {
        _dancePlan = plan;
        _dancePlanTrackId = current.id;
        _dancePlanLoading = false;
      });
    }
    final plan =
        (sighted && current != null && _dancePlanTrackId == current.id)
            ? _dancePlan
            : null;

    // Sighted but planless (first play, undecodable file): a gentle
    // default so Slow Dance works standalone with crossfade off.
    final fade = plan?.fade ??
        (crossfadeDuration == Duration.zero
            ? const Duration(seconds: 6)
            : crossfadeDuration);
    final startAt = plan?.startAt ?? duration - fade;
    if (startAt - pos > Duration.zero) return;

    // Where would we land? Only crossfade when there's a definite next.
    int? nextCursor;
    if (_cursor + 1 < _order.length) {
      nextCursor = _cursor + 1;
    } else if (_mode == QueueMode.repeatAll) {
      nextCursor = 0;
    }
    if (nextCursor == null) return;

    _startCrossfade(nextCursor, fade);
  }

  Future<void> _startCrossfade(int nextCursor, Duration fade) async {
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

    // Announce the incoming track ONCE so the UI can wipe art/title
    // from the outgoing one to this; the per-tick progress rides
    // [crossfadeT], not the state stream.
    crossfadeT.value = 0;
    _state.add(state.copyWith(crossfadeIncomingTrack: track));

    final total = fade.inMilliseconds;
    final stopwatch = Stopwatch()..start();
    _crossfadeTimer =
        Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final t =
          (stopwatch.elapsedMilliseconds / total).clamp(0.0, 1.0);
      // Smoothstep — equal-power feel, no mid-fade loudness bump.
      final e = t * t * (3 - 2 * t);
      _primary.setVolume((1 - e) * _gainScale);
      incoming.setVolume(e * _gainScale);
      crossfadeT.value = t;
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
    _setPrimaryVolume(1);

    // Republish the incoming player's real position BEFORE the clearing
    // emission. Otherwise positionProvider still holds the outgoing
    // player's near-end value until the newly-wired positionStream fires
    // its first tick — and for that gap the seek bar renders that stale
    // near-end position against the NEW (just-emitted) duration, snapping
    // to ~end for a frame before dropping back (user-reported "jump").
    _position.add(_primary.position);

    _state.add(state.copyWith(
      currentTrack: track,
      queue: [for (final i in _order) _source[i]],
      status: PlaybackStatus.playing,
      duration: _primary.duration ?? track.duration,
      clearCrossfade: true,
    ));
    // Reset AFTER the clearing emission: listeners gate on the state's
    // incoming track, so none can mistake this for a rewound fade.
    crossfadeT.value = 0;
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
    await _setPrimaryVolume(1);
    _state.add(state.copyWith(clearCrossfade: true));
    crossfadeT.value = 0;
  }

  // --- Internals ---

  /// Builds [_order]. [anchor] is an index into [_source] that must end
  /// up at the cursor (the track the user tapped).
  void _rebuildOrder({int? anchor}) {
    var indices = List.generate(_source.length, (i) => i);
    if (_mode == QueueMode.shuffle) {
      final weigh = shuffleWeight;
      if (weigh == null) {
        indices.shuffle(Random());
      } else {
        indices = _weightedOrder(indices, weigh);
      }
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

  /// Weighted sample without replacement: each draw picks a remaining
  /// index with probability ∝ its track's weight.
  List<int> _weightedOrder(
      List<int> indices, double Function(Track) weigh) {
    final rng = Random();
    final remaining = List.of(indices);
    final weights = [
      for (final i in remaining) max(weigh(_source[i]), 1e-6),
    ];
    final out = <int>[];
    var total = weights.fold(0.0, (a, b) => a + b);
    while (remaining.isNotEmpty) {
      var roll = rng.nextDouble() * total;
      var pick = remaining.length - 1;
      for (var j = 0; j < remaining.length; j++) {
        roll -= weights[j];
        if (roll <= 0) {
          pick = j;
          break;
        }
      }
      out.add(remaining.removeAt(pick));
      total -= weights.removeAt(pick);
    }
    return out;
  }

  /// Started on each repeat-one restart; see the guard below.
  final _repeatRestartedAt = Stopwatch();

  Future<void> _onTrackCompleted() async {
    // The old track can run out a beat before the crossfade ramp ends —
    // hand over immediately instead of double-advancing.
    if (_crossfading) {
      _finishCrossfade();
      return;
    }
    // Repeat-one restarts by seeking the SAME source back to zero. The
    // player can surface its end-of-track state again before the seek
    // lands — which re-restarted the song ("plays for a second,
    // restarts", user-reported, intermittent). A real re-completion
    // can't happen this soon after a restart unless the track is
    // seconds long, so ignore completions inside the window.
    if (_mode == QueueMode.repeatOne &&
        _repeatRestartedAt.isRunning &&
        _repeatRestartedAt.elapsed < const Duration(seconds: 5) &&
        (_primary.duration ?? Duration.zero) >
            const Duration(seconds: 10)) {
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

  /// Bumped on every play request. A slow load that loses this race
  /// (the user skipped again before it finished) must swallow its own
  /// failure: spamming previous/next interrupts each in-flight
  /// setAudioSource, and treating those aborts as unreadable files
  /// caused spurious auto-skips (user-reported on plus).
  int _playGeneration = 0;

  /// just_audio wraps every source in the player's internal playlist,
  /// whose id is stable for the player's lifetime — and just_audio_web
  /// caches platform source-players by that id, ignoring the fresh
  /// children later setAudioSource calls bring. Net effect: the SECOND
  /// load on the same player keeps playing the FIRST song forever
  /// (title/FFT advance, audio doesn't — user-reported). A fresh player
  /// per load sidesteps the stale cache; it's the same lifecycle the
  /// crossfade path already uses for its incoming player, which is why
  /// crossfades never showed the bug.
  Future<void> _replacePrimary() async {
    final old = _primary;
    _primary = AudioPlayer(handleInterruptions: false);
    _wirePlayer(_primary);
    await old.dispose();
  }

  Future<void> _playCurrent() async {
    final track = _currentTrack;
    if (track == null) return;
    final generation = ++_playGeneration;
    _state.add(state.copyWith(
      currentTrack: track,
      queue: [for (final i in _order) _source[i]],
      status: PlaybackStatus.loading,
    ));
    try {
      await _replacePrimary();
      if (generation != _playGeneration) return;
      await _setSource(_primary, track);
      if (generation != _playGeneration) return; // superseded mid-load
      await _setPrimaryVolume(1);
      await _primary.play();
      trackStarted.add(track);
    } catch (_) {
      // A newer request interrupted this load — its failure is noise,
      // not a broken track; the newer request owns the outcome.
      if (generation != _playGeneration) return;
      // Unreadable file (deleted, moved) — skip forward.
      await next(byUser: false);
    }
  }

  /// Web edition: every track is a blob URL minted from the picked
  /// file — the HTML5 audio backend streams it without an upload.
  static Future<Duration?> _setSource(AudioPlayer player, Track track) =>
      player.setAudioSource(AudioSource.uri(Uri.parse(track.filePath)));
}
