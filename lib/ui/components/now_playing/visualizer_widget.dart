import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/audio_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../providers/visualizer_provider.dart';
import '../../../providers/window_activity_provider.dart';
import '../../../theme/hanamimi_theme.dart';
import '../../../visualizer/visualizer_painter.dart';

class VisualizerWidget extends ConsumerStatefulWidget {
  const VisualizerWidget({super.key, this.height = 60});

  final double height;

  @override
  ConsumerState<VisualizerWidget> createState() => _VisualizerWidgetState();
}

class _VisualizerWidgetState extends ConsumerState<VisualizerWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _time = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    // elapsed restarts at zero every Ticker.start(), so advance _time
    // by deltas — motion stays continuous across stop/start cycles.
    _ticker = createTicker((elapsed) {
      final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
      _last = elapsed;
      setState(() => _time += dt);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final bands = ref.watch(visualizerBandsProvider).value ??
        List.filled(12, 0.05);

    // The clock ticker exists for styles whose motion is time-driven
    // (raindrops fall, radial rotates) — bars/wave redraw purely from
    // band emissions. Run it only while the visualizer is alive: an
    // always-on ticker forces an engine frame (and an NVIDIA GL swap
    // busy-wait) every vsync forever, even paused with the panel idle —
    // the bulk of the desktop constant-CPU report. When paused, the
    // band stream itself settles and rebuilds stop.
    final style = theme.visualizerStyle;
    final needsClock = style == VisualizerStyle.raindrops ||
        style == VisualizerStyle.radial;
    final playing =
        ref.watch(audioStateProvider).value?.isPlaying ?? false;
    final visible = ref.watch(windowVisibleProvider);
    final animate =
        visible && needsClock && (playing || bands.any((b) => b > 0.005));
    if (animate && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!animate && _ticker.isActive) {
      _ticker.stop();
    }

    return RepaintBoundary(
      child: CustomPaint(
        size: Size(double.infinity, widget.height),
        painter: VisualizerPainter(
          bands: bands,
          theme: theme,
          time: _time,
        ),
      ),
    );
  }
}
