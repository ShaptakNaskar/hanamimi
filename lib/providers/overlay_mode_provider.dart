import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop "pin as mini overlay" (3.0 feedback) — Hanamimi's answer to
/// Spotify's floating miniplayer. Rather than a second Flutter engine
/// (desktop_multi_window is heavy and flaky on Linux/media_kit), we shrink
/// THIS window into a small always-on-top player and restore it on exit.
///
/// The window's bounds are captured on the way in and put back on the way
/// out; the minimum size is temporarily lowered so the OS/WM will actually
/// let the window get compact (the normal floor is 360×600).
///
/// Note: the bootstrap's _WindowBoundsSaver persists size on every resize,
/// so quitting WHILE pinned remembers the compact size for next launch —
/// harmless (it clamps back up to the min) and self-heals on the first
/// resize. Exiting normally restores + re-saves the real size.
class OverlayModeNotifier extends Notifier<bool> {
  Rect? _savedBounds;

  /// The compact overlay footprint. Tall enough for art/visualizer +
  /// title + seek + transport, narrow like a phone.
  static const _compact = Size(360, 460);

  /// The app's normal minimum, mirrored from desktop_bootstrap's
  /// WindowOptions — restored on exit.
  static const _normalMin = Size(360, 600);

  @override
  bool build() => false;

  Future<void> enter() async {
    if (state) return;
    _savedBounds = await windowManager.getBounds();
    await windowManager.setMinimumSize(const Size(300, 380));
    await windowManager.setSize(_compact);
    await windowManager.setAlwaysOnTop(true);
    state = true;
  }

  Future<void> exit() async {
    if (!state) return;
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setMinimumSize(_normalMin);
    final bounds = _savedBounds;
    if (bounds != null) {
      await windowManager.setBounds(bounds);
    }
    _savedBounds = null;
    state = false;
  }

  Future<void> toggle() => state ? exit() : enter();
}

final overlayModeProvider =
    NotifierProvider<OverlayModeNotifier, bool>(OverlayModeNotifier.new);
