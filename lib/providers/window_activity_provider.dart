import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Window activity signals (desktop): every animation frame keeps the
/// whole render pipeline hot — engine raster, GL swap, compositor — so
/// eye-candy pays real CPU even when nobody can see it (the
/// constant-CPU report). Two tiers:
///
/// * [windowFocused] — input focus. Ambient decor (roaming pets,
///   particle drift, oneko) freezes on focus loss; the music-driven
///   visualizer drops to half rate but keeps moving, since a
///   visible-but-unfocused window on a second monitor reads as content.
/// * [windowVisible] — not minimized. Everything visual stops: bands,
///   wobble, playing bars. Playback itself is never touched.
///
/// Mobile never flips these — the OS already halts vsync callbacks when
/// an app leaves the foreground. app_shell's WindowListener keeps them
/// current on desktop.
final windowFocused = ValueNotifier<bool>(true);
final windowVisible = ValueNotifier<bool>(true);

Provider<bool> _wrap(ValueListenable<bool> source) => Provider<bool>((ref) {
      void changed() => ref.invalidateSelf();
      source.addListener(changed);
      ref.onDispose(() => source.removeListener(changed));
      return source.value;
    });

final windowFocusedProvider = _wrap(windowFocused);
final windowVisibleProvider = _wrap(windowVisible);
