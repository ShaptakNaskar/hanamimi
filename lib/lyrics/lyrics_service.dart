import 'dart:convert';

import 'package:http/http.dart' as http;

import '../library/models/track.dart';
import 'lrc_parser.dart';
import 'models/lyric_line.dart';
import 'musixmatch_provider.dart';
import 'richsync_parser.dart';

/// Resolves lyrics for a track and picks the best:
///
///   word-synced > line-synced > plain.
///
/// Web edition: no file tags to read (the embedded source reports
/// nothing) and no DB — results are cached in memory for the session.
/// Musixmatch is attempted first for word-level richsync; browsers
/// that CORS-block it simply fall through to LRCLIB.
class LyricsService {
  LyricsService();

  /// Session cache, keyed "title|artist". Holds nulls too, so absent
  /// lyrics don't retrigger lookups on every open.
  static final _cache = <String, Lyrics?>{};

  /// Session cache for user-forced source fetches (keyed track:source),
  /// so switching back and forth in the sheet doesn't refetch.
  static final _sourceCache = <String, Lyrics?>{};

  static String _key(Track t) => '${t.title}|${t.artist}';

  /// Fetch from one specific source, ignoring the quality priority —
  /// backs the source picker in the lyrics sheet. Null when that
  /// source has nothing for this track.
  Future<Lyrics?> fetchFromSource(Track track, LyricsSource source) async {
    final key = '${track.id}:${source.name}';
    if (_sourceCache.containsKey(key)) return _sourceCache[key];

    Lyrics? result;
    switch (source) {
      case LyricsSource.embedded:
        // The web edition never reads tag lyrics — the browser would
        // have to re-scan the whole file for a rare payload.
        result = null;
      case LyricsSource.musixmatch:
        final rich = await MusixmatchProvider.fetchRichsyncJson(
          title: track.title,
          artist: track.artist,
          duration: track.duration,
        );
        result = rich == null ? null : RichsyncParser.parse(rich);
      case LyricsSource.lrclib:
        final raw = await _lrclibRaw(track);
        final text = raw?.synced ?? raw?.plain;
        result = text == null
            ? null
            : raw!.synced != null
                ? LrcParser.parseSynced(text)
                : LrcParser.parsePlain(text);
    }
    if (result != null && result.isEmpty) result = null;
    // A missing embedded tag is definitive; a network miss might just
    // be a bad connection — let those retry on the next probe.
    if (result != null || source == LyricsSource.embedded) {
      _sourceCache[key] = result;
    }
    return result;
  }

  /// Returns null when no lyrics exist for the track.
  Future<Lyrics?> fetchFor(Track track) async {
    final key = _key(track);
    if (_cache.containsKey(key)) return _cache[key];

    Lyrics? result;

    // Word-level first: Musixmatch richsync (browser CORS permitting).
    final rich = await MusixmatchProvider.fetchRichsyncJson(
      title: track.title,
      artist: track.artist,
      duration: track.duration,
    );
    if (rich != null) {
      final parsed = RichsyncParser.parse(rich);
      if (!parsed.isEmpty) result = parsed;
    }

    // Line-level fallback: LRCLIB.
    if (result == null) {
      final raw = await _lrclibRaw(track);
      if (raw == null) return null; // offline/server — retry next time
      final text = raw.synced ?? raw.plain;
      result = text == null
          ? null
          : raw.synced != null
              ? LrcParser.parseSynced(text)
              : LrcParser.parsePlain(text);
      if (result != null && result.isEmpty) result = null;
    }

    _cache[key] = result;
    return result;
  }

  /// Raw LRCLIB response; null means network trouble (don't cache),
  /// (null, null) fields mean a definitive "not found".
  Future<({String? synced, String? plain})?> _lrclibRaw(
      Track track) async {
    try {
      final uri = Uri.https('lrclib.net', '/api/get', {
        'track_name': track.title,
        'artist_name': track.artist,
        'album_name': track.album,
        'duration': track.duration.inSeconds.toString(),
      });
      final res =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return (
          synced: body['syncedLyrics'] as String?,
          plain: body['plainLyrics'] as String?,
        );
      }
      if (res.statusCode == 404) return (synced: null, plain: null);
      return null;
    } catch (_) {
      return null;
    }
  }
}
