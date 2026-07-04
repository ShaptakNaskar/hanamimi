import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import '../library/models/track.dart';
import 'models/resolved_stream.dart';
import 'music_provider.dart';
import 'stream_cache.dart';

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
  final _streamCache = StreamCache();

  /// Keyed source:sourceId. In-memory only — stream URLs expire.
  final _cache = <String, ResolvedStream>{};
  final _inflight = <String, Future<ResolvedStream?>>{};

  /// Pushed from settings (M27); sensible defaults until then.
  StreamQuality quality = StreamQuality.high;
  bool enabled = true;
  int cacheCapBytes = 512 * 1024 * 1024;

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

    // Cache-as-you-play: LockCachingAudioSource writes the stream to
    // disk while playing, so a replay within the cache window costs no
    // data. It also serves through just_audio's proxy (Dart HTTP),
    // which is what lets YouTube URLs past ExoPlayer's 403.
    final cacheFile = await _streamCache.fileFor(track);
    unawaited(_streamCache.trim(cacheCapBytes));
    return LockCachingAudioSource(
      resolved.url,
      headers: resolved.headers.isEmpty
          // A non-empty header map is what forces the proxy path;
          // Saavn needs no headers but still benefits from caching.
          ? const {'User-Agent': 'Dart/3.7 (dart:io)'}
          : resolved.headers,
      cacheFile: cacheFile,
    );
  }

  /// Resolves and fully downloads a track's stream to [destination]
  /// (the explicit "Download" action). Returns true on success. Fetches
  /// with the Dart HTTP stack — the same one [sourceFor]'s proxy uses,
  /// so a URL that plays also downloads.
  Future<bool> download(Track track, String destination) async {
    final resolved = await _resolve(track);
    if (resolved == null) return false;
    try {
      final res = await http.get(resolved.url,
          headers: resolved.headers.isEmpty ? null : resolved.headers);
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return false;
      final tmp = File('$destination.part');
      await tmp.writeAsBytes(res.bodyBytes);
      // Atomic-ish: only expose the final path once fully written.
      await tmp.rename(destination);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> cacheSizeBytes() => _streamCache.sizeBytes();
  Future<void> clearCache() => _streamCache.clear();

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
        if (sourceId == null || !enabled) return null;
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
