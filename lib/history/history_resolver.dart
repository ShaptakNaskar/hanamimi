import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/models/listen_event.dart';
import '../library/models/track.dart';
import '../online/models/online_search_result.dart';
import '../providers/library_provider.dart';
import '../utils/track_identity.dart';

/// How a history row was (or wasn't) turned back into something playable.
enum HistoryResolution { byPath, byIdentity, onlineStream, gone }

class ResolvedHistoryPlay {
  const ResolvedHistoryPlay(this.resolution, [this.track]);
  final HistoryResolution resolution;
  final Track? track;
}

/// The tap-to-play fallback chain (IDEAS-APPROVED.md #7): history rows
/// are snapshots, so playback is best-effort re-resolution against the
/// *current* library — never a stale foreign key.
///
/// 1. The path it played from still exists → that library row.
/// 2. Identity-key search over the library (± duration tolerance) —
///    catches "I reorganized my Music folder".
/// 3. Online snapshot (yt/saavn id) → re-ensure the online row and
///    stream it: history outlives the file but can still be heard.
/// 4. Gone — the screen renders the row view-only.
Future<ResolvedHistoryPlay> resolveHistoryPlay(
    WidgetRef ref, ListenEvent event) async {
  final library = await ref.read(libraryProvider.future);

  // 1. Same file, still on disk, still in the library.
  final path = event.lastPath;
  if (path != null && File(path).existsSync()) {
    for (final t in library) {
      if (t.filePath == path) {
        return ResolvedHistoryPlay(HistoryResolution.byPath, t);
      }
    }
  }

  // 2. Identity match: normalized title+artist, duration within ±10s
  // (raw seconds rather than bucket equality — buckets have edges).
  final wantTitle = normalizeTitle(event.title);
  final wantArtist = normalizeArtist(event.artist);
  for (final t in library) {
    if (t.filePath == null) continue; // playable-now candidates only
    if ((t.duration.inSeconds - event.duration.inSeconds).abs() > 10) {
      continue;
    }
    if (normalizeTitle(t.title) == wantTitle &&
        normalizeArtist(t.artist) == wantArtist) {
      return ResolvedHistoryPlay(HistoryResolution.byIdentity, t);
    }
  }

  // 3. Online identity survives file loss entirely.
  final sourceId = event.sourceId;
  if (event.source != TrackSource.local && sourceId != null) {
    final track = await ref
        .read(libraryProvider.notifier)
        .ensureOnlineTrack(OnlineSearchResult(
          source: event.source,
          sourceId: sourceId,
          title: event.title,
          artist: event.artist,
          album: event.album,
          duration: event.duration,
        ));
    return ResolvedHistoryPlay(HistoryResolution.onlineStream, track);
  }

  return const ResolvedHistoryPlay(HistoryResolution.gone);
}
