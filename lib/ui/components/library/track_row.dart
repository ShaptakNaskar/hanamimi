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
  });

  final Track track;
  final HanamimiTheme theme;
  final VoidCallback onTap;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
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
                  title: track.album,
                  artPath: track.albumArtPath,
                  size: Sizes.trackRowArt,
                  radius: 8,
                ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      style: isPlaying
                          ? AppText.rowSongTitle(theme)
                              .copyWith(color: theme.primary)
                          : AppText.rowSongTitle(theme),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
