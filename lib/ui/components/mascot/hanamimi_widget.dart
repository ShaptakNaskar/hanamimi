import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'mascot_painter.dart';

enum MascotState { idle, playing, paused, changing, sleeping, loading }

const _poses = {
  MascotState.idle: MascotPose(
      eyes: EyeKind.open, brow: BrowKind.none, mouth: MouthKind.neutral),
  MascotState.playing: MascotPose(
      eyes: EyeKind.smile, brow: BrowKind.happy, mouth: MouthKind.open),
  MascotState.paused: MascotPose(
      eyes: EyeKind.half, brow: BrowKind.flat, mouth: MouthKind.neutral,
      tilt: 4),
  MascotState.changing: MascotPose(
      eyes: EyeKind.wide, brow: BrowKind.up, mouth: MouthKind.small,
      tilt: 14),
  MascotState.sleeping: MascotPose(
      eyes: EyeKind.closed, brow: BrowKind.flat, mouth: MouthKind.neutral,
      tilt: 6),
  MascotState.loading: MascotPose(
      eyes: EyeKind.open, brow: BrowKind.happy, mouth: MouthKind.tongue),
};

/// The living mascot. Rive is replaced by a code-driven animation layer:
/// blink scheduler, amplitude head-bop with lagging ears (secondary
/// motion), smooth tilt transitions, floating zzz while sleeping.
class HanamimiMascot extends StatefulWidget {
  const HanamimiMascot({
    super.key,
    required this.state,
    this.amplitude = 0,
    this.size = 100,
    this.fullBody = false,
    this.accessory = Accessory.none,
    this.onTap,
  });

  final MascotState state;

  /// 0..1 — how hard the music is hitting (visualizer bands in M8).
  final double amplitude;
  final double size;
  final bool fullBody;
  final Accessory accessory;
  final VoidCallback? onTap;

  @override
  State<HanamimiMascot> createState() => _HanamimiMascotState();
}

class _HanamimiMascotState extends State<HanamimiMascot>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _rng = math.Random();

  double _time = 0;
  Duration _last = Duration.zero;
  double _tilt = 0; // eased current tilt, degrees
  double _bobEnvelope = 0; // eases bob in/out on play/pause

  // Blink scheduling: slow blink every 4–7 s in eye-open states.
  double _nextBlinkAt = 3;
  double _blink = 0; // 0 open → 1 closed

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _time += dt;

    final targetTilt = _poses[widget.state]!.tilt;
    _tilt += (targetTilt - _tilt) * math.min(1, dt * 8);

    final bobTarget = widget.state == MascotState.playing ? 1.0 : 0.0;
    _bobEnvelope += (bobTarget - _bobEnvelope) * math.min(1, dt * 3);

    // Blink.
    if (_time >= _nextBlinkAt) {
      _blink = 1;
      _nextBlinkAt = _time + 4 + _rng.nextDouble() * 3;
    } else {
      _blink = math.max(0, _blink - dt * 8); // reopen over ~120ms
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
    // Reduce motion: hold still, keep only the slow blink.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final amp = reduceMotion ? 0.0 : 0.3 + widget.amplitude * 0.7;
    final bob = math.sin(_time * 4.0) * amp * 0.18 * _bobEnvelope;
    // Ears lag behind the head — sampled slightly in the past, smaller.
    final earSwing =
        math.sin(_time * 4.0 - 0.6) * amp * 0.12 * _bobEnvelope;
    final bounce = widget.state == MascotState.loading
        ? math.sin(_time * 6) * 2.0
        : 0.0;

    final h = widget.fullBody ? 158.0 : 132.0;
    return GestureDetector(
      onTap: widget.onTap,
      child: CustomPaint(
        size: Size(widget.size, widget.size * (h / 120)),
        painter: MascotPainter(
          pose: _poses[widget.state]!,
          blink: _blink,
          bob: bob + (_tilt - _poses[widget.state]!.tilt) * math.pi / 180,
          earSwing: earSwing,
          bodyBounce: bounce,
          fullBody: widget.fullBody,
          sleepPhase: widget.state == MascotState.sleeping
              ? (_time * 0.4) % 1.0
              : null,
          accessory: widget.accessory,
        ),
      ),
    );
  }
}
