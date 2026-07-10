import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../providers/window_activity_provider.dart';

// oneko — cursor-chasing cat. Native Dart port of oneko.js by adryd
// (https://github.com/adryd325/oneko.js), which revives the classic X11
// `neko`; the bundled sprite sheet (assets/oneko/oneko.png) is from that
// project. Brought in as an app buddy after the Vencord oneko plugin by
// V (https://vencord.dev/plugins/oneko). Both are GPLv3, as is this app.

/// oneko — the classic pointer-chasing cat (adryd325/oneko.js, itself
/// the X11 `neko`). On desktop she chases the mouse; on touch screens
/// she chases your taps and drags, reaches the last spot your finger
/// touched, gets bored, and naps there.
///
/// Faithful port of oneko.js: 32px sprites lifted from the 256x128 sheet,
/// 10px per step at 10 fps, with the alert / idle / tired / sleeping /
/// scratch behaviours. Wrap the shell body — hover events bubble to the
/// [Listener] even over buttons and lists, so the cat sees the pointer
/// everywhere without ever absorbing a click.
class OnekoLayer extends StatefulWidget {
  const OnekoLayer({super.key, required this.child});

  final Widget child;

  @override
  State<OnekoLayer> createState() => _OnekoLayerState();
}

class _OnekoLayerState extends State<OnekoLayer> {
  final _cursor = ValueNotifier<Offset?>(null);

  @override
  void dispose() {
    _cursor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Listener(
          // translucent, not deferToChild: without it, moving over the
          // empty parts of a pane (no widget to hit) fires no hover and
          // the cat chases a stale point, then sleeps mid-window. This
          // keeps the Listener in the hit path everywhere without
          // swallowing clicks from the panes below.
          behavior: HitTestBehavior.translucent,
          onPointerHover: (e) => _cursor.value = e.localPosition,
          onPointerMove: (e) => _cursor.value = e.localPosition,
          // Touch screens have no hover — taps are how the cat learns
          // where your finger went.
          onPointerDown: (e) => _cursor.value = e.localPosition,
          child: widget.child,
        ),
        // The cat is decoration — never let it eat a tap.
        Positioned.fill(
          child: IgnorePointer(child: _OnekoPet(cursor: _cursor)),
        ),
      ],
    );
  }
}

/// Grid (column, row) of each 32px sprite on the sheet. Derived from
/// oneko.js's negated background-position pairs.
const _sprites = <String, List<List<int>>>{
  'idle': [
    [3, 3]
  ],
  'alert': [
    [7, 3]
  ],
  'tired': [
    [3, 2]
  ],
  'sleeping': [
    [2, 0],
    [2, 1]
  ],
  'scratchSelf': [
    [5, 0],
    [6, 0],
    [7, 0]
  ],
  'scratchWallN': [
    [0, 0],
    [0, 1]
  ],
  'scratchWallS': [
    [7, 1],
    [6, 2]
  ],
  'scratchWallE': [
    [2, 2],
    [2, 3]
  ],
  'scratchWallW': [
    [4, 0],
    [4, 1]
  ],
  'N': [
    [1, 2],
    [1, 3]
  ],
  'NE': [
    [0, 2],
    [0, 3]
  ],
  'E': [
    [3, 0],
    [3, 1]
  ],
  'SE': [
    [5, 1],
    [5, 2]
  ],
  'S': [
    [6, 3],
    [7, 2]
  ],
  'SW': [
    [5, 3],
    [6, 1]
  ],
  'W': [
    [4, 2],
    [4, 3]
  ],
  'NW': [
    [1, 0],
    [1, 1]
  ],
};

/// The oneko cat curled up asleep — parked beside the edition logo
/// (the Vencord look) when she isn't chasing the pointer: follow
/// switched off on desktop, or always on mobile, where there is no
/// pointer to chase. Same sprite sheet, just the two sleeping frames
/// on a slow blink.
class SleepingOneko extends StatefulWidget {
  const SleepingOneko({super.key, this.size = 28});

  final double size;

  @override
  State<SleepingOneko> createState() => _SleepingOnekoState();
}

class _SleepingOnekoState extends State<SleepingOneko> {
  Timer? _timer;
  var _frame = 0;

  @override
  void initState() {
    super.initState();
    if (_OnekoPetState._sheet == null) {
      _OnekoPetState._loadSheet().then((_) {
        if (mounted) setState(() {});
      });
    }
    // Matches the chase-mode sleep cadence (sleep frames advance every
    // 4 ticks of the 100 ms clock). A 2-frame timer is too cheap to
    // need gating beyond the visibility check inside.
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted || !windowVisible.value) return;
      setState(() => _frame++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _OnekoPetState._sheet;
    if (sheet == null) return SizedBox(width: widget.size);
    final frames = _sprites['sleeping']!;
    // The sleeping pose sits low in its 32px cell — nudge her up so she
    // rests on the logo's baseline instead of dangling below it.
    return Transform.translate(
      offset: Offset(0, -widget.size * 0.14),
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _SleepingOnekoPainter(
            sheet: sheet,
            pose: frames[_frame % frames.length],
            size: widget.size,
          ),
        ),
      ),
    );
  }
}

class _SleepingOnekoPainter extends CustomPainter {
  _SleepingOnekoPainter({
    required this.sheet,
    required this.pose,
    required this.size,
  });

  final ui.Image sheet;
  final List<int> pose;
  final double size;

  @override
  void paint(Canvas canvas, Size _) {
    final src = Rect.fromLTWH(pose[0] * 32.0, pose[1] * 32.0, 32, 32);
    final dst = Rect.fromLTWH(0, 0, size, size);
    canvas.drawImageRect(
      sheet,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.none // crisp pixels
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(_SleepingOnekoPainter old) =>
      !identical(old.pose, pose) || old.size != size;
}

class _OnekoPet extends StatefulWidget {
  const _OnekoPet({required this.cursor});

  final ValueListenable<Offset?> cursor;

  @override
  State<_OnekoPet> createState() => _OnekoPetState();
}

class _OnekoPetState extends State<_OnekoPet> {
  static const double _speed = 10;
  // oneko runs its logic on a 100 ms clock — a plain timer, because a
  // vsync ticker (even one that skips 5 of 6 callbacks) forces the
  // engine to raster + swap every vsync, and NVIDIA's GL swap
  // busy-waits on CPU (the desktop constant-CPU report).
  static const _stepEvery = Duration(milliseconds: 100);

  // The sheet is loaded once and shared across rebuilds.
  static ui.Image? _sheet;
  static Future<ui.Image>? _loading;

  final _rng = math.Random();
  Timer? _timer;

  Size _area = Size.zero;
  bool _placed = false;
  double _x = 0;
  double _y = 0;
  int _frameCount = 0;
  int _idleTime = 0;
  String? _idleAnimation;
  int _idleFrame = 0;
  List<int> _pose = _sprites['idle']!.first;

  static Future<ui.Image> _loadSheet() {
    return _loading ??= () async {
      final data = await rootBundle.load('assets/oneko/oneko.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      return _sheet = frame.image;
    }();
  }

  @override
  void initState() {
    super.initState();
    if (_sheet != null) {
      _start();
    } else {
      _loadSheet().then((_) {
        if (mounted) {
          setState(() {});
          _start();
        }
      });
    }
  }

  void _start() {
    _timer = Timer.periodic(_stepEvery, (_) {
      if (mounted) _step();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _setPose(String name, int frame) {
    final frames = _sprites[name]!;
    _pose = frames[frame % frames.length];
  }

  void _step() {
    if (!_placed) return;
    // The cat naps while another window has focus (see
    // window_activity_provider) — chasing a cursor nobody is steering
    // kept the render pipeline hot.
    if (!windowFocused.value) return;
    _frameCount++;

    final cursor = widget.cursor.value;
    final tx = cursor?.dx ?? _x;
    final ty = cursor?.dy ?? _y;
    final diffX = _x - tx;
    final diffY = _y - ty;
    final distance = math.sqrt(diffX * diffX + diffY * diffY);

    final prevPose = _pose;
    final prevX = _x;
    final prevY = _y;

    if (distance < _speed || distance < 48) {
      _idle();
    } else {
      _idleAnimation = null;
      _idleFrame = 0;
      if (_idleTime > 1) {
        // Perk up before giving chase.
        _setPose('alert', 0);
        _idleTime = math.min(_idleTime, 7) - 1;
      } else {
        var dir = '';
        if (diffY / distance > 0.5) dir += 'N';
        if (diffY / distance < -0.5) dir += 'S';
        if (diffX / distance > 0.5) dir += 'W';
        if (diffX / distance < -0.5) dir += 'E';
        if (dir.isNotEmpty) _setPose(dir, _frameCount);
        _x -= (diffX / distance) * _speed;
        _y -= (diffY / distance) * _speed;
        _x = _x.clamp(16.0, math.max(16.0, _area.width - 16));
        _y = _y.clamp(16.0, math.max(16.0, _area.height - 16));
      }
    }

    // Only repaint when something visible actually changed — a cat
    // sitting idle shouldn't burn frames (the ticker keeps polling the
    // pointer cheaply either way).
    if (!identical(prevPose, _pose) || prevX != _x || prevY != _y) {
      setState(() {});
    }
  }

  void _idle() {
    _idleTime++;
    if (_idleTime > 10 && _rng.nextInt(200) == 0 && _idleAnimation == null) {
      final avail = <String>['sleeping', 'scratchSelf'];
      if (_x < 32) avail.add('scratchWallW');
      if (_y < 32) avail.add('scratchWallN');
      if (_x > _area.width - 32) avail.add('scratchWallE');
      if (_y > _area.height - 32) avail.add('scratchWallS');
      _idleAnimation = avail[_rng.nextInt(avail.length)];
    }
    // The real neko is a sleepy one: the dice above only MAYBE pick an
    // idle animation (1/200 a tick, sleeping just one option among the
    // scratches), so she could fidget for minutes without nodding off
    // (user report). ~8 s of stillness now guarantees a nap.
    if (_idleAnimation == null && _idleTime > 80) {
      _idleAnimation = 'sleeping';
    }

    switch (_idleAnimation) {
      case 'sleeping':
        if (_idleFrame < 8) {
          _setPose('tired', 0);
          break;
        }
        _setPose('sleeping', _idleFrame ~/ 4);
        if (_idleFrame > 192) _resetIdle();
        break;
      case 'scratchWallN':
      case 'scratchWallS':
      case 'scratchWallE':
      case 'scratchWallW':
        _setPose(_idleAnimation!, _idleFrame);
        if (_idleFrame > 9) _resetIdle();
        break;
      case 'scratchSelf':
        _setPose('scratchSelf', _idleFrame);
        if (_idleFrame > 9) _resetIdle();
        break;
      default:
        _setPose('idle', 0);
        return; // idle pose is static — don't advance the frame counter
    }
    _idleFrame++;
  }

  void _resetIdle() {
    _idleAnimation = null;
    _idleFrame = 0;
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _sheet;
    if (sheet == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth.isFinite && c.maxHeight.isFinite) {
          _area = Size(c.maxWidth, c.maxHeight);
          if (!_placed) {
            _x = _area.width / 2;
            _y = _area.height / 2;
            _placed = true;
          }
        }
        return RepaintBoundary(
          child: CustomPaint(
            size: _area,
            painter: _OnekoPainter(sheet: sheet, pose: _pose, x: _x, y: _y),
          ),
        );
      },
    );
  }
}

class _OnekoPainter extends CustomPainter {
  _OnekoPainter({
    required this.sheet,
    required this.pose,
    required this.x,
    required this.y,
  });

  final ui.Image sheet;
  final List<int> pose;
  final double x;
  final double y;

  static const double _s = 32;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(pose[0] * _s, pose[1] * _s, _s, _s);
    final dst = Rect.fromLTWH(x - _s / 2, y - _s / 2, _s, _s);
    canvas.drawImageRect(
      sheet,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.none // crisp pixels
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(_OnekoPainter old) =>
      old.x != x || old.y != y || !identical(old.pose, pose);
}
