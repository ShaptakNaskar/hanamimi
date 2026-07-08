import 'package:flutter/material.dart';

import '../../../library/models/track.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hanamimi_theme.dart';
import '../../../theme/theme_tokens.dart';
import '../library/art_thumb.dart';

/// A horizontal card shelf of tracks — the Home building block ("Jump
/// back in", "For you", "Discover" all render through this).
class TrackShelf extends StatelessWidget {
  const TrackShelf({
    super.key,
    required this.title,
    required this.tracks,
    required this.theme,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final String title;

  /// Muted line under the section label (e.g. the privacy note on the
  /// online shelves).
  final String? subtitle;
  final List<Track> tracks;
  final HanamimiTheme theme;
  final void Function(int index) onTap;

  /// Optional affordance next to the section label (e.g. play-all).
  final Widget? trailing;

  static const _cardWidth = 132.0;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(title, style: AppText.sectionLabel(theme))),
            if (trailing != null) trailing!,
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: Space.s1),
          Text(subtitle!,
              style: AppText.caption(theme)
                  .copyWith(color: theme.textMuted)),
        ],
        const SizedBox(height: Space.s3),
        SizedBox(
          height: _cardWidth + 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Cards bleed to the screen edge while the section label
            // keeps the page inset.
            clipBehavior: Clip.none,
            itemCount: tracks.length,
            separatorBuilder: (_, __) => const SizedBox(width: Space.s3),
            itemBuilder: (context, i) {
              final track = tracks[i];
              return InkWell(
                onTap: () => onTap(i),
                borderRadius: BorderRadius.circular(Radii.md),
                child: SizedBox(
                  width: _cardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ArtThumb(
                        title: track.title,
                        artPath: track.albumArtPath,
                        artUrl: track.artUrl,
                        size: _cardWidth,
                        radius: Radii.md,
                      ),
                      const SizedBox(height: Space.s2),
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.rowSongTitle(theme)
                            .copyWith(fontSize: 13),
                      ),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption(theme),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
