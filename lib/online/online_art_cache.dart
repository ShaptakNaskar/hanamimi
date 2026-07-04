import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Fetches a remote art URL once into the app cache so online tracks
/// ride the same Image.file + cacheWidth path as MediaStore thumbnails
/// (M18 perf fix). Returns the local path, or null on failure.
class OnlineArtCache {
  static final _inflight = <String, Future<String?>>{};

  static Future<String?> fetch(String artUrl, String cacheKey) =>
      _inflight.putIfAbsent(cacheKey, () async {
        try {
          final dir =
              Directory('${(await getTemporaryDirectory()).path}/art_online');
          await dir.create(recursive: true);
          final file = File('${dir.path}/$cacheKey.jpg');
          if (await file.exists()) return file.path;

          final res = await http
              .get(Uri.parse(artUrl))
              .timeout(const Duration(seconds: 15));
          if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
          await file.writeAsBytes(res.bodyBytes);
          return file.path;
        } catch (_) {
          return null;
        } finally {
          _inflight.remove(cacheKey);
        }
      });
}
