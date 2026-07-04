import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/playlist.dart';
import '../../library/models/track.dart';
import '../../online/models/online_search_result.dart';
import '../../providers/audio_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/online_provider.dart';
import '../../providers/online_settings_provider.dart';
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
  bool _searching = false;
  String _query = '';

  /// 0 = Library; 1.. index into [registeredOnlineSources].
  int _searchScope = 0;

  /// Debounced (400 ms) copy of the query for online scopes, so typing
  /// doesn't fire a provider request per keystroke.
  String _onlineQuery = '';
  Timer? _debounce;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    setState(() => _query = q);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _onlineQuery = q);
    });
  }

  void _closeSearch() {
    _debounce?.cancel();
    setState(() {
      _searching = false;
      _query = '';
      _onlineQuery = '';
      _searchScope = 0;
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    // Online off ⇒ no provider scopes; search stays library-only.
    final onlineSources = ref.watch(onlineEnabledProvider)
        ? registeredOnlineSources
        : const <TrackSource>[];
    final onlineScope = _searching && _searchScope > 0
        ? onlineSources[_searchScope - 1]
        : null;

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
                              hintText: onlineScope == null
                                  ? 'Search your music…'
                                  : 'Search ${onlineSourceLabels[onlineScope]}…',
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
                      Text('Hanamimi',
                          style: AppText.screenTitle(theme)
                              .copyWith(fontSize: 22)),
                      const SizedBox(height: Space.s3),
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
                                  ref.watch(onlineEnabledProvider)
                                      ? 'Search your music, YouTube & JioSaavn'
                                      : 'Search your music…',
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
            // While searching the pills become the search scope:
            // Library | YouTube | JioSaavn (ARCHITECTURE-ONLINE.md §9).
            child: PillTabBar(
              tabs: _searching
                  ? [
                      'Library',
                      for (final s in onlineSources) onlineSourceLabels[s]!,
                    ]
                  : const ['Songs', 'Albums', 'Folders', 'Playlists'],
              activeIndex: _searching ? _searchScope : _tab,
              onChanged: (i) => setState(() {
                if (_searching) {
                  _searchScope = i;
                } else {
                  _tab = i;
                }
              }),
              theme: theme,
            ),
          ),
          const SizedBox(height: Space.s2),
          Expanded(
            child: AnimatedSwitcher(
              duration: Anim.minTransition,
              child: onlineScope != null
                  ? _OnlineSearchTab(
                      key: ValueKey('online_${onlineScope.name}'),
                      source: onlineScope,
                      query: _onlineQuery,
                    )
                  : switch (_tab) {
                      0 => _SongsTab(key: const ValueKey(0), query: _query),
                      1 => _AlbumsTab(key: const ValueKey(1), query: _query),
                      2 => _FoldersTab(key: const ValueKey(2), query: _query),
                      _ => _PlaylistsTab(key: const ValueKey(3), query: _query),
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
        final q = query.trim().toLowerCase();
        final tracks = q.isEmpty
            ? allTracks
            : allTracks
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
                  _showPlaylistPicker(context, ref, theme, tracks[i].id),
            ),
          ),
        );
      },
    );
  }
}

/// Provider search results as track rows with a cloud badge. Tap /
/// swipe materializes the result into a real library row first
/// (ensureOnlineTrack), so likes, play counts and playlists just work.
class _OnlineSearchTab extends ConsumerWidget {
  const _OnlineSearchTab({
    super.key,
    required this.source,
    required this.query,
  });

  final TrackSource source;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final label = onlineSourceLabels[source]!;
    if (query.trim().length < 2) {
      return _Message('Type to search $label', theme: theme);
    }

    final results =
        ref.watch(onlineSearchProvider((source: source, query: query)));
    return results.when(
      loading: () => Center(
          child: CircularProgressIndicator(color: theme.primary)),
      error: (_, __) =>
          _Message('$label is unavailable right now', theme: theme),
      data: (hits) {
        if (hits.isEmpty) {
          return _Message('Nothing matches "$query"', theme: theme);
        }
        final playing = ref.watch(audioStateProvider).value?.currentTrack;
        return ListView.builder(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.s4, vertical: Space.s2),
          itemCount: hits.length,
          itemExtent: Sizes.trackRowHeight,
          itemBuilder: (context, i) {
            final hit = hits[i];
            return TrackRow(
              // Display-only stand-in; the real row is created on tap.
              track: Track(
                id: -1,
                title: hit.title,
                artist: hit.artist,
                album: hit.album,
                duration: hit.duration,
                source: hit.source,
                sourceId: hit.sourceId,
                artUrl: hit.artUrl,
              ),
              theme: theme,
              isPlaying: playing?.source == hit.source &&
                  playing?.sourceId == hit.sourceId,
              onTap: () => _play(ref, hit),
              onAddToQueue: () => _queue(context, ref, hit),
              onAddToPlaylist: () => _playlist(context, ref, theme, hit),
            );
          },
        );
      },
    );
  }

  Future<void> _play(WidgetRef ref, OnlineSearchResult hit) async {
    final track =
        await ref.read(libraryProvider.notifier).ensureOnlineTrack(hit);
    await ref.read(audioHandlerProvider).playTracks([track]);
  }

  Future<void> _queue(
      BuildContext context, WidgetRef ref, OnlineSearchResult hit) async {
    final track =
        await ref.read(libraryProvider.notifier).ensureOnlineTrack(hit);
    await ref.read(audioHandlerProvider).engine.addToQueue(track);
    if (context.mounted) _toast(context, 'Added to queue');
  }

  Future<void> _playlist(BuildContext context, WidgetRef ref,
      HanamimiTheme theme, OnlineSearchResult hit) async {
    final track =
        await ref.read(libraryProvider.notifier).ensureOnlineTrack(hit);
    if (context.mounted) _showPlaylistPicker(context, ref, theme, track.id);
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
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
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
  const _FoldersTab({super.key, this.query = ''});

  final String query;

  @override
  ConsumerState<_FoldersTab> createState() => _FoldersTabState();
}

class _FoldersTabState extends ConsumerState<_FoldersTab> {
  String? _openPath;

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
      return ListView.builder(
        key: const ValueKey('folder_list'),
        padding: const EdgeInsets.symmetric(
            horizontal: Space.s4, vertical: Space.s2),
        itemCount: visible.length,
        itemExtent: Sizes.trackRowHeight,
        itemBuilder: (context, i) => _FolderRow(
          folder: visible[i],
          theme: theme,
          onTap: () => setState(() => _openPath = visible[i].path),
        ),
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
                    onAddToPlaylist: () => _showPlaylistPicker(
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
  });

  final MusicFolder folder;
  final HanamimiTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
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

class _PlaylistsTab extends ConsumerStatefulWidget {
  const _PlaylistsTab({super.key, this.query = ''});

  final String query;

  @override
  ConsumerState<_PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends ConsumerState<_PlaylistsTab> {
  int? _openId;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final q = widget.query.trim().toLowerCase();
    final all = ref.watch(playlistsProvider).value ?? [];

    final open =
        _openId == null ? null : all.where((p) => p.id == _openId).firstOrNull;
    if (open != null) return _buildDetail(open, theme, q);

    final playlists = all
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .toList();

    return Stack(
      children: [
        if (playlists.isEmpty)
          _Message(
              q.isEmpty
                  ? 'No playlists yet — make one!'
                  : 'Nothing matches "${widget.query}"',
              theme: theme)
        else
          ListView.separated(
            padding: const EdgeInsets.all(Space.s4),
            itemCount: playlists.length,
            separatorBuilder: (_, __) => const SizedBox(height: Space.s3),
            itemBuilder: (context, i) => PlaylistCard(
              playlist: playlists[i],
              theme: theme,
              onTap: () => setState(() => _openId = playlists[i].id),
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
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: playlist.coverColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  playlist.name.isEmpty
                      ? '♪'
                      : playlist.name[0].toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(playlist.name,
                        style: AppText.rowSongTitle(theme),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(
                      '${tracks.length} song${tracks.length == 1 ? '' : 's'} · swipe left to remove',
                      style: AppText.caption(theme).copyWith(fontSize: 10),
                    ),
                  ],
                ),
              ),
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
              InkResponse(
                onTap: tracks.isEmpty
                    ? null
                    : () =>
                        ref.read(audioHandlerProvider).playTracks(tracks),
                radius: 22,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: theme.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.play_arrow,
                      color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? _Message(
                  q.isEmpty
                      ? 'Nothing here yet — swipe a song left in Songs and pick "${playlist.name}"'
                      : 'Nothing matches "${widget.query}"',
                  theme: theme)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Space.s4, vertical: Space.s2),
                  itemCount: visible.length,
                  itemExtent: Sizes.trackRowHeight,
                  itemBuilder: (context, i) => TrackRow(
                    track: visible[i],
                    theme: theme,
                    isPlaying: visible[i].id == playingId,
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
      ],
    );
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

Future<void> _showPlaylistPicker(
    BuildContext context, WidgetRef ref, HanamimiTheme theme, int trackId) async {
  // ref.read gives AsyncLoading if the Playlists tab was never opened
  // this session — await the future so existing playlists always show.
  final playlists = await ref.read(playlistsProvider.future);
  if (!context.mounted) return;
  if (playlists.isEmpty) {
    _toast(context, 'No playlists yet — make one first!');
    return;
  }
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add to playlist',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.textPrimary)),
            const SizedBox(height: Space.s3),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: playlists.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: Space.s3),
                itemBuilder: (context, i) => PlaylistCard(
                  playlist: playlists[i],
                  theme: theme,
                  onTap: () {
                    ref
                        .read(playlistsProvider.notifier)
                        .addTrack(playlists[i].id, trackId);
                    Navigator.pop(sheetContext);
                    _toast(context, 'Added to ${playlists[i].name}');
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
