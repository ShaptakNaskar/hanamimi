/// One row of the append-only listening log (IDEAS-APPROVED.md #7).
///
/// A snapshot, not a reference: it stores what the song *was* when it
/// played, never a foreign key into the mutable tracks table. History
/// must survive deleted/moved/re-scanned files (the Last.fm scrobble
/// model), so playback from history is best-effort re-resolution via
/// [identityKey] — see the history screen's fallback chain.
///
/// This edition is local-only, so there is no source dimension: every
/// row is a file that was on disk.
class ListenEvent {
  const ListenEvent({
    required this.id,
    required this.identityKey,
    required this.title,
    required this.artist,
    required this.album,
    required this.playedAt,
    required this.secondsListened,
    required this.duration,
    this.lastPath,
  });

  final int id;

  /// normalize(title)|normalize(artist)|duration bucket
  /// (utils/track_identity.dart).
  final String identityKey;

  final String title;
  final String artist;
  final String album;

  /// When playback of this row started.
  final DateTime playedAt;

  /// Furthest listened, in whole seconds (position-based, so pauses
  /// don't inflate it).
  final int secondsListened;

  final Duration duration;

  /// Where the file lived when it played — a resolution *hint* only,
  /// never trusted to still exist.
  final String? lastPath;

  factory ListenEvent.fromRow(Map<String, Object?> r) => ListenEvent(
        id: r['id'] as int,
        identityKey: r['identity_key'] as String,
        title: r['title'] as String,
        artist: r['artist'] as String,
        album: r['album'] as String? ?? '',
        playedAt:
            DateTime.fromMillisecondsSinceEpoch(r['played_at'] as int),
        secondsListened: r['seconds_listened'] as int,
        duration: Duration(milliseconds: r['duration_ms'] as int),
        lastPath: r['last_path'] as String?,
      );
}
