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
/// The `gamepads` plugin reports keys per-platform, so this handles both
/// conventions: the **Linux joystick API** (numeric keys "0".."10",
/// analog axes in ±32767 — this is the desktop path we test) and the
/// **Android/SDL** naming ("button-0", "dpad-up", ±1.0). Degrades to a
/// no-op when no controller is present.
class GamepadService {
  GamepadService({
    required this.onDirection,
    required this.onActivate,
    required this.onBack,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
  });

  final void Function(TraversalDirection) onDirection;
  final VoidCallback onActivate;
  final VoidCallback onBack;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  StreamSubscription<GamepadEvent>? _sub;

  // Analog sticks / hat axes fire a flood of values; latch once per push
  // past the deadzone and re-arm only when the axis recenters.
  bool _hActive = false;
  bool _vActive = false;
  static const _deadzone = 0.55;

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

  /// Linux js values are ±32767; SDL/Android are ±1.0. Fold both into
  /// a −1..1 range so the deadzone logic is platform-independent.
  double _norm(double v) => v.abs() > 1.5 ? v / 32767.0 : v;

  void _onEvent(GamepadEvent e) {
    final key = e.key.toLowerCase();

    if (e.type == KeyType.analog) {
      _handleAnalog(key, _norm(e.value));
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
