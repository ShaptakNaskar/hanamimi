import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/audio_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/library/track_row.dart';

/// Up-next list; tap a row to jump straight to it.
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
          Text('Up next',
              style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: theme.textPrimary)),
          const SizedBox(height: Space.s3),
          Expanded(
            child: queue.isEmpty
                ? Center(
                    child:
                        Text('Queue is empty', style: AppText.caption(theme)))
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
