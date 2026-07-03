import 'dart:convert';

import 'package:http/http.dart' as http;

import '../library/library_repository.dart';
import '../library/models/track.dart';
import 'embedded_lyrics.dart';
import 'lrc_parser.dart';
import 'models/lyric_line.dart';
import 'musixmatch_provider.dart';

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
        return quality >= 1
            ? LrcParser.parseSynced(text,
                source: quality == 2
                    ? LyricsSource.musixmatch
                    : LyricsSource.lrclib)
            : LrcParser.parsePlain(text);
      }
    }

    // Word-level first: Musixmatch richsync.
    final rich = await MusixmatchProvider.fetchEnhancedLrc(
      title: track.title,
      artist: track.artist,
      duration: track.duration,
    );
    if (rich != null) {
      await _repo.cacheLyrics(track.title, track.artist, rich, 2);
      return LrcParser.parseSynced(rich, source: LyricsSource.musixmatch);
    }

    // Line-level fallback: LRCLIB.
    String? synced;
    String? plain;
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
        synced = body['syncedLyrics'] as String?;
        plain = body['plainLyrics'] as String?;
      } else if (res.statusCode != 404) {
        return null; // server trouble — don't cache, retry next time
      }
    } catch (_) {
      return null; // offline — don't cache, retry when back online
    }

    final text = synced ?? plain ?? '';
    await _repo.cacheLyrics(
        track.title, track.artist, text, synced != null ? 1 : 0);
    if (text.isEmpty) return null;
    return synced != null
        ? LrcParser.parseSynced(text)
        : LrcParser.parsePlain(text);
  }
}
