import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Browser-side media plumbing (ARCHITECTURE-WEB.md §2): folder/file
/// picking, blob URLs, Web Audio decoding, wake lock. Everything the
/// Android edition does through Kotlin channels, the web edition does
/// through these few interop calls — nothing is ever uploaded; files
/// stay in the tab.
class WebMedia {
  /// Audio extensions the picker admits. Browsers can't play every one
  /// of these everywhere, but just_audio surfaces a load error and the
  /// queue skips on — same contract as a deleted file on Android.
  static const audioExtensions = {
    'mp3', 'm4a', 'aac', 'flac', 'ogg', 'oga', 'opus', 'wav', 'weba', 'webm',
  };

  static bool isAudioFile(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return audioExtensions.contains(name.substring(dot + 1).toLowerCase());
  }

  /// Every blob URL we mint maps back to its [web.File] so the FFT
  /// extractor and tag reader can re-read bytes without a filesystem.
  static final _byUrl = <String, web.File>{};

  static web.File? fileForUrl(String url) => _byUrl[url];

  static String urlFor(web.File file) {
    final url = web.URL.createObjectURL(file);
    _byUrl[url] = file;
    return url;
  }

  static void revoke(String url) {
    _byUrl.remove(url);
    web.URL.revokeObjectURL(url);
  }

  /// Opens the browser's FOLDER picker (`<input webkitdirectory>` —
  /// Chromium, Firefox and Safari all honor it) and resolves with the
  /// audio files inside, or null when the user cancels.
  static Future<List<web.File>?> pickFolder() => _pick(directory: true);

  /// Multi-select audio file picker, for "just these songs".
  static Future<List<web.File>?> pickFiles() => _pick(directory: false);

  static Future<List<web.File>?> _pick({required bool directory}) {
    final completer = Completer<List<web.File>?>();
    final input =
        web.document.createElement('input') as web.HTMLInputElement;
    input.type = 'file';
    if (directory) {
      input.webkitdirectory = true;
    } else {
      input.multiple = true;
      input.accept = 'audio/*';
    }

    input.onchange = (web.Event _) {
      final list = input.files;
      final out = <web.File>[];
      if (list != null) {
        for (var i = 0; i < list.length; i++) {
          final f = list.item(i);
          if (f != null && isAudioFile(f.name)) out.add(f);
        }
      }
      completer.complete(out);
    }.toJS;
    // Cancel fires no change event; the input just goes quiet. The
    // `cancel` event (newer browsers) closes the wait properly.
    input.oncancel = (web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }.toJS;

    input.click();
    return completer.future;
  }

  static Future<Uint8List> readBytes(web.File file) async {
    final buffer = await file.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  /// Reads just the first [length] bytes (tag headers) — no reason to
  /// pull a 60 MB FLAC into memory to learn its title.
  static Future<Uint8List> readHead(web.File file, int length) async {
    final slice = file.slice(0, length);
    final buffer = await slice.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  /// Reads the last [length] bytes (ID3v1, MP4 moov-at-end).
  static Future<Uint8List> readTail(web.File file, int length) async {
    final start = file.size > length ? file.size - length : 0;
    final slice = file.slice(start, file.size);
    final buffer = await slice.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  /// Mints a blob URL for embedded album art bytes.
  static String artUrl(Uint8List bytes, String mime) {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mime),
    );
    return web.URL.createObjectURL(blob);
  }

  /// The track's playable length, from an off-DOM `<audio>` element's
  /// metadata — cheap (no full decode), works for every format the
  /// browser can actually play. Null when the browser can't read it.
  static Future<Duration?> probeDuration(String url) {
    final completer = Completer<Duration?>();
    final audio = web.HTMLAudioElement()..preload = 'metadata';
    void finish(Duration? d) {
      if (!completer.isCompleted) completer.complete(d);
      audio.src = ''; // detach so the element can be collected
    }

    audio.onloadedmetadata = (web.Event _) {
      final s = audio.duration;
      finish(s.isFinite ? Duration(milliseconds: (s * 1000).round()) : null);
    }.toJS;
    audio.addEventListener('error', ((web.Event _) => finish(null)).toJS);
    audio.src = url;
    // A codec the browser silently ignores would hang the import queue.
    Timer(const Duration(seconds: 8), () => finish(null));
    return completer.future;
  }

  /// Decodes a whole file to PCM at 44100 Hz (the FFT pipeline's fixed
  /// rate — the browser resamples to the context rate for us, exactly
  /// like the desktop ffmpeg `-ar 44100`). Returns null when the
  /// browser can't decode the codec (the synth pulse covers it).
  static Future<DecodedPcm?> decodePcm(web.File file) async {
    try {
      final bytes = await file.arrayBuffer().toDart;
      // Length is a dummy — only decodeAudioData is used, and it
      // resamples to this context's sampleRate.
      final ctx = web.OfflineAudioContext(web.OfflineAudioContextOptions(
        numberOfChannels: 2,
        length: 1,
        sampleRate: 44100,
      ));
      final buffer = await ctx.decodeAudioData(bytes).toDart;
      final left = buffer.getChannelData(0).toDart;
      final right = buffer.numberOfChannels > 1
          ? buffer.getChannelData(1).toDart
          : left;
      return DecodedPcm(left, right);
    } catch (_) {
      return null;
    }
  }

  // --- Wake lock (Blackout / Caffeine) ---

  static web.WakeLockSentinel? _sentinel;

  static Future<void> setKeepScreenOn(bool on) async {
    try {
      if (on) {
        _sentinel ??=
            await web.window.navigator.wakeLock.request('screen').toDart;
      } else {
        await _sentinel?.release().toDart;
        _sentinel = null;
      }
    } catch (_) {
      // Unsupported browser / not allowed — the demo works regardless.
    }
  }
}

class DecodedPcm {
  const DecodedPcm(this.left, this.right);

  /// 44100 Hz Float32 channel data. Mono sources duplicate into both.
  final Float32List left;
  final Float32List right;
}
