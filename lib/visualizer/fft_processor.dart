import 'dart:math' as math;
import 'dart:typed_data';

/// Converts Android Visualizer FFT bytes into 12 smoothed 0–1 bands.
///
/// Android's format: byte 0 = DC real, byte 1 = Nyquist real, then
/// (real, imag) pairs for bins 1..N/2-1. Bands are log-spaced to
/// roughly match musical octaves.
class FftProcessor {
  static const bandCount = 12;

  final _bands = List<double>.filled(bandCount, 0);

  List<double> process(Uint8List fft) {
    final binCount = fft.length ~/ 2 - 1;
    if (binCount <= 0) return _bands;

    // Log-spaced band edges over the useful bin range.
    for (var band = 0; band < bandCount; band++) {
      final lo = _edge(band, binCount);
      final hi = math.max(lo + 1, _edge(band + 1, binCount));
      var sum = 0.0;
      for (var bin = lo; bin < hi; bin++) {
        final re = fft[2 + bin * 2].toSigned(8).toDouble();
        final im = fft[3 + bin * 2].toSigned(8).toDouble();
        sum += math.sqrt(re * re + im * im);
      }
      final avg = sum / (hi - lo);
      // 0..~181 → 0..1 with a perceptual curve; boost highs slightly.
      var v = math.pow(avg / 128.0, 0.6).toDouble();
      v *= 1.0 + band * 0.06;
      v = v.clamp(0.0, 1.0);

      // Fast attack, slow decay.
      _bands[band] = v > _bands[band]
          ? _bands[band] * 0.4 + v * 0.6
          : _bands[band] * 0.82 + v * 0.18;
    }
    return List.unmodifiable(_bands);
  }

  int _edge(int band, int binCount) {
    // Spread bands 0..12 over bins 1..binCount*0.75 logarithmically
    // (top quarter of bins is mostly empty for music).
    final maxBin = (binCount * 0.75).floor();
    final t = band / bandCount;
    return (math.pow(maxBin.toDouble(), t)).floor().clamp(1, maxBin);
  }
}
