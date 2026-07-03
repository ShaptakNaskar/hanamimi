import 'package:flutter/services.dart';

/// Dart side of MainActivity's "open with Hanamimi" handling.
class OpenWithChannel {
  static const _channel = MethodChannel('hanamimi/open_with');

  /// The ACTION_VIEW payload that launched the app, if any — consumed
  /// on read. Keys: uri, path (nullable), title (nullable).
  static Future<Map?> getPendingMedia() =>
      _channel.invokeMethod<Map>('getPendingMedia');

  /// Payloads arriving while the app is already running.
  static void setListener(void Function(Map payload) onMedia) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openMedia') {
        onMedia(call.arguments as Map);
      }
    });
  }
}
