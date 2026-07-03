import 'dart:convert';

import 'package:http/http.dart' as http;

import '../library/library_repository.dart';
import '../library/models/track.dart';
import 'embedded_lyrics.dart';
import 'lrc_parser.dart';
import 'models/lyric_line.dart';
import 'musixmatch_provider.dart';
import 'richsync_parser.dart';

/// Resolves lyrics for a track from three sources and picks the best:
///
///   word-synced > line-synced > plain,  ties go to embedded (offline).
///
/// Sources: the file's own tags (ID3 USLT / FLAC comments), Musixmatch
/// richsync (true word-level timings), and LRCLIB (line-level).
/// Network results are cached locally for 30 days — including "not
/// found", so absent lyrics don't retrigger lookups on every open.
class LyricsService {
  LyricsService(this._repo);

  final LibraryRepository _repo;
  static const _maxCacheAge = Duration(days: 30);

  /// Session cache for user-forced source fetches (keyed track:source),
  /// so switching back and forth in the sheet doesn't refetch.
  static final _sourceCache = <String, Lyrics?>{};

  /// Fetch from one specific source, ignoring the quality priority —
  /// backs the source picker in the lyrics sheet. Null when that
  /// source has nothing for this track.
  Future<Lyrics?> fetchFromSource(Track track, LyricsSource source) async {
    final key = '${track.id}:${source.name}';
    if (_sourceCache.containsKey(key)) return _sourceCache[key];

    Lyrics? result;
    switch (source) {
      case LyricsSource.embedded:
        final text = await EmbeddedLyricsReader.read(track.filePath);
        result = text == null
            ? null
            : LrcParser.parseAuto(text, source: LyricsSource.embedded);
      case LyricsSource.musixmatch:
        // The 30-day DB cache first — a forced switch shouldn't fail
        // just because the network is down right now.
        result = await _cachedForSource(track, source);
        if (result == null) {
          final rich = await MusixmatchProvider.fetchRichsyncJson(
            title: track.title,
            artist: track.artist,
            duration: track.duration,
          );
          result = rich == null ? null : RichsyncParser.parse(rich);
          if (result != null && !result.isEmpty) {
            // Word-synced is the top quality — safe to promote the
            // shared cache row (auto prefers it anyway).
            await _repo.cacheLyrics(track.title, track.artist, rich!, 2);
          }
        }
      case LyricsSource.lrclib:
        result = await _cachedForSource(track, source);
        if (result == null) {
          final raw = await _lrclibRaw(track);
          final text = raw?.synced ?? raw?.plain;
          result = text == null
              ? null
              : raw!.synced != null
                  ? LrcParser.parseSynced(text)
                  : LrcParser.parsePlain(text);
        }
    }
    if (result != null && result.isEmpty) result = null;
    // A missing embedded tag is definitive; a network miss might just
    // be a bad connection — let those retry on the next probe.
    if (result != null || source == LyricsSource.embedded) {
      _sourceCache[key] = result;
    }
    return result;
  }

  /// What the shared DB cache holds for this track, but only when that
  /// entry actually came from [source]: quality-2 rows are Musixmatch
  /// richsync, quality 0/1 rows are LRCLIB.
  Future<Lyrics?> _cachedForSource(Track track, LyricsSource source) async {
    final cached = await _repo.cachedLyrics(track.title, track.artist);
    if (cached == null) return null;
    final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(cached['cached_at'] as int));
    if (age >= _maxCacheAge) return null;
    final text = cached['lrc_text'] as String;
    if (text.isEmpty) return null;
    final quality = cached['quality'] as int? ?? 0;
    switch (source) {
      case LyricsSource.musixmatch:
        if (quality == 2 && RichsyncParser.looksLikeRichsync(text)) {
          return RichsyncParser.parse(text);
        }
      case LyricsSource.lrclib:
        if (quality == 1) return LrcParser.parseSynced(text);
        if (quality == 0) return LrcParser.parsePlain(text);
      case LyricsSource.embedded:
        break;
    }
    return null;
  }

  /// Returns null when no lyrics exist for the track.
  Future<Lyrics?> fetchFor(Track track) async {
    final embeddedText = await EmbeddedLyricsReader.read(track.filePath);
    final embedded = embeddedText == null
        ? null
        : LrcParser.parseAuto(embeddedText, source: LyricsSource.embedded);

    // Word-synced embedded lyrics can't be beaten — skip the network.
    if (embedded != null && embedded.quality == 2) return embedded;

    final fetched = await _fetchRemote(track);

    if (embedded == null) return fetched;
    if (fetched == null) return embedded;
    return fetched.quality > embedded.quality ? fetched : embedded;
  }

  Future<Lyrics?> _fetchRemote(Track track) async {
    final cached = await _repo.cachedLyrics(track.title, track.artist);
    if (cached != null) {
      final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(cached['cached_at'] as int));
      if (age < _maxCacheAge) {
        final text = cached['lrc_text'] as String;
        if (text.isEmpty) return null; // cached "not found"
        final quality = cached['quality'] as int? ?? 0;
        if (quality == 2 && RichsyncParser.looksLikeRichsync(text)) {
          return RichsyncParser.parse(text);
        }
        if (quality == 1) return LrcParser.parseSynced(text);
        if (quality == 0) return LrcParser.parsePlain(text);
        // quality 2 in legacy enhanced-LRC format: it lost the line-end
        // times, which makes highlights bleed across instrumental
        // breaks — fall through and refetch as richsync JSON.
      }
    }

    // Word-level first: Musixmatch richsync.
    final rich = await MusixmatchProvider.fetchRichsyncJson(
      title: track.title,
      artist: track.artist,
      duration: track.duration,
    );
    if (rich != null) {
      final parsed = RichsyncParser.parse(rich);
      if (!parsed.isEmpty) {
        await _repo.cacheLyrics(track.title, track.artist, rich, 2);
        return parsed;
      }
    }

    // Line-level fallback: LRCLIB.
    final raw = await _lrclibRaw(track);
    if (raw == null) return null; // offline/server — retry next time

    final text = raw.synced ?? raw.plain ?? '';
    await _repo.cacheLyrics(
        track.title, track.artist, text, raw.synced != null ? 1 : 0);
    if (text.isEmpty) return null;
    return raw.synced != null
        ? LrcParser.parseSynced(text)
        : LrcParser.parsePlain(text);
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
      final res = await http
          .get(uri, headers: {'User-Agent': 'Hanamimi/0.1 (music player)'})
          .timeout(const Duration(seconds: 10));
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
