import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'web_media.dart';

/// Web port of the FFT extractor (Kotlin FftExtractorChannel.kt /
/// desktop_fft.dart): the browser decodes the file to 44100 Hz PCM
/// (Web Audio `decodeAudioData` — the ffmpeg `-ar 44100` of this
/// edition), and the identical Hann-windowed 2048-point FFT → 12
/// log-spaced bands at 60 fps runs in Dart, each frame carrying
/// per-channel RMS (true L/R loudness for the VU meters) — 14 floats
/// per frame, flagged by 'stride' in the events
/// ({key, offset, bands, stride, done}). No worker isolate on web:
/// the analysis yields to the event loop between chunks instead.
///
/// Finished frame runs are kept in an in-memory LRU so replays skip the
/// decode and Slow Dance can read a track's loudness envelope — the
/// same role the desktop `.bin` disk cache plays.
class WebFft {
  static const _frameRate = 60; // must match FftExtractorChannel.FRAME_RATE
  static const _bands = 12;
  static const _frameFloats = _bands + 2; // + rmsL, rmsR
  static const _window = 2048;
  static const _chunkFrames = 120; // ~2s of frames per event
  static const _sampleRate = 44100;
  static const _maxCached = 16; // ~10 MB of Float32 frames at most

  static final _frames = StreamController<Map>.broadcast();
  static Stream<Map> get frames => _frames.stream;

  static final _cache = <String, Float32List>{};
  static int _job = 0;

  /// The complete frame run for [key] if it has been analyzed this
  /// session (stride 14). Slow Dance's planner reads this.
  static Float32List? cached(String key) => _cache[key];

  static Future<void> start(String path, String key) async {
    final job = ++_job;

    final hit = _cache.remove(key);
    if (hit != null) {
      _cache[key] = hit; // re-insertion = LRU touch
      await _streamCached(job, key, hit);
      return;
    }

    final file = WebMedia.fileForUrl(path);
    final pcm = file == null ? null : await WebMedia.decodePcm(file);
    if (job != _job) return;
    if (pcm == null) {
      // Codec the browser can't decode — terminal event so the
      // provider's watchdog doesn't retry a corpse forever.
      _frames.add({'key': key, 'offset': 0, 'bands': <double>[], 'done': true});
      return;
    }

    final analyzer = _Analyzer(key);
    final left = pcm.left;
    final right = pcm.right;
    // ~1 s of samples per slice, then yield — keeps the UI thread
    // responsive while a 5-minute track churns through ~18k FFTs.
    const slice = _sampleRate;
    for (var i = 0; i < left.length; i += slice) {
      final end = math.min(i + slice, left.length);
      for (var s = i; s < end; s++) {
        analyzer.push(left[s], right[s]);
      }
      for (final event in analyzer.takeEvents(done: false)) {
        if (job != _job) return;
        _frames.add(event);
      }
      await Future<void>.delayed(Duration.zero);
      if (job != _job) return; // superseded while yielding
    }
    for (final event in analyzer.takeEvents(done: true)) {
      _frames.add(event);
    }
    _cache[key] = analyzer.allFrames();
    while (_cache.length > _maxCached) {
      _cache.remove(_cache.keys.first);
    }
  }

  static Future<void> cancel() async {
    _job++;
  }

  static Future<void> _streamCached(
      int job, String key, Float32List run) async {
    final frameCount = run.length ~/ _frameFloats;
    var offset = 0;
    while (offset < frameCount) {
      if (job != _job) return;
      final n = math.min(_chunkFrames * 4, frameCount - offset);
      _frames.add({
        'key': key,
        'offset': offset,
        'bands': [
          for (var i = 0; i < n * _frameFloats; i++)
            run[offset * _frameFloats + i].toDouble(),
        ],
        'stride': _frameFloats,
        'done': offset + n >= frameCount,
      });
      offset += n;
      await Future<void>.delayed(Duration.zero);
    }
  }
}

/// Hann window → FFT → 12 log bands + per-channel RMS, one frame per
/// hop. The numbers match the Kotlin/desktop extractors bit for bit
/// (hop 735.0, norm N/4, 40 Hz–14 kHz edges); the FFT sees the (L+R)/2
/// mix, and the two RMS values are the true VU-meter signal.
class _Analyzer {
  _Analyzer(this.key);

  final String key;

  static const _hop = WebFft._sampleRate / WebFft._frameRate; // 735.0

  final _fft = _Fft(WebFft._window);
  static final _hann = List<double>.generate(
      WebFft._window,
      (i) =>
          0.5 * (1 - math.cos(2 * math.pi * i / (WebFft._window - 1))));
  final _ring = Float32List(WebFft._window);
  var _written = 0; // total mono samples seen
  var _nextFrameAt = _hop;

  // Per-hop channel energy for the VU RMS.
  var _sumL2 = 0.0, _sumR2 = 0.0;
  var _hopSamples = 0;

  final _edges = _bandEdgeBins();
  final _pending = <double>[];
  var _framesSent = 0;
  final _all = <double>[];

  // Reused across frames — allocating 2×16 KB per frame is the
  // difference between extraction outrunning playback or not.
  final _re = Float64List(WebFft._window);
  final _im = Float64List(WebFft._window);

  /// 13 bin edges, log-spaced ~40 Hz → 14 kHz.
  static List<int> _bandEdgeBins() {
    const binHz = WebFft._sampleRate / WebFft._window;
    const lo = 40.0;
    final hi = math.min(14000.0, WebFft._sampleRate / 2 * 0.9);
    return [
      for (var i = 0; i <= WebFft._bands; i++)
        (lo * math.pow(hi / lo, i / WebFft._bands) / binHz)
            .toInt()
            .clamp(1, WebFft._window ~/ 2 - 1),
    ];
  }

  void push(double left, double right) {
    _sumL2 += left * left;
    _sumR2 += right * right;
    _hopSamples++;
    _ring[_written % WebFft._window] = (left + right) * 0.5;
    _written++;
    if (_written >= _nextFrameAt) {
      _analyzeFrame();
      _nextFrameAt += _hop;
    }
  }

  void _analyzeFrame() {
    const n = WebFft._window;
    final re = _re..fillRange(0, n, 0);
    final im = _im..fillRange(0, n, 0);
    // Oldest→newest out of the ring, zero-padded before start.
    final have = math.min(_written, n);
    final startPad = n - have;
    for (var i = 0; i < have; i++) {
      final src = (_written - have + i) % n;
      re[startPad + i] = _ring[src] * _hann[startPad + i];
    }
    _fft.transform(re, im);
    // Hann coherent gain 0.5: a full-scale sine peaks at N/4.
    const norm = n / 4.0;
    for (var b = 0; b < WebFft._bands; b++) {
      final lo = _edges[b];
      final hi = math.max(_edges[b + 1], lo + 1);
      var sum = 0.0;
      for (var bin = lo; bin < hi; bin++) {
        sum += math.sqrt(re[bin] * re[bin] + im[bin] * im[bin]);
      }
      final v = (sum / (hi - lo)) / norm;
      _pending.add(v);
      _all.add(v);
    }
    final rmsL = _hopSamples > 0 ? math.sqrt(_sumL2 / _hopSamples) : 0.0;
    final rmsR = _hopSamples > 0 ? math.sqrt(_sumR2 / _hopSamples) : 0.0;
    _sumL2 = 0;
    _sumR2 = 0;
    _hopSamples = 0;
    _pending
      ..add(rmsL)
      ..add(rmsR);
    _all
      ..add(rmsL)
      ..add(rmsR);
  }

  /// Drains buffered frames into chunk events (empty list when there's
  /// less than a chunk and we're not done).
  List<Map> takeEvents({required bool done}) {
    final events = <Map>[];
    while (_pending.length >= WebFft._chunkFrames * WebFft._frameFloats ||
        (done && _pending.isNotEmpty)) {
      final n = math.min(
          WebFft._chunkFrames * WebFft._frameFloats, _pending.length);
      final chunk = _pending.sublist(0, n);
      _pending.removeRange(0, n);
      events.add({
        'key': key,
        'offset': _framesSent,
        'bands': chunk,
        'stride': WebFft._frameFloats,
        'done': done && _pending.isEmpty,
      });
      _framesSent += n ~/ WebFft._frameFloats;
    }
    if (done && events.isEmpty) {
      events.add({
        'key': key,
        'offset': _framesSent,
        'bands': <double>[],
        'stride': WebFft._frameFloats,
        'done': true,
      });
    }
    return events;
  }

  Float32List allFrames() => Float32List.fromList(_all);
}

/// Iterative radix-2 complex FFT with precomputed twiddles (port of the
/// Kotlin Fft class — identical to the desktop Dart port).
class _Fft {
  _Fft(this.n)
      : _cos = Float64List(n ~/ 2),
        _sin = Float64List(n ~/ 2),
        _reversed = Int32List(n) {
    for (var i = 0; i < n ~/ 2; i++) {
      _cos[i] = math.cos(2 * math.pi * i / n);
      _sin[i] = math.sin(2 * math.pi * i / n);
    }
    var bits = 0;
    while ((1 << bits) < n) {
      bits++;
    }
    for (var i = 0; i < n; i++) {
      var rev = 0;
      for (var b = 0; b < bits; b++) {
        if (i & (1 << b) != 0) rev |= 1 << (bits - 1 - b);
      }
      _reversed[i] = rev;
    }
  }

  final int n;
  final Float64List _cos;
  final Float64List _sin;
  final Int32List _reversed;

  void transform(Float64List re, Float64List im) {
    for (var i = 0; i < n; i++) {
      final j = _reversed[i];
      if (j > i) {
        var t = re[i];
        re[i] = re[j];
        re[j] = t;
        t = im[i];
        im[i] = im[j];
        im[j] = t;
      }
    }
    var size = 2;
    while (size <= n) {
      final half = size ~/ 2;
      final step = n ~/ size;
      for (var i = 0; i < n; i += size) {
        var k = 0;
        for (var j = i; j < i + half; j++) {
          final l = j + half;
          final tre = re[l] * _cos[k] + im[l] * _sin[k];
          final tim = -re[l] * _sin[k] + im[l] * _cos[k];
          re[l] = re[j] - tre;
          im[l] = im[j] - tim;
          re[j] += tre;
          im[j] += tim;
          k += step;
        }
      }
      size <<= 1;
    }
  }
}
