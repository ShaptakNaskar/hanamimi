import 'dart:io';

import 'package:flutter/services.dart';

import '../platform/desktop/desktop_ytdlp.dart';
import 'models/resolved_stream.dart';

/// Dart side of the embedded yt-dlp bridge (M28, plus-only). Mirrors the
/// media_store_channel style: a thin MethodChannel wrapper that never
/// throws — every failure returns null so the caller can fall back to
/// the pure-Dart youtube_explode path.
///
/// See android/.../YtDlpChannel.kt. We stay on no-PO-token player
/// clients, so there's no Node.js/BotGuard companion to install.
/// Desktop runs the real standalone yt-dlp as a subprocess instead
/// (DesktopYtDlp) — same contract, more capable.
class YtDlpChannel {
  static const _ch = MethodChannel('hanamimi/ytdlp');

  /// Best audio stream for a YouTube video id, or null on any failure
  /// (init failed, extraction broke, native crash). yt-dlp deciphers the
  /// `n` param itself, so the returned URL downloads at full speed.
  static Future<ResolvedStream?> resolve(
      String videoId, StreamQuality quality) async {
    if (!Platform.isAndroid) return DesktopYtDlp.resolve(videoId, quality);
    try {
      final map = await _ch.invokeMapMethod<String, dynamic>('resolve', {
        'id': videoId,
        'quality': quality.name, // 'low' → bestaudio[abr<=96], 'high' → bestaudio
      });
      final url = map?['url'] as String?;
      if (url == null) return null;

      final expiresAtMs = map!['expiresAtMs'] as int?;
      return ResolvedStream(
        url: Uri.parse(url),
        // Empty headers: stream_resolver injects a Dart UA to route
        // playback through its caching proxy, and download() fetches the
        // URL directly. android_vr URLs serve on both paths.
        codec: map['codec'] as String?,
        bitrateKbps: (map['abr'] as num?)?.round(),
        sampleRateHz: (map['asr'] as num?)?.toInt(),
        container: map['ext'] as String?,
        // yt-dlp deciphered the `n` param, so googlevideo serves this
        // URL at full speed — the visualizer can decode it for real bands.
        fullSpeed: true,
        expiresAt: expiresAtMs != null
            ? DateTime.fromMillisecondsSinceEpoch(expiresAtMs)
            : DateTime.now().add(const Duration(hours: 1)),
      );
    } catch (_) {
      return null;
    }
  }

  /// Pulls a fresh yt-dlp at runtime (the "Update extractor" settings
  /// action). Returns the new version string, or null on failure.
  static Future<String?> update() async {
    if (!Platform.isAndroid) return DesktopYtDlp.update();
    try {
      return await _ch.invokeMethod<String>('update');
    } catch (_) {
      return null;
    }
  }

  /// Desktop-only (M41): read the YT session cookies from an installed
  /// browser via yt-dlp `--cookies-from-browser`. [profile] optionally
  /// points at a specific profile folder for browsers/forks the default
  /// lookup misses. Android uses the in-app WebView instead, so this
  /// returns null there.
  static Future<String?> cookiesFromBrowser(String browser,
      {String? profile}) async {
    if (Platform.isAndroid) return null;
    return DesktopYtDlp.cookiesFromBrowser(browser, profile: profile);
  }

  /// Why the last [cookiesFromBrowser] returned null (desktop only).
  static String? get lastCookieError =>
      Platform.isAndroid ? null : DesktopYtDlp.lastCookieError;

  /// Parse a pasted cookies.txt (or raw Cookie header) into a header
  /// string — the extension-paste escape hatch. Pure string work, so it
  /// is safe on every platform.
  static String? cookieHeaderFromText(String text) =>
      DesktopYtDlp.cookieHeaderFromText(text);

  /// Current yt-dlp version (null if never initialized / unavailable).
  static Future<String?> version() async {
    if (!Platform.isAndroid) return DesktopYtDlp.version();
    try {
      return await _ch.invokeMethod<String>('version');
    } catch (_) {
      return null;
    }
  }
}
