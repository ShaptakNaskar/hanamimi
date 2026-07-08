import 'package:flutter/material.dart';

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
  NavItem('You', Icons.pets_outlined, Icons.pets_outlined),
];

class HanamimiBottomNav extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                          child: Text(_items[i].label),
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
