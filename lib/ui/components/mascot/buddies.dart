import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'mascot_painter.dart' show HanaColors;

/// Code-drawn animal "buddies" that share the mascot's no-asset ethos
/// (CustomPainter geometry, no images/Rive). A buddy is just a painter
/// that takes a 0–1 animation phase; a host widget drives that phase
/// with a Ticker. See ARCHITECTURE-ANIMATIONS.md — the rabbit below is
/// the worked example; the flock added for 1.2.0 (parrot, cat, hamster,
/// duck, koi) shares one [RoamingBuddy] host and is gated per-buddy by
/// buddy_provider.dart.
///
/// Contract: paint the buddy inside [size], baseline at the bottom edge,
/// facing right. Keep it within ~[size] so hosts can place it freely.
abstract class BuddyPainter extends CustomPainter {
  const BuddyPainter(this.phase);

  /// 0..1 looped animation phase (e.g. a hop cycle).
  final double phase;

  @override
  bool shouldRepaint(covariant BuddyPainter old) => old.phase != phase;
}

/// A small hopping rabbit. [phase] runs a hop cycle: it crouches, springs
/// up (ears flop back, legs tuck), and lands. Drawn ~[size] tall, feet on
/// the bottom edge, facing right.
class RabbitPainter extends BuddyPainter {
  RabbitPainter(super.phase, {this.color = const Color(0xFFFDF0F4), this.arc = 1.0});

  final Color color;

  /// Multiplies hop height — bigger leaps arc higher.
  final double arc;

  @override
  void paint(Canvas canvas, Size size) {
    // Design space 32×32, scaled to fit; feet sit on the baseline.
    final s = size.width / 32.0;
    canvas.save();
    canvas.translate((size.width - 32 * s) / 2, size.height - 32 * s);
    canvas.scale(s);

    // Hop: a smooth up-down over the cycle. 0 grounded → peak at 0.5.
    final hop = math.sin(phase * math.pi); // 0..1..0
    final lift = hop * 9 * arc; // how high off the baseline
    final squash = 1 - hop * 0.12; // slight stretch at the top
    // Legs tuck (feet rise toward the belly) mid-hop.
    final tuck = hop;

    final fur = Paint()..color = color;
    final furLine = Paint()
      ..color = HanaColors.nose.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final pink = Paint()..color = HanaColors.blush;
    final dark = Paint()..color = HanaColors.eye;

    canvas.translate(0, -lift);
    canvas.save();
    canvas.translate(16, 26);
    canvas.scale(1, squash); // squash/stretch about the feet
    canvas.translate(-16, -26);

    // Back foot (tucks up during the hop).
    final footY = 27.0 - tuck * 5;
    canvas.drawOval(
        Rect.fromCenter(center: Offset(11, footY), width: 8, height: 4), fur);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(11, footY), width: 8, height: 4),
        furLine);

    // Body — a plump egg leaning forward.
    final body = Path()
      ..addOval(Rect.fromCenter(
          center: const Offset(15, 20), width: 18, height: 16));
    canvas.drawPath(body, fur);
    canvas.drawPath(body, furLine);

    // Tail puff.
    canvas.drawCircle(const Offset(6, 21), 3, fur);
    canvas.drawCircle(const Offset(6, 21), 3, furLine);

    // Head.
    canvas.drawCircle(const Offset(23, 15), 6.5, fur);
    canvas.drawCircle(const Offset(23, 15), 6.5, furLine);

    // Ears — flop backward as it springs up (driven by hop).
    for (final side in [0.0, 1.0]) {
      final baseX = 21.0 + side * 3;
      final sway = hop * 6; // lean back at the top of the hop
      final ear = Path()
        ..moveTo(baseX, 11)
        ..quadraticBezierTo(
            baseX - 2 - sway, 2, baseX + 1 - sway * 1.4, -3)
        ..quadraticBezierTo(baseX + 3 - sway, 3, baseX + 2, 11)
        ..close();
      canvas.drawPath(ear, fur);
      canvas.drawPath(ear, furLine);
      // Inner ear.
      final inner = Path()
        ..moveTo(baseX + 0.5, 9)
        ..quadraticBezierTo(baseX - sway, 3, baseX + 0.8 - sway, -1)
        ..quadraticBezierTo(baseX + 1.6 - sway, 4, baseX + 1.4, 9)
        ..close();
      canvas.drawPath(inner, pink);
    }

    // Face: eye + nose + cheek blush.
    canvas.drawCircle(const Offset(25, 14), 1.3, dark);
    canvas.drawCircle(const Offset(26.5, 16.5), 1.1, pink); // nose
    canvas.drawCircle(const Offset(21.5, 16.5), 1.6,
        Paint()..color = HanaColors.blush.withValues(alpha: 0.6));

    canvas.restore();
    canvas.restore();
  }
}

/// A little rabbit that lives on a download progress bar and behaves
/// like a real one: it hops around in leaps of random length, darts to
/// the start, bounds up to the fill edge ("the front"), stops to sniff,
/// and faces wherever it's going. A tiny behaviour state machine drives
/// a [RabbitPainter] on one Ticker. The worked example for
/// ARCHITECTURE-ANIMATIONS.md — a buddy = a painter + a phase driver.
class DownloadRabbit extends StatefulWidget {
  const DownloadRabbit({super.key, required this.progress, this.size = 22});

  /// 0..1 download fraction — where "the front" is right now.
  final double? progress;
  final double size;

  @override
  State<DownloadRabbit> createState() => _DownloadRabbitState();
}

class _DownloadRabbitState extends State<DownloadRabbit> {
  late final Ticker _ticker;
  final _rng = math.Random();
  Duration _last = Duration.zero;

  double _w = 0; // usable travel width (set from layout)
  double _x = 0; // current left-position of the rabbit
  double _goalX = 0; // where it's headed over a few hops

  bool _hopping = false;
  double _hopT = 0; // 0..1 within one leap
  double _hopDur = 0.34; // seconds for this leap
  double _fromX = 0, _toX = 0, _arc = 1;
  double _pause = 0.5; // seconds left before the next leap
  bool _faceLeft = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_tick)..start();
  }

  double get _maxX => math.max(0, _w - widget.size);
  double get _frontX =>
      ((widget.progress ?? 0.5).clamp(0.0, 1.0) * _w - widget.size / 2)
          .clamp(0.0, _maxX);

  void _tick(Duration elapsed) {
    // Ambient pets read the same at 30 fps, and every skipped frame is
    // a skipped buffer swap (NVIDIA's GL swap busy-waits on CPU — the
    // desktop idle-CPU report).
    if ((elapsed - _last).inMilliseconds < 32) return;
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    if (!_started) return;

    if (_hopping) {
      _hopT += dt / _hopDur;
      if (_hopT >= 1) {
        _hopT = 0;
        _hopping = false;
        _x = _toX;
        // Reached the goal? rest and sniff. Mid-journey? tiny beat.
        _pause = (_x - _goalX).abs() < 3
            ? 0.5 + _rng.nextDouble() * 1.6
            : 0.05 + _rng.nextDouble() * 0.1;
      } else {
        final e = Curves.easeInOut.transform(_hopT);
        _x = _fromX + (_toX - _fromX) * e;
      }
    } else {
      _pause -= dt;
      if (_pause <= 0) _startHop();
    }
    setState(() {});
  }

  void _startHop() {
    // Pick a fresh goal when we've arrived at the last one.
    if ((_x - _goalX).abs() < 3) {
      final r = _rng.nextDouble();
      _goalX = r < 0.28
          ? 0 // dash back to the start
          : r < 0.58
              ? _frontX // bound up to the fill edge
              : _rng.nextDouble() * _maxX; // somewhere random
    }
    // A single leap covers a bounded, slightly random distance toward it.
    final maxHop = _w * (0.16 + _rng.nextDouble() * 0.14);
    final dir = _goalX >= _x ? 1.0 : -1.0;
    final dist = math.min(maxHop, (_goalX - _x).abs());
    _fromX = _x;
    _toX = (_x + dir * dist).clamp(0.0, _maxX);
    _faceLeft = dir < 0;
    _hopping = true;
    _hopT = 0;
    // Longer, higher arcs for bigger leaps.
    final norm = _w == 0 ? 0.0 : dist / _w;
    _hopDur = 0.28 + norm * 0.5;
    _arc = 1.0 + norm * 2.2;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _w = c.maxWidth;
      if (!_started && _w > 0) {
        _x = _frontX;
        _goalX = _x;
        _started = true;
      }
      final rabbit = SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(painter: RabbitPainter(_hopT, arc: _arc)),
      );
      return SizedBox(
        height: widget.size + 4,
        width: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: _x.clamp(0.0, _maxX),
              bottom: 0,
              // Face the direction of travel by mirroring horizontally.
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..scale(_faceLeft ? -1.0 : 1.0, 1.0),
                child: rabbit,
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ─── The flock (1.2.0) ────────────────────────────────────────────────
// Every ground buddy below shares this host: it travels to a random
// spot, rests, and repeats. While moving the phase advances with
// DISTANCE (one gait cycle per [stride] px, so legs match ground
// speed); while resting it advances with TIME (one idle cycle per
// [idlePeriod] s — a head-bob, a nibble, a tail wiggle). [swayAmp]
// floats the buddy on a vertical sine the whole time (the koi's water).

class RoamingBuddy extends StatefulWidget {
  const RoamingBuddy({
    super.key,
    required this.size,
    required this.painterBuilder,
    this.speed = 40,
    this.stride = 14,
    this.idlePeriod = 2.2,
    this.pauseMin = 1.5,
    this.pauseMax = 4.5,
    this.swayAmp = 0,
    this.swayPeriod = 3.0,
  });

  final double size;
  final BuddyPainter Function(double phase, bool moving) painterBuilder;
  final double speed; // px/s while traveling
  final double stride; // px per gait cycle
  final double idlePeriod; // s per idle-animation cycle
  final double pauseMin, pauseMax; // rest between trips
  final double swayAmp, swayPeriod;

  @override
  State<RoamingBuddy> createState() => _RoamingBuddyState();
}

class _RoamingBuddyState extends State<RoamingBuddy> {
  late final Ticker _ticker;
  final _rng = math.Random();
  Duration _last = Duration.zero;

  double _w = 0;
  double _x = 0, _goal = 0;
  bool _moving = false, _faceLeft = false, _started = false;
  double _pause = 1.0;
  double _gait = 0; // accumulated gait cycles
  double _time = 0; // total seconds, drives idle anim + sway

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_tick)..start();
  }

  double get _maxX => math.max(0, _w - widget.size);

  void _tick(Duration elapsed) {
    // Ambient pets read the same at 30 fps, and every skipped frame is
    // a skipped buffer swap (NVIDIA's GL swap busy-waits on CPU — the
    // desktop idle-CPU report).
    if ((elapsed - _last).inMilliseconds < 32) return;
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    if (!_started) return;
    _time += dt;

    if (_moving) {
      final step = widget.speed * dt;
      final dir = _goal >= _x ? 1.0 : -1.0;
      _x += dir * step;
      _gait += step / widget.stride;
      if ((_goal - _x).abs() <= step) {
        _x = _goal;
        _moving = false;
        _pause = widget.pauseMin +
            _rng.nextDouble() * (widget.pauseMax - widget.pauseMin);
      }
    } else {
      _pause -= dt;
      if (_pause <= 0 && _maxX > 8) {
        // Head somewhere meaningfully far so trips read as trips.
        var goal = _rng.nextDouble() * _maxX;
        if ((goal - _x).abs() < _maxX * 0.2) {
          goal = _x > _maxX / 2 ? _x - _maxX * 0.4 : _x + _maxX * 0.4;
        }
        _goal = goal.clamp(0.0, _maxX);
        _faceLeft = _goal < _x;
        _moving = true;
      }
    }
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _w = c.maxWidth;
      if (!_started && _w > 0) {
        _x = _rng.nextDouble() * _maxX;
        _goal = _x;
        _pause = 0.3 + _rng.nextDouble() * 1.5;
        _started = true;
      }
      final phase = _moving
          ? _gait % 1.0
          : (_time / widget.idlePeriod) % 1.0;
      final sway = widget.swayAmp *
          math.sin(_time * 2 * math.pi / widget.swayPeriod);
      return SizedBox(
        height: widget.size + widget.swayAmp * 2,
        width: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: _x.clamp(0.0, _maxX),
              bottom: widget.swayAmp + sway,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..scale(_faceLeft ? -1.0 : 1.0, 1.0),
                child: SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: CustomPaint(
                      painter: widget.painterBuilder(phase, _moving)),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Shared outline style — same soft brown line the rabbit uses.
Paint _buddyLine() => Paint()
  ..color = HanaColors.nose.withValues(alpha: 0.55)
  ..style = PaintingStyle.stroke
  ..strokeWidth = 1.1;

/// A pastel parrot that perches on the Library title. Idle it bobs its
/// head (more of a groove than a bob, honestly); traveling it does
/// quick two-footed sidestep hops, one per gait cycle.
class ParrotPainter extends BuddyPainter {
  ParrotPainter(super.phase, {this.moving = false});

  final bool moving;

  static const _body = Color(0xFF9ED9A4);
  static const _wing = Color(0xFF63BE8C);
  static const _belly = Color(0xFFE8F6E6);
  static const _beak = Color(0xFFF2A65A);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 32.0;
    canvas.save();
    canvas.translate((size.width - 32 * s) / 2, size.height - 32 * s);
    canvas.scale(s);

    final lift = moving ? math.sin(phase * math.pi) * 4.5 : 0.0;
    final bob = moving ? 0.0 : math.sin(phase * 2 * math.pi) * 0.5 + 0.5;
    final flap = moving ? math.sin(phase * math.pi) * 0.5 : 0.0;

    final line = _buddyLine();
    final body = Paint()..color = _body;
    final wing = Paint()..color = _wing;

    canvas.translate(0, -lift);

    // Feet — two little claws on the ground line.
    final feet = Paint()..color = const Color(0xFFE0A34E);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(13.5, 29.6), width: 3.2, height: 1.7),
        feet);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(17.5, 29.6), width: 3.2, height: 1.7),
        feet);

    // Tail — two long feathers trailing down-left.
    final feather = Paint()
      ..color = _wing
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
        Path()
          ..moveTo(11, 22)
          ..quadraticBezierTo(6, 26, 3.5, 28.5),
        feather);
    canvas.drawPath(
        Path()
          ..moveTo(11.5, 23.2)
          ..quadraticBezierTo(7.5, 27.5, 5.5, 30),
        feather);

    // Body — an egg leaning slightly forward.
    canvas.save();
    canvas.translate(15.5, 21.5);
    canvas.rotate(-0.14);
    final bodyRect =
        Rect.fromCenter(center: Offset.zero, width: 13, height: 15);
    canvas.drawOval(bodyRect, body);
    canvas.drawOval(bodyRect, line);
    canvas.restore();

    // Belly patch.
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(17, 23.5), width: 7.5, height: 9),
        Paint()..color = _belly);

    // Wing — folded oval that lifts mid-hop.
    canvas.save();
    canvas.translate(12.5, 21);
    canvas.rotate(-0.25 - flap);
    final wingRect =
        Rect.fromCenter(center: Offset.zero, width: 6.5, height: 10);
    canvas.drawOval(wingRect, wing);
    canvas.drawOval(wingRect, line);
    canvas.restore();

    // Head group dips with the bob.
    canvas.save();
    canvas.translate(0, bob * 1.6);
    canvas.drawCircle(const Offset(20, 11.5), 6, body);
    canvas.drawCircle(const Offset(20, 11.5), 6, line);
    // Crest curl.
    final crest = Paint()
      ..color = _wing
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
        Path()
          ..moveTo(18.5, 6.2)
          ..quadraticBezierTo(17.2, 3.6, 15.8, 3.0),
        crest);
    canvas.drawPath(
        Path()
          ..moveTo(19.8, 5.8)
          ..quadraticBezierTo(19.4, 3.2, 18.4, 2.0),
        crest);
    // Eye patch + pupil.
    canvas.drawCircle(const Offset(22.3, 10.5), 2.6, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(22.6, 10.6), 1.3, Paint()..color = HanaColors.eye);
    // Hooked beak.
    final beak = Path()
      ..moveTo(25.3, 8.8)
      ..quadraticBezierTo(29.3, 10, 26.6, 13.6)
      ..quadraticBezierTo(25.6, 11.5, 25.3, 8.8)
      ..close();
    canvas.drawPath(beak, Paint()..color = _beak);
    canvas.drawPath(beak, line);
    // Blush.
    canvas.drawCircle(const Offset(24.6, 13.6), 1.3,
        Paint()..color = HanaColors.blush.withValues(alpha: 0.6));
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ParrotPainter old) =>
      old.phase != phase || old.moving != moving;
}

/// A loaf-cat. Asleep she breathes slowly, tail wrapped in front,
/// floating Zz; when the music plays she wakes and her tail sways to
/// the phase. Stationary — she has claimed the mini player and is not
/// going anywhere.
class CatPainter extends BuddyPainter {
  CatPainter(super.phase, {this.sleeping = true});

  final bool sleeping;

  static const _fur = Color(0xFFC7BAD4);
  static const _shade = Color(0xFFB0A1C4);
  static const _cream = Color(0xFFF7F1E9);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 32.0;
    canvas.save();
    canvas.translate((size.width - 32 * s) / 2, size.height - 32 * s);
    canvas.scale(s);

    final wave = math.sin(phase * 2 * math.pi);
    final line = _buddyLine();
    final fur = Paint()..color = _fur;

    // Tail first so it sits behind the loaf.
    final tail = Paint()
      ..color = _shade
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    if (sleeping) {
      canvas.drawPath(
          Path()
            ..moveTo(5.5, 27)
            ..quadraticBezierTo(9, 30.6, 16, 29.6),
          tail);
    } else {
      final sway = wave * 2.4;
      canvas.drawPath(
          Path()
            ..moveTo(6, 25)
            ..quadraticBezierTo(1.5, 17, 4 + sway, 9.5),
          tail);
    }

    // Loaf body, breathing gently while asleep.
    canvas.save();
    if (sleeping) {
      canvas.translate(14.5, 30);
      canvas.scale(1, 1 + wave * 0.025);
      canvas.translate(-14.5, -30);
    }
    final loaf = RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(14.5, 24), width: 21, height: 12),
        const Radius.circular(6.5));
    canvas.drawRRect(loaf, fur);
    canvas.drawRRect(loaf, line);
    // Two little back stripes.
    final stripe = Paint()
      ..color = _shade
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
        Path()
          ..moveTo(7, 19.4)
          ..quadraticBezierTo(6.2, 21.5, 7, 23.6),
        stripe);
    canvas.drawPath(
        Path()
          ..moveTo(10.8, 18.6)
          ..quadraticBezierTo(10, 20.8, 10.8, 23),
        stripe);
    canvas.restore();

    // Front paws peeking out under the chin.
    final cream = Paint()..color = _cream;
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(19.5, 29.4), width: 4, height: 2.6),
        cream);
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(24, 29.4), width: 4, height: 2.6),
        cream);

    // Ears (behind the head circle's top edge).
    for (final (base, apex, lean) in [
      (const Offset(19.4, 13.6), const Offset(17.6, 8.4), 0.0),
      (const Offset(25.4, 13.2), const Offset(27.2, 8.2), 0.0),
    ]) {
      final ear = Path()
        ..moveTo(base.dx - 2 + lean, base.dy)
        ..lineTo(apex.dx, apex.dy)
        ..lineTo(base.dx + 2.4, base.dy + 0.6)
        ..close();
      canvas.drawPath(ear, fur);
      canvas.drawPath(ear, line);
      final inner = Path()
        ..moveTo(base.dx - 0.6 + lean, base.dy - 0.2)
        ..lineTo(apex.dx, apex.dy + 1.6)
        ..lineTo(base.dx + 1.2, base.dy + 0.2)
        ..close();
      canvas.drawPath(inner, Paint()..color = HanaColors.blush);
    }

    // Head resting on the right end of the loaf.
    canvas.drawCircle(const Offset(22.5, 17.5), 6.2, fur);
    canvas.drawCircle(const Offset(22.5, 17.5), 6.2, line);

    // Face.
    final eye = Paint()
      ..color = HanaColors.eye
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    if (sleeping) {
      // Two content closed-eye arcs.
      canvas.drawPath(
          Path()
            ..moveTo(19.2, 17)
            ..quadraticBezierTo(20.3, 18.2, 21.4, 17),
          eye);
      canvas.drawPath(
          Path()
            ..moveTo(23.8, 17)
            ..quadraticBezierTo(24.9, 18.2, 26, 17),
          eye);
    } else {
      canvas.drawCircle(const Offset(20.3, 17), 1.4, Paint()..color = HanaColors.eye);
      canvas.drawCircle(const Offset(24.9, 17), 1.4, Paint()..color = HanaColors.eye);
      canvas.drawCircle(const Offset(20.7, 16.6), 0.45, Paint()..color = Colors.white);
      canvas.drawCircle(const Offset(25.3, 16.6), 0.45, Paint()..color = Colors.white);
    }
    // Nose + mouth.
    canvas.drawPath(
        Path()
          ..moveTo(21.8, 19.2)
          ..lineTo(23.2, 19.2)
          ..lineTo(22.5, 20.2)
          ..close(),
        Paint()..color = HanaColors.blush);
    canvas.drawPath(
        Path()
          ..moveTo(22.5, 20.2)
          ..quadraticBezierTo(22.5, 21.2, 21.5, 21.4),
        eye..strokeWidth = 0.9);
    // Whiskers.
    final whisker = Paint()
      ..color = HanaColors.nose.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawLine(const Offset(27.6, 18.4), const Offset(30.6, 17.8), whisker);
    canvas.drawLine(const Offset(27.6, 19.6), const Offset(30.4, 20), whisker);
    // Blush.
    canvas.drawCircle(const Offset(26, 19.8), 1.3,
        Paint()..color = HanaColors.blush.withValues(alpha: 0.55));

    // Zz drifting up while asleep.
    if (sleeping) {
      final t = phase; // one z-cycle per breath
      final alpha = (math.sin(t * 2 * math.pi - math.pi / 2) * 0.5 + 0.5);
      final zPaint = Paint()
        ..color = _shade.withValues(alpha: alpha * 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round;
      void z(Offset c, double zs) {
        canvas.drawPath(
            Path()
              ..moveTo(c.dx - zs, c.dy - zs)
              ..lineTo(c.dx + zs, c.dy - zs)
              ..lineTo(c.dx - zs, c.dy + zs)
              ..lineTo(c.dx + zs, c.dy + zs),
            zPaint);
      }

      final rise = t * 2.2;
      z(Offset(28.2, 8.5 - rise), 1.5);
      z(Offset(30.6, 4.5 - rise), 1.0);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CatPainter old) =>
      old.phase != phase || old.sleeping != sleeping;
}

/// Ticker host for the stationary cat: slow breathing cycle asleep,
/// quicker tail-sway cycle while the music plays. Phase accumulates
/// continuously so waking up doesn't jump-cut.
class CatBuddy extends StatefulWidget {
  const CatBuddy({super.key, required this.sleeping, this.size = 26});

  final bool sleeping;
  final double size;

  @override
  State<CatBuddy> createState() => _CatBuddyState();
}

class _CatBuddyState extends State<CatBuddy> {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _phase = 0;

  @override
  void initState() {
    super.initState();
    _ticker = Ticker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    // Ambient pets read the same at 30 fps, and every skipped frame is
    // a skipped buffer swap (NVIDIA's GL swap busy-waits on CPU — the
    // desktop idle-CPU report).
    if ((elapsed - _last).inMilliseconds < 32) return;
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    _phase += dt / (widget.sleeping ? 3.4 : 1.5);
    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: CustomPaint(
          painter: CatPainter(_phase % 1.0, sleeping: widget.sleeping)),
    );
  }
}

class DuckPainter extends BuddyPainter {
  DuckPainter(super.phase, {this.moving = false});

  final bool moving;

  static const _body = Color(0xFFF8E49B);
  static const _wing = Color(0xFFEECB6A);
  static const _cream = Color(0xFFFDF7E4);
  static const _bill = Color(0xFFF0A050);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 32.0;
    canvas.save();
    canvas.translate((size.width - 32 * s) / 2, size.height - 32 * s);
    canvas.scale(s);

    final wave = math.sin(phase * 2 * math.pi);
    final line = _buddyLine();
    final body = Paint()..color = _body;

    // Feet + stubby legs (under the rocking body).
    final feetPaint = Paint()..color = _bill;
    final leg = Paint()
      ..color = _bill
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final lLift = moving ? math.max(0.0, wave) * 2.2 : 0.0;
    final rLift = moving ? math.max(0.0, -wave) * 2.2 : 0.0;
    canvas.drawLine(Offset(12.4, 27.5), Offset(12.4, 29.6 - lLift), leg);
    canvas.drawLine(Offset(17.8, 27.5), Offset(17.8, 29.6 - rLift), leg);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(13.4, 30 - lLift), width: 5, height: 2.2),
        feetPaint);
    canvas.drawOval(
        Rect.fromCenter(center: Offset(18.8, 30 - rLift), width: 5, height: 2.2),
        feetPaint);

    // Rock the whole bird about its feet while waddling; gentle
    // breathe-rock at rest.
    canvas.translate(15, 30);
    canvas.rotate(moving ? wave * 0.09 : wave * 0.02);
    canvas.translate(-15, -30);

    // Tail — perky triangle, wiggles when idle.
    canvas.save();
    if (!moving) {
      canvas.translate(8, 21);
      canvas.rotate(math.sin(phase * 4 * math.pi) * 0.12);
      canvas.translate(-8, -21);
    }
    final tail = Path()
      ..moveTo(6.5, 22)
      ..quadraticBezierTo(3.8, 19.5, 4.6, 17.2)
      ..quadraticBezierTo(7, 19, 8.6, 20.6)
      ..close();
    canvas.drawPath(tail, body);
    canvas.drawPath(tail, line);
    canvas.restore();

    // Body.
    final bodyRect =
        Rect.fromCenter(center: const Offset(14.5, 23.2), width: 17.5, height: 11.5);
    canvas.drawOval(bodyRect, body);
    canvas.drawOval(bodyRect, line);

    // Belly.
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(16, 26), width: 9.5, height: 6),
        Paint()..color = _cream);

    // Wing.
    canvas.save();
    canvas.translate(12.8, 22.8);
    canvas.rotate(-0.15);
    final wingRect =
        Rect.fromCenter(center: Offset.zero, width: 8.5, height: 6.4);
    canvas.drawOval(wingRect, Paint()..color = _wing);
    canvas.drawOval(wingRect, line);
    canvas.restore();

    // Neck + head.
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(20.5, 17.5), width: 7, height: 9),
        body);
    canvas.drawCircle(const Offset(23, 12.6), 5.6, body);
    canvas.drawCircle(const Offset(23, 12.6), 5.6, line);

    // Bill — two flattened ellipses.
    canvas.save();
    canvas.translate(28.4, 13.2);
    canvas.rotate(0.06);
    final upper = Rect.fromCenter(center: Offset.zero, width: 6, height: 2.8);
    canvas.drawOval(upper, Paint()..color = _bill);
    canvas.drawOval(upper, line);
    canvas.restore();
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(27.9, 14.9), width: 4.2, height: 1.9),
        Paint()..color = _bill);

    // Eye + blush.
    canvas.drawCircle(const Offset(24.6, 10.9), 1.35, Paint()..color = HanaColors.eye);
    canvas.drawCircle(const Offset(25, 10.5), 0.45, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(25.6, 14), 1.4,
        Paint()..color = HanaColors.blush.withValues(alpha: 0.55));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DuckPainter old) =>
      old.phase != phase || old.moving != moving;
}

class HeaderParrot extends StatelessWidget {
  const HeaderParrot({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) {
    return RoamingBuddy(
      size: size,
      speed: 55,
      stride: 12,
      idlePeriod: 1.9,
      pauseMin: 2.5,
      pauseMax: 7,
      painterBuilder: (p, m) => ParrotPainter(p, moving: m),
    );
  }
}

class PlaylistsDuck extends StatelessWidget {
  const PlaylistsDuck({super.key, this.size = 23});

  final double size;

  @override
  Widget build(BuildContext context) {
    return RoamingBuddy(
      size: size,
      speed: 24,
      stride: 15,
      idlePeriod: 2.4,
      pauseMin: 1.8,
      pauseMax: 5,
      painterBuilder: (p, m) => DuckPainter(p, moving: m),
    );
  }
}

class FireflyPreviewPainter extends BuddyPainter {
  FireflyPreviewPainter(super.phase);

  @override
  void paint(Canvas canvas, Size size) {
    const glow = Color(0xFFCFDA7E);
    const core = Color(0xFFEFE9A8);
    for (final (c, r, a) in [
      (Offset(size.width * 0.3, size.height * 0.35), 2.2, 1.0),
      (Offset(size.width * 0.68, size.height * 0.6), 1.7, 0.7),
      (Offset(size.width * 0.5, size.height * 0.82), 1.3, 0.45),
    ]) {
      canvas.drawCircle(
          c,
          r * 3,
          Paint()
            ..color = glow.withValues(alpha: 0.22 * a)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
      canvas.drawCircle(
          c, r, Paint()..color = core.withValues(alpha: 0.9 * a));
    }
  }
}
