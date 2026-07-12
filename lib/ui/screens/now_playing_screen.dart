import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/track.dart';
import '../../providers/audio_provider.dart';
import '../../providers/buddy_provider.dart';
import '../../providers/cat_mode_provider.dart';
import '../../providers/companion_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/mascot_provider.dart';
import '../../providers/nerd_provider.dart';
import '../../providers/reco_provider.dart';
import '../../providers/settings_provider.dart';
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
import '../components/now_playing/undress.dart';
import '../components/now_playing/visualizer_widget.dart';
import '../components/now_playing/wipe_reveal.dart';
import '../components/shared/particle_overlay.dart';
import 'blackout_screen.dart';
import '../modals/lyrics_sheet.dart';
import '../modals/playlist_picker_sheet.dart';
import '../modals/queue_sheet.dart';
import '../modals/sleep_timer_modal.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key, this.panel = false});

  /// True when living as the desktop/tablet side panel: the shell paints
  /// ONE art-glow wash + particle field under all three panes, so the
  /// panel skips its own copies (they'd confine the glow to 400px and
  /// double the particles).
  final bool panel;

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
              Icon(Icons.music_note_outlined, size: 48, color: theme.textMuted),
              const SizedBox(height: Space.s3),
              Text('Nothing playing yet', style: AppText.body(theme)),
              const SizedBox(height: Space.s1),
              Text(
                'Pick a song from your library',
                style: AppText.caption(theme),
              ),
            ],
          ),
        ),
      );
    }

    // Liked state lives in the library, not the audio snapshot.
    final libraryTrack =
        ref
            .watch(libraryProvider)
            .value
            ?.firstWhere((t) => t.id == track.id, orElse: () => track) ??
        track;

    // Crossfade: while the audio ramps from the outgoing track to the
    // incoming one, wipe the art and title/artist across (right→left) in
    // step — otherwise the screen keeps showing the old song over the new.
    final playing = audio?.isPlaying ?? false;
    final xf = audio?.crossfadeProgress;
    final incoming = audio?.crossfadeIncomingTrack;
    final crossfading = xf != null && incoming != null;
    final xfE = crossfading ? Curves.easeInOut.transform(xf) : 0.0;

    Widget titleArtist(Track t) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.title,
                style: AppText.npSongTitle(theme),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(t.artist,
                style: AppText.npArtist(theme),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (!panel)
          _BlurredArtBackground(
            track: track,
            theme: theme,
            incoming: crossfading ? incoming : null,
            progress: xfE,
          ),
        if (!panel)
          ParticleOverlay(
            theme: theme,
            fireflies: ref.watch(buddyEnabledProvider('fireflies')),
          ),
        SafeArea(
          bottom: false,
          // 3.0 #6 "Melt away": idle listening melts the chrome away
          // until it's art + visualizer + mascot. Any touch (or a
          // pause) brings it back.
          child: UndressLayer(
            enabled: ref.watch(meltAwayProvider) && (audio?.isPlaying ?? false),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final artSize = constraints.maxWidth * 0.72;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                  child: Column(
                    children: [
                      const Spacer(flex: 2),
                      crossfading
                          ? Stack(
                              alignment: Alignment.center,
                              children: [
                                AlbumArtWidget(
                                  track: track,
                                  theme: theme,
                                  isPlaying: playing,
                                  size: artSize,
                                ),
                                // Incoming art writes over the outgoing
                                // from the right, in step with the ramp.
                                WipeReveal(
                                  progress: xfE,
                                  child: AlbumArtWidget(
                                    track: incoming,
                                    theme: theme,
                                    isPlaying: playing,
                                    size: artSize,
                                  ),
                                ),
                              ],
                            )
                          : AlbumArtWidget(
                              track: track,
                              theme: theme,
                              isPlaying: playing,
                              size: artSize,
                            ),
                      const Spacer(flex: 2),
                      Undressable(
                        level: 2,
                        child: Row(
                          children: [
                            Expanded(
                              // Overwrite the text like the art: outgoing
                              // erased from the right as incoming writes in.
                              child: crossfading
                                  ? Stack(
                                      fit: StackFit.passthrough,
                                      children: [
                                        WipeReveal(
                                          progress: xfE,
                                          invert: true,
                                          child: titleArtist(track),
                                        ),
                                        WipeReveal(
                                          progress: xfE,
                                          child: titleArtist(incoming),
                                        ),
                                      ],
                                    )
                                  : titleArtist(track),
                            ),
                            const SizedBox(width: Space.s3),
                            _HeartButton(track: libraryTrack, theme: theme),
                          ],
                        ),
                      ),
                      const Undressable(level: 2, child: _NerdBar()),
                      const SizedBox(height: Space.s4),
                      Undressable(
                        level: 1,
                        child: _SeekBarSection(theme: theme),
                      ),
                      const SizedBox(height: Space.s6),
                      Undressable(
                        level: 1,
                        child: PlaybackControls(
                          onSleepTimer: () => showSleepTimerModal(context),
                          onQueue: () => showQueueSheet(context),
                          onAddToPlaylist:
                              () => showPlaylistPicker(
                                context,
                                ref,
                                theme,
                                libraryTrack.id,
                              ),
                          onStartRadio: () => startRadio(ref, libraryTrack),
                          onBlackout:
                              () => Navigator.of(
                                context,
                              ).push(BlackoutScreen.route()),
                        ),
                      ),
                      const SizedBox(height: Space.s4),
                      const VisualizerWidget(height: 56),
                      const Spacer(flex: 1),
                      Undressable(
                        level: 1,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => showLyricsSheet(context, track),
                          onVerticalDragEnd: (d) {
                            if ((d.primaryVelocity ?? 0) < -200) {
                              showLyricsSheet(context, track);
                            }
                          },
                          child: Column(
                            children: [
                              Icon(
                                Icons.keyboard_arrow_up,
                                color: theme.textMuted,
                                size: 20,
                              ),
                              Text('Lyrics', style: AppText.caption(theme)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.s2),
                      // Flexible + scaleDown: on screens shorter than the
                      // design height the mascot gives up the missing pixels
                      // instead of overflowing the column. flex 6 beats the
                      // Spacers (2+2+1) so with any reasonable free space the
                      // slot exceeds 90px and the mascot renders full size —
                      // FittedBox.scaleDown never enlarges.
                      Flexible(
                        flex: 6,
                        child: SizedBox(
                          width: double.infinity,
                          child: Stack(
                            children: [
                              if (ref.watch(buddyEnabledProvider('beagle')))
                                Align(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: HanamimiMascot(
                                      state: ref.watch(mascotStateProvider),
                                      amplitude: ref.watch(amplitudeProvider),
                                      accessory:
                                          ref.watch(catModeProvider).enabled
                                              ? Accessory.catEars
                                              : ref.watch(
                                                activeAccessoryProvider,
                                              ),
                                      size: 90,
                                      onTap: () {
                                        final unlocked =
                                            ref
                                                .read(catModeProvider.notifier)
                                                .registerMascotTap();
                                        if (unlocked) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      Radii.md,
                                                    ),
                                              ),
                                              content: const Text(
                                                'Meow?! Cat Mode unlocked 🐱',
                                                style: TextStyle(
                                                  fontFamily: 'Nunito',
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.s2),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Album art blurred to a wash, overlaid with the theme background at
/// 85% opacity (DESIGN.md §10.2). During a crossfade the [incoming] wash
/// wipes in over the outgoing one at [progress] so the ambient glow
/// overwrites in lockstep with the foreground art.
class _BlurredArtBackground extends StatelessWidget {
  const _BlurredArtBackground({
    required this.track,
    required this.theme,
    this.incoming,
    this.progress = 0,
  });

  final Track track;
  final HanamimiTheme theme;
  final Track? incoming;
  final double progress;

  Widget _wash(Track t) {
    final art = t.albumArtPath;
    if (art != null && File(art).existsSync()) {
      return ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
        // Blurring full-resolution art costs enormous raster time and
        // memory; at sigma 60 a small decode looks identical.
        child: Image.file(
          File(art),
          fit: BoxFit.cover,
          cacheWidth: 200,
          gaplessPlayback: true,
        ),
      );
    }
    return ColoredBox(color: theme.primary.withValues(alpha: 0.4));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _wash(track),
        if (incoming != null && progress > 0)
          WipeReveal(progress: progress, child: _wash(incoming!)),
        ColoredBox(color: theme.background.withValues(alpha: 0.85)),
      ],
    );
  }
}

/// Nerd mode: a subtle line of codec / bitrate / sample-rate chips plus
/// the live output route. Renders nothing when the toggle is off or the
/// info hasn't resolved yet.
class _NerdBar extends ConsumerWidget {
  const _NerdBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final info = ref.watch(nerdInfoProvider).value;
    if (info == null) return const SizedBox.shrink();

    final chips = <String>[
      if (info.codec != null) info.codec!,
      if (info.bitrateKbps != null) '${info.bitrateKbps} kbps',
      if (info.sampleRateHz != null)
        '${(info.sampleRateHz! / 1000).toStringAsFixed(1)} kHz',
    ];
    final output = info.output;
    final outLabel =
        output == null
            ? null
            : '${_routeGlyph(output.route)} ${output.name ?? output.route}';

    return Padding(
      padding: const EdgeInsets.only(top: Space.s2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: Space.s2,
          runSpacing: Space.s1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _NerdChip(text: info.sourceLabel, theme: theme, accent: true),
            for (final c in chips) _NerdChip(text: c, theme: theme),
            if (outLabel != null)
              Text(
                outLabel,
                style: AppText.caption(theme).copyWith(
                  fontSize: 11,
                  color: theme.textMuted,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
              ),
          ],
        ),
      ),
    );
  }

  static String _routeGlyph(String route) => switch (route) {
    'Bluetooth' => '🎧',
    'Wired' => '🎙️',
    'USB' => '🔌',
    _ => '🔊',
  };
}

class _NerdChip extends StatelessWidget {
  const _NerdChip({
    required this.text,
    required this.theme,
    this.accent = false,
  });

  final String text;
  final HanamimiTheme theme;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ? theme.primary : theme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _SeekBarSection extends ConsumerWidget {
  const _SeekBarSection({required this.theme});

  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioStateProvider).value;
    var position = ref.watch(positionProvider).value ?? Duration.zero;
    var duration = audio?.duration ?? Duration.zero;
    var buffered = ref.watch(bufferedProvider).value ?? Duration.zero;

    // Crossfade: roll the bar from the outgoing playhead to where the
    // incoming song already is (it's been playing through the fade), so
    // it glides instead of snapping to 0:00 at the handoff.
    final xf = audio?.crossfadeProgress;
    final incoming = audio?.crossfadeIncomingTrack;
    final crossfading = xf != null && incoming != null;
    if (crossfading) {
      final e = xf * xf * (3 - 2 * xf);
      final inPos = audio!.crossfadeIncomingPositionMs;
      final inDur = incoming.duration.inMilliseconds;
      int mix(int a, int b) => (a * (1 - e) + b * e).round();
      position =
          Duration(milliseconds: mix(position.inMilliseconds, inPos));
      duration =
          Duration(milliseconds: mix(duration.inMilliseconds, inDur));
      buffered =
          Duration(milliseconds: mix(buffered.inMilliseconds, inPos));
    }

    return SeekBarWidget(
      position: position,
      duration: duration,
      buffered: buffered,
      theme: theme,
      onSeek: crossfading
          ? (_) {}
          : (d) => ref.read(audioHandlerProvider).seek(d),
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
          builder:
              (context, child) => CustomPaint(
                painter: _HeartBurstPainter(
                  progress: _beat.value,
                  color: widget.theme.accent,
                ),
                child: child,
              ),
          child: ScaleTransition(
            scale: TweenSequence([
              TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 1),
              TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 1),
            ]).animate(
              CurvedAnimation(parent: _beat, curve: Curves.easeOutBack),
            ),
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
    final paint = Paint()..color = color.withValues(alpha: 1 - progress);
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
  bool shouldRepaint(_HeartBurstPainter old) => old.progress != progress;
}
