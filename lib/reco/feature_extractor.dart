import 'dart:math' as math;
import 'dart:typed_data';

/// Feature-vector layout version; bump when the layout below changes so
/// stale vectors get recomputed on next play.
const trackFeaturesVersion = 1;

/// Number of floats in a v1 vector.
const trackFeaturesLength = 30;

/// Summarizes a track's full visualizer decode (flattened frames × 12
/// linear band amplitudes at [frameRate] fps — exactly what the FFT
/// pipeline already produces) into a compact similarity vector. This is
/// the "content" leg of the recommender: nearest neighbours over these
/// vectors answer "what in my library sounds like this?".
///
/// v1 layout (30 floats):
///   [0..11]  per-band mean            (timbre / EQ shape)
///   [12..23] per-band std deviation   (dynamics per band)
///   [24]     spectral centroid mean   (brightness, 0–1 over bands)
///   [25]     spectral centroid std
///   [26]     total energy mean        (loudness feel)
///   [27]     total energy std
///   [28]     onset-flux mean          (percussiveness)
///   [29]     tempo estimate, BPM/200  (0 when no confident beat)
///
/// Returns an empty list for tracks too short to summarize (< 5 s).
Float32List summarizeFrames(
  List<double> frames, {
  int bandCount = 12,
  int frameRate = 60,
}) {
  final frameCount = frames.length ~/ bandCount;
  if (frameCount < frameRate * 5) return Float32List(0);

  final vector = Float32List(trackFeaturesLength);

  // Per-band mean/std + per-frame energy & centroid in one pass.
  final bandSum = List<double>.filled(bandCount, 0);
  final bandSumSq = List<double>.filled(bandCount, 0);
  final energy = Float64List(frameCount);
  var centroidSum = 0.0, centroidSumSq = 0.0;
  for (var f = 0; f < frameCount; f++) {
    var total = 0.0, weighted = 0.0;
    for (var b = 0; b < bandCount; b++) {
      final v = frames[f * bandCount + b];
      bandSum[b] += v;
      bandSumSq[b] += v * v;
      total += v;
      weighted += v * b;
    }
    energy[f] = total;
    final centroid = total > 1e-9 ? (weighted / total) / (bandCount - 1) : 0.0;
    centroidSum += centroid;
    centroidSumSq += centroid * centroid;
  }
  double std(double sum, double sumSq, int n) {
    final mean = sum / n;
    return math.sqrt(math.max(0, sumSq / n - mean * mean));
  }

  for (var b = 0; b < bandCount; b++) {
    vector[b] = bandSum[b] / frameCount;
    vector[bandCount + b] = std(bandSum[b], bandSumSq[b], frameCount);
  }
  vector[24] = centroidSum / frameCount;
  vector[25] = std(centroidSum, centroidSumSq, frameCount);
  var eSum = 0.0, eSumSq = 0.0;
  for (final e in energy) {
    eSum += e;
    eSumSq += e * e;
  }
  vector[26] = eSum / frameCount;
  vector[27] = std(eSum, eSumSq, frameCount);

  // Onset envelope: positive spectral flux (energy rising frame-over-
  // frame), the standard beat-tracking front end.
  final onset = Float64List(frameCount - 1);
  var onsetSum = 0.0;
  for (var f = 1; f < frameCount; f++) {
    var flux = 0.0;
    for (var b = 0; b < bandCount; b++) {
      final d =
          frames[f * bandCount + b] - frames[(f - 1) * bandCount + b];
      if (d > 0) flux += d;
    }
    onset[f - 1] = flux;
    onsetSum += flux;
  }
  vector[28] = onsetSum / onset.length;

  vector[29] = _tempoEstimate(onset, frameRate) / 200.0;
  return vector;
}

/// Autocorrelation of the onset envelope over the 60–180 BPM lag range.
/// Returns 0 when the strongest peak isn't convincingly above the
/// envelope's self-noise (ambient/speech — no beat to speak of).
double _tempoEstimate(Float64List onset, int frameRate) {
  final n = onset.length;
  final minLag = (frameRate * 60) ~/ 180; // 180 BPM
  final maxLag = (frameRate * 60) ~/ 60; // 60 BPM
  if (n < maxLag * 3) return 0;

  var mean = 0.0;
  for (final v in onset) {
    mean += v;
  }
  mean /= n;

  var r0 = 0.0;
  for (final v in onset) {
    r0 += (v - mean) * (v - mean);
  }
  if (r0 < 1e-9) return 0;

  var bestLag = 0;
  var bestR = 0.0;
  for (var lag = minLag; lag <= maxLag; lag++) {
    var r = 0.0;
    for (var i = 0; i + lag < n; i++) {
      r += (onset[i] - mean) * (onset[i + lag] - mean);
    }
    r /= r0;
    if (r > bestR) {
      bestR = r;
      bestLag = lag;
    }
  }
  if (bestLag == 0 || bestR < 0.1) return 0;
  return frameRate * 60 / bestLag;
}

/// Cosine similarity between two stored vectors (raw float32 bytes).
/// 0 when either vector is missing/degenerate.
double featureSimilarity(Uint8List a, Uint8List b) {
  final va = a.buffer.asFloat32List(a.offsetInBytes, a.length ~/ 4);
  final vb = b.buffer.asFloat32List(b.offsetInBytes, b.length ~/ 4);
  if (va.isEmpty || va.length != vb.length) return 0;
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < va.length; i++) {
    dot += va[i] * vb[i];
    na += va[i] * va[i];
    nb += vb[i] * vb[i];
  }
  if (na < 1e-12 || nb < 1e-12) return 0;
  return dot / (math.sqrt(na) * math.sqrt(nb));
}
