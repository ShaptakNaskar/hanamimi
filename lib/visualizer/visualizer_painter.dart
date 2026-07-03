import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/hanamimi_theme.dart';

/// Draws the 12-band visualizer in the theme's style (DESIGN.md §3):
/// bars (Cherry Blossom), raindrops (Rainy Day), radial burst
/// (Starry Night), waveform (Matcha). [time] drives motion for styles
/// that animate independently of band values.
class VisualizerPainter extends CustomPainter {
  VisualizerPainter({
    required this.bands,
    required this.theme,
    required this.time,
  });

  final List<double> bands;
  final HanamimiTheme theme;
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty) return;
    switch (theme.visualizerStyle) {
      case VisualizerStyle.bars:
        _paintBars(canvas, size);
      case VisualizerStyle.raindrops:
        _paintRaindrops(canvas, size);
      case VisualizerStyle.radial:
        _paintRadial(canvas, size);
      case VisualizerStyle.wave:
        _paintWave(canvas, size);
    }
  }

  void _paintBars(Canvas canvas, Size size) {
    final n = bands.length;
    final gap = size.width / (n * 2);
    final barW = gap;
    for (var i = 0; i < n; i++) {
      final h = math.max(4.0, bands[i] * size.height);
      final x = gap / 2 + i * (barW + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - h, barW, h),
        Radius.circular(barW / 2),
      );
      // Shorter bars pinker, taller shift toward lavender.
      final color =
          Color.lerp(theme.primary, theme.secondary, bands[i])!;
      canvas.drawRRect(rect, Paint()..color = color);
    }
  }

  void _paintRaindrops(Canvas canvas, Size size) {
    final n = bands.length;
    final colW = size.width / n;
    for (var i = 0; i < n; i++) {
      final intensity = bands[i];
      if (intensity < 0.06) continue;
      // Bass: large slow drops; treble: small fast ones.
      final speed = 0.25 + (i / n) * 0.9 + intensity * 0.4;
      final phase = (time * speed + i * 0.37) % 1.0;
      final y = phase * size.height;
      final r = (2.0 + (1 - i / n) * 4.0) * (0.5 + intensity * 0.8);
      final x = colW * (i + 0.5) + math.sin(i * 7.3) * colW * 0.2;
      final color = Color.lerp(theme.primary, theme.accent, intensity)!
          .withValues(alpha: (1 - phase) * 0.9);

      // Teardrop: circle + triangle tail upward.
      final paint = Paint()..color = color;
      canvas.drawCircle(Offset(x, y), r, paint);
      final tail = Path()
        ..moveTo(x - r * 0.8, y - r * 0.4)
        ..quadraticBezierTo(x, y - r * 2.6, x + r * 0.8, y - r * 0.4)
        ..close();
      canvas.drawPath(tail, paint);
    }
  }

  void _paintRadial(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.height / 2 - 2;
    const rays = 24;

    // Center glow — warm gold.
    canvas.drawCircle(
      center,
      6 + bands[0] * 5,
      Paint()
        ..color = theme.accent.withValues(alpha: 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    for (var ray = 0; ray < rays; ray++) {
      final band = bands[ray % bands.length];
      final angle = (ray / rays) * 2 * math.pi + time * 0.3;
      final len = 8 + band * maxR;
      final start = center +
          Offset(math.cos(angle), math.sin(angle)) * 8.0;
      final end = center +
          Offset(math.cos(angle), math.sin(angle)) * (8.0 + len);
      canvas.drawLine(
        start,
        end,
        Paint()
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..shader = LinearGradient(
            colors: [theme.primary, theme.secondary],
          ).createShader(Rect.fromPoints(start, end)),
      );
    }
  }

  void _paintWave(Canvas canvas, Size size) {
    final n = bands.length;
    final midY = size.height * 0.65;
    final points = <Offset>[
      for (var i = 0; i < n; i++)
        Offset(
          size.width * i / (n - 1),
          midY - bands[i] * size.height * 0.55,
        ),
    ];

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final mid = Offset(
        (points[i].dx + points[i + 1].dx) / 2,
        (points[i].dy + points[i + 1].dy) / 2,
      );
      path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);

    // Soft translucent wash under the line.
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
        fill, Paint()..color = theme.primary.withValues(alpha: 0.12));

    canvas.drawPath(
      path,
      Paint()
        ..color = theme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(VisualizerPainter old) =>
      old.bands != bands || old.time != time || old.theme != theme;
}
