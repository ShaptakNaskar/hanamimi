import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../theme/hanamimi_theme.dart';
import '../../../theme/theme_tokens.dart';

/// The playlist-as-a-place hero: big cover, name, meta line and the
/// action row. Shared by the offline playlist detail and the online
/// (YT Music) playlist view so the two can't drift apart again — they
/// once did, and the centered action Row pushed the play button off to
/// the right as soon as a variant added extra actions.
///
/// The play button is pinned dead-center regardless of how many
/// [leading]/[trailing] actions flank it: each side sits in an Expanded
/// half and grows outward from the middle.
class PlaylistHeroHeader extends StatelessWidget {
  const PlaylistHeroHeader({
    super.key,
    required this.theme,
    required this.cover,
    required this.title,
    required this.meta,
    this.hint,
    this.leading = const [],
    this.trailing = const [],
    this.onPlay,
  });

  final HanamimiTheme theme;
  final Widget cover;
  final String title;
  final String meta;

  /// Optional micro-hint under the meta line (e.g. reorder affordance).
  final String? hint;

  /// Secondary actions left / right of the centered play button.
  final List<Widget> leading;
  final List<Widget> trailing;

  /// Null disables the play button (empty playlist).
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        cover,
        const SizedBox(height: Space.s4),
        Text(title,
            style: AppText.screenTitle(theme),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: Space.s1),
        Text(meta, style: AppText.caption(theme)),
        if (hint != null)
          Text(hint!, style: AppText.caption(theme).copyWith(fontSize: 10)),
        const SizedBox(height: Space.s3),
        Row(
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: _spaced(leading),
              ),
            ),
            const SizedBox(width: Space.s4),
            InkResponse(
              onTap: onPlay,
              radius: 30,
              child: Container(
                width: Sizes.playButton,
                height: Sizes.playButton,
                decoration: BoxDecoration(
                    color: theme.primary, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow,
                    color: Colors.white, size: 32),
              ),
            ),
            const SizedBox(width: Space.s4),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: _spaced(trailing),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _spaced(List<Widget> actions) => [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: Space.s4),
          actions[i],
        ],
      ];
}

/// A secondary hero action: a muted icon on a 44px touch target. No
/// labels — uniform square targets keep every action equidistant from
/// the centered play button (label widths made them lopsided).
class HeroAction extends StatelessWidget {
  const HeroAction({
    super.key,
    required this.theme,
    required this.icon,
    this.onTap,
  });

  final HanamimiTheme theme;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: SizedBox(
        width: Sizes.minTouchTarget,
        height: Sizes.minTouchTarget,
        child: Icon(icon, size: 24, color: theme.textMuted),
      ),
    );
  }
}
