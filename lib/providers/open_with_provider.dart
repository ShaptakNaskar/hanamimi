import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/models/track.dart';
import '../library/open_with_channel.dart';
import 'audio_provider.dart';
import 'library_provider.dart';

/// Plays audio files opened from other apps ("open with Hanamimi").
/// Watched once from the app root; handles both the launch intent and
/// intents arriving while the app is alive.
final openWithProvider = Provider<void>((ref) {
  Future<void> play(Map payload) async {
    final path = payload['path'] as String?;
    final uri = payload['uri'] as String?;
    final source = path ?? uri;
    if (source == null) return;

    final handler = ref.read(audioHandlerProvider);

    // A library track for this file plays as itself (art, likes,
    // play counts all work).
    List<Track> library = const [];
    try {
      library = await ref.read(libraryProvider.future);
    } catch (_) {
      // Library unavailable (e.g. permission denied) — transient track.
    }
    final match = path == null
        ? null
        : library.where((t) => t.filePath == path).firstOrNull;
    if (match != null) {
      await handler.playTracks([match]);
      return;
    }

    final name =
        (payload['title'] as String?) ?? source.split('/').last;
    final dot = name.lastIndexOf('.');
    final title = dot > 0 ? name.substring(0, dot) : name;
    await handler.playTracks([
      Track(
        id: -1,
        mediaId: -1,
        title: title,
        artist: 'Unknown artist',
        album: 'Opened file',
        albumId: -1,
        filePath: source,
        duration: Duration.zero, // real duration comes from the player
      ),
    ]);
  }

  OpenWithChannel.setListener(play);
  // The intent that launched the app, if it was an "open with".
  Future(() async {
    final pending = await OpenWithChannel.getPendingMedia();
    if (pending != null) await play(pending);
  });
});
