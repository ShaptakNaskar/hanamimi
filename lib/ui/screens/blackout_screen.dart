import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/audio_provider.dart';
import '../../providers/power_provider.dart';
import '../../providers/sleep_timer_provider.dart';
import '../../providers/visualizer_provider.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../../utils/duration_ext.dart';
import '../components/mascot/oneko.dart';
import '../components/now_playing/visualizer_widget.dart';

/// Blackout Mode (3.0 #3) — the bedside-amp screen. OLED-black canvas,
/// analog VU needles, a big dim clock, and the oneko cat asleep in the
/// corner. She stirs on track change instead of any text notification —
/// the cat *is* the track-change cue. Screen stays awake at a brightness
/// floor; tap anywhere for transport controls, tap the ✕ to leave.
///
/// Affordable as an always-on surface because the visualizer's ticker
/// gating (the constant-CPU fix) already stops all motion when frames
/// settle.
class BlackoutScreen extends ConsumerStatefulWidget {
  const BlackoutScreen({super.key});

  static Route<void> route() => PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 500),
    pageBuilder: (_, __, ___) => const BlackoutScreen(),
    transitionsBuilder:
        (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
  );

  @override
  ConsumerState<BlackoutScreen> createState() => _BlackoutScreenState();
}

class _BlackoutScreenState extends ConsumerState<BlackoutScreen> {
  Timer? _clock;
  Timer? _controlsHide;
  var _now = DateTime.now();
  var _controlsVisible = false;
  var _stir = 0;
  int? _lastTrackId;

  /// Caffeine's state, cached on every build — dispose() must not touch
  /// ref (a throw there silently skipped the system restores below and
  /// left the phone stuck fullscreen + awake until force stop,
  /// user-reported).
  var _caffeineOn = false;
  var _restored = false;

  @override
  void initState() {
    super.initState();
    _scheduleClock();
    PowerChannel.setKeepScreenOn(true);
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    // The dimming is a scrim INSIDE this screen (see build), not a
    // window-brightness override. The screen_brightness override left
    // Nothing OS refusing slider input after exit — "the top app is
    // controlling brightness" — until the whole app was killed
    // (user-reported). On an OLED over a pure-black canvas the scrim
    // dims emitted light just the same, and it cannot outlive the
    // route by construction.
  }

  /// Puts the system back the way we found it: edge-to-edge UI, screen
  /// allowed to sleep (unless Caffeine ☕ holds it). Idempotent; runs at
  /// pop time via PopScope while the route is fully alive, with
  /// dispose() as the fallback for any exit that skips the pop path.
  void _restoreSystem() {
    if (_restored) return;
    _restored = true;
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (!_caffeineOn) PowerChannel.setKeepScreenOn(false);
  }

  /// Ticks exactly on the minute — 1 rebuild/min, not a polling loop.
  void _scheduleClock() {
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _clock = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleClock();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _controlsHide?.cancel();
    _restoreSystem();
    super.dispose();
  }

  void _tap() {
    setState(() => _controlsVisible = !_controlsVisible);
    _armHide();
  }

  /// (Re)starts the auto-hide countdown while the overlay is up.
  void _armHide() {
    _controlsHide?.cancel();
    if (_controlsVisible) {
      _controlsHide = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final audio = ref.watch(audioStateProvider).value;
    final track = audio?.currentTrack;
    _caffeineOn = ref.watch(caffeineProvider);
    final timer = ref.watch(sleepTimerProvider);
    // Eye lock: keep the meters at full brightness (no auto-dim) so you
    // can just stare. The scrim drops to 0 whenever this is on OR the
    // transport is up.
    final undim = ref.watch(blackoutUndimProvider);

    // The cat is the notification: stir her when the track changes.
    if (track != null && track.id != _lastTrackId) {
      if (_lastTrackId != null) _stir++;
      _lastTrackId = track.id;
    }

    final dim = Colors.white.withValues(alpha: 0.55);
    final dimmer = Colors.white.withValues(alpha: 0.30);
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');

    return PopScope(
      // Any pop — ✕ button, back gesture, predictive back — restores
      // the system BEFORE the route starts tearing down.
      onPopInvokedWithResult: (_, __) => _restoreSystem(),
      child: Scaffold(
        // Hard black regardless of theme — this screen is FOR the OLED.
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                children: [
                  const Spacer(flex: 3),
                  Text(
                    '$hh:$mm',
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 72,
                      fontWeight: FontWeight.w200,
                      letterSpacing: 4,
                      color: dim,
                    ),
                  ),
                  if (track != null) ...[
                    const SizedBox(height: Space.s2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s6),
                      child: Text(
                        '${track.title} — ${track.artist}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 13,
                          color: dimmer,
                        ),
                      ),
                    ),
                  ],
                  if (timer.isActive) ...[
                    const SizedBox(height: Space.s4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bedtime_rounded, size: 13, color: dimmer),
                        const SizedBox(width: Space.s2),
                        Text(
                          switch (timer.mode) {
                            SleepMode.countdown => timer.isFading
                                ? 'fading out…'
                                : 'sleeping in ${timer.remaining!.mmss}',
                            SleepMode.endOfTrack =>
                              'sleeping when this song ends',
                            SleepMode.off => '',
                          },
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            letterSpacing: 1,
                            color: dimmer,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const Spacer(flex: 2),
                  // Analog needles wear the big bedside-dial size; bars
                  // and LED meters keep their Now Playing proportions —
                  // stretched to 200px they read as a wall of pixels
                  // (user report).
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.s4,
                        ),
                        child: VisualizerWidget(
                          height:
                              ref.watch(blackoutStyleProvider) ==
                                      VisualizerStyle.vuMeters
                                  ? 200
                                  : 56,
                          styleOverride: ref.watch(blackoutStyleProvider),
                          // Bedside palette: never album-art accents,
                          // nothing bright enough to sting at night.
                          muted: true,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(flex: 3),
                ],
              ),
              // The corner cat — asleep until the song changes.
              Positioned(
                right: Space.s6,
                bottom: Space.s6,
                child: StirringOneko(size: 40, stir: _stir),
              ),
              // The brightness floor, as pixels instead of a window
              // override: dims the ambient layer while idle and lifts
              // whenever the transport is up so buttons stay crisp.
              IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: (_controlsVisible || undim) ? 0.0 : 0.45,
                  child: Container(color: Colors.black),
                ),
              ),
              // Tap-to-reveal transport; fades itself away after 5 s.
              AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _controlsVisible ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Stack(
                    children: [
                      Positioned(
                        top: Space.s6,
                        right: Space.s6,
                        child: IconButton(
                          icon: Icon(Icons.close_rounded, color: dim),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      // Cycle the meters without leaving the dark:
                      // bars → analog VU → LED VU. Persisted.
                      Positioned(
                        top: Space.s6,
                        left: Space.s6,
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.equalizer_rounded, color: dim),
                              onPressed: () {
                                final styles = VisualizerStyle.values;
                                final current =
                                    ref.read(blackoutStyleProvider);
                                ref.read(blackoutStyleProvider.notifier).set(
                                      styles[(current.index + 1) %
                                          styles.length],
                                    );
                                _armHide(); // keep the overlay up while cycling
                              },
                            ),
                            // Eye: lock the dim off so the meters stay
                            // bright to stare at. Filled = locked bright.
                            IconButton(
                              tooltip: undim
                                  ? 'Let the screen dim'
                                  : 'Keep the meters bright',
                              icon: Icon(
                                undim
                                    ? Icons.remove_red_eye_rounded
                                    : Icons.remove_red_eye_outlined,
                                color: undim
                                    ? Colors.white.withValues(alpha: 0.75)
                                    : dim,
                              ),
                              onPressed: () {
                                ref
                                    .read(blackoutUndimProvider.notifier)
                                    .toggle();
                                _armHide();
                              },
                            ),
                          ],
                        ),
                      ),
                      if (timer.isActive)
                        Align(
                          alignment: const Alignment(0, 0.62),
                          child: TextButton.icon(
                            onPressed: () {
                              ref
                                  .read(sleepTimerProvider.notifier)
                                  .cancel();
                              _armHide();
                            },
                            icon: Icon(Icons.bedtime_off_rounded,
                                size: 16, color: dim),
                            label: Text('Cancel sleep timer',
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 13,
                                  color: dim,
                                )),
                          ),
                        ),
                      Align(
                        alignment: const Alignment(0, 0.82),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              iconSize: 34,
                              icon: Icon(
                                Icons.skip_previous_rounded,
                                color: dim,
                              ),
                              onPressed:
                                  () =>
                                      ref
                                          .read(audioHandlerProvider)
                                          .skipToPrevious(),
                            ),
                            const SizedBox(width: Space.s4),
                            IconButton(
                              iconSize: 44,
                              icon: Icon(
                                (audio?.isPlaying ?? false)
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                              onPressed: () {
                                final h = ref.read(audioHandlerProvider);
                                (audio?.isPlaying ?? false)
                                    ? h.pause()
                                    : h.play();
                              },
                            ),
                            const SizedBox(width: Space.s4),
                            IconButton(
                              iconSize: 34,
                              icon: Icon(Icons.skip_next_rounded, color: dim),
                              onPressed:
                                  () =>
                                      ref
                                          .read(audioHandlerProvider)
                                          .skipToNext(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
