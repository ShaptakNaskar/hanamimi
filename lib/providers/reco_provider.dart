import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/models/queue_mode.dart';
import '../library/models/track.dart';
import '../reco/feature_extractor.dart';
import '../reco/recommender.dart';
import 'audio_provider.dart';
import 'home_provider.dart';
import 'library_provider.dart';
import 'theme_provider.dart';

/// One-shot load of everything the Tier 0 engine reads. Re-queried per
/// track start (playTick) so shelves and weights follow the listening
/// session; the queries are all small (id-keyed maps, no blobs besides
/// the ~120-byte feature vectors). Local-only — no network.
final recoDataProvider = FutureProvider<RecoData>((ref) async {
  ref.watch(playTickProvider);
  final repo = await ref.watch(libraryRepositoryProvider.future);
  final tracks = await repo.allTracks();

  final coPlay = <int, Map<int, int>>{};
  for (final row in await repo.allCoPlays()) {
    final from = row['from_id'] as int;
    (coPlay[from] ??= {})[row['to_id'] as int] = row['count'] as int;
  }

  // 3.0 #5: what this hour-of-day's listening looks like, ±1h so bucket
  // edges don't cliff (23:59 still counts the midnight bucket).
  final hour = DateTime.now().hour;
  final hourWindow = {(hour + 23) % 24, hour, (hour + 1) % 24};

  return RecoData(
    tracks: tracks,
    coPlay: coPlay,
    skips: await repo.skipCounts(),
    features: await repo.allTrackFeatures(trackFeaturesVersion),
    hourSeconds: await repo.identitySecondsForHours(hourWindow),
  );
});

/// Home "For you" shelf — on-device picks, airplane-mode safe.
final forYouProvider = FutureProvider<List<Track>>((ref) async {
  final data = await ref.watch(recoDataProvider.future);
  return Recommender(data).forYou();
});

/// Smart shuffle preference: shuffle weighted by taste instead of
/// uniform. Off by default — classic shuffle is the least surprising.
class SmartShuffleNotifier extends Notifier<bool> {
  static const _key = 'smart_shuffle';

  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(_key) ?? false;

  void toggle() {
    state = !state;
    ref.read(sharedPrefsProvider).setBool(_key, state);
  }
}

final smartShuffleProvider =
    NotifierProvider<SmartShuffleNotifier, bool>(SmartShuffleNotifier.new);

/// Pushes the smart-shuffle weight function into the engine (same
/// pattern as crossfadeProvider). Watched from app.dart.
final smartShufflePusherProvider = Provider<void>((ref) {
  final engine = ref.watch(audioHandlerProvider).engine;
  final enabled = ref.watch(smartShuffleProvider);
  if (!enabled) {
    engine.shuffleWeight = null;
    return;
  }
  final data = ref.watch(recoDataProvider).value;
  if (data == null) return; // keep the previous weigher until loaded
  engine.shuffleWeight = Recommender(data).shuffleWeight;
});

/// Builds a station from [seed] and starts playing it ("Start radio").
Future<void> startRadio(WidgetRef ref, Track seed) async {
  final data = await ref.read(recoDataProvider.future);
  final queue = Recommender(data).station(seed);
  await ref
      .read(audioHandlerProvider)
      .playTracks(queue, mode: QueueMode.sequential);
}
