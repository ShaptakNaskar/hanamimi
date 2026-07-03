import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/library_repository.dart';
import '../library/library_scanner.dart';
import '../library/models/playlist.dart';
import '../library/models/track.dart';

final libraryRepositoryProvider = FutureProvider<LibraryRepository>(
  (ref) => LibraryRepository.open(),
);

/// All tracks in the library. First read triggers a device scan if the
/// DB is empty; `rescan()` is the user-facing refresh.
class LibraryNotifier extends AsyncNotifier<List<Track>> {
  bool _permissionDenied = false;
  bool get permissionDenied => _permissionDenied;

  @override
  Future<List<Track>> build() async {
    final repo = await ref.watch(libraryRepositoryProvider.future);
    var tracks = await repo.allTracks();
    if (tracks.isEmpty) {
      final result = await LibraryScanner(repo).scan();
      _permissionDenied = result == ScanResult.permissionDenied;
      tracks = await repo.allTracks();
    }
    return tracks;
  }

  Future<void> rescan() async {
    final repo = await ref.read(libraryRepositoryProvider.future);
    final result = await LibraryScanner(repo).scan();
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

/// Albums derived from the track list, sorted by title.
final albumsProvider = Provider<List<Album>>((ref) {
  final tracks = ref.watch(libraryProvider).value ?? [];
  final byAlbum = <int, List<Track>>{};
  for (final t in tracks) {
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
}

final playlistsProvider =
    AsyncNotifierProvider<PlaylistsNotifier, List<Playlist>>(
        PlaylistsNotifier.new);
