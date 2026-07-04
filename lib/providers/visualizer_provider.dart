import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/models/track.dart';
import '../visualizer/fft_channel.dart';
import '../visualizer/fft_processor.dart';
import 'audio_provider.dart';
import 'theme_provider.dart';

/// User gain for the visualizer (soft songs barely register at 1×).
/// Persisted; applied before the perceptual curve in [BandShaper].
class VisualizerSensitivityNotifier extends Notifier<double> {
  static const _key = 'visualizer_sensitivity';

  @override
  double build() =>
      ref.watch(sharedPrefsProvider).getDouble(_key) ?? 1.0;

  void set(double value) {
    state = value.clamp(0.5, 3.0).toDouble();
    ref.read(sharedPrefsProvider).setDouble(_key, state);
  }
}

final visualizerSensitivityProvider =
    NotifierProvider<VisualizerSensitivityNotifier, double>(
        VisualizerSensitivityNotifier.new);

/// 12 frequency bands, 0–1, emitted at ~60 fps.
///
/// Band frames come from FftExtractorChannel: the track's audio is
/// decoded and analyzed once (then disk-cached), and this provider
/// samples the frame matching the current playback position — no
/// RECORD_AUDIO, sample-accurate, and independent of the output mix.
/// A gentle synthetic pulse covers the moments before frames exist
/// (extraction outruns playback within a second) and files the
/// decoder can't read.
final visualizerBandsProvider = StreamProvider<List<double>>((ref) {
  final controller = StreamController<List<double>>();
  final shaper = BandShaper();

  const frameRate = 60; // must match FftExtractorChannel.FRAME_RATE
  const bandCount = BandShaper.bandCount;

  String? currentKey;
  var frames = <double>[]; // flattened frames × 12
  var extractionDone = false;

  // Position extrapolation between player reports (same pattern as the
  // lyrics sheet) so sampling doesn't step at the stream's rate.
  var lastPosition = Duration.zero;
  final sinceReport = Stopwatch();
  ref.listen(positionProvider, (_, next) {
    final pos = next.value;
    if (pos != null) {
      lastPosition = pos;
      sinceReport
        ..reset()
        ..start();
    }
  });

  void startFor(Track track) {
    // v2: fractional-hop frame timing (old caches drift on rates not
    // divisible by 60).
    final path = track.filePath;
    final key = path == null
        ? 'stream_${track.source.name}_${track.sourceId}'
        : 'v2_${track.mediaId ?? track.sourceId}_${path.hashCode}_${track.duration.inMilliseconds}';
    if (key == currentKey) return;
    currentKey = key;
    frames = <double>[];
    extractionDone = false;
    if (path != null) {
      FftChannel.start(path, key);
    } else {
      // Online stream: decode the remote URL where the provider serves
      // full-speed (Saavn — MediaExtractor reads https directly and
      // outruns playback). resolver returns null for throttled sources
      // (YouTube) so the synth pulse covers them. Resolution is async
      // and coalesced with play-time; guard against a track change.
      final resolver = ref.read(audioHandlerProvider).engine.resolver;
      resolver.decodableStreamUrl(track).then((url) {
        if (url != null && key == currentKey) FftChannel.start(url, key);
      });
    }
  }

  final frameSub = FftChannel.frames.listen((event) {
    if (event['key'] != currentKey) return; // stale job
    final offset = (event['offset'] as int) * bandCount;
    final bands = (event['bands'] as List).cast<double>();
    // Chunks arrive in order; tolerate a gap by zero-filling.
    if (frames.length < offset) {
      frames.addAll(List.filled(offset - frames.length, 0.0));
    }
    frames.addAll(bands);
    if (event['done'] == true) extractionDone = true;
  });

  ref.listen(audioStateProvider, (_, next) {
    final track = next.value?.currentTrack;
    if (track != null) startFor(track);
  });
  final initial = ref.read(audioStateProvider).value?.currentTrack;
  if (initial != null) startFor(initial);

  /// Frame at [position], linearly interpolated between neighbors.
  List<double>? sample(Duration position) {
    final frameCount = frames.length ~/ bandCount;
    if (frameCount == 0) return null;
    final exact = position.inMilliseconds * frameRate / 1000;
    final lo = exact.floor();
    if (lo >= frameCount) {
      // Past the analyzed range: silence tail if extraction finished,
      // not-yet-decoded if it's still running.
      return extractionDone ? List.filled(bandCount, 0.0) : null;
    }
    final hi = math.min(lo + 1, frameCount - 1);
    final t = exact - lo;
    return [
      for (var b = 0; b < bandCount; b++)
        frames[lo * bandCount + b] * (1 - t) +
            frames[hi * bandCount + b] * t,
    ];
  }

  List<double> synth(bool playing) {
    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
    return [
      for (var i = 0; i < bandCount; i++)
        playing
            ? (0.12 +
                    0.12 * math.sin(t * 2.1 + i * 0.9) +
                    0.08 * math.sin(t * 3.7 + i * 1.7))
                .clamp(0.02, 1.0)
            : 0.0,
    ];
  }

  // ~60 fps drive for the renderers (the old Visualizer capture capped
  // this at 30 Hz, which looked steppy).
  var settled = false;
  final timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
    final playing = ref.read(audioStateProvider).value?.isPlaying ?? false;
    final position =
        playing ? lastPosition + sinceReport.elapsed : lastPosition;
    final raw = playing ? (sample(position) ?? synth(true)) : synth(false);
    final sensitivity = ref.read(visualizerSensitivityProvider);
    final bands = shaper.shape(raw, sensitivity);
    // Paused + fully decayed: stop rebuilding every listener at 60 Hz.
    final quiet = !playing && bands.every((b) => b < 0.005);
    if (quiet && settled) return;
    settled = quiet;
    controller.add(bands);
  });

  ref.onDispose(() {
    timer.cancel();
    frameSub.cancel();
    controller.close();
    FftChannel.cancel();
  });

  return controller.stream;
});

/// Overall loudness 0–1 (low-band weighted) — drives the mascot bop.
final amplitudeProvider = Provider<double>((ref) {
  final bands = ref.watch(visualizerBandsProvider).value;
  if (bands == null || bands.isEmpty) return 0;
  return (bands[0] * 0.4 +
          bands[1] * 0.3 +
          bands[2] * 0.2 +
          bands[3] * 0.1)
      .clamp(0.0, 1.0);
});
