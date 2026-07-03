import 'package:flutter/services.dart';

/// Dart side of the Kotlin MediaStore scanner
/// (android/.../MediaStoreChannel.kt).
class MediaStoreChannel {
  static const _channel = MethodChannel('hanamimi/mediastore');

  /// Raw device tracks: mediaId, title, artist, album, albumId,
  /// durationMs, filePath, trackNumber.
  static Future<List<Map<String, Object?>>> queryTracks() async {
    final result = await _channel.invokeListMethod<Map>('queryTracks');
    return (result ?? [])
        .map((m) => m.map((k, v) => MapEntry(k as String, v as Object?)))
        .toList();
  }

  /// Extracts a 512px thumbnail for the album into the cache dir.
  /// Returns the file path, or null if the album has no art.
  static Future<String?> getAlbumArt(int albumId) =>
      _channel.invokeMethod<String>('getAlbumArt', {'albumId': albumId});
}
