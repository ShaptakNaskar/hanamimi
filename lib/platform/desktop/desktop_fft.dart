import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'desktop_binaries.dart';

/// Desktop port of FftExtractorChannel.kt (ARCHITECTURE-DESKTOP.md
/// §2.1): ffmpeg decodes the file (or full-speed stream URL) to mono
/// PCM, and the same Hann-windowed 2048-point FFT → 12 log-spaced bands
/// at 60 fps runs in a Dart isolate. Identical event contract
/// ({key, offset, bands, done}) and cache format, so the visualizer
/// provider and BandShaper are shared verbatim.
class DesktopFft {
  static const _frameRate = 60; // must match FftExtractorChannel.FRAME_RATE
  static const _bands = 12;
  static const _window = 2048;
  static const _chunkFrames = 120; // ~2s of frames per event
  static const _maxCacheFiles = 64;

  // ffmpeg resamples for us, so the hop is a clean 735.0 (44100/60) and
  // the band-edge table is fixed.
  static const _sampleRate = 44100;

  static final _frames = StreamController<Map>.broadcast();
  static Stream<Map> get frames => _frames.stream;

  static Isolate? _isolate;
  static ReceivePort? _receive;
  static SendPort? _cancelPort;
  static int _job = 0;

  /// Kicks off (or resumes from cache) extraction for [path] — a local
  /// file or a direct-decodable https URL. Starting a new extraction
  /// cancels the previous one.
  static Future<void> start(String path, String key) async {
    await cancel();
    final job = ++_job;
    final cacheDir =
        '${(await getApplicationSupportDirectory()).path}/fft';

    final receive = ReceivePort();
    _receive = receive;
    receive.listen((message) {
      if (message is! Map || job != _job) return;
      if (message['_ctrl'] is SendPort) {
        _cancelPort = message['_ctrl'] as SendPort;
        return;
      }
      _frames.add(message);
    });
    // Errors in the isolate must surface as a terminal "done" event —
    // otherwise the watchdog retries against a silent corpse.
    final onError = RawReceivePort((List<dynamic> pair) {
      assert(() {
        // ignore: avoid_print
        print('DesktopFft isolate error: ${pair.first}\n${pair.last}');
        return true;
      }());
      if (job == _job) {
        _frames.add({'key': key, 'offset': 0, 'bands': <double>[], 'done': true});
      }
    });
    _isolate = await Isolate.spawn(
      _extractEntry,
      [
        receive.sendPort,
        path,
        key,
        cacheDir,
        DesktopBinaries.find('ffmpeg'),
      ],
      onError: onError.sendPort,
    );
  }

  static Future<void> cancel() async {
    _job++;
    // Cooperative: the isolate owns an ffmpeg child a hard kill would
    // orphan, so ask it to stop (it kills the child and drains out). A
    // delayed hard kill backstops an isolate wedged on a dead stream.
    _cancelPort?.send('cancel');
    _cancelPort = null;
    final isolate = _isolate;
    _isolate = null;
    if (isolate != null) {
      Timer(const Duration(seconds: 3),
          () => isolate.kill(priority: Isolate.immediate));
    }
    _receive?.close();
    _receive = null;
  }

  // --- Everything below runs in the extraction isolate ---

  static Future<void> _extractEntry(List<Object?> args) async {
    final send = args[0] as SendPort;
    final path = args[1] as String;
    final key = args[2] as String;
    final cacheDir = args[3] as String;
    final ffmpeg = args[4] as String;

    var cancelled = false;
    Process? proc;
    final ctrl = ReceivePort();
    ctrl.listen((_) {
      cancelled = true;
      proc?.kill();
    });
    send.send({'_ctrl': ctrl.sendPort});

    try {
      final cached = File('$cacheDir/$key.bin');
      if (await cached.exists()) {
        await _streamCached(send, key, cached, () => cancelled);
        return;
      }

      proc = await Process.start(ffmpeg, [
        '-v', 'quiet',
        '-i', path,
        '-vn',
        '-ac', '1',
        '-ar', '$_sampleRate',
        '-f', 'f32le',
        '-',
      ]);
      // Unread stderr can fill the pipe and wedge ffmpeg.
      unawaited(proc.stderr.drain<void>());

      final analyzer = _Analyzer(send, key);
      final carry = BytesBuilder(copy: true); // partial trailing float
      await for (final chunk in proc.stdout) {
        if (cancelled) break;
        carry.add(chunk);
        final bytes = carry.takeBytes();
        // sublistView bounds are in SOURCE elements (bytes) — and the
        // viewed span must be float-aligned, hence the carry of the
        // partial trailing sample.
        final usable = bytes.length & ~3;
        final samples = Float32List.sublistView(bytes, 0, usable);
        for (final s in samples) {
          analyzer.push(s);
        }
        if (usable < bytes.length) carry.add(bytes.sublist(usable));
      }
      final exit = await proc.exitCode;

      if (!cancelled && exit == 0) {
        await analyzer.finish(cacheDir, key);
        _trimCache(cacheDir);
      }
    } catch (e, st) {
      // Unreadable file / no ffmpeg — Dart falls back to the synth pulse.
      assert(() {
        // ignore: avoid_print
        print('DesktopFft extraction failed: $e\n$st');
        return true;
      }());
      if (!cancelled) {
        send.send({'key': key, 'offset': 0, 'bands': <double>[], 'done': true});
      }
    } finally {
      ctrl.close();
    }
  }

  /// Cache format (same as Android): [int32 frameCount][float32 band…],
  /// big-endian.
  static Future<void> _streamCached(
      SendPort send, String key, File file, bool Function() cancelled) async {
    final bytes = await file.readAsBytes();
    final data = ByteData.sublistView(bytes);
    final frameCount = data.getInt32(0);
    if (frameCount <= 0 || bytes.length < 4 + frameCount * _bands * 4) {
      send.send({'key': key, 'offset': 0, 'bands': <double>[], 'done': true});
      return;
    }
    var offset = 0;
    while (offset < frameCount && !cancelled()) {
      final n = math.min(_chunkFrames * 4, frameCount - offset);
      final chunk = List<double>.generate(n * _bands,
          (i) => data.getFloat32(4 + (offset * _bands + i) * 4));
      send.send({
        'key': key,
        'offset': offset,
        'bands': chunk,
        'done': offset + n >= frameCount,
      });
      offset += n;
    }
    try {
      file.setLastModifiedSync(DateTime.now());
    } catch (_) {}
  }

  static void _trimCache(String cacheDir) {
    try {
      final files = Directory(cacheDir).listSync().whereType<File>().toList();
      if (files.length <= _maxCacheFiles) return;
      files.sort((a, b) =>
          a.statSync().modified.compareTo(b.statSync().modified));
      for (final f in files.take(files.length - _maxCacheFiles)) {
        f.deleteSync();
      }
    } catch (_) {}
  }
}

/// Hann window → FFT → 12 log bands, one frame per hop. Numbers match
/// the Kotlin extractor bit for bit (hop 735.0, norm N/4, 40 Hz–14 kHz
/// edges) so a cache produced here draws identically on both platforms.
class _Analyzer {
  _Analyzer(this.send, this.key);

  final SendPort send;
  final String key;

  static const _hop = DesktopFft._sampleRate / DesktopFft._frameRate; // 735.0

  final _fft = _Fft(DesktopFft._window);
  final _hann = List<double>.generate(
      DesktopFft._window,
      (i) =>
          0.5 * (1 - math.cos(2 * math.pi * i / (DesktopFft._window - 1))));
  final _ring = Float32List(DesktopFft._window);
  var _written = 0; // total mono samples seen
  var _nextFrameAt = _hop;

  final _edges = _bandEdgeBins();
  final _pending = <double>[];
  var _framesSent = 0;
  final _cacheData = BytesBuilder(copy: false);
  var _frameCount = 0;

  // Reused across frames — allocating 2×16 KB per frame (12k+ frames a
  // song) made extraction slower than playback.
  final _re = Float64List(DesktopFft._window);
  final _im = Float64List(DesktopFft._window);

  /// 13 bin edges, log-spaced ~40 Hz → 14 kHz.
  static List<int> _bandEdgeBins() {
    const binHz = DesktopFft._sampleRate / DesktopFft._window;
    const lo = 40.0;
    final hi = math.min(14000.0, DesktopFft._sampleRate / 2 * 0.9);
    return [
      for (var i = 0; i <= DesktopFft._bands; i++)
        (lo * math.pow(hi / lo, i / DesktopFft._bands) / binHz)
            .toInt()
            .clamp(1, DesktopFft._window ~/ 2 - 1),
    ];
  }

  void push(double sample) {
    _ring[_written % DesktopFft._window] = sample;
    _written++;
    if (_written >= _nextFrameAt) {
      _analyzeFrame();
      _nextFrameAt += _hop;
    }
  }

  void _analyzeFrame() {
    const n = DesktopFft._window;
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
    final frame = ByteData(DesktopFft._bands * 4);
    for (var b = 0; b < DesktopFft._bands; b++) {
      final lo = _edges[b];
      final hi = math.max(_edges[b + 1], lo + 1);
      var sum = 0.0;
      for (var bin = lo; bin < hi; bin++) {
        sum += math.sqrt(re[bin] * re[bin] + im[bin] * im[bin]);
      }
      final v = (sum / (hi - lo)) / norm;
      _pending.add(v);
      frame.setFloat32(b * 4, v);
    }
    _cacheData.add(frame.buffer.asUint8List());
    _frameCount++;
    if (_pending.length >= DesktopFft._chunkFrames * DesktopFft._bands) {
      _flush(false);
    }
  }

  void _flush(bool done) {
    if (_pending.isEmpty && !done) return;
    send.send({
      'key': key,
      'offset': _framesSent,
      'bands': List<double>.of(_pending),
      'done': done,
    });
    _framesSent += _pending.length ~/ DesktopFft._bands;
    _pending.clear();
  }

  Future<void> finish(String cacheDir, String key) async {
    await Directory(cacheDir).create(recursive: true);
    final tmp = File('$cacheDir/$key.bin.tmp');
    final header = ByteData(4)..setInt32(0, _frameCount);
    await tmp.writeAsBytes(
      header.buffer.asUint8List() + _cacheData.takeBytes(),
      flush: true,
    );
    await tmp.rename('$cacheDir/$key.bin');
    _flush(true);
  }
}

/// Iterative radix-2 complex FFT with precomputed twiddles (port of the
/// Kotlin Fft class).
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
