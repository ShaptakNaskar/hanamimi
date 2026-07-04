import 'dart:convert';

import 'package:http/http.dart' as http;

import 'import_models.dart';

/// Reads a YouTube / YT-Music playlist via Innertube `browse` — the same
/// keyless private API the search already rides. Entries carry their
/// videoId directly, so no matching is needed downstream.
class YtPlaylistSource {
  static const _base =
      'https://www.youtube.com/youtubei/v1/browse?prettyPrint=false';

  static Map<String, dynamic> _context() => {
        'client': {
          'clientName': 'WEB',
          'clientVersion': '2.20250101.00.00',
          'hl': 'en',
        },
      };

  /// Extracts the playlist id from any YouTube playlist URL form.
  /// `list=PL…`, `/playlist?list=…`, `music.youtube.com/playlist?list=…`.
  static String? playlistId(String url) {
    final uri = Uri.tryParse(url.trim());
    final fromQuery = uri?.queryParameters['list'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    final m = RegExp(r'[?&]list=([A-Za-z0-9_-]+)').firstMatch(url);
    return m?.group(1);
  }

  /// (playlistTitle, entries). Empty entries on failure — best-effort.
  Future<(String, List<ImportedTrack>)> fetch(
    String url, {
    void Function(int fetched)? onProgress,
  }) async {
    final id = playlistId(url);
    if (id == null) return ('', const <ImportedTrack>[]);
    try {
      var body = await _browse({'browseId': 'VL$id'});
      if (body == null) return ('', const <ImportedTrack>[]);

      final title = _title(body) ?? 'YouTube playlist';
      final entries = <ImportedTrack>[];
      _collect(body, entries);
      onProgress?.call(entries.length);

      // Follow continuations (playlists page at ~100).
      var token = _continuation(body);
      var guard = 0;
      while (token != null && guard++ < 40) {
        body = await _browse({'continuation': token});
        if (body == null) break;
        final before = entries.length;
        _collect(body, entries);
        onProgress?.call(entries.length);
        if (entries.length == before) break; // no progress; stop
        token = _continuation(body);
      }
      return (title, entries);
    } catch (_) {
      return ('', const <ImportedTrack>[]);
    }
  }

  Future<Map<String, dynamic>?> _browse(Map<String, dynamic> extra) async {
    final res = await http
        .post(Uri.parse(_base),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'context': {'client': _context()['client']}, ...extra}))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// Walk every video entry. The WEB client moved from
  /// `playlistVideoRenderer` to `lockupViewModel` (2025); support both.
  void _collect(Object? node, List<ImportedTrack> out) {
    if (node is Map<String, dynamic>) {
      final lockup = node['lockupViewModel'];
      if (lockup is Map<String, dynamic>) {
        final t = _fromLockup(lockup);
        if (t != null) out.add(t);
      }
      final vr = node['playlistVideoRenderer'];
      if (vr is Map<String, dynamic>) {
        final t = _fromRenderer(vr);
        if (t != null) out.add(t);
      }
      for (final v in node.values) {
        _collect(v, out);
      }
    } else if (node is List) {
      for (final v in node) {
        _collect(v, out);
      }
    }
  }

  /// Modern lockupViewModel: contentId=videoId, title/artist under
  /// lockupMetadataViewModel, duration in the thumbnail overlay badge.
  ImportedTrack? _fromLockup(Map<String, dynamic> lv) {
    if (lv['contentType'] != 'LOCKUP_CONTENT_TYPE_VIDEO') return null;
    final videoId = lv['contentId'] as String?;
    final meta =
        lv['metadata']?['lockupMetadataViewModel'] as Map<String, dynamic>?;
    final title = meta?['title']?['content'] as String?;
    if (videoId == null || title == null) return null;

    // First metadata part is the channel/artist ("M83").
    String? artist;
    final rows = meta?['metadata']?['contentMetadataViewModel']
        ?['metadataRows'] as List?;
    outer:
    for (final row in rows ?? const []) {
      for (final part in (row?['metadataParts'] as List?) ?? const []) {
        final t = part?['text']?['content'] as String?;
        if (t != null && t.isNotEmpty) {
          artist = t;
          break outer;
        }
      }
    }

    // Duration badge ("3:32" / "1:02:14") sits as text in the thumbnail.
    int? durMs;
    final img = jsonEncode(lv['contentImage'] ?? const {});
    final m = RegExp(r'"(\d{1,2}:\d{2}(?::\d{2})?)"').firstMatch(img);
    if (m != null) durMs = _hmsToMs(m.group(1)!);

    return ImportedTrack(
      title: title,
      artist: artist ?? '',
      durationMs: durMs,
      youtubeId: videoId,
    );
  }

  /// Legacy playlistVideoRenderer (kept as a fallback).
  ImportedTrack? _fromRenderer(Map<String, dynamic> r) {
    final videoId = r['videoId'] as String?;
    final title = (r['title']?['runs'] as List?)?.first?['text'] as String?;
    if (videoId == null || title == null) return null;
    final artist = (r['shortBylineText']?['runs'] as List?)?.first?['text']
        as String?;
    final lenS = int.tryParse(r['lengthSeconds']?.toString() ?? '');
    return ImportedTrack(
      title: title,
      artist: artist ?? '',
      durationMs: lenS == null ? null : lenS * 1000,
      youtubeId: videoId,
    );
  }

  static int? _hmsToMs(String hms) {
    final parts = hms.split(':').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) return null;
    var s = 0;
    for (final p in parts) {
      s = s * 60 + p!;
    }
    return s * 1000;
  }

  String? _title(Object? node) {
    if (node is Map<String, dynamic>) {
      // metadata.playlistMetadataRenderer.title (WEB 2025).
      final pm = node['playlistMetadataRenderer'];
      if (pm is Map<String, dynamic> && pm['title'] is String) {
        return pm['title'] as String;
      }
      final mf = node['microformatDataRenderer'];
      if (mf is Map<String, dynamic> && mf['title'] is String) {
        return mf['title'] as String;
      }
      final h = node['playlistHeaderRenderer'];
      if (h is Map<String, dynamic>) {
        final t = (h['title']?['runs'] as List?)?.first?['text'] ??
            (h['title']?['simpleText']);
        if (t is String) return t;
      }
      for (final v in node.values) {
        final r = _title(v);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _title(v);
        if (r != null) return r;
      }
    }
    return null;
  }

  String? _continuation(Object? node) {
    if (node is Map<String, dynamic>) {
      final tok = node['continuationCommand']?['token'] ??
          node['continuationEndpoint']?['continuationCommand']?['token'];
      if (tok is String) return tok;
      for (final v in node.values) {
        final r = _continuation(v);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _continuation(v);
        if (r != null) return r;
      }
    }
    return null;
  }
}
