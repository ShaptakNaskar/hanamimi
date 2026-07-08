import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/reco/feature_extractor.dart';

/// M38a: the audio-feature summary that feeds content similarity.
/// Synthetic frame runs with known shape → known vector values.
void main() {
  const bands = 12;
  const fps = 60;

  List<double> constantFrames(int frameCount, List<double> perBand) => [
        for (var f = 0; f < frameCount; f++) ...perBand,
      ];

  test('too-short tracks produce no vector', () {
    final frames = constantFrames(fps * 3, List.filled(bands, 0.5));
    expect(summarizeFrames(frames), isEmpty);
  });

  test('band means and stds reflect the signal', () {
    // 30 s of a fixed spectrum: means = the spectrum, stds = 0.
    final spectrum = [
      for (var b = 0; b < bands; b++) 0.1 + b * 0.05,
    ];
    final v = summarizeFrames(constantFrames(fps * 30, spectrum));
    expect(v, hasLength(trackFeaturesLength));
    for (var b = 0; b < bands; b++) {
      expect(v[b], closeTo(spectrum[b], 1e-4));
      expect(v[bands + b], closeTo(0, 1e-4));
    }
    // A constant signal has no onsets and no beat.
    expect(v[28], closeTo(0, 1e-4));
    expect(v[29], closeTo(0, 1e-4));
  });

  test('tempo lands on a synthetic 120 BPM pulse', () {
    // 120 BPM at 60 fps = an energy burst every 30 frames.
    final frames = <double>[];
    for (var f = 0; f < fps * 40; f++) {
      final hit = f % 30 == 0 ? 0.8 : 0.05;
      frames.addAll(List.filled(bands, hit));
    }
    final v = summarizeFrames(frames);
    expect(v[29] * 200, closeTo(120, 3));
  });

  test('centroid tracks brightness', () {
    // All energy in the top band → centroid ≈ 1; bottom band → ≈ 0.
    final top = List<double>.filled(bands, 0.0)..[bands - 1] = 0.6;
    final bottom = List<double>.filled(bands, 0.0)..[0] = 0.6;
    expect(summarizeFrames(constantFrames(fps * 10, top))[24],
        closeTo(1.0, 1e-4));
    expect(summarizeFrames(constantFrames(fps * 10, bottom))[24],
        closeTo(0.0, 1e-4));
  });

  test('featureSimilarity: identical → 1, orthogonal → 0', () {
    Uint8List bytes(List<double> v) =>
        Float32List.fromList(v.cast<double>()).buffer.asUint8List();
    final a = bytes([1, 0, 2, 0]);
    final b = bytes([0, 3, 0, 4]);
    expect(featureSimilarity(a, a), closeTo(1, 1e-6));
    expect(featureSimilarity(a, b), closeTo(0, 1e-6));
    // Scaled copies are still "the same sound".
    final scaled = bytes([2, 0, 4, 0]);
    expect(featureSimilarity(a, scaled), closeTo(1, 1e-6));
    // Length mismatch / empty degrade to 0, never throw.
    expect(featureSimilarity(a, bytes([1, 2])), 0);
    expect(featureSimilarity(Uint8List(0), Uint8List(0)), 0);
  });

  test('similar spectra rank closer than different ones', () {
    final warm = [
      for (var b = 0; b < bands; b++) math.exp(-b / 3) * 0.5,
    ];
    final warmish = [
      for (var b = 0; b < bands; b++) math.exp(-b / 3.4) * 0.45,
    ];
    final bright = [
      for (var b = 0; b < bands; b++) math.exp(-(bands - 1 - b) / 3) * 0.5,
    ];
    Uint8List vec(List<double> spectrum) =>
        summarizeFrames(constantFrames(fps * 10, spectrum))
            .buffer
            .asUint8List();
    final w = vec(warm);
    expect(featureSimilarity(w, vec(warmish)),
        greaterThan(featureSimilarity(w, vec(bright))));
  });
}
