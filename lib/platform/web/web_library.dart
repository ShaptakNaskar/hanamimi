import 'dart:async';

import 'package:web/web.dart' as web;

import '../../library/models/track.dart';
import 'web_media.dart';
import 'web_tags.dart';

/// One picked folder (or loose-file selection) and the tracks minted
/// from it — the web edition's whole "library" is a list of these, held
/// in memory for the tab's lifetime. Nothing touches a server.
class WebFolder {
  const WebFolder({required this.name, required this.tracks});

  final String name;
  final List<Track> tracks;
}

/// Import progress for the sidebar ("Reading tags… 40/120").
class ImportProgress {
  const ImportProgress(this.done, this.total);

  final int done;
  final int total;
}

class WebImporter {
  static var _nextId = 1;

  /// Reads tags + duration for [files] and mints [Track]s. [onProgress]
  /// ticks per file. Files the browser can't even read a duration for
  /// are still imported (duration zero) — just_audio will surface the
  /// real length or the error at play time.
  static Future<List<Track>> import(
    List<web.File> files, {
    void Function(ImportProgress)? onProgress,
  }) async {
    final tracks = <Track>[];
    var done = 0;
    for (final file in files) {
      try {
        tracks.add(await _importOne(file));
      } catch (_) {
        // One unreadable file must not sink the folder.
      }
      done++;
      onProgress?.call(ImportProgress(done, files.length));
    }
    // Album, then track number, then name — a folder of albums reads in
    // playing order instead of raw directory order.
    tracks.sort((a, b) {
      final album = a.album.toLowerCase().compareTo(b.album.toLowerCase());
      if (album != 0) return album;
      final n = (a.trackNumber ?? 1 << 20).compareTo(b.trackNumber ?? 1 << 20);
      if (n != 0) return n;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return tracks;
  }

  static Future<Track> _importOne(web.File file) async {
    final url = WebMedia.urlFor(file);

    // Tags live in the head (ID3v2/FLAC/MP4-front/Ogg) or the tail
    // (ID3v1, moov-at-end). 512 KB of head covers nearly all embedded
    // art; 256 KB of tail covers end-moov files.
    final head = await WebMedia.readHead(file, 512 * 1024);
    final tail = file.size > 512 * 1024
        ? await WebMedia.readTail(file, 256 * 1024)
        : null;
    final tags = parseTags(head, tail: tail);

    String? artUrl;
    final artBytes = tags.artBytes;
    if (artBytes != null && artBytes.isNotEmpty) {
      artUrl = WebMedia.artUrl(artBytes, tags.artMime ?? 'image/jpeg');
    }

    final fromName = _titleArtistFromName(file.name);
    final duration = await WebMedia.probeDuration(url) ?? Duration.zero;

    return Track(
      id: _nextId++,
      // Stable across sessions for the same file: the FFT cache key and
      // liked-song identity both build on it.
      mediaId: Object.hash(file.name, file.size),
      title: tags.title ?? fromName.$2,
      artist: tags.artist ?? fromName.$1 ?? 'Unknown artist',
      album: tags.album ?? 'Unknown album',
      albumId: Object.hash(tags.album ?? '', tags.artist ?? ''),
      albumArtPath: artUrl,
      filePath: url,
      duration: duration,
      trackNumber: tags.trackNumber,
    );
  }

  /// "Artist - Title.mp3" → (Artist, Title); otherwise the bare stem.
  static (String?, String) _titleArtistFromName(String name) {
    var stem = name;
    final dot = stem.lastIndexOf('.');
    if (dot > 0) stem = stem.substring(0, dot);
    stem = stem.replaceAll('_', ' ').trim();
    final dash = stem.indexOf(RegExp(r'\s[-–—]\s'));
    if (dash > 0) {
      final artist = stem.substring(0, dash).trim();
      final title = stem.substring(dash + 3).trim();
      if (artist.isNotEmpty && title.isNotEmpty) return (artist, title);
    }
    return (null, stem);
  }
}
