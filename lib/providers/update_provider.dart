import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../platform/desktop/desktop_updater.dart';

const _repo = 'ShaptakNaskar/hanamimi';

/// Desktop is plus by definition (EDITIONS.md: the base edition is the
/// Play-Store lineage; only + ships as a desktop app), and its
/// packageName isn't a reliable edition signal anyway.
bool get _isPlusEdition =>
    !Platform.isAndroid; // Android decides below, per package id

/// The version string to show in About — read live from the built
/// package, so it always reflects what CI stamped and never needs a
/// hand-edit: e.g. "Hanamimi+ 花耳 · 1.0.3". (The internal versionCode
/// stays the CI run number for Android + the updater's newer-check.)
final appVersionLabelProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final edition = _isPlusEdition || info.packageName.endsWith('.plus')
        ? 'Hanamimi+'
        : 'Hanamimi';
    return '$edition 花耳 · ${info.version}';
  } catch (_) {
    return 'Hanamimi 花耳';
  }
});

/// "Hanamimi+" on the plus edition, "Hanamimi" on the base app — for the
/// Library header and anywhere else the edition name shows.
final editionNameProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return _isPlusEdition || info.packageName.endsWith('.plus')
        ? 'Hanamimi+'
        : 'Hanamimi';
  } catch (_) {
    return 'Hanamimi';
  }
});

/// The release channel THIS build follows, derived from its own package
/// id so main and plus never cross-update: `com.hanamimi.app.plus` →
/// `plus-v…` tags, `com.hanamimi.app` → `main-v…`. Same source on both
/// branches; the installed edition decides. Desktop always follows plus.
String _tagPrefixFor(String packageName) =>
    _isPlusEdition || packageName.endsWith('.plus') ? 'plus-v' : 'main-v';

/// A newer build published by the CI pipeline (GitHub Releases).
class AppUpdate {
  const AppUpdate({
    required this.versionName,
    required this.semver,
    required this.runNumber,
    required this.changelog,
    required this.apkUrl,
    required this.sizeBytes,
    required this.htmlUrl,
  });

  final String versionName;

  /// The release's GitHub page — for package-managed desktop installs
  /// (pacman/AUR) that update themselves and only want a "here's what's
  /// new, go grab it" link rather than an in-app download.
  final String htmlUrl;

  /// Bare x.y.z parsed from the tag, for version comparisons.
  final String semver;

  /// CI run number == versionCode; monotonic, what we compare.
  final int runNumber;
  final String changelog;
  final String apkUrl;
  final int sizeBytes;
}

/// Compares dotted version strings; returns <0, 0 or >0 like compareTo.
int compareSemver(String a, String b) {
  final pa = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  final pb = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  for (var i = 0; i < 3; i++) {
    final d = (i < pa.length ? pa[i] : 0) - (i < pb.length ? pb[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// Checks GitHub Releases for a newer build of THIS edition. Null = up to
/// date (or the check failed — never nag on network errors). CI tags
/// releases `<branch>-v<version>-<run>`; the version name is the primary
/// comparison. versionCode (= run number) only breaks ties, and must be
/// taken mod 1000 first: Flutter stamps per-ABI split APKs with
/// `abiCode*1000 + versionCode`, which made split installs (exactly what
/// the updater downloads) look newer than every release — the 1.0.6
/// "no updates found" bug.
final updateCheckProvider = FutureProvider<AppUpdate?>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final currentCode = (int.tryParse(info.buildNumber) ?? 0) % 1000;
    final currentVersion = info.version;
    final tagPrefix = _tagPrefixFor(info.packageName);
    // The device's preferred ABI, so we download the matching split APK
    // (smallest) and only fall back to the universal one.
    final abi = await UpdaterChannel.deviceAbi();

    final res = await http.get(
      Uri.parse('https://api.github.com/repos/$_repo/releases?per_page=50'),
      headers: {'Accept': 'application/vnd.github+json'},
    ).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;

    final releases = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    AppUpdate? best;
    for (final r in releases) {
      final tag = r['tag_name'] as String? ?? '';
      if (!tag.startsWith(tagPrefix)) continue;
      // <branch>-v1.0.1-42 → version between the prefix and the final
      // dash, run number after it.
      final run = int.tryParse(tag.split('-').last) ?? 0;
      final version = tag.substring(
          tagPrefix.length,
          tag.lastIndexOf('-') > tagPrefix.length
              ? tag.lastIndexOf('-')
              : tag.length);
      final versionCmp = compareSemver(version, currentVersion);
      final isNewer = versionCmp > 0 || (versionCmp == 0 && run > currentCode);
      if (!isNewer) continue;
      if (best != null) {
        final bestCmp = compareSemver(version, best.semver);
        if (bestCmp < 0 || (bestCmp == 0 && run <= best.runNumber)) continue;
      }

      // Android: match the device ABI (e.g. hanamimi-plus-arm64-v8a.apk),
      // fall back to the universal APK, then any split as a last resort.
      // Desktop: the platform's package (AppImage / Windows installer).
      final assets = (r['assets'] as List? ?? []).cast<Map<String, dynamic>>();
      Map<String, dynamic>? pick(String needle) {
        for (final a in assets) {
          if ((a['name'] as String? ?? '')
              .toLowerCase()
              .contains(needle.toLowerCase())) {
            return a;
          }
        }
        return null;
      }

      final asset = Platform.isAndroid
          ? (abi != null ? pick(abi) : null) ??
              pick('universal') ??
              pick('arm64-v8a')
          : Platform.isLinux
              ? pick('.AppImage') ?? pick('linux')
              : pick('setup.exe') ?? pick('.msix') ?? pick('windows');
      if (asset == null) continue;

      best = AppUpdate(
        versionName: (r['name'] as String?) ?? tag,
        semver: version,
        runNumber: run,
        changelog: (r['body'] as String?) ?? '',
        apkUrl: asset['browser_download_url'] as String,
        sizeBytes: (asset['size'] as num?)?.toInt() ?? 0,
        htmlUrl: (r['html_url'] as String?) ??
            'https://github.com/$_repo/releases',
      );
    }
    return best;
  } catch (_) {
    return null;
  }
});

/// Thin wrapper over the native installer channel (Android) or the
/// desktop self-updater (AppImage swap / installer launch).
class UpdaterChannel {
  static const _ch = MethodChannel('hanamimi/updater');

  static Future<bool> canInstall() async {
    if (!Platform.isAndroid) return DesktopUpdater.canInstall();
    try {
      return (await _ch.invokeMethod<bool>('canInstall')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openInstallPerm() async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('openInstallPerm');
    } catch (_) {}
  }

  /// The device's preferred ABI (e.g. "arm64-v8a", "x86_64"), for picking
  /// the matching split APK. Null if unavailable (and on desktop, where
  /// assets are picked by platform instead).
  static Future<String?> deviceAbi() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _ch.invokeMethod<String>('abi');
    } catch (_) {
      return null;
    }
  }

  static Future<bool> install(String path) async {
    if (!Platform.isAndroid) return DesktopUpdater.install(path);
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
  // Keep the asset's own extension — the desktop installer step cares
  // (.AppImage / .exe), and Android expects .apk either way.
  final ext = update.apkUrl.substring(update.apkUrl.lastIndexOf('.'));
  final file = File('${dir.path}/hanamimi-update-${update.runNumber}$ext');

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
