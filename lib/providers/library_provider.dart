import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_repository.dart';
import '../library/library_scanner.dart';
import '../library/models/playlist.dart';
import '../library/models/track.dart';
import '../online/models/online_search_result.dart';
import '../online/online_art_cache.dart';
import 'theme_provider.dart';

final libraryRepositoryProvider = FutureProvider<LibraryRepository>(
  (ref) => LibraryRepository.open(),
);

/// Directories excluded from the library scan. Persisted; edits apply
/// on the next (re)scan.
class ExcludedFoldersNotifier extends Notifier<Set<String>> {
  static const _key = 'excluded_folders';

  @override
  Set<String> build() =>
      ref.watch(sharedPrefsProvider).getStringList(_key)?.toSet() ?? {};

  void toggle(String path) {
    state = state.contains(path)
        ? ({...state}..remove(path))
        : {...state, path};
    ref.read(sharedPrefsProvider).setStringList(_key, state.toList());
  }
}

final excludedFoldersProvider =
    NotifierProvider<ExcludedFoldersNotifier, Set<String>>(
        ExcludedFoldersNotifier.new);

/// All tracks in the library. First read triggers a device scan if the
/// DB is empty; `rescan()` is the user-facing refresh.
class LibraryNotifier extends AsyncNotifier<List<Track>> {
  bool _permissionDenied = false;
  bool get permissionDenied => _permissionDenied;

  LibraryScanner _scanner(LibraryRepository repo) => LibraryScanner(
        repo,
        excludedDirs: ref.read(excludedFoldersProvider),
      );

  @override
  Future<List<Track>> build() async {
    final repo = await ref.watch(libraryRepositoryProvider.future);
    var tracks = await repo.allTracks();
    if (tracks.isEmpty) {
      final result = await _scanner(repo).scan();
      _permissionDenied = result == ScanResult.permissionDenied;
      tracks = await repo.allTracks();
    }
    return tracks;
  }

  Future<void> rescan() async {
    final repo = await ref.read(libraryRepositoryProvider.future);
    final result = await _scanner(repo).scan();
    _permissionDenied = result == ScanResult.permissionDenied;
    state = AsyncData(await repo.allTracks());
  }

  /// Materializes an online search result into a real library row
  /// (play/queue/playlist all call this first) and keeps the in-memory
  /// list in sync. Remote art is cached to disk in the background.
  Future<Track> ensureOnlineTrack(OnlineSearchResult result) async {
    final repo = await ref.read(libraryRepositoryProvider.future);
    final track = await repo.ensureOnlineTrack(result);

    final current = state.value ?? <Track>[];
    if (!current.any((t) => t.id == track.id)) {
      state = AsyncData([...current, track]
        ..sort((a, b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase())));
    }

    if (track.albumArtPath == null && track.artUrl != null) {
      unawaited(OnlineArtCache.fetch(
              track.artUrl!, '${track.source.name}_${track.sourceId}')
          .then((path) async {
        if (path == null) return;
        await repo.setTrackArt(track.id, path);
        state = AsyncData([
          for (final t in state.value ?? <Track>[])
            t.id == track.id ? t.copyWith(albumArtPath: path) : t,
        ]);
      }));
    }
    return track;
  }

  /// Reflects a finished download (DownloadManager already wrote the
  /// file + DB row) into the in-memory list.
  void markDownloaded(int trackId, String path) {
    state = AsyncData([
      for (final t in state.value ?? <Track>[])
        t.id == trackId ? t.copyWith(filePath: path) : t,
    ]);
  }

  /// Deletes a downloaded file and reverts the track to streaming.
  Future<void> removeDownload(Track track) async {
    final path = track.filePath;
    if (track.isLocal || path == null) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Losing the file is the goal; a failed delete shouldn't strand
      // the row pointing at it either way.
    }
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.setFilePath(track.id, null);
    state = AsyncData([
      for (final t in state.value ?? <Track>[])
        t.id == track.id ? t.copyWith(clearFilePath: true) : t,
    ]);
  }

  Future<void> toggleLiked(Track track) async {
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.setLiked(track.id, !track.liked);
    state = AsyncData([
      for (final t in state.value ?? <Track>[])
        t.id == track.id ? t.copyWith(liked: !track.liked) : t,
    ]);
  }
}

final libraryProvider =
    AsyncNotifierProvider<LibraryNotifier, List<Track>>(LibraryNotifier.new);

/// Albums derived from the track list, sorted by title. MediaStore-only
/// by definition — online tracks never group into albums here.
final albumsProvider = Provider<List<Album>>((ref) {
  final tracks = ref.watch(libraryProvider).value ?? [];
  final byAlbum = <int, List<Track>>{};
  for (final t in tracks) {
    if (!t.isLocal) continue;
    byAlbum.putIfAbsent(t.albumId, () => []).add(t);
  }
  final albums = byAlbum.entries.map((e) {
    final ts = [...e.value]..sort(
        (a, b) => (a.trackNumber ?? 0).compareTo(b.trackNumber ?? 0));
    return Album(
      albumId: e.key,
      title: ts.first.album,
      artist: ts.first.artist,
      artPath: ts.firstWhere((t) => t.albumArtPath != null, orElse: () => ts.first).albumArtPath,
      tracks: ts,
    );
  }).toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return albums;
});

/// Folders that directly contain music, grouped by each track's parent
/// directory and sorted by name.
final foldersProvider = Provider<List<MusicFolder>>((ref) {
  final tracks = ref.watch(libraryProvider).value ?? [];
  final byDir = <String, List<Track>>{};
  for (final t in tracks) {
    // MediaStore-only: downloaded online tracks live in app-private
    // storage and don't belong in folder browsing.
    final path = t.filePath;
    if (!t.isLocal || path == null) continue;
    final slash = path.lastIndexOf('/');
    final dir = slash <= 0 ? '/' : path.substring(0, slash);
    byDir.putIfAbsent(dir, () => []).add(t);
  }
  final folders = byDir.entries.map((e) {
    final name = e.key.substring(e.key.lastIndexOf('/') + 1);
    return MusicFolder(
      path: e.key,
      name: name.isEmpty ? '/' : name,
      tracks: e.value,
    );
  }).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return folders;
});

class PlaylistsNotifier extends AsyncNotifier<List<Playlist>> {
  @override
  Future<List<Playlist>> build() async {
    final repo = await ref.watch(libraryRepositoryProvider.future);
    return repo.allPlaylists();
  }

  Future<void> create(String name, int coverColor) async {
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.createPlaylist(name, coverColor);
    state = AsyncData(await repo.allPlaylists());
  }

  Future<void> addTrack(int playlistId, int trackId) async {
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.addToPlaylist(playlistId, trackId);
    state = AsyncData(await repo.allPlaylists());
  }

  Future<void> removeTrack(int playlistId, int trackId) async {
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.removeFromPlaylist(playlistId, trackId);
    state = AsyncData(await repo.allPlaylists());
  }

  Future<void> delete(int playlistId) async {
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.deletePlaylist(playlistId);
    state = AsyncData(await repo.allPlaylists());
  }

  /// Creates a playlist from imported online results (M30). Each result
  /// is materialized into a real library row (ensureOnlineTrack) then
  /// linked, in order. Returns the new playlist id.
  Future<int> importPlaylist(
      String name, int coverColor, List<OnlineSearchResult> results) async {
    final repo = await ref.read(libraryRepositoryProvider.future);
    final id = await repo.createPlaylist(name, coverColor);
    final library = ref.read(libraryProvider.notifier);
    for (final r in results) {
      final track = await library.ensureOnlineTrack(r);
      await repo.addToPlaylist(id, track.id);
    }
    state = AsyncData(await repo.allPlaylists());
    return id;
  }
}

final playlistsProvider =
    AsyncNotifierProvider<PlaylistsNotifier, List<Playlist>>(
        PlaylistsNotifier.new);
