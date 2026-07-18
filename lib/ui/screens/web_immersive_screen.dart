import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/track.dart';
import '../../providers/audio_provider.dart';
import '../../providers/buddy_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/now_playing/playback_controls.dart';
import '../components/now_playing/seek_bar_widget.dart';
import '../components/now_playing/visualizer_widget.dart';
import '../components/now_playing/wipe_reveal.dart';
import '../components/shared/particle_overlay.dart';
import '../modals/lyrics_sheet.dart';
import '../modals/queue_sheet.dart';
import '../modals/sleep_timer_modal.dart';
import 'blackout_screen.dart';

/// The wide-shell Now Playing — a straight port of the plus desktop
/// immersive screen (M31): blurred album art fills the pane, big art +
/// seek + controls + visualizer breathe on the left, and oversized
/// synced lyrics scroll on the right — the spicy-lyrics look. On web
/// it's not a route; it IS the pane beside the sidebar.
class WebImmersiveNowPlaying extends ConsumerWidget {
  const WebImmersiveNowPlaying({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final audio = ref.watch(audioStateProvider).value;
    final track = audio?.currentTrack;

    if (track == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_note_outlined, size: 48, color: theme.textMuted),
            const SizedBox(height: Space.s3),
            Text('Nothing playing yet', style: AppText.body(theme)),
            const SizedBox(height: Space.s1),
            Text('Pick a song from your library',
                style: AppText.caption(theme)),
          ],
        ),
      );
    }

    // Crossfade: the incoming track and the fade progress, so the art,
    // title, seek and background wipe across in step with the audio.
    // Per-frame progress rides the engine's crossfadeT notifier so only
    // the wrapped subtrees rebuild per tick, never this whole pane.
    final incoming = audio?.crossfadeIncomingTrack;
    final xfT = ref.watch(audioHandlerProvider).engine.crossfadeT;

    return Stack(
      fit: StackFit.expand,
      children: [
        incoming != null
            ? ValueListenableBuilder<double>(
                valueListenable: xfT,
                builder: (_, t, __) => _ImmersiveBackground(
                  track: track,
                  theme: theme,
                  incoming: incoming,
                  progress: t,
                ),
              )
            : _ImmersiveBackground(track: track, theme: theme),
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
                      child: _LeftColumn(track: track, theme: theme),
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
      ],
    );
  }
}

/// Heavy-blur art wash. Softer overlay than the phone Now Playing so
/// the cover's color really owns the room (spicy-lyrics energy). During
/// a crossfade the incoming wash wipes in over the outgoing in step
/// with the audio; otherwise a track change cross-fades softly.
class _ImmersiveBackground extends StatelessWidget {
  const _ImmersiveBackground({
    required this.track,
    required this.theme,
    this.incoming,
    this.progress = 0,
  });

  final Track track;
  final HanamimiTheme theme;
  final Track? incoming;
  final double progress;

  ImageProvider? _art(Track t) {
    final artUrl = t.albumArtPath; // web: blob URL from the embedded tag
    if (artUrl == null) return null;
    // Small decode — it's blurred to a wash anyway.
    return ResizeImage(NetworkImage(artUrl), width: 200);
  }

  Widget _wash(Track t) {
    final image = _art(t);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (image != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: Image(image: image, fit: BoxFit.cover),
          ),
        Container(color: theme.background.withValues(alpha: 0.72)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary keeps the big blur out of the 60 fps
    // visualizer/lyrics frames.
    if (incoming != null && progress > 0) {
      final e = Curves.easeInOut.transform(progress.clamp(0.0, 1.0));
      return RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            _wash(track),
            WipeReveal(progress: e, child: _wash(incoming!)),
          ],
        ),
      );
    }
    // Cross-fade on track change — a hard swap jumps between colors.
    final key = track.albumArtPath ?? 'no-art';
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        switchInCurve: Curves.easeOut,
        child: KeyedSubtree(key: ValueKey(key), child: _wash(track)),
      ),
    );
  }
}

class _LeftColumn extends ConsumerWidget {
  const _LeftColumn({required this.track, required this.theme});

  final Track track;
  final HanamimiTheme theme;

  Widget _art(Track t, double size) {
    final artUrl = t.albumArtPath;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
        image: artUrl != null
            ? DecorationImage(
                image: NetworkImage(artUrl), fit: BoxFit.cover)
            : null,
        color: theme.surface,
      ),
      child: artUrl == null
          ? Icon(Icons.music_note, size: 64, color: theme.textMuted)
          : null,
    );
  }

  Widget _titleArtist(Track t, WidgetRef ref) {
    // Liked state lives in the library, not the audio snapshot.
    final libraryTrack = ref.watch(libraryTrackProvider(t));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                t.title,
                style: AppText.npSongTitle(theme).copyWith(fontSize: 24),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: Space.s2),
            InkResponse(
              radius: 18,
              onTap: () => ref
                  .read(webLibraryProvider.notifier)
                  .toggleLiked(libraryTrack),
              child: Icon(
                libraryTrack.liked
                    ? Icons.favorite
                    : Icons.favorite_border,
                size: 20,
                color:
                    libraryTrack.liked ? theme.accent : theme.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s1),
        Text(
          t.artist,
          style: AppText.npArtist(theme),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioStateProvider).value;
    final basePosition = ref.watch(positionProvider).value ?? Duration.zero;
    final baseDuration = audio?.duration ?? Duration.zero;
    final engine = ref.read(audioHandlerProvider).engine;

    // Crossfade: wipe art + title from the right, roll the seek bar to
    // where the incoming song already is — in step with the audio.
    final incoming = audio?.crossfadeIncomingTrack;

    Widget content(double? xf) {
      final crossfading = xf != null && incoming != null;
      final xfE = crossfading ? Curves.easeInOut.transform(xf) : 0.0;
      var position = basePosition;
      var duration = baseDuration;
      if (crossfading) {
        final e = xf * xf * (3 - 2 * xf);
        final inPos = engine.crossfadeIncomingPosition.inMilliseconds;
        final inDur = incoming.duration.inMilliseconds;
        int mix(int a, int b) => (a * (1 - e) + b * e).round();
        position =
            Duration(milliseconds: mix(position.inMilliseconds, inPos));
        duration =
            Duration(milliseconds: mix(duration.inMilliseconds, inDur));
      }

      return LayoutBuilder(builder: (context, constraints) {
        final artSize = (constraints.maxHeight * 0.42).clamp(160.0, 380.0);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            crossfading
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      _art(track, artSize),
                      WipeReveal(
                          progress: xfE, child: _art(incoming, artSize)),
                    ],
                  )
                : _art(track, artSize),
            const SizedBox(height: Space.s6),
            crossfading
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      WipeReveal(
                          progress: xfE,
                          invert: true,
                          child: _titleArtist(track, ref)),
                      WipeReveal(
                          progress: xfE,
                          child: _titleArtist(incoming, ref)),
                    ],
                  )
                : _titleArtist(track, ref),
            const SizedBox(height: Space.s6),
            SeekBarWidget(
              position: position,
              duration: duration,
              theme: theme,
              onSeek: crossfading ? (_) {} : engine.seek,
            ),
            const SizedBox(height: Space.s4),
            PlaybackControls(
              onSleepTimer: () => showSleepTimerModal(context),
              onQueue: () => showQueueSheet(context),
              onBlackout: () =>
                  Navigator.of(context).push(BlackoutScreen.route()),
            ),
            const SizedBox(height: Space.s6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context)
                  .push(BlackoutScreen.route(light: true)),
              child: const VisualizerWidget(height: 64),
            ),
          ],
        );
      });
    }

    if (incoming == null) return content(null);
    return ValueListenableBuilder<double>(
      valueListenable: engine.crossfadeT,
      builder: (_, t, __) => content(t),
    );
  }
}
