import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../audio/models/queue_mode.dart';
import '../../../providers/audio_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../theme/theme_tokens.dart';

/// Main control row + secondary row (shuffle / repeat / sleep / queue)
/// per DESIGN.md §9.6.
class PlaybackControls extends ConsumerStatefulWidget {
  const PlaybackControls({super.key, this.onSleepTimer, this.onQueue});

  final VoidCallback? onSleepTimer;
  final VoidCallback? onQueue;

  @override
  ConsumerState<PlaybackControls> createState() => _PlaybackControlsState();
}

class _PlaybackControlsState extends ConsumerState<PlaybackControls>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _seekRelative(int seconds) async {
    final handler = ref.read(audioHandlerProvider);
    final pos = handler.engine.state.duration == Duration.zero
        ? Duration.zero
        : await handler.engine.positionStream.first;
    var target = pos + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    await handler.seek(target);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final audio = ref.watch(audioStateProvider).value;
    final handler = ref.read(audioHandlerProvider);
    final isPlaying = audio?.isPlaying ?? false;
    final mode = audio?.queueMode ?? QueueMode.sequential;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _IconOnly(
              icon: Icons.replay_10,
              color: theme.textMuted,
              onTap: () => _seekRelative(-10),
            ),
            const SizedBox(width: Space.s4),
            _CircleButton(
              size: Sizes.secondaryButton,
              background: theme.surface,
              borderColor: theme.divider,
              onTap: handler.skipToPrevious,
              child: Icon(Icons.skip_previous_outlined,
                  size: 24, color: theme.textPrimary),
            ),
            const SizedBox(width: Space.s6),
            ScaleTransition(
              scale: TweenSequence([
                TweenSequenceItem(
                    tween: Tween(begin: 1.0, end: 1.08), weight: 1),
                TweenSequenceItem(
                    tween: Tween(begin: 1.08, end: 1.0), weight: 1),
              ]).animate(_pulse),
              child: _CircleButton(
                size: Sizes.playButton,
                background: theme.primary,
                onTap: () {
                  _pulse.forward(from: 0);
                  isPlaying ? handler.pause() : handler.play();
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.8, end: 1.0).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    key: ValueKey(isPlaying),
                    size: 28,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.s6),
            _CircleButton(
              size: Sizes.secondaryButton,
              background: theme.surface,
              borderColor: theme.divider,
              onTap: handler.skipToNext,
              child: Icon(Icons.skip_next_outlined,
                  size: 24, color: theme.textPrimary),
            ),
            const SizedBox(width: Space.s4),
            _IconOnly(
              icon: Icons.forward_10,
              color: theme.textMuted,
              onTap: () => _seekRelative(10),
            ),
          ],
        ),
        const SizedBox(height: Space.s6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _IconOnly(
              icon: Icons.shuffle,
              size: 20,
              color: mode == QueueMode.shuffle
                  ? theme.primary
                  : theme.textMuted,
              onTap: () => handler.engine.setMode(
                mode == QueueMode.shuffle
                    ? QueueMode.sequential
                    : QueueMode.shuffle,
              ),
            ),
            _IconOnly(
              icon: mode == QueueMode.repeatOne
                  ? Icons.repeat_one
                  : Icons.repeat,
              size: 20,
              color: mode == QueueMode.repeatAll ||
                      mode == QueueMode.repeatOne
                  ? theme.primary
                  : theme.textMuted,
              onTap: () => handler.engine.setMode(switch (mode) {
                QueueMode.sequential || QueueMode.shuffle =>
                  QueueMode.repeatAll,
                QueueMode.repeatAll => QueueMode.repeatOne,
                QueueMode.repeatOne => QueueMode.sequential,
              }),
            ),
            _IconOnly(
              icon: Icons.nightlight_outlined,
              size: 20,
              color: theme.textMuted,
              onTap: widget.onSleepTimer ?? () {},
            ),
            _IconOnly(
              icon: Icons.queue_music,
              size: 20,
              color: theme.textMuted,
              onTap: widget.onQueue ?? () {},
            ),
          ],
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.size,
    required this.background,
    this.borderColor,
    required this.child,
    required this.onTap,
  });

  final double size;
  final Color background;
  final Color? borderColor;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: borderColor == null
              ? null
              : Border.all(color: borderColor!, width: 0.5),
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _IconOnly extends StatelessWidget {
  const _IconOnly({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 20,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: Sizes.minTouchTarget / 2,
      child: SizedBox(
        width: Sizes.minTouchTarget,
        height: Sizes.minTouchTarget,
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}
