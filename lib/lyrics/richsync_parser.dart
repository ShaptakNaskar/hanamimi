import 'dart:convert';

import 'models/lyric_line.dart';

/// Parses Musixmatch richsync JSON:
///   [{"ts": 2.88, "te": 8.76, "l": [{"c": "You", "o": 0}, ...], "x": "..."}]
/// Unlike LRC this carries a line END time, so highlighting can stop
/// during instrumental breaks.
abstract final class RichsyncParser {
  /// Cached lyric text can be richsync JSON or LRC — both start with
  /// '[', but only JSON follows it with '{'.
  static bool looksLikeRichsync(String text) =>
      text.trimLeft().startsWith('[{');

  static Lyrics parse(String jsonBody) {
    final lines = <LyricLine>[];
    try {
      for (final item in jsonDecode(jsonBody) as List) {
        final map = item as Map<String, dynamic>;
        final ts = (map['ts'] as num?)?.toDouble();
        final te = (map['te'] as num?)?.toDouble();
        final tokens = map['l'] as List?;
        if (ts == null || tokens == null) continue;

        final words = <LyricWord>[];
        for (final t in tokens) {
          final token = t as Map<String, dynamic>;
          final text = (token['c'] as String? ?? '').trim();
          if (text.isEmpty) continue;
          final offset = (token['o'] as num?)?.toDouble() ?? 0;
          words.add(LyricWord(start: _duration(ts + offset), text: text));
        }
        if (words.isEmpty) continue;

        lines.add(LyricLine(
          timestamp: _duration(ts),
          end: te == null ? null : _duration(te),
          text: words.map((w) => w.text).join(' '),
          words: words,
        ));
      }
    } catch (_) {
      return const Lyrics(
          lines: [], isSynced: true, source: LyricsSource.musixmatch);
    }
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return Lyrics(
        lines: lines, isSynced: true, source: LyricsSource.musixmatch);
  }

  static Duration _duration(double seconds) =>
      Duration(milliseconds: (seconds * 1000).round());
}
