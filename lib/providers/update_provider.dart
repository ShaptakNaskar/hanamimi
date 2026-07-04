import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const _repo = 'ShaptakNaskar/hanamimi';

/// The version string to show in About — read live from the built
/// package, so it always reflects what CI stamped and never needs a
/// hand-edit: e.g. "Hanamimi+ 花耳 · 1.0.3". (The internal versionCode
/// stays the CI run number for Android + the updater's newer-check.)
final appVersionLabelProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final edition =
        info.packageName.endsWith('.plus') ? 'Hanamimi+' : 'Hanamimi';
    return '$edition 花耳 · ${info.version}';
  } catch (_) {
    return 'Hanamimi 花耳';
  }
});

/// The release channel THIS build follows, derived from its own package
/// id so main and plus never cross-update: `com.hanamimi.app.plus` →
/// `plus-v…` tags, `com.hanamimi.app` → `main-v…`. Same source on both
/// branches; the installed edition decides.
String _tagPrefixFor(String packageName) =>
    packageName.endsWith('.plus') ? 'plus-v' : 'main-v';

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

/// Checks GitHub Releases for a newer build of THIS edition. Null = up to
/// date (or the check failed — never nag on network errors). The CI tags
/// releases `<branch>-v<version>-<run>` with versionCode = run number, so
/// "newer" is a plain integer comparison against this build's versionCode.
final updateCheckProvider = FutureProvider<AppUpdate?>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final currentCode = int.tryParse(info.buildNumber) ?? 0;
    final tagPrefix = _tagPrefixFor(info.packageName);
    // The device's preferred ABI, so we download the matching split APK
    // (smallest) and only fall back to the universal one.
    final abi = await UpdaterChannel.deviceAbi();

    final res = await http.get(
      Uri.parse('https://api.github.com/repos/$_repo/releases?per_page=15'),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;

    final releases = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    AppUpdate? best;
    for (final r in releases) {
      final tag = r['tag_name'] as String? ?? '';
      if (!tag.startsWith(tagPrefix)) continue;
      // <branch>-v1.0.1-42 → run number after the final dash.
      final run = int.tryParse(tag.split('-').last) ?? 0;
      if (run <= currentCode || run <= (best?.runNumber ?? 0)) continue;

      // Match the device ABI (e.g. hanamimi-plus-arm64-v8a.apk); fall back
      // to the universal APK, then any split as a last resort.
      final assets = (r['assets'] as List? ?? []).cast<Map<String, dynamic>>();
      Map<String, dynamic>? pick(String needle) {
        for (final a in assets) {
          if ((a['name'] as String? ?? '').contains(needle)) return a;
        }
        return null;
      }

      final asset = (abi != null ? pick(abi) : null) ??
          pick('universal') ??
          pick('arm64-v8a');
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

  /// The device's preferred ABI (e.g. "arm64-v8a", "x86_64"), for picking
  /// the matching split APK. Null if unavailable.
  static Future<String?> deviceAbi() async {
    try {
      return await _ch.invokeMethod<String>('abi');
    } catch (_) {
      return null;
    }
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
