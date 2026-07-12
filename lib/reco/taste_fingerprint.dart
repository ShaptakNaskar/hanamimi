import '../utils/track_identity.dart';

/// Taste-fingerprint MinHash (3.0 #5 — Taste Compatibility).
///
/// The leaderboard backend only ever sees aggregate seconds — never an
/// artist name. Compatibility therefore ships as a *fingerprint*: the
/// top artists (by listened seconds, off the local history log) are
/// folded into a fixed-size MinHash signature. The server can estimate
/// Jaccard overlap between two users' artist sets from matching
/// signature positions without ever learning a single artist. 128
/// slots × 32-bit mins, irreversible, and only uploaded behind its own
/// consent line on top of the leaderboard opt-in.
const tasteSignatureSize = 128;

/// Below this many distinct artists the estimate is meaningless — the
/// UI shows "still getting to know you" instead.
const tasteMinArtists = 10;

/// Only the heavy rotation defines taste; the long tail is noise.
const tasteTopArtists = 50;

/// FNV-1a, 32-bit — tiny, fast, and identical across platforms (the
/// signature must be comparable between an Android phone and a Linux
/// desktop).
int _fnv1a(String s) {
  var hash = 0x811c9dc5;
  for (final unit in s.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// Builds the signature from `{artist: secondsListened}` (raw names —
/// normalization happens here so history and fingerprint always agree).
/// Returns null while there's not enough listening to fingerprint.
List<int>? buildTasteSignature(Map<String, int> artistSeconds) {
  // Merge on the normalized name: "Yoasobi feat. X" and "YOASOBI"
  // are one artist.
  final merged = <String, int>{};
  artistSeconds.forEach((artist, seconds) {
    final name = normalizeArtist(artist);
    if (name.isEmpty || name == 'unknown artist') return;
    merged[name] = (merged[name] ?? 0) + seconds;
  });
  if (merged.length < tasteMinArtists) return null;

  final top = merged.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final artists = [for (final e in top.take(tasteTopArtists)) e.key];

  // MinHash: slot i keeps the minimum of hash_i over the artist set.
  // Seeding by slot index makes 128 independent-enough hash functions
  // out of one FNV.
  final sig = List<int>.filled(tasteSignatureSize, 0xFFFFFFFF);
  for (final artist in artists) {
    for (var i = 0; i < tasteSignatureSize; i++) {
      final h = _fnv1a('$i|$artist');
      if (h < sig[i]) sig[i] = h;
    }
  }
  return sig;
}
