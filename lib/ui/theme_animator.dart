import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/theme_provider.dart';
import '../theme/hanamimi_theme.dart';

/// Drives the gentle cross-fade between themes. Watches the resolved target
/// ([resolvedThemeProvider]) and lerps the displayed theme
/// ([currentThemeProvider]) toward it over ~400 ms, so switching themes —
/// and the adaptive theme recolouring per track — washes in smoothly
/// instead of snapping. Mounted once, above the app content.
class ThemeAnimator extends ConsumerStatefulWidget {
  const ThemeAnimator({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ThemeAnimator> createState() => _ThemeAnimatorState();
}

class _ThemeAnimatorState extends ConsumerState<ThemeAnimator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  HanamimiTheme? _from;
  HanamimiTheme? _to;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..addListener(() {
        final from = _from, to = _to;
        if (from != null && to != null) {
          ref
              .read(currentThemeProvider.notifier)
              .set(HanamimiTheme.lerp(from, to, _c.value));
        }
      });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<HanamimiTheme>(resolvedThemeProvider, (_, next) {
      _from = ref.read(currentThemeProvider); // lerp from what's on screen
      _to = next;
      _c.forward(from: 0);
    });
    return widget.child;
  }
}
