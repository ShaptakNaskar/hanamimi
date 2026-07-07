import 'dart:io';
import 'dart:ui';

import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

import '../../library/open_with_channel.dart';
import 'desktop_binaries.dart';

/// One-stop desktop init (ARCHITECTURE-DESKTOP.md): media_kit, the ffi
/// SQLite backend, helper-binary lookup, open-with args and the window.
/// Called from main() before anything touches audio or the DB;
/// Android never reaches this file.
Future<void> initDesktop(List<String> args, SharedPreferences prefs) async {
  MediaKit.ensureInitialized();

  // Same schema and SQL as Android — only the backend switches.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  DesktopBinaries.supportBinDir =
      '${(await getApplicationSupportDirectory()).path}/bin';

  // "Open with Hanamimi" on desktop = file paths as launch arguments.
  OpenWithChannel.desktopPendingFromArgs(args);

  await windowManager.ensureInitialized();
  final size = Size(
    prefs.getDouble(_kWindowW) ?? 420,
    prefs.getDouble(_kWindowH) ?? 780,
  );
  const options = WindowOptions(
    title: 'Hanamimi+ 花耳',
    minimumSize: Size(360, 600),
    center: true,
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setSize(size);
    await windowManager.show();
    await windowManager.focus();
  });
  windowManager.addListener(_WindowBoundsSaver(prefs));
}

const _kWindowW = 'desktop_window_w';
const _kWindowH = 'desktop_window_h';

/// Remembers the window size across launches (position is left to the
/// window manager — tiling WMs place windows themselves anyway).
class _WindowBoundsSaver with WindowListener {
  _WindowBoundsSaver(this.prefs);
  final SharedPreferences prefs;

  @override
  void onWindowResized() async {
    final size = await windowManager.getSize();
    await prefs.setDouble(_kWindowW, size.width);
    await prefs.setDouble(_kWindowH, size.height);
  }
}

/// True on the platforms this bootstrap covers. UI code uses this
/// instead of raw Platform checks so a future macOS port is one edit.
bool get isDesktop =>
    Platform.isLinux || Platform.isWindows || Platform.isMacOS;
