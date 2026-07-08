import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../online/models/online_search_result.dart';
import '../library/models/track.dart';

/// A personalized YT Music home feed: direct-play songs (Quick Picks)
/// plus playlist / mix cards (the bulk of most feeds).
class YtHomeFeed {
  const YtHomeFeed({required this.songs, required this.playlists});
  final List<OnlineSearchResult> songs;
  final List<YtPlaylistCard> playlists;

  bool get isEmpty => songs.isEmpty && playlists.isEmpty;
}

/// A playlist / mix card on the home feed — resolved to tracks on tap.
class YtPlaylistCard {
  const YtPlaylistCard({
    required this.title,
    required this.playlistId,
    this.artUrl,
  });
  final String title;
  final String playlistId;
  final String? artUrl;
}

/// Tier 3 (ARCHITECTURE-RECOMMENDATIONS.md §4): the user's own YT Music
/// session, used to read their personalized feed. Authentication is
/// **cookie-based, never OAuth** — the WebView captures the logged-in
/// session cookies and we sign each Innertube request with a
/// SAPISIDHASH, exactly like the YT Music web client. No app is
/// registered with Google, so none of the OAuth "verify your app"
/// review applies.
///
/// Read-only by default: this signs feed/library reads only. Playback
/// still resolves anonymously through yt-dlp, so the account never
/// streams a byte (the risk reducer). "Report plays" is a separate,
/// off-by-default toggle handled by the provider layer.
class YtSession {
  YtSession({required this.cookie});

  /// The full `Cookie:` header string captured from the WebView (or a
  /// pasted / browser-imported cookies value on desktop).
  final String cookie;

  static const _origin = 'https://music.youtube.com';

  /// The SAPISID (or __Secure-3PAPISID) value from the cookie jar — the
  /// secret the auth hash is computed over.
  String? get _sapisid {
    for (final part in cookie.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length < 2) continue;
      if (kv[0] == 'SAPISID' || kv[0] == '__Secure-3PAPISID') {
        return kv.sublist(1).join('=');
      }
    }
    return null;
  }

  bool get looksSignedIn => _sapisid != null;

  /// `SAPISIDHASH <ts>_<sha1(ts SP sapisid SP origin)>` — the exact
  /// scheme the YT Music web client uses.
  String? _authHeader() {
    final sapisid = _sapisid;
    if (sapisid == null) return null;
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final digest = sha1.convert(utf8.encode('$ts $sapisid $_origin'));
    return 'SAPISIDHASH ${ts}_$digest';
  }

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        'Origin': _origin,
        'Cookie': cookie,
        'Authorization': _authHeader() ?? '',
        // The web client sends this; some endpoints 400 without it.
        'X-Goog-AuthUser': '0',
      };

  Map<String, dynamic> _context() => {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': '1.20250101.01.00',
          'hl': 'en',
        },
      };

  Future<Map<String, dynamic>?> _browse(String browseId) async {
    final auth = _authHeader();
    if (auth == null) return null;
    try {
      final res = await http
          .post(
            Uri.parse(
                'https://music.youtube.com/youtubei/v1/browse?prettyPrint=false'),
            headers: _headers(),
            body: jsonEncode({'context': _context(), 'browseId': browseId}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      return body is Map<String, dynamic> ? body : null;
    } catch (_) {
      return null;
    }
  }

  /// The signed-in YT Music home feed. Returns **songs** (Quick Picks —
  /// present once the account has listening history) *and* **playlist /
  /// mix cards** (what a fresh account's feed is mostly made of). Empty
  /// only when the session is invalid/expired — the caller treats that
  /// as "signed out" and prompts a re-login.
  Future<YtHomeFeed> homeFeed() async {
    final body = await _browse('FEmusic_home');
    if (body == null) return const YtHomeFeed(songs: [], playlists: []);

    final songItems = <Map<String, dynamic>>[];
    final cardItems = <Map<String, dynamic>>[];
    void walk(Object? node) {
      if (node is Map<String, dynamic>) {
        final song = node['musicResponsiveListItemRenderer'];
        if (song is Map<String, dynamic>) songItems.add(song);
        final card = node['musicTwoRowItemRenderer'];
        if (card is Map<String, dynamic>) cardItems.add(card);
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(body);

    final seenSong = <String>{};
    final songs = <OnlineSearchResult>[];
    for (final it in songItems) {
      final r = _toResult(it);
      if (r != null && seenSong.add(r.sourceId)) songs.add(r);
    }
    // A two-row card can be a song (watchEndpoint) or a playlist/album
    // (browseEndpoint) — route each to the right bucket.
    final seenPl = <String>{};
    final playlists = <YtPlaylistCard>[];
    for (final it in cardItems) {
      final vid = _findVideoId(it);
      if (vid != null) {
        final r = _toResult(it);
        if (r != null && seenSong.add(r.sourceId)) songs.add(r);
        continue;
      }
      final id = _findPlaylistId(it);
      final title =
          (it['title']?['runs'] as List?)?.first?['text'] as String?;
      if (id != null && title != null && seenPl.add(id)) {
        playlists.add(YtPlaylistCard(
          title: title,
          playlistId: id,
          artUrl: _findThumbs(it),
        ));
      }
    }
    return YtHomeFeed(songs: songs, playlists: playlists);
  }

  /// The songs inside a home-feed playlist / mix card, so tapping one
  /// plays it. browseId is the VL…/PL… id from the card.
  Future<List<OnlineSearchResult>> playlistTracks(String browseId) async {
    // A VL-prefixed id browses the playlist; a bare PL… needs the VL.
    final id = browseId.startsWith('VL') ? browseId : 'VL$browseId';
    final body = await _browse(id);
    if (body == null) return const [];
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

    walk(body);
    final seen = <String>{};
    final out = <OnlineSearchResult>[];
    for (final it in items) {
      final r = _toResult(it);
      if (r != null && seen.add(r.sourceId)) out.add(r);
    }
    return out;
  }

  /// The user's own playlists + liked songs, for library import.
  /// Returns (title, browseOrPlaylistId) pairs.
  Future<List<(String, String)>> libraryPlaylists() async {
    final body = await _browse('FEmusic_liked_playlists');
    if (body == null) return const [];
    final out = <(String, String)>[];
    void walk(Object? node) {
      if (node is Map<String, dynamic>) {
        final it = node['musicTwoRowItemRenderer'];
        if (it is Map<String, dynamic>) {
          final title =
              (it['title']?['runs'] as List?)?.first?['text'] as String?;
          final id = _findPlaylistId(it);
          if (title != null && id != null) out.add((title, id));
        }
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(body);
    return out;
  }

  static String? _findPlaylistId(Object? node) {
    if (node is Map<String, dynamic>) {
      final be = node['browseEndpoint'];
      if (be is Map<String, dynamic> && be['browseId'] is String) {
        final id = be['browseId'] as String;
        if (id.startsWith('VL') || id.startsWith('PL')) return id;
      }
      for (final v in node.values) {
        final r = _findPlaylistId(v);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _findPlaylistId(v);
        if (r != null) return r;
      }
    }
    return null;
  }

  OnlineSearchResult? _toResult(Map<String, dynamic> it) {
    try {
      final videoId = _findVideoId(it);
      if (videoId == null) return null;
      // musicTwoRowItemRenderer.title.runs / flexColumns for the list form.
      String? title =
          (it['title']?['runs'] as List?)?.first?['text'] as String?;
      String? artist =
          (it['subtitle']?['runs'] as List?)?.first?['text'] as String?;
      if (title == null) {
        final flex = (it['flexColumns'] as List?) ?? const [];
        if (flex.isNotEmpty) {
          title = flex[0]['musicResponsiveListItemFlexColumnRenderer']
              ?['text']?['runs']?.first?['text'] as String?;
        }
        if (flex.length > 1) {
          artist = flex[1]['musicResponsiveListItemFlexColumnRenderer']
              ?['text']?['runs']?.first?['text'] as String?;
        }
      }
      if (title == null || title.isEmpty) return null;
      return OnlineSearchResult(
        source: TrackSource.youtube,
        sourceId: videoId,
        title: title,
        artist: (artist == null || artist.isEmpty)
            ? 'Unknown artist'
            : artist,
        duration: Duration.zero,
        artUrl: _findThumbs(it),
      );
    } catch (_) {
      return null;
    }
  }

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

  /// Reports a play to the user's YT history ("report plays" toggle,
  /// off by default). Fire-and-forget; used only when the user opts
  /// into the feedback loop.
  Future<void> reportPlay(String videoId) async {
    final auth = _authHeader();
    if (auth == null) return;
    try {
      await http
          .post(
            Uri.parse(
                'https://music.youtube.com/youtubei/v1/player?prettyPrint=false'),
            headers: _headers(),
            body: jsonEncode({'context': _context(), 'videoId': videoId}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {}
  }

  /// Display-only Track for a home-feed card (no DB row until played).
  static Track ephemeral(OnlineSearchResult r) => Track(
        id: -1,
        title: r.title,
        artist: r.artist,
        album: r.album,
        duration: r.duration,
        source: r.source,
        sourceId: r.sourceId,
        artUrl: r.artUrl,
      );
}
