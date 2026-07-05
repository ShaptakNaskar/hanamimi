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
}

/// True when the app is exempt from battery optimization. `ref.refresh`
/// it after returning from the system dialog to pick up the new state.
final batteryOptIgnoredProvider = FutureProvider<bool>(
    (ref) => PowerChannel.isIgnoringBatteryOptimizations());
