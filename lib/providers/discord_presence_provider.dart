import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/desktop/desktop_bootstrap.dart';
import '../platform/desktop/discord_presence_service.dart';
import 'audio_provider.dart';
import 'theme_provider.dart';

class DiscordPresenceEnabledNotifier extends Notifier<bool> {
  static const preferenceKey = 'discord_presence';

  @override
  bool build() =>
      ref.watch(sharedPrefsProvider).getBool(preferenceKey) ?? false;

  void set(bool enabled) {
    state = enabled;
    ref.read(sharedPrefsProvider).setBool(preferenceKey, enabled);
  }
}

final discordPresenceEnabledProvider =
    NotifierProvider<DiscordPresenceEnabledNotifier, bool>(
      DiscordPresenceEnabledNotifier.new,
    );

/// Root-lifetime side effect: creates the Discord bridge only on desktop and
/// only after the user opts in. Rebuilding on toggle-off disposes the socket,
/// which clears the activity immediately.
final discordPresencePusherProvider = Provider<void>((ref) {
  if (!isDesktop || !ref.watch(discordPresenceEnabledProvider)) return;

  final service = DiscordPresenceService(ref.read(audioHandlerProvider).engine);
  service.start();
  ref.onDispose(() => unawaited(service.dispose()));
});
