import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Hanamimi's palette, ported from the design prototype (Mascot.jsx).
abstract final class HanaColors {
  static const earDark = Color(0xFF5B3A29);
  static const cap = Color(0xFF6B4530);
  static const tan = Color(0xFFE0AD6E);
  static const muzzle = Color(0xFFFBF6F0);
  static const muzzleShade = Color(0xFFEFE3D6);
  static const eye = Color(0xFF2C2A33);
  static const nose = Color(0xFF3B2B28);
  static const blush = Color(0xFFF4A7B9);
  static const tongue = Color(0xFFF08CA0);
}

enum Accessory { none, bow, headphones, flower, crown, catEars }

enum EyeKind { open, wide, smile, half, closed }

enum BrowKind { none, happy, up, flat }

enum MouthKind { neutral, small, open, tongue }

/// Static geometry of one mascot pose. The animation layer supplies
/// [tilt] (head, degrees), [bob] (radians) and [earSwing] (radians)
/// each frame.
class MascotPose {
  const MascotPose({
    required this.eyes,
    required this.brow,
    required this.mouth,
    this.tilt = 0,
  });

  final EyeKind eyes;
  final BrowKind brow;
  final MouthKind mouth;
  final double tilt;
}

/// Draws the beagle in the prototype's 120×132 (158 full-body) space,
/// scaled to fit. Pure geometry — no state of its own.
class MascotPainter extends CustomPainter {
  MascotPainter({
    required this.pose,
    this.blink = 0, // 0 = open, 1 = fully closed (overrides eye kind)
    this.bob = 0, // head rotation, radians
    this.earSwing = 0, // extra ear rotation (lags behind bob), radians
    this.bodyBounce = 0, // vertical offset in local units
    this.fullBody = false,
    this.sleepPhase, // 0..1 → floating zzz when non-null
    this.accessory = Accessory.none,
  });

  final MascotPose pose;
  final double blink;
  final double bob;
  final double earSwing;
  final double bodyBounce;
  final bool fullBody;
  final double? sleepPhase;
  final Accessory accessory;

  static const _w = 120.0;

  @override
  void paint(Canvas canvas, Size size) {
    final h = fullBody ? 158.0 : 132.0;
    final scale = (size.width / _w).clamp(0.0, size.height / h);
    canvas.save();
    canvas.translate((size.width - _w * scale) / 2,
        (size.height - h * scale) / 2);
    canvas.scale(scale);
    canvas.translate(0, bodyBounce);

    if (sleepPhase != null) _drawZzz(canvas, sleepPhase!);

    if (fullBody) _drawBody(canvas);

    // Head group rotates around the chin (60, 102).
    canvas.save();
    canvas.translate(60, 102);
    canvas.rotate(bob + pose.tilt * (3.14159 / 180));
    canvas.translate(-60, -102);

    _drawEars(canvas);
    _drawHead(canvas);
    _drawFace(canvas);
    _drawAccessory(canvas);

    canvas.restore();
    canvas.restore();
  }

  void _drawAccessory(Canvas canvas) {
    switch (accessory) {
      case Accessory.none:
        return;
      case Accessory.bow:
        final pink = Paint()..color = HanaColors.blush;
        final deep = Paint()..color = const Color(0xFFE8829B);
        // Two loops + knot, perched top-right of the head.
        final left = Path()
          ..moveTo(78, 30)
          ..quadraticBezierTo(66, 20, 68, 32)
          ..quadraticBezierTo(70, 39, 78, 30)
          ..close();
        final right = Path()
          ..moveTo(78, 30)
          ..quadraticBezierTo(90, 18, 90, 30)
          ..quadraticBezierTo(89, 38, 78, 30)
          ..close();
        canvas.drawPath(left, pink);
        canvas.drawPath(right, pink);
        canvas.drawCircle(const Offset(78, 30), 4, deep);
      case Accessory.headphones:
        final band = Paint()
          ..color = const Color(0xFF8A6FD1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(
            Rect.fromCircle(center: const Offset(60, 52), radius: 42),
            3.34, 2.75, false, band);
        final cup = Paint()..color = const Color(0xFF8A6FD1);
        canvas.drawOval(
            Rect.fromCenter(
                center: const Offset(21, 62), width: 13, height: 20),
            cup);
        canvas.drawOval(
            Rect.fromCenter(
                center: const Offset(99, 62), width: 13, height: 20),
            cup);
      case Accessory.flower:
        final petal = Paint()..color = const Color(0xFFFFC9DE);
        for (var i = 0; i < 5; i++) {
          final a = i * 2 * math.pi / 5;
          canvas.drawCircle(
              Offset(92 + 6 * math.cos(a), 34 + 6 * math.sin(a)), 5, petal);
        }
        canvas.drawCircle(
            const Offset(92, 34), 4, Paint()..color = const Color(0xFFFFD580));
      case Accessory.crown:
        final gold = Paint()..color = const Color(0xFFFFD580);
        final crown = Path()
          ..moveTo(46, 26)
          ..lineTo(48, 14)
          ..lineTo(55, 22)
          ..lineTo(60, 10)
          ..lineTo(65, 22)
          ..lineTo(72, 14)
          ..lineTo(74, 26)
          ..close();
        canvas.drawPath(crown, gold);
      case Accessory.catEars:
        final fur = Paint()..color = HanaColors.cap;
        final inner = Paint()..color = HanaColors.blush;
        final leftEar = Path()
          ..moveTo(34, 30)
          ..lineTo(38, 12)
          ..lineTo(50, 24)
          ..close();
        final rightEar = Path()
          ..moveTo(86, 30)
          ..lineTo(82, 12)
          ..lineTo(70, 24)
          ..close();
        canvas.drawPath(leftEar, fur);
        canvas.drawPath(rightEar, fur);
        final leftIn = Path()
          ..moveTo(38, 27)
          ..lineTo(40, 17)
          ..lineTo(47, 24)
          ..close();
        final rightIn = Path()
          ..moveTo(82, 27)
          ..lineTo(80, 17)
          ..lineTo(73, 24)
          ..close();
        canvas.drawPath(leftIn, inner);
        canvas.drawPath(rightIn, inner);
    }
  }


  void _drawBody(Canvas canvas) {
    final tan = Paint()..color = HanaColors.tan;
    final muzzle = Paint()..color = HanaColors.muzzle;
    // The cream belly/paws sit directly on the app background, which on
    // the light themes is nearly the same color — a soft brown edge
    // keeps the silhouette readable there (barely shows on dark).
    final edge = Paint()
      ..color = HanaColors.earDark.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    // Tail.
    final tail = Path()
      ..moveTo(86, 122)
      ..quadraticBezierTo(104, 118, 104, 104)
      ..quadraticBezierTo(110, 116, 100, 126)
      ..quadraticBezierTo(92, 132, 86, 122)
      ..close();
    canvas.drawPath(tail, tan);

    canvas.drawOval(
        Rect.fromCenter(center: const Offset(60, 124), width: 62, height: 48),
        tan);
    final belly =
        Rect.fromCenter(center: const Offset(60, 134), width: 40, height: 32);
    canvas.drawOval(belly, muzzle);
    canvas.drawOval(belly, edge);
    // Paws.
    final leftPaw =
        Rect.fromCenter(center: const Offset(44, 150), width: 18, height: 14);
    final rightPaw =
        Rect.fromCenter(center: const Offset(76, 150), width: 18, height: 14);
    canvas.drawOval(leftPaw, muzzle);
    canvas.drawOval(rightPaw, muzzle);
    canvas.drawOval(leftPaw, edge);
    canvas.drawOval(rightPaw, edge);
  }

  void _drawEars(Canvas canvas) {
    final paint = Paint()..color = HanaColors.earDark;

    void ear(Offset center, double baseAngle, Offset pivot) {
      canvas.save();
      canvas.translate(pivot.dx, pivot.dy);
      canvas.rotate(baseAngle + earSwing);
      canvas.translate(-pivot.dx, -pivot.dy);
      canvas.drawOval(
          Rect.fromCenter(center: center, width: 30, height: 70), paint);
      canvas.restore();
    }

    ear(const Offset(24, 74), 9 * 3.14159 / 180, const Offset(24, 44));
    ear(const Offset(96, 70), -9 * 3.14159 / 180, const Offset(96, 42));
  }

  void _drawHead(Canvas canvas) {
    canvas.drawCircle(
        const Offset(60, 62), 40, Paint()..color = HanaColors.tan);

    // Brown cap on top of the head.
    final cap = Path()
      ..moveTo(22, 56)
      ..quadraticBezierTo(24, 22, 60, 22)
      ..quadraticBezierTo(96, 22, 98, 56)
      ..quadraticBezierTo(80, 40, 60, 40)
      ..quadraticBezierTo(40, 40, 22, 56)
      ..close();
    canvas.drawPath(cap, Paint()..color = HanaColors.cap);

    // The face plate (muzzle, blush, eyes, nose, mouth) is lifted
    // toward the cap: without eyebrows the forehead read too tall, so
    // the whole face is nudged up to rebalance. Kept in sync with the
    // matching lift in _drawFace.
    const faceLift = 5.0;

    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(60, 76 - faceLift), width: 50, height: 42),
        Paint()..color = HanaColors.muzzle);
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(60, 80 - faceLift), width: 50, height: 34),
        Paint()
          ..color = HanaColors.muzzleShade.withValues(alpha: 0.45));

    // Blush.
    final blush = Paint()..color = HanaColors.blush.withValues(alpha: 0.5);
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(36, 72 - faceLift), width: 14, height: 9),
        blush);
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(84, 72 - faceLift), width: 14, height: 9),
        blush);
  }

  void _drawFace(Canvas canvas) {
    // Kept in sync with _drawHead's faceLift (see note there).
    const faceLift = 5.0;
    canvas.save();
    canvas.translate(0, -faceLift);

    _drawEye(canvas, 44);
    _drawEye(canvas, 76);
    // Eyebrows removed by design — the browless face reads softer and
    // rounder. Poses still carry a BrowKind for possible future use.

    // Nose with specular dot.
    canvas.drawOval(
        Rect.fromCenter(center: const Offset(60, 68), width: 15, height: 11),
        Paint()..color = HanaColors.nose);
    canvas.drawCircle(const Offset(57.5, 65.8), 1.6,
        Paint()..color = Colors.white.withValues(alpha: 0.7));

    _drawMouth(canvas);
    canvas.restore();
  }

  void _drawEye(Canvas canvas, double x) {
    final paint = Paint()..color = HanaColors.eye;
    final stroke = Paint()
      ..color = HanaColors.eye
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round;

    var kind = pose.eyes;
    // Blink overrides open-style eyes.
    if (blink > 0.6 && (kind == EyeKind.open || kind == EyeKind.wide)) {
      kind = EyeKind.closed;
    }

    switch (kind) {
      case EyeKind.open || EyeKind.wide:
        final rx = kind == EyeKind.wide ? 8.5 : 7.5;
        final ry =
            (kind == EyeKind.wide ? 11.5 : 10.0) * (1 - blink * 0.8);
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(x, 60), width: rx * 2, height: ry * 2),
            paint);
        canvas.drawCircle(Offset(x + rx * 0.4, 60 - ry * 0.45), 2.4,
            Paint()..color = Colors.white);
        canvas.drawCircle(Offset(x - rx * 0.35, 60 + ry * 0.3), 1.1,
            Paint()..color = Colors.white.withValues(alpha: 0.7));
      case EyeKind.smile:
        final p = Path()
          ..moveTo(x - 8, 62)
          ..quadraticBezierTo(x, 53, x + 8, 62);
        canvas.drawPath(p, stroke);
      case EyeKind.half || EyeKind.closed:
        final dip = kind == EyeKind.closed ? 6.0 : 5.0;
        final p = Path()
          ..moveTo(x - 8, 59)
          ..quadraticBezierTo(x, 59 + dip, x + 8, 59);
        canvas.drawPath(p, stroke);
    }
  }

  void _drawMouth(Canvas canvas) {
    final stroke = Paint()
      ..color = HanaColors.eye
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    switch (pose.mouth) {
      case MouthKind.neutral:
        final p = Path()
          ..moveTo(53, 81)
          ..quadraticBezierTo(60, 86, 67, 81);
        canvas.drawPath(p, stroke);
      case MouthKind.small:
        canvas.drawOval(
            Rect.fromCenter(
                center: const Offset(60, 84), width: 7, height: 6),
            Paint()..color = HanaColors.eye);
      case MouthKind.open:
        final p = Path()
          ..moveTo(50, 80)
          ..quadraticBezierTo(60, 92, 70, 80)
          ..quadraticBezierTo(60, 86, 50, 80)
          ..close();
        canvas.drawPath(p, Paint()..color = HanaColors.eye);
        canvas.drawOval(
            Rect.fromCenter(
                center: const Offset(60, 86), width: 9, height: 6),
            Paint()..color = HanaColors.tongue);
      case MouthKind.tongue:
        final p = Path()
          ..moveTo(53, 81)
          ..quadraticBezierTo(60, 87, 67, 81);
        canvas.drawPath(p, stroke);
        final tongue = Path()
          ..moveTo(60, 84)
          ..quadraticBezierTo(57, 84, 57, 89)
          ..arcToPoint(const Offset(63, 89),
              radius: const Radius.circular(3), clockwise: false)
          ..quadraticBezierTo(63, 84, 60, 84)
          ..close();
        canvas.drawPath(tongue, Paint()..color = HanaColors.tongue);
    }
  }

  void _drawZzz(Canvas canvas, double phase) {
    void z(String text, Offset base, double fontSize, double offsetPhase) {
      final p = (phase + offsetPhase) % 1.0;
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: HanaColors.eye.withValues(alpha: (1 - p) * 0.8),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, base + Offset(p * 6, -p * 14));
    }

    z('z', const Offset(88, 24), 13, 0);
    z('Z', const Offset(97, 8), 16, 0.5);
  }

  @override
  bool shouldRepaint(MascotPainter old) =>
      old.pose != pose ||
      old.blink != blink ||
      old.bob != bob ||
      old.earSwing != earSwing ||
      old.bodyBounce != bodyBounce ||
      old.fullBody != fullBody ||
      old.sleepPhase != sleepPhase ||
      old.accessory != accessory;
}
