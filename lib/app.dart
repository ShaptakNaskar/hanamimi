import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'theme/theme_tokens.dart';
import 'theme/themes.dart';

class HanamimiApp extends ConsumerWidget {
  const HanamimiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness:
          theme.isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: theme.background,
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
        child: const _ThemePreviewHome(),
      ),
    );
  }
}

/// Temporary M2 home: proves the four themes render and switch.
/// Replaced by the app shell in M3.
class _ThemePreviewHome extends ConsumerWidget {
  const _ThemePreviewHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hanamimi', style: AppText.hero(theme)),
              const SizedBox(height: Space.s2),
              Text('花耳 — design system preview', style: AppText.caption(theme)),
              const SizedBox(height: Space.s6),
              for (final t in allThemes)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.s3),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(Radii.md),
                    onTap: () =>
                        ref.read(currentThemeProvider.notifier).setTheme(t.id),
                    child: Container(
                      height: Sizes.trackRowHeight,
                      padding: const EdgeInsets.all(Space.s4),
                      decoration: BoxDecoration(
                        color: theme.surface,
                        borderRadius: BorderRadius.circular(Radii.md),
                        border: Border.all(
                          color: t.id == theme.id ? theme.primary : theme.divider,
                          width: t.id == theme.id ? 2 : 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(t.emoji),
                          const SizedBox(width: Space.s3),
                          Text(t.name, style: AppText.rowSongTitle(theme)),
                          const Spacer(),
                          for (final c in [t.primary, t.secondary, t.accent])
                            Padding(
                              padding: const EdgeInsets.only(left: Space.s1),
                              child: CircleAvatar(radius: 8, backgroundColor: c),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
