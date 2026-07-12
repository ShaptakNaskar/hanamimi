import 'dart:async';

import 'package:flutter/material.dart';

/// "The UI Undresses" (3.0 #6): the longer you listen without touching
/// anything, the more chrome melts away — controls first, then labels —
/// until it's just cover art, the visualizer and the cat breathing with
/// the music. Touch anything and it all slides back.
///
/// Two timers, no ticker: stage changes are single rebuilds through a
/// ValueNotifier, and the fades are AnimatedOpacity — nothing runs
/// while idle, per the desktop constant-CPU lesson.
///
/// Stages: 0 = fully dressed · 1 = controls gone · 2 = labels gone too.
class UndressLayer extends StatefulWidget {
  const UndressLayer({
    super.key,
    required this.enabled,
    required this.child,
  });

  /// Fades only run while true (i.e. music is playing); when it flips
  /// false everything re-dresses immediately.
  final bool enabled;

  final Widget child;

  @override
  State<UndressLayer> createState() => _UndressLayerState();
}

class _UndressLayerState extends State<UndressLayer> {
  static const _toStage1 = Duration(seconds: 20);
  static const _toStage2 = Duration(seconds: 25); // after stage 1

  final _stage = ValueNotifier<int>(0);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(UndressLayer old) {
    super.didUpdateWidget(old);
    if (widget.enabled != old.enabled) _touch();
  }

  void _arm() {
    _timer?.cancel();
    if (!widget.enabled) return;
    _timer = Timer(_toStage1, () {
      _stage.value = 1;
      _timer = Timer(_toStage2, () => _stage.value = 2);
    });
  }

  void _touch() {
    if (_stage.value != 0) _stage.value = 0;
    _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _touch(),
      onPointerMove: (_) => _touch(),
      onPointerHover: (_) => _touch(),
      onPointerSignal: (_) => _touch(),
      child: _UndressScope(stage: _stage, child: widget.child),
    );
  }
}

class _UndressScope extends InheritedNotifier<ValueNotifier<int>> {
  const _UndressScope({required ValueNotifier<int> stage, required super.child})
      : super(notifier: stage);
}

/// Wraps a piece of Now Playing chrome that should melt away at
/// [level] (1 = controls, 2 = labels). Renders the child untouched when
/// there's no [UndressLayer] above (e.g. the desktop panel).
class Undressable extends StatelessWidget {
  const Undressable({super.key, required this.level, required this.child});

  final int level;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_UndressScope>();
    if (scope == null) return child;
    final hidden = scope.notifier!.value >= level;
    return AnimatedOpacity(
      // Slow, dreamy melt out; snappy return so a touch feels instant.
      duration: hidden
          ? const Duration(milliseconds: 1800)
          : const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      opacity: hidden ? 0 : 1,
      child: IgnorePointer(ignoring: hidden, child: child),
    );
  }
}
