/// Where a track's audio comes from (ARCHITECTURE-ONLINE.md §3.1).
enum TrackSource { local, youtube, saavn }

class Track {
  const Track({
    required this.id,
    this.mediaId,
    required this.title,
    required this.artist,
    required this.album,
    this.albumId = 0,
    this.albumArtPath,
    this.filePath,
    required this.duration,
    this.trackNumber,
    this.playCount = 0,
    this.lastPlayed,
    this.liked = false,
    this.source = TrackSource.local,
    this.sourceId,
    this.artUrl,
  });

  /// Local DB row id.
  final int id;

  /// MediaStore _ID on the device; null for online tracks.
  final int? mediaId;

  final String title;
  final String artist;
  final String album;

  /// MediaStore album id; 0 for online tracks (Albums stay local-only).
  final int albumId;
  final String? albumArtPath;

  /// Null for online tracks until they're downloaded.
  final String? filePath;
  final Duration duration;
  final int? trackNumber;
  final int playCount;
  final DateTime? lastPlayed;
  final bool liked;

  final TrackSource source;

  /// videoId / Saavn song id; null for local tracks.
  final String? sourceId;

  /// Remote art; [albumArtPath] holds the locally cached copy.
  final String? artUrl;

  bool get isLocal => source == TrackSource.local;

  /// Downloaded online tracks behave as local for playback while
  /// keeping their online identity.
  bool get isPlayableOffline => filePath != null;

  Track copyWith({
    String? albumArtPath,
    String? filePath,
    bool clearFilePath = false,
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
        filePath: clearFilePath ? null : filePath ?? this.filePath,
        duration: duration,
        trackNumber: trackNumber,
        playCount: playCount ?? this.playCount,
        lastPlayed: lastPlayed ?? this.lastPlayed,
        liked: liked ?? this.liked,
        source: source,
        sourceId: sourceId,
        artUrl: artUrl,
      );

  factory Track.fromRow(Map<String, Object?> r) => Track(
        id: r['id'] as int,
        mediaId: r['media_id'] as int?,
        title: r['title'] as String,
        artist: r['artist'] as String,
        album: r['album'] as String,
        albumId: r['album_id'] as int? ?? 0,
        albumArtPath: r['album_art_path'] as String?,
        filePath: r['file_path'] as String?,
        duration: Duration(milliseconds: r['duration_ms'] as int),
        trackNumber: r['track_number'] as int?,
        playCount: r['play_count'] as int,
        lastPlayed: r['last_played'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['last_played'] as int),
        liked: (r['liked'] as int) != 0,
        source: TrackSource.values.byName(r['source'] as String? ?? 'local'),
        sourceId: r['source_id'] as String?,
        artUrl: r['art_url'] as String?,
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
        'source': source.name,
        'source_id': sourceId,
        'art_url': artUrl,
      };
}

/// A directory on disk that directly contains audio files (VLC-style
/// folder browsing). Derived from track file paths.
class MusicFolder {
  const MusicFolder({
    required this.path,
    required this.name,
    required this.tracks,
  });

  final String path;
  final String name;
  final List<Track> tracks;
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
