import 'dart:math' as math;
import 'dart:typed_data';

import '../library/models/track.dart';
import '../platform/web/web_fft.dart';

/// Where and how long to crossfade out of a track (Slow Dance, 3.0 #4).
class SlowDancePlan {
  const SlowDancePlan({required this.startAt, required this.fade});

  /// Position in the outgoing track where the incoming one starts.
  final Duration startAt;
  final Duration fade;
}

/// Sighted crossfade planning: reads the track's analyzed RMS frames
/// (the web edition keeps them in WebFft's in-memory cache instead of a
/// disk file — same 60 fps, stride-14 layout) and finds where the
/// outgoing track's energy actually dies, so the next song starts as
/// this one fades, loudness-matched instead of a blind timer.
///
/// Returns null when the run isn't analyzed yet (first seconds of a
/// track's first play) — the caller falls back to the classic timer.
Future<SlowDancePlan?> planSlowDance(Track track) async {
  try {
    final run = WebFft.cached(_keyFor(track));
    if (run == null) return null;
    const stride = 14;
    final frameCount = run.length ~/ stride;

    const fps = 60;
    if (frameCount < 30 * fps) return null; // <30 s — don't bother

    // Per-frame loudness from the L/R RMS pair, lightly smoothed
    // (~250 ms box) so a single quiet beat can't read as "the song died".
    final loud = Float64List(frameCount);
    for (var i = 0; i < frameCount; i++) {
      loud[i] = (run[i * stride + 12] + run[i * stride + 13]) / 2;
    }
    const smooth = 15; // frames ≈ 250 ms
    final smoothed = Float64List(frameCount);
    var acc = 0.0;
    for (var i = 0; i < frameCount; i++) {
      acc += loud[i];
      if (i >= smooth) acc -= loud[i - smooth];
      smoothed[i] = acc / math.min(i + 1, smooth);
    }

    // Reference level: 75th percentile of the whole track — robust to
    // both quiet intros and brickwalled masters.
    final sorted = smoothed.toList()..sort();
    final reference = sorted[(sorted.length * 3) ~/ 4];
    if (reference <= 0.001) return null; // silence / broken decode
    final threshold = reference * 0.25;

    // Walk back from the end: the fade starts after the last frame
    // that was still properly loud.
    var lastLoud = frameCount - 1;
    while (lastLoud > 0 && smoothed[lastLoud] < threshold) {
      lastLoud--;
    }

    final end = Duration(milliseconds: frameCount * 1000 ~/ fps);
    var fade = end - Duration(milliseconds: lastLoud * 1000 ~/ fps);
    // Cold endings still get a short overlap; long ambient fades are
    // capped so the next track doesn't barge in half a minute early.
    if (fade < const Duration(seconds: 2)) {
      fade = const Duration(seconds: 2);
    } else if (fade > const Duration(seconds: 15)) {
      fade = const Duration(seconds: 15);
    }
    return SlowDancePlan(startAt: end - fade, fade: fade);
  } catch (_) {
    return null; // any hiccup = classic timer, never a crash
  }
}

/// Mirrors the cache-key derivation in visualizerBandsProvider — if
/// that moves, move this with it.
String _keyFor(Track track) =>
    'v3_${track.mediaId}_${track.filePath.hashCode}_${track.duration.inMilliseconds}';
