import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/track.dart';
import '../../providers/audio_provider.dart';
import '../../providers/mystery_date_provider.dart';
import '../../providers/night_mode_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/library/track_row.dart';

/// Up-next list; tap a row to jump straight to it. In Mystery Date
/// Mode (3.0 #1) everything past the current track is hidden behind a
/// "getting ready..." shimmer — no peeking, just trust.
void showQueueSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.7,
      child: _QueueSheetBody(),
    ),
  );
}

class _QueueSheetBody extends ConsumerWidget {
  const _QueueSheetBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final audio = ref.watch(audioStateProvider).value;
    final queue = audio?.queue ?? [];
    final currentId = audio?.currentTrack?.id;
    final mystery = ref.watch(mysteryDateProvider);

    // Reorder keys: a track can sit in the queue twice, so the id alone
    // isn't unique — number the repeats.
    final seen = <int, int>{};
    final keys = [
      for (final t in queue)
        ValueKey('q_${t.id}_${seen[t.id] = (seen[t.id] ?? 0) + 1}'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s4, Space.s4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text((mystery ? 'Mystery date' : 'Up next')
                        .whisper(ref.watch(nightModeActiveProvider)),
                    style: TextStyle(
                        fontFamily: 'Nunito',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary)),
              ),
              IconButton(
                tooltip: mystery
                    ? 'Show the queue again'
                    : 'Mystery date — hide what plays next',
                icon: Icon(
                  mystery
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 20,
                  color: mystery ? theme.primary : theme.textMuted,
                ),
                onPressed: () =>
                    ref.read(mysteryDateProvider.notifier).toggle(),
              ),
            ],
          ),
          const SizedBox(height: Space.s3),
          Expanded(
            child: queue.isEmpty
                ? Center(
                    child:
                        Text('Queue is empty', style: AppText.caption(theme)))
                : mystery
                    ? _MysteryQueue(
                        theme: theme,
                        current: [
                          for (final t in queue)
                            if (t.id == currentId) t,
                        ].firstOrNull,
                        hiddenCount: queue.length,
                      )
                    // Long-press a row to drag it to a new spot.
                    : ReorderableListView.builder(
                        onReorder: (oldIndex, newIndex) {
                          if (newIndex > oldIndex) newIndex--;
                          ref
                              .read(audioHandlerProvider)
                              .engine
                              .moveInQueue(oldIndex, newIndex);
                        },
                        proxyDecorator: (child, _, __) => Material(
                            color: Colors.transparent,
                            elevation: 4,
                            borderRadius: BorderRadius.circular(Radii.md),
                            child: child),
                        itemCount: queue.length,
                        itemExtent: Sizes.trackRowHeight,
                        itemBuilder: (context, i) => KeyedSubtree(
                          key: keys[i],
                          child: TrackRow(
                            track: queue[i],
                            theme: theme,
                            isPlaying: queue[i].id == currentId,
                            onTap: () {
                              ref
                                  .read(audioHandlerProvider)
                                  .engine
                                  .jumpToQueueIndex(i);
                              Navigator.pop(context);
                            },
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

/// The current track (that much you're allowed to know) above a shimmer
/// placeholder standing in for everything the mode refuses to reveal.
class _MysteryQueue extends StatelessWidget {
  const _MysteryQueue({
    required this.theme,
    required this.current,
    required this.hiddenCount,
  });

  final HanamimiTheme theme;
  final Track? current;
  final int hiddenCount;

  @override
  Widget build(BuildContext context) {
    final now = current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (now != null)
          TrackRow(
            track: now,
            theme: theme,
            isPlaying: true,
            onTap: () {},
          ),
        const SizedBox(height: Space.s4),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Shimmer(color: theme.primary),
                const SizedBox(height: Space.s4),
                Text('getting ready...',
                    style: AppText.caption(theme)
                        .copyWith(fontStyle: FontStyle.italic)),
                const SizedBox(height: Space.s1),
                Text('no peeking 🌹', style: AppText.caption(theme)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Three soft pulsing bars — a queue-shaped ghost. One repeating
/// controller; disposed with the sheet, so no idle-CPU concern.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.color});

  final Color color;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Container(
                  width: 180 - i * 24.0,
                  height: 10,
                  decoration: BoxDecoration(
                    // Each bar breathes offset from its neighbor.
                    color: widget.color.withValues(
                        alpha: 0.10 +
                            0.14 *
                                (1 -
                                    ((t + i * 0.33) % 1.0 - 0.5).abs() *
                                        2)),
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
