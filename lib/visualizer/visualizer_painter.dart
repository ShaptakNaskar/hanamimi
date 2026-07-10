import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/hanamimi_theme.dart';

/// Cross-frame state for styles whose motion can't be derived from
/// (time, bands) alone — the VU needles' spring ballistics. Owned by
/// the widget so it survives painter reconstruction every frame.
class VisualizerSim {
  double _lastTime = -1;

  /// VU needle positions/velocities, 0–1 of full deflection.
  final needles = [0.0, 0.0];
  final needleVel = [0.0, 0.0];

  /// Peak-LED brightness per meter; snaps to 1 on a peak, then decays
  /// so the LED visibly hangs like a real peak indicator.
  final ledGlow = [0.0, 0.0];

  /// LED-VU peak-hold per channel: held level and seconds since set.
  final levelPeaks = [0.0, 0.0];
  final levelPeakAge = [9.0, 9.0];

  /// True while needles/peak markers are still visibly falling — keeps
  /// the clock ticking briefly after the band stream settles on pause.
  bool get hasEnergy =>
      needles.any((n) => n > 0.005) ||
      ledGlow.any((g) => g > 0.02) ||
      levelPeaks.any((p) => p > 0.005);

  /// Advances the sim clock; returns a clamped dt (0 on first frame or
  /// when paint reruns at an unchanged time, e.g. band-driven repaints).
  double step(double time) {
    final dt =
        _lastTime < 0 ? 0.0 : (time - _lastTime).clamp(0.0, 0.1).toDouble();
    _lastTime = time;
    return dt;
  }
}

/// Draws the 12-band visualizer in the given style (DESIGN.md §3):
/// rounded gradient bars, or twin analog VU meters. [time] drives the
/// VU needle physics; [reactivity] (its own slider, distinct from the
/// sensitivity gain applied to the bands upstream) stiffens the needle
/// spring — high is jumpy, low is smoothed.
class VisualizerPainter extends CustomPainter {
  VisualizerPainter({
    required this.bands,
    required this.theme,
    required this.style,
    required this.time,
    required this.sim,
    this.reactivity = 1.0,
    this.vuSplit = false,
    this.ledDiscrete = true,
  });

  final List<double> bands;
  final HanamimiTheme theme;
  final VisualizerStyle style;
  final double time;
  final VisualizerSim sim;
  final double reactivity;

  /// True: needles show a bass/treble split; false: L/R loudness.
  final bool vuSplit;

  /// LED VU look: discrete LED segments (foobar) vs continuous bar (OBS).
  final bool ledDiscrete;

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty) return;
    final dt = sim.step(time);
    switch (style) {
      case VisualizerStyle.bars:
        _paintBars(canvas, size);
      case VisualizerStyle.vuMeters:
        _paintVuMeters(canvas, size, dt);
      case VisualizerStyle.ledVu:
        _paintLedVu(canvas, size, dt);
    }
  }

  /// Meter colors must stay vivid AND escalate: the adaptive themes
  /// lift their palette from album art, which guarantees neither — a
  /// washed accent made the hot zone read dimmer than the mid zone
  /// (user report, twice). Each zone gets a higher saturation floor
  /// than the last, so hot is always the most vibrant whatever the
  /// palette; hand-tuned themes pass through nearly unchanged.
  static Color _zone(Color c, double minSat, double minL, double maxL) {
    final hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation(math.max(hsl.saturation, minSat))
        .withLightness(hsl.lightness.clamp(minL, maxL))
        .toColor();
  }

  Color get _safeColor => _zone(theme.primary, 0.55, 0.45, 0.62);
  Color get _midColor => _zone(theme.secondary, 0.68, 0.45, 0.60);

  /// Hot must out-punch mid on ANY palette: saturation floored at 0.9,
  /// lightness pinned near 0.5 where chroma peaks (a 0.66 ceiling let
  /// a light adaptive accent render as pastel salmon — dimmer-looking
  /// than the lime mid zone), and the hue leaned 40% toward red so the
  /// top of the meter always speaks "danger" in any theme.
  Color get _hotColor {
    final hsl = HSLColor.fromColor(theme.accent);
    final h = hsl.hue;
    final toRed = h <= 180 ? -h : 360 - h;
    return hsl
        .withHue((h + toRed * 0.4) % 360)
        .withSaturation(math.max(hsl.saturation, 0.9))
        .withLightness(hsl.lightness.clamp(0.48, 0.58))
        .toColor();
  }

  /// Channel letter for LED-VU row [ch]: L/R in loudness mode, B/T
  /// when the meters listen to the bass/treble split.
  String _channelLetter(int ch) =>
      vuSplit ? (ch == 0 ? 'B' : 'T') : (ch == 0 ? 'L' : 'R');

  void _paintChannelLabel(Canvas canvas, int ch, Offset at) {
    final label = TextPainter(
      text: TextSpan(
        text: _channelLetter(ch),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: theme.textMuted,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, at - Offset(0, label.height / 2));
  }

  /// The two meter drive values, shared by both VU styles. Loudness
  /// mode (default): true left/right channel RMS (frame values
  /// [12]/[13]). Split mode (the original look, kept by request):
  /// left = lows, right = highs — which also doubles as the fallback
  /// when channel RMS isn't in the frame.
  List<double> _vuTargets() => !vuSplit && bands.length >= 14
      ? [bands[12].clamp(0.0, 1.0), bands[13].clamp(0.0, 1.0)]
      : [
          (bands[0] * 0.35 +
                  bands[1] * 0.30 +
                  bands[2] * 0.20 +
                  bands[3] * 0.15)
              .clamp(0.0, 1.0),
          (bands[6] * 0.15 +
                  bands[7] * 0.20 +
                  bands[8] * 0.25 +
                  bands[9] * 0.20 +
                  bands[10] * 0.20)
              .clamp(0.0, 1.0),
        ];

  void _paintBars(Canvas canvas, Size size) {
    // Frames carry L/R loudness after the 12 spectral bands — bars
    // only draw the spectrum.
    final n = math.min(bands.length, 12);
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

  void _paintVuMeters(Canvas canvas, Size size, double dt) {
    // Two analog needle meters fed by _vuTargets (left/right loudness,
    // or the bass/treble split).
    final targets = _vuTargets();
    // Reactivity stiffens the spring: 1× is the stock feel, 3× snaps
    // to every transient, 0.5× glides. Damping tracks √k so the
    // overshoot ratio (the "analog" wobble) stays constant, with extra
    // damping folded in at the low end so it reads smoothed, not slow.
    final k = 120 * (0.3 + 0.7 * reactivity);
    final damping =
        9 * math.sqrt(k / 120) * (reactivity < 1 ? 2 - reactivity : 1);
    for (var m = 0; m < 2; m++) {
      final accel =
          (targets[m] - sim.needles[m]) * k - sim.needleVel[m] * damping;
      sim.needleVel[m] += accel * dt;
      sim.needles[m] =
          (sim.needles[m] + sim.needleVel[m] * dt).clamp(-0.02, 1.04);

      final faceW = size.width / 2 - 12;
      final face = Rect.fromLTWH(
          m == 0 ? 4 : size.width / 2 + 8, 2, faceW, size.height - 4);
      // No face fill — the dial floats on the screen background.
      // Still clip: ticks/needle can't spill out of the meter's slot
      // whatever the aspect ratio.
      canvas.save();
      canvas.clipRRect(
          RRect.fromRectAndRadius(face, const Radius.circular(10)));

      final pivot = Offset(face.center.dx, face.bottom - 4);
      // Radius fits inside the face height (the -90° tick reaches
      // straight up from the pivot), then capped by width.
      final arcR = math.min(face.height - 10, faceW * 0.46);
      const sweepFrom = -140.0 * math.pi / 180; // needle angle range
      const sweepTo = -40.0 * math.pi / 180;

      // Tick marks; the hot top quarter in (vivid) accent, like a red
      // zone — adaptive palettes can wash the raw accent to grey.
      final hotZone = _hotColor;
      for (var tIdx = 0; tIdx <= 10; tIdx++) {
        final f = tIdx / 10;
        final a = sweepFrom + (sweepTo - sweepFrom) * f;
        final dirT = Offset(math.cos(a), math.sin(a));
        final major = tIdx.isEven;
        canvas.drawLine(
          pivot + dirT * (arcR - (major ? 7 : 4)),
          pivot + dirT * arcR,
          Paint()
            ..color = f > 0.72 ? hotZone : theme.textMuted
            ..strokeWidth = major ? 2 : 1
            ..strokeCap = StrokeCap.round,
        );
      }


      final needle = sim.needles[m].clamp(0.0, 1.0);
      final na = sweepFrom + (sweepTo - sweepFrom) * needle;
      final nd = Offset(math.cos(na), math.sin(na));
      // Peaking must read at a glance: the needle brightens toward a
      // lit-up shade of the (vivid) accent and gains a glow halo.
      final hsl = HSLColor.fromColor(hotZone);
      final hotAccent = hsl
          .withLightness(
              (hsl.lightness + (1 - hsl.lightness) * 0.45).clamp(0.0, 1.0))
          .withSaturation((hsl.saturation * 1.2).clamp(0.0, 1.0))
          .toColor();
      final hot = ((needle - 0.7) / 0.3).clamp(0.0, 1.0);
      final needleColor = Color.lerp(theme.primary, hotAccent, hot)!;
      final tip = pivot + nd * (arcR - 2);

      // Peak LED in the dial's dead space — centered, just below the
      // arc's midpoint, above the pivot. Snaps on past 0.85, hangs on
      // for a beat like a real peak indicator. Drawn before the needle
      // (it sits on the needle's path at center deflection).
      if (needle > 0.85) {
        sim.ledGlow[m] = 1.0;
      } else {
        sim.ledGlow[m] = math.max(0, sim.ledGlow[m] - 2.5 * dt);
      }
      final glow = sim.ledGlow[m];
      final led = Offset(pivot.dx, pivot.dy - arcR * 0.5);
      if (glow > 0.02) {
        canvas.drawCircle(
          led,
          6.0,
          Paint()
            ..color = hotAccent.withValues(alpha: glow * 0.7)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }
      canvas.drawCircle(
        led,
        2.6,
        Paint()
          ..color = Color.lerp(
              theme.divider.withValues(alpha: 0.6), hotAccent, glow)!,
      );

      // Pivot dot below the needle too — the needle sweeps over both.
      canvas.drawCircle(pivot, 3.2, Paint()..color = theme.secondary);
      if (hot > 0.05) {
        canvas.drawLine(
          pivot + nd * 4.0,
          tip,
          Paint()
            ..color = hotAccent.withValues(alpha: hot * 0.7)
            ..strokeWidth = 6
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawLine(
        pivot + nd * 4.0,
        tip,
        Paint()
          ..color = needleColor
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }
  }

  /// Horizontal stereo level meters, L above R with no gap to speak
  /// of — the hi-fi/OBS look. [ledDiscrete] picks tightly packed LED
  /// segments (with a hanging peak segment) or a continuous bar (with
  /// a peak line). Zones run primary → secondary → accent.
  void _paintLedVu(Canvas canvas, Size size, double dt) {
    final targets = _vuTargets();
    const labelW = 12.0;
    const rowGap = 2.0;
    final rowH = (size.height - rowGap) / 2;
    final meterW = size.width - labelW;

    final safe = _safeColor;
    final mid = _midColor;
    final hot = _hotColor;
    Color zoneColor(double f) => f < 0.60
        ? safe
        : f < 0.82
            ? mid
            : hot;
    // Unlit slots are DARK embers of their zone, like real hardware —
    // the old translucent-pale treatment read as a washed-out lit
    // section and made the (rarely reached) hot zone look broken.
    Color dimColor(Color c) {
      final hsl = HSLColor.fromColor(c);
      return hsl
          .withLightness(hsl.lightness * 0.42)
          .withSaturation(hsl.saturation * 0.8)
          .toColor()
          .withValues(alpha: 0.55);
    }

    for (var ch = 0; ch < 2; ch++) {
      final top = ch * (rowH + rowGap);
      final level = targets[ch];

      // Peak-hold: jump up with the signal, hang ~0.5 s, then fall.
      if (level >= sim.levelPeaks[ch]) {
        sim.levelPeaks[ch] = level;
        sim.levelPeakAge[ch] = 0;
      } else {
        sim.levelPeakAge[ch] += dt;
        if (sim.levelPeakAge[ch] > 0.5) {
          sim.levelPeaks[ch] =
              math.max(0, sim.levelPeaks[ch] - 0.8 * dt);
        }
      }
      final peak = sim.levelPeaks[ch];

      // Channel letter, vertically centered on its row.
      _paintChannelLabel(canvas, ch, Offset(0, top + rowH / 2));

      if (ledDiscrete) {
        // Tightly packed segments, hairline gaps (the foobar look).
        const cellW = 5.0;
        const cellGap = 1.5;
        final n = math.max(8, (meterW / (cellW + cellGap)).floor());
        final lit = (level * n).round();
        final peakIdx = (peak * (n - 1)).round();
        for (var i = 0; i < n; i++) {
          final f = i / (n - 1);
          final x = labelW + i * (cellW + cellGap);
          final on = i < lit;
          final isPeak = i == peakIdx && peak > 0.02;
          final color = isPeak
              ? theme.textPrimary.withValues(alpha: 0.9)
              : on
                  ? zoneColor(f)
                  : dimColor(zoneColor(f));
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x, top, cellW, rowH),
              const Radius.circular(1),
            ),
            Paint()..color = color,
          );
        }
      } else {
        // Continuous bar over a dark-ember zone track (the OBS look).
        final row = Rect.fromLTWH(labelW, top, meterW, rowH);
        void zones(double upTo, {required bool lit}) {
          final stops = [0.0, 0.60, 0.82, 1.0];
          for (var z = 0; z < 3; z++) {
            final lo = stops[z], hi = math.min(stops[z + 1], upTo);
            if (hi <= lo) break;
            final c = zoneColor(lo + 0.01);
            canvas.drawRect(
              Rect.fromLTWH(row.left + lo * meterW, top,
                  (hi - lo) * meterW, rowH),
              Paint()..color = lit ? c : dimColor(c),
            );
          }
        }

        canvas.save();
        canvas.clipRRect(
            RRect.fromRectAndRadius(row, const Radius.circular(3)));
        zones(1.0, lit: false); // ember full-length track
        zones(level, lit: true); // lit portion
        // Peak line hangs past the bar tip.
        if (peak > 0.02) {
          canvas.drawRect(
            Rect.fromLTWH(
                row.left + (peak * meterW).clamp(0.0, meterW - 2),
                top,
                2,
                rowH),
            Paint()..color = theme.textPrimary.withValues(alpha: 0.9),
          );
        }
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(VisualizerPainter old) =>
      old.bands != bands ||
      old.time != time ||
      old.theme != theme ||
      old.style != style ||
      old.reactivity != reactivity ||
      old.vuSplit != vuSplit ||
      old.ledDiscrete != ledDiscrete;
}
