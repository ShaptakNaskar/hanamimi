import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/track.dart';
import '../../providers/audio_provider.dart';
import '../../providers/cat_mode_provider.dart';
import '../../providers/companion_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/mascot_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/visualizer_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/mascot/hanamimi_widget.dart';
import '../components/mascot/mascot_painter.dart';
import '../components/now_playing/album_art_widget.dart';
import '../components/now_playing/playback_controls.dart';
import '../components/now_playing/seek_bar_widget.dart';
import '../components/now_playing/visualizer_widget.dart';
import '../components/shared/particle_overlay.dart';
import '../modals/lyrics_sheet.dart';
import '../modals/queue_sheet.dart';
import '../modals/sleep_timer_modal.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final audio = ref.watch(audioStateProvider).value;
    final track = audio?.currentTrack;

    if (track == null) {
      return SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.music_note_outlined,
                  size: 48, color: theme.textMuted),
              const SizedBox(height: Space.s3),
              Text('Nothing playing yet', style: AppText.body(theme)),
              const SizedBox(height: Space.s1),
              Text('Pick a song from your library',
                  style: AppText.caption(theme)),
            ],
          ),
        ),
      );
    }

    // Liked state lives in the library, not the audio snapshot.
    final libraryTrack = ref
            .watch(libraryProvider)
            .value
            ?.firstWhere((t) => t.id == track.id, orElse: () => track) ??
        track;

    return Stack(
      fit: StackFit.expand,
      children: [
        _BlurredArtBackground(track: track, theme: theme),
        ParticleOverlay(theme: theme),
        SafeArea(
          bottom: false,
          child: LayoutBuilder(builder: (context, constraints) {
            final artSize = constraints.maxWidth * 0.72;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s4),
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  AlbumArtWidget(
                    track: track,
                    theme: theme,
                    isPlaying: audio?.isPlaying ?? false,
                    size: artSize,
                  ),
                  const Spacer(flex: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(track.title,
                                style: AppText.npSongTitle(theme),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text(track.artist,
                                style: AppText.npArtist(theme),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.s3),
                      if (!libraryTrack.isLocal)
                        _DownloadButton(track: libraryTrack, theme: theme),
                      _HeartButton(track: libraryTrack, theme: theme),
                    ],
                  ),
                  const SizedBox(height: Space.s4),
                  _SeekBarSection(theme: theme),
                  const SizedBox(height: Space.s6),
                  PlaybackControls(
                    onSleepTimer: () => showSleepTimerModal(context),
                    onQueue: () => showQueueSheet(context),
                  ),
                  const SizedBox(height: Space.s4),
                  const VisualizerWidget(height: 56),
                  const Spacer(flex: 1),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => showLyricsSheet(context, track),
                    onVerticalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) < -200) {
                        showLyricsSheet(context, track);
                      }
                    },
                    child: Column(
                      children: [
                        Icon(Icons.keyboard_arrow_up,
                            color: theme.textMuted, size: 20),
                        Text('Lyrics', style: AppText.caption(theme)),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.s2),
                  HanamimiMascot(
                    state: ref.watch(mascotStateProvider),
                    amplitude: ref.watch(amplitudeProvider),
                    accessory: ref.watch(catModeProvider).enabled
                        ? Accessory.catEars
                        : ref.watch(activeAccessoryProvider),
                    size: 90,
                    onTap: () {
                      final unlocked = ref
                          .read(catModeProvider.notifier)
                          .registerMascotTap();
                      if (unlocked) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(Radii.md)),
                          content: const Text(
                              'Meow?! Cat Mode unlocked 🐱',
                              style: TextStyle(fontFamily: 'Nunito')),
                        ));
                      }
                    },
                  ),
                  const SizedBox(height: Space.s2),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

/// Album art blurred to a wash, overlaid with the theme background at
/// 85% opacity (DESIGN.md §10.2).
class _BlurredArtBackground extends StatelessWidget {
  const _BlurredArtBackground({required this.track, required this.theme});

  final Track track;
  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context) {
    final art = track.albumArtPath;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (art != null && File(art).existsSync())
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
            // Blurring full-resolution art costs enormous raster time and
            // memory; at sigma 60 a small decode looks identical.
            child: Image.file(File(art),
                fit: BoxFit.cover, cacheWidth: 200, gaplessPlayback: true),
          )
        else
          ColoredBox(color: theme.primary.withValues(alpha: 0.4)),
        ColoredBox(color: theme.background.withValues(alpha: 0.85)),
      ],
    );
  }
}

class _SeekBarSection extends ConsumerWidget {
  const _SeekBarSection({required this.theme});

  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration =
        ref.watch(audioStateProvider).value?.duration ?? Duration.zero;

    return SeekBarWidget(
      position: position,
      duration: duration,
      theme: theme,
      onSeek: (d) => ref.read(audioHandlerProvider).seek(d),
    );
  }
}

/// Download-for-offline button, shown only for online tracks. Spins
/// while fetching, becomes a filled check once the file is saved.
class _DownloadButton extends ConsumerStatefulWidget {
  const _DownloadButton({required this.track, required this.theme});

  final Track track;
  final HanamimiTheme theme;

  @override
  ConsumerState<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends ConsumerState<_DownloadButton> {
  bool _busy = false;

  Future<void> _download() async {
    if (_busy || widget.track.isPlayableOffline) return;
    setState(() => _busy = true);
    final ok =
        await ref.read(libraryProvider.notifier).downloadTrack(widget.track);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      content: Text(ok ? 'Saved for offline' : "Couldn't download",
          style: const TextStyle(fontFamily: 'Nunito')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final downloaded = widget.track.isPlayableOffline;
    return InkResponse(
      radius: Sizes.minTouchTarget / 2,
      onTap: downloaded ? null : _download,
      child: SizedBox(
        width: Sizes.minTouchTarget,
        height: Sizes.minTouchTarget,
        child: Center(
          child: _busy
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: widget.theme.primary),
                )
              : Icon(
                  downloaded
                      ? Icons.download_done
                      : Icons.download_for_offline_outlined,
                  size: 24,
                  color: downloaded
                      ? widget.theme.primary
                      : widget.theme.textMuted,
                ),
        ),
      ),
    );
  }
}

/// Heart with the beat-once pulse (DESIGN.md §7). Particle burst lands
/// with the polish milestone.
class _HeartButton extends ConsumerStatefulWidget {
  const _HeartButton({required this.track, required this.theme});

  final Track track;
  final HanamimiTheme theme;

  @override
  ConsumerState<_HeartButton> createState() => _HeartButtonState();
}

class _HeartButtonState extends ConsumerState<_HeartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: Anim.heartPulse,
  );

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final liked = widget.track.liked;
    return InkResponse(
      radius: Sizes.minTouchTarget / 2,
      onTap: () {
        if (!liked) _beat.forward(from: 0);
        ref.read(libraryProvider.notifier).toggleLiked(widget.track);
      },
      child: SizedBox(
        width: Sizes.minTouchTarget,
        height: Sizes.minTouchTarget,
        child: AnimatedBuilder(
          animation: _beat,
          builder: (context, child) => CustomPaint(
            painter: _HeartBurstPainter(
              progress: _beat.value,
              color: widget.theme.accent,
            ),
            child: child,
          ),
          child: ScaleTransition(
            scale: TweenSequence([
              TweenSequenceItem(
                  tween: Tween(begin: 1.0, end: 1.3), weight: 1),
              TweenSequenceItem(
                  tween: Tween(begin: 1.3, end: 1.0), weight: 1),
            ]).animate(
                CurvedAnimation(parent: _beat, curve: Curves.easeOutBack)),
            child: Icon(
              liked ? Icons.favorite : Icons.favorite_border,
              size: 24,
              color: liked ? widget.theme.accent : widget.theme.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// 6 tiny accent dots radiating from the heart on like (DESIGN.md §13).
class _HeartBurstPainter extends CustomPainter {
  _HeartBurstPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0 || progress == 1) return;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color.withValues(alpha: 1 - progress);
    for (var i = 0; i < 6; i++) {
      final angle = i * math.pi / 3 + 0.3;
      final r = 12 + progress * 14;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * r,
        2 * (1 - progress * 0.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_HeartBurstPainter old) =>
      old.progress != progress;
}
