import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../online/models/resolved_stream.dart';
import 'desktop_binaries.dart';

/// Desktop implementation of the yt-dlp contract
/// (ARCHITECTURE-DESKTOP.md §3): the real standalone yt-dlp binary as a
/// subprocess — bundled with the app, or fetched once into the app
/// support dir when missing (mirroring youtubedl-android's lazy init).
/// Same never-throw shape as YtDlpChannel: null means "fall back to
/// youtube_explode".
class DesktopYtDlp {
  static const _releaseUrl =
      'https://github.com/yt-dlp/yt-dlp/releases/latest/download/';

  /// Coalesces concurrent first-use downloads.
  static Future<String?>? _binaryFuture;

  static Future<ResolvedStream?> resolve(
      String videoId, StreamQuality quality) async {
    final bin = await _ensureBinary(allowDownload: true);
    if (bin == null) return null;
    try {
      final res = await Process.run(bin, [
        'https://www.youtube.com/watch?v=$videoId',
        '-f',
        quality == StreamQuality.low
            ? 'bestaudio[abr<=96]/bestaudio'
            : 'bestaudio',
        '--no-playlist',
        '--no-warnings',
        // Same no-PO-token clients the Android embed uses (M28).
        '--extractor-args', 'youtube:player_client=android_vr,web_embedded',
        '--dump-single-json',
      ]).timeout(const Duration(seconds: 45));
      if (res.exitCode != 0) return null;
      final info = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      final url = info['url'] as String?;
      if (url == null) return null;

      final uri = Uri.parse(url);
      // googlevideo URLs carry their death date (?expire=<unix seconds>).
      final expireParam = int.tryParse(uri.queryParameters['expire'] ?? '');
      return ResolvedStream(
        url: uri,
        codec: info['acodec'] as String?,
        bitrateKbps: (info['abr'] as num?)?.round(),
        sampleRateHz: (info['asr'] as num?)?.toInt(),
        container: info['ext'] as String?,
        // yt-dlp deciphered the `n` param — full-speed URL, so the
        // visualizer can decode it for real bands.
        fullSpeed: true,
        expiresAt: expireParam != null
            ? DateTime.fromMillisecondsSinceEpoch(expireParam * 1000)
            : DateTime.now().add(const Duration(hours: 1)),
      );
    } catch (_) {
      return null;
    }
  }

  /// Desktop Tier 3 sign-in (M41): extract the YT Music session cookies
  /// straight out of an installed browser's profile via yt-dlp's
  /// `--cookies-from-browser`, no WebView needed. Prefer **Firefox** —
  /// Chrome ≥127 on Windows added App-Bound Encryption that breaks
  /// Chromium cookie extraction. Returns a `Cookie:` header string
  /// (name=value; …) scoped to youtube domains, or null when the
  /// browser has no logged-in session.
  static Future<String?> cookiesFromBrowser(String browser) async {
    final bin = await _ensureBinary(allowDownload: true);
    if (bin == null) return null;
    try {
      final res = await Process.run(bin, [
        '--cookies-from-browser', browser,
        '--cookies', '-', // write Netscape cookies.txt to stdout
        '--skip-download',
        '--no-warnings',
        // A cheap page that forces the cookie jar to be read/emitted.
        'https://music.youtube.com/',
      ]).timeout(const Duration(seconds: 45));
      if (res.exitCode != 0) return null;
      return _cookieHeaderFromNetscape(res.stdout as String);
    } catch (_) {
      return null;
    }
  }

  /// Netscape cookies.txt → `name=value; …` for youtube/google domains.
  static String? _cookieHeaderFromNetscape(String text) {
    final pairs = <String>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.startsWith('#') || line.trim().isEmpty) continue;
      final cols = line.split('\t');
      if (cols.length < 7) continue;
      final domain = cols[0];
      if (!domain.contains('youtube.com') && !domain.contains('google.com')) {
        continue;
      }
      pairs.add('${cols[5]}=${cols[6]}');
    }
    return pairs.isEmpty ? null : pairs.join('; ');
  }

  /// The "Update extractor" settings action. The standalone binary
  /// self-updates with -U; a distro-packaged one can't, so the fallback
  /// is a fresh download into the support dir (which then shadows PATH).
  static Future<String?> update() async {
    final bin = await _ensureBinary(allowDownload: true);
    if (bin == null) return null;
    try {
      final res =
          await Process.run(bin, ['-U']).timeout(const Duration(minutes: 3));
      if (res.exitCode == 0) return version();
    } catch (_) {}
    final fresh = await _download();
    return fresh == null ? null : version();
  }

  static Future<String?> version() async {
    // No download for a passive version display.
    final bin = await _ensureBinary(allowDownload: false);
    if (bin == null) return null;
    try {
      final res = await Process.run(bin, ['--version'])
          .timeout(const Duration(seconds: 15));
      if (res.exitCode != 0) return null;
      final v = (res.stdout as String).trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _ensureBinary({required bool allowDownload}) {
    return _binaryFuture ??= () async {
      if (await DesktopBinaries.works('yt-dlp')) {
        return DesktopBinaries.find('yt-dlp');
      }
      if (!allowDownload) {
        _binaryFuture = null; // retry once resolution actually needs it
        return null;
      }
      final path = await _download();
      if (path == null) _binaryFuture = null; // offline now ≠ offline later
      return path;
    }();
  }

  static Future<String?> _download() async {
    final dir = DesktopBinaries.supportBinDir;
    if (dir == null) return null;
    try {
      final name = Platform.isWindows ? 'yt-dlp.exe' : 'yt-dlp';
      final res = await http
          .get(Uri.parse('$_releaseUrl$name'))
          .timeout(const Duration(minutes: 3));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      await Directory(dir).create(recursive: true);
      final file = File('$dir/$name');
      await file.writeAsBytes(res.bodyBytes, flush: true);
      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', file.path]);
      }
      DesktopBinaries.supportBinDir = dir; // clear the lookup cache
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
