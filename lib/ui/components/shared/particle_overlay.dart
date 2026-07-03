import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../theme/hanamimi_theme.dart';

/// Theme background particles (DESIGN.md §3/§12): drifting sakura
/// petals on Cherry Blossom, rising star dots on Starry Night, nothing
/// on Rainy Day / Matcha. Never obstructs touch — pure IgnorePointer.
class ParticleOverlay extends StatefulWidget {
  const ParticleOverlay({super.key, required this.theme});

  final HanamimiTheme theme;

  bool get _enabled =>
      theme.id == 'cherry_blossom' || theme.id == 'starry_night';

  @override
  State<ParticleOverlay> createState() => _ParticleOverlayState();
}

class _Particle {
  _Particle(math.Random rng, {required bool anywhere})
      : x = rng.nextDouble(),
        y = anywhere ? rng.nextDouble() : -0.05,
        size = 2 + rng.nextDouble() * 6,
        speed = 0.02 + rng.nextDouble() * 0.05,
        drift = (rng.nextDouble() - 0.5) * 0.04,
        spin = rng.nextDouble() * 2 * math.pi,
        opacity = 0.15 + rng.nextDouble() * 0.25;

  double x, y;
  final double size, speed, drift, spin, opacity;
}

class _ParticleOverlayState extends State<ParticleOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _rng = math.Random();
  final _particles = <_Particle>[];
  Duration _last = Duration.zero;
  double _time = 0;

  static const _count = 14;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _count; i++) {
      _particles.add(_Particle(_rng, anywhere: true));
    }
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    if (!widget._enabled) return;
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _time += dt;
    final falling = widget.theme.id == 'cherry_blossom';
    for (var i = 0; i < _particles.length; i++) {
      final p = _particles[i];
      p.y += (falling ? p.speed : -p.speed) * dt * 3;
      p.x += p.drift * dt + (falling ? math.sin(_time + i) * 0.0006 : 0);
      final gone = falling ? p.y > 1.05 : p.y < -0.05;
      if (gone) _particles[i] = _Particle(_rng, anywhere: false)..y = falling ? -0.05 : 1.05;
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
    if (!widget._enabled || MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ParticlePainter(
          particles: _particles,
          theme: widget.theme,
          time: _time,
        ),
      ),
    );
  }
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({
    required this.particles,
    required this.theme,
    required this.time,
  });

  final List<_Particle> particles;
  final HanamimiTheme theme;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final sakura = theme.id == 'cherry_blossom';
    for (final p in particles) {
      final pos = Offset(p.x * size.width, p.y * size.height);
      if (sakura) {
        _petal(canvas, pos, p);
      } else {
        canvas.drawCircle(
          pos,
          p.size * 0.35,
          Paint()
            ..color = theme.accent.withValues(alpha: p.opacity * 0.8),
        );
      }
    }
  }

  /// Five-pointed soft petal shape with a slight concave middle.
  void _petal(Canvas canvas, Offset center, _Particle p) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(p.spin + time * 0.4);
    final s = p.size;
    final path = Path()
      ..moveTo(0, -s)
      ..quadraticBezierTo(s * 0.9, -s * 0.6, s * 0.55, s * 0.35)
      ..quadraticBezierTo(s * 0.25, s * 0.9, 0, s * 0.55) // concave dip
      ..quadraticBezierTo(-s * 0.25, s * 0.9, -s * 0.55, s * 0.35)
      ..quadraticBezierTo(-s * 0.9, -s * 0.6, 0, -s)
      ..close();
    canvas.drawPath(
        path,
        Paint()
          ..color = theme.primary.withValues(alpha: p.opacity));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => true;
}
