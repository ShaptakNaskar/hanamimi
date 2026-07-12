import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/models/listen_event.dart';
import '../library/models/track.dart';
import '../providers/library_provider.dart';
import '../utils/track_identity.dart';

/// How a history row was (or wasn't) turned back into something playable.
enum HistoryResolution { byPath, byIdentity, gone }

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
/// 3. Gone — the screen renders the row view-only.
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
    if ((t.duration.inSeconds - event.duration.inSeconds).abs() > 10) {
      continue;
    }
    if (normalizeTitle(t.title) == wantTitle &&
        normalizeArtist(t.artist) == wantArtist) {
      return ResolvedHistoryPlay(HistoryResolution.byIdentity, t);
    }
  }

  return const ResolvedHistoryPlay(HistoryResolution.gone);
}
