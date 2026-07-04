import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../online/models/resolved_stream.dart';
import 'audio_provider.dart';
import 'theme_provider.dart';

/// Quality to use on a metered (mobile-data) connection. [matchWifi]
/// defers to [streamQualityProvider]; the other two force a level.
enum MeteredQuality { low, high, matchWifi }

/// Master online switch. When off, search scopes hide and the resolver
/// refuses to resolve streams (downloaded tracks still play).
class OnlineEnabledNotifier extends Notifier<bool> {
  static const _key = 'online_enabled';

  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(_key) ?? true;

  void set(bool value) {
    state = value;
    ref.read(sharedPrefsProvider).setBool(_key, value);
  }
}

final onlineEnabledProvider =
    NotifierProvider<OnlineEnabledNotifier, bool>(OnlineEnabledNotifier.new);

/// Streaming quality on Wi-Fi (and the fallback for metered=matchWifi).
class StreamQualityNotifier extends Notifier<StreamQuality> {
  static const _key = 'stream_quality';

  @override
  StreamQuality build() {
    final name = ref.watch(sharedPrefsProvider).getString(_key);
    return StreamQuality.values
        .firstWhere((q) => q.name == name, orElse: () => StreamQuality.high);
  }

  void set(StreamQuality value) {
    state = value;
    ref.read(sharedPrefsProvider).setString(_key, value.name);
  }
}

final streamQualityProvider =
    NotifierProvider<StreamQualityNotifier, StreamQuality>(
        StreamQualityNotifier.new);

class MeteredQualityNotifier extends Notifier<MeteredQuality> {
  static const _key = 'metered_quality';

  @override
  MeteredQuality build() {
    final name = ref.watch(sharedPrefsProvider).getString(_key);
    return MeteredQuality.values
        .firstWhere((q) => q.name == name, orElse: () => MeteredQuality.low);
  }

  void set(MeteredQuality value) {
    state = value;
    ref.read(sharedPrefsProvider).setString(_key, value.name);
  }
}

final meteredQualityProvider =
    NotifierProvider<MeteredQualityNotifier, MeteredQuality>(
        MeteredQualityNotifier.new);

/// Stream cache cap in MB (LockCachingAudioSource LRU, §8).
class StreamCacheSizeNotifier extends Notifier<int> {
  static const _key = 'stream_cache_mb';

  @override
  int build() => ref.watch(sharedPrefsProvider).getInt(_key) ?? 512;

  void set(int mb) {
    state = mb;
    ref.read(sharedPrefsProvider).setInt(_key, mb);
  }
}

final streamCacheSizeProvider =
    NotifierProvider<StreamCacheSizeNotifier, int>(StreamCacheSizeNotifier.new);

/// True when the active network bills by the byte (mobile data).
final isMeteredProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool metered(List<ConnectivityResult> r) =>
      r.contains(ConnectivityResult.mobile) &&
      !r.contains(ConnectivityResult.wifi) &&
      !r.contains(ConnectivityResult.ethernet);
  yield metered(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(metered);
});

/// Pushes the effective quality + enabled flag into the engine's
/// resolver whenever any input changes. Watched once at the app root.
final resolverConfigProvider = Provider<void>((ref) {
  final enabled = ref.watch(onlineEnabledProvider);
  final wifiQuality = ref.watch(streamQualityProvider);
  final metered = ref.watch(isMeteredProvider).value ?? false;
  final meteredQuality = ref.watch(meteredQualityProvider);
  final cacheMb = ref.watch(streamCacheSizeProvider);

  final effective = !metered
      ? wifiQuality
      : switch (meteredQuality) {
          MeteredQuality.low => StreamQuality.low,
          MeteredQuality.high => StreamQuality.high,
          MeteredQuality.matchWifi => wifiQuality,
        };

  final resolver = ref.read(audioHandlerProvider).engine.resolver;
  resolver.enabled = enabled;
  resolver.quality = effective;
  resolver.cacheCapBytes = cacheMb * 1024 * 1024;
});
