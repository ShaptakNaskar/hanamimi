import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/block/desede_engine.dart';
import 'package:pointycastle/pointycastle.dart' show KeyParameter;

import '../library/models/track.dart';
import 'models/online_search_result.dart';
import 'models/resolved_stream.dart';
import 'music_provider.dart';

/// JioSaavn via its public JSON endpoints (the BlackHole approach,
/// ARCHITECTURE-ONLINE.md §4.3). Simpler and more stable than YouTube:
/// no token dance, true CBR streams, long-lived URLs. Best-effort:
/// null/empty on any failure.
class SaavnProvider implements MusicProvider {
  static const _host = 'www.jiosaavn.com';

  /// The well-known static DES key (saavn.dev, BlackHole). Single DES
  /// expressed as DESede with all three subkeys equal.
  static final _desKey =
      Uint8List.fromList(utf8.encode('383465913834659138346591'));

  @override
  TrackSource get source => TrackSource.saavn;

  @override
  Future<List<OnlineSearchResult>> search(String query) async {
    try {
      final auto = await _api({
        '__call': 'autocomplete.get',
        'query': query,
      });
      final songs =
          (auto?['songs']?['data'] as List?)?.cast<Map<String, dynamic>>() ??
              const [];
      final ids = [
        for (final s in songs)
          if (s['id'] is String) s['id'] as String,
      ];
      if (ids.isEmpty) return const [];

      // Autocomplete rows lack duration; one batched getDetails fills
      // duration + clean artist/album for the whole result page.
      final details = await _api({
        '__call': 'song.getDetails',
        'pids': ids.join(','),
      });
      if (details == null) return const [];

      return [
        for (final id in ids)
          if (details[id] case final Map<String, dynamic> d)
            if (_toResult(id, d) case final result?) result,
      ];
    } catch (_) {
      return const [];
    }
  }

  OnlineSearchResult? _toResult(String id, Map<String, dynamic> d) {
    final title = d['song'] as String?;
    final seconds = int.tryParse('${d['duration']}');
    if (title == null || seconds == null || seconds <= 0) return null;
    return OnlineSearchResult(
      source: TrackSource.saavn,
      sourceId: id,
      title: _unescape(title),
      artist: _unescape(
          (d['primary_artists'] ?? d['singers'] ?? 'Unknown artist')
              as String),
      album: _unescape((d['album'] ?? '') as String),
      duration: Duration(seconds: seconds),
      // Album art comes 150x150; the CDN serves 500x500 with the same
      // path, which matches the now-playing art size.
      artUrl: (d['image'] as String?)?.replaceFirst('150x150', '500x500'),
    );
  }

  @override
  Future<ResolvedStream?> resolveStream(
      String sourceId, StreamQuality quality) async {
    try {
      final details = await _api({
        '__call': 'song.getDetails',
        'pids': sourceId,
      });
      final d = details?[sourceId] as Map<String, dynamic>?;
      final encrypted = d?['encrypted_media_url'] as String?;
      if (encrypted == null) return null;

      final base = _decryptMediaUrl(encrypted);
      if (base == null) return null;

      // Decrypted URLs point at the 96 kbps file; the CDN serves other
      // bitrates by suffix substitution. 320 only where licensed.
      final has320 = '${d?['320kbps']}' == 'true';
      final (suffix, kbps) = switch (quality) {
        StreamQuality.high when has320 => ('_320', 320),
        StreamQuality.high => ('_160', 160),
        StreamQuality.low => ('_96', 96),
      };

      return ResolvedStream(
        url: Uri.parse(base.replaceFirst('_96', suffix)),
        codec: 'aac',
        bitrateKbps: kbps,
        sampleRateHz: 44100,
        container: 'm4a',
        fullSpeed: true,
        // Saavn CDN URLs are unsigned and long-lived (§4.3) — a
        // generous TTL just keeps the cache honest.
        expiresAt: DateTime.now().add(const Duration(hours: 12)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _api(Map<String, String> params) async {
    final uri = Uri.https(_host, '/api.php', {
      '_format': 'json',
      '_marker': '0',
      'cc': 'in',
      ...params,
    });
    final res = await http.get(uri, headers: {
      // The api rejects botty default UAs.
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14) Hanamimi/1.0',
    }).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body);
    return body is Map<String, dynamic> ? body : null;
  }

  /// Base64 → DES/ECB decrypt → PKCS5 unpad → URL.
  static String? _decryptMediaUrl(String encrypted) {
    final data = base64.decode(encrypted);
    if (data.isEmpty || data.length % 8 != 0) return null;
    final engine = DESedeEngine()..init(false, KeyParameter(_desKey));
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i += 8) {
      engine.processBlock(data, i, out, i);
    }
    final pad = out.last;
    final url = utf8.decode(
        pad >= 1 && pad <= 8 ? out.sublist(0, out.length - pad) : out,
        allowMalformed: true);
    return url.startsWith('http') ? url : null;
  }

  static String _unescape(String s) => s
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}
