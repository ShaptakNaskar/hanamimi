import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import '../platform/desktop/desktop_library.dart';
import 'library_repository.dart';
import 'media_store_channel.dart';

enum ScanResult { done, permissionDenied }

/// Orchestrates a library scan: permission → track query → DB sync
/// → album art extraction for any albums still missing art.
///
/// The query is the platform seam (ARCHITECTURE-DESKTOP.md §4): Android
/// asks MediaStore, desktop walks the user's music folders with ffprobe.
/// Everything downstream (sync, prune, art) is shared.
class LibraryScanner {
  LibraryScanner(
    this._repo, {
    this.excludedDirs = const {},
    this.musicFolders = const {},
  });

  final LibraryRepository _repo;

  /// Directories the user opted out of; tracks directly inside them are
  /// dropped from the scan, which also removes their existing DB rows via
  /// the sync's disappeared-file cleanup. Subfolders are separate entries
  /// in the Folders tab, so they hide independently — hiding Downloads
  /// must not take Downloads/Music/Album with it.
  final Set<String> excludedDirs;

  /// Desktop only: the folders the user pointed the library at (VLC-style
  /// "add folder"). Ignored on Android, where MediaStore is the index.
  final Set<String> musicFolders;

  bool _isExcluded(String filePath) {
    final slash = filePath.lastIndexOf('/');
    final dir = slash <= 0 ? '/' : filePath.substring(0, slash);
    return excludedDirs.contains(dir);
  }

  Future<bool> requestPermission() async {
    // Desktop reads plain files the user pointed us at — nothing to ask.
    if (!Platform.isAndroid) return true;
    // permission_handler maps Permission.audio to READ_MEDIA_AUDIO on
    // API 33+ and to READ_EXTERNAL_STORAGE below.
    final status = await Permission.audio.request();
    return status.isGranted;
  }

  Future<ScanResult> scan() async {
    if (!await requestPermission()) return ScanResult.permissionDenied;

    final List<Map<String, Object?>> scanned;
    if (Platform.isAndroid) {
      scanned = await MediaStoreChannel.queryTracks();
    } else {
      // Files already in the DB skip the ffprobe (their row carries the
      // metadata; sync only needs their id to keep them alive).
      final known = <String>{
        for (final t in await _repo.allTracks())
          if (t.isLocal && t.filePath != null) t.filePath!,
      };
      scanned =
          await DesktopLibrary.queryTracks(musicFolders, knownPaths: known);
    }
    final kept = scanned
        .where((s) => !_isExcluded(s['filePath'] as String? ?? ''))
        .toList();
    await _repo.syncScannedTracks(kept);
    // The index can still list files the user deleted; drop any local
    // track whose file is actually gone from disk.
    await _repo.pruneMissingLocalFiles();

    // Fetch art once per album that has tracks without an art path. A
    // local file from the album rides along so the extractor can read the
    // embedded picture itself when the system thumbnailer fails.
    final tracks = await _repo.allTracks();
    final missingArt = <int, String?>{};
    for (final t in tracks) {
      if (t.albumArtPath != null) continue;
      missingArt.putIfAbsent(t.albumId, () => null);
      if (t.isLocal && t.filePath != null) missingArt[t.albumId] = t.filePath;
    }
    for (final e in missingArt.entries) {
      try {
        final path = Platform.isAndroid
            ? await MediaStoreChannel.getAlbumArt(e.key, filePath: e.value)
            : await DesktopLibrary.extractAlbumArt(e.key, filePath: e.value);
        if (path != null) await _repo.setAlbumArt(e.key, path);
      } catch (_) {
        // One album's art must never abort the scan — the track sync
        // above is already committed; art fills in on the next pass.
      }
    }
    return ScanResult.done;
  }
}
