import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../library/library_repository.dart';
import '../library/models/track.dart';
import '../utils/track_identity.dart';

/// Tier-0 backup (3.0 #8): everything that makes this install *yours* —
/// history, settings, playlists, favorites — in one ZIP. Local file, no
/// server, works offline. (The plus edition adds a passphrase-encrypted
/// cloud tier on top of this same bundle; this edition is local-only.)
///
/// Tracks are stored as identity *snapshots* (title/artist/duration),
/// never row ids — restore re-links against the new device's freshly
/// scanned library via the shared identity key (#7), so it works even
/// though every file path changed.
class BackupService {
  /// Bump on breaking bundle changes and keep import able to read every
  /// older version (the 2.1.1 duplicate-column lesson, applied to
  /// bundles: a 3.2 app importing a 3.0 bundle must not explode).
  static const schemaVersion = 1;

  /// Prefs worth carrying to a new device. Deliberately excludes
  /// device-specific paths (music/excluded folders) and dev toggles.
  static const _prefsAllowlist = [
    'theme_id',
    'night_mode',
    'crossfade_seconds',
    'slow_dance',
    'melt_away',
    'smart_shuffle',
    'autoplay_continuation',
    'mystery_date',
    'blackout_style',
    'accessory',
    'buddies_disabled',
    'cat_follow',
    'cat_mode',
    'cat_unlocked',
    'listen_seconds',
    'nerd_mode',
    'led_vu_discrete',
    'vu_split',
    'visualizer_reactivity',
    'visualizer_sensitivity',
    'visualizer_style_override',
  ];

  static Map<String, Object?> _snapshotTrack(Track t) => {
        'title': t.title,
        'artist': t.artist,
        'album': t.album,
        'durationMs': t.duration.inMilliseconds,
      };

  /// Builds the ZIP bytes. Pure data — callers decide where it goes
  /// (share sheet on Android).
  static Future<Uint8List> buildBundle({
    required SharedPreferences prefs,
    required LibraryRepository repo,
  }) async {
    final manifest = {
      'schemaVersion': schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'app': 'hanamimi',
    };

    final settings = <String, Object?>{
      for (final key in _prefsAllowlist)
        if (prefs.get(key) != null) key: prefs.get(key),
    };

    final history = await repo.allListenHistory();

    final tracks = await repo.allTracks();
    final byId = {for (final t in tracks) t.id: t};
    final favorites = [
      for (final t in tracks)
        if (t.liked) _snapshotTrack(t),
    ];
    final playlists = [
      for (final p in await repo.allPlaylists())
        {
          'name': p.name,
          'coverColor': p.coverColor.toARGB32(),
          'createdAt': p.createdAt.millisecondsSinceEpoch,
          'tracks': [
            for (final id in p.trackIds)
              if (byId[id] != null) _snapshotTrack(byId[id]!),
          ],
        },
    ];

    final archive = Archive();
    void addJson(String name, Object data) {
      final bytes = utf8.encode(jsonEncode(data));
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    addJson('manifest.json', manifest);
    addJson('settings.json', settings);
    addJson('history.json', history);
    addJson('favorites.json', favorites);
    addJson('playlists.json', playlists);

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// What a restore actually did — surfaced in the UI so "it worked"
  /// is a claim with numbers behind it.
  static Future<BackupRestoreSummary> importBundle(
    Uint8List zipBytes, {
    required SharedPreferences prefs,
    required LibraryRepository repo,
  }) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);

    Object? readJson(String name) {
      final f = archive.findFile(name);
      if (f == null) return null;
      return jsonDecode(utf8.decode(f.content as List<int>));
    }

    final manifest = readJson('manifest.json');
    if (manifest is! Map || manifest['app'] != 'hanamimi') {
      throw const BackupFormatException('Not a Hanamimi backup');
    }
    final version = (manifest['schemaVersion'] as num?)?.toInt() ?? 0;
    if (version > schemaVersion) {
      throw const BackupFormatException(
          'This backup is from a newer Hanamimi — update the app first');
    }

    // Settings first: everything below may read them.
    var settingsRestored = 0;
    final settings = readJson('settings.json');
    if (settings is Map) {
      for (final e in settings.entries) {
        final key = e.key as String;
        if (!_prefsAllowlist.contains(key)) continue;
        final v = e.value;
        if (v is bool) {
          await prefs.setBool(key, v);
        } else if (v is int) {
          await prefs.setInt(key, v);
        } else if (v is double) {
          await prefs.setDouble(key, v);
        } else if (v is String) {
          await prefs.setString(key, v);
        } else if (v is List) {
          await prefs.setStringList(key, v.cast<String>());
        } else {
          continue;
        }
        settingsRestored++;
      }
    }

    // History: append-only, deduped inside the repo.
    var historyAdded = 0;
    final history = readJson('history.json');
    if (history is List) {
      historyAdded = await repo.importListenHistory([
        for (final r in history)
          if (r is Map) r.map((k, v) => MapEntry(k as String, v as Object?)),
      ]);
    }

    // Track re-linking by identity key over the current library.
    final library = await repo.allTracks();
    final byIdentity = <String, Track>{
      for (final t in library)
        identityKey(title: t.title, artist: t.artist, duration: t.duration):
            t,
    };

    Track? resolve(Map snap) {
      final duration =
          Duration(milliseconds: (snap['durationMs'] as num?)?.toInt() ?? 0);
      return byIdentity[identityKey(
          title: snap['title'] as String? ?? '',
          artist: snap['artist'] as String? ?? '',
          duration: duration)];
    }

    var favoritesRestored = 0;
    var favoritesMissed = 0;
    final favorites = readJson('favorites.json');
    if (favorites is List) {
      for (final snap in favorites) {
        if (snap is! Map) continue;
        final track = resolve(snap);
        if (track == null) {
          favoritesMissed++;
        } else {
          await repo.setLiked(track.id, true);
          favoritesRestored++;
        }
      }
    }

    var playlistsRestored = 0;
    var playlistTracksMissed = 0;
    final playlists = readJson('playlists.json');
    if (playlists is List) {
      final existingNames = {
        for (final p in await repo.allPlaylists()) p.name,
      };
      for (final p in playlists) {
        if (p is! Map) continue;
        final name = p['name'] as String? ?? 'Restored playlist';
        // Same-name playlist already here (double import) — skip whole.
        if (existingNames.contains(name)) continue;
        final id = await repo.createPlaylist(
            name, (p['coverColor'] as num?)?.toInt() ?? 0xFFF4A7B9);
        playlistsRestored++;
        final tracks = p['tracks'];
        if (tracks is List) {
          for (final snap in tracks) {
            if (snap is! Map) continue;
            final track = resolve(snap);
            if (track == null) {
              playlistTracksMissed++;
            } else {
              await repo.addToPlaylist(id, track.id);
            }
          }
        }
      }
    }

    return BackupRestoreSummary(
      settingsRestored: settingsRestored,
      historyAdded: historyAdded,
      favoritesRestored: favoritesRestored,
      favoritesMissed: favoritesMissed,
      playlistsRestored: playlistsRestored,
      playlistTracksMissed: playlistTracksMissed,
    );
  }
}

class BackupRestoreSummary {
  const BackupRestoreSummary({
    required this.settingsRestored,
    required this.historyAdded,
    required this.favoritesRestored,
    required this.favoritesMissed,
    required this.playlistsRestored,
    required this.playlistTracksMissed,
  });

  final int settingsRestored;
  final int historyAdded;
  final int favoritesRestored;
  final int favoritesMissed;
  final int playlistsRestored;
  final int playlistTracksMissed;

  String describe() {
    final parts = <String>[
      if (historyAdded > 0) '$historyAdded plays',
      if (favoritesRestored > 0) '$favoritesRestored favorites',
      if (playlistsRestored > 0) '$playlistsRestored playlists',
      if (settingsRestored > 0) 'settings',
    ];
    final missed = favoritesMissed + playlistTracksMissed;
    final main = parts.isEmpty
        ? 'Nothing new to restore'
        : 'Restored ${parts.join(', ')}';
    return missed > 0
        ? '$main — $missed songs aren\'t in this library (yet)'
        : main;
  }
}

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}
