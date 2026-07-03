class LyricLine {
  const LyricLine({required this.timestamp, required this.text});

  final Duration timestamp;
  final String text;
}

class Lyrics {
  const Lyrics({required this.lines, required this.isSynced});

  /// For synced lyrics, timestamps are meaningful; for plain lyrics
  /// every timestamp is zero and [isSynced] is false.
  final List<LyricLine> lines;
  final bool isSynced;

  bool get isEmpty => lines.isEmpty;
}
