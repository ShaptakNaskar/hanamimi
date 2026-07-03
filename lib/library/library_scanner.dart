import 'package:permission_handler/permission_handler.dart';

import 'library_repository.dart';
import 'media_store_channel.dart';

enum ScanResult { done, permissionDenied }

/// Orchestrates a library scan: permission → MediaStore query → DB sync
/// → album art extraction for any albums still missing art.
class LibraryScanner {
  LibraryScanner(this._repo, {this.excludedDirs = const {}});

  final LibraryRepository _repo;

  /// Directories the user opted out of; tracks inside them (at any
  /// depth) are dropped from the scan, which also removes their
  /// existing DB rows via the sync's disappeared-file cleanup.
  final Set<String> excludedDirs;

  bool _isExcluded(String filePath) => excludedDirs
      .any((dir) => filePath == dir || filePath.startsWith('$dir/'));

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

    // Fetch art once per album that has tracks without an art path.
    final tracks = await _repo.allTracks();
    final missingArt = <int>{
      for (final t in tracks)
        if (t.albumArtPath == null) t.albumId,
    };
    for (final albumId in missingArt) {
      final path = await MediaStoreChannel.getAlbumArt(albumId);
      if (path != null) await _repo.setAlbumArt(albumId, path);
    }
    return ScanResult.done;
  }
}
