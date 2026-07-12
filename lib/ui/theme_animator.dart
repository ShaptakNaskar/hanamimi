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
    _c.dispose();
    super.dispose();
  }

  /// Recolour driven by the crossfade's progress. Runs on every audio
  /// state / incoming-palette change.
  void _syncCrossfade() {
    final audio = ref.read(audioStateProvider).value;
    final xf = audio?.crossfadeProgress;
    final incoming = ref.read(crossfadeIncomingThemeProvider).value;

    if (xf != null && incoming != null) {
      // Actively fading: lerp the palette from where we started toward
      // the incoming art by the fade's progress.
      _xfBase ??= ref.read(currentThemeProvider);
      _xfIncoming = incoming;
      _xfIncomingId = audio!.crossfadeIncomingTrack?.id;
      _c.stop(); // the 400ms wash mustn't fight the fade-driven lerp
      final e = Curves.easeInOut.transform(xf);
      ref
          .read(currentThemeProvider.notifier)
          .set(HanamimiTheme.lerp(_xfBase!, incoming, e));
      return;
    }

    // The fade ended (or was aborted). Settle.
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
