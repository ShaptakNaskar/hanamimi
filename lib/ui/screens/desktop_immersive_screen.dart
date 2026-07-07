import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/audio_provider.dart';
import '../../providers/buddy_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/now_playing/playback_controls.dart';
import '../components/now_playing/seek_bar_widget.dart';
import '../components/now_playing/visualizer_widget.dart';
import '../components/shared/particle_overlay.dart';
import '../modals/lyrics_sheet.dart';
import '../modals/queue_sheet.dart';
import '../modals/sleep_timer_modal.dart';

/// Full-window desktop Now Playing (M31, the user's "image 3"):
/// blurred album art fills the window, big art + seek + controls +
/// visualizer breathe on the left, and oversized synced lyrics scroll
/// on the right — the spicy-lyrics look, in Hanamimi's own voice.
/// Esc or the collapse button returns to the three-pane shell.
class DesktopImmersiveScreen extends ConsumerWidget {
  const DesktopImmersiveScreen({super.key});

  static Route<void> route() => PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, __, ___) => const DesktopImmersiveScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final audio = ref.watch(audioStateProvider).value;
    final track = audio?.currentTrack;

    if (track == null) {
      // Track cleared while immersive — nothing to show, fall back.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: theme.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _ImmersiveBackground(track: track, theme: theme),
          ParticleOverlay(
            theme: theme,
            fireflies: ref.watch(buddyEnabledProvider('fireflies')),
          ),
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: Space.s6),
                        child: _LeftColumn(
                            track: track, theme: theme, ref: ref),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.only(right: Space.s6),
                    // The SAME karaoke machinery as the phone sheet —
                    // word-synced fill, interludes, source picker and
                    // offset (auto-hiding, spicy-lyrics style), scaled
                    // up with distance-blurred neighbor lines.
                    child: LyricsView(
                      track: track,
                      sheetChrome: false,
                      autoHideHeader: true,
                      textScale: 1.5,
                      blurLines: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Collapse, top-right — mirrors the expand affordance.
          Positioned(
            top: Space.s3,
            right: Space.s3,
            child: IconButton(
              tooltip: 'Back to library (Esc)',
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.close_fullscreen_rounded,
                  size: 20, color: theme.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Heavy-blur art wash. Softer overlay than the phone Now Playing so
/// the cover's color really owns the room (spicy-lyrics energy).
class _ImmersiveBackground extends StatelessWidget {
  const _ImmersiveBackground({required this.track, required this.theme});

  final dynamic track;
  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context) {
    final artPath = track.albumArtPath as String?;
    final artUrl = track.artUrl as String?;
    ImageProvider? image;
    if (artPath != null) {
      image = FileImage(File(artPath));
    } else if (artUrl != null) {
      image = NetworkImage(artUrl);
    }
    // Small decode — it's blurred to a wash anyway.
    if (image != null) image = ResizeImage(image, width: 200);
    // Cross-fade on track change, like the shell's BackdropWash — a
    // hard swap here made immersive track changes jump between colors
    // while the three-pane view glided (user-reported). RepaintBoundary
    // keeps the big blur out of the 60 fps visualizer/lyrics frames.
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        switchInCurve: Curves.easeOut,
        child: Stack(
          key: ValueKey(artPath ?? artUrl ?? 'no-art'),
          fit: StackFit.expand,
          children: [
            if (image != null)
              ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: Image(image: image, fit: BoxFit.cover),
              ),
            Container(color: theme.background.withValues(alpha: 0.72)),
          ],
        ),
      ),
    );
  }
}

class _LeftColumn extends ConsumerStatefulWidget {
  const _LeftColumn(
      {required this.track, required this.theme, required this.ref});

  final dynamic track;
  final HanamimiTheme theme;
  final WidgetRef ref;

  @override
  ConsumerState<_LeftColumn> createState() => _LeftColumnState();
}

class _LeftColumnState extends ConsumerState<_LeftColumn> {
  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final track = widget.track;
    final audio = ref.watch(audioStateProvider).value;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration = audio?.duration ?? Duration.zero;
    final engine = ref.read(audioHandlerProvider).engine;

    final artPath = track.albumArtPath as String?;
    final artUrl = track.artUrl as String?;

    return LayoutBuilder(builder: (context, constraints) {
      final artSize = (constraints.maxHeight * 0.42).clamp(160.0, 380.0);
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: artSize,
            height: artSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.lg),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
              image: artPath != null
                  ? DecorationImage(
                      image: FileImage(File(artPath)), fit: BoxFit.cover)
                  : artUrl != null
                      ? DecorationImage(
                          image: NetworkImage(artUrl), fit: BoxFit.cover)
                      : null,
              color: theme.surface,
            ),
            child: artPath == null && artUrl == null
                ? Icon(Icons.music_note, size: 64, color: theme.textMuted)
                : null,
          ),
          const SizedBox(height: Space.s6),
          Text(
            track.title as String,
            style: AppText.npSongTitle(theme).copyWith(fontSize: 24),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.s1),
          Text(
            track.artist as String,
            style: AppText.npArtist(theme),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.s6),
          SeekBarWidget(
            position: position,
            duration: duration,
            theme: theme,
            onSeek: engine.seek,
          ),
          const SizedBox(height: Space.s4),
          PlaybackControls(
            onSleepTimer: () => showSleepTimerModal(context),
            onQueue: () => showQueueSheet(context),
          ),
          const SizedBox(height: Space.s6),
          const VisualizerWidget(height: 64),
        ],
      );
    });
  }
}

