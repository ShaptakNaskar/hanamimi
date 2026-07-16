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
/// Blackout Mode's corner cat (3.0 #3): asleep by default, and *she* is
/// the track-change cue — bump [stir] and she startles awake, scratches,
/// and settles back down. No toast, no text, just the cat.
class StirringOneko extends StatefulWidget {
  const StirringOneko({super.key, this.size = 36, required this.stir});

  final double size;

  /// Increment to wake her briefly (typically on track change).
  final int stir;

  @override
  State<StirringOneko> createState() => _StirringOnekoState();
}

class _StirringOnekoState extends State<StirringOneko> {
  Timer? _timer;
  var _frame = 0;
  var _awakeTicks = 0; // >0 while stirred; counts down per tick

  @override
  void initState() {
    super.initState();
    if (_OnekoPetState._sheet == null) {
      _OnekoPetState._loadSheet().then((_) {
        if (mounted) setState(() {});
      });
    }
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted || !windowVisible.value) return;
      setState(() {
        _frame++;
        if (_awakeTicks > 0) _awakeTicks--;
      });
    });
  }

  @override
  void didUpdateWidget(StirringOneko old) {
    super.didUpdateWidget(old);
    if (widget.stir != old.stir) {
      setState(() {
        _awakeTicks = 10; // ~4 s: alert, a scratch, back to sleep
        _frame = 0;
      });
    }
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
    final pose = _awakeTicks > 7
        ? _sprites['alert']![0]
        : _awakeTicks > 0
            ? _sprites['scratchSelf']![_frame % 3]
            : _sprites['sleeping']![(_frame ~/ 2) % 2];
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _SleepingOnekoPainter(
          sheet: sheet,
          pose: pose,
          size: widget.size,
        ),
      ),
    );
  }
}

/// Blackout's corner cat — the REAL oneko chase brain pointed at a
/// hardcoded "cursor" (3.0 feedback: the hand-scripted entrance looked
/// robotic next to the pointer chase, so instead we tell her where to
/// WANT to be and let the authentic oneko.js logic do the walking,
/// perking, fidgeting and napping). Dark skin: the target is her seat
/// in the corner — she pads in, settles, and naps there. Light skin:
/// the target parks past the left edge and she runs off after it. A
/// track change ([stir]) slides it a hop away and back so she wakes,
/// pads over, and returns to her seat — no synthetic poses anywhere.
class BlackoutOneko extends StatefulWidget {
  const BlackoutOneko({
    super.key,
    required this.present,
    required this.stir,
    required this.seat,
  });

  /// Whether the cat belongs on screen (the dark skin is showing).
  final bool present;

  /// Increment to stir her awake briefly (track change).
  final int stir;

  /// Her seat, given the layer's size — where the "cursor" rests while
  /// the room is dark.
  final Offset Function(Size area) seat;

  @override
  State<BlackoutOneko> createState() => _BlackoutOnekoState();
}

class _BlackoutOnekoState extends State<BlackoutOneko> {
  final _target = ValueNotifier<Offset?>(null);
  Timer? _stirNudge;
  var _area = Size.zero;

  void _retarget() {
    if (_area == Size.zero) return;
    final seat = widget.seat(_area);
    // "Away" sits far enough past the edge that she has fully left the
    // screen before the chase brain calls it arrived.
    _target.value = widget.present ? seat : Offset(-120, seat.dy);
  }

  @override
  void didUpdateWidget(BlackoutOneko old) {
    super.didUpdateWidget(old);
    if (widget.present != old.present) {
      _stirNudge?.cancel();
      _retarget();
    } else if (widget.stir != old.stir &&
        widget.present &&
        _area != Size.zero) {
      // Track change: drag the target a hop away, then home again.
      _target.value = widget.seat(_area).translate(-96, 0);
      _stirNudge?.cancel();
      _stirNudge = Timer(const Duration(seconds: 2), () {
        if (mounted && widget.present) _target.value = widget.seat(_area);
      });
    }
  }

  @override
  void dispose() {
    _stirNudge?.cancel();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final area = Size(c.maxWidth, c.maxHeight);
      if (area != _area) {
        _area = area;
        _retarget(); // first layout and any resize/rotation
      }
      return _OnekoPet(
        cursor: _target,
        // She should actually reach the seat, not hover 48 px off it.
        arriveWithin: 12,
        // First appearance is offscreen left at seat height, so opening
        // straight into the dark begins with the walk-in.
        spawn: (s) => Offset(-48, widget.seat(s).dy),
      );
    });
  }
}

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

/// A single still oneko sprite — for previews and chips where the live
/// pointer-chasing cat would be overkill (e.g. the buddy picker row).
/// Reuses the one shared sprite sheet; paints nothing until it loads.
class OnekoStill extends StatefulWidget {
  const OnekoStill({super.key, this.size = 30, this.pose = 'idle'});

  final double size;

  /// Key into the sprite table — 'idle' (sitting, facing you) by default.
  final String pose;

  @override
  State<OnekoStill> createState() => _OnekoStillState();
}

class _OnekoStillState extends State<OnekoStill> {
  @override
  void initState() {
    super.initState();
    if (_OnekoPetState._sheet == null) {
      _OnekoPetState._loadSheet().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _OnekoPetState._sheet;
    if (sheet == null) {
      return SizedBox(width: widget.size, height: widget.size);
    }
    final pose = (_sprites[widget.pose] ?? _sprites['idle']!).first;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _SleepingOnekoPainter(
          sheet: sheet,
          pose: pose,
          size: widget.size,
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
  const _OnekoPet({required this.cursor, this.spawn, this.arriveWithin = 48});

  final ValueListenable<Offset?> cursor;

  /// Where the cat first appears; defaults to the center of the area.
  final Offset Function(Size area)? spawn;

  /// How close counts as "arrived". The pointer chase keeps a polite
  /// 48 px distance from the cursor; a hardcoded seat ([BlackoutOneko])
  /// wants her ON the spot.
  final double arriveWithin;

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

    if (distance < _speed || distance < widget.arriveWithin) {
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
        // Targets may sit past an edge (BlackoutOneko parks hers
        // offscreen to send the cat away) — widen the walkable box to
        // include the target so the clamp never strands her at the
        // border.
        _x = _x.clamp(
            math.min(16.0, tx), math.max(math.max(16.0, _area.width - 16), tx));
        _y = _y.clamp(math.min(16.0, ty),
            math.max(math.max(16.0, _area.height - 16), ty));
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
    // Fidget dice. oneko.js rolls 1/200 a tick, but combined with the
    // guaranteed 8 s nap below that meant the scratch poses effectively
    // never showed — she was only ever seen waiting, yawning, sleeping
    // (user report). 1/45 over the ~7 s pre-nap window makes "do a cat
    // thing, then curl up" the normal sequence, wall scratches included
    // whenever she settled near an edge. Edge margin widened to 48 px
    // (the strict 32 px required pixel-perfect cornering to ever see).
    if (_idleTime > 10 && _rng.nextInt(45) == 0 && _idleAnimation == null) {
      final avail = <String>['scratchSelf', 'scratchSelf', 'sleeping'];
      if (_x < 48) avail.add('scratchWallW');
      if (_y < 48) avail.add('scratchWallN');
      if (_x > _area.width - 48) avail.add('scratchWallE');
      if (_y > _area.height - 48) avail.add('scratchWallS');
      _idleAnimation = avail[_rng.nextInt(avail.length)];
    }
    // ~8 s of stillness still guarantees a nap — but a long sleeper now
    // stirs once in a while (a sleepy scratch between sleep cycles)
    // instead of freezing on the sleep loop forever.
    if (_idleAnimation == null && _idleTime > 80) {
      _idleAnimation =
          _idleTime > 200 && _rng.nextInt(4) == 0 ? 'scratchSelf' : 'sleeping';
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
            final spawn = widget.spawn?.call(_area) ??
                Offset(_area.width / 2, _area.height / 2);
            _x = spawn.dx;
            _y = spawn.dy;
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
