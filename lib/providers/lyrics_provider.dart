import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lyrics/lyrics_service.dart';
import '../lyrics/models/lyric_line.dart';
import 'audio_provider.dart';
import 'library_provider.dart';

/// Lyrics for a library track id (ids are stable, so the family caches
/// cleanly across rebuilds).
final lyricsProvider = FutureProvider.family<Lyrics?, int>((ref, trackId) async {
  final repo = await ref.watch(libraryRepositoryProvider.future);
  final track = (await repo.allTracks())
      .where((t) => t.id == trackId)
      .firstOrNull ??
      ref.read(audioStateProvider).value?.currentTrack;
  if (track == null || track.id != trackId) return null;
  return LyricsService(repo).fetchFor(track);
});
