import 'dart:async';
import 'dart:convert';

import '../../audio/models/audio_state.dart';
import '../../audio/queue_manager.dart';
import '../../library/models/track.dart';
import 'discord_rpc_client.dart';

/// Public identifier for Hanamimi's Discord application. Unlike a client
/// secret, Discord application IDs are intentionally shipped in clients.
const hanamimiDiscordApplicationId = '1536036237792776253';

/// Public fallback used when a local song has no web-accessible cover.
/// Local file paths are deliberately never shared with Discord.
const hanamimiDiscordArtworkUrl =
    'https://raw.githubusercontent.com/ShaptakNaskar/hanamimi/plus/'
    'assets/icon/icon.png';

typedef DiscordRpcClientFactory = DiscordRpcClient Function();

/// Best-effort bridge from QueueManager's platform-neutral playback state to
/// the locally running Discord desktop client.
///
/// Discord being closed, starting late, or dropping its IPC socket must never
/// disturb playback. Failures are swallowed and retried after a short cooldown.
class DiscordPresenceService {
  DiscordPresenceService(this.engine, {DiscordRpcClientFactory? clientFactory})
    : _clientFactory =
          clientFactory ??
          (() => DiscordLocalRpcClient(
            applicationId: hanamimiDiscordApplicationId,
          ));

  final QueueManager engine;
  final DiscordRpcClientFactory _clientFactory;

  StreamSubscription<AudioState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<void>? _clientDisconnectedSub;
  Timer? _retryTimer;
  DiscordRpcClient? _client;

  late AudioState _state;
  late Duration _position;
  DateTime? _positionObservedAt;
  String? _lastActivityKey;
  Future<void> _serial = Future.value();
  bool _disposed = false;
  bool _syncQueued = false;
  bool _forceSync = false;

  void start() {
    _state = engine.state;
    _position = engine.position;
    _positionObservedAt = DateTime.now();

    _stateSub = engine.stateStream.listen(_onState);
    _positionSub = engine.positionStream.listen(_onPosition);
    _scheduleSync(force: true);
  }

  void _onState(AudioState state) {
    if (_disposed) return;
    _state = state;
    _position = engine.position;
    _positionObservedAt = DateTime.now();
    _scheduleSync(force: true);
  }

  void _onPosition(Duration position) {
    if (_disposed) return;
    final now = DateTime.now();
    final observedAt = _positionObservedAt;
    final previous = _position;
    _position = position;
    _positionObservedAt = now;

    // Timestamps advance on Discord's side, so normal position ticks need no
    // IPC traffic. A seek is the exception: move the timestamp anchor when the
    // observed jump differs materially from elapsed wall time.
    if (_state.isPlaying && observedAt != null) {
      final expectedAdvance = now.difference(observedAt).inMilliseconds;
      final actualAdvance = (position - previous).inMilliseconds;
      if ((actualAdvance - expectedAdvance).abs() > 2500) {
        _scheduleSync(force: true);
      }
    }
  }

  void _scheduleSync({bool force = false}) {
    if (_disposed) return;
    _forceSync = _forceSync || force;
    if (_syncQueued) return;
    _syncQueued = true;
    scheduleMicrotask(() {
      _syncQueued = false;
      final forceNow = _forceSync;
      _forceSync = false;
      _serial = _serial
          .then((_) => _sync(force: forceNow))
          .catchError((Object _) {});
    });
  }

  Future<void> _sync({required bool force}) async {
    if (_disposed) return;
    final state = _state;
    final track = state.currentTrack;
    if (track == null ||
        state.status == PlaybackStatus.idle ||
        state.status == PlaybackStatus.completed) {
      await _dropClient();
      return;
    }

    final now = DateTime.now();
    final activity = buildDiscordActivity(state, _position, now: now);
    final key = discordActivityKey(state, _position, now: now);
    if (!force && key == _lastActivityKey) return;

    try {
      final client = await _ensureClient();
      if (client == null || _disposed) return;
      await client.setActivity(activity);
      _lastActivityKey = key;
      _retryTimer?.cancel();
      _retryTimer = null;
    } catch (_) {
      await _dropClient();
      _scheduleRetry();
    }
  }

  Future<DiscordRpcClient?> _ensureClient() async {
    if (_client != null) return _client;
    final client = _clientFactory();
    try {
      await client.connect();
      _client = client;
      _clientDisconnectedSub = client.disconnected.listen((_) {
        if (_disposed || _client != client) return;
        _client = null;
        _lastActivityKey = null;
        unawaited(_clientDisconnectedSub?.cancel());
        _clientDisconnectedSub = null;
        unawaited(client.disconnect());
        _scheduleRetry();
      });
      _lastActivityKey = null;
      return client;
    } catch (_) {
      try {
        await client.disconnect();
      } catch (_) {}
      _scheduleRetry();
      return null;
    }
  }

  void _scheduleRetry() {
    if (_disposed || _retryTimer != null) return;
    _retryTimer = Timer(const Duration(seconds: 30), () {
      _retryTimer = null;
      _scheduleSync(force: true);
    });
  }

  Future<void> _dropClient() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    _lastActivityKey = null;
    final client = _client;
    _client = null;
    await _clientDisconnectedSub?.cancel();
    _clientDisconnectedSub = null;
    try {
      await client?.disconnect();
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    await _stateSub?.cancel();
    await _positionSub?.cancel();
    try {
      await _serial;
    } catch (_) {}
    await _dropClient();
  }
}

/// Pure mapping kept separate from the IPC lifecycle so the public metadata
/// and timestamp rules can be regression-tested without running Discord.
DiscordActivity buildDiscordActivity(
  AudioState state,
  Duration position, {
  required DateTime now,
}) {
  final track = state.currentTrack!;
  final duration =
      state.duration > Duration.zero ? state.duration : track.duration;
  final safePosition = _clampPosition(position, duration);
  final artUrl = _publicArtwork(track.artUrl);

  final start =
      state.isPlaying && duration > Duration.zero
          ? now.subtract(safePosition)
          : null;
  final end =
      state.isPlaying && duration > Duration.zero
          ? now.add(duration - safePosition)
          : null;

  return DiscordActivity(
    name: 'Hanamimi+',
    type: 2, // Listening
    details: _limitDiscordText(track.title),
    state: _limitDiscordText(_presenceState(state.status, track)),
    start: start,
    end: end,
    largeImage: artUrl ?? hanamimiDiscordArtworkUrl,
    largeText: _limitDiscordText(
      track.album.trim().isEmpty ? track.title : track.album,
    ),
    smallImage: artUrl == null ? null : hanamimiDiscordArtworkUrl,
    smallText: artUrl == null ? null : 'Hanamimi+',
  );
}

String discordActivityKey(
  AudioState state,
  Duration position, {
  required DateTime now,
}) {
  final track = state.currentTrack;
  if (track == null) return 'none:${state.status.name}';
  final duration =
      state.duration > Duration.zero ? state.duration : track.duration;
  final safePosition = _clampPosition(position, duration);
  // Rounding tolerates the sub-second jitter between the player tick and wall
  // clock while still changing after a real seek.
  final anchorSeconds =
      state.isPlaying
          ? now.subtract(safePosition).millisecondsSinceEpoch ~/ 1000
          : 0;
  return jsonEncode([
    track.source.name,
    track.sourceId ?? track.id,
    state.status.name,
    duration.inMilliseconds,
    anchorSeconds,
    track.title,
    track.artist,
    track.album,
    _publicArtwork(track.artUrl),
  ]);
}

Duration _clampPosition(Duration position, Duration duration) {
  if (position < Duration.zero) return Duration.zero;
  if (duration > Duration.zero && position > duration) return duration;
  return position;
}

String _presenceState(PlaybackStatus status, Track track) {
  final artist = track.artist.trim().isEmpty ? 'Unknown artist' : track.artist;
  final album = track.album.trim();
  final metadata = album.isEmpty ? artist : '$artist • $album';
  return switch (status) {
    PlaybackStatus.paused => 'Paused • $metadata',
    PlaybackStatus.loading => 'Loading • $metadata',
    _ => metadata,
  };
}

String? _publicArtwork(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  return uri != null && (uri.scheme == 'https' || uri.scheme == 'http')
      ? uri.toString()
      : null;
}

String _limitDiscordText(String value) {
  const maxRunes = 128;
  final runes = value.runes;
  if (runes.length <= maxRunes) return value;
  return '${String.fromCharCodes(runes.take(maxRunes - 1))}…';
}
