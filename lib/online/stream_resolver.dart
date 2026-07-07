import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../audio/player_port.dart';
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

/// The single gate between a [Track] and a playable [PlaybackSource]
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

  Future<PlaybackSource> sourceFor(Track track) async {
    final path = track.filePath;
    if (path != null) {
      // Downloaded/local: zero network. Tracks opened from other apps
      // carry a content:// uri instead of a filesystem path (the
      // just_audio backend handles that split).
      return PlaybackSource.file(path);
    }
    final resolved = await _resolve(track);
    if (resolved == null) throw StreamResolutionException(track);

    // Cache-as-you-play (Android backend): the cacheFile makes
    // just_audio write the stream to disk while playing, and serves it
    // through its proxy (Dart HTTP) — which is what lets YouTube URLs
    // past ExoPlayer's 403. The media_kit backend ignores the file.
    final cacheFile = await _streamCache.fileFor(track);
    unawaited(_streamCache.trim(cacheCapBytes));
    return PlaybackSource.remote(
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
  ///
  /// Streams to disk chunk by chunk (a song never sits whole in RAM)
  /// and reports [onProgress] (received bytes, total or null) so the
  /// download manager can show progress/speed. [isCancelled] is checked
  /// between chunks; cancelling deletes the partial file.
  /// [quality] overrides the playback quality setting — the download
  /// picker's choice; resolution bypasses the URL cache so a cached
  /// low-quality playback URL can't sneak into a high-quality download.
  Future<bool> download(
    Track track,
    String destination, {
    StreamQuality? quality,
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final resolved = quality == null
        ? await _resolve(track)
        : await _resolveFresh(track, quality);
    if (resolved == null) return false;

    final client = http.Client();
    final tmp = File('$destination.part');
    try {
      final req = http.Request('GET', resolved.url);
      if (resolved.headers.isNotEmpty) req.headers.addAll(resolved.headers);
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return false;

      final total = res.contentLength;
      var received = 0;
      final sink = tmp.openWrite();
      try {
        await for (final chunk in res.stream) {
          if (isCancelled?.call() ?? false) {
            await sink.close();
            await tmp.delete();
            return false;
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      if (received == 0) {
        await tmp.delete();
        return false;
      }
      // Atomic-ish: only expose the final path once fully written.
      await tmp.rename(destination);
      return true;
    } catch (_) {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
      return false;
    } finally {
      client.close();
    }
  }

  /// Resolution with an explicit quality, no cache read/write — used by
  /// downloads so the picked quality is honored exactly.
  Future<ResolvedStream?> _resolveFresh(
      Track track, StreamQuality quality) async {
    final sourceId = track.sourceId;
    if (sourceId == null || !enabled) return null;
    try {
      return await _providers[track.source]?.resolveStream(sourceId, quality);
    } catch (_) {
      return null;
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

  /// A remote URL the visualizer's FFT extractor can decode ahead of
  /// playback — only for sources that serve faster than real time. A
  /// `n`-throttled youtube_explode URL runs at ~1× (a separate decode
  /// can't outrun playback), so it returns null and the synth pulse
  /// covers it. Saavn's CDN and yt-dlp-resolved YouTube (M28, `n`
  /// deciphered) are unthrottled → real bands. Reuses the play-time
  /// resolution (coalesced/cached), so no extra extraction call.
  Future<String?> decodableStreamUrl(Track track) async {
    if (track.filePath != null) return null;
    try {
      final resolved = await _resolve(track);
      return resolved != null && resolved.fullSpeed
          ? resolved.url.toString()
          : null;
    } catch (_) {
      return null;
    }
  }

  /// The resolved audio metadata (codec / bitrate / sample-rate /
  /// container) for a track, for the Nerd-mode overlay. Reuses the
  /// coalesced/cached resolution; null for a local file or on failure.
  Future<ResolvedStream?> streamInfo(Track track) async {
    if (track.filePath != null) return null;
    try {
      return await _resolve(track);
    } catch (_) {
      return null;
    }
  }

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
