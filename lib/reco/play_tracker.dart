import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/models/track.dart';
import '../providers/audio_provider.dart';
import '../providers/library_provider.dart';

/// How early an abandoned track counts as a skip (a negative vote)
/// rather than a listen. Matches ARCHITECTURE-RECOMMENDATIONS.md §3.
const skipThreshold = Duration(seconds: 20);

/// M38a behavioural logging: turns the play stream into recommendation
/// signals. Every track transition is either a co-play ("listened to A,
/// then started B" → co_play matrix, the Markov source for radio and
/// up-next) or a skip (abandoned inside [skipThreshold] → skip_count).
///
/// Watches the furthest position reached rather than wall-clock time so
/// pauses don't inflate a listen and seeking backwards can't erase one.
/// Purely local — this never touches the network.
final playSequenceTrackerProvider = Provider<void>((ref) {
  final engine = ref.watch(audioHandlerProvider).engine;

  Track? current;
  var maxPosition = Duration.zero;

  final posSub = engine.positionStream.listen((pos) {
    if (pos > maxPosition) maxPosition = pos;
  });

  final startSub = engine.trackStarted.stream.listen((track) async {
    final prev = current;
    final listened = maxPosition;
    current = track;
    maxPosition = Duration.zero;
    // Same track restarting (repeat, manual replay) is not a transition.
    if (prev == null || prev.id == track.id) return;
    final repo = await ref.read(libraryRepositoryProvider.future);
    if (listened < skipThreshold) {
      await repo.recordSkip(prev.id);
    } else {
      await repo.recordCoPlay(prev.id, track.id);
    }
  });

  ref.onDispose(() {
    posSub.cancel();
    startSub.cancel();
  });
});
