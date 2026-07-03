import 'package:flutter/services.dart';

/// Dart side of android/.../FftExtractorChannel.kt — visualizer band
/// frames computed by decoding the audio file (no RECORD_AUDIO).
class FftChannel {
  static const _method = MethodChannel('hanamimi/fft');
  static const _events = EventChannel('hanamimi/fft/frames');

  /// Kicks off (or resumes from cache) extraction for [path]. Frames
  /// arrive on [frames] tagged with [key]; starting a new extraction
  /// cancels the previous one.
  static Future<void> start(String path, String key) =>
      _method.invokeMethod('start', {'path': path, 'key': key});

  static Future<void> cancel() => _method.invokeMethod('cancel');

  /// Chunks: {key: String, offset: int (frame index), bands: Float64List
  /// (frames × 12, flattened), done: bool}.
  static Stream<Map> get frames =>
      _events.receiveBroadcastStream().map((e) => e as Map);
}
