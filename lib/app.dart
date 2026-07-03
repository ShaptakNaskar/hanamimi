import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/audio_provider.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_tokens.dart';
import 'ui/app_shell.dart';

class HanamimiApp extends ConsumerWidget {
  const HanamimiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    ref.watch(playCountRecorderProvider);

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
      home: AnimatedTheme(
        data: AppTheme.from(theme),
        duration: Anim.themeCrossfade,
        child: const AppShell(),
      ),
    );
  }
}
