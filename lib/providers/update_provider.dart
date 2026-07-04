import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Which release channel this build follows. The plus build only ever
/// offers plus releases (tags `plus-v…`).
const _tagPrefix = 'plus-v';
const _repo = 'ShaptakNaskar/hanamimi';

/// A newer build published by the CI pipeline (GitHub Releases).
class AppUpdate {
  const AppUpdate({
    required this.versionName,
    required this.runNumber,
    required this.changelog,
    required this.apkUrl,
    required this.sizeBytes,
  });

  final String versionName;

  /// CI run number == versionCode; monotonic, what we compare.
  final int runNumber;
  final String changelog;
  final String apkUrl;
  final int sizeBytes;
}

/// Checks GitHub Releases for a newer plus build. Null = up to date (or
/// check failed — never nag on network errors). The CI tags releases
/// `plus-v<version>-<run>` with versionCode = run number, so "newer"
/// is a plain integer comparison against this build's versionCode.
final updateCheckProvider = FutureProvider<AppUpdate?>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(info.buildNumber) ?? 0;

    final res = await http.get(
      Uri.parse('https://api.github.com/repos/$_repo/releases?per_page=15'),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;

    final releases = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    AppUpdate? best;
    for (final r in releases) {
      final tag = r['tag_name'] as String? ?? '';
      if (!tag.startsWith(_tagPrefix)) continue;
      // plus-v1.0.0-42 → run number after the final dash.
      final run = int.tryParse(tag.split('-').last) ?? 0;
      if (run <= currentCode || run <= (best?.runNumber ?? 0)) continue;

      // Prefer the arm64 asset (every current device); universal fallback.
      final assets = (r['assets'] as List? ?? []).cast<Map<String, dynamic>>();
      Map<String, dynamic>? pick(String needle) {
        for (final a in assets) {
          if ((a['name'] as String? ?? '').contains(needle)) return a;
        }
        return null;
      }

      final asset = pick('arm64-v8a') ?? pick('universal');
      if (asset == null) continue;

      best = AppUpdate(
        versionName: (r['name'] as String?) ?? tag,
        runNumber: run,
        changelog: (r['body'] as String?) ?? '',
        apkUrl: asset['browser_download_url'] as String,
        sizeBytes: (asset['size'] as num?)?.toInt() ?? 0,
      );
    }
    return best;
  } catch (_) {
    return null;
  }
});

/// Thin wrapper over the native installer channel.
class UpdaterChannel {
  static const _ch = MethodChannel('hanamimi/updater');

  static Future<bool> canInstall() async {
    try {
      return (await _ch.invokeMethod<bool>('canInstall')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openInstallPerm() async {
    try {
      await _ch.invokeMethod('openInstallPerm');
    } catch (_) {}
  }

  static Future<bool> install(String path) async {
    try {
      return (await _ch.invokeMethod<bool>('install', {'path': path})) ??
          false;
    } catch (_) {
      return false;
    }
  }
}

/// Streams download progress for the update APK, then returns the file
/// path. Throws on failure (the dialog shows the error state).
Stream<double> downloadUpdate(AppUpdate update, void Function(String) onDone) async* {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/hanamimi-update-${update.runNumber}.apk');

  final client = http.Client();
  try {
    final req = http.Request('GET', Uri.parse(update.apkUrl))
      ..followRedirects = true;
    final res = await client.send(req);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final total = res.contentLength ?? update.sizeBytes;
    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) yield received / total;
      }
    } finally {
      await sink.close();
    }
    onDone(file.path);
  } finally {
    client.close();
  }
}
