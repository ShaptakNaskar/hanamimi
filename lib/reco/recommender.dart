import 'dart:math' as math;
import 'dart:typed_data';

import '../library/models/track.dart';
import '../utils/track_identity.dart';
import 'feature_extractor.dart';

/// Everything the on-device recommender reads, loaded in one shot from
/// the repository (M38a's accrued signals + the library itself).
class RecoData {
  const RecoData({
    required this.tracks,
    required this.coPlay,
    required this.skips,
    required this.features,
    this.hourSeconds = const {},
  });

  final List<Track> tracks;

  /// from-track id → {to-track id: transition count}.
  final Map<int, Map<int, int>> coPlay;

  /// track id → skip count (only tracks ever skipped).
  final Map<int, int> skips;

  /// track id → raw float32 feature vector (only decoded tracks).
  final Map<int, Uint8List> features;

  /// 3.0 #5: identity_key → seconds listened during the current
  /// hour-of-day window, straight off the listen_history log. "3am-you
  /// has different taste than 3pm-you" — the cheapest context signal
  /// there is. Empty on fresh installs; the boost simply contributes 0.
  final Map<String, int> hourSeconds;

  static const empty = RecoData(
      tracks: [], coPlay: {}, skips: {}, features: {});
}

/// The Tier 0 engine (ARCHITECTURE-RECOMMENDATIONS.md §3): blends
/// behaviour (recency-weighted plays, co-play transitions, skips),
/// content (audio-feature similarity) and metadata (artists, albums,
/// likes) into scores. Pure — no IO, no network, trivially testable.
class Recommender {
  Recommender(this.data, {DateTime? now, math.Random? rng})
      : _now = now ?? DateTime.now(),
        _rng = rng ?? math.Random();

  final RecoData data;
  final DateTime _now;
  final math.Random _rng;

  /// Recency-weighted affinity — "how much does this track define my
  /// taste right now". Half-life ~ a month and a half.
  double _anchorAffinity(Track t) {
    final last = t.lastPlayed;
    final recency = last == null
        ? 0.0
        : math.exp(-_now.difference(last).inHours / (45 * 24));
    return t.playCount * recency + (t.liked ? 2.0 : 0.0);
  }

  double _skipPenalty(int id) =>
      math.min((data.skips[id] ?? 0) * 0.25, 1.0);

  /// Hour-of-day affinity, 0–1: how much this song belongs to *this*
  /// hour, log-scaled so one long night doesn't dominate forever.
  /// Identity keys are cached per track id — normalization is regex
  /// work and forYou() touches every library row.
  final _identityCache = <int, String>{};
  double _hourBoost(Track t) {
    if (data.hourSeconds.isEmpty) return 0;
    final key = _identityCache[t.id] ??= identityKey(
        title: t.title, artist: t.artist, duration: t.duration);
    final s = data.hourSeconds[key];
    if (s == null || s <= 0) return 0;
    // ~200s in-window ≈ 0.5, saturating toward 1 around ~2h.
    return math.min(math.log(1 + s / 60) / math.log(1 + 120), 1.0);
  }

  /// The user's current taste anchors: heavy rotation + likes.
  List<Track> anchors({int limit = 12}) {
    final scored = data.tracks
        .map((t) => (t, _anchorAffinity(t)))
        .where((e) => e.$2 > 0)
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return [for (final e in scored.take(limit)) e.$1];
  }

  /// "For you": tracks the anchors point at — via co-play transitions,
  /// audio similarity and shared artists — minus what's already on the
  /// Jump-back-in shelf. Cold start degrades gracefully: with no play
  /// history everything scores ~0 and the shelf simply stays hidden.
  List<Track> forYou({int limit = 20}) {
    final anchorTracks = anchors();
    if (anchorTracks.isEmpty) return const [];
    final anchorIds = {for (final a in anchorTracks) a.id};
    final anchorArtists = {for (final a in anchorTracks) a.artist};
    final anchorAlbums = {
      for (final a in anchorTracks)
        if (a.album.isNotEmpty) a.album,
    };
    final likedArtists = {
      for (final t in data.tracks)
        if (t.liked) t.artist,
    };

    // The freshest listens live on the Jump-back-in shelf already.
    final recent = data.tracks
        .where((t) => t.lastPlayed != null)
        .toList()
      ..sort((a, b) => b.lastPlayed!.compareTo(a.lastPlayed!));
    final shelfDuplicates = {
      for (final t in recent.take(8)) t.id,
    };

    // Max normalized co-play mass flowing from the anchors.
    final coMass = <int, double>{};
    for (final a in anchorTracks) {
      final row = data.coPlay[a.id];
      if (row == null || row.isEmpty) continue;
      final rowMax = row.values.reduce(math.max).toDouble();
      row.forEach((to, count) {
        coMass[to] = (coMass[to] ?? 0) + count / rowMax;
      });
    }
    final coMax = coMass.isEmpty
        ? 1.0
        : coMass.values.reduce(math.max);

    final anchorVecs = [
      for (final a in anchorTracks)
        if (data.features[a.id] != null) data.features[a.id]!,
    ];

    final scored = <(Track, double)>[];
    for (final t in data.tracks) {
      if (anchorIds.contains(t.id) || shelfDuplicates.contains(t.id)) {
        continue;
      }
      final co = (coMass[t.id] ?? 0) / coMax;

      var content = 0.0;
      final vec = data.features[t.id];
      if (vec != null) {
        for (final av in anchorVecs) {
          final sim = featureSimilarity(vec, av);
          if (sim > content) content = sim;
        }
      }

      var meta = 0.0;
      if (anchorArtists.contains(t.artist)) meta += 0.6;
      if (likedArtists.contains(t.artist)) meta += 0.2;
      if (anchorAlbums.contains(t.album)) meta += 0.2;

      // Rediscovery: a once-loved track that's drifted out of rotation.
      final last = t.lastPlayed;
      final dormant = last != null &&
          _now.difference(last).inDays > 14 &&
          t.playCount >= 3;
      // Novelty: never played, but the signals say it fits.
      final fresh = t.playCount == 0 && (content > 0.5 || meta > 0);

      final score = co * 1.0 +
          content * 0.8 +
          meta * 0.5 +
          _hourBoost(t) * 0.35 + // this hour's regulars bubble up
          (dormant ? 0.25 : 0.0) +
          (fresh ? 0.15 : 0.0) -
          _skipPenalty(t.id);
      if (score > 0.05) scored.add((t, score));
    }
    scored.sort((a, b) => b.$2.compareTo(a.$2));

    // Artist-diversity cap so one binge artist can't own the shelf.
    final perArtist = <String, int>{};
    final out = <Track>[];
    for (final (t, _) in scored) {
      final n = perArtist[t.artist] ?? 0;
      if (n >= 3) continue;
      perArtist[t.artist] = n + 1;
      out.add(t);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// One radio step: given the track just queued, pick what flows next.
  /// Blend of the Markov walk (co-play out of [current]), sounds-like
  /// similarity, and staying near the seed's neighbourhood; slight
  /// randomness (top-k sample) so two stations from one seed differ.
  Track? _stationStep(
      Track seed, Track current, Set<int> used, List<Track> pool) {
    final currentRow = data.coPlay[current.id] ?? const <int, int>{};
    final currentMax = currentRow.isEmpty
        ? 1.0
        : currentRow.values.reduce(math.max).toDouble();
    final seedVec = data.features[seed.id];
    final currentVec = data.features[current.id];

    final scored = <(Track, double)>[];
    for (final t in pool) {
      if (used.contains(t.id)) continue;
      final co = (currentRow[t.id] ?? 0) / currentMax;
      var content = 0.0;
      final vec = data.features[t.id];
      if (vec != null) {
        if (currentVec != null) {
          content = featureSimilarity(vec, currentVec) * 0.7;
        }
        if (seedVec != null) {
          content =
              math.max(content, featureSimilarity(vec, seedVec) * 0.5);
        }
      }
      var meta = 0.0;
      if (t.artist == current.artist || t.artist == seed.artist) {
        meta += 0.3;
      }
      if (t.liked) meta += 0.1;
      final score = co * 1.0 +
          content +
          meta +
          _hourBoost(t) * 0.2 -
          _skipPenalty(t.id);
      if (score > 0.02) scored.add((t, score));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) => b.$2.compareTo(a.$2));
    // Sample among the top few, weighted by score.
    final top = scored.take(5).toList();
    var total = 0.0;
    for (final e in top) {
      total += e.$2;
    }
    var roll = _rng.nextDouble() * total;
    for (final e in top) {
      roll -= e.$2;
      if (roll <= 0) return e.$1;
    }
    return top.last.$1;
  }

  /// Song radio: [seed] first, then a Markov/similarity walk through
  /// the library. Falls back to a same-artist pool, then a random
  /// sample, so a fresh install still gets *a* station.
  List<Track> station(Track seed, {int length = 25}) {
    final pool = [
      for (final t in data.tracks)
        if (t.id != seed.id) t,
    ];
    final queue = <Track>[seed];
    final used = <int>{seed.id};
    var current = seed;

    while (queue.length < length) {
      final next = _stationStep(seed, current, used, pool);
      if (next == null) break;
      queue.add(next);
      used.add(next.id);
      current = next;
    }

    if (queue.length < length) {
      // Signals ran dry — pad with the seed's artist, then random picks.
      final sameArtist = [
        for (final t in pool)
          if (!used.contains(t.id) && t.artist == seed.artist) t,
      ]..shuffle(_rng);
      for (final t in sameArtist) {
        if (queue.length >= length) break;
        queue.add(t);
        used.add(t.id);
      }
      final rest = [
        for (final t in pool)
          if (!used.contains(t.id)) t,
      ]..shuffle(_rng);
      for (final t in rest) {
        if (queue.length >= length) break;
        queue.add(t);
        used.add(t.id);
      }
    }
    return queue;
  }

  /// Smart-shuffle weight: favorites surface more often, skipped tracks
  /// less, nothing is ever excluded (floor 0.15).
  double shuffleWeight(Track t) {
    final w = 1.0 +
        math.log(1 + t.playCount) * 0.6 +
        (t.liked ? 1.5 : 0.0) -
        _skipPenalty(t.id);
    return math.max(w, 0.15);
  }
}
