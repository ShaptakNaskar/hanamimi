import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/hanamimi_theme.dart';
import '../../../theme/theme_tokens.dart';
import '../../../utils/duration_ext.dart';

/// The caterpillar seek bar (DESIGN.md §9.5): capsule track, wavy body
/// along the filled portion, thumb "head" with two eyes that grows on
/// touch. Timestamps sit below.
class SeekBarWidget extends StatefulWidget {
  const SeekBarWidget({
    super.key,
    required this.position,
    required this.duration,
    required this.theme,
    required this.onSeek,
    this.buffered = Duration.zero,
    this.partnerPosition,
  });

  final Duration position;
  final Duration duration;

  /// How much of the track has buffered — drawn as a lighter overlay
  /// ahead of the played portion.
  final Duration buffered;

  /// Long-Distance Date (3.0 #6): where the partner is in this track —
  /// a tiny heart under the bar. Null when not in a room.
  final Duration? partnerPosition;
  final HanamimiTheme theme;
  final ValueChanged<Duration> onSeek;

  @override
  State<SeekBarWidget> createState() => _SeekBarWidgetState();
}

class _SeekBarWidgetState extends State<SeekBarWidget> {
  double? _dragValue; // 0..1 while scrubbing
  bool get _dragging => _dragValue != null;

  double get _progress {
    if (_dragValue != null) return _dragValue!;
    final ms = widget.duration.inMilliseconds;
    return ms == 0
        ? 0
        : (widget.position.inMilliseconds / ms).clamp(0.0, 1.0);
  }

  Duration get _displayPosition => _dragging
      ? widget.duration * _dragValue!
      : widget.position;

  double get _bufferedFraction {
    final ms = widget.duration.inMilliseconds;
    if (ms == 0) return 0;
    return (widget.buffered.inMilliseconds / ms).clamp(0.0, 1.0);
  }

  void _updateDrag(Offset localPosition, double width) {
    setState(() {
      _dragValue = (localPosition.dx / width).clamp(0.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) =>
                _updateDrag(d.localPosition, width),
            onHorizontalDragUpdate: (d) =>
                _updateDrag(d.localPosition, width),
            onHorizontalDragEnd: (_) {
              widget.onSeek(widget.duration * _dragValue!);
              setState(() => _dragValue = null);
            },
            onTapUp: (d) {
              final v = (d.localPosition.dx / width).clamp(0.0, 1.0);
              widget.onSeek(widget.duration * v);
            },
            child: SizedBox(
              height: 32,
              child: CustomPaint(
                size: Size(width, 32),
                painter: _CaterpillarPainter(
                  progress: _progress,
                  buffered: _bufferedFraction,
                  partner: widget.partnerPosition == null ||
                          widget.duration == Duration.zero
                      ? null
                      : (widget.partnerPosition!.inMilliseconds /
                              widget.duration.inMilliseconds)
                          .clamp(0.0, 1.0),
                  theme: widget.theme,
                  thumbScale: _dragging ? 20 / 14 : 1.0,
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: Space.s1),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_displayPosition.mmss,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: TypeScale.timestamp,
                    color: widget.theme.textMuted)),
            Text(widget.duration.mmss,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: TypeScale.timestamp,
                    color: widget.theme.textMuted)),
          ],
        ),
      ],
    );
  }
}

class _CaterpillarPainter extends CustomPainter {
  _CaterpillarPainter({
    required this.progress,
    required this.buffered,
    this.partner,
    required this.theme,
    required this.thumbScale,
  });

  final double progress;
  final double buffered;

  /// Partner's position 0–1 (date mode), or null.
  final double? partner;
  final HanamimiTheme theme;
  final double thumbScale;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    const trackH = 6.0;
    final fillEnd = size.width * progress;

    final trackPaint = Paint()
      ..color = theme.divider
      ..style = PaintingStyle.stroke
      ..strokeWidth = trackH
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(3, cy), Offset(size.width - 3, cy), trackPaint);

    // Buffered overlay: a lighter segment ahead of the played portion,
    // so you can see how much is loaded (matters most for online
    // streaming). Drawn between the fill end and the buffered end.
    final bufferedEnd = size.width * buffered;
    if (bufferedEnd > fillEnd + 1) {
      canvas.drawLine(
        Offset(math.max(3, fillEnd), cy),
        Offset(math.min(size.width - 3, bufferedEnd), cy),
        Paint()
          ..color = theme.primary.withValues(alpha: 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = trackH
          ..strokeCap = StrokeCap.round,
      );
    }

    if (fillEnd > 3) {
      // Wavy caterpillar body along the filled portion.
      final bodyPaint = Paint()
        ..color = theme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackH
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(3, cy);
      for (double x = 3; x <= math.max(3, fillEnd - 4); x += 2) {
        path.lineTo(x, cy + math.sin(x / 9) * 1.6);
      }
      canvas.drawPath(path, bodyPaint);
    }

    // Thumb — the head.
    final r = 7.0 * thumbScale;
    final head = Offset(fillEnd.clamp(r, size.width - r), cy);
    canvas.drawCircle(
      head,
      r + 2,
      Paint()
        ..color = theme.primary.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(head, r, Paint()..color = Colors.white);

    // Two tiny eyes looking forward.
    final eyePaint = Paint()..color = theme.textPrimary;
    canvas.drawCircle(head + Offset(r * 0.25, -r * 0.25), 1.4, eyePaint);
    canvas.drawCircle(head + Offset(r * 0.65, -r * 0.1), 1.4, eyePaint);

    // Date mode: the partner rides along as a small accent dot under
    // the track — you can see each other approach the same beat.
    final p = partner;
    if (p != null) {
      final px = (size.width * p).clamp(3.0, size.width - 3.0);
      canvas.drawCircle(
          Offset(px, cy + trackH + 3),
          2.5,
          Paint()..color = theme.accent);
    }
  }

  @override
  bool shouldRepaint(_CaterpillarPainter old) =>
      old.progress != progress ||
      old.buffered != buffered ||
      old.partner != partner ||
      old.thumbScale != thumbScale ||
      old.theme != theme;
}
