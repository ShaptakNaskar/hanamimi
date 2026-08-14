import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/audio/models/audio_state.dart';
import 'package:hanamimi/library/models/track.dart';
import 'package:hanamimi/platform/desktop/discord_presence_service.dart';

void main() {
  const localTrack = Track(
    id: 7,
    title: 'Haru no Umi',
    artist: 'Michio Miyagi',
    album: 'Koto Classics',
    albumArtPath: '/private/music/cover.jpg',
    filePath: '/private/music/haru.flac',
    duration: Duration(minutes: 4),
  );

  const onlineTrack = Track(
    id: 8,
    title: '夜に駆ける',
    artist: 'YOASOBI',
    album: 'THE BOOK',
    duration: Duration(minutes: 4, seconds: 21),
    source: TrackSource.youtube,
    sourceId: 'x8VYWazR5mE',
    artUrl: 'https://example.com/the-book.jpg',
  );

  group('Discord presence mapping', () {
    test('playing activity has listening type, metadata and progress', () {
      final now = DateTime.utc(2026, 8, 9, 12);
      final activity =
          buildDiscordActivity(
            const AudioState(
              currentTrack: onlineTrack,
              status: PlaybackStatus.playing,
              duration: Duration(minutes: 4, seconds: 21),
            ),
            const Duration(minutes: 1, seconds: 5),
            now: now,
          ).toJson();

      expect(activity['name'], 'Hanamimi+');
      expect(activity['type'], 2);
      expect(activity['details'], '夜に駆ける');
      expect(activity['state'], 'YOASOBI • THE BOOK');
      expect(activity['timestamps'], {
        'start':
            now
                .subtract(const Duration(minutes: 1, seconds: 5))
                .millisecondsSinceEpoch,
        'end':
            now
                .add(const Duration(minutes: 3, seconds: 16))
                .millisecondsSinceEpoch,
      });
      expect(
        activity['assets'],
        containsPair('large_image', 'https://example.com/the-book.jpg'),
      );
      expect(
        activity['assets'],
        containsPair('small_image', hanamimiDiscordArtworkUrl),
      );
    });

    test('paused activity names its status and stops the progress clock', () {
      final activity =
          buildDiscordActivity(
            const AudioState(
              currentTrack: localTrack,
              status: PlaybackStatus.paused,
              duration: Duration(minutes: 4),
            ),
            const Duration(minutes: 2),
            now: DateTime.utc(2026, 8, 9, 12),
          ).toJson();

      expect(activity['state'], 'Paused • Michio Miyagi • Koto Classics');
      expect(activity['timestamps'], isNull);
      expect(
        activity['assets'],
        containsPair('large_image', hanamimiDiscordArtworkUrl),
      );
      expect(activity.toString(), isNot(contains('/private/music')));
    });

    test('normal ticks retain an activity key while seeks change it', () {
      const state = AudioState(
        currentTrack: onlineTrack,
        status: PlaybackStatus.playing,
        duration: Duration(minutes: 4, seconds: 21),
      );
      final now = DateTime.utc(2026, 8, 9, 12);
      final initial = discordActivityKey(
        state,
        const Duration(seconds: 30),
        now: now,
      );
      final normalTick = discordActivityKey(
        state,
        const Duration(seconds: 31),
        now: now.add(const Duration(seconds: 1)),
      );
      final seek = discordActivityKey(
        state,
        const Duration(minutes: 2),
        now: now.add(const Duration(seconds: 1)),
      );

      expect(normalTick, initial);
      expect(seek, isNot(initial));
    });

    test('Discord text is capped without splitting non-BMP characters', () {
      final longTrack = Track(
        id: 9,
        title: List.filled(140, '🌸').join(),
        artist: 'Artist',
        album: '',
        duration: const Duration(minutes: 1),
      );
      final activity =
          buildDiscordActivity(
            AudioState(
              currentTrack: longTrack,
              status: PlaybackStatus.playing,
              duration: longTrack.duration,
            ),
            Duration.zero,
            now: DateTime.utc(2026, 8, 9, 12),
          ).toJson();

      final details = activity['details']! as String;
      expect(details.runes.length, 128);
      expect(details.endsWith('…'), isTrue);
    });
  });
}
