import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/models/track.dart';
import '../online/models/online_search_result.dart';
import '../online/music_provider.dart';

/// Search scopes for the library search pill: Library first, then one
/// per registered provider (M25: YouTube; M26 adds JioSaavn).
const onlineSourceLabels = {
  TrackSource.youtube: 'YouTube',
  TrackSource.saavn: 'JioSaavn',
};

List<TrackSource> get registeredOnlineSources => [
      for (final source in onlineSourceLabels.keys)
        if (musicProviderRegistry.containsKey(source)) source,
    ];

/// One provider search, cached per (source, query) for the session —
/// flicking between scopes doesn't refetch. The UI debounces input
/// (400 ms) before touching this.
final onlineSearchProvider = FutureProvider.autoDispose
    .family<List<OnlineSearchResult>, ({TrackSource source, String query})>(
        (ref, args) async {
  final provider = musicProviderRegistry[args.source];
  if (provider == null || args.query.trim().length < 2) return const [];
  // Keep results alive while the search session lasts.
  ref.keepAlive();
  return provider.search(args.query.trim());
});
