@TestOn('linux')
library;

/// End-to-end tests for the 3.0 feature set, run over the REAL
/// repository / backup / crypto / planner code with a real (ffi)
/// SQLite database and real files — only the platform dirs are faked.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/audio/slow_dance.dart';
import 'package:hanamimi/backup/backup_service.dart';
import 'package:hanamimi/backup/passphrase_backup.dart';
import 'package:hanamimi/library/library_repository.dart';
import 'package:hanamimi/library/models/listen_event.dart';
import 'package:hanamimi/library/models/track.dart';
import 'package:hanamimi/theme/hanamimi_theme.dart';
import 'package:hanamimi/theme/night_shift.dart';
import 'package:hanamimi/theme/themes.dart';
import 'package:hanamimi/utils/track_identity.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Points path_provider at a per-test temp dir so LibraryRepository /
/// planSlowDance operate on real files in an isolated sandbox.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);
  String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory sandbox;
  late _FakePathProvider pathProvider;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('hanamimi_e2e_');
    pathProvider = _FakePathProvider(sandbox.path);
    PathProviderPlatform.instance = pathProvider;
  });

  tearDown(() async {
    try {
      await sandbox.delete(recursive: true);
    } catch (_) {}
  });

  /// One scan with ALL the device's tracks — syncScannedTracks is a
  /// full diff, so per-track calls would prune the previous rows.
  Future<Map<int, int>> scanTracks(
      LibraryRepository repo, List<Map<String, Object?>> specs) async {
    await repo.syncScannedTracks([
      for (final s in specs)
        {
          'mediaId': s['mediaId'],
          'title': s['title'],
          'artist': s['artist'],
          'album': 'E2E Album',
          'albumId': 1,
          'filePath': s['path'],
          'durationMs': s['durationMs'] ?? 200000,
          'trackNumber': null,
        }
    ]);
    final all = await repo.allTracks();
    return {
      for (final s in specs)
        s['mediaId'] as int:
            all.firstWhere((t) => t.mediaId == s['mediaId']).id,
    };
  }

  group('DB v6 migration (2.x → 3.0 upgrade path)', () {
    test('a real v5 database upgrades in place and keeps its rows',
        () async {
      // Build a faithful v5 database the way a 2.5.2 install left it.
      final dbPath = '${sandbox.path}/hanamimi.db';
      final v5 = await openDatabase(dbPath, version: 5,
          onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            media_id INTEGER UNIQUE, title TEXT NOT NULL,
            artist TEXT NOT NULL, album TEXT NOT NULL,
            album_id INTEGER NOT NULL DEFAULT 0, album_art_path TEXT,
            file_path TEXT, duration_ms INTEGER NOT NULL,
            track_number INTEGER, play_count INTEGER NOT NULL DEFAULT 0,
            last_played INTEGER, liked INTEGER NOT NULL DEFAULT 0,
            source TEXT NOT NULL DEFAULT 'local', source_id TEXT,
            art_url TEXT, skip_count INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE playlists (
            id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
            cover_color INTEGER NOT NULL, created_at INTEGER NOT NULL,
            cover_image_path TEXT
          )''');
        await db.execute('''
          CREATE TABLE playlist_tracks (
            playlist_id INTEGER NOT NULL, track_id INTEGER NOT NULL,
            position INTEGER NOT NULL,
            PRIMARY KEY (playlist_id, track_id)
          )''');
        await db.execute('''
          CREATE TABLE lyric_cache (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            track_title TEXT NOT NULL, artist_name TEXT NOT NULL,
            lrc_text TEXT NOT NULL, quality INTEGER NOT NULL DEFAULT 0,
            cached_at INTEGER NOT NULL
          )''');
        await db.execute(
            'CREATE TABLE co_play (from_id INTEGER NOT NULL, to_id INTEGER NOT NULL, count INTEGER NOT NULL DEFAULT 1, PRIMARY KEY (from_id, to_id))');
        await db.execute(
            'CREATE TABLE track_features (track_id INTEGER PRIMARY KEY, version INTEGER NOT NULL, vector BLOB NOT NULL, computed_at INTEGER NOT NULL)');
        await db.insert('tracks', {
          'media_id': 7,
          'title': 'Survivor',
          'artist': 'Old Artist',
          'album': 'Old Album',
          'duration_ms': 180000,
          'file_path': '/music/survivor.flac',
        });
      });
      await v5.close();

      // The 3.0 open() must upgrade 5 → 6 without touching the rows.
      final repo = await LibraryRepository.open();
      final tracks = await repo.allTracks();
      expect(tracks, hasLength(1));
      expect(tracks.first.title, 'Survivor');

      // listen_history exists and is writable.
      final rowId = await repo.insertListen(
        identityKey: 'survivor|old artist|18',
        title: 'Survivor',
        artist: 'Old Artist',
        album: 'Old Album',
        source: 'local',
        playedAt: DateTime.now(),
        durationMs: 180000,
        lastPath: '/music/survivor.flac',
      );
      expect(rowId, greaterThan(0));

      // Idempotence (the 2.1.1 lesson): re-running the v6 create must
      // not throw on the already-existing table/indexes.
      final raw = await openDatabase('${sandbox.path}/hanamimi.db');
      final version =
          (await raw.rawQuery('PRAGMA user_version')).first.values.first;
      expect(version, 6);
      await raw.execute(
          'CREATE TABLE IF NOT EXISTS listen_history (id INTEGER PRIMARY KEY)');
      await raw.close();
    });
  });

  group('listen history log (#7)', () {
    test('write → settle → page → aggregate round-trip', () async {
      final repo = await LibraryRepository.open();
      final now = DateTime.now();

      // Three listens: two of one song (today + yesterday), one skip
      // candidate that the tracker deletes.
      final id1 = await repo.insertListen(
        identityKey: identityKey(
            title: 'Idol',
            artist: 'YOASOBI',
            duration: const Duration(seconds: 213)),
        title: 'Idol',
        artist: 'YOASOBI',
        album: 'THE BOOK 3',
        source: 'local',
        playedAt: now,
        durationMs: 213000,
        lastPath: '/music/idol.flac',
      );
      await repo.updateListenSeconds(id1, 200);

      final id2 = await repo.insertListen(
        identityKey: identityKey(
            title: 'Idol',
            artist: 'YOASOBI',
            duration: const Duration(seconds: 213)),
        title: 'Idol',
        artist: 'YOASOBI',
        album: 'THE BOOK 3',
        source: 'local',
        playedAt: now.subtract(const Duration(days: 1)),
        durationMs: 213000,
      );
      await repo.updateListenSeconds(id2, 150);

      final skipRow = await repo.insertListen(
        identityKey: 'x|y|1',
        title: 'x',
        artist: 'y',
        album: '',
        source: 'local',
        playedAt: now,
        durationMs: 10000,
      );
      await repo.deleteListen(skipRow); // sub-20s bail

      final page = await repo.listenHistoryPage(limit: 10);
      expect(page, hasLength(2));
      // Newest first.
      final events = page.map(ListenEvent.fromRow).toList();
      expect(events.first.playedAt.isAfter(events.last.playedAt), isTrue);
      expect(events.first.secondsListened, 200);
      expect(events.first.lastPath, '/music/idol.flac');

      // Artist aggregate = MinHash input.
      final artists = await repo.artistSeconds();
      expect(artists['YOASOBI'], 350);

      // Hour bucketing: this hour's window sees the row played now
      // (yesterday's row also matches — same wall-clock hour, which is
      // exactly the intent of hour-of-day bucketing).
      final hour = now.hour;
      final inWindow = await repo
          .identitySecondsForHours({(hour + 23) % 24, hour, (hour + 1) % 24});
      final key = identityKey(
          title: 'Idol',
          artist: 'YOASOBI',
          duration: const Duration(seconds: 213));
      expect(inWindow[key], 350);

      // A window far from now sees nothing.
      final far = await repo
          .identitySecondsForHours({(hour + 11) % 24, (hour + 12) % 24});
      expect(far[key], isNull);
    });
  });

  group('backup ZIP round-trip (#8 tier 0)', () {
    test(
        'export on device A → import on device B relinks by identity, '
        'restores playlists/favorites/settings, and dedupes on re-import',
        () async {
      SharedPreferences.setMockInitialValues({
        'theme_id': 'starry_night',
        'crossfade_seconds': 6,
        'slow_dance': true,
        'stats_client_id': 'e2e-client-42',
        'stats_local_seconds': 12345,
        'leaderboard_nickname': 'e2e sappy',
        'yt_connected': true, // NOT allowlisted — must not travel
      });
      final prefsA = await SharedPreferences.getInstance();

      // Device A: two local tracks, one liked, one playlist, history.
      final repoA = await LibraryRepository.open();
      final idsA = await scanTracks(repoA, [
        {
          'mediaId': 1,
          'title': 'Idol',
          'artist': 'YOASOBI',
          'path': '/oldphone/Music/idol.flac',
          'durationMs': 213000,
        },
        {
          'mediaId': 2,
          'title': 'Ghost City',
          'artist': 'Nowhere Band',
          'path': '/oldphone/Music/ghost.flac',
          'durationMs': 240000,
        },
      ]);
      final likedId = idsA[1]!;
      final otherId = idsA[2]!;
      await repoA.setLiked(likedId, true);
      final playlistId = await repoA.createPlaylist('roadtrip 🌸', 0xFFF4A7B9);
      await repoA.addToPlaylist(playlistId, likedId);
      await repoA.addToPlaylist(playlistId, otherId);
      final h = await repoA.insertListen(
        identityKey: identityKey(
            title: 'Idol',
            artist: 'YOASOBI',
            duration: const Duration(milliseconds: 213000)),
        title: 'Idol',
        artist: 'YOASOBI',
        album: 'THE BOOK 3',
        source: 'local',
        playedAt: DateTime.now(),
        durationMs: 213000,
      );
      await repoA.updateListenSeconds(h, 180);

      final zip = await BackupService.buildBundle(prefs: prefsA, repo: repoA);
      expect(zip.length, greaterThan(200));

      // Device B: fresh sandbox, fresh prefs. Library has the SAME
      // song at a DIFFERENT path (reorganized music folder) but NOT
      // Ghost City.
      final sandboxB = await Directory.systemTemp.createTemp('hanamimi_b_');
      addTearDown(() => sandboxB.delete(recursive: true));
      pathProvider.root = sandboxB.path;
      SharedPreferences.setMockInitialValues({});
      final prefsB = await SharedPreferences.getInstance();
      final repoB = await LibraryRepository.open();
      final newIdolId = (await scanTracks(repoB, [
        {
          'mediaId': 99,
          'title': 'IDOL (feat. nobody)', // messier tags, same identity
          'artist': 'yoasobi',
          'path': '/newphone/Tunes/idol_v2.flac',
          'durationMs': 215000, // same 10s identity bucket
        },
      ]))[99]!;

      final summary = await BackupService.importBundle(zip,
          prefs: prefsB, repo: repoB, onlineAllowed: false);

      expect(summary.historyAdded, 1);
      expect(summary.favoritesRestored, 1);
      expect(summary.favoritesMissed, 0);
      expect(summary.playlistsRestored, 1);
      expect(summary.playlistTracksMissed, 1, // Ghost City isn't here
          reason: summary.describe());

      // The favorite landed on the NEW device's row via identity.
      final tracksB = await repoB.allTracks();
      expect(
          tracksB.firstWhere((t) => t.id == newIdolId).liked, isTrue);

      final playlistsB = await repoB.allPlaylists();
      expect(playlistsB.single.name, 'roadtrip 🌸');
      expect(playlistsB.single.trackIds, [newIdolId]);

      // Settings: allowlisted travel, leaderboard identity continues,
      // non-allowlisted (yt_connected) does not.
      expect(prefsB.getString('theme_id'), 'starry_night');
      expect(prefsB.getInt('crossfade_seconds'), 6);
      expect(prefsB.getString('stats_client_id'), 'e2e-client-42');
      expect(prefsB.getInt('stats_local_seconds'), 12345);
      expect(prefsB.getBool('yt_connected'), isNull);

      // Import the same ZIP again: nothing doubles.
      final again = await BackupService.importBundle(zip,
          prefs: prefsB, repo: repoB, onlineAllowed: false);
      expect(again.historyAdded, 0);
      expect(again.playlistsRestored, 0);
      expect((await repoB.allPlaylists()), hasLength(1));
      expect((await repoB.listenHistoryPage()), hasLength(1));
    });

    test('garbage and foreign ZIPs are rejected cleanly', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = await LibraryRepository.open();
      expect(
          () => BackupService.importBundle(
              Uint8List.fromList(List.filled(100, 42)),
              prefs: prefs,
              repo: repo,
              onlineAllowed: false),
          throwsA(anything));
    });
  });

  group('passphrase crypto (#8 convenience tier)', () {
    test('phrase shape, key/id domain separation, roundtrip, wrong-key',
        () {
      final phrase = PassphraseBackup.generatePhrase();
      expect(phrase.split(' '), hasLength(PassphraseBackup.wordCount));

      final blobId = PassphraseBackup.blobIdFor(phrase);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(blobId), isTrue,
          reason: 'blobId must satisfy the backend validator');
      // Normalization: sloppy typing on the new device still finds it.
      expect(PassphraseBackup.blobIdFor('  ${phrase.toUpperCase()}  '),
          blobId);

      final bundle = Uint8List.fromList(
          List.generate(4096, (i) => (i * 31) & 0xFF));
      final blob = PassphraseBackup.encryptBundle(bundle, phrase, null);
      expect(blob.length, greaterThan(bundle.length)); // nonce + tag
      // Ciphertext must not contain the plaintext (spot check).
      expect(blob.sublist(12, 60), isNot(bundle.sublist(0, 48)));

      final back = PassphraseBackup.decryptBundle(blob, phrase, null);
      expect(back, bundle);

      // Wrong phrase / wrong second-factor password must throw, not
      // return garbage (GCM tag).
      expect(
          () => PassphraseBackup.decryptBundle(
              blob, PassphraseBackup.generatePhrase(), null),
          throwsA(anything));
      final withPw = PassphraseBackup.encryptBundle(bundle, phrase, 'hunter2');
      expect(PassphraseBackup.decryptBundle(withPw, phrase, 'hunter2'),
          bundle);
      expect(
          () => PassphraseBackup.decryptBundle(withPw, phrase, 'wrong'),
          throwsA(anything));
      expect(() => PassphraseBackup.decryptBundle(withPw, phrase, null),
          throwsA(anything));
    });
  });

  group('slow dance planner (#4)', () {
    /// Writes a synthetic v3 cache file the way the extractors do:
    /// big-endian [int32 frameCount][14 float32s × frame] @60fps.
    Future<Track> makeCachedTrack({
      required int loudSeconds,
      required int tailSeconds,
      double tailLevel = 0.02,
    }) async {
      const fps = 60;
      const stride = 14;
      final frames = (loudSeconds + tailSeconds) * fps;
      final data = ByteData(4 + frames * stride * 4);
      data.setInt32(0, frames);
      for (var f = 0; f < frames; f++) {
        final loud = f < loudSeconds * fps;
        for (var s = 0; s < stride; s++) {
          final v = s < 12
              ? (loud ? 0.6 : tailLevel)
              : (loud ? 0.55 : tailLevel); // RMS columns
          data.setFloat32(4 + (f * stride + s) * 4, v);
        }
      }
      const path = '/music/fade.flac';
      final durationMs = (loudSeconds + tailSeconds) * 1000;
      final key = 'v3_${1}_${path.hashCode}_$durationMs';
      final file = File('${pathProvider.root}/fft/$key.bin');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List());
      return Track(
        id: 1,
        mediaId: 1,
        title: 'Fade',
        artist: 'Test',
        album: '',
        filePath: path,
        duration: Duration(milliseconds: durationMs),
      );
    }

    test('finds the energy tail of a track with a long fade-out',
        () async {
      final track =
          await makeCachedTrack(loudSeconds: 100, tailSeconds: 8);
      final plan = await planSlowDance(track);
      expect(plan, isNotNull);
      // The fade should cover (roughly) the 8s quiet tail.
      expect(plan!.fade.inSeconds, inInclusiveRange(6, 10),
          reason: 'fade=${plan.fade}');
      expect(plan.startAt.inSeconds, inInclusiveRange(97, 102),
          reason: 'startAt=${plan.startAt}');
    });

    test('cold ending still gets the minimum overlap', () async {
      final track =
          await makeCachedTrack(loudSeconds: 100, tailSeconds: 0);
      final plan = await planSlowDance(track);
      expect(plan, isNotNull);
      expect(plan!.fade, const Duration(seconds: 2));
    });

    test('30-minute ambient fade is capped at 15s', () async {
      final track =
          await makeCachedTrack(loudSeconds: 60, tailSeconds: 40);
      final plan = await planSlowDance(track);
      expect(plan!.fade, const Duration(seconds: 15));
    });

    test('no cache file → null (classic-timer fallback)', () async {
      const track = Track(
        id: 2,
        mediaId: 2,
        title: 'Uncached',
        artist: 'Test',
        album: '',
        filePath: '/music/uncached.flac',
        duration: Duration(seconds: 200),
      );
      expect(await planSlowDance(track), isNull);
    });

    test('corrupt cache → null, never a crash', () async {
      const path = '/music/corrupt.flac';
      final key = 'v3_${3}_${path.hashCode}_200000';
      final file = File('${pathProvider.root}/fft/$key.bin');
      await file.parent.create(recursive: true);
      await file.writeAsBytes([1, 2, 3, 4, 5]);
      const track = Track(
        id: 3,
        mediaId: 3,
        title: 'Corrupt',
        artist: 'Test',
        album: '',
        filePath: path,
        duration: Duration(seconds: 200),
      );
      expect(await planSlowDance(track), isNull);
    });
  });

  group('night shift (#2)', () {
    test('every theme goes dark, ember-warm, and readable', () {
      for (final t in allThemes) {
        final n = nightShift(t);
        expect(n.brightness, HanamimiBrightness.dark,
            reason: '${t.id} must flip dark at night');
        expect(n.emoji, '🌙');
        // Canvas actually darker than the accent (contrast survives).
        expect(n.background.computeLuminance(),
            lessThan(n.primary.computeLuminance()),
            reason: '${t.id}: accents must stay visible on the canvas');
        expect(n.background.computeLuminance(), lessThan(0.05),
            reason: '${t.id}: night canvas must be near-black');
        expect(n.textPrimary.computeLuminance(), greaterThan(0.3),
            reason: '${t.id}: text must stay readable');
        // Discrete fields survive so lerp/pickers stay coherent.
        expect(n.id, t.id);
        expect(n.visualizerStyle, t.visualizerStyle);
      }
    });
  });
}
