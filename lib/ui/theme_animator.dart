import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/adaptive_theme_provider.dart';
import '../providers/audio_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/hanamimi_theme.dart';

/// Drives the gentle cross-fade between themes. Watches the resolved target
/// ([resolvedThemeProvider]) and lerps the displayed theme
/// ([currentThemeProvider]) toward it over ~400 ms, so switching themes —
/// and the adaptive theme recolouring per track — washes in smoothly
/// instead of snapping. Mounted once, above the app content.
///
/// During an audio crossfade it hands the wheel to [_syncCrossfade]: the
/// palette lerps from the outgoing art to the (pre-computed) incoming art
/// by the crossfade's own progress, so the visualizer, transport buttons
/// and seek bar recolour in lockstep with the art wipe rather than
/// snapping when the track finally switches.
class ThemeAnimator extends ConsumerStatefulWidget {
  const ThemeAnimator({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ThemeAnimator> createState() => _ThemeAnimatorState();
}

class _ThemeAnimatorState extends ConsumerState<ThemeAnimator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  HanamimiTheme? _from;
  HanamimiTheme? _to;

  // Crossfade recolour state. [_xfBase] is the palette on screen when the
  // fade began (its lerp anchor); [_xfIncoming]/[_xfIncomingId] the target
  // palette and the track it belongs to. [_graceUntilMs] briefly ignores
  // the resolved-theme wash after a fade finishes, to swallow the adaptive
  // provider's async re-resolve (which momentarily re-reports the OLD
  // palette and would otherwise wobble the colour back).
  HanamimiTheme? _xfBase;
  HanamimiTheme? _xfIncoming;
  int? _xfIncomingId;
  int _graceUntilMs = 0;
  Timer? _xfTimer;

  bool get _inGrace =>
      DateTime.now().millisecondsSinceEpoch < _graceUntilMs;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addListener(() {
        final from = _from, to = _to;
        if (from != null && to != null) {
          ref
              .read(currentThemeProvider.notifier)
              .set(HanamimiTheme.lerp(from, to, _c.value));
        }
      });
  }

  @override
  void dispose() {
    _xfTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  /// One step of the fade-driven palette lerp. Runs on a deliberate
  /// ~150 ms cadence, NOT per frame: every set() here re-themes the
  /// entire app (every screen watches the theme), so tracking the
  /// fade's 60 Hz progress would rebuild the world for the whole fade
  /// — the color moves so little per step that this looks identical.
  void _stepCrossfadeLerp() {
    final incoming = _xfIncoming;
    // The end/abort emission cancels this timer; between the engine's
    // notifier reset and that emission, never lerp backwards.
    if (incoming == null ||
        ref.read(audioStateProvider).value?.crossfadeIncomingTrack == null) {
      return;
    }
    final engine = ref.read(audioHandlerProvider).engine;
    final e = Curves.easeInOut.transform(engine.crossfadeT.value);
    ref
        .read(currentThemeProvider.notifier)
        .set(HanamimiTheme.lerp(_xfBase!, incoming, e));
  }

  /// Recolour driven by the crossfade. Runs on the fade's start/end
  /// audio-state emissions and when the incoming palette arrives.
  void _syncCrossfade() {
    final audio = ref.read(audioStateProvider).value;
    final fading = audio?.crossfadeIncomingTrack != null;
    final incoming = ref.read(crossfadeIncomingThemeProvider).value;

    if (fading && incoming != null) {
      // Actively fading: lerp the palette from where we started toward
      // the incoming art by the fade's progress.
      _xfBase ??= ref.read(currentThemeProvider);
      _xfIncoming = incoming;
      _xfIncomingId = audio!.crossfadeIncomingTrack?.id;
      _c.stop(); // the 400ms wash mustn't fight the fade-driven lerp
      _xfTimer ??= Timer.periodic(
          const Duration(milliseconds: 150), (_) => _stepCrossfadeLerp());
      _stepCrossfadeLerp();
      return;
    }

    // The fade ended (or was aborted). Settle.
    _xfTimer?.cancel();
    _xfTimer = null;
    if (_xfBase != null) {
      final currentId = audio?.currentTrack?.id;
      if (_xfIncoming != null && currentId == _xfIncomingId) {
        // Finished onto the incoming track — pin its palette and hold
        // through the adaptive provider's async re-resolve.
        ref.read(currentThemeProvider.notifier).set(_xfIncoming!);
        _graceUntilMs = DateTime.now().millisecondsSinceEpoch + 1500;
      } else {
        // Aborted / diverted elsewhere — ease to whatever's current now.
        _from = ref.read(currentThemeProvider);
        _to = ref.read(resolvedThemeProvider);
        _c.forward(from: 0);
      }
      _xfBase = null;
      _xfIncoming = null;
      _xfIncomingId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<HanamimiTheme>(resolvedThemeProvider, (_, next) {
      // While a fade owns the colour (or during the post-fade settle
      // grace), don't snap the 400ms wash on top of it.
      if (_xfBase != null || _inGrace) return;
      _from = ref.read(currentThemeProvider); // lerp from what's on screen
      _to = next;
      _c.forward(from: 0);
    });
    ref.listen(audioStateProvider, (_, __) => _syncCrossfade());
    ref.listen(crossfadeIncomingThemeProvider, (_, __) => _syncCrossfade());
    return widget.child;
  }
}
