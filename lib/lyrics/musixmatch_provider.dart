import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

/// Word-level synced lyrics (richsync) from Musixmatch's desktop-app
/// API — the same word-timing data "Beautiful Lyrics"-style plugins
/// use. Best-effort: any failure (captcha-gated token, rate limit,
/// no richsync for the track) returns null and the caller falls back
/// to line-synced sources.
abstract final class MusixmatchProvider {
  static const _root = 'apic-desktop.musixmatch.com';
  static const _appId = 'web-desktop-app-v1.0';
  static const _headers = {
    'cookie': 'AWSELBCORS=0; AWSELB=0',
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64)',
  };
  static const _timeout = Duration(seconds: 10);

  static String? _token;
  static DateTime? _tokenFetchedAt;

  /// Returns the raw richsync JSON body (see [RichsyncParser]) or null.
  static Future<String?> fetchRichsyncJson({
    required String title,
    required String artist,
    required Duration duration,
  }) async {
    try {
      final token = await _getToken();
      if (token == null) return null;

      final trackId = await _findTrackId(token, title, artist, duration);
      if (trackId == null) return null;

      final body = await _get('track.richsync.get', token, {
        'track_id': '$trackId',
      });
      final richsyncBody = ((body?['richsync']
          as Map<String, dynamic>?)?['richsync_body']) as String?;
      if (richsyncBody == null || richsyncBody.isEmpty) return null;
      return richsyncBody;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _getToken() async {
    if (_token != null &&
        DateTime.now().difference(_tokenFetchedAt!) <
            const Duration(minutes: 30)) {
      return _token;
    }
    final res = await http
        .get(
          Uri.https(_root, '/ws/1.1/token.get', {
            'app_id': _appId,
            't': '${Random().nextInt(1 << 32)}',
          }),
          headers: _headers,
        )
        .timeout(_timeout);
    final message = (jsonDecode(res.body)
        as Map<String, dynamic>)['message'] as Map<String, dynamic>;
    if ((message['header'] as Map<String, dynamic>)['status_code'] != 200) {
      return null;
    }
    _token = (message['body'] as Map<String, dynamic>)['user_token'] as String?;
    _tokenFetchedAt = DateTime.now();
    return _token;
  }

  static Future<Map<String, dynamic>?> _get(
      String endpoint, String token, Map<String, String> params) async {
    final res = await http
        .get(
          Uri.https(_root, '/ws/1.1/$endpoint', {
            'app_id': _appId,
            'usertoken': token,
            ...params,
          }),
          headers: _headers,
        )
        .timeout(_timeout);
    final message = (jsonDecode(res.body)
        as Map<String, dynamic>)['message'] as Map<String, dynamic>;
    if ((message['header'] as Map<String, dynamic>)['status_code'] != 200) {
      return null;
    }
    return message['body'] as Map<String, dynamic>?;
  }

  /// First search hit that has richsync and roughly matches our file's
  /// duration (avoids word timings from a remix/extended cut).
  static Future<int?> _findTrackId(
      String token, String title, String artist, Duration duration) async {
    final body = await _get('track.search', token, {
      'q_track': title,
      'q_artist': artist,
      'page_size': '5',
      'page': '1',
      's_track_rating': 'desc',
    });
    final list = body?['track_list'] as List?;
    if (list == null) return null;
    for (final item in list) {
      final track = (item as Map<String, dynamic>)['track'] as Map<String, dynamic>;
      if (track['has_richsync'] != 1) continue;
      final length = track['track_length'] as int? ?? 0;
      if (duration.inSeconds > 0 &&
          length > 0 &&
          (length - duration.inSeconds).abs() > 8) {
        continue;
      }
      return track['track_id'] as int?;
    }
    return null;
  }

}
