import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:gamepads/gamepads.dart';

/// Couch-mode gamepad input (ROG Ally / Steam Deck / any pad). Maps a
/// controller to the two things that matter on a handheld: **transport**
/// (bumpers = prev/next, a face button = play/pause) and **directional
/// focus** (D-pad / left stick move the Flutter focus, so the whole UI
/// is reachable without touching the screen). A face button activates
/// the focused control; another steps back.
///
/// The `gamepads` plugin reports keys per-platform, so this handles three
/// conventions (the ROG Ally's embedded pad is an XInput/Xbox-360 device
/// on every OS, but each backend surfaces it differently):
///
///  * **Linux joydev** — numeric keys "0".."10", analog axes signed
///    ±32767, D-pad = hat axes 6 (X) / 7 (Y). The desktop path we test.
///  * **Windows WinMM** (`joyGetPosEx`) — buttons "button-N", analog axes
///    UNSIGNED 0..65535 (centre ≈32767), and the **D-pad as a POV hat**
///    (`key:"pov"`, an angle in centidegrees, NOT an axis). Both the
///    unsigned range and the POV hat were unhandled originally, which
///    left the whole thing dead on the Ally under Windows.
///  * **Android/SDL** — named keys ("button-0", "dpad-up"), values ±1.0.
///
/// Degrades to a no-op when no controller is present.
class GamepadService {
  GamepadService({
    required this.onDirection,
    required this.onActivate,
    required this.onBack,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.isActive,
  });

  final void Function(TraversalDirection) onDirection;
  final VoidCallback onActivate;
  final VoidCallback onBack;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  /// Only act on controller input while Hanamimi is foregrounded/focused.
  /// The desktop backend reads the raw joystick device, which keeps firing
  /// even when another window (e.g. a game) has focus — without this gate,
  /// gaming input would skip your music (user-reported).
  final bool Function() isActive;

  StreamSubscription<GamepadEvent>? _sub;

  // Analog sticks / hat axes fire a flood of values; latch once per push
  // past the deadzone and re-arm only when the axis recenters.
  bool _hActive = false;
  bool _vActive = false;
  static const _deadzone = 0.55;

  // Last cardinal fired by the Windows POV hat, or null when centred —
  // a POV can swing straight between directions without recentring, so
  // we fire on every direction *change*, not just on leaving centre.
  TraversalDirection? _povDir;

  void start() {
    try {
      _sub = Gamepads.events.listen(_onEvent);
    } catch (_) {
      // No gamepad backend on this platform/build — stay a no-op.
    }
  }

  void dispose() {
    _sub?.cancel();
  }

  /// Fold every backend's axis range into −1..1 so the deadzone logic is
  /// platform-independent. Detected by key SHAPE (not `Platform`, so it
  /// stays valid on web): Windows WinMM axes are named "dw…" and unsigned
  /// 0..65535; Linux joydev axes are signed ±32767; SDL/Android are ±1.0.
  double _norm(String key, double v) {
    if (key.startsWith('dw')) return (v - 32767.5) / 32767.5; // Windows
    if (v.abs() > 1.5) return v / 32767.0; // Linux joydev
    return v; // SDL/Android already −1..1
  }

  void _onEvent(GamepadEvent e) {
    // Ignore controller input unless Hanamimi is the active window —
    // otherwise a game's rapid inputs would drive the player.
    if (!isActive()) return;
    final key = e.key.toLowerCase();

    if (e.type == KeyType.analog) {
      // Windows surfaces the D-pad as a POV hat (an angle), not an axis.
      if (key == 'pov') {
        _handlePov(e.value);
        return;
      }
      _handleAnalog(key, _norm(key, e.value));
      return;
    }

    // Buttons: 1.0 = pressed, 0.0 = released. Act on the press edge.
    if (e.value <= 0.5) return;

    // Android/SDL name their D-pad as a button; Linux sends it as an
    // axis (handled above). Cover the named form here.
    if (key.contains('dpad') || key.contains('hat')) {
      if (key.contains('up')) return onDirection(TraversalDirection.up);
      if (key.contains('down')) return onDirection(TraversalDirection.down);
      if (key.contains('left')) return onDirection(TraversalDirection.left);
      if (key.contains('right')) {
        return onDirection(TraversalDirection.right);
      }
    }

    // Normalize "button-4" / "4" → the bare index for a single mapping.
    final idx = int.tryParse(key.replaceAll(RegExp(r'[^0-9]'), ''));
    switch (idx) {
      case 0: // A / cross — activate the focused control
        onActivate();
      case 1: // B / circle — back
        onBack();
      case 4: // LB — previous track
        onPrevious();
      case 5: // RB — next track
        onNext();
      case 6: // Back/Select
      case 7: // Start/Menu — play/pause
        onPlayPause();
      default:
        if (key.contains('start') || key.contains('menu')) onPlayPause();
    }
  }

  /// Windows POV hat (the D-pad): an angle in centidegrees — 0=up,
  /// 9000=right, 18000=down, 27000=left — or 65535 (JOY_POVCENTERED)
  /// when released. Snap 8-way angles to the nearest cardinal for focus
  /// traversal and fire once per direction change.
  void _handlePov(double raw) {
    final v = raw.round();
    // Anything outside a real 0..35999 angle means "centred".
    if (v < 0 || v >= 36000) {
      _povDir = null;
      return;
    }
    final deg = v / 100.0;
    final dir = (deg >= 315 || deg < 45)
        ? TraversalDirection.up
        : deg < 135
            ? TraversalDirection.right
            : deg < 225
                ? TraversalDirection.down
                : TraversalDirection.left;
    if (dir == _povDir) return; // still held the same way — don't repeat
    _povDir = dir;
    onDirection(dir);
  }

  /// Test seam: drive a synthetic controller event through the mapping
  /// (the real path is [Gamepads.events], which a test can't feed).
  @visibleForTesting
  void debugHandleEvent(GamepadEvent e) => _onEvent(e);

  void _handleAnalog(String key, double value) {
    final idx = int.tryParse(key.replaceAll(RegExp(r'[^0-9]'), ''));
    // Horizontal: left-stick X (axis 0) or D-pad hat X (axis 6).
    final horizontal =
        idx == 0 || idx == 6 || key.contains('x') || key.contains('left');
    // Vertical: left-stick Y (axis 1) or D-pad hat Y (axis 7).
    final vertical =
        idx == 1 || idx == 7 || key.contains('y') || key.contains('up');

    if (horizontal) {
      if (value.abs() < 0.2) {
        _hActive = false;
      } else if (!_hActive && value.abs() > _deadzone) {
        _hActive = true;
        onDirection(value > 0
            ? TraversalDirection.right
            : TraversalDirection.left);
      }
    }
    if (vertical) {
      if (value.abs() < 0.2) {
        _vActive = false;
      } else if (!_vActive && value.abs() > _deadzone) {
        _vActive = true;
        // Down is positive on both js and SDL sticks/hats.
        onDirection(
            value > 0 ? TraversalDirection.down : TraversalDirection.up);
      }
    }
  }
}
