import 'dart:io';

/// Desktop self-update (ARCHITECTURE-DESKTOP.md §7). Same GitHub
/// Releases feed and UpdaterChannel contract as Android; only the
/// install step differs:
///
/// - **Linux/AppImage**: replace the running .AppImage in place and
///   relaunch it (the sideload ethos — no package manager involved).
///   Outside an AppImage (dev run, distro package) there's nothing we
///   can safely swap, so canInstall is false and the dialog falls back
///   to "open the release page".
/// - **Windows**: launch the downloaded installer and exit; the
///   installer replaces the app.
class DesktopUpdater {
  /// The path of the running AppImage, set by AppImage runtimes.
  static String? get _appImage => Platform.environment['APPIMAGE'];

  static Future<bool> canInstall() async {
    if (Platform.isLinux) return _appImage != null;
    return Platform.isWindows;
  }

  static Future<bool> install(String path) async {
    try {
      if (Platform.isLinux) {
        final target = _appImage;
        if (target == null) return false;
        // Swap atomically-ish: new image next to the old, then rename
        // over it (same filesystem). The running process keeps its
        // mapped pages; the relaunch picks up the new file.
        final staging = File('$target.new');
        await File(path).copy(staging.path);
        await Process.run('chmod', ['+x', staging.path]);
        await staging.rename(target);
        await Process.start(target, [], mode: ProcessStartMode.detached);
        exit(0);
      }
      if (Platform.isWindows) {
        await Process.start(path, [], mode: ProcessStartMode.detached);
        exit(0);
      }
    } catch (_) {}
    return false;
  }
}
