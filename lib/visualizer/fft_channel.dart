import 'dart:io';

import 'package:flutter/services.dart';

import '../platform/desktop/desktop_fft.dart';

/// Dart side of android/.../FftExtractorChannel.kt — visualizer band
/// frames computed by decoding the audio file (no RECORD_AUDIO).
/// Desktop decodes with ffmpeg and runs the same math in a Dart isolate
/// (DesktopFft) — identical frames, same contract.
class FftChannel {
  static const _method = MethodChannel('hanamimi/fft');
  static const _events = EventChannel('hanamimi/fft/frames');

  /// Kicks off (or resumes from cache) extraction for [path]. Frames
  /// arrive on [frames] tagged with [key]; starting a new extraction
  /// cancels the previous one.
  static Future<void> start(String path, String key) =>
      Platform.isAndroid
          ? _method.invokeMethod('start', {'path': path, 'key': key})
          : DesktopFft.start(path, key);

  static Future<void> cancel() => Platform.isAndroid
      ? _method.invokeMethod('cancel')
      : DesktopFft.cancel();

  /// Chunks: {key: String, offset: int (frame index), bands: Float64List
  /// (frames × stride, flattened), stride: int? (14 on desktop — 12
  /// bands + L/R RMS; absent on Android = 12), done: bool}.
  static Stream<Map> get frames => Platform.isAndroid
      ? _events.receiveBroadcastStream().map((e) => e as Map)
      : DesktopFft.frames;
}
