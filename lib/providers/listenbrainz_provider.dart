import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../reco/listenbrainz.dart';
import 'audio_provider.dart';
import 'theme_provider.dart';

/// Tier 2 connection state. The token's presence IS the consent: it can
/// only get here through the consent dialog, and disconnect() wipes it.
/// Until then, no ListenBrainz code path is reachable — the milestone's
/// "zero network calls before consent".
class ListenBrainzAccount {
  const ListenBrainzAccount({
    required this.token,
    required this.host,
    required this.user,
  });

  final String token;
  final String host;
  final String user;

  bool get connected => token.isNotEmpty && user.isNotEmpty;

  static const none =
      ListenBrainzAccount(token: '', host: '', user: '');
}

class ListenBrainzNotifier extends Notifier<ListenBrainzAccount> {
  static const _tokenKey = 'lb_token';
  static const _hostKey = 'lb_host';
  static const _userKey = 'lb_user';

  @override
  ListenBrainzAccount build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return ListenBrainzAccount(
      token: prefs.getString(_tokenKey) ?? '',
      host: prefs.getString(_hostKey) ?? '',
      user: prefs.getString(_userKey) ?? '',
    );
  }

  /// Validates against the instance and stores the connection.
  /// Returns the user name, or null when the token/host is bad.
  Future<String?> connect(String token, {String? host}) async {
    final client = ListenBrainz(token: token, host: host);
    final user = await client.validate();
    if (user == null) return null;
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_hostKey, client.host);
    await prefs.setString(_userKey, user);
    state =
        ListenBrainzAccount(token: token, host: client.host, user: user);
    return user;
  }

  /// One-tap disconnect wipes the token (milestone verification).
  Future<void> disconnect() async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.remove(_tokenKey);
    await prefs.remove(_hostKey);
    await prefs.remove(_userKey);
    state = ListenBrainzAccount.none;
  }
}

final listenBrainzProvider =
    NotifierProvider<ListenBrainzNotifier, ListenBrainzAccount>(
        ListenBrainzNotifier.new);

/// Scrobbler: submits a listen once a track has genuinely been heard —
/// ListenBrainz's own guideline: 4 minutes or half the track, whichever
/// comes first. Position-based (like the skip tracker) so pauses don't
/// count. Active only while connected. Watched from app.dart.
final lbScrobblerProvider = Provider<void>((ref) {
  final account = ref.watch(listenBrainzProvider);
  if (!account.connected) return;
  final client = ListenBrainz(token: account.token, host: account.host);
  final engine = ref.watch(audioHandlerProvider).engine;

  String? currentKey;
  ({String title, String artist, String album, DateTime started})? current;
  var submitted = false;

  final posSub = engine.positionStream.listen((pos) {
    final c = current;
    if (c == null || submitted) return;
    final duration = engine.state.duration;
    final threshold = duration > Duration.zero
        ? Duration(
            milliseconds:
                (duration.inMilliseconds / 2).round().clamp(0, 240000))
        : const Duration(seconds: 240);
    if (pos >= threshold) {
      submitted = true;
      client.submitListen(
        title: c.title,
        artist: c.artist,
        album: c.album,
        listenedAt: c.started,
      );
    }
  });

  final startSub = engine.trackStarted.stream.listen((track) {
    final key = '${track.source.name}_${track.sourceId ?? track.id}';
    if (key == currentKey) return;
    currentKey = key;
    submitted = false;
    current = (
      title: track.title,
      artist: track.artist,
      album: track.album,
      started: DateTime.now(),
    );
  });

  ref.onDispose(() {
    posSub.cancel();
    startSub.cancel();
  });
});

/// Home "Weekly Jams" shelf: ListenBrainz's collaborative picks, as
/// plain (title, artist) pairs — played by resolving through YT Music
/// search at tap time.
final weeklyJamsProvider =
    FutureProvider<List<(String, String)>>((ref) async {
  final account = ref.watch(listenBrainzProvider);
  if (!account.connected) return const [];
  final client = ListenBrainz(token: account.token, host: account.host);
  return client.createdForPlaylist(account.user);
});
