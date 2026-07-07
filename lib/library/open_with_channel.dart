import 'dart:io';

import 'package:flutter/services.dart';

/// Dart side of MainActivity's "open with Hanamimi" handling.
///
/// Desktop: the ACTION_VIEW equivalent is file paths handed to main()
/// as launch arguments — the bootstrap parks them here and the same
/// getPendingMedia contract serves both platforms.
class OpenWithChannel {
  static const _channel = MethodChannel('hanamimi/open_with');

  static Map? _desktopPending;

  /// Called once from the desktop bootstrap with the process args.
  static void desktopPendingFromArgs(List<String> args) {
    final path = args
        .where((a) => !a.startsWith('-') && File(a).existsSync())
        .firstOrNull;
    if (path == null) return;
    _desktopPending = {
      'uri': Uri.file(path).toString(),
      'path': path,
      'title': path.substring(path.lastIndexOf('/') + 1),
    };
  }

  /// The ACTION_VIEW payload that launched the app, if any — consumed
  /// on read. Keys: uri, path (nullable), title (nullable).
  static Future<Map?> getPendingMedia() {
    if (!Platform.isAndroid) {
      final pending = _desktopPending;
      _desktopPending = null;
      return Future.value(pending);
    }
    return _channel.invokeMethod<Map>('getPendingMedia');
  }

  /// Payloads arriving while the app is already running (Android only —
  /// desktop launches are separate processes).
  static void setListener(void Function(Map payload) onMedia) {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openMedia') {
        onMedia(call.arguments as Map);
      }
    });
  }
}
