import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/night_mode_provider.dart';
import '../../../theme/hanamimi_theme.dart';
import '../../../theme/theme_tokens.dart';

class NavItem {
  const NavItem(this.label, this.icon, this.activeIcon);
  final String label;
  final IconData icon;
  final IconData activeIcon;
}

const _items = [
  NavItem('Home', Icons.home_outlined, Icons.home_rounded),
  NavItem('Library', Icons.music_note_outlined, Icons.music_note_outlined),
  NavItem('Playing', Icons.play_circle_outline, Icons.play_circle),
  NavItem('Downloads', Icons.download_outlined, Icons.download),
  NavItem('You', Icons.pets_outlined, Icons.pets_outlined),
];

/// Desktop wide-window nav (ARCHITECTURE-DESKTOP.md §5): the same
/// destinations as [HanamimiBottomNav], standing up as a left rail.
/// In the side-by-side layout Now Playing lives in its own permanent
/// panel, so [showPlaying] drops that destination from the rail.
/// Phone landscape borrows it with [labels] off — a slim icons-only
/// strip where a bottom nav would eat the little height there is.
class HanamimiSideRail extends ConsumerWidget {
  const HanamimiSideRail({
    super.key,
    required this.activeIndex,
    required this.onChanged,
    required this.theme,
    this.showPlaying = true,
    this.labels = true,
  });

  final int activeIndex;
  final ValueChanged<int> onChanged;
  final HanamimiTheme theme;
  final bool showPlaying;
  final bool labels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = ref.watch(nightModeActiveProvider);
    return Container(
      width: labels ? 76 : 64,
      decoration: BoxDecoration(
        // Opaque like the sidebar — a light album backdrop used to wash
        // this rail pale and hide its icons on a dark theme.
        color: theme.surface,
        border: Border(
            right: BorderSide(
                color: theme.divider.withValues(alpha: 0.4), width: 0.5)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _items.length; i++)
              if (showPlaying || i != 2)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s3),
                child: InkResponse(
                  onTap: () => onChanged(i),
                  radius: 34,
                  child: Column(
                    children: [
                      Icon(
                        i == activeIndex
                            ? _items[i].activeIcon
                            : _items[i].icon,
                        size: 24,
                        color: i == activeIndex
                            ? theme.primary
                            : theme.textMuted,
                      ),
                      if (labels) ...[
                        const SizedBox(height: 3),
                        AnimatedDefaultTextStyle(
                          duration: Anim.minTransition,
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 10,
                            fontWeight: i == activeIndex
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: i == activeIndex
                                ? theme.primary
                                : theme.textMuted.withValues(alpha: 0.85),
                          ),
                          child: Text(_items[i].label.whisper(night)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class HanamimiBottomNav extends ConsumerWidget {
  const HanamimiBottomNav({
    super.key,
    required this.activeIndex,
    required this.onChanged,
    required this.theme,
  });

  final int activeIndex;
  final ValueChanged<int> onChanged;
  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final night = ref.watch(nightModeActiveProvider);
    return Container(
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(top: BorderSide(color: theme.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: Sizes.bottomNavHeight,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: InkResponse(
                    onTap: () => onChanged(i),
                    radius: 40,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          i == activeIndex
                              ? _items[i].activeIcon
                              : _items[i].icon,
                          size: 24,
                          color: i == activeIndex
                              ? theme.primary
                              : theme.textMuted,
                        ),
                        const SizedBox(height: 3),
                        AnimatedDefaultTextStyle(
                          duration: Anim.minTransition,
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 10,
                            fontWeight: i == activeIndex
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: i == activeIndex
                                ? theme.primary
                                : theme.textMuted.withValues(alpha: 0.85),
                          ),
                          child: Text(_items[i].label.whisper(night)),
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
