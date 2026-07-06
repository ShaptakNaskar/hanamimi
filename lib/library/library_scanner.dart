import 'package:permission_handler/permission_handler.dart';

import 'library_repository.dart';
import 'media_store_channel.dart';

enum ScanResult { done, permissionDenied }

/// Orchestrates a library scan: permission → MediaStore query → DB sync
/// → album art extraction for any albums still missing art.
class LibraryScanner {
  LibraryScanner(this._repo, {this.excludedDirs = const {}});

  final LibraryRepository _repo;

  /// Directories the user opted out of; tracks directly inside them are
  /// dropped from the scan, which also removes their existing DB rows via
  /// the sync's disappeared-file cleanup. Subfolders are separate entries
  /// in the Folders tab, so they hide independently — hiding Downloads
  /// must not take Downloads/Music/Album with it.
  final Set<String> excludedDirs;

  bool _isExcluded(String filePath) {
    final slash = filePath.lastIndexOf('/');
    final dir = slash <= 0 ? '/' : filePath.substring(0, slash);
    return excludedDirs.contains(dir);
  }

  Future<bool> requestPermission() async {
    // permission_handler maps Permission.audio to READ_MEDIA_AUDIO on
    // API 33+ and to READ_EXTERNAL_STORAGE below.
    final status = await Permission.audio.request();
    return status.isGranted;
  }

  Future<ScanResult> scan() async {
    if (!await requestPermission()) return ScanResult.permissionDenied;

    final scanned = await MediaStoreChannel.queryTracks();
    final kept = scanned
        .where((s) => !_isExcluded(s['filePath'] as String? ?? ''))
        .toList();
    await _repo.syncScannedTracks(kept);
    // MediaStore can still list files the user deleted; drop any local
    // track whose file is actually gone from disk.
    await _repo.pruneMissingLocalFiles();

    // Fetch art once per album that has tracks without an art path. A
    // local file from the album rides along so the channel can read the
    // embedded picture itself when the system thumbnailer fails.
    final tracks = await _repo.allTracks();
    final missingArt = <int, String?>{};
    for (final t in tracks) {
      if (t.albumArtPath != null) continue;
      missingArt.putIfAbsent(t.albumId, () => null);
      if (t.isLocal && t.filePath != null) missingArt[t.albumId] = t.filePath;
    }
    for (final e in missingArt.entries) {
      final path =
          await MediaStoreChannel.getAlbumArt(e.key, filePath: e.value);
      if (path != null) await _repo.setAlbumArt(e.key, path);
    }
    return ScanResult.done;
  }
}
