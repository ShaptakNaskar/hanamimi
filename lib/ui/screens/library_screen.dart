import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../audio/models/queue_mode.dart';
import '../../library/models/playlist.dart';
import '../../library/models/track.dart';
import '../../utils/back_stack.dart';
import '../../providers/audio_provider.dart';
import '../../platform/desktop/desktop_bootstrap.dart';
import '../../providers/desktop_shell_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/mascot_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/update_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../../providers/buddy_provider.dart';
import '../components/library/album_card.dart';
import '../components/mascot/buddies.dart';
import '../components/mascot/hanamimi_widget.dart';
import '../components/mascot/oneko.dart';
import '../components/library/playlist_card.dart';
import '../components/library/playlist_cover.dart';
import '../components/library/track_row.dart';
import '../components/shared/pill_tab_bar.dart';
import '../modals/download_quality_sheet.dart';
import '../modals/import_playlist_sheet.dart';
import '../modals/playlist_picker_sheet.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  int _tab = 0;
  bool _searching = false;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // System back closes the search overlay before leaving the screen.
    BackStack.register(this, () {
      if (!_searching) return false;
      _closeSearch();
      return true;
    });
  }

  @override
  void dispose() {
    BackStack.unregister(this);
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    setState(() => _query = q);
  }

  void _closeSearch() {
    setState(() {
      _searching = false;
      _query = '';
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    // Library search is local-only — online (YouTube/JioSaavn) search
    // lives in the You page now.
    // Desktop sidebar deep-link (three-pane shell): a request overrides
    // the tab until the user drives the pills again.
    final collectionRequest = ref.watch(desktopCollectionProvider);
    final visualTab = collectionRequest == null
        ? _tab
        : collectionRequest.type == DesktopCollectionType.folder
            ? 2
            : 3;

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Space.s6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            child: _searching
                ? Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: Sizes.inputHeight,
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            onChanged: _onQueryChanged,
                            style: AppText.body(theme),
                            decoration: InputDecoration(
                              hintText: 'Search your music…',
                              hintStyle: AppText.body(theme)
                                  .copyWith(color: theme.textMuted),
                              prefixIcon: Icon(Icons.search,
                                  size: 20, color: theme.textMuted),
                              filled: true,
                              fillColor: theme.surface,
                              contentPadding: EdgeInsets.zero,
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(Radii.pill),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.s2),
                      InkResponse(
                        onTap: _closeSearch,
                        radius: 20,
                        child:
                            Icon(Icons.close, size: 24, color: theme.textMuted),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // In the three-pane shell (desktop windows AND
                      // wide tablets) the sidebar already wears the
                      // mascot + edition title — repeating it here read
                      // as a glitch.
                      if (MediaQuery.sizeOf(context).width < 1240) ...[
                        Row(
                          children: [
                            // The mascot lives in the header too — she
                            // reacts to playback just like on Now Playing.
                            if (ref
                                .watch(buddyEnabledProvider('beagle'))) ...[
                              HanamimiMascot(
                                  state: ref.watch(mascotStateProvider),
                                  size: 30),
                              const SizedBox(width: Space.s2),
                            ],
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Text(
                                    ref.watch(editionNameProvider).value ??
                                        'Hanamimi',
                                    style: AppText.screenTitle(theme)
                                        .copyWith(fontSize: 22)),
                                // The parrot perches on the title and hops
                                // along it (Requests.txt #20).
                                if (ref
                                    .watch(buddyEnabledProvider('parrot')))
                                  const Positioned(
                                      left: 0,
                                      right: 0,
                                      top: -15,
                                      child: HeaderParrot()),
                              ],
                            ),
                            // The cat sleeps beside the logo (the
                            // Vencord look) — always on mobile, and on
                            // desktop whenever pointer-chasing is off.
                            if (ref.watch(buddyEnabledProvider('cat')) &&
                                (!isDesktop ||
                                    !ref.watch(catFollowProvider))) ...[
                              const SizedBox(width: Space.s1),
                              const SleepingOneko(),
                            ],
                          ],
                        ),
                        const SizedBox(height: Space.s3),
                      ],
                      // A visible search bar that NAMES the online
                      // sources — the icon-only entry point hid that
                      // this app searches & streams YouTube/JioSaavn.
                      GestureDetector(
                        onTap: () => setState(() => _searching = true),
                        child: Container(
                          height: Sizes.inputHeight,
                          padding: const EdgeInsets.symmetric(
                              horizontal: Space.s3),
                          decoration: BoxDecoration(
                            color: theme.surface,
                            borderRadius:
                                BorderRadius.circular(Radii.pill),
                            border: Border.all(
                                color: theme.divider, width: 0.5),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.search,
                                  size: 20, color: theme.textMuted),
                              const SizedBox(width: Space.s2),
                              Expanded(
                                child: Text(
                                  'Search your music…',
                                  style: AppText.body(theme).copyWith(
                                      color: theme.textMuted),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: Space.s4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            // Collection pills; while searching they still switch which
            // local collection the query filters.
            child: PillTabBar(
              tabs: const ['Songs', 'Albums', 'Folders', 'Playlists'],
              activeIndex: visualTab,
              onChanged: (i) => setState(() {
                // Manual pill tap takes the wheel back from the sidebar.
                ref.read(desktopCollectionProvider.notifier).clear();
                _tab = i;
              }),
              theme: theme,
            ),
          ),
          const SizedBox(height: Space.s2),
          Expanded(
            child: AnimatedSwitcher(
              duration: Anim.minTransition,
              child: collectionRequest != null
                      ? switch (collectionRequest.type) {
                          DesktopCollectionType.folder => _FoldersTab(
                              key: ValueKey(
                                  'sidebar_${collectionRequest.nonce}'),
                              query: _query,
                              initialOpenPath: collectionRequest.folderPath,
                            ),
                          DesktopCollectionType.playlist => _PlaylistsTab(
                              key: ValueKey(
                                  'sidebar_${collectionRequest.nonce}'),
                              query: _query,
                              initialOpenId: collectionRequest.playlistId,
                            ),
                          DesktopCollectionType.liked => _PlaylistsTab(
                              key: ValueKey(
                                  'sidebar_${collectionRequest.nonce}'),
                              query: _query,
                              initialLikedOpen: true,
                            ),
                        }
                      : switch (_tab) {
                          0 =>
                            _SongsTab(key: const ValueKey(0), query: _query),
                          1 =>
                            _AlbumsTab(key: const ValueKey(1), query: _query),
                          2 =>
                            _FoldersTab(key: const ValueKey(2), query: _query),
                          _ => _PlaylistsTab(
                              key: const ValueKey(3), query: _query),
                        },
            ),
          ),
        ],
      ),
    );
  }
}

class _SongsTab extends ConsumerWidget {
  const _SongsTab({super.key, this.query = ''});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final library = ref.watch(libraryProvider);

    return library.when(
      loading: () => Center(
          child: CircularProgressIndicator(color: theme.primary)),
      error: (e, _) => _Message('Something went wrong: $e', theme: theme),
      data: (allTracks) {
        // Library = what's on the device. Online tracks (streamed or
        // downloaded) live in search, playlists, the queue and the
        // Downloads tab — mixing them in here made the library feel
        // like someone else's. Deduped: the same song ripped twice
        // (same tags + duration, different filename) shows once.
        final localTracks = dedupeTracks([
          for (final t in allTracks)
            if (t.isLocal) t,
        ]);
        final q = query.trim().toLowerCase();
        final tracks = q.isEmpty
            ? localTracks
            : localTracks
                .where((t) =>
                    t.title.toLowerCase().contains(q) ||
                    t.artist.toLowerCase().contains(q) ||
                    t.album.toLowerCase().contains(q))
                .toList();
        if (tracks.isEmpty && q.isNotEmpty) {
          return _Message('Nothing matches "$query"', theme: theme);
        }
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
        final playingId =
            ref.watch(audioStateProvider).value?.currentTrack?.id;
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
              isPlaying: tracks[i].id == playingId,
              onTap: () => ref
                  .read(audioHandlerProvider)
                  .playTracks(tracks, startIndex: i),
              onAddToQueue: () {
                ref
                    .read(audioHandlerProvider)
                    .engine
                    .addToQueue(tracks[i]);
                _toast(context, 'Added to queue');
              },
              onAddToPlaylist: () =>
                  showPlaylistPicker(context, ref, theme, tracks[i].id),
            ),
          ),
        );
      },
    );
  }
}

class _AlbumsTab extends ConsumerWidget {
  const _AlbumsTab({super.key, this.query = ''});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final q = query.trim().toLowerCase();
    final albums = ref
        .watch(albumsProvider)
        .where((a) =>
            q.isEmpty ||
            a.title.toLowerCase().contains(q) ||
            a.artist.toLowerCase().contains(q))
        .toList();

    if (albums.isEmpty) {
      return _Message(
          q.isEmpty ? 'No albums yet' : 'Nothing matches "$query"',
          theme: theme);
    }
    return GridView.builder(
      padding: const EdgeInsets.all(Space.s4),
      // Max-extent so album covers stay album-sized on a wide desktop
      // pane (2 fixed columns blew them up to half the pane each).
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: Space.s3,
        crossAxisSpacing: Space.s3,
      ),
      itemCount: albums.length,
      itemBuilder: (context, i) => AlbumCard(
        album: albums[i],
        onTap: () =>
            ref.read(audioHandlerProvider).playTracks(albums[i].tracks),
      ),
    );
  }
}

/// VLC-style folder browsing: folders that contain music, drill into
/// one to see and play its songs (folder becomes the queue).
class _FoldersTab extends ConsumerStatefulWidget {
  const _FoldersTab({super.key, this.query = '', this.initialOpenPath});

  /// Desktop sidebar deep-link: open this folder immediately.
  final String? initialOpenPath;

  final String query;

  @override
  ConsumerState<_FoldersTab> createState() => _FoldersTabState();
}

class _FoldersTabState extends ConsumerState<_FoldersTab> {
  String? _openPath;

  @override
  void initState() {
    super.initState();
    _openPath = widget.initialOpenPath;
    // System back climbs out of the open folder before leaving the tab.
    BackStack.register(this, () {
      if (_openPath == null) return false;
      setState(() => _openPath = null);
      return true;
    });
  }

  @override
  void dispose() {
    BackStack.unregister(this);
    super.dispose();
  }

  /// Folder → playlist with the folder's name (deduped "Name 2", …) and
  /// its songs in folder order.
  Future<void> _createPlaylistFromFolder(MusicFolder folder) async {
    final existing = ref.read(playlistsProvider).value ?? [];
    var name = folder.name;
    var n = 2;
    while (existing.any((p) => p.name.toLowerCase() == name.toLowerCase())) {
      name = '${folder.name} ${n++}';
    }
    final color =
        playlistCoverColors[existing.length % playlistCoverColors.length];
    await ref.read(playlistsProvider.notifier).createWithTracks(
        name, color.toARGB32(), [for (final t in folder.tracks) t.id]);
    if (mounted) _toast(context, 'Playlist "$name" created 🌸');
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final folders = ref.watch(foldersProvider);
    final q = widget.query.trim().toLowerCase();

    final open = _openPath == null
        ? null
        : folders.where((f) => f.path == _openPath).firstOrNull;

    if (open == null) {
      final visible = folders
          .where((f) => q.isEmpty || f.name.toLowerCase().contains(q))
          .toList();
      if (visible.isEmpty) {
        return _Message(
            q.isEmpty ? 'No folders yet' : 'Nothing matches "${widget.query}"',
            theme: theme);
      }
      return Column(
        key: const ValueKey('folder_list'),
        children: [
          // The long-press affordance was invisible — say it out loud.
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Space.s4, Space.s1, Space.s4, Space.s1),
            child: Text('long-press a folder to turn it into a playlist',
                style: AppText.caption(theme).copyWith(fontSize: 10)),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.s4, vertical: Space.s2),
              itemCount: visible.length,
              itemExtent: Sizes.trackRowHeight,
              itemBuilder: (context, i) => _FolderRow(
                folder: visible[i],
                theme: theme,
                onTap: () => setState(() => _openPath = visible[i].path),
                onCreatePlaylist: () =>
                    _createPlaylistFromFolder(visible[i]),
              ),
            ),
          ),
        ],
      );
    }

    // Inside a folder: header with back + name, then its tracks.
    final playingId = ref.watch(audioStateProvider).value?.currentTrack?.id;
    final tracks = open.tracks
        .where((t) =>
            q.isEmpty ||
            t.title.toLowerCase().contains(q) ||
            t.artist.toLowerCase().contains(q))
        .toList();

    return Column(
      key: ValueKey('folder_${open.path}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s2, Space.s1, Space.s4, 0),
          child: Row(
            children: [
              InkResponse(
                onTap: () => setState(() => _openPath = null),
                radius: 20,
                child: SizedBox(
                  width: Sizes.minTouchTarget,
                  height: Sizes.minTouchTarget,
                  child: Icon(Icons.chevron_left,
                      size: 26, color: theme.textPrimary),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(open.name,
                        style: AppText.rowSongTitle(theme),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(
                      '${open.tracks.length} song${open.tracks.length == 1 ? '' : 's'} · ${open.path}',
                      style: AppText.caption(theme).copyWith(fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.s2),
              InkResponse(
                onTap: () => _createPlaylistFromFolder(open),
                radius: 20,
                child: SizedBox(
                  width: Sizes.minTouchTarget,
                  height: Sizes.minTouchTarget,
                  child: Icon(Icons.playlist_add,
                      size: 22, color: theme.textMuted),
                ),
              ),
              InkResponse(
                onTap: () => ref
                    .read(audioHandlerProvider)
                    .playTracks(open.tracks),
                radius: 22,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: theme.primary, shape: BoxShape.circle),
                  child:
                      const Icon(Icons.play_arrow, color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: tracks.isEmpty
              ? _Message('Nothing matches "${widget.query}"', theme: theme)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Space.s4, vertical: Space.s2),
                  itemCount: tracks.length,
                  itemExtent: Sizes.trackRowHeight,
                  itemBuilder: (context, i) => TrackRow(
                    track: tracks[i],
                    theme: theme,
                    isPlaying: tracks[i].id == playingId,
                    onTap: () => ref
                        .read(audioHandlerProvider)
                        .playTracks(tracks, startIndex: i),
                    onAddToQueue: () {
                      ref
                          .read(audioHandlerProvider)
                          .engine
                          .addToQueue(tracks[i]);
                      _toast(context, 'Added to queue');
                    },
                    onAddToPlaylist: () => showPlaylistPicker(
                        context, ref, theme, tracks[i].id),
                  ),
                ),
        ),
      ],
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.theme,
    required this.onTap,
    this.onCreatePlaylist,
  });

  final MusicFolder folder;
  final HanamimiTheme theme;
  final VoidCallback onTap;

  /// Long-press: folder → playlist.
  final VoidCallback? onCreatePlaylist;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onCreatePlaylist,
        splashColor: theme.primary.withValues(alpha: 0.12),
        highlightColor: theme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.md),
        child: SizedBox(
          height: Sizes.trackRowHeight,
          child: Row(
            children: [
              Container(
                width: Sizes.trackRowArt,
                height: Sizes.trackRowArt,
                decoration: BoxDecoration(
                  color: theme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.folder_outlined,
                    size: 24, color: theme.primary),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(folder.name,
                        style: AppText.rowSongTitle(theme),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      '${folder.tracks.length} song${folder.tracks.length == 1 ? '' : 's'}',
                      style: AppText.rowArtist(theme),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: theme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pinned "Liked songs" collection card — same notebook style as
/// PlaylistCard, with a heart cover on the theme accent.
class _LikedSongsCard extends StatelessWidget {
  const _LikedSongsCard({
    required this.count,
    required this.theme,
    required this.onTap,
  });

  final int count;
  final HanamimiTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.surface,
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: theme.divider, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 80,
                decoration: BoxDecoration(
                  color: theme.accent,
                  borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(Radii.md)),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.favorite,
                    size: 30, color: Colors.white),
              ),
              const SizedBox(width: Space.s4),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Liked songs',
                      style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count track${count == 1 ? '' : 's'}',
                      style: AppText.caption(theme),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.textMuted),
              const SizedBox(width: Space.s3),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistsTab extends ConsumerStatefulWidget {
  const _PlaylistsTab({
    super.key,
    this.query = '',
    this.initialOpenId,
    this.initialLikedOpen = false,
  });

  final String query;

  /// Desktop sidebar deep-link: open this playlist (or liked songs)
  /// immediately. The tab is keyed per request, so a fresh click lands
  /// here as a fresh state.
  final int? initialOpenId;
  final bool initialLikedOpen;

  @override
  ConsumerState<_PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends ConsumerState<_PlaylistsTab> {
  int? _openId;
  bool _likedOpen = false;

  @override
  void initState() {
    super.initState();
    _openId = widget.initialOpenId;
    _likedOpen = widget.initialLikedOpen;
    // System back closes the open playlist / liked-songs detail first.
    BackStack.register(this, () {
      if (_likedOpen) {
        setState(() => _likedOpen = false);
        return true;
      }
      if (_openId != null) {
        setState(() => _openId = null);
        return true;
      }
      return false;
    });
  }

  @override
  void dispose() {
    BackStack.unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final q = widget.query.trim().toLowerCase();
    final all = ref.watch(playlistsProvider).value ?? [];

    if (_likedOpen) return _buildLikedDetail(theme, q);
    final open =
        _openId == null ? null : all.where((p) => p.id == _openId).firstOrNull;
    if (open != null) return _buildDetail(open, theme, q);

    final playlists = all
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .toList();
    final likedCount = (ref.watch(libraryProvider).value ?? [])
        .where((t) => t.liked)
        .length;

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.all(Space.s4),
          // Slot 0 is the pinned Liked-songs collection; likes had no
          // home before — hearts were stored but nowhere to see them.
          itemCount: playlists.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: Space.s3),
          itemBuilder: (context, i) {
            if (i == 0) {
              final card = _LikedSongsCard(
                count: likedCount,
                theme: theme,
                onTap: () => setState(() => _likedOpen = true),
              );
              // The duck struts along the top edge of the pinned card
              // — anchored to furniture like the cat and parrot, not
              // floating in the whitespace.
              if (!ref.watch(buddyEnabledProvider('duck'))) return card;
              return Padding(
                padding: const EdgeInsets.only(top: Space.s2),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    card,
                    const Positioned(
                        left: 10,
                        right: 10,
                        top: -17,
                        child: PlaylistsDuck(size: 22)),
                  ],
                ),
              );
            }
            final playlist = playlists[i - 1];
            return PlaylistCard(
              playlist: playlist,
              theme: theme,
              onTap: () => setState(() => _openId = playlist.id),
            );
          },
        ),
        Positioned(
          right: Space.s4,
          bottom: Space.s4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Import a YouTube / Spotify playlist by link (M30, plus).
              FloatingActionButton.small(
                heroTag: 'import_playlist',
                backgroundColor: theme.surface,
                foregroundColor: theme.primary,
                elevation: 2,
                shape: const StadiumBorder(),
                onPressed: () => showImportPlaylistSheet(context),
                child: const Icon(Icons.link),
              ),
              const SizedBox(height: Space.s2),
              FloatingActionButton.extended(
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
            ],
          ),
        ),
      ],
    );
  }

  ///   /// Liked-songs detail: every liked track, newest hearts included the
  /// moment they're tapped (the list watches the library). Unlike is
  /// done from the heart itself, so no swipe actions here.
  Widget _buildLikedDetail(HanamimiTheme theme, String q) {
    final liked = (ref.watch(libraryProvider).value ?? [])
        .where((t) => t.liked)
        .toList();
    final visible = liked
        .where((t) =>
            q.isEmpty ||
            t.title.toLowerCase().contains(q) ||
            t.artist.toLowerCase().contains(q))
        .toList();
    final playingId = ref.watch(audioStateProvider).value?.currentTrack?.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s2, Space.s1, Space.s4, 0),
          child: Row(
            children: [
              InkResponse(
                onTap: () => setState(() => _likedOpen = false),
                radius: 20,
                child: SizedBox(
                  width: Sizes.minTouchTarget,
                  height: Sizes.minTouchTarget,
                  child: Icon(Icons.chevron_left,
                      size: 26, color: theme.textPrimary),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: theme.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.favorite,
                    size: 18, color: Colors.white),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Liked songs',
                        style: AppText.rowSongTitle(theme)),
                    Text(
                      '${liked.length} song${liked.length == 1 ? '' : 's'}',
                      style: AppText.caption(theme),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.s2),
        Expanded(
          child: visible.isEmpty
              ? _Message(
                  q.isEmpty
                      ? 'Tap the heart on a song to keep it here'
                      : 'Nothing matches "${widget.query}"',
                  theme: theme)
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: Space.s4),
                  itemCount: visible.length,
                  itemExtent: Sizes.trackRowHeight,
                  itemBuilder: (context, i) => TrackRow(
                    track: visible[i],
                    theme: theme,
                    isPlaying: visible[i].id == playingId,
                    onTap: () => ref
                        .read(audioHandlerProvider)
                        .playTracks(visible, startIndex: i),
                  ),
                ),
        ),
      ],
    );
  }

  /// Queue every online track in the playlist that isn't saved offline
  /// yet, at the chosen quality — no more downloading songs one by one.
  Future<void> _downloadAll(List<Track> tracks, HanamimiTheme theme) async {
    final pending = [
      for (final t in tracks)
        if (!t.isLocal && !t.isPlayableOffline) t,
    ];
    if (pending.isEmpty) return;
    final quality = await resolveDownloadQuality(context, ref);
    if (quality == null || !mounted) return; // cancelled
    for (final t in pending) {
      ref.read(downloadManagerProvider.notifier).enqueue(t, quality);
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md)),
      content: Text(
        'Downloading ${pending.length} song${pending.length == 1 ? '' : 's'} — see the Downloads tab 🐰',
        style: const TextStyle(fontFamily: 'Nunito'),
      ),
    ));
  }

  /// Playlist detail: header (play all, delete), tracks in playlist
  /// order. Swipe a row left to remove it from the playlist.
  Widget _buildDetail(Playlist playlist, HanamimiTheme theme, String q) {
    final allTracks = ref.watch(libraryProvider).value ?? [];
    final byId = {for (final t in allTracks) t.id: t};
    final tracks = [
      for (final id in playlist.trackIds)
        if (byId[id] != null) byId[id]!,
    ];
    final visible = tracks
        .where((t) =>
            q.isEmpty ||
            t.title.toLowerCase().contains(q) ||
            t.artist.toLowerCase().contains(q))
        .toList();
    final playingId = ref.watch(audioStateProvider).value?.currentTrack?.id;

    // Hero header (community ask): big collage cover, name, meta and
    // the action row — the playlist as a place, not just a list.
    final totalDur = tracks.fold(Duration.zero, (d, t) => d + t.duration);
    final totalLabel = totalDur.inHours > 0
        ? '${totalDur.inHours}h ${totalDur.inMinutes.remainder(60)}m'
        : '${totalDur.inMinutes} min';
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s4),
      child: Column(
        children: [
          // Tap the cover to pick a custom image (or reset it).
          GestureDetector(
            onTap: () => _pickCover(playlist, theme),
            child:
                PlaylistCover(playlist: playlist, size: 180, fontSize: 56),
          ),
          const SizedBox(height: Space.s4),
          Text(playlist.name,
              style: AppText.screenTitle(theme),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: Space.s1),
          Text(
            '${tracks.length} song${tracks.length == 1 ? '' : 's'} · $totalLabel',
            style: AppText.caption(theme),
          ),
          Text('swipe left to remove · hold to reorder',
              style: AppText.caption(theme).copyWith(fontSize: 10)),
          const SizedBox(height: Space.s3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Online tracks not yet saved offline → "download all".
              if (tracks.any((t) => !t.isLocal && !t.isPlayableOffline))
                InkResponse(
                  onTap: () => _downloadAll(tracks, theme),
                  radius: 22,
                  child: SizedBox(
                    width: Sizes.minTouchTarget,
                    height: Sizes.minTouchTarget,
                    child: Icon(Icons.download_for_offline_outlined,
                        size: 24, color: theme.textMuted),
                  ),
                ),
              const SizedBox(width: Space.s4),
              InkResponse(
                onTap: tracks.isEmpty
                    ? null
                    : () {
                        final handler = ref.read(audioHandlerProvider);
                        handler.playTracks(tracks);
                        handler.engine.setMode(QueueMode.shuffle);
                      },
                radius: 22,
                child: SizedBox(
                  width: Sizes.minTouchTarget,
                  height: Sizes.minTouchTarget,
                  child:
                      Icon(Icons.shuffle, size: 24, color: theme.textMuted),
                ),
              ),
              const SizedBox(width: Space.s4),
              InkResponse(
                onTap: tracks.isEmpty
                    ? null
                    : () =>
                        ref.read(audioHandlerProvider).playTracks(tracks),
                radius: 30,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                      color: theme.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white, size: 32),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s2, Space.s1, Space.s4, 0),
          child: Row(
            children: [
              InkResponse(
                onTap: () => setState(() => _openId = null),
                radius: 20,
                child: SizedBox(
                  width: Sizes.minTouchTarget,
                  height: Sizes.minTouchTarget,
                  child: Icon(Icons.chevron_left,
                      size: 26, color: theme.textPrimary),
                ),
              ),
              const Spacer(),
              InkResponse(
                onTap: () => _confirmDeletePlaylist(playlist, theme),
                radius: 20,
                child: SizedBox(
                  width: Sizes.minTouchTarget,
                  height: Sizes.minTouchTarget,
                  child: Icon(Icons.delete_outline,
                      size: 20, color: theme.textMuted),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? Column(
                  children: [
                    header,
                    Expanded(
                      child: _Message(
                          q.isEmpty
                              ? 'Nothing here yet — swipe a song left in Songs and pick "${playlist.name}"'
                              : 'Nothing matches "${widget.query}"',
                          theme: theme),
                    ),
                  ],
                )
              // Long-press drag to reorder — but only on the unfiltered
              // list, where row indices match playlist positions.
              : ReorderableListView.builder(
                  header: header,
                  buildDefaultDragHandles: q.isEmpty,
                  onReorder: (oldIndex, newIndex) {
                    if (q.isNotEmpty) return;
                    if (newIndex > oldIndex) newIndex--;
                    ref
                        .read(playlistsProvider.notifier)
                        .reorderTrack(playlist.id, oldIndex, newIndex);
                  },
                  proxyDecorator: (child, _, __) => Material(
                      color: Colors.transparent,
                      elevation: 4,
                      borderRadius: BorderRadius.circular(Radii.md),
                      child: child),
                  padding: const EdgeInsets.symmetric(
                      horizontal: Space.s4, vertical: Space.s2),
                  itemCount: visible.length,
                  itemExtent: Sizes.trackRowHeight,
                  itemBuilder: (context, i) => KeyedSubtree(
                    key: ValueKey('pl_${playlist.id}_${visible[i].id}'),
                    child: TrackRow(
                      track: visible[i],
                      theme: theme,
                      isPlaying: visible[i].id == playingId,
                      // Clear the desktop reorder handle that overlays the
                      // trailing edge (only shown when q.isEmpty).
                      trailingReserve: isDesktop && q.isEmpty ? 40 : 0,
                      onTap: () => ref
                          .read(audioHandlerProvider)
                          .playTracks(visible, startIndex: i),
                      onAddToQueue: () {
                        ref
                            .read(audioHandlerProvider)
                            .engine
                            .addToQueue(visible[i]);
                        _toast(context, 'Added to queue');
                      },
                      onRemove: () {
                        ref
                            .read(playlistsProvider.notifier)
                            .removeTrack(playlist.id, visible[i].id);
                        _toast(context, 'Removed from ${playlist.name}');
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// Cover picker: gallery image (copied into app storage so the pick
  /// survives the gallery cleaning caches) or back to the collage.
  Future<void> _pickCover(Playlist playlist, HanamimiTheme theme) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.image_outlined, color: theme.textPrimary),
              title: Text('Choose cover image', style: AppText.body(theme)),
              onTap: () => Navigator.pop(sheetContext, 'pick'),
            ),
            if (playlist.coverImagePath != null)
              ListTile(
                leading:
                    Icon(Icons.restart_alt, color: theme.textPrimary),
                title: Text('Back to song-art cover',
                    style: AppText.body(theme)),
                onTap: () => Navigator.pop(sheetContext, 'reset'),
              ),
          ],
        ),
      ),
    );
    if (action == 'reset') {
      await ref.read(playlistsProvider.notifier).setCover(playlist.id, null);
      return;
    }
    if (action != 'pick') return;

    // Android Photo Picker on mobile; a plain file dialog on desktop.
    final String? pickedPath;
    if (Platform.isAndroid) {
      final picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, maxWidth: 1024);
      pickedPath = picked?.path;
    } else {
      final picked = await openFile(acceptedTypeGroups: const [
        XTypeGroup(
            label: 'Images', extensions: ['jpg', 'jpeg', 'png', 'webp']),
      ]);
      pickedPath = picked?.path;
    }
    if (pickedPath == null) return;
    final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/playlist_covers');
    await dir.create(recursive: true);
    // Unique name per pick — reusing one path would keep showing the old
    // image from the decode cache.
    final dest =
        '${dir.path}/${playlist.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(pickedPath).copy(dest);
    final old = playlist.coverImagePath;
    await ref.read(playlistsProvider.notifier).setCover(playlist.id, dest);
    if (old != null) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
  }

  void _confirmDeletePlaylist(Playlist playlist, HanamimiTheme theme) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.lg)),
        title: Text('Delete "${playlist.name}"?',
            style: AppText.rowSongTitle(theme)),
        content: Text('The songs themselves stay in your library.',
            style: AppText.caption(theme)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Keep',
                style: AppText.button(theme)
                    .copyWith(color: theme.textMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              setState(() => _openId = null);
              ref.read(playlistsProvider.notifier).delete(playlist.id);
            },
            child: Text('Delete',
                style:
                    AppText.button(theme).copyWith(color: theme.accent)),
          ),
        ],
      ),
    );
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 1),
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md)),
    content:
        Text(message, style: const TextStyle(fontFamily: 'Nunito')),
  ));
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
