@TestOn('linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/platform/desktop/desktop_library.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regression: "changed the music location, rescanned, stale entries
/// stayed" (user-reported on desktop, M31). Replays the desktop scan
/// pipeline — DesktopLibrary.queryTracks → syncScannedTracks-shaped
/// diff → prune — against real files with the real ffprobe.
void main() {
  late Database db;
  late Directory tmp;

  Future<void> makeFlac(String path, String title) async {
    await Directory(File(path).parent.path).create(recursive: true);
    final res = await Process.run('ffmpeg', [
      '-y', '-v', 'quiet',
      '-f', 'lavfi', '-i', 'sine=frequency=440:duration=1',
      '-metadata', 'title=$title',
      '-metadata', 'artist=Test Artist',
      path,
    ]);
    expect(res.exitCode, 0, reason: 'ffmpeg must produce $path');
  }

  // The repo's sync, replicated over the ffi db (LibraryRepository.open
  // needs path_provider; the SQL below is copied from syncScannedTracks
  // so the diff semantics under test are identical).
  Future<void> sync(List<Map<String, Object?>> scanned) async {
    await db.transaction((txn) async {
      final existing = await txn.query('tracks',
          columns: ['media_id'], where: "source = 'local'");
      final existingIds = existing.map((r) => r['media_id'] as int).toSet();
      final scannedIds = <int>{};
      for (final s in scanned) {
        final mediaId = s['mediaId'] as int;
        scannedIds.add(mediaId);
        if (!existingIds.contains(mediaId)) {
          await txn.insert('tracks', {
            'media_id': mediaId,
            'title': s['title'] as String? ?? 'Unknown',
            'artist': (s['artist'] as String?) ?? 'Unknown artist',
            'album': (s['album'] as String?) ?? 'Unknown album',
            'album_id': s['albumId'] as int? ?? 0,
            'file_path': s['filePath'] as String,
            'duration_ms': s['durationMs'] as int? ?? 0,
          });
        }
      }
      for (final mediaId in existingIds.difference(scannedIds)) {
        await txn.delete('tracks',
            where: "media_id = ? AND source = 'local'",
            whereArgs: [mediaId]);
      }
    });
  }

  Future<Set<String>> dbPaths() async => {
        for (final r in await db.query('tracks', columns: ['file_path']))
          r['file_path'] as String,
      };

  Future<Set<String>> knownPaths() => dbPaths();

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE tracks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_id INTEGER UNIQUE,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT NOT NULL,
        album_id INTEGER NOT NULL DEFAULT 0,
        file_path TEXT,
        duration_ms INTEGER NOT NULL,
        source TEXT NOT NULL DEFAULT 'local'
      )
    ''');
    tmp = await Directory.systemTemp.createTemp('hanamimi_scan_test');
  });

  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('switching music folders drops the old folder\'s rows', () async {
    final dirA = '${tmp.path}/A';
    final dirB = '${tmp.path}/B';
    await makeFlac('$dirA/one.flac', 'One');
    await makeFlac('$dirA/two.flac', 'Two');
    await makeFlac('$dirB/three.flac', 'Three');

    // Initial scan of A.
    await sync(await DesktopLibrary.queryTracks({dirA}));
    expect(await dbPaths(),
        {'$dirA/one.flac', '$dirA/two.flac'});

    // User switches the library to B; A's files still exist on disk.
    await sync(await DesktopLibrary.queryTracks({dirB},
        knownPaths: await knownPaths()));
    expect(await dbPaths(), {'$dirB/three.flac'},
        reason: 'rows from the abandoned folder must be removed');
  });

  test('deleting files inside the folder drops their rows', () async {
    final dirA = '${tmp.path}/A';
    await makeFlac('$dirA/one.flac', 'One');
    await makeFlac('$dirA/two.flac', 'Two');
    await sync(await DesktopLibrary.queryTracks({dirA}));
    expect((await dbPaths()).length, 2);

    await File('$dirA/two.flac').delete();
    await sync(await DesktopLibrary.queryTracks({dirA},
        knownPaths: await knownPaths()));
    expect(await dbPaths(), {'$dirA/one.flac'});
  });

  test('rescan with unchanged folder keeps rows and probes nothing new',
      () async {
    final dirA = '${tmp.path}/A';
    await makeFlac('$dirA/one.flac', 'One');
    await sync(await DesktopLibrary.queryTracks({dirA}));

    final again = await DesktopLibrary.queryTracks({dirA},
        knownPaths: await knownPaths());
    // Known files come back as membership-only rows (no re-probe).
    expect(again.single.containsKey('title'), isFalse);
    await sync(again);
    expect(await dbPaths(), {'$dirA/one.flac'});
  });
}
