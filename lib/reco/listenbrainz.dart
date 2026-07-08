import 'dart:convert';

import 'package:http/http.dart' as http;

/// ListenBrainz client (Tier 2, ARCHITECTURE-RECOMMENDATIONS.md §4).
/// Strictly opt-in: nothing here is ever constructed, let alone called,
/// until the user has pasted a token through the consent dialog. Open
/// data, self-hostable — [host] defaults to the public instance but any
/// self-hosted URL works.
class ListenBrainz {
  ListenBrainz({required this.token, String? host})
      : host = _normalizeHost(host);

  final String token;
  final String host;

  static const defaultHost = 'https://api.listenbrainz.org';

  static String _normalizeHost(String? h) {
    final t = (h ?? '').trim();
    if (t.isEmpty) return defaultHost;
    final withScheme = t.contains('://') ? t : 'https://$t';
    return withScheme.endsWith('/')
        ? withScheme.substring(0, withScheme.length - 1)
        : withScheme;
  }

  Map<String, String> get _headers => {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
      };

  /// Validates the token; returns the account's user name, or null when
  /// the token (or host) is bad.
  Future<String?> validate() async {
    try {
      final res = await http
          .get(Uri.parse('$host/1/validate-token'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['valid'] == true ? body['user_name'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  /// Submits one completed listen (scrobble). Fire-and-forget: a lost
  /// scrobble is not worth surfacing an error for.
  Future<void> submitListen({
    required String title,
    required String artist,
    String? album,
    DateTime? listenedAt,
  }) async {
    try {
      await http
          .post(
            Uri.parse('$host/1/submit-listens'),
            headers: _headers,
            body: jsonEncode({
              'listen_type': 'single',
              'payload': [
                {
                  'listened_at': (listenedAt ?? DateTime.now())
                          .millisecondsSinceEpoch ~/
                      1000,
                  'track_metadata': {
                    'track_name': title,
                    'artist_name': artist,
                    if (album != null && album.isNotEmpty)
                      'release_name': album,
                  },
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      // Offline / instance down — drop it.
    }
  }

  /// The newest "created for you" playlist whose title matches
  /// [titleContains] (Weekly Jams / Weekly Exploration), as
  /// (title, artist) pairs. Empty when none exists yet — LB generates
  /// them weekly once enough listens accumulate.
  Future<List<(String title, String artist)>> createdForPlaylist(
    String user, {
    String titleContains = 'Weekly Jams',
  }) async {
    try {
      final listRes = await http
          .get(
            Uri.parse(
                '$host/1/user/${Uri.encodeComponent(user)}/playlists/createdfor'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 15));
      if (listRes.statusCode != 200) return const [];
      final playlists =
          (jsonDecode(listRes.body)['playlists'] as List?) ?? const [];

      String? mbid;
      for (final p in playlists) {
        final playlist = p['playlist'] as Map<String, dynamic>?;
        final title = playlist?['title'] as String? ?? '';
        if (!title.contains(titleContains)) continue;
        // identifier is a URL ending in the playlist MBID.
        final identifier = playlist?['identifier'] as String? ?? '';
        mbid = identifier.split('/').lastWhere((s) => s.isNotEmpty,
            orElse: () => '');
        if (mbid.isNotEmpty) break;
      }
      if (mbid == null || mbid.isEmpty) return const [];

      final plRes = await http
          .get(Uri.parse('$host/1/playlist/$mbid'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (plRes.statusCode != 200) return const [];
      final tracks = (jsonDecode(plRes.body)['playlist']?['track']
              as List?) ??
          const [];
      return [
        for (final t in tracks)
          if (t['title'] is String && (t['title'] as String).isNotEmpty)
            (t['title'] as String, (t['creator'] as String?) ?? ''),
      ];
    } catch (_) {
      return const [];
    }
  }
}
