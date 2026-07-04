import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/library/models/track.dart';

void main() {
  test('local track round-trips through row maps', () {
    final track = Track(
      id: 7,
      mediaId: 42,
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      albumId: 3,
      albumArtPath: '/art/3.jpg',
      filePath: '/music/song.mp3',
      duration: const Duration(seconds: 200),
      trackNumber: 4,
      playCount: 2,
      liked: true,
    );
    final back = Track.fromRow({'id': 7, ...track.toRow()});
    expect(back.source, TrackSource.local);
    expect(back.mediaId, 42);
    expect(back.filePath, '/music/song.mp3');
    expect(back.sourceId, isNull);
    expect(back.liked, isTrue);
    expect(back.isPlayableOffline, isTrue);
  });

  test('online track round-trips with null file identity', () {
    final track = Track(
      id: 9,
      title: 'Stream',
      artist: 'Artist',
      album: '',
      duration: const Duration(seconds: 180),
      source: TrackSource.youtube,
      sourceId: 'dQw4w9WgXcQ',
      artUrl: 'https://img.example/art.jpg',
    );
    final back = Track.fromRow({'id': 9, ...track.toRow()});
    expect(back.source, TrackSource.youtube);
    expect(back.sourceId, 'dQw4w9WgXcQ');
    expect(back.mediaId, isNull);
    expect(back.filePath, isNull);
    expect(back.artUrl, 'https://img.example/art.jpg');
    expect(back.isPlayableOffline, isFalse);
  });

  test('rows without v3 columns default to local (pre-migration shape)', () {
    final back = Track.fromRow({
      'id': 1,
      'media_id': 5,
      'title': 'T',
      'artist': 'A',
      'album': 'B',
      'album_id': 2,
      'file_path': '/m/t.mp3',
      'duration_ms': 1000,
      'play_count': 0,
      'liked': 0,
    });
    expect(back.source, TrackSource.local);
    expect(back.isLocal, isTrue);
  });
}
