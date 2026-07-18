import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/companion_provider.dart';
import 'providers/night_mode_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_tokens.dart';
import 'ui/handheld_scroll_behavior.dart';
import 'ui/theme_animator.dart';
import 'ui/web_shell.dart';

class HanamimiApp extends ConsumerWidget {
  const HanamimiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    ref.watch(crossfadeProvider); // pushes the setting into the engine
    ref.watch(slowDanceProvider); // 3.0 sighted-crossfade planner
    ref.watch(nightGainPusherProvider); // 3.0 night-mode gentler gain
    ref.watch(listenTimeProvider); // accumulates while playing

    return MaterialApp(
      title: 'Hanamimi 花耳',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.from(theme),
      scrollBehavior: const HandheldScrollBehavior(),
      home: AnimatedTheme(
        data: AppTheme.from(theme),
        duration: Anim.themeCrossfade,
        child: const ThemeAnimator(child: WebShell()),
      ),
    );
  }
}
