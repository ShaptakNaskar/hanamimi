import 'dart:convert';

import '../../library/models/track.dart';
import 'queue_mode.dart';

/// A persisted snapshot of "what was playing" so the app can offer to
/// resume it on next launch (the VLC behaviour). Stored as JSON in
/// SharedPreferences; rewritten as playback moves, cleared when the
/// user declines the resume prompt.
class PlaybackSession {
  const PlaybackSession({
    required this.queue,
    required this.index,
    required this.position,
    required this.mode,
  });

  /// The play order as the user last saw it.
  final List<Track> queue;

  /// Cursor into [queue] — the track that was current.
  final int index;
  final Duration position;
  final QueueMode mode;

  Track? get current =>
      (index >= 0 && index < queue.length) ? queue[index] : null;

  String encode() => jsonEncode({
        'index': index,
        'positionMs': position.inMilliseconds,
        'mode': mode.name,
        // Round-trips through Track.fromRow (toRow omits the row id).
        'queue': [
          for (final t in queue) {...t.toRow(), 'id': t.id},
        ],
      });

  static PlaybackSession? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final rows = (map['queue'] as List?)?.cast<Map<String, dynamic>>() ??
          const [];
      final queue = [for (final r in rows) Track.fromRow(r)];
      if (queue.isEmpty) return null;
      return PlaybackSession(
        queue: queue,
        index: (map['index'] as num?)?.toInt() ?? 0,
        position: Duration(milliseconds: (map['positionMs'] as num?)?.toInt() ?? 0),
        mode: QueueMode.values.firstWhere(
          (m) => m.name == map['mode'],
          orElse: () => QueueMode.sequential,
        ),
      );
    } catch (_) {
      return null;
    }
  }
}
