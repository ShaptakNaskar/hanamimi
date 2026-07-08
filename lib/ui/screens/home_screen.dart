import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/audio_provider.dart';
import '../../providers/home_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/reco_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/home/track_shelf.dart';

/// Home — the start page (ARCHITECTURE-RECOMMENDATIONS.md §5). Shelves
/// in trust order: your recents first, then the on-device picks. Base
/// Hanamimi is local-only, so there are no online shelves here.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static String greeting(DateTime now) {
    final h = now.hour;
    if (h < 5) return 'Up late ♪';
    if (h < 12) return 'Good morning ♪';
    if (h < 17) return 'Good afternoon ♪';
    return 'Good evening ♪';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final recent = ref.watch(recentTracksProvider).value ?? const [];
    final forYou = ref.watch(forYouProvider).value ?? const [];
    final libraryEmpty =
        (ref.watch(libraryProvider).value ?? const []).isEmpty;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        children: [
          const SizedBox(height: Space.s6),
          Text(greeting(DateTime.now()),
              style: AppText.screenTitle(theme)),
          const SizedBox(height: Space.s6),
          if (recent.isEmpty)
            _EmptyHome(theme: theme, libraryEmpty: libraryEmpty)
          else
            TrackShelf(
              title: 'JUMP BACK IN',
              tracks: recent,
              theme: theme,
              onTap: (i) => ref
                  .read(audioHandlerProvider)
                  .playTracks(recent, startIndex: i),
            ),
          if (forYou.isNotEmpty) ...[
            const SizedBox(height: Space.s6),
            TrackShelf(
              title: 'FOR YOU',
              subtitle: 'picked on this device, from your listening',
              tracks: forYou,
              theme: theme,
              // Tap = the pick seeds a whole station, not a bare
              // one-song queue — "For you" is a doorway, not a list.
              onTap: (i) => startRadio(ref, forYou[i]),
            ),
          ],
          const SizedBox(height: Space.s6),
        ],
      ),
    );
  }
}

/// Cold start — the page still breathes instead of showing a blank
/// list (the whole point of Home over Songs as the landing tab).
class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.theme, required this.libraryEmpty});

  final HanamimiTheme theme;
  final bool libraryEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: theme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(libraryEmpty ? 'Welcome to Hanamimi 🌸' : 'All quiet 🌸',
              style: AppText.rowSongTitle(theme)),
          const SizedBox(height: Space.s2),
          Text(
            libraryEmpty
                ? 'Your music lives in the Library tab — add folders '
                    'there. Everything you play gathers here.'
                : "Play something and it'll be waiting here next time.",
            style: AppText.caption(theme),
          ),
        ],
      ),
    );
  }
}
