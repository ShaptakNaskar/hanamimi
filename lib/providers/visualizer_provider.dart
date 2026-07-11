import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/models/track.dart';
import '../reco/feature_extractor.dart';
import '../theme/hanamimi_theme.dart';
import '../visualizer/fft_channel.dart';
import '../visualizer/fft_processor.dart';
import 'audio_provider.dart';
import 'library_provider.dart';
import 'theme_provider.dart';
import 'window_activity_provider.dart';

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

/// Needle reactivity for the VU meters: high = jumpy, low = smoothed.
/// Drives the needle spring stiffness in the painter (sensitivity
/// stays a pure gain on the bands).
class VisualizerReactivityNotifier extends Notifier<double> {
  static const _key = 'visualizer_reactivity';

  @override
  double build() =>
      ref.watch(sharedPrefsProvider).getDouble(_key) ?? 1.0;

  void set(double value) {
    state = value.clamp(0.5, 3.0).toDouble();
    ref.read(sharedPrefsProvider).setDouble(_key, state);
  }
}

final visualizerReactivityProvider =
    NotifierProvider<VisualizerReactivityNotifier, double>(
        VisualizerReactivityNotifier.new);

/// What the VU needles measure: false = true L/R channel loudness
/// (real-VU behaviour), true = the old bass/treble split.
class VuSplitNotifier extends Notifier<bool> {
  static const _key = 'vu_split';

  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(_key) ?? false;

  void set(bool on) {
    ref.read(sharedPrefsProvider).setBool(_key, on);
    state = on;
  }
}

final vuSplitProvider =
    NotifierProvider<VuSplitNotifier, bool>(VuSplitNotifier.new);

/// LED VU meter look: true = discrete LED segments (the foobar VU),
/// false = continuous gradient bar (the OBS mixer).
class LedVuDiscreteNotifier extends Notifier<bool> {
  static const _key = 'led_vu_discrete';

  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(_key) ?? true;

  void set(bool on) {
    ref.read(sharedPrefsProvider).setBool(_key, on);
    state = on;
  }
}

final ledVuDiscreteProvider =
    NotifierProvider<LedVuDiscreteNotifier, bool>(LedVuDiscreteNotifier.new);

/// User-chosen visualizer style; null means "follow the theme".
/// Persisted by enum name so reordering the enum can't corrupt it.
class VisualizerStyleOverrideNotifier extends Notifier<VisualizerStyle?> {
  static const _key = 'visualizer_style_override';

  @override
  VisualizerStyle? build() {
    final name = ref.watch(sharedPrefsProvider).getString(_key);
    return VisualizerStyle.values.asNameMap()[name];
  }

  void set(VisualizerStyle? style) {
    state = style;
    final prefs = ref.read(sharedPrefsProvider);
    if (style == null) {
      prefs.remove(_key);
    } else {
      prefs.setString(_key, style.name);
    }
  }
}

final visualizerStyleOverrideProvider =
    NotifierProvider<VisualizerStyleOverrideNotifier, VisualizerStyle?>(
        VisualizerStyleOverrideNotifier.new);

/// The style renderers should draw: the user override, else the theme's.
final effectiveVisualizerStyleProvider = Provider<VisualizerStyle>((ref) =>
    ref.watch(visualizerStyleOverrideProvider) ??
    ref.watch(currentThemeProvider).visualizerStyle);

/// 12 frequency bands + L/R channel loudness, 0–1, at ~60 fps.
///
/// Emits 14 values: [0..11] spectral bands, [12] left-channel RMS,
/// [13] right-channel RMS (the true VU-meter signal). Frames come from
/// FftExtractorChannel: the track's audio is decoded and analyzed once
/// (then disk-cached), and this provider samples the frame matching
/// the current playback position — no RECORD_AUDIO, sample-accurate,
/// and independent of the output mix. Both extractors send 14-float
/// frames ('stride': 14); if a frame ever arrives without channel RMS
/// (stride 12), a lows/highs pseudo-split stands in for L/R. A gentle
/// synthetic pulse covers the moments before frames exist (extraction
/// outruns playback within a second) and files the decoder can't read.
final visualizerBandsProvider = StreamProvider<List<double>>((ref) {
  final controller = StreamController<List<double>>();
  final shaper = BandShaper();

  const frameRate = 60; // must match FftExtractorChannel.FRAME_RATE
  const bandCount = BandShaper.bandCount;
  const outCount = bandCount + 2; // bands + L/R loudness

  String? currentKey;
  int? currentTrackId; // DB row id, for the M38a feature store
  var frames = <double>[]; // flattened frames × stride
  var stride = bandCount; // floats per frame in [frames]
  var extractionDone = false;

  // Watchdog state: extraction can die without producing a frame —
  // e.g. MediaCodec is exhausted while ANOTHER app still holds the
  // hardware decoders during a cross-app playback handoff. One-shot
  // extraction then leaves the synth pulse on screen for the whole
  // track. Retried (bounded) from the render timer below.
  String? retryKey;
  var retries = 0;
  var noFramesSince = 0; // ms epoch; 0 = clock not running
  var lastResumeTick = 0; // detects app-resume to re-arm the watchdog

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
    // v3: frames carry L/R RMS after the bands (v2 fixed fractional-hop
    // frame timing). New prefixes miss the old 12-float cache files,
    // which age out of the extractor's LRU.
    final path = track.filePath;
    final key = path == null
        ? 'stream3_${track.source.name}_${track.sourceId}'
        : 'v3_${track.mediaId ?? track.sourceId}_${path.hashCode}_${track.duration.inMilliseconds}';
    if (key == currentKey) return;
    currentKey = key;
    currentTrackId = track.id;
    frames = <double>[];
    stride = bandCount;
    extractionDone = false;
    if (key != retryKey) {
      // Genuinely new track — fresh retry budget.
      retryKey = key;
      retries = 0;
    }
    noFramesSince = 0;
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
    // Both extractors flag 14-float frames; no flag means legacy 12.
    stride = (event['stride'] as int?) ?? bandCount;
    final offset = (event['offset'] as int) * stride;
    final bands = (event['bands'] as List).cast<double>();
    // Chunks arrive in order; tolerate a gap by zero-filling.
    if (frames.length < offset) {
      frames.addAll(List.filled(offset - frames.length, 0.0));
    }
    frames.addAll(bands);
    if (event['done'] == true) {
      extractionDone = true;
      // M38a: the decode we just paid for doubles as the content-
      // similarity source — summarize the full frame run into the
      // track's feature vector (once per track per layout version).
      // Strip the RMS columns first: vectors must stay comparable with
      // the 12-band ones already in the library.
      final tid = currentTrackId;
      if (tid != null && frames.isNotEmpty) {
        final s = stride;
        final snapshot = s == bandCount
            ? List<double>.from(frames)
            : <double>[
                for (var f = 0; f + s <= frames.length; f += s)
                  ...frames.getRange(f, f + bandCount),
              ];
        Future(() async {
          final repo = await ref.read(libraryRepositoryProvider.future);
          if (await repo.hasTrackFeatures(tid, trackFeaturesVersion)) {
            return;
          }
          final vector = summarizeFrames(snapshot);
          if (vector.isEmpty) return;
          await repo.saveTrackFeatures(
              tid, trackFeaturesVersion, vector.buffer.asUint8List());
        });
      }
    }
  });

  ref.listen(audioStateProvider, (_, next) {
    final track = next.value?.currentTrack;
    if (track != null) startFor(track);
  });
  final initial = ref.read(audioStateProvider).value?.currentTrack;
  if (initial != null) startFor(initial);

  /// Frame at [position], linearly interpolated between neighbors.
  /// Always [outCount] values: 12-float frames get a lows/highs
  /// pseudo-split appended in place of the missing channel RMS.
  List<double>? sample(Duration position) {
    final s = stride;
    final frameCount = frames.length ~/ s;
    if (frameCount == 0) return null;
    final exact = position.inMilliseconds * frameRate / 1000;
    final lo = exact.floor();
    if (lo >= frameCount) {
      // Past the analyzed range: silence tail if extraction finished,
      // not-yet-decoded if it's still running.
      return extractionDone ? List.filled(outCount, 0.0) : null;
    }
    final hi = math.min(lo + 1, frameCount - 1);
    final t = exact - lo;
    final raw = [
      for (var b = 0; b < s; b++)
        frames[lo * s + b] * (1 - t) + frames[hi * s + b] * t,
    ];
    if (s < outCount) {
      raw
        ..add(raw[0] * 0.35 + raw[1] * 0.30 + raw[2] * 0.20 + raw[3] * 0.15)
        ..add(raw[6] * 0.15 +
            raw[7] * 0.20 +
            raw[8] * 0.25 +
            raw[9] * 0.20 +
            raw[10] * 0.20);
    }
    return raw;
  }

  List<double> synth(bool playing) {
    final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final out = [
      for (var i = 0; i < outCount; i++)
        playing
            ? (0.12 +
                    0.12 * math.sin(t * 2.1 + i * 0.9) +
                    0.08 * math.sin(t * 3.7 + i * 1.7))
                .clamp(0.02, 1.0)
            : 0.0,
    ];
    if (playing && outCount >= 14) {
      // The sine ripple reads fine as bars, but the VU styles drive
      // their needles/LEDs from the L/R slots — where the ripple turns
      // into two rigid metronomes (user report). Meters expect a
      // loudness ENVELOPE, so fake a groove instead: a decaying kick,
      // a softer offbeat hat, per-beat accent variation, a slow swell,
      // and a small L/R skew so the channels breathe independently.
      const bps = 104 / 60; // unhurried; doesn't race whatever's loading
      final beat = t * bps;
      final ph = beat - beat.floorToDouble();
      // Cheap deterministic per-beat "randomness" (shader-style hash).
      final accent =
          0.7 + 0.3 * ((math.sin(beat.floorToDouble() * 12.9898) * 43758.5453) % 1.0);
      final kick = accent * math.exp(-ph * 6.5);
      final hat = 0.35 * math.exp(-((ph + 0.5) % 1.0) * 9.0);
      final swell = 0.8 + 0.2 * math.sin(t * 0.31);
      final rms = (0.16 + 0.55 * kick + 0.18 * hat) * swell;
      final skew = 0.08 * math.sin(t * 1.7);
      out[12] = (rms * (1 + skew)).clamp(0.02, 1.0);
      out[13] = (rms * (1 - skew)).clamp(0.02, 1.0);
    }
    return out;
  }

  // ~60 fps drive for the renderers (the old Visualizer capture capped
  // this at 30 Hz, which looked steppy).
  var settled = false;
  var tick = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
    // Minimized: freeze the stream — every emission rebuilds all the
    // band listeners and keeps the render pipeline hot for a window
    // nobody can see. Unfocused (visible on a second monitor, another
    // app in front): keep moving at half rate.
    tick++;
    if (!windowVisible.value) return;
    if (!windowFocused.value && tick.isOdd) return;
    final playing = ref.read(audioStateProvider).value?.isPlaying ?? false;
    final position =
        playing ? lastPosition + sinceReport.elapsed : lastPosition;

    // Coming back from the background can leave a dead FFT extraction
    // (MediaCodec was reclaimed while frozen) with the retry budget spent,
    // stranding the synth pulse. Re-arm the watchdog on each resume so it
    // re-kicks the same track's extraction.
    final resumeTick = ref.read(appResumeTickProvider);
    if (resumeTick != lastResumeTick) {
      lastResumeTick = resumeTick;
      if (frames.isEmpty) {
        retries = 0;
        noFramesSince = 0;
      }
    }

    // Watchdog: playing but no real frame has landed → the extraction
    // died (codec busy, stream hiccup). Re-kick it, up to 3 times.
    if (playing && frames.isEmpty && currentKey != null && retries < 3) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (noFramesSince == 0) {
        noFramesSince = now;
      } else if (now - noFramesSince > 4000) {
        retries++;
        currentKey = null; // defeat the same-key guard
        final track = ref.read(audioStateProvider).value?.currentTrack;
        if (track != null) startFor(track);
      }
    } else if (frames.isNotEmpty) {
      noFramesSince = 0;
    }
    final raw = playing ? (sample(position) ?? synth(true)) : synth(false);
    final sensitivity = ref.read(visualizerSensitivityProvider);
    final reactivity = ref.read(visualizerReactivityProvider);
    final bands = shaper.shape(raw, sensitivity, reactivity);
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
