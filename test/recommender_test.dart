import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/library/models/track.dart';
import 'package:hanamimi/reco/recommender.dart';

/// M38c: the Tier 0 blended recommender over synthetic listening data.
void main() {
  final now = DateTime(2026, 7, 8, 20);

  Track track(int id, String title, String artist,
          {String album = '',
          int playCount = 0,
          DateTime? lastPlayed,
          bool liked = false}) =>
      Track(
        id: id,
        title: title,
        artist: artist,
        album: album,
        duration: const Duration(minutes: 3),
        playCount: playCount,
        lastPlayed: lastPlayed,
        liked: liked,
      );

  Uint8List vec(List<double> v) =>
      Float32List.fromList(v).buffer.asUint8List();

  test('cold start: no history → empty shelf, station still plays', () {
    final tracks = [
      for (var i = 0; i < 10; i++) track(i, 'Song $i', 'Artist ${i % 3}'),
    ];
    final rec = Recommender(
        RecoData(tracks: tracks, coPlay: {}, skips: {}, features: {}),
        now: now,
        rng: math.Random(42));
    expect(rec.forYou(), isEmpty);
    // Station from a seed still fills up (artist pad, then random).
    final station = rec.station(tracks.first, length: 8);
    expect(station, hasLength(8));
    expect(station.first.id, tracks.first.id);
    expect(station.map((t) => t.id).toSet(), hasLength(8));
  });

  test('co-play neighbours of heavy rotation land in For you', () {
    final heavy = track(1, 'Anthem', 'A',
        playCount: 30, lastPlayed: now.subtract(const Duration(hours: 5)));
    final neighbour = track(2, 'Companion', 'B');
    final stranger = track(3, 'Stranger', 'C');
    final rec = Recommender(
        RecoData(
          tracks: [heavy, neighbour, stranger],
          coPlay: {
            1: {2: 9},
          },
          skips: {},
          features: {},
        ),
        now: now,
        rng: math.Random(1));
    final picks = rec.forYou();
    expect(picks.map((t) => t.id), contains(2));
    expect(picks.map((t) => t.id), isNot(contains(3)));
  });

  test('skips push a track out of the shelf', () {
    final heavy = track(1, 'Anthem', 'A',
        playCount: 30, lastPlayed: now.subtract(const Duration(hours: 5)));
    // Both point at the anchor equally; one gets skipped a lot.
    final liked = track(2, 'Kept', 'B');
    final skipped = track(3, 'Skipped', 'B');
    final rec = Recommender(
        RecoData(
          tracks: [heavy, liked, skipped],
          coPlay: {
            1: {2: 5, 3: 5},
          },
          skips: {3: 4},
          features: {},
        ),
        now: now);
    final ids = rec.forYou().map((t) => t.id).toList();
    expect(ids, contains(2));
    // Skip penalty (4 × 0.25 = 1.0) wipes out its co-play score.
    expect(ids, isNot(contains(3)));
  });

  test('content similarity recommends sound-alikes of favorites', () {
    final fav = track(1, 'Warm', 'A',
        playCount: 20,
        liked: true,
        lastPlayed: now.subtract(const Duration(days: 1)));
    final alike = track(2, 'Warm too', 'B');
    final different = track(3, 'Harsh', 'C');
    final warm = <double>[1, 0.8, 0.5, 0.2, 0.1, 0.05, 0, 0, 0, 0, 0, 0];
    final bright = <double>[0, 0, 0, 0, 0, 0, 0.1, 0.2, 0.5, 0.8, 1, 0.9];
    final rec = Recommender(
        RecoData(
          tracks: [fav, alike, different],
          coPlay: {},
          skips: {},
          features: {
            1: vec(warm),
            2: vec([for (final v in warm) v * 0.9]),
            3: vec(bright),
          },
        ),
        now: now);
    final ids = rec.forYou().map((t) => t.id).toList();
    expect(ids, contains(2));
    expect(ids.indexOf(2), lessThan(math.max(ids.indexOf(3), ids.length)));
  });

  test('station walks the co-play chain', () {
    final a = track(1, 'A', 'X', playCount: 5, lastPlayed: now);
    final b = track(2, 'B', 'X');
    final c = track(3, 'C', 'Y');
    final rec = Recommender(
        RecoData(
          tracks: [a, b, c],
          coPlay: {
            1: {2: 10},
            2: {3: 10},
          },
          skips: {},
          features: {},
        ),
        now: now,
        rng: math.Random(7));
    final station = rec.station(a, length: 3);
    expect(station.map((t) => t.id).toList(), [1, 2, 3]);
  });

  test('shuffle weight: favorites > fresh > skipped, never zero', () {
    final rec = Recommender(
        RecoData(tracks: const [], coPlay: {}, skips: {9: 10}, features: {}),
        now: now);
    final favorite = track(1, 'Fav', 'A', playCount: 40, liked: true);
    final fresh = track(2, 'Fresh', 'B');
    final skipped = track(9, 'Nope', 'C');
    expect(rec.shuffleWeight(favorite),
        greaterThan(rec.shuffleWeight(fresh)));
    expect(rec.shuffleWeight(fresh),
        greaterThan(rec.shuffleWeight(skipped)));
    expect(rec.shuffleWeight(skipped), greaterThan(0));
  });

  test('one artist cannot own the whole shelf', () {
    final anchor = track(1, 'Anchor', 'Anchor Artist',
        playCount: 50, lastPlayed: now.subtract(const Duration(hours: 2)));
    final tracks = [
      anchor,
      // 8 tracks by the anchor's artist, all metadata-boosted.
      for (var i = 2; i <= 9; i++)
        track(i, 'Same $i', 'Anchor Artist'),
    ];
    final rec = Recommender(
        RecoData(tracks: tracks, coPlay: {}, skips: {}, features: {}),
        now: now);
    final picks = rec.forYou();
    expect(picks.where((t) => t.artist == 'Anchor Artist').length,
        lessThanOrEqualTo(3));
  });
}
