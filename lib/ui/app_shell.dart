import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../theme/theme_tokens.dart';
import 'components/mini_player.dart';
import 'components/shared/bottom_nav.dart';
import 'screens/library_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/you_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  int _previousIndex = 0;

  static const _screens = [
    LibraryScreen(),
    NowPlayingScreen(),
    YouScreen(),
  ];

  void _onNavChanged(int i) {
    if (i == _index) return;
    setState(() {
      _previousIndex = _index;
      _index = i;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    // Content slides in from the direction of travel (DESIGN.md §8).
    final slideFromRight = _index > _previousIndex;

    return Scaffold(
      body: AnimatedSwitcher(
        duration: Anim.tabSlide,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeOut,
        transitionBuilder: (child, animation) {
          final isIncoming = child.key == ValueKey(_index);
          final beginX = isIncoming
              ? (slideFromRight ? 0.15 : -0.15)
              : (slideFromRight ? -0.15 : 0.15);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(beginX, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(
          key: ValueKey(_index),
          child: _screens[_index],
        ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Hidden on the Playing tab — the full screen is already there.
          if (_index != 1) MiniPlayer(onOpen: () => _onNavChanged(1)),
          HanamimiBottomNav(
            activeIndex: _index,
            onChanged: _onNavChanged,
            theme: theme,
          ),
        ],
      ),
    );
  }
}
