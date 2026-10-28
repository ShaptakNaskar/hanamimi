import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/platform/desktop/desktop_library.dart';

void main() {
  test('lastSep splits mixed Windows paths at the real parent', () {
    // Real stored shape: default root joined with '/', walk adds '\'.
    const p = r'C:\Users\Sappy/Music\Adhd Core\01 - Prism.flac';
    expect(p.substring(0, DesktopLibrary.lastSep(p)),
        r'C:\Users\Sappy/Music\Adhd Core');
    expect(DesktopLibrary.lastSep('/home/a/b.mp3'), 7);
  });
}
