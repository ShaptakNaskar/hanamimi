import 'dart:io';

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
}
