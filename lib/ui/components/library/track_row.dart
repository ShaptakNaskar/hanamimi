import 'package:flutter/material.dart';

import '../../../library/models/track.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hanamimi_theme.dart';
import '../../../theme/theme_tokens.dart';
import '../../../utils/duration_ext.dart';
import 'art_thumb.dart';
import 'playing_bars.dart';

class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.theme,
    required this.onTap,
    this.isPlaying = false,
    this.onAddToQueue,
    this.onAddToPlaylist,
    this.onRemove,
  });

  final Track track;
  final HanamimiTheme theme;
  final VoidCallback onTap;
  final bool isPlaying;

  /// Swipe right reveals "add to queue"; swipe left "add to playlist"
  /// (DESIGN.md §9.1) — or "remove" inside a playlist view. Rows spring
  /// back after the action fires.
  final VoidCallback? onAddToQueue;
  final VoidCallback? onAddToPlaylist;

  /// When set, swipe-left removes instead of adding to a playlist.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final row = _buildRow(context);
    if (onAddToQueue == null && onAddToPlaylist == null && onRemove == null) {
      return row;
    }

    return Dismissible(
      // Source-qualified: ephemeral online search rows all carry id -1,
      // but their sourceId is unique.
      key: ValueKey('track_${track.source.name}_${track.sourceId ?? track.id}'),
      direction: DismissDirection.horizontal,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.35,
        DismissDirection.endToStart: 0.35,
      },
      // Fire the action, then spring back instead of dismissing.
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onAddToQueue?.call();
        } else if (onRemove != null) {
          onRemove!.call();
        } else {
          onAddToPlaylist?.call();
        }
        return false;
      },
      background: _SwipeAction(
        alignment: Alignment.centerLeft,
        color: theme.secondary,
        icon: Icons.add_circle_outline,
        label: 'Queue',
      ),
      secondaryBackground: onRemove != null
          ? _SwipeAction(
              alignment: Alignment.centerRight,
              color: theme.accent,
              icon: Icons.remove_circle_outline,
              label: 'Remove',
            )
          : _SwipeAction(
              alignment: Alignment.centerRight,
              color: theme.primary,
              icon: Icons.bookmark_add_outlined,
              label: 'Playlist',
            ),
      child: row,
    );
  }

  Widget _buildRow(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: theme.primary.withValues(alpha: 0.12),
        highlightColor: theme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.md),
        child: SizedBox(
          height: Sizes.trackRowHeight,
          child: Row(
            children: [
              if (isPlaying)
                SizedBox(
                  width: Sizes.trackRowArt,
                  height: Sizes.trackRowArt,
                  child: Center(child: PlayingBars(color: theme.primary)),
                )
              else
                ArtThumb(
                  title: track.album.isEmpty ? track.title : track.album,
                  artPath: track.albumArtPath,
                  artUrl: track.artUrl,
                  size: Sizes.trackRowArt,
                  radius: 8,
                ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            track.title,
                            style: isPlaying
                                ? AppText.rowSongTitle(theme)
                                    .copyWith(color: theme.primary)
                                : AppText.rowSongTitle(theme),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Cloud badge: streamed / downloaded (§9).
                        if (!track.isLocal) ...[
                          const SizedBox(width: Space.s1),
                          Icon(
                            track.isPlayableOffline
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_outlined,
                            size: 13,
                            color: theme.textMuted,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.artist,
                      style: AppText.rowArtist(theme),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.s3),
              Text(track.duration.mmss, style: AppText.timestamp(theme)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeAction extends StatelessWidget {
  const _SwipeAction({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: Space.s4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}
