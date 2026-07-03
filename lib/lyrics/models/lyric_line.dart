/// One word with its own start time (enhanced LRC `<mm:ss.xx>` tags).
class LyricWord {
  const LyricWord({required this.start, required this.text});

  final Duration start;
  final String text;
}

class LyricLine {
  const LyricLine({
    required this.timestamp,
    required this.text,
    this.end,
    this.words,
  });

  final Duration timestamp;
  final String text;

  /// When the vocal for this line stops (richsync `te`). Null for LRC
  /// sources, which only mark line starts — the UI estimates then.
  /// Without this, the last word would keep "filling" through any
  /// instrumental break that follows the line.
  final Duration? end;

  /// Word-level timings when the source provides them; null for plain
  /// line-level lyrics (the UI synthesizes an approximation then).
  final List<LyricWord>? words;

  bool get hasWordTimings => words != null && words!.isNotEmpty;
}

/// Where the lyrics came from — used for the quality priority order.
enum LyricsSource { embedded, lrclib, musixmatch }

class Lyrics {
  const Lyrics({
    required this.lines,
    required this.isSynced,
    this.source = LyricsSource.lrclib,
  });

  /// For synced lyrics, timestamps are meaningful; for plain lyrics
  /// every timestamp is zero and [isSynced] is false.
  final List<LyricLine> lines;
  final bool isSynced;
  final LyricsSource source;

  bool get isEmpty => lines.isEmpty;

  bool get hasWordTimings => lines.any((l) => l.hasWordTimings);

  /// 2 = word-synced, 1 = line-synced, 0 = plain. Higher wins when
  /// choosing between embedded and fetched lyrics.
  int get quality => hasWordTimings ? 2 : (isSynced ? 1 : 0);
}
