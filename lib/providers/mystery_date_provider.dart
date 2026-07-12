import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme_provider.dart';

/// Mystery Date Mode (3.0 #1): the queue refuses to say what's next.
/// No upcoming list — just trust. Anticipation is the dopamine; it's
/// why radio survived a century of on-demand.
class MysteryDateNotifier extends Notifier<bool> {
  static const _key = 'mystery_date';

  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(_key) ?? false;

  void toggle() {
    state = !state;
    ref.read(sharedPrefsProvider).setBool(_key, state);
  }
}

final mysteryDateProvider =
    NotifierProvider<MysteryDateNotifier, bool>(MysteryDateNotifier.new);
