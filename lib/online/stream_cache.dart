import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../library/models/track.dart';

/// Manages the transparent stream cache directory
/// (`cache/stream/<source>_<sourceId>`) that LockCachingAudioSource
/// writes to, plus the LRU trim that keeps it under the user's cap.
class StreamCache {
  Directory? _dir;

  Future<Directory> _dirFor() async {
    final dir = _dir ??=
        Directory('${(await getTemporaryDirectory()).path}/stream');
    await dir.create(recursive: true);
    return dir;
  }

  /// Stable cache file for a track's stream. The `.mp3` suffix is
  /// cosmetic — just_audio sniffs the container, not the extension.
  Future<File> fileFor(Track track) async =>
      File('${(await _dirFor()).path}/${track.source.name}_${track.sourceId}');

  /// Evicts least-recently-used cache files until the directory fits
  /// under [capBytes]. Called after a new stream starts caching.
  Future<void> trim(int capBytes) async {
    try {
      final dir = await _dirFor();
      final files = await dir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      var total = 0;
      final stats = <(File, FileStat)>[];
      for (final f in files) {
        final st = await f.stat();
        total += st.size;
        stats.add((f, st));
      }
      if (total <= capBytes) return;
      // Oldest access first.
      stats.sort((a, b) => a.$2.accessed.compareTo(b.$2.accessed));
      for (final (file, st) in stats) {
        if (total <= capBytes) break;
        try {
          await file.delete();
          total -= st.size;
        } catch (_) {
          // A file being actively written can't be deleted; skip it.
        }
      }
    } catch (_) {
      // Cache trimming is best-effort; never let it break playback.
    }
  }

  /// Total bytes currently held (for the settings display).
  Future<int> sizeBytes() async {
    try {
      final dir = await _dirFor();
      var total = 0;
      await for (final e in dir.list()) {
        if (e is File) total += (await e.stat()).size;
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clear() async {
    try {
      final dir = await _dirFor();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
