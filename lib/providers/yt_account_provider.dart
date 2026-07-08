import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/models/track.dart';
import '../reco/secret_box.dart';
import '../reco/yt_session.dart';
import 'audio_provider.dart';
import 'theme_provider.dart';

/// Tier 3 connection + policy state.
class YtAccount {
  const YtAccount({
    required this.cookie,
    required this.reportPlays,
  });

  /// Empty until the user signs in through the consent WebView.
  final String cookie;

  /// "Report plays to your YT history" — the feedback loop. OFF by
  /// default: read-only mode means the cookie signs feed reads only and
  /// playback stays anonymous (yt-dlp), so the account never streams.
  final bool reportPlays;

  bool get connected => cookie.isNotEmpty;

  static const none = YtAccount(cookie: '', reportPlays: false);

  YtAccount copyWith({String? cookie, bool? reportPlays}) => YtAccount(
        cookie: cookie ?? this.cookie,
        reportPlays: reportPlays ?? this.reportPlays,
      );
}

class YtAccountNotifier extends AsyncNotifier<YtAccount> {
  static const _connectedKey = 'yt_connected';
  static const _reportKey = 'yt_report_plays';

  @override
  Future<YtAccount> build() async {
    final prefs = ref.watch(sharedPrefsProvider);
    if (!(prefs.getBool(_connectedKey) ?? false)) return YtAccount.none;
    final cookie = await SecretBox.read() ?? '';
    if (cookie.isEmpty) return YtAccount.none;
    return YtAccount(
      cookie: cookie,
      reportPlays: prefs.getBool(_reportKey) ?? false,
    );
  }

  /// Stores the captured session cookie (encrypted) and marks connected.
  Future<void> connect(String cookie) async {
    await SecretBox.write(cookie);
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool(_connectedKey, true);
    state = AsyncData(YtAccount(
      cookie: cookie,
      reportPlays: prefs.getBool(_reportKey) ?? false,
    ));
  }

  /// Sign-out wipes the cookie from secure storage (milestone check).
  Future<void> disconnect() async {
    await SecretBox.clear();
    await ref.read(sharedPrefsProvider).setBool(_connectedKey, false);
    state = const AsyncData(YtAccount.none);
  }

  Future<void> setReportPlays(bool on) async {
    await ref.read(sharedPrefsProvider).setBool(_reportKey, on);
    final current = state.value ?? YtAccount.none;
    state = AsyncData(current.copyWith(reportPlays: on));
  }
}

final ytAccountProvider =
    AsyncNotifierProvider<YtAccountNotifier, YtAccount>(
        YtAccountNotifier.new);

/// The personalized YT Music home feed (Quick Picks songs + playlist /
/// mix cards), signed with the session cookie. Empty when not connected
/// or the session expired.
final ytHomeFeedProvider = FutureProvider<YtHomeFeed>((ref) async {
  final account = ref.watch(ytAccountProvider).value ?? YtAccount.none;
  if (!account.connected) {
    return const YtHomeFeed(songs: [], playlists: []);
  }
  return YtSession(cookie: account.cookie).homeFeed();
});

/// Reports a play to YT history, but only when connected AND the user
/// turned on the "report plays" feedback loop (off by default). This is
/// the one place playback touches the account — everything else is
/// read-only.
final ytPlayReporterProvider = Provider<void>((ref) {
  final account = ref.watch(ytAccountProvider).value ?? YtAccount.none;
  if (!account.connected || !account.reportPlays) return;
  final session = YtSession(cookie: account.cookie);
  final engine = ref.watch(audioHandlerProvider).engine;
  final sub = engine.trackStarted.stream.listen((track) {
    if (track.source == TrackSource.youtube && track.sourceId != null) {
      session.reportPlay(track.sourceId!);
    }
  });
  ref.onDispose(sub.cancel);
});
