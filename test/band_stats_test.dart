import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/visualizer/fft_processor.dart';

/// Feeds [stats] `frames` copies of one 14-slot frame, as one chunk.
void feed(BandStats stats, List<double> frame, {int frames = 200}) {
  stats.add([for (var i = 0; i < frames; i++) ...frame], 14);
}

List<double> frameWith({double band0 = 0, double l = 0, double r = 0}) {
  final f = List<double>.filled(14, 0.0);
  f[0] = band0;
  f[12] = l;
  f[13] = r;
  return f;
}

void main() {
  group('BandStats auto gain', () {
    test('silence stays exactly zero', () {
      final stats = BandStats();
      feed(stats, frameWith(band0: 0.3, l: 0.2, r: 0.2));
      final out = stats.norm(List.filled(14, 0.0));
      expect(out, everyElement(0.0));
    });

    test('a quiet track peaks the meter at its own ceiling', () {
      final stats = BandStats();
      // Lofi bass: peaks at 0.1 — stock gain (×2.5) would show 0.25.
      feed(stats, frameWith(band0: 0.1));
      final out = stats.norm(frameWith(band0: 0.1));
      expect(out[0], closeTo(1.0, 0.05));
    });

    test('boost is capped for near-empty bands', () {
      final stats = BandStats();
      // Band 0 "peaking" at 0.02: uncapped normalization would be ×50,
      // but the cap holds it to 8× the stock 2.5 → 0.02 * 20 = 0.4.
      feed(stats, frameWith(band0: 0.02));
      final out = stats.norm(frameWith(band0: 0.02));
      expect(out[0], closeTo(0.4, 0.05));
    });

    test('below the signal floor falls back to stock gain', () {
      final stats = BandStats();
      // 0.005 is under the ~0.012 audibility floor — no stats, so the
      // divisor must reproduce the stock path (×2.5 for band 0).
      feed(stats, frameWith(band0: 0.005));
      final out = stats.norm(frameWith(band0: 0.005));
      expect(out[0], closeTo(0.005 * 2.5, 0.001));
    });

    test('L/R normalize by their shared peak, preserving balance', () {
      final stats = BandStats();
      feed(stats, frameWith(l: 0.4, r: 0.2));
      final out = stats.norm(frameWith(l: 0.4, r: 0.2));
      expect(out[12], closeTo(1.0, 0.05));
      expect(out[13], closeTo(0.5, 0.05));
    });

    test('too few frames means no stats — stock fallback', () {
      final stats = BandStats();
      feed(stats, frameWith(band0: 0.1), frames: 30); // < ~1.5 s active
      final out = stats.norm(frameWith(band0: 0.1));
      expect(out[0], closeTo(0.1 * 2.5, 0.001));
    });
  });

  test('BandShaper skips tilt and stock gain for normalized input', () {
    final shaper = BandShaper();
    // One shape() call: attack blends 55% of the way toward the target.
    // For a full-scale normalized value the target is 1.0 (pow keeps 1).
    final out = shaper.shape(List.filled(14, 1.0), 1.0, 1.0, true);
    expect(out, everyElement(closeTo(0.55, 0.001)));
  });
}
