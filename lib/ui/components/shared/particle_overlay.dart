import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../theme/hanamimi_theme.dart';

/// Theme background particles (DESIGN.md §3/§12): drifting sakura
/// petals on Cherry Blossom, rising star dots on Starry Night, and —
/// when [fireflies] is on — a blinking firefly swarm on any DARK theme.
/// Never obstructs touch — pure IgnorePointer.
class ParticleOverlay extends StatefulWidget {
  const ParticleOverlay({super.key, required this.theme, this.fireflies = false});

  final HanamimiTheme theme;

  /// Firefly swarm on dark themes (the caller gates this behind the
  /// 'fireflies' buddy toggle).
  final bool fireflies;

  bool get _classic =>
      theme.id == 'cherry_blossom' || theme.id == 'starry_night';
  bool get _firefliesOn => fireflies && theme.isDark;
  bool get _enabled => _classic || _firefliesOn;

  @override
  State<ParticleOverlay> createState() => _ParticleOverlayState();
}

/// One firefly: wanders on slow sine paths and blinks on its own
/// rhythm (the blink is squared so it flares briefly and rests long).
class _Firefly {
  _Firefly(math.Random rng)
      : x = rng.nextDouble(),
        y = rng.nextDouble(),
        wx = 0.5 + rng.nextDouble() * 0.9,
        wy = 0.4 + rng.nextDouble() * 0.8,
        px = rng.nextDouble() * 2 * math.pi,
        py = rng.nextDouble() * 2 * math.pi,
        pulse = 1.8 + rng.nextDouble() * 2.8,
        pp = rng.nextDouble() * 2 * math.pi,
        size = 1.3 + rng.nextDouble() * 1.6;

  double x, y;
  final double wx, wy, px, py, pulse, pp, size;
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
  static const _fireflyCount = 10;
  final _fireflies = <_Firefly>[];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _count; i++) {
      _particles.add(_Particle(_rng, anywhere: true));
    }
    for (var i = 0; i < _fireflyCount; i++) {
      _fireflies.add(_Firefly(_rng));
    }
    _ticker = createTicker(_tick);
    // Only tick when there's something to animate — an idle active
    // ticker still forces an engine frame every vsync.
    _syncTicker();
  }

  @override
  void didUpdateWidget(ParticleOverlay old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  void _syncTicker() {
    if (!mounted) return;
    if (widget._enabled && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!widget._enabled && _ticker.isActive) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  void _tick(Duration elapsed) {
    // Ambient drift doesn't need 60 fps — repaint at ~30. On desktop
    // this overlay covers the whole window and every saved frame is a
    // full-layer paint (part of the high-CPU report).
    if ((elapsed - _last).inMilliseconds < 32) return;
    // Clamp dt: it spans the whole disabled/backgrounded stretch after
    // a theme switch or app resume, which would teleport every particle.
    final dt =
        ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 15);
    _last = elapsed;
    if (!widget._enabled) return;
    _time += dt;
    if (widget._classic) {
      final falling = widget.theme.id == 'cherry_blossom';
      for (var i = 0; i < _particles.length; i++) {
        final p = _particles[i];
        p.y += (falling ? p.speed : -p.speed) * dt * 3;
        p.x += p.drift * dt + (falling ? math.sin(_time + i) * 0.0006 : 0);
        final gone = falling ? p.y > 1.05 : p.y < -0.05;
        if (gone) _particles[i] = _Particle(_rng, anywhere: false)..y = falling ? -0.05 : 1.05;
      }
    }
    if (widget._firefliesOn) {
      for (final f in _fireflies) {
        // Lazy sine wander — fireflies drift, they don't travel.
        f.x += math.sin(_time * f.wx + f.px) * 0.0009;
        f.y += math.cos(_time * f.wy + f.py) * 0.0007;
        if (f.x < -0.03) f.x += 1.06;
        if (f.x > 1.03) f.x -= 1.06;
        if (f.y < -0.03) f.y += 1.06;
        if (f.y > 1.03) f.y -= 1.06;
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
    if (!widget._enabled || MediaQuery.disableAnimationsOf(context)) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _ParticlePainter(
          particles: widget._classic ? _particles : const [],
          fireflies: widget._firefliesOn ? _fireflies : const [],
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
    required this.fireflies,
    required this.theme,
    required this.time,
  });

  final List<_Particle> particles;
  final List<_Firefly> fireflies;
  final HanamimiTheme theme;
  final double time;

  static const _glow = Color(0xFFE8F0A8);
  static const _core = Color(0xFFF7F4C5);

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
    for (final f in fireflies) {
      final blink = math
          .pow(math.max(0.0, math.sin(time * 2 * math.pi / f.pulse + f.pp)), 2)
          .toDouble();
      if (blink < 0.04) continue; // resting dark between flashes
      final pos = Offset(f.x * size.width, f.y * size.height);
      canvas.drawCircle(
        pos,
        f.size * 3.4,
        Paint()
          ..color = _glow.withValues(alpha: 0.08 + blink * 0.16)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
        pos,
        f.size,
        Paint()..color = _core.withValues(alpha: 0.3 + blink * 0.65),
      );
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
