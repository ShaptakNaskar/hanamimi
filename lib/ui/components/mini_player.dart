import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/audio_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import 'library/art_thumb.dart';

/// Persistent bar above the bottom nav when a track is loaded
/// (DESIGN.md §9.7). 2px progress line along the top edge; tapping the
/// body opens Now Playing.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final audio = ref.watch(audioStateProvider).value;
    final track = audio?.currentTrack;

    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      child: track == null
          ? const SizedBox(width: double.infinity)
          : GestureDetector(
              onTap: onOpen,
              child: Container(
                height: Sizes.miniPlayerHeight,
                decoration: BoxDecoration(
                  color: theme.surface.withValues(alpha: 0.97),
                  border: Border(
                      top: BorderSide(color: theme.divider, width: 0.5)),
                ),
                child: Column(
                  children: [
                    _ProgressLine(theme: theme),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: Space.s4),
                        child: Row(
                          children: [
                            ArtThumb(
                              title: track.album.isEmpty
                                  ? track.title
                                  : track.album,
                              artPath: track.albumArtPath,
                              artUrl: track.artUrl,
                              size: Sizes.miniPlayerArt,
                              radius: Radii.md,
                            ),
                            const SizedBox(width: Space.s3),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    track.title,
                                    style: TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: theme.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    track.artist,
                                    style: TextStyle(
                                      fontFamily: 'Nunito',
                                      fontSize: 12,
                                      color: theme.textMuted,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: Space.s3),
                            _PlayPauseButton(
                              isPlaying: audio?.isPlaying ?? false,
                              color: theme.primary,
                              onTap: () {
                                final handler =
                                    ref.read(audioHandlerProvider);
                                (audio?.isPlaying ?? false)
                                    ? handler.pause()
                                    : handler.play();
                              },
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

class _ProgressLine extends ConsumerWidget {
  const _ProgressLine({required this.theme});

  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration =
        ref.watch(audioStateProvider).value?.duration ?? Duration.zero;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return SizedBox(
      height: 2,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress,
          child: Container(color: theme.primary),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.isPlaying,
    required this.color,
    required this.onTap,
  });

  final bool isPlaying;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: Tween(begin: 0.8, end: 1.0).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            key: ValueKey(isPlaying),
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
