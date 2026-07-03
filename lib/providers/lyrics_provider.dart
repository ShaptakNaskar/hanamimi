import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lyrics/lyrics_service.dart';
import '../lyrics/models/lyric_line.dart';
import 'audio_provider.dart';
import 'library_provider.dart';
import 'theme_provider.dart';

/// Lyrics for a library track id. Honors the user's per-track source
/// choice (from the sheet's source picker); otherwise auto-picks the
/// best quality (word > line > plain).
final lyricsProvider = FutureProvider.family<Lyrics?, int>((ref, trackId) async {
  final repo = await ref.watch(libraryRepositoryProvider.future);
  final track = (await repo.allTracks())
      .where((t) => t.id == trackId)
      .firstOrNull ??
      ref.read(audioStateProvider).value?.currentTrack;
  if (track == null || track.id != trackId) return null;

  final service = LyricsService(repo);

  final overrideName = ref
      .watch(sharedPrefsProvider)
      .getString('lyrics_source_$trackId');
  if (overrideName != null) {
    final source = LyricsSource.values
        .where((s) => s.name == overrideName)
        .firstOrNull;
    if (source != null) {
      final forced = await service.fetchFromSource(track, source);
      if (forced != null) return forced;
      // Source dried up (e.g. offline now) — fall through to auto.
    }
  }
  return service.fetchFor(track);
});
