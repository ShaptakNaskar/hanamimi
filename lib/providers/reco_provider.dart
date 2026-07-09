import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/models/queue_mode.dart';
import '../library/models/track.dart';
import '../online/models/online_search_result.dart';
import '../online/music_provider.dart';
import '../online/saavn_provider.dart';
import '../online/youtube_provider.dart';
import '../reco/discover.dart';
import '../reco/feature_extractor.dart';
import '../reco/recommender.dart';
import '../reco/yt_session.dart';
import 'audio_provider.dart';
import 'home_provider.dart';
import 'library_provider.dart';
import 'online_settings_provider.dart';
import 'theme_provider.dart';
import 'yt_account_provider.dart';

/// One-shot load of everything the Tier 0 engine reads. Re-queried per
/// track start (playTick) so shelves and weights follow the listening
/// session; the queries are all small (id-keyed maps, no blobs besides
/// the ~120-byte feature vectors).
///
/// **Local-only.** Tier 0 (For you, song radio, smart shuffle) recommends
/// from your own library — online picks come source-pure from the
/// providers (Discover / online radio), so the on-device engine and the
/// local queue never get mixed with YouTube/JioSaavn rows. This is what
/// keeps "For you" playable offline and the queue from becoming a
/// hodgepodge of sources.
final recoDataProvider = FutureProvider<RecoData>((ref) async {
  ref.watch(playTickProvider);
  final repo = await ref.watch(libraryRepositoryProvider.future);
  final tracks = [
    for (final t in await repo.allTracks())
      if (t.isLocal) t,
  ];

  final coPlay = <int, Map<int, int>>{};
  for (final row in await repo.allCoPlays()) {
    final from = row['from_id'] as int;
    (coPlay[from] ??= {})[row['to_id'] as int] = row['count'] as int;
  }

  return RecoData(
    tracks: tracks,
    coPlay: coPlay,
    skips: await repo.skipCounts(),
    features: await repo.allTrackFeatures(trackFeaturesVersion),
  );
});

/// Source-pure continuation from [seed], excluding the seed itself:
/// a YouTube seed → YT radio, a JioSaavn seed → Saavn reco, a local seed
/// → the on-device station over your local library. Never cross-matches
/// sources, so a station stays within the world it started in.
Future<List<Track>> _continuationFor(WidgetRef ref, Track seed,
    {int limit = 24}) async {
  if (ref.read(onlineEnabledProvider) && seed.sourceId != null) {
    List<OnlineSearchResult> similar = const [];
    if (seed.source == TrackSource.saavn) {
      similar = await (musicProviderRegistry[TrackSource.saavn]
                  as SaavnProvider?)
              ?.similarSongs(seed.sourceId!) ??
          const [];
    } else if (seed.source == TrackSource.youtube) {
      similar = await (musicProviderRegistry[TrackSource.youtube]
                  as YouTubeProvider?)
              ?.relatedSongs(seed.sourceId!) ??
          const [];
    }
    if (similar.isNotEmpty) {
      final notifier = ref.read(libraryProvider.notifier);
      return [
        for (final r in similar.take(limit))
          await notifier.ensureOnlineTrack(r),
      ];
    }
  }
  // Local seed (or online off / providers dry): on-device station over
  // the local library.
  final data = await ref.read(recoDataProvider.future);
  return Recommender(data).station(seed, length: limit + 1).skip(1).toList();
}

/// Home "For you" shelf — on-device picks, airplane-mode safe.
final forYouProvider = FutureProvider<List<Track>>((ref) async {
  final data = await ref.watch(recoDataProvider.future);
  return Recommender(data).forYou();
});

/// Smart shuffle preference (M38c): shuffle weighted by taste instead
/// of uniform. Off by default — classic shuffle is the least surprising.
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
  final rec = Recommender(data);
  engine.shuffleWeight = rec.shuffleWeight;
});

/// Builds a source-pure station from [seed] and starts playing it
/// ("Start radio" / tapping a For-you card). The seed always plays
/// first; the continuation matches the seed's source.
Future<void> startRadio(WidgetRef ref, Track seed) async {
  // Play the seed immediately so the tap always does something, even
  // while the (possibly online) continuation is still resolving.
  final handler = ref.read(audioHandlerProvider);
  await handler.playTracks([seed], mode: QueueMode.sequential);
  final tail = await _continuationFor(ref, seed);
  final fresh = [
    for (final t in tail)
      if (t.id != seed.id) t,
  ];
  for (final t in fresh) {
    await handler.engine.addToQueue(t);
  }
}

/// Autoplay / radio continuation preference (M39): when the queue ends,
/// keep going with similar songs. On by default — it's the first place
/// the recommender is felt, and turning it off is one switch away.
class AutoplayNotifier extends Notifier<bool> {
  static const _key = 'autoplay_continuation';

  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(_key) ?? true;

  void toggle() {
    state = !state;
    ref.read(sharedPrefsProvider).setBool(_key, state);
  }
}

final autoplayProvider =
    NotifierProvider<AutoplayNotifier, bool>(AutoplayNotifier.new);

/// Pushes the autoplay fetcher into the engine. Source-affinity routing
/// (ARCHITECTURE-RECOMMENDATIONS.md §4): a Saavn seed continues from
/// Saavn's recommender, a YT seed from YT's radio, a local seed from
/// the on-device station — regional tracks never get cross-matched.
/// Online lanes respect the online master toggle. Watched from app.dart.
final autoplayPusherProvider = Provider<void>((ref) {
  final engine = ref.watch(audioHandlerProvider).engine;
  if (!ref.watch(autoplayProvider)) {
    engine.autoplayFetcher = null;
    return;
  }
  final online = ref.watch(onlineEnabledProvider);

  engine.autoplayFetcher = (last) async {
    if (online && last.sourceId != null) {
      List<OnlineSearchResult> similar = const [];
      if (last.source == TrackSource.saavn) {
        final saavn =
            musicProviderRegistry[TrackSource.saavn] as SaavnProvider?;
        similar = await saavn?.similarSongs(last.sourceId!) ?? const [];
      } else if (last.source == TrackSource.youtube) {
        final yt = musicProviderRegistry[TrackSource.youtube]
            as YouTubeProvider?;
        similar = await yt?.relatedSongs(last.sourceId!) ?? const [];
      }
      if (similar.isNotEmpty) {
        final notifier = ref.read(libraryProvider.notifier);
        return [
          for (final r in similar.take(10))
            await notifier.ensureOnlineTrack(r),
        ];
      }
      // Online seed but the provider came back dry — stop rather than
      // cross-match into local tracks (that's what made the queue a
      // hodgepodge of sources).
      return const [];
    }
    // Local seed: Tier 0 station continuation over the local library —
    // works in airplane mode, ships on both editions.
    final data = await ref.read(recoDataProvider.future);
    return Recommender(data).station(last, length: 11).skip(1).toList();
  };
});

// Discover lanes are memoized on their seed identity: recoData refreshes
// every track start, but the lanes should only refetch when the actual
// seeds (newest online plays / top anchor) change — not per song.
String? _lanesKey;
List<DiscoverLane> _lanesCache = const [];

/// Home "Discover" (Tier 1, + only): per-catalog lanes from anonymous
/// per-seed lookups. Empty when online is off — the shelf disappears
/// entirely, as the milestone requires.
final discoverLanesProvider = FutureProvider<List<DiscoverLane>>((ref) async {
  if (!ref.watch(onlineEnabledProvider)) {
    _lanesKey = null;
    _lanesCache = const [];
    return const [];
  }
  ref.watch(playTickProvider);
  // Discover needs the FULL play history (incl. online) to find the
  // newest YouTube/JioSaavn seed; the local-only recoData just supplies
  // the top local anchor for the bridge lane.
  final repo = await ref.watch(libraryRepositoryProvider.future);
  final history = await repo.allTracks();
  final localData = await ref.watch(recoDataProvider.future);
  final anchor = Recommender(localData).anchors(limit: 1).firstOrNull;
  final key = Discover.seedKey(history: history, localAnchor: anchor);
  if (key == _lanesKey) return _lanesCache;
  final lanes =
      await Discover().lanes(history: history, localAnchor: anchor);
  _lanesKey = key;
  _lanesCache = lanes;
  return lanes;
});

/// Materializes a Discover lane into real library rows and plays it
/// from [index] (ephemeral-until-touched, ARCHITECTURE-ONLINE.md §3.3).
Future<void> playDiscoverLane(
    WidgetRef ref, DiscoverLane lane, int index) async {
  final notifier = ref.read(libraryProvider.notifier);
  final tracks = [
    for (final item in lane.items) await notifier.ensureOnlineTrack(item),
  ];
  await ref
      .read(audioHandlerProvider)
      .playTracks(tracks, startIndex: index, mode: QueueMode.sequential);
}

/// Plays the signed-in YT Music Quick Picks (Tier 3) from [index].
/// Playback stays anonymous (yt-dlp) — the cookie only fetched the feed.
Future<void> playYtSongs(
    WidgetRef ref, List<OnlineSearchResult> songs, int index) async {
  final notifier = ref.read(libraryProvider.notifier);
  final tracks = [
    for (final r in songs) await notifier.ensureOnlineTrack(r),
  ];
  await ref
      .read(audioHandlerProvider)
      .playTracks(tracks, startIndex: index, mode: QueueMode.sequential);
}

/// Resolves a home-feed playlist / mix card to its tracks and plays it.
/// Returns false when the playlist came back empty.
Future<bool> playYtPlaylist(WidgetRef ref, YtPlaylistCard card) async {
  final account = ref.read(ytAccountProvider).value;
  if (account == null || !account.connected) return false;
  final items =
      await YtSession(cookie: account.cookie).playlistTracks(card.playlistId);
  if (items.isEmpty) return false;
  final notifier = ref.read(libraryProvider.notifier);
  final tracks = [
    for (final r in items) await notifier.ensureOnlineTrack(r),
  ];
  await ref
      .read(audioHandlerProvider)
      .playTracks(tracks, mode: QueueMode.sequential);
  return true;
}

/// One-time "want deeper recs?" Home card (Tier 2/3 doorway) —
/// dismissible forever, per the doc.
class DeepRecsCardDismissed extends Notifier<bool> {
  static const _key = 'deep_recs_card_dismissed';

  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(_key) ?? false;

  void dismiss() {
    state = true;
    ref.read(sharedPrefsProvider).setBool(_key, true);
  }
}

final deepRecsCardDismissedProvider =
    NotifierProvider<DeepRecsCardDismissed, bool>(DeepRecsCardDismissed.new);
