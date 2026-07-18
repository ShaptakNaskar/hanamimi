import '../platform/web/web_fft.dart';

/// Web edition: the same surface the Android MethodChannel exposes,
/// backed by the in-browser extractor (Web Audio decode → Dart FFT).
/// visualizer_provider consumes this identically on every platform.
class FftChannel {
  /// Kicks off (or replays from the in-memory cache) extraction for
  /// [path] (a blob URL). Frames arrive on [frames] tagged with [key];
  /// starting a new extraction cancels the previous one.
  static Future<void> start(String path, String key) =>
      WebFft.start(path, key);

  static Future<void> cancel() => WebFft.cancel();

  /// Chunks: {key: String, offset: int (frame index), bands:
  /// List&lt;double&gt; (frames × stride, flattened), stride: 14, done: bool}.
  static Stream<Map> get frames => WebFft.frames;
}
