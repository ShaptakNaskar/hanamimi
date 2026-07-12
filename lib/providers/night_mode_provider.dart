import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_provider.dart';
import 'theme_provider.dart';

/// Night Mode (3.0 — "After Midnight, It Whispers"). One system owning
/// the after-dark ambience: the embers palette shift (night_shift.dart),
/// softer lowercase copy, and a gentler master gain. Merged from ideas
/// #2 and #5 per the scoping decisions.
enum NightModeSetting { auto, always, never }

class NightModeSettingNotifier extends Notifier<NightModeSetting> {
  static const _key = 'night_mode';

  @override
  NightModeSetting build() {
    final saved = ref.watch(sharedPrefsProvider).getString(_key);
    return NightModeSetting.values
            .where((v) => v.name == saved)
            .firstOrNull ??
        NightModeSetting.auto;
  }

  void set(NightModeSetting v) {
    state = v;
    ref.read(sharedPrefsProvider).setString(_key, v.name);
  }
}

final nightModeSettingProvider =
    NotifierProvider<NightModeSettingNotifier, NightModeSetting>(
        NightModeSettingNotifier.new);

/// The auto window: midnight up to (not including) 6am.
bool _inNightWindow(DateTime now) => now.hour < 6;

/// Whether night ambience is live right now. In auto mode a one-shot
/// timer re-evaluates exactly at the next boundary (midnight or 6am).
///
/// Timers count *monotonic* time, so a device clock change slips right
/// past the scheduled boundary (user-reported: set the clock past
/// midnight, nothing shifted until a force stop). Two backstops, both
/// nearly free: re-evaluate on every app resume (clock edits happen in
/// Settings, i.e. backgrounded), and a once-a-minute sanity check that
/// only invalidates when the computed answer actually flipped — one
/// no-op callback per minute, no rebuilds, per the constant-CPU lesson.
class NightModeActive extends Notifier<bool> {
  Timer? _boundary;
  Timer? _sanity;

  @override
  bool build() {
    _boundary?.cancel();
    _boundary = null;
    _sanity?.cancel();
    _sanity = null;
    final setting = ref.watch(nightModeSettingProvider);
    ref.watch(appResumeTickProvider); // fresh look at the clock on resume
    ref.onDispose(() {
      _boundary?.cancel();
      _sanity?.cancel();
    });

    switch (setting) {
      case NightModeSetting.always:
        return true;
      case NightModeSetting.never:
        return false;
      case NightModeSetting.auto:
        final now = DateTime.now();
        final active = _inNightWindow(now);
        final boundary = active
            ? DateTime(now.year, now.month, now.day, 6)
            : DateTime(now.year, now.month, now.day + 1); // next midnight
        _boundary = Timer(
            boundary.difference(now) + const Duration(seconds: 1),
            () => ref.invalidateSelf());
        _sanity = Timer.periodic(const Duration(minutes: 1), (_) {
          if (_inNightWindow(DateTime.now()) != state) ref.invalidateSelf();
        });
        return active;
    }
  }
}

final nightModeActiveProvider =
    NotifierProvider<NightModeActive, bool>(NightModeActive.new);

/// Night Mode's lowercase voice: past midnight the app's own copy —
/// titles, section labels, nav — drops to lowercase ("after midnight,
/// it whispers"). Applied at the call sites of chrome strings; song
/// metadata is never touched (lowercasing a track title would
/// misrepresent the library, not soften the app).
extension NightWhisper on String {
  String whisper(bool night) => night ? toLowerCase() : this;
}

/// Pushes the gentler night gain into the engine (same pattern as
/// crossfadeProvider). Watched from app.dart. 0.8 is "noticeably
/// softer, nobody reaches for the volume knob".
final nightGainPusherProvider = Provider<void>((ref) {
  final engine = ref.watch(audioHandlerProvider).engine;
  final active = ref.watch(nightModeActiveProvider);
  engine.setGainScale(active ? 0.8 : 1.0);
});
