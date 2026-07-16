import 'dart:math' as math;
import 'dart:typed_data';

/// Shapes raw frame values from FftExtractorChannel into the 0–1
/// values the renderers draw: perceptual curve, user sensitivity and
/// fast-attack/slow-decay smoothing (tuned for ~60 ticks/second).
///
/// Frames are 12 spectral bands, optionally followed by extra
/// broadband values (the L/R channel RMS pair for the VU meters) that
/// get the same gain/curve/ballistics but no spectral tilt.
class BandShaper {
  static const bandCount = 12;

  /// Stock fixed gains. Auto gain ([BandStats]) replaces these with the
  /// track's own peaks, and folds them into its fallback divisors so
  /// both modes meet at the same scale when a track has no stats yet.
  static const _bandGain = 2.5;
  static const _rmsGain = 1.875;

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
  /// [normalized] marks values already mapped to display space by
  /// [BandStats] auto gain — tilt and stock gain are skipped, so only
  /// sensitivity (now a trim), the curve and the ballistics apply.
  List<double> shape(List<double> raw, double sensitivity,
      [double reactivity = 1.0, bool normalized = false]) {
    if (_values.length != raw.length) {
      _values = List<double>.filled(raw.length, 0);
    }
    final attack = (0.55 * reactivity).clamp(0.2, 1.0).toDouble();
    final decay = (0.10 * reactivity).clamp(0.03, 0.6).toDouble();
    for (var i = 0; i < raw.length; i++) {
      final tilt = (normalized || i >= bandCount) ? 1.0 : _tilt[i];
      // Broadband RMS runs hotter than any single band — the full 2.5×
      // pinned the VU needles at 1× sensitivity (user: 0.75× felt
      // right, so that's baked in).
      final gain =
          normalized ? 1.0 : (i < bandCount ? _bandGain : _rmsGain);
      var v = raw[i] * tilt * gain * sensitivity;
      v = math.pow(v.clamp(0.0, 1.0), 0.6).toDouble();

      _values[i] = v > _values[i]
          ? _values[i] * (1 - attack) + v * attack
          : _values[i] * (1 - decay) + v * decay;
    }
    return List.unmodifiable(_values);
  }
}

/// Per-track amplitude statistics for the auto-gain visualizer: the
/// track's own 95th-percentile level per slot maps to full scale, so a
/// quiet lofi master fills the meters exactly like a loud EDM one.
///
/// Built incrementally from the same frame chunks the meters buffer —
/// fixed histograms per slot, so there's never a sort or a re-scan of
/// the frame run, and stats are usable (and self-correcting) while
/// extraction is still streaming in. Pure scaling: silence stays 0.
class BandStats {
  static const _slots = BandShaper.bandCount + 2; // bands + L/R RMS
  static const _bins = 512;

  /// Values below ~0.012 don't count as signal — a long silent intro
  /// must not drag the percentile down and over-drive the loud parts.
  static const _floorBin = 6;

  /// Boost ceiling, relative to the stock fixed gain: a band with
  /// genuinely no content (rolled-off lofi treble) stays humble instead
  /// of amplifying the noise floor to full scale.
  static const _maxBoost = 8.0;

  final _hist =
      List.generate(_slots, (_) => Uint32List(_bins), growable: false);
  List<double>? _divisors;

  /// What the stock pipeline multiplies slot [i] by — auto gain's
  /// fallback (and its boost-cap reference) so a slot with no usable
  /// stats renders exactly like the fixed-gain path.
  static double _stockGain(int i) => i < BandShaper.bandCount
      ? BandShaper._tilt[i] * BandShaper._bandGain
      : BandShaper._rmsGain;

  /// Accumulates a flattened chunk of frames (stride 12 or 14). A
  /// legacy 12-float stride leaves the L/R histograms empty; those
  /// slots then fall back to stock gain via the null-p95 path.
  void add(List<double> chunk, int stride) {
    final width = math.min(stride, _slots);
    for (var f = 0; f + stride <= chunk.length; f += stride) {
      for (var i = 0; i < width; i++) {
        final bin = (chunk[f + i] * _bins).toInt().clamp(0, _bins - 1);
        _hist[i][bin]++;
      }
    }
    _divisors = null; // recomputed lazily on the next norm()
  }

  /// Maps raw linear amplitudes into display space: this track's p95
  /// level → 1.0 (true peaks above it pin briefly — that's the point).
  /// Output feeds `shape(..., normalized: true)`.
  List<double> norm(List<double> raw) {
    final d = _divisors ??= _computeDivisors();
    return [
      for (var i = 0; i < raw.length; i++)
        raw[i] / d[math.min(i, _slots - 1)],
    ];
  }

  List<double> _computeDivisors() {
    final d = List<double>.filled(_slots, 1.0);
    for (var i = 0; i < _slots; i++) {
      final stock = _stockGain(i);
      final p95 = _p95(_hist[i]);
      // No usable signal → behave like stock; otherwise normalize to
      // the track's p95, but never boost more than _maxBoost × stock.
      d[i] = p95 == null ? 1 / stock : math.max(p95, 1 / (stock * _maxBoost));
    }
    // The VU needles show channel balance — L and R normalize by their
    // SHARED peak so a lopsided mix stays lopsided on screen.
    final lr = math.max(d[_slots - 2], d[_slots - 1]);
    d[_slots - 2] = lr;
    d[_slots - 1] = lr;
    return d;
  }

  /// 95th percentile of the audible values in [h]; null when there's
  /// under ~1.5 s of signal above the floor (nothing to normalize to).
  double? _p95(Uint32List h) {
    var active = 0;
    for (var b = _floorBin; b < _bins; b++) {
      active += h[b];
    }
    if (active < 90) return null;
    var remain = math.max(1, (active * 0.05).round());
    for (var b = _bins - 1; b >= _floorBin; b--) {
      remain -= h[b];
      if (remain <= 0) return (b + 1) / _bins;
    }
    return null;
  }
}
