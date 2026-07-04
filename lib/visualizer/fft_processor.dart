import 'dart:math' as math;

/// Shapes raw band amplitudes from FftExtractorChannel into the 0–1
/// values the renderers draw: perceptual curve, user sensitivity and
/// fast-attack/slow-decay smoothing (tuned for ~60 ticks/second).
class BandShaper {
  static const bandCount = 12;

  final _bands = List<double>.filled(bandCount, 0);

  /// Spectral-tilt compensation, measured on device: music amplitude
  /// falls ~×1.4 per log band, so uncorrected the top band reads
  /// ~1/60 of bass and never visibly moves. This flattens each band's
  /// typical content into the same on-screen range (bass unchanged,
  /// band 11 ≈ ×47) so hi-hats and cymbals actually dance.
  static final _tilt = List<double>.generate(
      bandCount, (b) => math.pow(1.42, b).toDouble());

  /// [raw] is 12 linear amplitudes (0..~1, typically well under 0.5);
  /// [sensitivity] is the user multiplier (1.0 = default).
  List<double> shape(List<double> raw, double sensitivity) {
    for (var band = 0; band < bandCount; band++) {
      var v = raw[band] * _tilt[band] * 2.5 * sensitivity;
      v = math.pow(v.clamp(0.0, 1.0), 0.6).toDouble();

      _bands[band] = v > _bands[band]
          ? _bands[band] * 0.45 + v * 0.55
          : _bands[band] * 0.90 + v * 0.10;
    }
    return List.unmodifiable(_bands);
  }
}
