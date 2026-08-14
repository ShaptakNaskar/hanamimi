import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/utils/app_frame_ticker.dart';

void main() {
  testWidgets('fixed visual ticker runs at 60 Hz and stops cleanly', (
    tester,
  ) async {
    final first = <Duration>[];
    final second = <Duration>[];
    final a = AppFrameTicker(first.add, nativeVsyncOnMobile: false);
    final b = AppFrameTicker(second.add, nativeVsyncOnMobile: false);

    a.start();
    b.start();
    await tester.pump(desktopVisualFrameInterval);

    expect(first, hasLength(1));
    expect(second, hasLength(1));
    expect(
      (first.single - second.single).abs(),
      lessThan(const Duration(milliseconds: 1)),
    );

    a.stop();
    await tester.pump(desktopVisualFrameInterval);

    expect(first, hasLength(1));
    expect(second, hasLength(2));

    a.dispose();
    b.dispose();
  });
}
