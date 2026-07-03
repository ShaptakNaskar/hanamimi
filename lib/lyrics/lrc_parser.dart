import 'models/lyric_line.dart';

/// Parses `.lrc` timestamped lyrics:
///   [00:12.34] Cherry petals fall softly
/// A line may carry several timestamps. Metadata tags ([ar:], [ti:], …)
/// are ignored.
abstract final class LrcParser {
  static final _timeTag = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');

  static Lyrics parseSynced(String lrc) {
    final lines = <LyricLine>[];
    for (final raw in lrc.split('\n')) {
      final tags = _timeTag.allMatches(raw).toList();
      if (tags.isEmpty) continue;
      final text = raw.substring(tags.last.end).trim();
      if (text.isEmpty) continue;
      for (final tag in tags) {
        final minutes = int.parse(tag.group(1)!);
        final seconds = int.parse(tag.group(2)!);
        final fracRaw = tag.group(3) ?? '0';
        // ".5" = 500ms, ".50" = 500ms, ".500" = 500ms
        final millis =
            (int.parse(fracRaw) * (1000 / _pow10(fracRaw.length))).round();
        lines.add(LyricLine(
          timestamp: Duration(
              minutes: minutes, seconds: seconds, milliseconds: millis),
          text: text,
        ));
      }
    }
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return Lyrics(lines: lines, isSynced: true);
  }

  static Lyrics parsePlain(String text) => Lyrics(
        lines: [
          for (final l in text.split('\n'))
            if (l.trim().isNotEmpty)
              LyricLine(timestamp: Duration.zero, text: l.trim()),
        ],
        isSynced: false,
      );

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
