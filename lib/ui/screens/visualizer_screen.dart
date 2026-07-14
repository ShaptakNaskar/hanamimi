import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/track.dart';
import '../../providers/audio_provider.dart';
import '../../providers/power_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/visualizer_provider.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/now_playing/visualizer_widget.dart';

/// Visualizer-Only Mode (3.0 feedback) — the "just let me stare" screen.
/// Unlike Blackout (the dim OLED bedside amp), this one keeps the album's
/// full color: a blurred art wash fills the room and the meters wear
/// their normal theme/album accents, big and centered. Tap anywhere for a
/// minimal transport that fades itself away; the top bar switches the
/// visualization and — for the VU meters — flips the needle source
/// (loudness ↔ bass/treble). Screen stays awake while you watch.
///
/// Cheap as a stare-surface for the same reason Blackout is: the
/// visualizer's ticker gating stops all motion when frames settle.
class VisualizerScreen extends ConsumerStatefulWidget {
  const VisualizerScreen({super.key});

  static Route<void> route() => PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) => const VisualizerScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      );

  @override
  ConsumerState<VisualizerScreen> createState() => _VisualizerScreenState();
}

class _VisualizerScreenState extends ConsumerState<VisualizerScreen> {
  Timer? _controlsHide;
  var _controlsVisible = false;

  /// Caffeine's state, cached each build — dispose() must not read ref
  /// (a throw there would skip the system restores, same lesson as
  /// Blackout).
  var _caffeineOn = false;
  var _restored = false;

  @override
  void initState() {
    super.initState();
    PowerChannel.setKeepScreenOn(true);
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  /// Puts the system back the way we found it. Idempotent; runs at pop
  /// time via PopScope while the route is alive, with dispose() as the
  /// fallback for exits that skip the pop path.
  void _restoreSystem() {
    if (_restored) return;
    _restored = true;
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (!_caffeineOn) PowerChannel.setKeepScreenOn(false);
  }

  @override
  void dispose() {
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
      _controlsHide = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final audio = ref.watch(audioStateProvider).value;
    final track = audio?.currentTrack;
    _caffeineOn = ref.watch(caffeineProvider);

    if (track == null) {
      // Nothing playing — bail back to where we came from.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    final style = ref.watch(effectiveVisualizerStyleProvider);
    // Both VU-type meters read L/R, so both get the source toggle...
    final isVu =
        style == VisualizerStyle.vuMeters || style == VisualizerStyle.ledVu;
    // ...but only the analog needle DIAL wants the big bedside size. The
    // LED VU (and bars) read as a stretched wall of pixels that tall — it
    // keeps its Now Playing proportion (the Blackout lesson).
    final vizHeight = switch (style) {
      VisualizerStyle.vuMeters => 220.0,
      VisualizerStyle.ledVu => 56.0,
      _ => 72.0,
    };

    return PopScope(
      onPopInvokedWithResult: (_, __) => _restoreSystem(),
      child: Scaffold(
        backgroundColor: theme.background,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Full-color album wash — the whole point vs. Blackout's
              // hard black. Blurred to a color field so the meters win.
              _ArtWash(track: track, theme: theme),
              // The star of the show.
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: Space.s6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        VisualizerWidget(
                          height: vizHeight,
                          styleOverride: style,
                        ),
                        const SizedBox(height: Space.s6),
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: theme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: Space.s1),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            color: theme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Tap-to-reveal chrome: top bar (close / switch viz / VU
              // source) and the transport. Fades itself away after 4 s.
              AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _controlsVisible ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: _Chrome(
                    theme: theme,
                    audio: audio,
                    style: style,
                    isVu: isVu,
                    onClose: () => Navigator.of(context).pop(),
                    onCycleStyle: () {
                      final styles = VisualizerStyle.values;
                      final current =
                          ref.read(visualizerStyleOverrideProvider) ?? style;
                      ref.read(visualizerStyleOverrideProvider.notifier).set(
                            styles[(current.index + 1) % styles.length],
                          );
                      _armHide();
                    },
                    onToggleSource: () {
                      final on = ref.read(vuSplitProvider);
                      ref.read(vuSplitProvider.notifier).set(!on);
                      _armHide();
                    },
                    vuSplit: ref.watch(vuSplitProvider),
                    // LED VU only: discrete segments ↔ solid gradient.
                    ledDiscrete: ref.watch(ledVuDiscreteProvider),
                    onToggleDiscrete: () {
                      final on = ref.read(ledVuDiscreteProvider);
                      ref.read(ledVuDiscreteProvider.notifier).set(!on);
                      _armHide();
                    },
                    onPrev: () =>
                        ref.read(audioHandlerProvider).skipToPrevious(),
                    onNext: () => ref.read(audioHandlerProvider).skipToNext(),
                    onPlayPause: () {
                      final h = ref.read(audioHandlerProvider);
                      (audio?.isPlaying ?? false) ? h.pause() : h.play();
                    },
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

/// Heavy-blur album wash behind the meters, with a theme scrim so the
/// color reads as an ambient field, not a busy photo. Mirrors the
/// immersive screen's background treatment.
class _ArtWash extends StatelessWidget {
  const _ArtWash({required this.track, required this.theme});

  final Track track;
  final HanamimiTheme theme;

  ImageProvider? _art() {
    final artPath = track.albumArtPath;
    if (artPath == null) return null;
    return ResizeImage(FileImage(File(artPath)), width: 200);
  }

  @override
  Widget build(BuildContext context) {
    final image = _art();
    // RepaintBoundary keeps the big blur out of the 60 fps meter frames.
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        child: KeyedSubtree(
          key: ValueKey(track.albumArtPath ?? 'no-art'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: theme.background),
              if (image != null)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                  child: Image(image: image, fit: BoxFit.cover),
                ),
              // A little darker than the immersive wash — the meters sit
              // on top and need the contrast.
              Container(color: theme.background.withValues(alpha: 0.62)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.theme,
    required this.audio,
    required this.style,
    required this.isVu,
    required this.vuSplit,
    required this.ledDiscrete,
    required this.onClose,
    required this.onCycleStyle,
    required this.onToggleSource,
    required this.onToggleDiscrete,
    required this.onPrev,
    required this.onNext,
    required this.onPlayPause,
  });

  final HanamimiTheme theme;
  final dynamic audio;
  final VisualizerStyle style;
  final bool isVu;
  final bool vuSplit;
  final bool ledDiscrete;
  final VoidCallback onClose;
  final VoidCallback onCycleStyle;
  final VoidCallback onToggleSource;
  final VoidCallback onToggleDiscrete;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPlayPause;

  Widget _pill(IconData icon, String label, Color tint, VoidCallback onTap) =>
      TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: tint),
        label: Text(
          label,
          style: TextStyle(fontFamily: 'Nunito', fontSize: 12, color: tint),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tint = theme.textPrimary;
    final isLed = style == VisualizerStyle.ledVu;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Top bar dodges the notch (SafeArea). Pinned to the TOP —
        // without the Positioned it's a StackFit.expand child stretched
        // to full height, so the Row centres vertically and collides
        // with the meters (user-reported, worst in portrait). The
        // centred content below deliberately keeps NO horizontal safe
        // area, so a lone left-side notch in landscape can't shove the
        // transport off the title.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Space.s3, vertical: Space.s2),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Switch visualization',
                  icon: Icon(Icons.equalizer_rounded, color: tint),
                  onPressed: onCycleStyle,
                ),
                // VU meters: the needle source — loudness (L/R) vs.
                // bass/treble.
                if (isVu)
                  _pill(Icons.tune_rounded,
                      vuSplit ? 'Bass / treble' : 'Loudness', tint,
                      onToggleSource),
                // LED VU: the look — discrete segments vs. solid bar.
                if (isLed)
                  _pill(
                      ledDiscrete
                          ? Icons.view_week_rounded
                          : Icons.gradient_rounded,
                      ledDiscrete ? 'Segments' : 'Solid',
                      tint,
                      onToggleDiscrete),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  icon: Icon(Icons.close_rounded, color: tint),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          ),
        ),
        // Transport — screen-centered so it sits directly under the
        // (also screen-centered) title.
        Align(
          alignment: const Alignment(0, 0.86),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                iconSize: 34,
                icon: Icon(Icons.skip_previous_rounded, color: tint),
                onPressed: onPrev,
              ),
              const SizedBox(width: Space.s4),
              IconButton(
                iconSize: 46,
                icon: Icon(
                  (audio?.isPlaying ?? false)
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: theme.primary,
                ),
                onPressed: onPlayPause,
              ),
              const SizedBox(width: Space.s4),
              IconButton(
                iconSize: 34,
                icon: Icon(Icons.skip_next_rounded, color: tint),
                onPressed: onNext,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
