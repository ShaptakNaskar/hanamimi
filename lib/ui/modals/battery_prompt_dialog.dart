import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/power_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_tokens.dart';

const _promptShownKey = 'battery_prompt_shown';

/// First-launch battery-optimization ask. OEM battery managers silently
/// kill background playback (paused music, stuck seek bar), and burying
/// the fix in You → settings meant most users only found it after being
/// bitten. Shown once, on the first open, only when the exemption isn't
/// already granted; declining leaves the You-screen row as the fallback.
Future<void> maybeShowBatteryPrompt(
    BuildContext context, WidgetRef ref) async {
  if (!Platform.isAndroid) return;
  final prefs = ref.read(sharedPrefsProvider);
  if (prefs.getBool(_promptShownKey) ?? false) return;
  if (await PowerChannel.isIgnoringBatteryOptimizations()) {
    // Already exempt (or unknowable) — never ask, never re-check.
    await prefs.setBool(_promptShownKey, true);
    return;
  }
  await prefs.setBool(_promptShownKey, true);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => const _BatteryPromptDialog(),
  );
}

class _BatteryPromptDialog extends ConsumerWidget {
  const _BatteryPromptDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    return AlertDialog(
      backgroundColor: theme.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg)),
      title: Text('Keep the music playing 🎵',
          style: AppText.rowSongTitle(theme)),
      content: Text(
        "Android's battery optimization can pause your music when the "
        'screen is off. Allow Hanamimi to run unrestricted so playback '
        'stays stable.\n\nYou can change this anytime in You → '
        '"Keep playing in background".',
        style: AppText.caption(theme),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Not now',
              style: AppText.rowSongTitle(theme)
                  .copyWith(color: theme.textMuted)),
        ),
        TextButton(
          onPressed: () async {
            await PowerChannel.requestIgnoreBatteryOptimizations();
            ref.invalidate(batteryOptIgnoredProvider);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text('Allow',
              style:
                  AppText.rowSongTitle(theme).copyWith(color: theme.primary)),
        ),
      ],
    );
  }
}
