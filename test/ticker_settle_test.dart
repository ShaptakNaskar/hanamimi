import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hanamimi/library/models/track.dart';
import 'package:hanamimi/providers/window_activity_provider.dart';
import 'package:hanamimi/theme/themes.dart';
import 'package:hanamimi/ui/components/mascot/hanamimi_widget.dart';
import 'package:hanamimi/ui/components/now_playing/album_art_widget.dart';

/// Regression tests for the desktop constant-CPU bug: widgets whose
/// vsync tickers never stopped kept the engine producing a frame every
/// vsync forever — full render pipeline (raster, GL swap, compositor)
/// hot even paused and idle. An active ticker registers a transient
/// frame callback, so `binding.transientCallbackCount == 0` IS "no
/// frames are being demanded".
void main() {
  final track = Track(
    id: 1,
    mediaId: 1,
    title: 'Test',
    artist: 'Test',
    album: 'Test',
    albumId: 1,
    filePath: '/tmp/test.mp3',
    duration: const Duration(minutes: 3),
  );

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  setUp(() {
    windowFocused.value = true;
    windowVisible.value = true;
  });

  testWidgets('album art wobble ticks only while playing',
      (tester) async {
    await tester.pumpWidget(host(AlbumArtWidget(
      track: track,
      theme: cherryBlossom,
      isPlaying: false,
      size: 100,
    )));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0,
        reason: 'paused art must not keep a ticker alive');

    await tester.pumpWidget(host(AlbumArtWidget(
      track: track,
      theme: cherryBlossom,
      isPlaying: true,
      size: 100,
    )));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, greaterThan(0),
        reason: 'playing art wobbles');

    // Back to paused: the wobble eases out (~600 ms) and the ticker
    // must stop — this exact leak was the constant-CPU report.
    await tester.pumpWidget(host(AlbumArtWidget(
      track: track,
      theme: cherryBlossom,
      isPlaying: false,
      size: 100,
    )));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.binding.transientCallbackCount, 0,
        reason: 'wobble eased out — ticker must stop');
  });

  testWidgets('album art wobble stops when the window is hidden',
      (tester) async {
    await tester.pumpWidget(host(AlbumArtWidget(
      track: track,
      theme: cherryBlossom,
      isPlaying: true,
      size: 100,
    )));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, greaterThan(0));

    windowVisible.value = false;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, 0,
        reason: 'minimized window must not demand frames');

    // Restore: the listener restarts the wobble.
    windowVisible.value = true;
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.binding.transientCallbackCount, greaterThan(0),
        reason: 'restore resumes the wobble');
  });

  testWidgets('mascot settles to zero tickers when paused',
      (tester) async {
    await tester.pumpWidget(host(const HanamimiMascot(
      state: MascotState.paused,
    )));
    // Give the pose time to ease in and the eyes to finish any blink.
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.binding.transientCallbackCount, 0,
        reason: 'a paused mascot at rest must stop its ticker '
            '(a blink wake-up timer is fine; a running ticker is not)');
  });
}
