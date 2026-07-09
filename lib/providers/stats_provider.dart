import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/models/track.dart';
import 'audio_provider.dart';
import 'theme_provider.dart';

/// Per-platform + cumulative listening stats, tracked locally. Time
/// recording is automatic (not gated on consent); only *sending* the
/// numbers to the leaderboard is opt-in (see the stats upload flow).
class ListenStats {
  const ListenStats({
    this.localSeconds = 0,
    this.youtubeSeconds = 0,
    this.saavnSeconds = 0,
    this.localSongs = 0,
    this.youtubeSongs = 0,
    this.saavnSongs = 0,
  });

  final int localSeconds;
  final int youtubeSeconds;
  final int saavnSeconds;
  final int localSongs;
  final int youtubeSongs;
  final int saavnSongs;

  int get totalSeconds => localSeconds + youtubeSeconds + saavnSeconds;
  int get totalSongs => localSongs + youtubeSongs + saavnSongs;
  int get totalMinutes => totalSeconds ~/ 60;

  int minutesFor(TrackSource s) => secondsFor(s) ~/ 60;
  int secondsFor(TrackSource s) => switch (s) {
        TrackSource.local => localSeconds,
        TrackSource.youtube => youtubeSeconds,
        TrackSource.saavn => saavnSeconds,
      };
  int songsFor(TrackSource s) => switch (s) {
        TrackSource.local => localSongs,
        TrackSource.youtube => youtubeSongs,
        TrackSource.saavn => saavnSongs,
      };

  ListenStats copyWith({
    int? localSeconds,
    int? youtubeSeconds,
    int? saavnSeconds,
    int? localSongs,
    int? youtubeSongs,
    int? saavnSongs,
  }) =>
      ListenStats(
        localSeconds: localSeconds ?? this.localSeconds,
        youtubeSeconds: youtubeSeconds ?? this.youtubeSeconds,
        saavnSeconds: saavnSeconds ?? this.saavnSeconds,
        localSongs: localSongs ?? this.localSongs,
        youtubeSongs: youtubeSongs ?? this.youtubeSongs,
        saavnSongs: saavnSongs ?? this.saavnSongs,
      );

  /// The payload shape the leaderboard backend expects.
  Map<String, dynamic> toJson() => {
        'localSeconds': localSeconds,
        'youtubeSeconds': youtubeSeconds,
        'saavnSeconds': saavnSeconds,
        'localSongs': localSongs,
        'youtubeSongs': youtubeSongs,
        'saavnSongs': saavnSongs,
        'totalSeconds': totalSeconds,
        'totalSongs': totalSongs,
      };
}

class ListenStatsNotifier extends Notifier<ListenStats> {
  static const _kLocalSec = 'stats_local_seconds';
  static const _kYtSec = 'stats_youtube_seconds';
  static const _kSaavnSec = 'stats_saavn_seconds';
  static const _kLocalSongs = 'stats_local_songs';
  static const _kYtSongs = 'stats_youtube_songs';
  static const _kSaavnSongs = 'stats_saavn_songs';

  Timer? _timer;

  // Existing installs already tracked a cumulative total for the mascot
  // ('listen_seconds'). Seed the new per-platform stats from it once, so
  // the ~hours you've already listened show up immediately instead of
  // starting from zero. Attributed to local — the source split wasn't
  // recorded before, and for existing users it was overwhelmingly local.
  static const _legacyTotalKey = 'listen_seconds';
  static const _seededKey = 'stats_seeded_from_legacy';

  @override
  ListenStats build() {
    final prefs = ref.read(sharedPrefsProvider);
    final engine = ref.watch(audioHandlerProvider).engine;

    if (!(prefs.getBool(_seededKey) ?? false)) {
      final legacy = prefs.getInt(_legacyTotalKey) ?? 0;
      final noStatsYet = (prefs.getInt(_kLocalSec) ?? 0) == 0 &&
          (prefs.getInt(_kYtSec) ?? 0) == 0 &&
          (prefs.getInt(_kSaavnSec) ?? 0) == 0;
      if (legacy > 0 && noStatsYet) {
        prefs.setInt(_kLocalSec, legacy);
      }
      prefs.setBool(_seededKey, true);
    }

    // +1 song per track start, attributed to its source.
    final startSub = engine.trackStarted.stream.listen((track) {
      switch (track.source) {
        case TrackSource.local:
          state = state.copyWith(localSongs: state.localSongs + 1);
          prefs.setInt(_kLocalSongs, state.localSongs);
        case TrackSource.youtube:
          state = state.copyWith(youtubeSongs: state.youtubeSongs + 1);
          prefs.setInt(_kYtSongs, state.youtubeSongs);
        case TrackSource.saavn:
          state = state.copyWith(saavnSongs: state.saavnSongs + 1);
          prefs.setInt(_kSaavnSongs, state.saavnSongs);
      }
    });

    // +5s to the current track's source while playing.
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      final audio = ref.read(audioStateProvider).value;
      if (!(audio?.isPlaying ?? false)) return;
      final source = audio?.currentTrack?.source ?? TrackSource.local;
      switch (source) {
        case TrackSource.local:
          state = state.copyWith(localSeconds: state.localSeconds + 5);
          prefs.setInt(_kLocalSec, state.localSeconds);
        case TrackSource.youtube:
          state = state.copyWith(youtubeSeconds: state.youtubeSeconds + 5);
          prefs.setInt(_kYtSec, state.youtubeSeconds);
        case TrackSource.saavn:
          state = state.copyWith(saavnSeconds: state.saavnSeconds + 5);
          prefs.setInt(_kSaavnSec, state.saavnSeconds);
      }
    });

    ref.onDispose(() {
      _timer?.cancel();
      startSub.cancel();
    });

    return ListenStats(
      localSeconds: prefs.getInt(_kLocalSec) ?? 0,
      youtubeSeconds: prefs.getInt(_kYtSec) ?? 0,
      saavnSeconds: prefs.getInt(_kSaavnSec) ?? 0,
      localSongs: prefs.getInt(_kLocalSongs) ?? 0,
      youtubeSongs: prefs.getInt(_kYtSongs) ?? 0,
      saavnSongs: prefs.getInt(_kSaavnSongs) ?? 0,
    );
  }
}

final listenStatsProvider =
    NotifierProvider<ListenStatsNotifier, ListenStats>(
        ListenStatsNotifier.new);
