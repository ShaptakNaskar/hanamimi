import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'mascot_painter.dart' show HanaColors;

/// Code-drawn animal "buddies" that share the mascot's no-asset ethos
/// (CustomPainter geometry, no images/Rive). A buddy is just a painter
/// that takes a 0–1 animation phase; a host widget drives that phase
/// with a Ticker. See ARCHITECTURE-ANIMATIONS.md for how to add a dog,
/// cat, etc. — the rabbit below is the worked example.
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
