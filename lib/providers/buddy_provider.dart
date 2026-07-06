import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_provider.dart';

/// One entry per code-drawn pet (the BuddySpec registry from
/// ARCHITECTURE-ANIMATIONS.md §4). The beagle is listed too so she can
/// be tucked away like any other buddy — she still greets you in the
/// You tab, on share cards and in the sleep-timer modal.
class BuddyInfo {
  const BuddyInfo(this.id, this.name, this.home);

  final String id;
  final String name;

  /// Where it lives — shown as the settings row caption.
  final String home;
}

const buddyCatalog = [
  BuddyInfo('beagle', 'Hanamimi', 'Header & Now Playing'),
  BuddyInfo('parrot', 'Parrot', 'Perches on the Library title'),
  BuddyInfo('cat', 'Cat', 'Naps on the mini player'),
  BuddyInfo('hamster', 'Hamster', 'Scampers on your companion card'),
  BuddyInfo('duck', 'Duck', 'Struts atop Liked songs'),
  BuddyInfo('koi', 'Koi', 'Has a pond below Now Playing'),
  // Rabbit is plus-only (lives on download bars) — not listed on main.
];

/// Which buddies the user has switched OFF — everyone is on by default,
/// stored as a disabled-list so new buddies added later start enabled.
class BuddyTogglesNotifier extends Notifier<Set<String>> {
  static const _key = 'buddies_disabled';

  @override
  Set<String> build() =>
      (ref.watch(sharedPrefsProvider).getStringList(_key) ?? const [])
          .toSet();

  void setEnabled(String id, bool on) {
    final disabled = {...state};
    on ? disabled.remove(id) : disabled.add(id);
    ref
        .read(sharedPrefsProvider)
        .setStringList(_key, disabled.toList()..sort());
    state = disabled;
  }
}

final buddyTogglesProvider =
    NotifierProvider<BuddyTogglesNotifier, Set<String>>(
        BuddyTogglesNotifier.new);

/// True when the buddy with [id] should be visible.
final buddyEnabledProvider = Provider.family<bool, String>(
    (ref, id) => !ref.watch(buddyTogglesProvider).contains(id));
