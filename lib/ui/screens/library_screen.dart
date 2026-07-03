import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/shared/pill_tab_bar.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: Space.s6),
            Row(
              children: [
                Text('Hanamimi',
                    style: AppText.screenTitle(theme).copyWith(fontSize: 22)),
                const Spacer(),
                Icon(Icons.search, size: 24, color: theme.textMuted),
              ],
            ),
            const SizedBox(height: Space.s4),
            PillTabBar(
              tabs: const ['Songs', 'Albums', 'Playlists'],
              activeIndex: _tab,
              onChanged: (i) => setState(() => _tab = i),
              theme: theme,
            ),
            const SizedBox(height: Space.s4),
            Expanded(
              child: AnimatedSwitcher(
                duration: Anim.minTransition,
                child: _EmptyTab(
                  key: ValueKey(_tab),
                  label: const ['songs', 'albums', 'playlists'][_tab],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder until the data layer (M4) provides real content.
class _EmptyTab extends ConsumerWidget {
  const _EmptyTab({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    return Center(
      child: Text('No $label yet', style: AppText.caption(theme)),
    );
  }
}
