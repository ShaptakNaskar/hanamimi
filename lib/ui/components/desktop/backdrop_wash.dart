import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/audio_provider.dart';
import '../../../providers/theme_provider.dart';

/// Whole-window art glow for the desktop shell: the current track's
/// cover, heavily blurred, washed down to a subtle tint that sits
/// UNDER all three panes. One uniform glow across the entire app —
/// the panes float on it as translucent layers, so no pane boundary
/// ever reads as a jump into a different color.
class BackdropWash extends ConsumerWidget {
  const BackdropWash({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final track = ref.watch(audioStateProvider).value?.currentTrack;

    final artPath = track?.albumArtPath;
    // Base edition is local-only — no artUrl on the Track model.
    ImageProvider? image =
        artPath != null ? FileImage(File(artPath)) : null;
    // The wash is blurred to mush anyway — a 200px decode blurs in a
    // fraction of the time of full-res art (same lesson as the lyrics
    // sheet backdrop on Android).
    if (image != null) image = ResizeImage(image, width: 200);

    // RepaintBoundary: a sigma-100 blur over the whole window is the
    // most expensive paint in the app. Isolated, it rasterizes once
    // per track change; un-isolated, the 60 fps siblings (visualizer,
    // particles) dragged it into every frame — the desktop
    // high-CPU-while-idle bug.
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        switchInCurve: Curves.easeOut,
        child: image == null
            ? const SizedBox.expand()
            : Stack(
                key: ValueKey(artPath),
                fit: StackFit.expand,
                children: [
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                    child: Image(image: image, fit: BoxFit.cover),
                  ),
                  Container(
                      color: theme.background.withValues(alpha: 0.82)),
                ],
              ),
      ),
    );
  }
}
