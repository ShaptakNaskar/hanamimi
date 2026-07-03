import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';

/// Placeholder until the audio engine (M5) and Now Playing UI (M6) land.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    return SafeArea(
      bottom: false,
      child: Center(
        child: Text('Nothing playing yet', style: AppText.caption(theme)),
      ),
    );
  }
}
