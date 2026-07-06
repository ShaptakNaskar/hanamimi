import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Battery-optimization exemption. Aggressive OEM battery managers kill
/// the playback service in the background, which silently pauses the
/// music (and, on the reconnect, leaves the seek bar stuck). Letting the
/// app run unrestricted keeps playback alive.
class PowerChannel {
  static const _ch = MethodChannel('hanamimi/power');

  static Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return (await _ch
              .invokeMethod<bool>('isIgnoringBatteryOptimizations')) ??
          true;
    } catch (_) {
      return true; // unknown → assume fine, never nag on error
    }
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _ch.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }

  /// Holds the screen awake via the activity window flag (no wakelock
  /// permission involved). Callers own turning it back off.
  static Future<void> setKeepScreenOn(bool on) async {
    try {
      await _ch.invokeMethod('setKeepScreenOn', {'on': on});
    } catch (_) {}
  }
}

/// Caffeine ☕ — keeps the screen awake for staring at the visualizer.
/// Deliberately not persisted: like real caffeine it wears off (next
/// launch starts fresh), so a forgotten toggle can't drain the battery
/// for days.
class CaffeineNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() {
    state = !state;
    PowerChannel.setKeepScreenOn(state);
  }
}

final caffeineProvider =
    NotifierProvider<CaffeineNotifier, bool>(CaffeineNotifier.new);

/// True when the app is exempt from battery optimization. `ref.refresh`
/// it after returning from the system dialog to pick up the new state.
final batteryOptIgnoredProvider = FutureProvider<bool>(
    (ref) => PowerChannel.isIgnoringBatteryOptimizations());
