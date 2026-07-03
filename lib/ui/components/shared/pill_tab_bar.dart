import 'package:flutter/material.dart';

import '../../../theme/hanamimi_theme.dart';
import '../../../theme/theme_tokens.dart';

/// Capsule segmented control (Songs | Albums | Playlists).
/// A primary-colored pill indicator slides under the active tab with a
/// spring curve, per DESIGN.md §9.4.
class PillTabBar extends StatelessWidget {
  const PillTabBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onChanged,
    required this.theme,
  });

  final List<String> tabs;
  final int activeIndex;
  final ValueChanged<int> onChanged;
  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context) {
    // "Soft indentation in the screen": background slightly darkened.
    final sunken = Color.lerp(theme.background, theme.textPrimary, 0.05)!;

    return Container(
      height: Sizes.pillTabBarHeight,
      padding: const EdgeInsets.all(Space.s1),
      decoration: BoxDecoration(
        color: sunken,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final tabWidth = constraints.maxWidth / tabs.length;
        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutBack,
              left: tabWidth * activeIndex,
              width: tabWidth,
              top: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.primary,
                  borderRadius: BorderRadius.circular(Radii.pill),
                  boxShadow: [
                    BoxShadow(
                      color: theme.primary.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(i),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: Anim.minTransition,
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: i == activeIndex
                                ? Colors.white
                                : theme.textMuted,
                          ),
                          child: Text(tabs[i]),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }
}
