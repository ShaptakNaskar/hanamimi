import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Committed filenames are content identities, independent of the iOS container.
class IosLibrary {
  static const channel = MethodChannel('hanamimi/ios_library');
  static const extensions = {'mp3', 'm4a', 'aac', 'flac', 'wav', 'aiff', 'aif'};
  static const maxBytes = 2 * 1024 * 1024 * 1024;

  static Future<Directory> musicDirectory() async {
    final root = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/Music',
    );
    if (await FileSystemEntity.type(root.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FileSystemException('Music cannot be a symbolic link');
    }
    await root.create(recursive: true);
    return root;
  }

  static Future<File> import(String name, Stream<List<int>> bytes) async {
    final ext = name.split('.').last.toLowerCase();
    if (utf8.encode(name).length > 180 ||
        name.contains(RegExp(r'[/\\\x00-\x1f]')) ||
        !extensions.contains(ext)) {
      throw const FormatException(
        'Choose an MP3, M4A, AAC, FLAC, WAV or AIFF file.',
      );
    }
    final staging = Directory(
      '${(await getApplicationSupportDirectory()).path}/ImportStaging',
    );
    await staging.create(recursive: true);
    final file = File(
      '${staging.path}/${Random.secure().nextInt(1 << 32)}.part.$ext',
    );
    await file.create(exclusive: true);
    final sink = file.openWrite();
    try {
      var size = 0;
      await for (final chunk in bytes.timeout(const Duration(seconds: 30))) {
        size += chunk.length;
        if (size > maxBytes) throw const FormatException('File exceeds 2 GiB.');
        sink.add(chunk);
        await sink.flush();
      }
      await sink.close();
      if (size == 0) throw const FormatException('The file is empty.');
      // Validate native decode before publishing a file into the scan root.
      await channel.invokeMethod('validate', {'path': file.path});
      final digest = await sha256.bind(file.openRead()).first;
      final root = await musicDirectory();
      final existing =
          await root
              .list(followLinks: false)
              .where(
                (f) =>
                    f is File &&
                    f.uri.pathSegments.last.startsWith('$digest--'),
              )
              .take(1)
              .toList();
      if (existing.isNotEmpty) return File(existing.first.path);
      final destination = File('${root.path}/$digest--$name');
      if (await destination.exists()) return destination;
      return await file.rename(destination.path);
    } finally {
      await sink.close();
      if (await file.exists()) await file.delete();
    }
  }

  static Future<List<Map<String, Object?>>>? _scan;
  static Future<List<Map<String, Object?>>> queryTracks() =>
      _scan ??= _queryTracks().whenComplete(() => _scan = null);

  static Future<void> initialize() async {
    final staging = Directory('${(await getApplicationSupportDirectory()).path}/ImportStaging');
    if (await staging.exists()) await staging.delete(recursive: true);
    final temporary = await getTemporaryDirectory();
    await for (final entry in temporary.list(followLinks: false)) {
      if (entry is File && entry.uri.pathSegments.last.startsWith('hanamimi-decode-')) {
        await entry.delete();
      }
    }
  }

  static Future<List<Map<String, Object?>>> _queryTracks() async {
    final root = await musicDirectory();
    // Files/Finder placements go through the same validation and deduplication.
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! File) continue;
      var name = entry.uri.pathSegments.last;
      if (RegExp(r'^[a-f0-9]{64}--').hasMatch(name)) {
        final digest = await sha256.bind(entry.openRead()).first;
        if (name.startsWith('$digest--')) continue;
        name = name.substring(66);
      }
      if (!extensions.contains(name.split('.').last.toLowerCase())) continue;
      try {
        final committed = await import(name, entry.openRead());
        if (committed.path != entry.path) await entry.delete();
      } on PlatformException {
        // A malformed file in Files must not hide the rest of the library.
      } on FormatException {
        continue;
      }
    }
    final rows = await channel.invokeListMethod<Map>('scan', {
      'path': root.path,
    });
    return (rows ?? []).map((m) => m.cast<String, Object?>()).toList();
  }
}
