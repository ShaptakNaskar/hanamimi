import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../library/models/track.dart';
import 'models/online_search_result.dart';
import 'models/resolved_stream.dart';
import 'music_provider.dart';
import 'ytdlp_channel.dart';

/// YouTube provider. Stream extraction rides youtube_explode_dart
/// (Innertube player API; no key). Search calls Innertube's search
/// endpoint directly: youtube_explode 3.1.0's page parser broke on a
/// July-2026 response-shape change, and a defensive JSON walk over the
/// raw API survives shape drift that a strict parser doesn't (§12).
/// Same best-effort shape as MusixmatchProvider: null/empty on failure.
class YouTubeProvider implements MusicProvider {
  final _yt = YoutubeExplode();

  @override
  TrackSource get source => TrackSource.youtube;

  @override
  Future<List<OnlineSearchResult>> search(String query) async {
    try {
      final res = await http
          .post(
            Uri.parse(
                'https://www.youtube.com/youtubei/v1/search?prettyPrint=false'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': 'WEB',
                  'clientVersion': '2.20250101.00.00',
                  'hl': 'en',
                },
              },
              'query': query,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return const [];

      // Collect every videoRenderer wherever it sits in the tree —
      // resilient to YouTube reshuffling the wrapper hierarchy.
      final renderers = <Map<String, dynamic>>[];
      void walk(Object? node) {
        if (node is Map<String, dynamic>) {
          final vr = node['videoRenderer'];
          if (vr is Map<String, dynamic>) renderers.add(vr);
          node.values.forEach(walk);
        } else if (node is List) {
          node.forEach(walk);
        }
      }

      walk(jsonDecode(res.body));

      return [
        for (final r in renderers)
          if (_toResult(r) case final result?) result,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Searches **YouTube Music** (the `WEB_REMIX` Innertube client against
  /// music.youtube.com) instead of general YouTube. Results are curated
  /// *songs* with clean artist metadata and no random videos/live cuts,
  /// so they match imported playlist entries far better. Same videoId
  /// space — they resolve through the exact same stream path. Best-effort:
  /// empty on any failure (the importer falls back to general search).
  Future<List<OnlineSearchResult>> searchMusic(String query) async {
    try {
      final res = await http
          .post(
            Uri.parse(
                'https://music.youtube.com/youtubei/v1/search?prettyPrint=false'),
            headers: {
              'Content-Type': 'application/json',
              'Origin': 'https://music.youtube.com',
            },
            body: jsonEncode({
              'context': {
                'client': {
                  'clientName': 'WEB_REMIX',
                  'clientVersion': '1.20250101.01.00',
                  'hl': 'en',
                },
              },
              'query': query,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return const [];

      // YT Music lists items as musicResponsiveListItemRenderer, scattered
      // across shelves — collect them wherever they sit.
      final items = <Map<String, dynamic>>[];
      void walk(Object? node) {
        if (node is Map<String, dynamic>) {
          final it = node['musicResponsiveListItemRenderer'];
          if (it is Map<String, dynamic>) items.add(it);
          node.values.forEach(walk);
        } else if (node is List) {
          node.forEach(walk);
        }
      }

      walk(jsonDecode(res.body));

      final seen = <String>{};
      final out = <OnlineSearchResult>[];
      for (final it in items) {
        final r = _toMusicResult(it);
        if (r != null && seen.add(r.sourceId)) out.add(r);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  OnlineSearchResult? _toMusicResult(Map<String, dynamic> it) {
    try {
      // videoId lives on a watchEndpoint somewhere inside the item.
      final videoId = _findVideoId(it);
      if (videoId == null) return null;

      final flex = (it['flexColumns'] as List?) ?? const [];
      List<dynamic> runsOf(int i) {
        if (flex.length <= i) return const [];
        final col = flex[i]['musicResponsiveListItemFlexColumnRenderer'];
        final runs = col?['text']?['runs'];
        return runs is List ? runs : const [];
      }

      final title = runsOf(0).isEmpty ? null : runsOf(0).first['text'] as String?;
      if (title == null || title.isEmpty) return null;

      // Column 1 varies: a pure song is "Song • Artist [• Album • 3:45]",
      // a video is "Artist • 12M views • 3:19". Pull a duration if present
      // (song shelf entries often omit it — that's fine, title+artist
      // carry the match), and take the first run that's a real name (not a
      // type label or a view count) as the artist.
      const typeLabels = {
        'song', 'video', 'album', 'artist', 'playlist', 'ep', 'single'
      };
      Duration? duration;
      String? artist;
      for (final run in runsOf(1)) {
        final text = (run['text'] as String?)?.trim() ?? '';
        if (text.isEmpty || text == '•') continue;
        final d = _parseLength(text);
        if (d != null) {
          duration ??= d;
          continue;
        }
        final low = text.toLowerCase();
        if (typeLabels.contains(low)) continue;
        if (low.contains('view') || low.contains('plays')) continue;
        artist ??= text;
      }

      return OnlineSearchResult(
        source: TrackSource.youtube,
        sourceId: videoId,
        title: title,
        artist: artist ?? 'Unknown artist',
        duration: duration ?? Duration.zero,
        artUrl: _findThumbs(it),
      );
    } catch (_) {
      return null;
    }
  }

  /// First `watchEndpoint.videoId` anywhere under [node].
  static String? _findVideoId(Object? node) {
    if (node is Map<String, dynamic>) {
      final we = node['watchEndpoint'];
      if (we is Map<String, dynamic> && we['videoId'] is String) {
        return we['videoId'] as String;
      }
      for (final v in node.values) {
        final r = _findVideoId(v);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _findVideoId(v);
        if (r != null) return r;
      }
    }
    return null;
  }

  /// Last thumbnail url anywhere under [node] (biggest).
  static String? _findThumbs(Object? node) {
    if (node is Map<String, dynamic>) {
      final t = node['thumbnails'];
      if (t is List && t.isNotEmpty) return t.last['url'] as String?;
      for (final v in node.values) {
        final r = _findThumbs(v);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _findThumbs(v);
        if (r != null) return r;
      }
    }
    return null;
  }

  OnlineSearchResult? _toResult(Map<String, dynamic> r) {
    try {
      final videoId = r['videoId'] as String?;
      final title = (r['title']?['runs'] as List?)?.first?['text'] as String?;
      final author =
          (r['ownerText']?['runs'] as List?)?.first?['text'] as String?;
      // No lengthText = live stream or premiere; not playable audio.
      final duration = _parseLength(r['lengthText']?['simpleText'] as String?);
      if (videoId == null || title == null || duration == null) return null;

      final thumbs = (r['thumbnail']?['thumbnails'] as List?) ?? const [];
      return OnlineSearchResult(
        source: TrackSource.youtube,
        sourceId: videoId,
        title: title,
        artist: author ?? 'Unknown artist',
        duration: duration,
        artUrl: thumbs.isEmpty ? null : thumbs.last['url'] as String?,
      );
    } catch (_) {
      return null; // one malformed item never kills the result list
    }
  }

  /// "3:32" or "1:01:14" → Duration.
  static Duration? _parseLength(String? text) {
    if (text == null) return null;
    final parts = text.split(':').map(int.tryParse).toList();
    if (parts.any((p) => p == null) || parts.isEmpty) return null;
    var seconds = 0;
    for (final p in parts) {
      seconds = seconds * 60 + p!;
    }
    return Duration(seconds: seconds);
  }

  /// Clients to try in order. YouTube 403s stream URLs from clients it
  /// decides need a proof-of-origin token — which client that hits
  /// varies over time and per network, so each resolved URL is
  /// validated with a 1-byte fetch and the next client tried on
  /// failure (the ViMusic/InnerTune playbook).
  static final _clientChain = <List<YoutubeApiClient>?>[
    [YoutubeApiClient.androidVr], // no PoToken/nsig gate on its URLs
    [YoutubeApiClient.ios],
    [YoutubeApiClient.android],
    null, // package default (androidSdkless) last resort
  ];

  @override
  Future<ResolvedStream?> resolveStream(
      String sourceId, StreamQuality quality) async {
    // M28: embedded yt-dlp first. It deciphers the `n` parameter itself,
    // so its URL downloads at full speed (the throttle that made bulk
    // downloads crawl is gone). If it's unavailable — init failed, low
    // storage, YouTube change, native crash — it returns null and we
    // drop to the pure-Dart youtube_explode client-rotation below, so
    // YouTube still plays (degraded, real-time-throttled) either way.
    final viaYtDlp = await YtDlpChannel.resolve(sourceId, quality);
    if (viaYtDlp != null && await _urlServes(viaYtDlp.url)) return viaYtDlp;

    return _resolveViaExplode(sourceId, quality);
  }

  Future<ResolvedStream?> _resolveViaExplode(
      String sourceId, StreamQuality quality) async {
    for (final clients in _clientChain) {
      try {
        final manifest =
            await _yt.videos.streams.getManifest(sourceId, ytClients: clients);
        final audio = manifest.audioOnly.toList();
        if (audio.isEmpty) continue;

        // High: best available (opus/webm tops out ~160k). Low: closest
        // to ~96k so mobile data isn't burned on the premium stream.
        audio.sort((a, b) => a.bitrate.compareTo(b.bitrate));
        final chosen = switch (quality) {
          StreamQuality.high => audio.last,
          StreamQuality.low => audio.reduce((a, b) =>
              (a.bitrate.bitsPerSecond - 96000).abs() <=
                      (b.bitrate.bitsPerSecond - 96000).abs()
                  ? a
                  : b),
        };

        if (!await _urlServes(chosen.url)) continue;

        // Stream URLs carry their own death date (?expire=<unix
        // seconds>, ~6 h out); conservative fallback if absent.
        final expireParam =
            int.tryParse(chosen.url.queryParameters['expire'] ?? '');
        final expiresAt = expireParam != null
            ? DateTime.fromMillisecondsSinceEpoch(expireParam * 1000)
            : DateTime.now().add(const Duration(hours: 1));

        return ResolvedStream(
          url: chosen.url,
          // Non-empty headers make just_audio serve the stream through
          // its in-process proxy, i.e. fetch with Dart's HTTP stack.
          // googlevideo 403s ExoPlayer's Java stack for these URLs
          // (client fingerprinting) while the Dart stack — the one
          // _urlServes just validated — is served fine.
          headers: const {'User-Agent': 'Dart/3.7 (dart:io)'},
          codec: chosen.audioCodec,
          bitrateKbps: chosen.bitrate.kiloBitsPerSecond.round(),
          expiresAt: expiresAt,
        );
      } catch (_) {
        // Try the next client.
      }
    }
    return null;
  }

  /// One ranged byte proves googlevideo will actually serve this URL
  /// from this device — a URL that resolves but 403s otherwise
  /// surfaces as an opaque ExoPlayer source error.
  static Future<bool> _urlServes(Uri url) async {
    try {
      final res = await http.get(url, headers: {
        'Range': 'bytes=0-0',
      }).timeout(const Duration(seconds: 8));
      return res.statusCode == 200 || res.statusCode == 206;
    } catch (_) {
      return false;
    }
  }
}
