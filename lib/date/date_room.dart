import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../audio/models/audio_state.dart';
import '../library/models/track.dart';
import '../online/models/online_search_result.dart';
import '../providers/audio_provider.dart';
import '../providers/leaderboard_provider.dart';
import '../providers/library_provider.dart';
import '../providers/theme_provider.dart';
import 'ably_transport.dart';

/// Long-Distance Date Mode (3.0 #6, plus only): two Hanamimi instances,
/// one shared queue, lockstep playback over a 6-character room code. No
/// accounts, no chat.
///
/// Transport is Ably (SSE receive + REST publish via [AblyTransport] —
/// the 2.5s Mongo poll this replaced delivered actions a poll-cycle
/// late and false "partner stepped away"s, user-tested). Two channels
/// per room: `hanamimi:st:CODE` carries queue/control events,
/// `hanamimi:hb:CODE` the 5s presence heartbeats. The Mongo room doc
/// remains the durable snapshot — room codes, membership, and the
/// queue for late joiners — refreshed by a slow keepalive sync that
/// doubles as a degraded fallback when Ably is unreachable.
///
/// Playback intent (an "anchor": position + playing + when it was set)
/// comes from control events; both clients drift-correct toward the
/// same anchor, and "you wait for each other" is a *local* reaction to
/// the partner's heartbeat stall flag.
const _apiBase = 'https://sappy-dir.vercel.app/api/hanamimi';

class DateRoomState {
  const DateRoomState({
    this.code,
    this.shared = false,
    this.partnerJoined = false,
    this.partnerOnline = false,
    this.partnerStalled = false,
    this.partnerBufferedMs = 0,
    this.partnerPositionMs = 0,
    this.pausedForPartner = false,
    this.isDj = false,
    this.following = true,
    this.partnerFollowing = true,
    this.realtime = false,
    this.error,
  });

  /// Null = not in a room.
  final String? code;

  /// True once a queue lives in the room (shared by us or them).
  final bool shared;

  final bool partnerJoined;
  final bool partnerOnline;
  final bool partnerStalled;
  final int partnerBufferedMs;
  final int partnerPositionMs;

  /// We're holding playback because the partner is buffering.
  final bool pausedForPartner;

  /// True when *we* are the DJ — the one whose playback is the shared
  /// timeline. Exactly one side is the DJ; the other mirrors it. Either
  /// side can [DateRoomNotifier.takeOver] to become the DJ (Jam-style).
  final bool isDj;

  /// For a non-DJ: whether we're in lockstep with the DJ (true) or have
  /// detached to listen solo (false) after touching our own transport.
  /// [DateRoomNotifier.rejoin] snaps back. The DJ is always "leading",
  /// so this stays true for them.
  final bool following;

  /// The partner's [following] flag, learned from their heartbeat — the
  /// DJ only waits on a buffering partner who is actually in lockstep.
  final bool partnerFollowing;

  /// Live Ably connection (false = degraded slow-poll fallback).
  final bool realtime;

  final String? error;

  bool get inRoom => code != null;

  /// Non-DJ, detached to listen on their own — the Rejoin state.
  bool get solo => !isDj && !following;

  DateRoomState copyWith({
    String? code,
    bool clearCode = false,
    bool? shared,
    bool? partnerJoined,
    bool? partnerOnline,
    bool? partnerStalled,
    int? partnerBufferedMs,
    int? partnerPositionMs,
    bool? pausedForPartner,
    bool? isDj,
    bool? following,
    bool? partnerFollowing,
    bool? realtime,
    String? error,
    bool clearError = false,
  }) =>
      DateRoomState(
        code: clearCode ? null : code ?? this.code,
        shared: shared ?? this.shared,
        partnerJoined: partnerJoined ?? this.partnerJoined,
        partnerOnline: partnerOnline ?? this.partnerOnline,
        partnerStalled: partnerStalled ?? this.partnerStalled,
        partnerBufferedMs: partnerBufferedMs ?? this.partnerBufferedMs,
        partnerPositionMs: partnerPositionMs ?? this.partnerPositionMs,
        pausedForPartner: pausedForPartner ?? this.pausedForPartner,
        isDj: isDj ?? this.isDj,
        following: following ?? this.following,
        partnerFollowing: partnerFollowing ?? this.partnerFollowing,
        realtime: realtime ?? this.realtime,
        error: clearError ? null : error ?? this.error,
      );
}

class DateRoomNotifier extends Notifier<DateRoomState> {
  AblyTransport? _transport;
  StreamSubscription? _msgSub;
  StreamSubscription? _connSub;
  Timer? _heartbeat;
  Timer? _slowSync;
  StreamSubscription? _stateSub;
  StreamSubscription? _posSub;

  var _queueRev = -1;
  var _applyingRemote = false;
  var _syncInFlight = false;
  var _sharing = false;

  /// The materialized room queue (real library rows) in room order.
  List<Track> _roomTracks = const [];

  /// The current playback intent both sides converge on: where the
  /// music should be ([_anchorPosMs] as of [_anchorAt]) and whether
  /// it's moving. Updated by every control event, ours included.
  var _anchorPosMs = 0;
  DateTime _anchorAt = DateTime.now();
  var _anchorPlaying = false;
  var _anchorIndex = 0;

  DateTime? _partnerLastSeen;

  /// Leadership term — a Raft-style monotonic counter that decides who's
  /// the DJ without trusting either device's wall clock. Every takeover
  /// bumps it past what it has seen; on a conflict the higher term wins
  /// (ties broken by memberId), so a fresh takeover always beats a stale
  /// claim and both sides converge on one DJ. The creator opens at 1,
  /// the joiner at 0.
  var _djTerm = 0;
  var _partnerTerm = 0;
  var _partnerIsDj = false;

  /// We only wait on the partner's buffer while we're actually locked to
  /// them: a follower waits for its DJ; the DJ waits for a following
  /// partner. A solo listener neither waits nor is waited for.
  bool get _lockstep =>
      state.partnerOnline &&
      (state.isDj ? state.partnerFollowing : state.following);

  /// When we last drove a control locally. The Mongo snapshot lags our
  /// own fire-and-forget writes, so a slow-sync tick landing right after
  /// a local action must not read the stale doc back and revert us.
  DateTime _lastLocalControlAt =
      DateTime.fromMillisecondsSinceEpoch(0);

  /// Engine facts as of the last event, for local-action detection.
  bool? _lastKnownPlaying;
  int? _lastKnownTrackId;
  Duration _lastPos = Duration.zero;

  String get _memberId =>
      StatsClientId.get(ref.read(sharedPrefsProvider));

  String get _stChannel => 'hanamimi:st:${state.code}';
  String get _hbChannel => 'hanamimi:hb:${state.code}';

  @override
  DateRoomState build() {
    ref.onDispose(_stopSync);
    return const DateRoomState();
  }

  // --- Room lifecycle ---

  Future<bool> createRoom() async {
    try {
      final res = await _post('/room', {'memberId': _memberId});
      if (res == null) return false;
      // The creator opens as DJ (term 1); the joiner arrives as a
      // follower (term 0) and mirrors whatever's already playing.
      _djTerm = 1;
      state = DateRoomState(code: res['code'] as String?, isDj: true);
      _startSync();
      return true;
    } catch (_) {
      state = state.copyWith(error: 'Could not create a room');
      return false;
    }
  }

  Future<bool> joinRoom(String code) async {
    try {
      final normalized = code.trim().toUpperCase();
      final res =
          await _post('/room/$normalized/join', {'memberId': _memberId});
      if (res == null) {
        state = state.copyWith(error: 'Room not found (or already full)');
        return false;
      }
      _djTerm = 0;
      state = DateRoomState(code: normalized); // follower, mirroring
      _startSync();
      // The join response is the late-join snapshot: whatever queue and
      // transport state already live in the room.
      await _applySnapshot(res);
      return true;
    } catch (_) {
      state = state.copyWith(error: 'Could not join — check the code');
      return false;
    }
  }

  Future<void> leave() async {
    final code = state.code;
    _stopSync();
    state = const DateRoomState();
    if (code != null) {
      try {
        await _post('/room/$code/leave', {'memberId': _memberId});
      } catch (_) {}
    }
  }

  /// Pushes what's playing right now into the room. Called by the
  /// sheet's button AND automatically whenever a track starts outside
  /// the room queue — partners shouldn't have to press anything for
  /// the music to follow (user-tested: they did, and it didn't).
  /// Only online tracks travel; the partner can't hear files on your
  /// disk. Returns a user-facing error, or null on success.
  Future<String?> shareCurrentQueue() async {
    if (_sharing) return null;
    final engine = ref.read(audioHandlerProvider).engine;
    final s = engine.state;
    final online = [
      for (final t in s.queue)
        if (t.sourceId != null) t,
    ];
    if (online.isEmpty) {
      return 'Date mode needs online songs — local files can\'t travel';
    }
    var index = online.indexWhere((t) => t.id == s.currentTrack?.id);
    if (index < 0) index = 0;
    _sharing = true;
    try {
      _roomTracks = online;
      final positionMs = engine.position.inMilliseconds;
      final playing = s.status == PlaybackStatus.playing;

      // The queue itself travels through Mongo (it can be far bigger
      // than an Ably message); the st channel just announces the new
      // rev so the partner fetches it immediately.
      final res = await _post('/room/${state.code}/sync', {
        'memberId': _memberId,
        'sinceQueueRev': 1 << 30, // never echo the queue back
        ..._presenceBody(),
        'control': {
          'queue': [
            for (final t in online)
              {
                'title': t.title,
                'artist': t.artist,
                'album': t.album,
                'source': t.source.name,
                'sourceId': t.sourceId,
                'durationMs': t.duration.inMilliseconds,
                'artUrl': t.artUrl,
              },
          ],
          'currentIndex': index,
          'positionMs': positionMs,
          'isPlaying': playing,
        },
      });
      if (res == null) return 'Could not share — check your connection';
      _queueRev = (res['queueRev'] as num?)?.toInt() ?? _queueRev;
      _setAnchor(index, positionMs, playing);
      _lastLocalControlAt = DateTime.now();
      // Sharing your queue makes you the DJ — your world becomes the
      // room's, and the partner mirrors it.
      _becomeDj();
      state = state.copyWith(
          shared: true, isDj: true, following: true, clearError: true);
      unawaited(_transport?.publish(_stChannel, 'queue', {
        'memberId': _memberId,
        'queueRev': _queueRev,
        'index': index,
        'positionMs': positionMs,
        'isPlaying': playing,
        'term': _djTerm,
      }));
      _announceDj();
      return null;
    } catch (_) {
      return 'Could not share — check your connection';
    } finally {
      _sharing = false;
    }
  }

  // --- Sync loop ---

  void _startSync() {
    _stopSync(keepState: true);

    final code = state.code!;
    _transport = AblyTransport(
      channels: ['hanamimi:st:$code', 'hanamimi:hb:$code'],
      fetchToken: () async {
        try {
          final res =
              await _post('/room/$code/token', {'memberId': _memberId});
          return res?['token'] as String?;
        } catch (_) {
          return null;
        }
      },
    );
    _msgSub = _transport!.messages.listen(_onMessage);
    _connSub = _transport!.connectedStream.listen((up) {
      state = state.copyWith(realtime: up);
      if (up) {
        // Fresh SSE connection: anything the partner published while we
        // were reconnecting never replayed to us. Announce ourselves so
        // they clear any "stepped away", then pull the durable snapshot
        // to recover whatever control/queue events we missed.
        unawaited(_transport?.publish(_hbChannel, 'hb', {
          'memberId': _memberId,
          ..._presenceBody(),
        }));
        unawaited(_syncNow());
      }
    });

    // Presence heartbeat out + partner staleness check. 5s beats with
    // a 15s window: three misses before "stepped away", instead of the
    // poll model's hair-trigger.
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_transport?.publish(_hbChannel, 'hb', {
        'memberId': _memberId,
        ..._presenceBody(),
      }));
      // Only judge the partner "stepped away" while OUR transport is
      // actually up — a silence during our own reconnect says nothing
      // about them, and declaring them gone was the asymmetric
      // "partner stepped away" (one side's SSE down, the other fine).
      final seen = _partnerLastSeen;
      if ((_transport?.connected ?? false) &&
          state.partnerOnline &&
          (seen == null ||
              DateTime.now().difference(seen) >
                  const Duration(seconds: 15))) {
        state = state.copyWith(partnerOnline: false, partnerStalled: false);
      }
      _driftCorrect();
    });

    // Keepalive + safety net: refreshes Mongo expiry/presence and, if a
    // realtime event ever slips through, reconciles both sides toward
    // the durable snapshot. 15s bounds the worst-case catch-up — the
    // 60s it replaced is exactly the "40 seconds late" the user saw when
    // realtime silently fell back to this path.
    _slowSync = Timer.periodic(
        const Duration(seconds: 15), (_) => _syncNow());

    final engine = ref.read(audioHandlerProvider).engine;
    _lastKnownPlaying = null;
    _lastKnownTrackId = engine.state.currentTrack?.id;

    // Local action detection: play/pause and track jumps become control
    // events; remote applies are masked by _applyingRemote.
    _stateSub = engine.stateStream.listen((s) {
      if (_applyingRemote) return;
      final playing = s.status == PlaybackStatus.playing;
      final trackId = s.currentTrack?.id;

      // A follower who touches their own transport drops out of lockstep
      // into "solo" — they never drive the room; the DJ does. A Rejoin
      // snaps them back (see [rejoin]).
      if (!state.isDj) {
        if (state.following &&
            state.shared &&
            (trackId != _lastKnownTrackId ||
                (_lastKnownPlaying != null &&
                    playing != _lastKnownPlaying))) {
          _detach();
        }
        _lastKnownPlaying = playing;
        _lastKnownTrackId = trackId;
        return;
      }

      if (trackId != null && trackId != _lastKnownTrackId) {
        _lastKnownTrackId = trackId;
        _lastKnownPlaying = playing;
        final index = _roomTracks.indexWhere((t) => t.id == trackId);
        if (index >= 0) {
          _publishControl(index: index, positionMs: 0, isPlaying: true);
        } else {
          // Playing something outside the room queue — the music
          // follows you: share the new world automatically. (The old
          // build treated this as a local-only detour, which read as
          // "my song change never reached them", user-tested.)
          unawaited(shareCurrentQueue());
        }
        return;
      }
      if (_lastKnownPlaying != null &&
          playing != _lastKnownPlaying &&
          !state.pausedForPartner &&
          state.shared) {
        _publishControl(
          index: _anchorIndex,
          positionMs:
              ref.read(audioHandlerProvider).engine.position.inMilliseconds,
          isPlaying: playing,
        );
      }
      _lastKnownPlaying = playing;
      _lastKnownTrackId = trackId;
    });

    // Seek detection: the position stream ticks ~4×/s; a jump bigger
    // than 3s that isn't a track change is a user seek.
    _posSub = engine.positionStream.listen((pos) {
      if (!_applyingRemote &&
          state.shared &&
          (pos - _lastPos).abs() > const Duration(seconds: 3) &&
          _lastKnownTrackId ==
              ref.read(audioHandlerProvider).engine.state.currentTrack?.id) {
        if (state.isDj) {
          _publishControl(
            index: _anchorIndex,
            positionMs: pos.inMilliseconds,
            isPlaying: _lastKnownPlaying ?? false,
          );
        } else if (state.following) {
          _detach(); // a follower scrubbing goes solo
        }
      }
      _lastPos = pos;
    });
  }

  void _stopSync({bool keepState = false}) {
    _transport?.close();
    _transport = null;
    _msgSub?.cancel();
    _connSub?.cancel();
    _heartbeat?.cancel();
    _slowSync?.cancel();
    _stateSub?.cancel();
    _posSub?.cancel();
    _queueRev = -1;
    _partnerLastSeen = null;
    // Leadership survives a sync *restart* (keepState) — only a real
    // room exit clears it, so createRoom's opening term isn't wiped when
    // _startSync tears the old transport down.
    if (!keepState) {
      _djTerm = 0;
      _partnerTerm = 0;
      _partnerIsDj = false;
      _lastLocalControlAt = DateTime.fromMillisecondsSinceEpoch(0);
      _roomTracks = const [];
    }
  }

  Map<String, Object?> _presenceBody() {
    final engine = ref.read(audioHandlerProvider).engine;
    final s = engine.state;
    final track = s.currentTrack;
    return {
      'positionMs': engine.position.inMilliseconds,
      'isPlaying': s.status == PlaybackStatus.playing,
      'bufferedMs': 0,
      'stalled': s.status == PlaybackStatus.loading,
      'trackKey':
          track == null ? '' : '${track.source.name}:${track.sourceId}',
      'isDj': state.isDj,
      'following': state.following,
      'term': _djTerm,
    };
  }

  void _setAnchor(int index, int positionMs, bool playing) {
    _anchorIndex = index;
    _anchorPosMs = positionMs;
    _anchorAt = DateTime.now();
    _anchorPlaying = playing;
  }

  Duration get _anchorExpected => Duration(
      milliseconds: _anchorPosMs +
          (_anchorPlaying
              ? DateTime.now().difference(_anchorAt).inMilliseconds
              : 0));

  /// A local transport action → control event to the partner, plus a
  /// fire-and-forget Mongo write so the durable snapshot keeps up.
  void _publishControl(
      {required int index, required int positionMs, required bool isPlaying}) {
    _setAnchor(index, positionMs, isPlaying);
    _lastLocalControlAt = DateTime.now();
    unawaited(_transport?.publish(_stChannel, 'control', {
      'memberId': _memberId,
      'index': index,
      'positionMs': positionMs,
      'isPlaying': isPlaying,
    }));
    unawaited(_post('/room/${state.code}/sync', {
      'memberId': _memberId,
      'sinceQueueRev': 1 << 30,
      ..._presenceBody(),
      'control': {
        'currentIndex': index,
        'positionMs': positionMs,
        'isPlaying': isPlaying,
      },
    }).catchError((_) => null));
  }

  // --- Receiving ---

  Future<void> _onMessage(AblyMessage msg) async {
    final from = msg.data['memberId'] as String?;
    if (from == null || from == _memberId) return;

    if (msg.name == 'hb') {
      _partnerLastSeen = DateTime.now();
      final stalled = msg.data['stalled'] == true;
      _partnerTerm =
          math.max(_partnerTerm, (msg.data['term'] as num?)?.toInt() ?? 0);
      _partnerIsDj = msg.data['isDj'] == true;
      state = state.copyWith(
        partnerJoined: true,
        partnerOnline: true,
        partnerStalled: stalled,
        partnerBufferedMs: (msg.data['bufferedMs'] as num?)?.toInt() ?? 0,
        partnerPositionMs:
            (msg.data['positionMs'] as num?)?.toInt() ?? 0,
        partnerFollowing: msg.data['following'] != false,
        clearError: true,
      );
      _reconcileRoles(from);
      await _stallGate();
      return;
    }

    // The partner became the DJ (took over / shared their queue). Yield
    // unless we hold a strictly newer term, then snap to their timeline.
    if (msg.name == 'dj') {
      _partnerLastSeen = DateTime.now();
      final term = (msg.data['term'] as num?)?.toInt() ?? 0;
      _partnerTerm = math.max(_partnerTerm, term);
      _partnerIsDj = true;
      if (term >= _djTerm) {
        _djTerm = term;
        final index = (msg.data['index'] as num?)?.toInt() ?? _anchorIndex;
        final positionMs =
            (msg.data['positionMs'] as num?)?.toInt() ?? _anchorPosMs;
        final playing = msg.data['isPlaying'] == true;
        final ageMs = playing
            ? DateTime.now()
                .difference(msg.timestamp)
                .inMilliseconds
                .clamp(0, 10000)
            : 0;
        _setAnchor(index, positionMs + ageMs, playing);
        state = state.copyWith(
            partnerJoined: true,
            partnerOnline: true,
            isDj: false,
            following: true,
            clearError: true);
        await _applyAnchor();
      }
      return;
    }

    if (msg.name == 'control') {
      _partnerLastSeen = DateTime.now();
      state = state.copyWith(partnerJoined: true, partnerOnline: true);
      final index = (msg.data['index'] as num?)?.toInt() ?? 0;
      final positionMs = (msg.data['positionMs'] as num?)?.toInt() ?? 0;
      final playing = msg.data['isPlaying'] == true;
      // Age the position by transit time (Ably server clock; clamped —
      // a skewed device clock must not fling the seek).
      final ageMs = playing
          ? DateTime.now()
              .difference(msg.timestamp)
              .inMilliseconds
              .clamp(0, 10000)
          : 0;
      _setAnchor(index, positionMs + ageMs, playing);
      // Only mirror the DJ while we're following them. A solo listener
      // still tracks the anchor (so Rejoin lands on the live spot) but
      // isn't moved; the DJ ignores it (there's only one DJ).
      if (state.following && !state.isDj) await _applyAnchor();
      return;
    }

    if (msg.name == 'queue') {
      _partnerLastSeen = DateTime.now();
      final rev = (msg.data['queueRev'] as num?)?.toInt() ?? 0;
      final index = (msg.data['index'] as num?)?.toInt() ?? 0;
      final positionMs = (msg.data['positionMs'] as num?)?.toInt() ?? 0;
      final playing = msg.data['isPlaying'] == true;
      _setAnchor(index, positionMs, playing);
      // Fetch regardless of role so a solo listener already has the
      // tracks materialized the moment they Rejoin.
      if (rev > _queueRev) await _fetchQueue();
      if (state.following && !state.isDj) await _applyAnchor();
    }
  }

  // --- Leadership (DJ handoff) ---

  /// Drop out of lockstep to listen on our own. The DJ keeps playing;
  /// [rejoin] snaps us back. No-op for the DJ.
  void _detach() {
    if (state.isDj || !state.following) return;
    state = state.copyWith(following: false, pausedForPartner: false);
  }

  /// Claim the next leadership term (past anything we've seen).
  void _becomeDj() => _djTerm = math.max(_djTerm, _partnerTerm) + 1;

  /// Tell the partner we're the DJ now, with where the music sits.
  void _announceDj() {
    unawaited(_transport?.publish(_stChannel, 'dj', {
      'memberId': _memberId,
      'term': _djTerm,
      'index': _anchorIndex,
      'positionMs': _anchorPosMs,
      'isPlaying': _anchorPlaying,
    }));
  }

  /// Make our current playback the room's timeline and broadcast it.
  void _leadFromEngine() {
    final engine = ref.read(audioHandlerProvider).engine;
    final s = engine.state;
    final trackId = s.currentTrack?.id;
    final idx = _roomTracks.indexWhere((t) => t.id == trackId);
    final playing = s.status == PlaybackStatus.playing;
    if (idx >= 0) {
      _lastKnownTrackId = trackId;
      _lastKnownPlaying = playing;
      _publishControl(
          index: idx,
          positionMs: engine.position.inMilliseconds,
          isPlaying: playing);
      _announceDj();
    } else {
      // Our track isn't the room queue — publish the whole thing (which
      // also claims the DJ term and announces it).
      unawaited(shareCurrentQueue());
    }
  }

  /// Become the DJ: our playback leads, the partner mirrors us.
  Future<void> takeOver() async {
    if (state.isDj || !state.inRoom) return;
    _becomeDj();
    state = state.copyWith(
        isDj: true, following: true, pausedForPartner: false);
    _leadFromEngine();
  }

  /// Snap back into lockstep with the DJ from a solo detour.
  Future<void> rejoin() async {
    if (state.isDj || state.following) return;
    state = state.copyWith(following: true, pausedForPartner: false);
    await _applyAnchor();
  }

  /// Converge on a single DJ from a partner heartbeat: two claimants →
  /// the higher term wins (ties by memberId); no claimant → the lower
  /// memberId takes it so the room is never leaderless.
  void _reconcileRoles(String partnerId) {
    if (state.isDj && _partnerIsDj) {
      final iLose = _partnerTerm > _djTerm ||
          (_partnerTerm == _djTerm && _memberId.compareTo(partnerId) > 0);
      if (iLose) {
        _djTerm = _partnerTerm;
        state = state.copyWith(isDj: false, following: true);
        unawaited(_applyAnchor());
      }
    } else if (!state.isDj &&
        !_partnerIsDj &&
        state.partnerOnline &&
        state.shared &&
        _memberId.compareTo(partnerId) < 0) {
      _becomeDj();
      state = state.copyWith(isDj: true, following: true);
      _leadFromEngine();
    }
  }

  /// Pulls the room queue out of Mongo (it's too big for the realtime
  /// channel) and materializes it into real library rows.
  Future<void> _fetchQueue() async {
    final res = await _post('/room/${state.code}/sync', {
      'memberId': _memberId,
      'sinceQueueRev': _queueRev,
      ..._presenceBody(),
    });
    if (res == null) return;
    await _materializeQueue(res);
  }

  Future<void> _materializeQueue(Map<String, dynamic> res) async {
    final queue = res['queue'];
    if (queue is! List || queue.isEmpty) return;
    _queueRev = (res['queueRev'] as num?)?.toInt() ?? _queueRev;
    final notifier = ref.read(libraryProvider.notifier);
    _roomTracks = [
      for (final t in queue)
        if (t is Map && (t['sourceId'] as String?)?.isNotEmpty == true)
          await notifier.ensureOnlineTrack(OnlineSearchResult(
            source: TrackSource.values.asNameMap()[t['source']] ??
                TrackSource.youtube,
            sourceId: t['sourceId'] as String,
            title: t['title'] as String? ?? 'Unknown',
            artist: t['artist'] as String? ?? 'Unknown artist',
            album: t['album'] as String? ?? '',
            duration: Duration(
                milliseconds: (t['durationMs'] as num?)?.toInt() ?? 0),
            artUrl: (t['artUrl'] as String?)?.isEmpty == true
                ? null
                : t['artUrl'] as String?,
          )),
    ];
    state = state.copyWith(shared: true);
  }

  /// Converges the local engine onto the current anchor: right queue,
  /// right track, right position, right transport state.
  Future<void> _applyAnchor() async {
    if (_roomTracks.isEmpty) return;
    final engine = ref.read(audioHandlerProvider).engine;
    _applyingRemote = true;
    try {
      final wanted = _anchorIndex < _roomTracks.length
          ? _roomTracks[_anchorIndex]
          : null;
      final sameQueue = engine.state.queue.length == _roomTracks.length &&
          engine.state.queue.isNotEmpty &&
          engine.state.queue.first.id == _roomTracks.first.id;

      if (!sameQueue) {
        await engine.loadQueue(_roomTracks, startIndex: _anchorIndex);
      } else if (wanted != null &&
          engine.state.currentTrack?.id != wanted.id) {
        await engine.jumpToQueueIndex(_anchorIndex);
      }
      await engine.seek(_anchorExpected);
      if (_anchorPlaying && !state.pausedForPartner) {
        await engine.play();
      } else {
        await engine.pause();
      }
      _lastKnownPlaying = _anchorPlaying && !state.pausedForPartner;
      _lastKnownTrackId = engine.state.currentTrack?.id;
      state = state.copyWith(shared: true);
    } finally {
      _applyingRemote = false;
    }
  }

  /// Nudge back onto the anchor clock when we've drifted while playing.
  Future<void> _driftCorrect() async {
    // Only a follower who's mirroring drifts against the anchor — the DJ
    // *is* the anchor, and a solo listener is off on their own.
    if (state.isDj || !state.following) return;
    if (!state.shared || !_anchorPlaying || state.pausedForPartner) return;
    final engine = ref.read(audioHandlerProvider).engine;
    if (engine.state.status != PlaybackStatus.playing) return;
    if (engine.state.currentTrack?.id !=
        (_anchorIndex < _roomTracks.length
            ? _roomTracks[_anchorIndex].id
            : null)) {
      return;
    }
    final drift = engine.position - _anchorExpected;
    if (drift.abs() > const Duration(milliseconds: 1500)) {
      _applyingRemote = true;
      try {
        await engine.seek(_anchorExpected);
      } finally {
        _applyingRemote = false;
      }
    }
  }

  /// The "wait for each other" gate: partner buffering → we hold;
  /// partner recovers → we resume. Local decision, no control event.
  Future<void> _stallGate() async {
    final engine = ref.read(audioHandlerProvider).engine;
    if (_lockstep &&
        state.partnerStalled &&
        engine.state.status == PlaybackStatus.playing) {
      _applyingRemote = true;
      try {
        await engine.pause();
        state = state.copyWith(pausedForPartner: true);
        _lastKnownPlaying = false;
      } finally {
        _applyingRemote = false;
      }
    } else if (state.pausedForPartner &&
        (!_lockstep || !state.partnerStalled)) {
      _applyingRemote = true;
      try {
        await engine.seek(_anchorExpected);
        if (_anchorPlaying) await engine.play();
        state = state.copyWith(pausedForPartner: false);
        _lastKnownPlaying = _anchorPlaying;
      } finally {
        _applyingRemote = false;
      }
    }
  }

  // --- Mongo snapshot path (join bootstrap + degraded fallback) ---

  Future<void> _syncNow() async {
    final code = state.code;
    if (code == null || _syncInFlight) return;
    _syncInFlight = true;
    try {
      final res = await _post('/room/$code/sync', {
        'memberId': _memberId,
        'sinceQueueRev': _queueRev,
        ..._presenceBody(),
      });
      if (res == null) return;
      // Always reconcile against the durable snapshot. It's a keepalive
      // when realtime is healthy (the divergence guard makes it a no-op)
      // and the recovery path when an event was missed — the old code
      // only re-anchored while fully disconnected, so a single dropped
      // control event stuck until someone acted again.
      await _applySnapshot(res);
    } catch (_) {
      // Keepalive errors are transient; the next tick retries.
    } finally {
      _syncInFlight = false;
    }
  }

  /// Reconciles against a Mongo room snapshot (join response, reconnect
  /// recovery, or the periodic safety net). Presence is refreshed every
  /// time; the anchor is only re-applied when the snapshot genuinely
  /// diverges from where we already are, so a healthy realtime session
  /// never gets reseeked out from under itself.
  Future<void> _applySnapshot(Map<String, dynamic> res) async {
    final partner = res['partner'];
    if (partner is Map) {
      // The snapshot can turn presence back ON (recovering a false
      // "stepped away" when our realtime receive was down) but never
      // off — the connected-only staleness timer owns going offline, so
      // a lagging Mongo doc can't flap the partner against live beats.
      final online = partner['online'] == true;
      state = state.copyWith(
        partnerJoined: true,
        partnerOnline: state.partnerOnline || online,
      );
      if (online) _partnerLastSeen = DateTime.now();
    }

    await _materializeQueue(res);
    if (_roomTracks.isEmpty) return;

    // The DJ *is* the timeline — the snapshot is its own Mongo write, so
    // never let it move the DJ. (Presence/queue above still refresh.)
    if (state.isDj) return;

    // Don't let a stale read undo a change we just made locally — our
    // own Mongo write may not have landed yet.
    if (DateTime.now().difference(_lastLocalControlAt) <
        const Duration(seconds: 6)) {
      return;
    }

    final roomPlaying = res['isPlaying'] == true;
    final ageMs = (res['positionAgeMs'] as num?)?.toInt() ?? 0;
    final index = (res['currentIndex'] as num?)?.toInt() ?? 0;
    final posMs = ((res['positionMs'] as num?)?.toInt() ?? 0) +
        (roomPlaying ? ageMs : 0);

    // Only re-anchor on real divergence, else the 15s poll would reseek
    // every tick and fight live playback.
    final diverged = index != _anchorIndex ||
        roomPlaying != _anchorPlaying ||
        (Duration(milliseconds: posMs) - _anchorExpected).abs() >
            const Duration(seconds: 3);
    if (!diverged) return;

    // Keep the anchor fresh for everyone (so a solo listener's Rejoin
    // still lands on the DJ's live spot) but only *move* a follower who's
    // in lockstep.
    _setAnchor(index, posMs, roomPlaying);
    if (state.following) await _applyAnchor();
  }

  Future<Map<String, dynamic>?> _post(
      String path, Map<String, Object?> body) async {
    final res = await http
        .post(Uri.parse('$_apiBase$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body);
    return data is Map<String, dynamic> ? data : null;
  }
}

final dateRoomProvider =
    NotifierProvider<DateRoomNotifier, DateRoomState>(DateRoomNotifier.new);
