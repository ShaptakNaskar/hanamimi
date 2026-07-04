import '../library/models/track.dart';
import 'models/online_search_result.dart';
import 'models/resolved_stream.dart';

/// One online catalog (YouTube, JioSaavn, …). Implementations follow
/// the MusixmatchProvider precedent: best-effort, null on failure —
/// a broken provider must never take the rest of the app down.
abstract interface class MusicProvider {
  TrackSource get source;

  Future<List<OnlineSearchResult>> search(String query);

  Future<ResolvedStream?> resolveStream(String sourceId, StreamQuality quality);
}

/// Registry consumed by [StreamResolver] and the search UI. Providers
/// register themselves at startup (main.dart); adding one later touches
/// nothing outside lib/online/.
final musicProviderRegistry = <TrackSource, MusicProvider>{};
