import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/audio_provider.dart';
import '../../../providers/window_activity_provider.dart';
import '../../../utils/app_frame_ticker.dart';

/// Three softly rising-and-falling bars shown on the row of the
/// currently playing track (DESIGN.md §9.1). Watches playback itself:
/// paused music freezes the bars (dancing bars on a paused track read
/// wrong — user-reported) and stops their vsync ticker.
class PlayingBars extends ConsumerStatefulWidget {
  const PlayingBars({super.key, required this.color, this.size = 20});

  final Color color;
  final double size;

  @override
  ConsumerState<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends ConsumerState<PlayingBars> {
  late final AppFrameTicker _ticker;
  Duration _last = Duration.zero;
  double _time = 0;

  @override
  void initState() {
    super.initState();
    _ticker = AppFrameTicker((elapsed) {
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
    final playing = (ref.watch(audioStateProvider).value?.isPlaying ??
            false) &&
        // Minimized: no point dancing at 60 fps for a hidden window.
        ref.watch(windowVisibleProvider);
    if (playing && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!playing && _ticker.isActive) {
      _ticker.stop();
    }

    final t = _time * 2 * math.pi / 1.2;
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: widget.size * 0.18,
                height: widget.size *
                    (0.35 + 0.55 * (0.5 + 0.5 * math.sin(t + i * 2.1))),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
