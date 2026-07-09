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

  /// The last stderr from [cookiesFromBrowser], surfaced to the sign-in
  /// dialog so a failure explains itself (browser not found, profile in a
  /// non-standard location, keyring locked…) instead of a blank "no
  /// session" message.
  static String? lastCookieError;

  /// Desktop Tier 3 sign-in (M41): extract the YT Music session cookies
  /// straight out of an installed browser's profile via yt-dlp's
  /// `--cookies-from-browser`, no WebView needed. Prefer **Firefox** —
  /// Chrome ≥127 on Windows added App-Bound Encryption that breaks
  /// Chromium cookie extraction. Returns a `Cookie:` header string
  /// (name=value; …) scoped to youtube domains, or null when the
  /// browser has no logged-in session.
  ///
  /// [profile] optionally points yt-dlp at a specific profile FOLDER —
  /// needed when the browser stores its profile somewhere the default
  /// lookup misses (Firefox under `~/.config/mozilla`, Snap/Flatpak
  /// sandboxes, or a Chromium fork like Thorium). yt-dlp's spec is
  /// `BROWSER[:PROFILE_PATH]`; a fork can be read as e.g. `chromium` with
  /// the fork's profile path.
  static Future<String?> cookiesFromBrowser(String browser,
      {String? profile}) async {
    lastCookieError = null;
    final bin = await _ensureBinary(allowDownload: true);
    if (bin == null) {
      lastCookieError = 'yt-dlp is not available.';
      return null;
    }
    // `browser:profile` when a path is given (yt-dlp reads a fork/moved
    // profile this way); bare browser name otherwise.
    final cleaned = _sanitizeProfilePath(profile);
    final spec = cleaned != null ? '$browser:$cleaned' : browser;
    // Write to a fresh temp FILE, not stdout. `--cookies -` does NOT
    // reliably dump the jar to stdout (it came back empty in testing);
    // `--cookies <file>` does. The file must NOT pre-exist — `--cookies`
    // is bidirectional and tries to LOAD an existing file first, erroring
    // "does not look like a Netscape format cookies file" on an empty one.
    final dir = await Directory.systemTemp.createTemp('hana_ytck');
    final jar = File('${dir.path}/cookies.txt');
    try {
      final res = await Process.run(bin, [
        '--cookies-from-browser', spec,
        '--cookies', jar.path,
        '--skip-download',
        '--no-warnings',
        // Enumerate nothing — we only want the jar loaded and written, not
        // a video resolved (which trips YouTube's bot checks / nsig).
        '--playlist-items', '0',
        // An ALWAYS-SUPPORTED page. NOT music.youtube.com/ — yt-dlp
        // rejects that bare host as an "Unsupported URL" and exits
        // non-zero, throwing the freshly-read cookies away (the real
        // reason browser-import never worked). www + playlist-items 0
        // loads cookies and writes the jar in ~3s.
        'https://www.youtube.com/',
      ]).timeout(const Duration(seconds: 45));
      if (res.exitCode != 0 || !jar.existsSync()) {
        lastCookieError = _tidyError(res.stderr as String);
        return null;
      }
      final header = _cookieHeaderFromNetscape(jar.readAsStringSync());
      if (header == null) {
        lastCookieError = 'No YouTube/Google cookies in that profile — '
            'is it signed in to YouTube?';
      }
      return header;
    } catch (e) {
      lastCookieError = e.toString();
      return null;
    } finally {
      // Never leave the session cookies lying in /tmp.
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// Clean a user-pasted profile path for yt-dlp's `browser:PROFILE`
  /// spec. Returns null for blank input.
  ///
  /// Windows is the sharp edge: Explorer's "Copy as path" wraps the path
  /// in double quotes (`"C:\Users\…\Profiles\x.default"`), which yt-dlp
  /// then treats as part of the filename and can't find — so strip a
  /// single surrounding pair of quotes. Backslashes are LEFT INTACT
  /// (yt-dlp is handed the arg directly, no shell, and a Windows abs path
  /// like `C:\…` is used verbatim there); only wrapping quotes and stray
  /// whitespace are removed.
  static String? _sanitizeProfilePath(String? raw) {
    if (raw == null) return null;
    var p = raw.trim();
    if (p.length >= 2) {
      final first = p[0], last = p[p.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        p = p.substring(1, p.length - 1).trim();
      }
    }
    return p.isEmpty ? null : p;
  }

  /// First meaningful line of a yt-dlp stderr blob, trimmed for display.
  static String _tidyError(String stderr) {
    for (final line in const LineSplitter().convert(stderr)) {
      final t = line.trim();
      if (t.isEmpty) continue;
      return t.replaceFirst(RegExp(r'^ERROR:\s*'), '');
    }
    return 'yt-dlp could not read that browser profile.';
  }

  /// Parse a pasted cookies blob into a `Cookie:` header. Accepts either a
  /// Netscape `cookies.txt` (what "Get cookies.txt LOCALLY" and similar
  /// extensions export) OR an already-formed `name=value; …` header
  /// string. This is the extension-paste escape hatch for browsers/forks
  /// yt-dlp can't read directly. Returns null if nothing usable is found.
  static String? cookieHeaderFromText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    // Netscape format has TAB-separated 7-column rows.
    if (trimmed.contains('\t')) {
      final header = _cookieHeaderFromNetscape(trimmed);
      if (header != null) return header;
    }
    // Otherwise treat it as a raw Cookie header (must at least carry the
    // SAPISID/__Secure-3PAPISID auth secret to be a real session).
    if (trimmed.contains('SAPISID') ||
        trimmed.contains('__Secure-3PAPISID')) {
      return trimmed;
    }
    return null;
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
      // NIGHTLY keeps up with YouTube's player changes far better than
      // the stable channel; fall back to a plain self-update if this
      // build of yt-dlp doesn't understand --update-to.
      var res = await Process.run(bin, ['--update-to', 'nightly'])
          .timeout(const Duration(minutes: 3));
      if (res.exitCode != 0) {
        res = await Process.run(bin, ['-U']).timeout(const Duration(minutes: 3));
      }
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
