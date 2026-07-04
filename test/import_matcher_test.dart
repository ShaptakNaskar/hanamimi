import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/library/models/track.dart';
import 'package:hanamimi/online/import/import_models.dart';
import 'package:hanamimi/online/models/online_search_result.dart';

void main() {
  group('normalizeForMatch', () {
    test('strips feature credits, remaster/version tags, brackets', () {
      expect(normalizeForMatch('Song (feat. Someone)'), 'song');
      expect(normalizeForMatch('Title - Remastered 2011'), 'title');
      expect(normalizeForMatch('Name (2019 Remaster)'), 'name');
      expect(normalizeForMatch('Track [Radio Edit]'), 'track');
      expect(normalizeForMatch('A ft. B'), 'a');
    });

    test('lowercases and collapses punctuation/space', () {
      expect(normalizeForMatch('  Hello,   World!! '), 'hello world');
    });
  });

  group('tokenSimilarity', () {
    test('identical → 1, disjoint → 0', () {
      expect(tokenSimilarity('midnight city', 'midnight city'), 1.0);
      expect(tokenSimilarity('abc', 'xyz'), 0.0);
    });

    test('partial overlap is between', () {
      final s = tokenSimilarity('best day of my life', 'best day life');
      expect(s, greaterThan(0.4));
      expect(s, lessThan(1.0));
    });
  });

  group('matchScore', () {
    OnlineSearchResult hit(String title, String artist, int sec) =>
        OnlineSearchResult(
          source: TrackSource.youtube,
          sourceId: 'x',
          title: title,
          artist: artist,
          duration: Duration(seconds: sec),
        );

    test('exact title+artist+duration scores high', () {
      const want = ImportedTrack(
          title: 'Midnight City', artist: 'M83', durationMs: 240000);
      final score = matchScore(want, hit('Midnight City', 'M83', 240));
      expect(score, greaterThan(0.9));
    });

    test('wrong song scores low', () {
      const want = ImportedTrack(
          title: 'Midnight City', artist: 'M83', durationMs: 240000);
      final score =
          matchScore(want, hit('Completely Different', 'Other Band', 120));
      expect(score, lessThan(0.3));
    });

    test('feature-credit noise still matches the same song', () {
      const want = ImportedTrack(
          title: 'Good Things Fall Apart (with Jon Bellion)',
          artist: 'ILLENIUM',
          durationMs: 217000);
      final score = matchScore(
          want, hit('Good Things Fall Apart', 'ILLENIUM, Jon Bellion', 217));
      expect(score, greaterThan(0.55)); // above the auto-accept threshold
    });

    test('duration mismatch drags the score down', () {
      const want =
          ImportedTrack(title: 'Song', artist: 'Artist', durationMs: 180000);
      final near = matchScore(want, hit('Song', 'Artist', 181));
      final far = matchScore(want, hit('Song', 'Artist', 400));
      expect(near, greaterThan(far));
    });
  });

  group('detectImportSource', () {
    test('recognizes YouTube and Spotify URLs', () {
      expect(detectImportSource('https://youtube.com/playlist?list=PL1'),
          ImportSource.youtube);
      expect(detectImportSource('https://music.youtube.com/playlist?list=PL1'),
          ImportSource.youtube);
      expect(detectImportSource('https://open.spotify.com/playlist/abc'),
          ImportSource.spotify);
      expect(detectImportSource('spotify:playlist:abc'), ImportSource.spotify);
      expect(detectImportSource('https://example.com'), ImportSource.unknown);
    });
  });
}
