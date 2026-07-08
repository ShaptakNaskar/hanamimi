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
/// - **Windows**: run the downloaded installer silently (/VERYSILENT)
///   and exit; Inno reinstalls into the same folder (UsePreviousAppDir)
///   and a silent-only [Run] entry relaunches the app. No wizard, no
///   clicks — the app just blinks and comes back updated.
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
        // Silent, unattended reinstall over the current install. We exit
        // right after so the running .exe unlocks; /FORCECLOSEAPPLICATIONS
        // is the safety net if any file is still held.
        await Process.start(path, [
          '/VERYSILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/FORCECLOSEAPPLICATIONS',
        ], mode: ProcessStartMode.detached);
        exit(0);
      }
    } catch (_) {}
    return false;
  }
}
