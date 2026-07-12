import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../library/models/track.dart';

/// Where and how long to crossfade out of a track (Slow Dance, 3.0 #4).
class SlowDancePlan {
  const SlowDancePlan({required this.startAt, required this.fade});

  /// Position in the outgoing track where the incoming one starts.
  final Duration startAt;
  final Duration fade;
}

/// Sighted crossfade planning: reads the track's cached RMS frames (the
/// same v3 disk cache the visualizers fill, [int32 frameCount][float32 ×
/// stride], big-endian, 60 fps) and finds where the outgoing track's
/// energy actually dies — so the next song starts as this one fades,
/// loudness-matched instead of a blind fixed-duration timer.
///
/// Returns null when no cache exists yet (first-ever play of a track,
/// or a stream the extractor can't decode) — the caller falls back to
/// the classic timer.
Future<SlowDancePlan?> planSlowDance(Track track) async {
  try {
    final file = await _cacheFileFor(track);
    if (file == null || !await file.exists()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length < 8) return null;
    final data = ByteData.sublistView(bytes);
    final frameCount = data.getInt32(0);
    if (frameCount <= 0) return null;
    // Stride from the actual payload — v3 files are 14 floats/frame,
    // but tolerate legacy 12 (no RMS: fall back to the band mean).
    final stride = (bytes.length - 4) ~/ (frameCount * 4);
    if (stride != 14 && stride != 12) return null;

    const fps = 60;
    if (frameCount < 30 * fps) return null; // <30 s — don't bother

    // Per-frame loudness, lightly smoothed (~250 ms box) so a single
    // quiet beat can't read as "the song died".
    final loud = Float64List(frameCount);
    for (var i = 0; i < frameCount; i++) {
      final base = 4 + i * stride * 4;
      if (stride == 14) {
        loud[i] = (data.getFloat32(base + 12 * 4) +
                data.getFloat32(base + 13 * 4)) /
            2;
      } else {
        var sum = 0.0;
        for (var b = 0; b < 12; b++) {
          sum += data.getFloat32(base + b * 4);
        }
        loud[i] = sum / 12;
      }
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
    var fade =
        end - Duration(milliseconds: lastLoud * 1000 ~/ fps);
    // Cold endings still get a short overlap; long ambient fades are
    // capped so the next track doesn't barge in half a minute early.
    if (fade < const Duration(seconds: 2)) {
      fade = const Duration(seconds: 2);
    } else if (fade > const Duration(seconds: 15)) {
      fade = const Duration(seconds: 15);
    }
    return SlowDancePlan(startAt: end - fade, fade: fade);
  } catch (_) {
    return null; // any parse hiccup = classic timer, never a crash
  }
}

/// Mirrors the cache-key/dir derivation in visualizerBandsProvider and
/// the two extractors — if those move, move this with them.
Future<File?> _cacheFileFor(Track track) async {
  final path = track.filePath;
  final key = path == null
      ? 'stream3_${track.source.name}_${track.sourceId}'
      : 'v3_${track.mediaId ?? track.sourceId}_${path.hashCode}_${track.duration.inMilliseconds}';
  final dir = Platform.isAndroid
      ? (await getTemporaryDirectory()).path
      : (await getApplicationSupportDirectory()).path;
  return File('$dir/fft/$key.bin');
}
