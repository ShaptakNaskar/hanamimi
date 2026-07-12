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
import '../../date/date_room.dart';
import '../../providers/desktop_shell_provider.dart';
import '../../providers/download_provider.dart';
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
import '../modals/download_quality_sheet.dart';
import 'blackout_screen.dart';
import '../modals/lyrics_sheet.dart';
import '../modals/playlist_picker_sheet.dart';
import '../modals/queue_sheet.dart';
import '../modals/sleep_timer_modal.dart';

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key, this.panel = false});

  /// True when living as the desktop side panel: the blurred-art wash
  /// dissolves into the app background at its left edge instead of
  /// cutting a hard, glowing seam against the middle pane.
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
    // incoming one, dissolve the art and title/artist across in step —
    // otherwise the screen keeps showing the old song over the new.
    final playing = audio?.isPlaying ?? false;
    final xf = audio?.crossfadeProgress;
    final incoming = audio?.crossfadeIncomingTrack;
    final crossfading = xf != null && incoming != null;
    final xfE = crossfading ? Curves.easeInOut.transform(xf) : 0.0;

    Widget titleArtist(Track t, {Color? titleColor}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.title,
                style: AppText.npSongTitle(theme).copyWith(color: titleColor),
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
        // As the desktop side panel the shell paints ONE art glow and
        // ONE particle field under/over all three panes — private
        // copies here would confine them to the panel and make the
        // pane boundary read as a different world.
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
          // pause) brings it back. Desktop panel included (user ask) —
          // its Listener only spans the panel, so browsing the library
          // doesn't reset the fade; the panel calms down beside you.
          child: UndressLayer(
            enabled: ref.watch(meltAwayProvider) &&
                (audio?.isPlaying ?? false),
            child: LayoutBuilder(
            builder: (context, constraints) {
              // Freeform windows (desktop) and short screens: the art
              // yields to the height budget, the content column never
              // stretches past phone width, and below ~620px the mascot
              // strip bows out entirely (M31 — a clipped mascot or a
              // floating half-hamster looks like a glitch, not a pet).
              final artSize = math.min(
                constraints.maxWidth * 0.72,
                constraints.maxHeight * 0.38,
              );
              final showMascotStrip = constraints.maxHeight >= 620;
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
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
                                  // Incoming art writes over the
                                  // outgoing from the right, in step with
                                  // the audio ramp.
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
                                // Overwrite the text like the art: the
                                // outgoing stays put while the incoming
                                // wipes over it from the right.
                                child: crossfading
                                    ? Stack(
                                        fit: StackFit.passthrough,
                                        children: [
                                          // Outgoing erased from the
                                          // right as the incoming writes
                                          // in — no overlapping strings.
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
                              if (!libraryTrack.isLocal)
                                _DownloadButton(
                                  track: libraryTrack,
                                  theme: theme,
                                ),
                              _HeartButton(
                                  track: libraryTrack, theme: theme),
                            ],
                          ),
                        ),
                        const Undressable(level: 2, child: _NerdBar()),
                        const SizedBox(height: Space.s4),
                        const _DateRoomBanner(),
                        Undressable(
                            level: 1,
                            child: _SeekBarSection(theme: theme)),
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
                            onBlackout: () => Navigator.of(context)
                                .push(BlackoutScreen.route()),
                          ),
                        ),
                        const SizedBox(height: Space.s4),
                        const VisualizerWidget(height: 56),
                        const Spacer(flex: 1),
                        Undressable(
                          level: 1,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            // Desktop panel: lyrics live in the middle
                            // pane (Spotify-style), not a bottom sheet
                            // rising through the middle of a big window.
                            onTap:
                                () =>
                                    panel
                                        ? ref
                                            .read(
                                              desktopLyricsOpenProvider
                                                  .notifier,
                                            )
                                            .toggle()
                                        : showLyricsSheet(context, track),
                            onVerticalDragEnd: (d) {
                              if ((d.primaryVelocity ?? 0) < -200) {
                                if (panel) {
                                  ref
                                      .read(
                                          desktopLyricsOpenProvider.notifier)
                                      .toggle();
                                } else {
                                  showLyricsSheet(context, track);
                                }
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
                        // instead of overflowing the column (10px overflow on
                        // 1080x2400 with taller system insets). flex 6 beats
                        // the Spacers (2+2+1) so with any reasonable free
                        // space the slot exceeds 90px and the mascot renders
                        // full size — FittedBox.scaleDown never enlarges.
                        if (showMascotStrip)
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
                                          amplitude: ref.watch(
                                            amplitudeProvider,
                                          ),
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
                                                    .read(
                                                      catModeProvider.notifier,
                                                    )
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
                  ),
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

/// Nerd mode (M28+): a subtle line of codec / bitrate / sample-rate /
/// container chips plus the live output route. Renders nothing when the
/// toggle is off or the info hasn't resolved yet.
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
      if (info.container != null) info.container!,
    ];
    final output = info.output;
    final outLabel =
        output == null
            ? null
            : '${_routeGlyph(output.route)} ${output.name ?? output.route}';

    final style = AppText.caption(
      theme,
    ).copyWith(fontSize: 11, color: theme.textMuted, letterSpacing: 0.2);

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
            if (outLabel != null) Text(outLabel, style: style, maxLines: 1),
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

/// Album art blurred to a wash, overlaid with the theme background at
/// 85% opacity (DESIGN.md §10.2). During a crossfade the [incoming]
/// wash rises over the outgoing one at [progress] so the ambient glow
/// dissolves in lockstep with the foreground art — fully seamless.
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

class _SeekBarSection extends ConsumerWidget {
  const _SeekBarSection({required this.theme});

  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioStateProvider).value;
    var position = ref.watch(positionProvider).value ?? Duration.zero;
    var duration = audio?.duration ?? Duration.zero;
    var buffered = ref.watch(bufferedProvider).value ?? Duration.zero;
    final room = ref.watch(dateRoomProvider);

    // Crossfade: roll the bar from the outgoing playhead to where the
    // incoming song already is (it's been playing through the fade), so
    // it glides instead of snapping to 0:00 at the handoff.
    final xf = audio?.crossfadeProgress;
    final incoming = audio?.crossfadeIncomingTrack;
    final crossfading = xf != null && incoming != null;
    if (crossfading) {
      final e = Curves.easeInOut.transform(xf);
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
      // Date mode: the partner's position rides under the bar.
      partnerPosition: room.inRoom && room.shared && room.partnerOnline
          ? Duration(milliseconds: room.partnerPositionMs)
          : null,
      theme: theme,
      // A seek mid-transition would map to the blended duration — ignore
      // it; the fade is only a few seconds.
      onSeek: crossfading
          ? (_) {}
          : (d) => ref.read(audioHandlerProvider).seek(d),
    );
  }
}

/// Download-for-offline button, shown only for online tracks. Opens
/// the quality picker (unless a choice is remembered), hands the job
/// to the download manager, spins while it's queued/running, becomes a
/// filled check once the file is saved.
class _DownloadButton extends ConsumerWidget {
  const _DownloadButton({required this.track, required this.theme});

  final Track track;
  final HanamimiTheme theme;

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final quality = await resolveDownloadQuality(context, ref);
    if (quality == null) return; // dismissed the picker
    ref.read(downloadManagerProvider.notifier).enqueue(track, quality);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          content: const Text(
            'Added to Downloads',
            style: TextStyle(fontFamily: 'Nunito'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloaded = track.isPlayableOffline;
    final busy = ref
        .watch(downloadManagerProvider)
        .any(
          (t) =>
              t.track.id == track.id &&
              (t.status == DownloadStatus.queued ||
                  t.status == DownloadStatus.downloading),
        );
    return InkResponse(
      radius: Sizes.minTouchTarget / 2,
      onTap: downloaded || busy ? null : () => _download(context, ref),
      child: SizedBox(
        width: Sizes.minTouchTarget,
        height: Sizes.minTouchTarget,
        child: Center(
          child:
              busy
                  ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.primary,
                    ),
                  )
                  : Icon(
                    downloaded
                        ? Icons.download_done
                        : Icons.download_for_offline_outlined,
                    size: 24,
                    color: downloaded ? theme.primary : theme.textMuted,
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

/// Date mode: a slim tap-to-rejoin pill shown only when we've drifted
/// solo from the DJ, so lockstep is one tap away without opening the
/// You-tab sheet. Silent the rest of the time (the sheet carries the
/// full DJ / follower / take-over detail).
class _DateRoomBanner extends ConsumerWidget {
  const _DateRoomBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(dateRoomProvider);
    if (!room.inRoom || !room.solo) return const SizedBox.shrink();
    final theme = ref.watch(currentThemeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s3),
      child: Center(
        child: Material(
          color: theme.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(Radii.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.md),
            onTap: () => ref.read(dateRoomProvider.notifier).rejoin(),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.s3, vertical: Space.s2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sync_rounded, size: 15, color: theme.primary),
                  const SizedBox(width: Space.s2),
                  Text('Listening solo — tap to rejoin the DJ',
                      style: AppText.caption(theme)
                          .copyWith(color: theme.primary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
