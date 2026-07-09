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
          // Art (square) + a flexible caption block. The caption is
          // Expanded so a tall glyph run (Devanagari, accents) or a large
          // text-scale can never push the card past this box — it was
          // overflowing by ~1px on some titles otherwise.
          height: _cardWidth + 50,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Clip to the pane, not Clip.none — in the three-pane shell an
            // unclipped horizontal list painted its off-screen cards past
            // the middle pane and under the transparent Now Playing panel
            // (user-reported "overlap"). hardEdge keeps cards inside their
            // column; the first still aligns with the inset section label.
            clipBehavior: Clip.hardEdge,
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
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
