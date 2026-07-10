import 'dart:math' as math;

/// Shapes raw frame values from FftExtractorChannel into the 0–1
/// values the renderers draw: perceptual curve, user sensitivity and
/// fast-attack/slow-decay smoothing (tuned for ~60 ticks/second).
///
/// Frames are 12 spectral bands, optionally followed by extra
/// broadband values (the L/R channel RMS pair for the VU meters) that
/// get the same gain/curve/ballistics but no spectral tilt.
class BandShaper {
  static const bandCount = 12;

  var _values = <double>[];

  /// Spectral-tilt compensation, measured on device: music amplitude
  /// falls ~×1.4 per log band, so uncorrected the top band reads
  /// ~1/60 of bass and never visibly moves. This flattens each band's
  /// typical content into the same on-screen range (bass unchanged,
  /// band 11 ≈ ×47) so hi-hats and cymbals actually dance.
  static final _tilt = List<double>.generate(
      bandCount, (b) => math.pow(1.42, b).toDouble());

  /// [raw] is 12 linear band amplitudes (0..~1, typically well under
  /// 0.5) plus any broadband extras; [sensitivity] is the user gain
  /// (1.0 = default). [reactivity] scales the attack/decay ballistics:
  /// 1.0 is the stock feel, 3.0 snaps to every transient, 0.5 glides.
  List<double> shape(List<double> raw, double sensitivity,
      [double reactivity = 1.0]) {
    if (_values.length != raw.length) {
      _values = List<double>.filled(raw.length, 0);
    }
    final attack = (0.55 * reactivity).clamp(0.2, 1.0).toDouble();
    final decay = (0.10 * reactivity).clamp(0.03, 0.6).toDouble();
    for (var i = 0; i < raw.length; i++) {
      final tilt = i < bandCount ? _tilt[i] : 1.0;
      // Broadband RMS runs hotter than any single band — the full 2.5×
      // pinned the VU needles at 1× sensitivity (user: 0.75× felt
      // right, so that's baked in).
      final gain = i < bandCount ? 2.5 : 1.875;
      var v = raw[i] * tilt * gain * sensitivity;
      v = math.pow(v.clamp(0.0, 1.0), 0.6).toDouble();

      _values[i] = v > _values[i]
          ? _values[i] * (1 - attack) + v * attack
          : _values[i] * (1 - decay) + v * decay;
    }
    return List.unmodifiable(_values);
  }
}
