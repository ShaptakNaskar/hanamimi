import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../audio/queue_manager.dart';
import 'audio_provider.dart';

enum SleepMode { off, countdown, endOfTrack }

class SleepTimerState {
  const SleepTimerState({
    this.mode = SleepMode.off,
    this.remaining,
    this.isFading = false,
  });

  final SleepMode mode;
  final Duration? remaining;
  final bool isFading;

  bool get isActive => mode != SleepMode.off;
}

class SleepTimerNotifier extends Notifier<SleepTimerState> {
  Timer? _tick;
  Timer? _fade;

  static const _fadeDuration = Duration(seconds: 30);

  @override
  SleepTimerState build() {
    ref.onDispose(_cancelTimers);
    return const SleepTimerState();
  }

  void startCountdown(Duration duration) {
    _cancelTimers();
    _engine.pauseAtTrackEnd = false;
    state = SleepTimerState(mode: SleepMode.countdown, remaining: duration);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = state.remaining! - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        _tick?.cancel();
        _beginFade();
      } else {
        state = SleepTimerState(mode: SleepMode.countdown, remaining: left);
      }
    });
  }

  void startEndOfTrack() {
    _cancelTimers();
    _engine.pauseAtTrackEnd = true;
    _engine.onSleepTimerFired = () {
      state = const SleepTimerState();
    };
    state = const SleepTimerState(mode: SleepMode.endOfTrack);
  }

  /// 30-second smoothstep fade to silence (screen dims alongside),
  /// then pause and restore volume so the next manual play is full
  /// loudness.
  void _beginFade() {
    state = SleepTimerState(
        mode: state.mode, remaining: Duration.zero, isFading: true);
    final stopwatch = Stopwatch()..start();
    _fade = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      final t = (stopwatch.elapsedMilliseconds /
              _fadeDuration.inMilliseconds)
          .clamp(0.0, 1.0);
      final e = t * t * (3 - 2 * t);
      await _engine.setVolume(1 - e);
      await _setBrightness(1 - e * 0.85); // dim to 15%, not black
      if (t >= 1) {
        timer.cancel();
        await _engine.pause();
        await _engine.setVolume(1);
        await _resetBrightness();
        state = const SleepTimerState();
      }
    });
  }

  /// Cancel: ramp back to full volume over 2 seconds, restore screen.
  void cancel() {
    final wasFading = state.isFading;
    _cancelTimers();
    _engine.pauseAtTrackEnd = false;
    state = const SleepTimerState();
    _resetBrightness();
    if (wasFading) {
      final stopwatch = Stopwatch()..start();
      Timer.periodic(const Duration(milliseconds: 50), (timer) async {
        final t =
            (stopwatch.elapsedMilliseconds / 2000).clamp(0.0, 1.0);
        await _engine.setVolume(t);
        if (t >= 1) timer.cancel();
      });
    }
  }

  // App-level brightness only — never touches the system setting.
  // Best-effort: some ROMs deny it, and that shouldn't break the fade.
  // Desktop monitors aren't ours to dim — the volume fade carries it.
  Future<void> _setBrightness(double value) async {
    if (!Platform.isAndroid) return;
    try {
      await ScreenBrightness.instance
          .setApplicationScreenBrightness(value.clamp(0.05, 1.0));
    } catch (_) {}
  }

  Future<void> _resetBrightness() async {
    if (!Platform.isAndroid) return;
    try {
      await ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {}
  }

  void _cancelTimers() {
    _tick?.cancel();
    _fade?.cancel();
  }

  QueueManager get _engine => ref.read(audioHandlerProvider).engine;
}

final sleepTimerProvider =
    NotifierProvider<SleepTimerNotifier, SleepTimerState>(
        SleepTimerNotifier.new);
