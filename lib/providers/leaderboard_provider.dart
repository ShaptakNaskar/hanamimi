import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../reco/taste_fingerprint.dart';
import 'library_provider.dart';
import 'stats_provider.dart';
import 'theme_provider.dart';

/// Base of the Hanamimi stats/leaderboard API (my portfolio backend).
const _apiBase = 'https://sappy-dir.vercel.app/api/hanamimi';

/// One leaderboard row (top-10 listeners by total time).
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.nickname,
    required this.device,
    required this.totalSeconds,
    required this.totalSongs,
    required this.localSeconds,
    required this.youtubeSeconds,
    required this.saavnSeconds,
    this.compat,
    this.isSelf = false,
  });

  final String nickname;
  final String device; // '' when the user shared name only
  final int totalSeconds;
  final int totalSongs;
  final int localSeconds;
  final int youtubeSeconds;
  final int saavnSeconds;

  /// Taste compatibility with the caller, 0–100 (3.0 #5). Null when
  /// either side hasn't shared a fingerprint (or this row is you).
  final int? compat;
  final bool isSelf;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> j) =>
      LeaderboardEntry(
        nickname: j['nickname'] as String? ?? 'Anonymous',
        device: j['device'] as String? ?? '',
        totalSeconds: (j['totalSeconds'] as num?)?.toInt() ?? 0,
        totalSongs: (j['totalSongs'] as num?)?.toInt() ?? 0,
        localSeconds: (j['localSeconds'] as num?)?.toInt() ?? 0,
        youtubeSeconds: (j['youtubeSeconds'] as num?)?.toInt() ?? 0,
        saavnSeconds: (j['saavnSeconds'] as num?)?.toInt() ?? 0,
        compat: (j['compat'] as num?)?.toInt(),
        isSelf: j['self'] == true,
      );
}

/// Persistent, random client id so re-uploads update the same row rather
/// than duplicating. Not tied to any device identifier.
class StatsClientId {
  static const _key = 'stats_client_id';

  static String get(dynamic prefs) {
    final existing = prefs.getString(_key) as String?;
    if (existing != null && existing.isNotEmpty) return existing;
    final rnd = Random.secure();
    final id = List.generate(16, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    prefs.setString(_key, id);
    return id;
  }
}

/// The device make + model, for the *optional* device field. Returns ''
/// on platforms/failures — the user can always share name only.
Future<String> deviceMakeModel() async {
  try {
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      final maker = a.manufacturer.isEmpty
          ? ''
          : a.manufacturer[0].toUpperCase() + a.manufacturer.substring(1);
      return '$maker ${a.model}'.trim();
    }
    if (Platform.isLinux) {
      final l = await info.linuxInfo;
      return l.prettyName;
    }
    if (Platform.isWindows) {
      final w = await info.windowsInfo;
      return w.productName;
    }
  } catch (_) {}
  return '';
}

/// Whether the user has connected to the leaderboard (opted in). The
/// nickname's presence is the consent record.
class LeaderboardOptIn {
  static const _nickKey = 'leaderboard_nickname';
  static const _shareDeviceKey = 'leaderboard_share_device';
  static const _shareTasteKey = 'leaderboard_share_taste';
}

/// Current opt-in state, exposed to the UI.
class LeaderboardAccount {
  const LeaderboardAccount({
    required this.nickname,
    required this.shareDevice,
    this.shareTaste = false,
  });
  final String nickname; // '' = not opted in
  final bool shareDevice;

  /// 3.0 #5: consent to upload the MinHash taste fingerprint (never
  /// artist names) for the compatibility feature. Its own consent line
  /// on top of the leaderboard opt-in.
  final bool shareTaste;
  bool get optedIn => nickname.isNotEmpty;

  static const none = LeaderboardAccount(nickname: '', shareDevice: false);
}

class LeaderboardNotifier extends Notifier<LeaderboardAccount> {
  @override
  LeaderboardAccount build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return LeaderboardAccount(
      nickname: prefs.getString(LeaderboardOptIn._nickKey) ?? '',
      shareDevice: prefs.getBool(LeaderboardOptIn._shareDeviceKey) ?? false,
      shareTaste: prefs.getBool(LeaderboardOptIn._shareTasteKey) ?? false,
    );
  }

  /// Opts in and uploads immediately. [shareDevice] adds the make/model;
  /// [shareTaste] adds the irreversible taste fingerprint.
  /// Returns true on a successful upload.
  Future<bool> connect(String nickname,
      {required bool shareDevice, bool shareTaste = false}) async {
    final prefs = ref.read(sharedPrefsProvider);
    final trimmed = nickname.trim();
    if (trimmed.isEmpty) return false;
    await prefs.setString(LeaderboardOptIn._nickKey, trimmed);
    await prefs.setBool(LeaderboardOptIn._shareDeviceKey, shareDevice);
    await prefs.setBool(LeaderboardOptIn._shareTasteKey, shareTaste);
    state = LeaderboardAccount(
        nickname: trimmed,
        shareDevice: shareDevice,
        shareTaste: shareTaste);
    return upload();
  }

  /// Stops sharing: forgets the nickname locally. (The server row is left
  /// as-is; a future call could add a delete endpoint.)
  Future<void> disconnect() async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.remove(LeaderboardOptIn._nickKey);
    await prefs.remove(LeaderboardOptIn._shareDeviceKey);
    await prefs.remove(LeaderboardOptIn._shareTasteKey);
    state = LeaderboardAccount.none;
  }

  /// Pushes the current stats to the leaderboard. No-op (false) when not
  /// opted in — nothing is ever sent without an explicit nickname.
  Future<bool> upload() async {
    final account = state;
    if (!account.optedIn) return false;
    try {
      final prefs = ref.read(sharedPrefsProvider);
      final stats = ref.read(listenStatsProvider);
      final device = account.shareDevice ? await deviceMakeModel() : '';

      // Taste fingerprint: built fresh off the local history log at
      // upload time — no separate stored aggregate to drift out of
      // sync. Sending explicit null clears a previously shared one.
      Object? signature;
      if (account.shareTaste) {
        final repo = await ref.read(libraryRepositoryProvider.future);
        signature = buildTasteSignature(await repo.artistSeconds());
      }

      final body = {
        'clientId': StatsClientId.get(prefs),
        'nickname': account.nickname,
        'device': device,
        ...stats.toJson(),
        'signature': signature,
      };
      final res = await http
          .post(Uri.parse('$_apiBase/stats'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

final leaderboardAccountProvider =
    NotifierProvider<LeaderboardNotifier, LeaderboardAccount>(
        LeaderboardNotifier.new);

/// Top-10 listeners. Refreshable from the leaderboard screen. The
/// clientId rides along so the server can annotate each row with taste
/// compatibility vs the caller (3.0 #5) — percent only, signatures
/// never leave the server.
final leaderboardProvider =
    FutureProvider.autoDispose<List<LeaderboardEntry>>((ref) async {
  final prefs = ref.watch(sharedPrefsProvider);
  final clientId = StatsClientId.get(prefs);
  final res = await http
      .get(Uri.parse('$_apiBase/leaderboard?clientId=$clientId'))
      .timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) return const [];
  final data = jsonDecode(res.body);
  if (data is! List) return const [];
  return [
    for (final e in data)
      if (e is Map<String, dynamic>) LeaderboardEntry.fromJson(e),
  ];
});
