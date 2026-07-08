import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'desktop_binaries.dart';

/// Desktop replacement for the Kotlin MediaStore scanner
/// (ARCHITECTURE-DESKTOP.md §4): a recursive walk over the user's music
/// folders, tags read with ffprobe, embedded art extracted with ffmpeg.
/// Emits the exact map shape MediaStoreChannel.queryTracks does, so
/// LibraryRepository.syncScannedTracks is untouched.
class DesktopLibrary {
  static const _audioExtensions = {
    '.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.opus', '.wma',
    '.aif', '.aiff', '.alac', '.ape', '.mka',
  };

  /// Probe pool size — one ffprobe process per new file, this many in
  /// flight. First scan of a big library is IO/process bound; rescans
  /// skip every file already in the DB (their metadata rows are only
  /// read on insert, and their membership is what keeps them alive).
  static const _probeConcurrency = 8;

  /// Index of the last path separator, handling both POSIX '/' and
  /// Windows '\'. Directory.list returns native separators, so a
  /// hardcoded '/' finds nothing on Windows (and substring(0, -1)
  /// throws) — which silently emptied the library there.
  static int _lastSep(String path) {
    final slash = path.lastIndexOf('/');
    final back = path.lastIndexOf('\\');
    return slash > back ? slash : back;
  }

  /// Every audio file under [folders] — the walk without the probe
  /// (folder pickers and the excluded-folders sheet only need paths).
  static Future<List<String>> listAudioFiles(Set<String> folders) async {
    final files = <String>[];
    for (final root in folders) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      // handleError: an unreadable subdirectory (or one deleted while
      // the walk runs — exactly what happens right after the user
      // reorganizes their music) raises mid-stream and killed the whole
      // rescan, leaving stale rows behind. Skip and keep walking.
      await for (final entry in dir
          .list(recursive: true, followLinks: false)
          .handleError((_) {})) {
        if (entry is! File) continue;
        final path = entry.path;
        final name = path.substring(_lastSep(path) + 1);
        if (name.startsWith('.')) continue;
        final dot = name.lastIndexOf('.');
        if (dot < 0) continue;
        if (_audioExtensions.contains(name.substring(dot).toLowerCase())) {
          files.add(path);
        }
      }
    }
    return files;
  }

  /// [knownPaths]: local files already in the DB — emitted as
  /// membership-only rows (mediaId + filePath) without a probe.
  static Future<List<Map<String, Object?>>> queryTracks(
    Set<String> folders, {
    Set<String> knownPaths = const {},
  }) async {
    final files = await listAudioFiles(folders);

    final results = <Map<String, Object?>>[];
    final pending = <String>[];
    for (final path in files) {
      if (knownPaths.contains(path)) {
        // Row exists — sync only needs to see the mediaId to keep it.
        results.add({'mediaId': pathId(path), 'filePath': path});
      } else {
        pending.add(path);
      }
    }

    for (var i = 0; i < pending.length; i += _probeConcurrency) {
      final batch = pending.skip(i).take(_probeConcurrency);
      final probed = await Future.wait(batch.map(_probeFile));
      results.addAll(probed.whereType<Map<String, Object?>>());
    }
    return results;
  }

  /// FNV-1a 64-bit over the path — the desktop stand-in for MediaStore's
  /// _ID. Deliberately implemented (not String.hashCode, which isn't
  /// guaranteed stable across Dart versions) because media_id is the
  /// scan-sync identity in the DB.
  static int pathId(String path) => _fnv(path);

  static int _fnv(String s) {
    var h = 0xcbf29ce484222325;
    for (final c in utf8.encode(s)) {
      h ^= c;
      h *= 0x100000001b3; // 64-bit wrap-around is the algorithm
    }
    return h & 0x7fffffffffffffff; // keep it positive for readability
  }

  static Future<Map<String, Object?>?> _probeFile(String path) async {
    try {
      final res = await Process.run(DesktopBinaries.find('ffprobe'), [
        '-v', 'quiet',
        '-print_format', 'json',
        '-show_format',
        '-show_streams',
        path,
      ]);
      if (res.exitCode != 0) return null;
      final info = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      final format = (info['format'] as Map<String, dynamic>?) ?? const {};
      final streams = (info['streams'] as List?) ?? const [];
      final audio = streams.cast<Map<String, dynamic>>().firstWhere(
            (s) => s['codec_type'] == 'audio',
            orElse: () => const {},
          );
      if (audio.isEmpty) return null;

      // Tag keys vary by container ("TITLE" in FLAC, "title" in MP3) and
      // can sit on the format or the stream — merge case-insensitively.
      final tags = <String, String>{};
      for (final source in [audio['tags'], format['tags']]) {
        if (source is Map) {
          source.forEach((k, v) {
            tags.putIfAbsent(k.toString().toLowerCase(), () => v.toString());
          });
        }
      }

      final durationSecs =
          double.tryParse(format['duration'] as String? ?? '') ??
              double.tryParse(audio['duration'] as String? ?? '') ??
              0.0;

      final sep = _lastSep(path);
      final dir = path.substring(0, sep);
      final dot = path.lastIndexOf('.');
      final fileName = path.substring(sep + 1, dot > sep ? dot : path.length);
      final album = tags['album'];
      // Album identity: name + album-artist (so two different
      // "Greatest Hits" don't merge); untagged files group per-folder.
      final albumArtist =
          tags['album_artist'] ?? tags['albumartist'] ?? '';
      final albumKey = album == null
          ? 'dir:$dir'
          : '${album.toLowerCase()}|${albumArtist.toLowerCase()}';

      return {
        'mediaId': pathId(path),
        'title': tags['title'] ?? fileName,
        'artist': tags['artist'],
        'album': album,
        'albumId': _fnv(albumKey),
        'durationMs': (durationSecs * 1000).round(),
        'filePath': path,
        'trackNumber': _trackNumber(tags['track']),
      };
    } catch (_) {
      return null; // unreadable file never kills the scan
    }
  }

  /// "5", "5/12" → 5.
  static int? _trackNumber(String? raw) {
    if (raw == null) return null;
    return int.tryParse(raw.split('/').first.trim());
  }

  // --- Album art ---

  static Future<Directory> _artDir() async {
    final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/album_art');
    await dir.create(recursive: true);
    return dir;
  }

  /// Desktop counterpart of MediaStoreChannel.getAlbumArt: a ≤512px
  /// thumbnail from the file's embedded picture, falling back to a
  /// cover image sitting in the album folder. Null when neither exists.
  static Future<String?> extractAlbumArt(int albumId,
      {String? filePath}) async {
    final out = File('${(await _artDir()).path}/$albumId.jpg');
    if (await out.exists()) return out.path;
    if (filePath == null) return null;

    // Embedded art shows up to ffmpeg as an attached-pic video stream;
    // -frames:v 1 + scale handles any source format/size.
    if (await _ffmpegThumb(filePath, out.path)) return out.path;

    final dir = filePath.substring(0, _lastSep(filePath));
    for (final name in [
      'cover.jpg', 'cover.png', 'folder.jpg', 'folder.png',
      'front.jpg', 'front.png', 'album.jpg', 'AlbumArt.jpg',
    ]) {
      final candidate = File('$dir/$name');
      if (await candidate.exists() &&
          await _ffmpegThumb(candidate.path, out.path)) {
        return out.path;
      }
    }
    return null;
  }

  static Future<bool> _ffmpegThumb(String input, String output) async {
    try {
      final res = await Process.run(DesktopBinaries.find('ffmpeg'), [
        '-y', '-v', 'quiet',
        '-i', input,
        '-an',
        '-frames:v', '1',
        '-vf', "scale='min(512,iw)':-2",
        output,
      ]);
      return res.exitCode == 0 && await File(output).length() > 0;
    } catch (_) {
      return false;
    }
  }
}
