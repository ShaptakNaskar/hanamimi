import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../online/models/online_search_result.dart';
import 'models/playlist.dart';
import 'models/track.dart';

/// sqflite-backed store for the music library.
/// (ARCHITECTURE.md specifies Isar, but Isar 3.x is unmaintained and
/// incompatible with AGP 8 — see PROGRESS.md deviations.)
class LibraryRepository {
  LibraryRepository._(this._db);

  final Database _db;

  static Future<LibraryRepository> open() async {
    // Android resolves the bare name to the app databases dir; the ffi
    // backend on desktop wants an explicit per-OS location (the global
    // databaseFactory is switched to ffi in the desktop bootstrap).
    final dbPath = Platform.isAndroid
        ? 'hanamimi.db'
        : '${(await getApplicationSupportDirectory()).path}/hanamimi.db';
    final db = await openDatabase(
      dbPath,
      version: 5,
      // v2 adds lyric quality (word/line/plain). Old rows predate the
      // word-synced provider, so wipe them and refetch on demand.
      // v3 adds online sources (ARCHITECTURE-ONLINE.md §7).
      // v4 adds user-picked playlist cover images.
      // v5 adds the recommendation signals (ARCHITECTURE-RECOMMENDATIONS.md
      // M38a): co_play transitions, per-track audio features, skip counts.
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await db.execute('DROP TABLE IF EXISTS lyric_cache');
          await _createLyricCache(db);
        }
        if (oldVersion < 3) await _migrateTracksV3(db);
        if (oldVersion < 4) {
          if (!await _columnExists(db, 'playlists', 'cover_image_path')) {
            await db.execute(
                'ALTER TABLE playlists ADD COLUMN cover_image_path TEXT');
          }
        }
        if (oldVersion < 5) {
          // Add skip_count only if it isn't already present. A pre-v3 DB
          // gets its tracks table rebuilt from _tracksSchema (which now
          // carries skip_count), and some builds left the column present
          // while the version lagged — a blind ALTER then throws
          // "duplicate column name" and wedges the whole app (desktop
          // crash, user-reported). The existence check makes the
          // migration idempotent regardless of prior state.
          if (!await _columnExists(db, 'tracks', 'skip_count')) {
            await db.execute(
                'ALTER TABLE tracks ADD COLUMN skip_count INTEGER NOT NULL DEFAULT 0');
          }
          await _createRecoTables(db);
        }
      },
      onCreate: (db, _) async {
        await db.execute(_tracksSchema('tracks'));
        await db.execute(_onlineIndex);
        await _createRecoTables(db);
        await db.execute('''
          CREATE TABLE playlists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            cover_color INTEGER NOT NULL,
            created_at INTEGER NOT NULL,
            cover_image_path TEXT
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

  /// v3: media_id and file_path are nullable (online tracks have
  /// neither until downloaded), plus source identity columns.
  static String _tracksSchema(String name) => '''
      CREATE TABLE $name (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_id INTEGER UNIQUE,
        title TEXT NOT NULL,
        artist TEXT NOT NULL,
        album TEXT NOT NULL,
        album_id INTEGER NOT NULL DEFAULT 0,
        album_art_path TEXT,
        file_path TEXT,
        duration_ms INTEGER NOT NULL,
        track_number INTEGER,
        play_count INTEGER NOT NULL DEFAULT 0,
        last_played INTEGER,
        liked INTEGER NOT NULL DEFAULT 0,
        source TEXT NOT NULL DEFAULT 'local',
        source_id TEXT,
        art_url TEXT,
        skip_count INTEGER NOT NULL DEFAULT 0
      )
    ''';

  /// One row per online identity; local rows (source_id NULL) exempt.
  static const _onlineIndex = '''
      CREATE UNIQUE INDEX idx_tracks_online ON tracks(source, source_id)
        WHERE source_id IS NOT NULL
    ''';

  /// SQLite can't relax NOT NULL/UNIQUE in place — rebuild the table.
  /// Row ids are copied verbatim so playlist_tracks references survive.
  /// (openDatabase already wraps version callbacks in a transaction.)
  static Future<void> _migrateTracksV3(Database db) async {
    await db.execute(_tracksSchema('tracks_v3'));
    await db.execute('''
      INSERT INTO tracks_v3
        (id, media_id, title, artist, album, album_id, album_art_path,
         file_path, duration_ms, track_number, play_count, last_played, liked)
      SELECT id, media_id, title, artist, album, album_id, album_art_path,
         file_path, duration_ms, track_number, play_count, last_played, liked
      FROM tracks
    ''');
    await db.execute('DROP TABLE tracks');
    await db.execute('ALTER TABLE tracks_v3 RENAME TO tracks');
    await db.execute(_onlineIndex);
  }

  /// True when [table] already has [column] — used to make ALTER-based
  /// migrations idempotent so a re-run (or a column added out of version
  /// order) can't crash with "duplicate column name".
  static Future<bool> _columnExists(
      DatabaseExecutor db, String table, String column) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((r) => r['name'] == column);
  }

  /// M38a recommendation signals. co_play counts "B started after A
  /// played through" transitions (the Markov/co-occurrence source);
  /// track_features holds the per-track audio summary vector extracted
  /// during the visualizer decode.
  static Future<void> _createRecoTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS co_play (
        from_id INTEGER NOT NULL,
        to_id INTEGER NOT NULL,
        count INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (from_id, to_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS track_features (
        track_id INTEGER PRIMARY KEY,
        version INTEGER NOT NULL,
        vector BLOB NOT NULL,
        computed_at INTEGER NOT NULL
      )
    ''');
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
      // Local rows only — a rescan must never touch online tracks
      // (their media_id is NULL anyway).
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
        await txn.delete('tracks',
            where: "media_id = ? AND source = 'local'", whereArgs: [mediaId]);
        changes++;
      }
    });
    return changes;
  }

  /// Drops **local** tracks whose file is gone from disk. Android's
  /// MediaStore keeps stale rows after a file is deleted (until its own
  /// media scan catches up), so those ghosts survive [syncScannedTracks]
  /// and show up as unplayable songs — verifying the path on disk removes
  /// them for good. Scoped to `source = 'local'`: an online track with a
  /// missing download must keep its row (it can still stream), so it's not
  /// touched here.
  Future<int> pruneMissingLocalFiles() async {
    final rows = await _db.query('tracks',
        columns: ['id', 'file_path'],
        where: "source = 'local' AND file_path IS NOT NULL");
    var removed = 0;
    for (final r in rows) {
      final path = r['file_path'] as String?;
      if (path == null || File(path).existsSync()) continue;
      await _db.delete('tracks', where: 'id = ?', whereArgs: [r['id']]);
      removed++;
    }
    return removed;
  }

  Future<void> setAlbumArt(int albumId, String path) => _db.update(
      'tracks', {'album_art_path': path},
      where: 'album_id = ?', whereArgs: [albumId]);

  /// Per-track art for online rows (they all share album_id 0, so the
  /// album-wide setter would stamp every online track at once).
  Future<void> setTrackArt(int trackId, String path) => _db.update(
      'tracks', {'album_art_path': path},
      where: 'id = ?', whereArgs: [trackId]);

  /// Marks an online track as downloaded: playback short-circuits to
  /// the file while the row keeps its online identity. A null [path]
  /// clears the download (back to streaming).
  Future<void> setFilePath(int trackId, String? path) => _db.update(
      'tracks', {'file_path': path},
      where: 'id = ?', whereArgs: [trackId]);

  /// Upserts a search result into the library (keyed source+sourceId)
  /// and returns the real row. Runs at the moment of interaction —
  /// play, queue, like, playlist — so every downstream system only
  /// ever sees real rows (ARCHITECTURE-ONLINE.md §3.3).
  Future<Track> ensureOnlineTrack(OnlineSearchResult result) async {
    final existing = await _db.query('tracks',
        where: 'source = ? AND source_id = ?',
        whereArgs: [result.source.name, result.sourceId],
        limit: 1);
    if (existing.isNotEmpty) return Track.fromRow(existing.first);

    final id = await _db.insert('tracks', {
      'title': result.title,
      'artist': result.artist,
      'album': result.album,
      'duration_ms': result.duration.inMilliseconds,
      'source': result.source.name,
      'source_id': result.sourceId,
      'art_url': result.artUrl,
    });
    final rows =
        await _db.query('tracks', where: 'id = ?', whereArgs: [id], limit: 1);
    return Track.fromRow(rows.first);
  }

  Future<void> setLiked(int trackId, bool liked) => _db.update(
      'tracks', {'liked': liked ? 1 : 0},
      where: 'id = ?', whereArgs: [trackId]);

  Future<void> recordPlay(int trackId) => _db.rawUpdate(
      'UPDATE tracks SET play_count = play_count + 1, last_played = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, trackId]);

  /// Most recently played tracks, newest first — the Home "Jump back
  /// in" shelf.
  Future<List<Track>> recentlyPlayed({int limit = 20}) async {
    final rows = await _db.query('tracks',
        where: 'last_played IS NOT NULL',
        orderBy: 'last_played DESC',
        limit: limit);
    return rows.map(Track.fromRow).toList();
  }

  // --- Recommendation signals (M38a) ---

  /// A track abandoned within the first ~20 s — a negative vote.
  Future<void> recordSkip(int trackId) => _db.rawUpdate(
      'UPDATE tracks SET skip_count = skip_count + 1 WHERE id = ?',
      [trackId]);

  /// One observed transition "listened to [fromId], then started [toId]".
  Future<void> recordCoPlay(int fromId, int toId) => _db.rawInsert('''
      INSERT INTO co_play (from_id, to_id, count) VALUES (?, ?, 1)
      ON CONFLICT(from_id, to_id) DO UPDATE SET count = count + 1
    ''', [fromId, toId]);

  /// Every observed transition out of [fromId]: {to_id: count}.
  Future<Map<int, int>> coPlaysFrom(int fromId) async {
    final rows = await _db
        .query('co_play', where: 'from_id = ?', whereArgs: [fromId]);
    return {
      for (final r in rows) r['to_id'] as int: r['count'] as int,
    };
  }

  /// The full transition matrix, for the recommender's batch scoring.
  Future<List<Map<String, Object?>>> allCoPlays() => _db.query('co_play');

  Future<void> saveTrackFeatures(
          int trackId, int version, Uint8List vector) =>
      _db.insert(
        'track_features',
        {
          'track_id': trackId,
          'version': version,
          'vector': vector,
          'computed_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<bool> hasTrackFeatures(int trackId, int version) async {
    final rows = await _db.query('track_features',
        columns: ['track_id'],
        where: 'track_id = ? AND version = ?',
        whereArgs: [trackId, version],
        limit: 1);
    return rows.isNotEmpty;
  }

  /// All feature vectors of [version]: {track_id: raw float32 bytes}.
  Future<Map<int, Uint8List>> allTrackFeatures(int version) async {
    final rows = await _db.query('track_features',
        where: 'version = ?', whereArgs: [version]);
    return {
      for (final r in rows)
        r['track_id'] as int: r['vector'] as Uint8List,
    };
  }

  /// skip_count per track (kept out of the Track model — only the
  /// recommender cares).
  Future<Map<int, int>> skipCounts() async {
    final rows = await _db.query('tracks',
        columns: ['id', 'skip_count'], where: 'skip_count > 0');
    return {
      for (final r in rows) r['id'] as int: r['skip_count'] as int,
    };
  }

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

  /// Sets or clears (null) the user-picked playlist cover image.
  Future<void> setPlaylistCover(int playlistId, String? path) =>
      _db.update('playlists', {'cover_image_path': path},
          where: 'id = ?', whereArgs: [playlistId]);

  /// Persists a drag-reorder: positions are rewritten to match the
  /// given full track-id order.
  Future<void> reorderPlaylist(
      int playlistId, List<int> orderedTrackIds) async {
    final batch = _db.batch();
    for (var i = 0; i < orderedTrackIds.length; i++) {
      batch.update('playlist_tracks', {'position': i},
          where: 'playlist_id = ? AND track_id = ?',
          whereArgs: [playlistId, orderedTrackIds[i]]);
    }
    await batch.commit(noResult: true);
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
