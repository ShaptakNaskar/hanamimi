import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../library/models/track.dart';
import '../../../providers/audio_provider.dart';
import '../../../providers/overlay_mode_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../providers/visualizer_provider.dart';
import '../../../theme/hanamimi_theme.dart';
import '../../../theme/theme_tokens.dart';
import '../now_playing/seek_bar_widget.dart';
import '../now_playing/visualizer_widget.dart';

/// The compact, always-on-top mini-player shown while overlay mode is on
/// (see [overlayModeProvider]). Two views — album art, or the visualizer
/// — with transport below. The visualizer view carries the switch-style
/// and (for VU meters) the loudness↔bass/treble source toggle. The ⤢
/// button restores the full window.
class DesktopOverlayPlayer extends ConsumerStatefulWidget {
  const DesktopOverlayPlayer({super.key});

  @override
  ConsumerState<DesktopOverlayPlayer> createState() =>
      _DesktopOverlayPlayerState();
}

class _DesktopOverlayPlayerState extends ConsumerState<DesktopOverlayPlayer> {
  bool _showViz = false;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final audio = ref.watch(audioStateProvider).value;
    final track = audio?.currentTrack;
    final style = ref.watch(effectiveVisualizerStyleProvider);
    final isVu =
        style == VisualizerStyle.vuMeters || style == VisualizerStyle.ledVu;

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.s3),
          child: Column(
            children: [
              // Top bar: view toggle (left), restore full window (right).
              Row(
                children: [
                  _TopButton(
                    icon: _showViz
                        ? Icons.image_outlined
                        : Icons.graphic_eq_rounded,
                    tooltip: _showViz ? 'Album art' : 'Visualizer',
                    color: theme.textMuted,
                    onTap: () => setState(() => _showViz = !_showViz),
                  ),
                  if (_showViz) ...[
                    _TopButton(
                      icon: Icons.equalizer_rounded,
                      tooltip: 'Switch visualization',
                      color: theme.textMuted,
                      onTap: () {
                        final styles = VisualizerStyle.values;
                        final current =
                            ref.read(visualizerStyleOverrideProvider) ?? style;
                        ref
                            .read(visualizerStyleOverrideProvider.notifier)
                            .set(styles[(current.index + 1) % styles.length]);
                      },
                    ),
                    if (isVu)
                      _TopButton(
                        icon: Icons.tune_rounded,
                        tooltip: ref.watch(vuSplitProvider)
                            ? 'Source: bass / treble'
                            : 'Source: loudness',
                        color: ref.watch(vuSplitProvider)
                            ? theme.primary
                            : theme.textMuted,
                        onTap: () {
                          final on = ref.read(vuSplitProvider);
                          ref.read(vuSplitProvider.notifier).set(!on);
                        },
                      ),
                  ],
                  const Spacer(),
                  _TopButton(
                    icon: Icons.open_in_full_rounded,
                    tooltip: 'Back to full window',
                    color: theme.textMuted,
                    onTap: () =>
                        ref.read(overlayModeProvider.notifier).exit(),
                  ),
                ],
              ),
              const SizedBox(height: Space.s2),
              // The stage: art or meters.
              Expanded(
                child: Center(
                  child: track == null
                      ? Text('Nothing playing',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            color: theme.textMuted,
                          ))
                      : (_showViz
                          ? VisualizerWidget(
                              height: isVu ? 180 : 64,
                              styleOverride: style,
                            )
                          : _Art(track: track, theme: theme)),
                ),
              ),
              const SizedBox(height: Space.s3),
              if (track != null) ...[
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: theme.textPrimary,
                  ),
                ),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 12,
                    color: theme.textMuted,
                  ),
                ),
                const SizedBox(height: Space.s2),
                _Seek(theme: theme),
              ],
              const SizedBox(height: Space.s1),
              _Transport(theme: theme, isPlaying: audio?.isPlaying ?? false),
            ],
          ),
        ),
      ),
    );
  }
}

class _Art extends StatelessWidget {
  const _Art({required this.track, required this.theme});
  final Track track;
  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context) {
    final artPath = track.albumArtPath;
    final artUrl = track.artUrl;
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.lg),
          color: theme.surface,
          image: artPath != null
              ? DecorationImage(
                  image: FileImage(File(artPath)), fit: BoxFit.cover)
              : artUrl != null
                  ? DecorationImage(
                      image: NetworkImage(artUrl), fit: BoxFit.cover)
                  : null,
        ),
        child: artPath == null && artUrl == null
            ? Icon(Icons.music_note, size: 48, color: theme.textMuted)
            : null,
      ),
    );
  }
}

class _Seek extends ConsumerWidget {
  const _Seek({required this.theme});
  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioStateProvider).value;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final buffered = ref.watch(bufferedProvider).value ?? Duration.zero;
    return SeekBarWidget(
      position: position,
      duration: audio?.duration ?? Duration.zero,
      buffered: buffered,
      theme: theme,
      onSeek: (d) => ref.read(audioHandlerProvider).seek(d),
    );
  }
}

class _Transport extends ConsumerWidget {
  const _Transport({required this.theme, required this.isPlaying});
  final HanamimiTheme theme;
  final bool isPlaying;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 26,
          icon: Icon(Icons.skip_previous_rounded, color: theme.textPrimary),
          onPressed: handler.skipToPrevious,
        ),
        const SizedBox(width: Space.s2),
        Container(
          width: 48,
          height: 48,
          decoration:
              BoxDecoration(color: theme.primary, shape: BoxShape.circle),
          child: IconButton(
            iconSize: 26,
            icon: Icon(
              isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
            onPressed: () => isPlaying ? handler.pause() : handler.play(),
          ),
        ),
        const SizedBox(width: Space.s2),
        IconButton(
          iconSize: 26,
          icon: Icon(Icons.skip_next_rounded, color: theme.textPrimary),
          onPressed: handler.skipToNext,
        ),
      ],
    );
  }
}

class _TopButton extends StatelessWidget {
  const _TopButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      iconSize: 20,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: color),
      onPressed: onTap,
    );
  }
}
