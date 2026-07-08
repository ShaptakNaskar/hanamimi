import '../library/models/track.dart';
import '../online/models/online_search_result.dart';
import '../online/music_provider.dart';
import '../online/saavn_provider.dart';
import '../online/youtube_provider.dart';

/// One Discover shelf lane (ARCHITECTURE-RECOMMENDATIONS.md §4, Tier 1).
/// Lanes are per-catalog by design — a Saavn seed only ever asks Saavn,
/// a YT seed only YT. Cross-catalog matching is where regional metadata
/// falls apart, so candidates are never merged into one pool.
class DiscoverLane {
  const DiscoverLane({
    required this.title,
    required this.source,
    required this.items,
  });

  final String title;
  final TrackSource source;
  final List<OnlineSearchResult> items;
}

/// Tier 1 anonymous discovery. All lookups are per-seed and carry no
/// account or cookie state — the same exposure as searching/streaming,
/// which an online-enabled user already accepts. Seeds are chosen
/// locally (the on-device taste model's job); the providers only ever
/// see isolated track ids.
class Discover {
  Discover({YouTubeProvider? youtube, SaavnProvider? saavn})
      : _youtube = youtube ??
            musicProviderRegistry[TrackSource.youtube] as YouTubeProvider?,
        _saavn = saavn ??
            musicProviderRegistry[TrackSource.saavn] as SaavnProvider?;

  final YouTubeProvider? _youtube;
  final SaavnProvider? _saavn;

  /// Identity of the seeds [lanes] would pick — callers memoize on this
  /// so lanes only refetch when a seed actually changes, not per play.
  static String seedKey({required List<Track> history, Track? localAnchor}) {
    String? newest(TrackSource source) {
      Track? best;
      for (final t in history) {
        if (t.source != source ||
            t.sourceId == null ||
            t.lastPlayed == null) {
          continue;
        }
        if (best == null || t.lastPlayed!.isAfter(best.lastPlayed!)) {
          best = t;
        }
      }
      return best?.sourceId;
    }

    return '${newest(TrackSource.saavn)}|${newest(TrackSource.youtube)}'
        '|${localAnchor?.id}';
  }

  /// Builds the Home Discover lanes from listening history.
  ///
  /// Routing (§4): the freshest *played* seed per online catalog gets a
  /// lane from its own catalog. With no online history yet, the top
  /// local anchor bridges into YT via a metadata search — one anonymous
  /// query, so a local-only listener still gets a Discover shelf the
  /// moment online is enabled.
  Future<List<DiscoverLane>> lanes({
    required List<Track> history,
    Track? localAnchor,
    int itemsPerLane = 12,
  }) async {
    Track? newestOf(TrackSource source) {
      Track? best;
      for (final t in history) {
        if (t.source != source || t.sourceId == null) continue;
        if (t.lastPlayed == null) continue;
        if (best == null || t.lastPlayed!.isAfter(best.lastPlayed!)) {
          best = t;
        }
      }
      return best;
    }

    final futures = <Future<DiscoverLane?>>[];

    final saavnSeed = newestOf(TrackSource.saavn);
    final saavn = _saavn;
    if (saavnSeed != null && saavn != null) {
      futures.add(() async {
        final items = await saavn.similarSongs(saavnSeed.sourceId!);
        return items.isEmpty
            ? null
            : DiscoverLane(
                title: 'MORE LIKE ${saavnSeed.title.toUpperCase()}',
                source: TrackSource.saavn,
                items: items.take(itemsPerLane).toList(),
              );
      }());
    }

    final ytSeed = newestOf(TrackSource.youtube);
    final youtube = _youtube;
    if (youtube != null) {
      if (ytSeed != null) {
        futures.add(() async {
          final items = await youtube.relatedSongs(ytSeed.sourceId!);
          return items.isEmpty
              ? null
              : DiscoverLane(
                  title: 'MORE LIKE ${ytSeed.title.toUpperCase()}',
                  source: TrackSource.youtube,
                  items: items.take(itemsPerLane).toList(),
                );
        }());
      } else if (localAnchor != null) {
        // Local-only listener: bridge the top local anchor into YT by
        // metadata (one anonymous search + one radio lookup).
        futures.add(() async {
          final hits = await youtube
              .searchMusic('${localAnchor.title} ${localAnchor.artist}');
          if (hits.isEmpty) return null;
          final items = await youtube.relatedSongs(hits.first.sourceId);
          return items.isEmpty
              ? null
              : DiscoverLane(
                  title: 'DISCOVER',
                  source: TrackSource.youtube,
                  items: items.take(itemsPerLane).toList(),
                );
        }());
      }
    }

    final lanes = await Future.wait(futures);
    return [
      for (final lane in lanes)
        if (lane != null) lane,
    ];
  }
}
