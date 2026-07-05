import 'dart:convert';

import 'package:http/http.dart' as http;

import 'import_models.dart';

/// Reads a **public** Spotify playlist without login, via the embed
/// page (`open.spotify.com/embed/playlist/<id>`), whose inline
/// `__NEXT_DATA__` JSON carries the track list (title + artist +
/// duration). Metadata only — entries are matched to YouTube/JioSaavn
/// downstream. Private playlists need OAuth (deferred, see
/// ARCHITECTURE-IMPORT.md). Best-effort: empty on any failure.
class SpotifyPlaylistSource {
  /// Extracts the playlist id from a Spotify URL / URI.
  /// `open.spotify.com/playlist/<id>`, `spotify:playlist:<id>`.
  static String? playlistId(String url) {
    final m = RegExp(r'playlist[/:]([A-Za-z0-9]+)').firstMatch(url.trim());
    return m?.group(1);
  }

  Future<(String, List<ImportedTrack>)> fetch(String url) async {
    final id = playlistId(url);
    if (id == null) return ('', const <ImportedTrack>[]);
    try {
      final res = await http.get(
        Uri.parse('https://open.spotify.com/embed/playlist/$id'),
        headers: {
          // The embed page gates on a browser-ish UA.
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Hanamimi/1.0',
        },
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return ('', const <ImportedTrack>[]);

      final json = _extractNextData(res.body);
      if (json == null) return ('', const <ImportedTrack>[]);

      final name = _title(json) ?? 'Spotify playlist';
      final entries = <ImportedTrack>[];
      _collect(json, entries);
      return (name, entries);
    } catch (_) {
      return ('', const <ImportedTrack>[]);
    }
  }

  /// Pulls the JSON out of `<script id="__NEXT_DATA__" ...>{…}</script>`.
  Map<String, dynamic>? _extractNextData(String html) {
    final marker = RegExp(
        r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>',
        dotAll: true);
    final m = marker.firstMatch(html);
    if (m == null) return null;
    try {
      final decoded = jsonDecode(m.group(1)!);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Walk for track objects: Spotify's embed uses
  /// {title, subtitle, duration, isExplicit, uri, …} in a trackList.
  /// Defensive — matches any object carrying title + subtitle (+ maybe
  /// duration) to survive shape drift.
  void _collect(Object? node, List<ImportedTrack> out) {
    if (node is Map<String, dynamic>) {
      final title = node['title'];
      final subtitle = node['subtitle'];
      final uri = node['uri']?.toString() ?? '';
      final isTrack = uri.contains(':track:');
      // The playlist's OWN entity node also carries title + subtitle +
      // duration (playlist name / owner / total length), so it used to be
      // scooped up and "searched" as a bogus song. Skip anything that's a
      // non-track entity (playlist/album/artist/show/episode).
      final isEntity = uri.contains(':playlist:') ||
          uri.contains(':album:') ||
          uri.contains(':artist:') ||
          uri.contains(':show:') ||
          uri.contains(':episode:');
      if (title is String &&
          title.isNotEmpty &&
          subtitle is String &&
          !isEntity &&
          (isTrack || node.containsKey('duration'))) {
        final durMs = _durationMs(node['duration']);
        out.add(ImportedTrack(
          title: title,
          artist: subtitle,
          durationMs: durMs,
        ));
      }
      for (final v in node.values) { _collect(v, out); }
    } else if (node is List) {
      for (final v in node) { _collect(v, out); }
    }
  }

  int? _durationMs(Object? d) {
    if (d is int) return d; // already ms
    if (d is num) return d.toInt();
    if (d is String) return int.tryParse(d);
    return null;
  }

  String? _title(Object? node) {
    // The playlist's own name sits under entity/title near the root.
    if (node is Map<String, dynamic>) {
      final entity = node['entity'];
      if (entity is Map<String, dynamic> && entity['title'] is String) {
        return entity['title'] as String;
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
}
