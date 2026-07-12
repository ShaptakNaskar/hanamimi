import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/models/track.dart';
import '../providers/audio_provider.dart';
import '../providers/library_provider.dart';
import '../reco/play_tracker.dart' show skipThreshold;
import '../utils/track_identity.dart';

/// Writes the append-only listening log (IDEAS-APPROVED.md #7).
///
/// A history row opens the moment a track starts and its seconds are
/// bumped while playback runs, so a crash/kill loses at most one bump
/// interval — not the whole play. Rows abandoned inside [skipThreshold]
/// are deleted on the next transition: the log records listens, and a
/// sub-20s bail is the recommender's definition of "not a listen".
///
/// Seconds are derived from the furthest playback position (same rule
/// as play_tracker) so pauses can't inflate a row and rewinds can't
/// shrink one.
final listenHistoryTrackerProvider = Provider<void>((ref) {
  final engine = ref.watch(audioHandlerProvider).engine;

  int? openRowId;
  Track? current;
  var maxPosition = Duration.zero;
  var lastWrittenSeconds = -1;

  Future<void> flush() async {
    final rowId = openRowId;
    if (rowId == null) return;
    final seconds = maxPosition.inSeconds;
    if (seconds == lastWrittenSeconds) return;
    lastWrittenSeconds = seconds;
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.updateListenSeconds(rowId, seconds);
  }

  final posSub = engine.positionStream.listen((pos) {
    if (pos > maxPosition) maxPosition = pos;
  });

  // Periodic crash-safety bump. 10s keeps writes negligible (one tiny
  // UPDATE) while capping data loss on a hard kill.
  final bumpTimer = Timer.periodic(const Duration(seconds: 10), (_) {
    final playing =
        ref.read(audioStateProvider).value?.isPlaying ?? false;
    if (playing) flush();
  });

  final startSub = engine.trackStarted.stream.listen((track) async {
    final prevRow = openRowId;
    final prev = current;
    final listened = maxPosition;

    // Same track restarting (repeat, manual replay) keeps its row —
    // mirroring play_tracker's "not a transition" rule.
    if (prev != null && prev.id == track.id) return;

    current = track;
    maxPosition = Duration.zero;
    openRowId = null;
    lastWrittenSeconds = -1;

    final repo = await ref.read(libraryRepositoryProvider.future);

    // Settle the outgoing row: final seconds, or deletion for a skip.
    if (prevRow != null) {
      if (listened < skipThreshold) {
        await repo.deleteListen(prevRow);
      } else {
        await repo.updateListenSeconds(prevRow, listened.inSeconds);
      }
    }

    openRowId = await repo.insertListen(
      identityKey: identityKey(
          title: track.title,
          artist: track.artist,
          duration: track.duration),
      title: track.title,
      artist: track.artist,
      album: track.album,
      playedAt: DateTime.now(),
      durationMs: track.duration.inMilliseconds,
      lastPath: track.filePath,
    );
  });

  ref.onDispose(() {
    bumpTimer.cancel();
    posSub.cancel();
    startSub.cancel();
    flush();
  });
});
