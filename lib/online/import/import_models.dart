import '../../library/models/track.dart';
import '../models/online_search_result.dart';

/// A raw playlist entry as read from the source (title + artist +
/// duration). YouTube entries already carry a playable videoId; Spotify
/// entries are metadata-only and must be matched to a playable source.
class ImportedTrack {
  const ImportedTrack({
    required this.title,
    required this.artist,
    this.durationMs,
    this.youtubeId,
  });

  final String title;
  final String artist;
  final int? durationMs;

  /// Set for YouTube-sourced entries — no matching needed, this *is* the
  /// playable id.
  final String? youtubeId;

  Duration? get duration =>
      durationMs == null ? null : Duration(milliseconds: durationMs!);
}

/// The outcome of importing one [ImportedTrack]: either matched to a
/// playable [OnlineSearchResult] (with a confidence 0–1) or unmatched.
class ImportMatch {
  const ImportMatch({
    required this.source,
    this.result,
    this.confidence = 0,
    this.candidates = const [],
  });

  /// The original playlist entry.
  final ImportedTrack source;

  /// The chosen playable result, or null if nothing matched confidently.
  final OnlineSearchResult? result;
  final double confidence;

  /// Top alternatives (for the review sheet's manual pick).
  final List<OnlineSearchResult> candidates;

  bool get matched => result != null;

  ImportMatch withResult(OnlineSearchResult r) =>
      ImportMatch(source: source, result: r, confidence: 1, candidates: candidates);
}

/// The fetched playlist plus its per-track matches.
class ImportResult {
  const ImportResult({
    required this.playlistName,
    required this.matches,
    required this.fromSource,
  });

  final String playlistName;
  final List<ImportMatch> matches;

  /// 'YouTube' / 'Spotify' — for the review header.
  final String fromSource;

  Iterable<ImportMatch> get confident => matches.where((m) => m.matched);
  Iterable<ImportMatch> get misses => matches.where((m) => !m.matched);
}

/// Live progress for the import sheet.
class ImportProgress {
  const ImportProgress({
    required this.phase,
    this.fetched = 0,
    this.total = 0,
    this.matched = 0,
  });

  final ImportPhase phase;
  final int fetched;
  final int total;
  final int matched;
}

enum ImportPhase { idle, fetching, matching, done, failed }

/// Detected playlist source from a pasted URL.
enum ImportSource { youtube, spotify, unknown }

ImportSource detectImportSource(String url) {
  final u = url.toLowerCase();
  if (u.contains('spotify.com') || u.startsWith('spotify:')) {
    return ImportSource.spotify;
  }
  if (u.contains('youtube.com') ||
      u.contains('youtu.be') ||
      u.contains('music.youtube.com')) {
    return ImportSource.youtube;
  }
  return ImportSource.unknown;
}

/// Normalizes a title/artist for matching: strips feature credits,
/// remaster/version tags and bracketed junk, lowercases, collapses
/// whitespace. Pure — unit-testable.
String normalizeForMatch(String s) {
  var out = s.toLowerCase();
  // Drop (feat. …), [feat …], ft. …
  out = out.replaceAll(
      RegExp(r'[\(\[]\s*(feat|ft|featuring)\.?\s[^\)\]]*[\)\]]'), ' ');
  out = out.replaceAll(RegExp(r'\b(feat|ft|featuring)\.?\s.*$'), ' ');
  // Drop " - Remastered 2011", "(2019 Remaster)", "- Radio Edit", etc.
  out = out.replaceAll(
      RegExp(r'[-\(\[]\s*[^\)\]]*\b(remaster|remastered|radio edit|'
          r'single version|album version|mono|stereo|deluxe|'
          r'bonus track|explicit|clean)\b[^\)\]]*[\)\]]?'),
      ' ');
  // Any remaining bracketed content.
  out = out.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ');
  // Non-alphanumeric → space, collapse.
  out = out.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  return out;
}

/// Token-set Jaccard similarity 0–1 between two normalized strings.
double tokenSimilarity(String a, String b) {
  final sa = normalizeForMatch(a).split(' ').where((t) => t.isNotEmpty).toSet();
  final sb = normalizeForMatch(b).split(' ').where((t) => t.isNotEmpty).toSet();
  if (sa.isEmpty || sb.isEmpty) return 0;
  final inter = sa.intersection(sb).length;
  final union = sa.union(sb).length;
  return inter / union;
}

/// Confidence 0–1 that [candidate] is the same song as [want].
/// Title 55% + artist 30% + duration proximity 15%.
double matchScore(ImportedTrack want, OnlineSearchResult candidate) {
  final title = tokenSimilarity(want.title, candidate.title);
  final artist = want.artist.isEmpty
      ? 0.5 // unknown artist: neutral, don't punish
      : tokenSimilarity(want.artist, candidate.artist);
  var dur = 0.5;
  final wantMs = want.durationMs;
  final candMs = candidate.duration.inMilliseconds;
  // Only score duration when BOTH are known — YT Music song entries often
  // omit it, and treating unknown as a mismatch would rank a live cut
  // (which lists a duration) above the real studio track.
  if (wantMs != null && wantMs > 0 && candMs > 0) {
    final deltaS = ((wantMs - candMs).abs()) / 1000;
    dur = deltaS <= 3
        ? 1.0
        : deltaS <= 8
            ? 0.7
            : deltaS <= 15
                ? 0.4
                : 0.0;
  }
  return title * 0.55 + artist * 0.30 + dur * 0.15;
}

/// A YouTube import entry maps straight to a playable result.
OnlineSearchResult youtubeResultOf(ImportedTrack t) => OnlineSearchResult(
      source: TrackSource.youtube,
      sourceId: t.youtubeId!,
      title: t.title,
      artist: t.artist,
      duration: t.duration ?? Duration.zero,
    );
