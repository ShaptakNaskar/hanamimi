import 'dart:math' as math;

/// Shapes raw band amplitudes from FftExtractorChannel into the 0–1
/// values the renderers draw: perceptual curve, user sensitivity and
/// fast-attack/slow-decay smoothing (tuned for ~60 ticks/second).
class BandShaper {
  static const bandCount = 12;

  final _bands = List<double>.filled(bandCount, 0);

  /// [raw] is 12 linear amplitudes (0..~1, typically well under 0.5);
  /// [sensitivity] is the user multiplier (1.0 = default).
  List<double> shape(List<double> raw, double sensitivity) {
    for (var band = 0; band < bandCount; band++) {
      var v = raw[band] * 2.5 * sensitivity;
      v = math.pow(v.clamp(0.0, 1.0), 0.6).toDouble();
      v *= 1.0 + band * 0.05; // slight treble lift, music is bass-heavy
      v = v.clamp(0.0, 1.0);

      _bands[band] = v > _bands[band]
          ? _bands[band] * 0.45 + v * 0.55
          : _bands[band] * 0.90 + v * 0.10;
    }
    return List.unmodifiable(_bands);
  }
}
