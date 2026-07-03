import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../visualizer/fft_processor.dart';
import '../visualizer/visualizer_channel.dart';
import 'audio_provider.dart';

/// 12 frequency bands, 0–1. Real FFT when the Visualizer is attached
/// (needs RECORD_AUDIO); otherwise a gentle synthetic pulse while
/// playing so the UI never looks dead.
final visualizerBandsProvider = StreamProvider<List<double>>((ref) {
  final controller = StreamController<List<double>>();
  final processor = FftProcessor();

  int? attachedSession;
  StreamSubscription? fftSub;
  Timer? synthTimer;
  var askedForPermission = false;

  Future<void> tryAttach(int sessionId) async {
    if (attachedSession == sessionId) return;
    // A new session arrives on every track change once crossfade is on —
    // ask once, then only re-check quietly so a denial doesn't turn into
    // a permission dialog per song.
    final status = askedForPermission
        ? await Permission.microphone.status
        : await Permission.microphone.request();
    askedForPermission = true;
    if (!status.isGranted) return;
    // The Kotlin side releases any previous Visualizer on re-attach —
    // needed because every crossfade swap creates a new audio session.
    if (await VisualizerChannel.attach(sessionId)) {
      attachedSession = sessionId;
      synthTimer?.cancel();
      fftSub ??= VisualizerChannel.fftStream.listen(
        (fft) => controller.add(processor.process(fft)),
      );
    }
  }

  // Synthetic fallback: soft waves while playing.
  void startSynth() {
    synthTimer?.cancel();
    synthTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final playing =
          ref.read(audioStateProvider).value?.isPlaying ?? false;
      final t = DateTime.now().millisecondsSinceEpoch / 1000.0;
      controller.add([
        for (var i = 0; i < FftProcessor.bandCount; i++)
          playing
              ? (0.3 +
                      0.3 * math.sin(t * 2.1 + i * 0.9) +
                      0.2 * math.sin(t * 3.7 + i * 1.7))
                  .clamp(0.05, 1.0)
              : 0.05,
      ]);
    });
  }

  startSynth();

  final sub = ref.listen(audioStateProvider, (prev, next) {
    final sessionId = next.value?.audioSessionId;
    if (sessionId != null) tryAttach(sessionId);
  });

  // The session id may already be known when this provider spins up.
  final existing = ref.read(audioStateProvider).value?.audioSessionId;
  if (existing != null) tryAttach(existing);

  ref.onDispose(() {
    sub.close();
    fftSub?.cancel();
    synthTimer?.cancel();
    controller.close();
    VisualizerChannel.detach();
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
