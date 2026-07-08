import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/audio_provider.dart';
import 'providers/companion_provider.dart';
import 'providers/open_with_provider.dart';
import 'providers/reco_provider.dart';
import 'providers/session_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/theme_provider.dart';
import 'reco/play_tracker.dart';
import 'theme/app_theme.dart';
import 'theme/theme_tokens.dart';
import 'ui/app_shell.dart';
import 'ui/handheld_scroll_behavior.dart';
import 'ui/theme_animator.dart';

class HanamimiApp extends ConsumerWidget {
  const HanamimiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    ref.watch(playCountRecorderProvider);
    ref.watch(playSequenceTrackerProvider); // M38a co-play/skip logging
    ref.watch(smartShufflePusherProvider); // M38c weighted shuffle
    ref.watch(crossfadeProvider); // pushes the setting into the engine
    ref.watch(listenTimeProvider); // accumulates while playing
    ref.watch(openWithProvider); // handles "open with Hanamimi" intents
    ref.watch(sessionPersistenceProvider); // saves what's playing for resume

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          theme.isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: theme.surface,
      systemNavigationBarIconBrightness:
          theme.isDark ? Brightness.light : Brightness.dark,
    ));

    return MaterialApp(
      title: 'Hanamimi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.from(theme),
      // Finger/stylus drag-scroll for handheld touchscreens.
      scrollBehavior: const HandheldScrollBehavior(),
      home: AnimatedTheme(
        data: AppTheme.from(theme),
        duration: Anim.themeCrossfade,
        child: const ThemeAnimator(child: AppShell()),
      ),
    );
  }
}
