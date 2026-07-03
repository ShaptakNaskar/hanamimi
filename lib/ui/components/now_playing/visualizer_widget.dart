import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/theme_provider.dart';
import '../../../providers/visualizer_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      setState(() => _time = elapsed.inMicroseconds / 1e6);
    })
      ..start();
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
