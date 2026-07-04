import 'dart:async';

import '../../library/models/track.dart';
import '../models/online_search_result.dart';
import '../music_provider.dart';
import 'import_models.dart';
import 'spotify_playlist_source.dart';
import 'yt_playlist_source.dart';

/// Orchestrates a playlist import: parse the URL, fetch the track list,
/// and (for Spotify) match every entry to a playable YouTube/JioSaavn
/// result. Emits [ImportProgress] as it goes. Never throws — a failure
/// ends with [ImportPhase.failed].
class PlaylistImporter {
  PlaylistImporter({Map<TrackSource, MusicProvider>? providers})
      : _providers = providers ?? musicProviderRegistry;

  final Map<TrackSource, MusicProvider> _providers;

  /// Confidence at/above which a Spotify match is auto-accepted; below
  /// it, the track goes to the review sheet as a "miss" (with candidates).
  static const _acceptThreshold = 0.55;

  Stream<ImportProgress> progress(String url) => _controller.stream;
  final _controller = StreamController<ImportProgress>.broadcast();

  void _emit(ImportProgress p) {
    if (!_controller.isClosed) _controller.add(p);
  }

  Future<ImportResult?> run(String url) async {
    final source = detectImportSource(url);
    try {
      switch (source) {
        case ImportSource.youtube:
          return await _runYouTube(url);
        case ImportSource.spotify:
          return await _runSpotify(url);
        case ImportSource.unknown:
          _emit(const ImportProgress(phase: ImportPhase.failed));
          return null;
      }
    } catch (_) {
      _emit(const ImportProgress(phase: ImportPhase.failed));
      return null;
    } finally {
      await _controller.close();
    }
  }

  Future<ImportResult?> _runYouTube(String url) async {
    _emit(const ImportProgress(phase: ImportPhase.fetching));
    final (name, entries) = await YtPlaylistSource().fetch(
      url,
      onProgress: (n) =>
          _emit(ImportProgress(phase: ImportPhase.fetching, fetched: n)),
    );
    if (entries.isEmpty) {
      _emit(const ImportProgress(phase: ImportPhase.failed));
      return null;
    }
    // YouTube entries are already playable — no matching.
    final matches = [
      for (final e in entries)
        ImportMatch(
          source: e,
          result: youtubeResultOf(e),
          confidence: 1,
        ),
    ];
    _emit(ImportProgress(
        phase: ImportPhase.done,
        total: entries.length,
        matched: entries.length));
    return ImportResult(
        playlistName: name, matches: matches, fromSource: 'YouTube');
  }

  Future<ImportResult?> _runSpotify(String url) async {
    _emit(const ImportProgress(phase: ImportPhase.fetching));
    final (name, entries) = await SpotifyPlaylistSource().fetch(url);
    if (entries.isEmpty) {
      _emit(const ImportProgress(phase: ImportPhase.failed));
      return null;
    }

    final matches = <ImportMatch>[];
    var matched = 0;
    for (var i = 0; i < entries.length; i++) {
      final m = await _match(entries[i]);
      matches.add(m);
      if (m.matched) matched++;
      _emit(ImportProgress(
        phase: ImportPhase.matching,
        fetched: i + 1,
        total: entries.length,
        matched: matched,
      ));
      // Be polite to the provider APIs.
      await Future.delayed(const Duration(milliseconds: 120));
    }
    _emit(ImportProgress(
        phase: ImportPhase.done, total: entries.length, matched: matched));
    return ImportResult(
        playlistName: name, matches: matches, fromSource: 'Spotify');
  }

  /// Searches JioSaavn then YouTube, scores candidates, returns the best
  /// match (auto-accepted) or an unmatched result carrying candidates.
  Future<ImportMatch> _match(ImportedTrack want) async {
    final query = '${want.title} ${want.artist}'.trim();
    final candidates = <OnlineSearchResult>[];
    // Saavn first (licensed CBR), then YouTube — matches the resolver's
    // quality preference.
    for (final src in const [TrackSource.saavn, TrackSource.youtube]) {
      final provider = _providers[src];
      if (provider == null) continue;
      try {
        final hits = await provider.search(query);
        candidates.addAll(hits.take(5));
      } catch (_) {
        // best-effort; try the next provider
      }
    }
    if (candidates.isEmpty) return ImportMatch(source: want);

    candidates.sort((a, b) => matchScore(want, b).compareTo(matchScore(want, a)));
    final best = candidates.first;
    final score = matchScore(want, best);
    return ImportMatch(
      source: want,
      result: score >= _acceptThreshold ? best : null,
      confidence: score,
      candidates: candidates.take(5).toList(),
    );
  }
}
