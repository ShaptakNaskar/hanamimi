import 'package:just_audio/just_audio.dart';

import '../library/models/track.dart';
import 'models/resolved_stream.dart';
import 'music_provider.dart';

/// Thrown when a track can't be turned into a playable source
/// (offline, extraction broke, provider missing). The engine treats it
/// like an unreadable file: skip forward, guarded against cascades.
class StreamResolutionException implements Exception {
  StreamResolutionException(this.track);
  final Track track;

  @override
  String toString() =>
      'StreamResolutionException(${track.source.name}:${track.sourceId})';
}

/// The single gate between a [Track] and a playable [AudioSource]
/// (ARCHITECTURE-ONLINE.md §5). Local files short-circuit; online
/// tracks resolve through their provider with an in-memory TTL cache.
class StreamResolver {
  StreamResolver({Map<TrackSource, MusicProvider>? providers})
      : _providers = providers ?? musicProviderRegistry;

  final Map<TrackSource, MusicProvider> _providers;

  /// Keyed source:sourceId. In-memory only — stream URLs expire.
  final _cache = <String, ResolvedStream>{};
  final _inflight = <String, Future<ResolvedStream?>>{};

  /// Pushed from settings (M27); High until then.
  StreamQuality quality = StreamQuality.high;

  Future<AudioSource> sourceFor(Track track) async {
    final path = track.filePath;
    if (path != null) {
      // Downloaded/local: zero network. Tracks opened from other apps
      // carry a content:// uri instead of a filesystem path.
      return path.startsWith('content://')
          ? AudioSource.uri(Uri.parse(path))
          : AudioSource.file(path);
    }
    final resolved = await _resolve(track);
    if (resolved == null) throw StreamResolutionException(track);
    return AudioSource.uri(
      resolved.url,
      headers: resolved.headers.isEmpty ? null : resolved.headers,
    );
  }

  /// Warms the cache without side effects — called ahead of crossfades
  /// so resolution latency doesn't eat into the ramp.
  Future<void> preResolve(Track track) async {
    if (track.filePath != null) return;
    try {
      await _resolve(track);
    } catch (_) {
      // Best-effort; the real resolve at play time reports failure.
    }
  }

  /// Drops the cached URL (e.g. after an HTTP 403 on playback) so the
  /// next [sourceFor] resolves fresh.
  void invalidate(Track track) => _cache.remove(_key(track));

  String _key(Track t) => '${t.source.name}:${t.sourceId}';

  Future<ResolvedStream?> _resolve(Track track) {
    final key = _key(track);
    final cached = _cache[key];
    if (cached != null && cached.isFresh) return Future.value(cached);
    _cache.remove(key);
    // Coalesce concurrent resolves (preResolve racing play).
    return _inflight.putIfAbsent(key, () async {
      try {
        final sourceId = track.sourceId;
        if (sourceId == null) return null;
        final resolved =
            await _providers[track.source]?.resolveStream(sourceId, quality);
        if (resolved != null) _cache[key] = resolved;
        return resolved;
      } finally {
        _inflight.remove(key);
      }
    });
  }
}
