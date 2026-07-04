import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/models/audio_state.dart';
import '../audio/models/playback_session.dart';
import 'audio_provider.dart';
import 'theme_provider.dart';

const _sessionKey = 'playback_session';

/// The session saved by a previous run, read once at startup so the
/// shell can offer to resume it. Null when there's nothing to resume.
final savedSessionProvider = Provider<PlaybackSession?>((ref) {
  final raw = ref.watch(sharedPrefsProvider).getString(_sessionKey);
  return PlaybackSession.decode(raw);
});

/// Forgets the saved session (user declined the resume prompt).
void clearSavedSession(WidgetRef ref) {
  ref.read(sharedPrefsProvider).remove(_sessionKey);
}

/// Persists "what's playing" as it moves, so it can be resumed next
/// launch. Watched once at the app root. Writes on every track/status
/// change and at most once every 5 s while a position ticks. Never
/// writes an empty snapshot, so a saved session survives the cold start
/// until the user resumes or dismisses it.
final sessionPersistenceProvider = Provider<void>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  final engine = ref.read(audioHandlerProvider).engine;

  var lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  int? lastTrackId;
  PlaybackStatus? lastStatus;

  void save() {
    final snap = engine.snapshotSession();
    if (snap == null) return;
    prefs.setString(_sessionKey, snap.encode());
    lastSave = DateTime.now();
  }

  final subs = <StreamSubscription<dynamic>>[
    engine.stateStream.listen((s) {
      // Save on track change and on play/pause transitions (a pause must
      // capture its exact position immediately, not up to 5 s later).
      if (s.currentTrack?.id != lastTrackId || s.status != lastStatus) {
        lastTrackId = s.currentTrack?.id;
        lastStatus = s.status;
        save();
      }
    }),
    engine.positionStream.listen((_) {
      if (DateTime.now().difference(lastSave) >= const Duration(seconds: 5)) {
        save();
      }
    }),
  ];
  ref.onDispose(() {
    for (final s in subs) {
      s.cancel();
    }
  });
});
