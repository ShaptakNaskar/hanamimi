/// Shared song-identity normalization (IDEAS-APPROVED.md #7).
///
/// History rows key songs by a pragmatic fingerprint — normalized title
/// + artist + a coarse duration bucket — computed once at write time. No
/// audio hashing: heavy, and it breaks on re-encodes/retags anyway.
/// Keeping the rules in one place is the point: history restore and
/// tap-to-play both re-derive this key over the current library, so the
/// rules must never fork.
library;

/// Strips featuring credits, bracketed noise and case so "Song (feat. X)"
/// and "song" collapse to the same identity.
String normalizeTitle(String title) => _normalize(title);

/// Same rules as titles, plus "A feat. B" collapses to "a" — the lead
/// artist is the identity, guests are noise.
String normalizeArtist(String artist) => _normalize(artist);

String _normalize(String s) {
  var out = s.toLowerCase().trim();
  // "feat."/"ft."/"featuring" and everything after it, bracketed or not.
  out = out.replaceFirst(
      RegExp(r'[\(\[\{]?\s*(feat\.?|ft\.?|featuring)\s+.*$'), '');
  // Leftover empty brackets / dangling separators from the strip above.
  out = out.replaceAll(RegExp(r'[\(\[\{]\s*[\)\]\}]'), '');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  out = out.replaceFirst(RegExp(r'[\s,;&\-–]+$'), '').trim();
  return out;
}

/// 10-second buckets: wide enough that re-encodes and metadata rounding
/// land in the same bucket, narrow enough that a radio edit and the
/// album cut usually don't.
int durationBucket(Duration duration) => duration.inSeconds ~/ 10;

/// The identity key stored on history rows. Computed once at write time;
/// playback re-resolution recomputes it over the current library to
/// find candidates.
String identityKey({
  required String title,
  required String artist,
  required Duration duration,
}) =>
    '${normalizeTitle(title)}|${normalizeArtist(artist)}|${durationBucket(duration)}';
