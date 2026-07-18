import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import '../library/models/track.dart';
import '../platform/web/web_library.dart';
import '../platform/web/web_media.dart';
import '../utils/track_identity.dart';
import 'theme_provider.dart';

/// The web library: whatever folders/files the visitor picked this
/// session, in memory only — blob URLs die with the tab, so there is
/// nothing to persist except the likes (kept by song identity, so
/// re-picking the same folder next visit lights the same hearts).
class WebLibraryNotifier extends Notifier<List<WebFolder>> {
  static const _likedKey = 'web_liked_songs';

  @override
  List<WebFolder> build() => const [];

  Set<String> get _likedKeys =>
      (ref.read(sharedPrefsProvider).getStringList(_likedKey) ?? const [])
          .toSet();

  /// Folder picker → one sidebar group per pick. Returns the number of
  /// tracks imported, or null when the user cancelled the picker.
  Future<int?> addFolder() async {
    final files = await WebMedia.pickFolder();
    if (files == null) return null;
    return _import(files, folderNameFrom(files));
  }

  /// Loose files → they gather in a "Picked songs" group.
  Future<int?> addFiles() async {
    final files = await WebMedia.pickFiles();
    if (files == null) return null;
    return _import(files, 'Picked songs');
  }

  Future<int> _import(List<web.File> files, String name) async {
    if (files.isEmpty) return 0;
    ref
        .read(importProgressProvider.notifier)
        .set(ImportProgress(0, files.length));
    final liked = _likedKeys;
    var tracks = await WebImporter.import(
      files,
      onProgress: (p) => ref.read(importProgressProvider.notifier).set(p),
    );
    tracks = [
      for (final t in tracks)
        liked.contains(_identity(t)) ? t.copyWith(liked: true) : t,
    ];
    ref.read(importProgressProvider.notifier).set(null);

    // Re-picking the same folder replaces it instead of stacking a twin.
    final existing = state.indexWhere((f) => f.name == name);
    if (existing >= 0) {
      state = [
        for (var i = 0; i < state.length; i++)
          i == existing ? WebFolder(name: name, tracks: tracks) : state[i],
      ];
    } else {
      state = [...state, WebFolder(name: name, tracks: tracks)];
    }
    return tracks.length;
  }

  void removeFolder(String name) {
    for (final f in state.where((f) => f.name == name)) {
      for (final t in f.tracks) {
        WebMedia.revoke(t.filePath);
      }
    }
    state = [for (final f in state) if (f.name != name) f];
  }

  void toggleLiked(Track track) {
    final nowLiked = !track.liked;
    state = [
      for (final f in state)
        WebFolder(name: f.name, tracks: [
          for (final t in f.tracks)
            t.id == track.id ? t.copyWith(liked: nowLiked) : t,
        ]),
    ];
    final keys = _likedKeys;
    final key = _identity(track);
    nowLiked ? keys.add(key) : keys.remove(key);
    ref
        .read(sharedPrefsProvider)
        .setStringList(_likedKey, keys.toList()..sort());
  }

  static String _identity(Track t) => identityKey(
      title: t.title, artist: t.artist, duration: t.duration);

  /// The webkitdirectory picker keeps each file's relative path; the
  /// first path segment is the folder the user actually chose.
  static String folderNameFrom(List<web.File> files) {
    for (final f in files) {
      final rel = f.webkitRelativePath;
      final slash = rel.indexOf('/');
      if (slash > 0) return rel.substring(0, slash);
    }
    return 'Music';
  }
}

final webLibraryProvider =
    NotifierProvider<WebLibraryNotifier, List<WebFolder>>(
        WebLibraryNotifier.new);

/// Live import progress, null when idle — the importer pushes, the
/// sidebar chip watches.
class ImportProgressNotifier extends Notifier<ImportProgress?> {
  @override
  ImportProgress? build() => null;

  void set(ImportProgress? value) => state = value;
}

final importProgressProvider =
    NotifierProvider<ImportProgressNotifier, ImportProgress?>(
        ImportProgressNotifier.new);

/// Every imported track, flat — the "play all" / shuffle-all source.
final allTracksProvider = Provider<List<Track>>((ref) => [
      for (final folder in ref.watch(webLibraryProvider)) ...folder.tracks,
    ]);

/// The freshest copy of a track (its liked flag lives here, not in the
/// audio snapshot).
final libraryTrackProvider = Provider.family<Track, Track>((ref, track) {
  for (final folder in ref.watch(webLibraryProvider)) {
    for (final t in folder.tracks) {
      if (t.id == track.id) return t;
    }
  }
  return track;
});
