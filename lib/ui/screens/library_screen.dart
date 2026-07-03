import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/playlist.dart';
import '../../providers/library_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/library/album_card.dart';
import '../components/library/playlist_card.dart';
import '../components/library/track_row.dart';
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Space.s6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            child: Row(
              children: [
                Text('Hanamimi',
                    style: AppText.screenTitle(theme).copyWith(fontSize: 22)),
                const Spacer(),
                Icon(Icons.search, size: 24, color: theme.textMuted),
              ],
            ),
          ),
          const SizedBox(height: Space.s4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            child: PillTabBar(
              tabs: const ['Songs', 'Albums', 'Playlists'],
              activeIndex: _tab,
              onChanged: (i) => setState(() => _tab = i),
              theme: theme,
            ),
          ),
          const SizedBox(height: Space.s2),
          Expanded(
            child: AnimatedSwitcher(
              duration: Anim.minTransition,
              child: switch (_tab) {
                0 => const _SongsTab(key: ValueKey(0)),
                1 => const _AlbumsTab(key: ValueKey(1)),
                _ => const _PlaylistsTab(key: ValueKey(2)),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SongsTab extends ConsumerWidget {
  const _SongsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final library = ref.watch(libraryProvider);

    return library.when(
      loading: () => Center(
          child: CircularProgressIndicator(color: theme.primary)),
      error: (e, _) => _Message('Something went wrong: $e', theme: theme),
      data: (tracks) {
        if (tracks.isEmpty) {
          final denied =
              ref.read(libraryProvider.notifier).permissionDenied;
          return _Message(
            denied
                ? 'Hanamimi needs permission to find your music'
                : 'No songs found on this device',
            theme: theme,
            actionLabel: denied ? 'Grant access' : 'Rescan',
            onAction: () => ref.read(libraryProvider.notifier).rescan(),
          );
        }
        return RefreshIndicator(
          color: theme.primary,
          onRefresh: () => ref.read(libraryProvider.notifier).rescan(),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(
                horizontal: Space.s4, vertical: Space.s2),
            itemCount: tracks.length,
            itemExtent: Sizes.trackRowHeight,
            itemBuilder: (context, i) => TrackRow(
              track: tracks[i],
              theme: theme,
              onTap: () {
                // Playback lands in M5.
              },
            ),
          ),
        );
      },
    );
  }
}

class _AlbumsTab extends ConsumerWidget {
  const _AlbumsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final albums = ref.watch(albumsProvider);

    if (albums.isEmpty) {
      return _Message('No albums yet', theme: theme);
    }
    return GridView.builder(
      padding: const EdgeInsets.all(Space.s4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: Space.s3,
        crossAxisSpacing: Space.s3,
      ),
      itemCount: albums.length,
      itemBuilder: (context, i) => AlbumCard(
        album: albums[i],
        onTap: () {
          // Album detail / play lands with the audio engine.
        },
      ),
    );
  }
}

class _PlaylistsTab extends ConsumerWidget {
  const _PlaylistsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final playlists = ref.watch(playlistsProvider).value ?? [];

    return Stack(
      children: [
        if (playlists.isEmpty)
          _Message('No playlists yet — make one!', theme: theme)
        else
          ListView.separated(
            padding: const EdgeInsets.all(Space.s4),
            itemCount: playlists.length,
            separatorBuilder: (_, __) => const SizedBox(height: Space.s3),
            itemBuilder: (context, i) => PlaylistCard(
              playlist: playlists[i],
              theme: theme,
              onTap: () {},
            ),
          ),
        Positioned(
          right: Space.s4,
          bottom: Space.s4,
          child: FloatingActionButton.extended(
            heroTag: 'new_playlist',
            backgroundColor: theme.primary,
            foregroundColor: Colors.white,
            elevation: 2,
            shape: const StadiumBorder(),
            icon: const Icon(Icons.add),
            label: const Text('New playlist',
                style: TextStyle(
                    fontFamily: 'Nunito', fontWeight: FontWeight.w600)),
            onPressed: () => _showCreatePlaylistSheet(context, ref, theme),
          ),
        ),
      ],
    );
  }
}

void _showCreatePlaylistSheet(
    BuildContext context, WidgetRef ref, HanamimiTheme theme) {
  final controller = TextEditingController();
  var selectedColor = playlistCoverColors.first;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: EdgeInsets.only(
          left: Space.s4,
          right: Space.s4,
          top: Space.s6,
          bottom: MediaQuery.of(context).viewInsets.bottom + Space.s6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New playlist',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.textPrimary)),
            const SizedBox(height: Space.s4),
            TextField(
              controller: controller,
              autofocus: true,
              style: AppText.body(theme),
              decoration: InputDecoration(
                hintText: 'Playlist name',
                hintStyle: AppText.body(theme)
                    .copyWith(color: theme.textMuted),
                filled: true,
                fillColor: theme.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.md),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: Space.s4),
            Wrap(
              spacing: Space.s3,
              children: [
                for (final c in playlistCoverColors)
                  GestureDetector(
                    onTap: () => setState(() => selectedColor = c),
                    child: AnimatedContainer(
                      duration: Anim.minTransition,
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selectedColor == c
                              ? theme.textPrimary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Space.s6),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primary,
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(vertical: Space.s3),
                ),
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isEmpty) return;
                  ref
                      .read(playlistsProvider.notifier)
                      .create(name, selectedColor.toARGB32());
                  Navigator.pop(context);
                },
                child: const Text('Create',
                    style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text,
      {required this.theme, this.actionLabel, this.onAction});

  final String text;
  final HanamimiTheme theme;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: AppText.body(theme), textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: Space.s4),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.primary,
                shape: const StadiumBorder(),
              ),
              onPressed: onAction,
              child: Text(actionLabel!,
                  style: const TextStyle(
                      fontFamily: 'Nunito', fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }
}
