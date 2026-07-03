import 'dart:convert';

import 'package:http/http.dart' as http;

import '../library/library_repository.dart';
import '../library/models/track.dart';
import 'lrc_parser.dart';
import 'models/lyric_line.dart';

/// Fetches lyrics from LRCLIB (free, keyless) with a 30-day local cache.
class LyricsService {
  LyricsService(this._repo);

  final LibraryRepository _repo;
  static const _maxCacheAge = Duration(days: 30);

  /// Returns null when no lyrics exist for the track.
  Future<Lyrics?> fetchFor(Track track) async {
    final cached = await _repo.cachedLyrics(track.title, track.artist);
    if (cached != null) {
      final age = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(cached['cached_at'] as int));
      if (age < _maxCacheAge) {
        final text = cached['lrc_text'] as String;
        if (text.isEmpty) return null; // cached "not found"
        return (cached['is_timestamped'] as int) != 0
            ? LrcParser.parseSynced(text)
            : LrcParser.parsePlain(text);
      }
    }

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
        track.title, track.artist, text, synced != null);
    if (text.isEmpty) return null;
    return synced != null
        ? LrcParser.parseSynced(text)
        : LrcParser.parsePlain(text);
  }
}
