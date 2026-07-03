import 'models/lyric_line.dart';

/// Parses `.lrc` timestamped lyrics:
///   [00:12.34] Cherry petals fall softly
/// including the enhanced word-level variant:
///   [00:12.34] <00:12.34> Cherry <00:13.10> petals <00:13.80> fall
/// A line may carry several line timestamps. Metadata tags ([ar:],
/// [ti:], …) are ignored.
abstract final class LrcParser {
  static final _timeTag = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  static final _wordTag = RegExp(r'<(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?>');

  static Duration _tagToDuration(Match tag) {
    final minutes = int.parse(tag.group(1)!);
    final seconds = int.parse(tag.group(2)!);
    final fracRaw = tag.group(3) ?? '0';
    // ".5" = 500ms, ".50" = 500ms, ".500" = 500ms
    final millis =
        (int.parse(fracRaw) * (1000 / _pow10(fracRaw.length))).round();
    return Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
  }

  static Lyrics parseSynced(String lrc,
      {LyricsSource source = LyricsSource.lrclib}) {
    final lines = <LyricLine>[];
    for (final raw in lrc.split('\n')) {
      final tags = _timeTag.allMatches(raw).toList();
      if (tags.isEmpty) continue;
      final body = raw.substring(tags.last.end);

      // Enhanced LRC: word tags inside the body.
      final wordTags = _wordTag.allMatches(body).toList();
      List<LyricWord>? words;
      String text;
      if (wordTags.isNotEmpty) {
        words = [];
        for (var w = 0; w < wordTags.length; w++) {
          final end = w + 1 < wordTags.length
              ? wordTags[w + 1].start
              : body.length;
          final wordText = body.substring(wordTags[w].end, end).trim();
          if (wordText.isEmpty) continue;
          words.add(LyricWord(
              start: _tagToDuration(wordTags[w]), text: wordText));
        }
        text = words.map((w) => w.text).join(' ');
        if (words.isEmpty) words = null;
      } else {
        text = body.trim();
      }
      if (text.isEmpty) continue;

      for (final tag in tags) {
        lines.add(LyricLine(
          timestamp: _tagToDuration(tag),
          text: text,
          words: words,
        ));
      }
    }
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return Lyrics(lines: lines, isSynced: true, source: source);
  }

  static Lyrics parsePlain(String text,
      {LyricsSource source = LyricsSource.lrclib}) =>
      Lyrics(
        lines: [
          for (final l in text.split('\n'))
            if (l.trim().isNotEmpty)
              LyricLine(timestamp: Duration.zero, text: l.trim()),
        ],
        isSynced: false,
        source: source,
      );

  /// Auto-detect: synced when the text carries LRC line tags. Embedded
  /// USLT lyrics are very often LRC-formatted.
  static Lyrics parseAuto(String text,
      {LyricsSource source = LyricsSource.lrclib}) =>
      _timeTag.hasMatch(text)
          ? parseSynced(text, source: source)
          : parsePlain(text, source: source);

  static int _pow10(int n) => switch (n) { 1 => 10, 2 => 100, _ => 1000 };

  /// Index of the line active at [position] (last line whose timestamp
  /// has passed), or -1 before the first line. Binary search.
  static int activeLine(List<LyricLine> lines, Duration position) {
    var lo = -1, hi = lines.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (lines[mid].timestamp <= position) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }
}
