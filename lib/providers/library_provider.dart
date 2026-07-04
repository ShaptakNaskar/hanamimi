import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_repository.dart';
import '../library/library_scanner.dart';
import '../library/models/playlist.dart';
import '../library/models/track.dart';
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
}

final playlistsProvider =
    AsyncNotifierProvider<PlaylistsNotifier, List<Playlist>>(
        PlaylistsNotifier.new);
