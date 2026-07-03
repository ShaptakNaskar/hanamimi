import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/components/mascot/mascot_painter.dart';
import 'audio_provider.dart';
import 'theme_provider.dart';

class AccessoryInfo {
  const AccessoryInfo(this.accessory, this.name, this.unlockHours);

  final Accessory accessory;
  final String name;
  final int unlockHours;

  String get unlockLabel =>
      'Listen for $unlockHours hour${unlockHours == 1 ? '' : 's'}';
}

/// Unlockables from ARCHITECTURE.md §11.3 (cat ears come with Cat Mode
/// in the polish milestone).
const accessoryCatalog = [
  AccessoryInfo(Accessory.bow, 'Pink bow', 1),
  AccessoryInfo(Accessory.headphones, 'Tiny headphones', 10),
  AccessoryInfo(Accessory.flower, 'Flower', 25),
  AccessoryInfo(Accessory.crown, 'Tiny crown', 100),
];

/// Total listen time. Accumulates in 5s ticks while playing, persisted.
class ListenTimeNotifier extends Notifier<Duration> {
  static const _key = 'listen_seconds';
  Timer? _timer;

  @override
  Duration build() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      final playing =
          ref.read(audioStateProvider).value?.isPlaying ?? false;
      if (playing) {
        state += const Duration(seconds: 5);
        ref
            .read(sharedPrefsProvider)
            .setInt(_key, state.inSeconds);
      }
    });
    ref.onDispose(() => _timer?.cancel());
    return Duration(
        seconds: ref.read(sharedPrefsProvider).getInt(_key) ?? 0);
  }
}

final listenTimeProvider =
    NotifierProvider<ListenTimeNotifier, Duration>(ListenTimeNotifier.new);

/// The accessory Hanamimi is currently wearing. Persisted.
class ActiveAccessoryNotifier extends Notifier<Accessory> {
  static const _key = 'accessory';

  @override
  Accessory build() {
    final saved = ref.watch(sharedPrefsProvider).getString(_key);
    return Accessory.values
            .where((a) => a.name == saved)
            .firstOrNull ??
        Accessory.none;
  }

  void toggle(Accessory accessory) {
    state = state == accessory ? Accessory.none : accessory;
    ref.read(sharedPrefsProvider).setString(_key, state.name);
  }
}

final activeAccessoryProvider =
    NotifierProvider<ActiveAccessoryNotifier, Accessory>(
        ActiveAccessoryNotifier.new);

bool isUnlocked(AccessoryInfo info, Duration listened) =>
    listened.inHours >= info.unlockHours;
