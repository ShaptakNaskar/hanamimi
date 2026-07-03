class Track {
  const Track({
    required this.id,
    required this.mediaId,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumId,
    this.albumArtPath,
    required this.filePath,
    required this.duration,
    this.trackNumber,
    this.playCount = 0,
    this.lastPlayed,
    this.liked = false,
  });

  /// Local DB row id.
  final int id;

  /// MediaStore _ID on the device.
  final int mediaId;

  final String title;
  final String artist;
  final String album;
  final int albumId;
  final String? albumArtPath;
  final String filePath;
  final Duration duration;
  final int? trackNumber;
  final int playCount;
  final DateTime? lastPlayed;
  final bool liked;

  Track copyWith({
    String? albumArtPath,
    int? playCount,
    DateTime? lastPlayed,
    bool? liked,
  }) =>
      Track(
        id: id,
        mediaId: mediaId,
        title: title,
        artist: artist,
        album: album,
        albumId: albumId,
        albumArtPath: albumArtPath ?? this.albumArtPath,
        filePath: filePath,
        duration: duration,
        trackNumber: trackNumber,
        playCount: playCount ?? this.playCount,
        lastPlayed: lastPlayed ?? this.lastPlayed,
        liked: liked ?? this.liked,
      );

  factory Track.fromRow(Map<String, Object?> r) => Track(
        id: r['id'] as int,
        mediaId: r['media_id'] as int,
        title: r['title'] as String,
        artist: r['artist'] as String,
        album: r['album'] as String,
        albumId: r['album_id'] as int,
        albumArtPath: r['album_art_path'] as String?,
        filePath: r['file_path'] as String,
        duration: Duration(milliseconds: r['duration_ms'] as int),
        trackNumber: r['track_number'] as int?,
        playCount: r['play_count'] as int,
        lastPlayed: r['last_played'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['last_played'] as int),
        liked: (r['liked'] as int) != 0,
      );

  Map<String, Object?> toRow() => {
        'media_id': mediaId,
        'title': title,
        'artist': artist,
        'album': album,
        'album_id': albumId,
        'album_art_path': albumArtPath,
        'file_path': filePath,
        'duration_ms': duration.inMilliseconds,
        'track_number': trackNumber,
        'play_count': playCount,
        'last_played': lastPlayed?.millisecondsSinceEpoch,
        'liked': liked ? 1 : 0,
      };
}

/// Albums are derived from tracks (grouped by MediaStore album id).
class Album {
  const Album({
    required this.albumId,
    required this.title,
    required this.artist,
    this.artPath,
    required this.tracks,
  });

  final int albumId;
  final String title;
  final String artist;
  final String? artPath;
  final List<Track> tracks;
}
