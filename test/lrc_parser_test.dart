import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/lyrics/lrc_parser.dart';

void main() {
  group('LrcParser.parseSynced', () {
    test('parses timestamped lines in order', () {
      final l = LrcParser.parseSynced('''
[ti: Some Song]
[00:16.80] The beagle watches, ears perked
[00:12.34] Cherry petals fall softly

[01:02.5] A minute in
''');
      expect(l.isSynced, isTrue);
      expect(l.lines.map((e) => e.text).toList(), [
        'Cherry petals fall softly',
        'The beagle watches, ears perked',
        'A minute in',
      ]);
      expect(l.lines[0].timestamp,
          const Duration(seconds: 12, milliseconds: 340));
      expect(l.lines[2].timestamp,
          const Duration(minutes: 1, seconds: 2, milliseconds: 500));
    });

    test('handles multiple timestamps on one line', () {
      final l = LrcParser.parseSynced('[00:10.00][00:50.00] Chorus line');
      expect(l.lines.length, 2);
      expect(l.lines[0].timestamp, const Duration(seconds: 10));
      expect(l.lines[1].timestamp, const Duration(seconds: 50));
      expect(l.lines[0].text, 'Chorus line');
    });

    test('skips metadata and empty-text lines', () {
      final l = LrcParser.parseSynced('[ar:Artist]\n[00:05.00]\n[00:06.00] hi');
      expect(l.lines.length, 1);
      expect(l.lines.single.text, 'hi');
    });
  });

  group('LrcParser.activeLine', () {
    final lines = LrcParser.parseSynced('''
[00:10.00] one
[00:20.00] two
[00:30.00] three
''').lines;

    test('before first line → -1', () {
      expect(LrcParser.activeLine(lines, const Duration(seconds: 5)), -1);
    });

    test('exactly on a timestamp → that line', () {
      expect(LrcParser.activeLine(lines, const Duration(seconds: 20)), 1);
    });

    test('between lines → previous line', () {
      expect(LrcParser.activeLine(lines, const Duration(seconds: 29)), 1);
    });

    test('after last line → last', () {
      expect(LrcParser.activeLine(lines, const Duration(minutes: 5)), 2);
    });
  });

  test('parsePlain marks unsynced and strips blanks', () {
    final l = LrcParser.parsePlain('line one\n\n  line two  \n');
    expect(l.isSynced, isFalse);
    expect(l.lines.map((e) => e.text).toList(), ['line one', 'line two']);
  });
}
