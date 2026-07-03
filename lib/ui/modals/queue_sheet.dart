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
                : ListView.builder(
                    itemCount: queue.length,
                    itemExtent: Sizes.trackRowHeight,
                    itemBuilder: (context, i) => TrackRow(
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
        ],
      ),
    );
  }
}
