import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Locates the helper binaries the desktop build leans on (ffmpeg,
/// ffprobe, yt-dlp). Search order (ARCHITECTURE-DESKTOP.md §3):
///
///   1. next to the app executable — where the AppImage / installer
///      bundles them,
///   2. the app-support `bin/` dir — where a runtime download lands
///      (yt-dlp fetched on demand, mirroring youtubedl-android's init),
///   3. bare name — resolved through PATH by the OS (dev machines,
///      distro packages).
class DesktopBinaries {
  static final _cache = <String, String>{};

  static String find(String name) => _cache.putIfAbsent(name, () {
        final exe = Platform.isWindows ? '$name.exe' : name;
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        for (final candidate in [
          '$exeDir/$exe',
          '$exeDir/bin/$exe',
          if (_supportBin != null) '$_supportBin/$exe',
        ]) {
          if (File(candidate).existsSync()) return candidate;
        }
        return exe; // PATH
      });

  /// Set once at startup (path_provider needs a running engine); until
  /// then lookups skip the support-dir candidate.
  static String? _supportBin;
  static String? get supportBinDir => _supportBin;
  static set supportBinDir(String? dir) {
    _supportBin = dir;
    _cache.clear();
  }

  /// True when [name] resolves to something that actually runs.
  static Future<bool> works(String name) async {
    try {
      final res = await Process.run(find(name), ['-version']);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Desktop self-setup: ffmpeg/ffprobe power the library scan, album
  /// art and the visualizer. When neither a bundled nor a system copy
  /// exists (slim installer / AppImage — kept under Telegram's 50 MB
  /// bot limit), fetch the static build once into the support dir,
  /// exactly like yt-dlp's lazy init. Fire-and-forget from the
  /// bootstrap; scans just find no tags until it lands, then the next
  /// rescan fills in.
  static Future<void> ensureMediaTools() async {
    if (Platform.isAndroid) return;
    if (await works('ffmpeg') && await works('ffprobe')) return;
    final dir = _supportBin;
    if (dir == null) return;
    try {
      await Directory(dir).create(recursive: true);
      if (Platform.isWindows) {
        final zip = File('$dir/ffmpeg-download.zip');
        final res = await http
            .get(Uri.parse(
                'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip'))
            .timeout(const Duration(minutes: 10));
        if (res.statusCode != 200 || res.bodyBytes.isEmpty) return;
        await zip.writeAsBytes(res.bodyBytes, flush: true);
        // Windows always has PowerShell — no archive dependency needed.
        await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          'Expand-Archive -Force "${zip.path}" "$dir/ffmpeg-tmp"; '
              'Copy-Item "$dir/ffmpeg-tmp/*/bin/ffmpeg.exe" "$dir/"; '
              'Copy-Item "$dir/ffmpeg-tmp/*/bin/ffprobe.exe" "$dir/"; '
              'Remove-Item -Recurse -Force "$dir/ffmpeg-tmp", "${zip.path}"',
        ]);
      } else if (Platform.isLinux) {
        final tarball = File('$dir/ffmpeg-download.tar.xz');
        final res = await http
            .get(Uri.parse(
                'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz'))
            .timeout(const Duration(minutes: 10));
        if (res.statusCode != 200 || res.bodyBytes.isEmpty) return;
        await tarball.writeAsBytes(res.bodyBytes, flush: true);
        // GNU tar is part of every desktop distro base.
        await Process.run('tar', [
          '-xJf', tarball.path,
          '-C', dir,
          '--strip-components=2',
          '--wildcards', '*/bin/ffmpeg', '*/bin/ffprobe',
        ]);
        await tarball.delete();
      }
      _cache.clear(); // re-resolve now that the binaries exist
    } catch (_) {}
  }
}
