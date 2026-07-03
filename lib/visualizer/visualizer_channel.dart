import 'package:flutter/services.dart';

/// Dart side of android/.../VisualizerChannel.kt.
class VisualizerChannel {
  static const _method = MethodChannel('hanamimi/visualizer');
  static const _events = EventChannel('hanamimi/visualizer/fft');

  /// Returns false when the Visualizer couldn't attach (usually missing
  /// RECORD_AUDIO permission).
  static Future<bool> attach(int sessionId) async =>
      await _method.invokeMethod<bool>('attach', {'sessionId': sessionId}) ??
      false;

  static Future<void> detach() => _method.invokeMethod('detach');

  static Stream<Uint8List> get fftStream =>
      _events.receiveBroadcastStream().map((e) => e as Uint8List);
}
