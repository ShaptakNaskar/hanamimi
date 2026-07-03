import 'package:sqflite/sqflite.dart';

import 'models/playlist.dart';
import 'models/track.dart';

/// sqflite-backed store for the music library.
/// (ARCHITECTURE.md specifies Isar, but Isar 3.x is unmaintained and
/// incompatible with AGP 8 — see PROGRESS.md deviations.)
class LibraryRepository {
  LibraryRepository._(this._db);

  final Database _db;

  static Future<LibraryRepository> open() async {
    final db = await openDatabase(
      'hanamimi.db',
      version: 2,
      // v2 adds lyric quality (word/line/plain). Old rows predate the
      // word-synced provider, so wipe them and refetch on demand.
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await db.execute('DROP TABLE IF EXISTS lyric_cache');
          await _createLyricCache(db);
        }
      },
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE tracks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            media_id INTEGER NOT NULL UNIQUE,
            title TEXT NOT NULL,
            artist TEXT NOT NULL,
            album TEXT NOT NULL,
            album_id INTEGER NOT NULL,
            album_art_path TEXT,
            file_path TEXT NOT NULL,
            duration_ms INTEGER NOT NULL,
            track_number INTEGER,
            play_count INTEGER NOT NULL DEFAULT 0,
            last_played INTEGER,
            liked INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE playlists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            cover_color INTEGER NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE playlist_tracks (
            playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
            track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            PRIMARY KEY (playlist_id, track_id)
          )
        ''');
        await _createLyricCache(db);
      },
    );
    return LibraryRepository._(db);
  }

  static Future<void> _createLyricCache(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE lyric_cache (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_title TEXT NOT NULL,
        artist_name TEXT NOT NULL,
        lrc_text TEXT NOT NULL,
        quality INTEGER NOT NULL DEFAULT 0,
        cached_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_lyric_cache ON lyric_cache(track_title, artist_name)');
  }

  // --- Tracks ---

  Future<List<Track>> allTracks() async {
    final rows =
        await _db.query('tracks', orderBy: 'title COLLATE NOCASE ASC');
    return rows.map(Track.fromRow).toList();
  }

  /// Syncs scanned device tracks into the DB: inserts new media ids,
  /// removes rows whose files disappeared. Returns number of changes.
  Future<int> syncScannedTracks(List<Map<String, Object?>> scanned) async {
    var changes = 0;
    await _db.transaction((txn) async {
      final existing = await txn.query('tracks', columns: ['media_id']);
      final existingIds = existing.map((r) => r['media_id'] as int).toSet();
      final scannedIds = <int>{};

      for (final s in scanned) {
        final mediaId = s['mediaId'] as int;
        scannedIds.add(mediaId);
        if (!existingIds.contains(mediaId)) {
          await txn.insert('tracks', {
            'media_id': mediaId,
            'title': s['title'] as String? ?? 'Unknown',
            // MediaStore reports missing metadata as the literal "<unknown>".
            'artist': switch (s['artist'] as String?) {
              null || '<unknown>' => 'Unknown artist',
              final a => a,
            },
            'album': switch (s['album'] as String?) {
              null || '<unknown>' => 'Unknown album',
              final a => a,
            },
            'album_id': s['albumId'] as int,
            'file_path': s['filePath'] as String,
            'duration_ms': s['durationMs'] as int,
            'track_number': s['trackNumber'] as int?,
          });
          changes++;
        }
      }

      final removed = existingIds.difference(scannedIds);
      for (final mediaId in removed) {
        await txn
            .delete('tracks', where: 'media_id = ?', whereArgs: [mediaId]);
        changes++;
      }
    });
    return changes;
  }

  Future<void> setAlbumArt(int albumId, String path) => _db.update(
      'tracks', {'album_art_path': path},
      where: 'album_id = ?', whereArgs: [albumId]);

  Future<void> setLiked(int trackId, bool liked) => _db.update(
      'tracks', {'liked': liked ? 1 : 0},
      where: 'id = ?', whereArgs: [trackId]);

  Future<void> recordPlay(int trackId) => _db.rawUpdate(
      'UPDATE tracks SET play_count = play_count + 1, last_played = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, trackId]);

  // --- Playlists ---

  Future<List<Playlist>> allPlaylists() async {
    final rows = await _db.query('playlists', orderBy: 'created_at DESC');
    final playlists = <Playlist>[];
    for (final r in rows) {
      final links = await _db.query('playlist_tracks',
          where: 'playlist_id = ?',
          whereArgs: [r['id']],
          orderBy: 'position ASC');
      playlists.add(Playlist.fromRow(
          r, links.map((l) => l['track_id'] as int).toList()));
    }
    return playlists;
  }

  Future<int> createPlaylist(String name, int coverColor) =>
      _db.insert('playlists', {
        'name': name,
        'cover_color': coverColor,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

  Future<void> deletePlaylist(int id) =>
      _db.delete('playlists', where: 'id = ?', whereArgs: [id]);

  Future<void> removeFromPlaylist(int playlistId, int trackId) =>
      _db.delete('playlist_tracks',
          where: 'playlist_id = ? AND track_id = ?',
          whereArgs: [playlistId, trackId]);

  Future<void> addToPlaylist(int playlistId, int trackId) async {
    final max = Sqflite.firstIntValue(await _db.rawQuery(
        'SELECT MAX(position) FROM playlist_tracks WHERE playlist_id = ?',
        [playlistId]));
    await _db.insert(
      'playlist_tracks',
      {
        'playlist_id': playlistId,
        'track_id': trackId,
        'position': (max ?? -1) + 1,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Dev tool: force every lyric to refetch on next open.
  Future<void> clearLyricsCache() => _db.delete('lyric_cache');

  // --- Lyric cache ---

  Future<Map<String, Object?>?> cachedLyrics(
      String title, String artist) async {
    final rows = await _db.query('lyric_cache',
        where: 'track_title = ? AND artist_name = ?',
        whereArgs: [title, artist],
        limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> cacheLyrics(
      String title, String artist, String lrcText, int quality) async {
    await _db.delete('lyric_cache',
        where: 'track_title = ? AND artist_name = ?',
        whereArgs: [title, artist]);
    await _db.insert('lyric_cache', {
      'track_title': title,
      'artist_name': artist,
      'lrc_text': lrcText,
      'quality': quality,
      'cached_at': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
