import 'package:flutter/material.dart';

import '../../../library/models/playlist.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hanamimi_theme.dart';
import '../../../theme/theme_tokens.dart';
import 'playlist_cover.dart';

/// Horizontal notebook-style card (DESIGN.md §9.3): cover (custom image,
/// art collage or colour block) on the left, name + track count right.
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.theme,
    required this.onTap,
  });

  final Playlist playlist;
  final HanamimiTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: theme.divider, width: 0.5),
          ),
          child: Row(
            children: [
              PlaylistCover(
                playlist: playlist,
                size: 80,
                borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(Radii.md)),
              ),
              const SizedBox(width: Space.s4),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${playlist.trackIds.length} tracks',
                      style: AppText.caption(theme),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.textMuted),
              const SizedBox(width: Space.s3),
            ],
          ),
        ),
      ),
    );
  }
}
