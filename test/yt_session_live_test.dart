@Tags(['online'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/reco/yt_session.dart';

/// Live Tier 3 check against a real signed-in session. Not run in CI
/// (needs a cookie); run explicitly with the burner:
///   YT_COOKIE_FILE=/path/to/cookies.txt \
///     flutter test --run-skipped -t online test/yt_session_live_test.dart
///
/// Reads a Netscape cookies.txt (yt-dlp --cookies-from-browser output)
/// the same way DesktopYtDlp does, then drives the real YtSession.
void main() {
  final path = Platform.environment['YT_COOKIE_FILE'];

  test('authenticated home feed + playlist resolution', () async {
    if (path == null || !File(path).existsSync()) {
      markTestSkipped('set YT_COOKIE_FILE to a cookies.txt to run');
      return;
    }
    final header = _cookieHeader(File(path).readAsStringSync());
    final session = YtSession(cookie: header);
    expect(session.looksSignedIn, isTrue,
        reason: 'cookies.txt must carry a SAPISID');

    final feed = await session.homeFeed();
    expect(feed.isEmpty, isFalse,
        reason: 'a signed-in feed has songs and/or playlist cards');
    // ignore: avoid_print
    print('home feed: ${feed.songs.length} songs, '
        '${feed.playlists.length} playlist cards');

    if (feed.playlists.isNotEmpty) {
      final card = feed.playlists.first;
      final tracks = await session.playlistTracks(card.playlistId);
      expect(tracks, isNotEmpty,
          reason: 'a home-feed playlist resolves to tracks');
      // ignore: avoid_print
      print('"${card.title}" → ${tracks.length} tracks, '
          'e.g. ${tracks.take(3).map((t) => t.title)}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

String _cookieHeader(String netscape) {
  final pairs = <String>[];
  for (final line in netscape.split('\n')) {
    if (line.startsWith('#') || line.trim().isEmpty) continue;
    final cols = line.split('\t');
    if (cols.length < 7) continue;
    if (!cols[0].contains('youtube.com') && !cols[0].contains('google.com')) {
      continue;
    }
    pairs.add('${cols[5]}=${cols[6]}');
  }
  return pairs.join('; ');
}
