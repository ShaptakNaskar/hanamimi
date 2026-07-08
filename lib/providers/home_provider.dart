import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/models/track.dart';
import 'audio_provider.dart';
import 'library_provider.dart';

/// Bumped on every track start so the Home shelves re-query — the
/// library list itself doesn't refresh on play, so "Jump back in"
/// would otherwise lag a whole session behind.
class PlayTick extends Notifier<int> {
  @override
  int build() {
    final engine = ref.watch(audioHandlerProvider).engine;
    final sub = engine.trackStarted.stream.listen((_) => state++);
    ref.onDispose(sub.cancel);
    return 0;
  }
}

final playTickProvider = NotifierProvider<PlayTick, int>(PlayTick.new);

/// Home "Jump back in": most recent listens, newest first.
final recentTracksProvider = FutureProvider<List<Track>>((ref) async {
  ref.watch(playTickProvider);
  final repo = await ref.watch(libraryRepositoryProvider.future);
  return repo.recentlyPlayed();
});
