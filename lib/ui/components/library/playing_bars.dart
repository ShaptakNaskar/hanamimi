import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/audio_provider.dart';

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

class _PlayingBarsState extends ConsumerState<PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing =
        ref.watch(audioStateProvider).value?.isPlaying ?? false;
    if (playing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!playing && _controller.isAnimating) {
      _controller.stop();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * math.pi;
        return SizedBox(
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
        );
      },
    );
  }
}
