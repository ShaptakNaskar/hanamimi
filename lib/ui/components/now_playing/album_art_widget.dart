import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../library/models/track.dart';
import '../../../providers/window_activity_provider.dart';
import '../../../theme/hanamimi_theme.dart';
import '../../../theme/theme_tokens.dart';
import '../library/art_thumb.dart';

/// Full-size album art: soft primary ambient shadow, gentle cross-dissolve
/// on track change, and the idle ±1° wobble while playing (DESIGN.md §8).
class AlbumArtWidget extends StatefulWidget {
  const AlbumArtWidget({
    super.key,
    required this.track,
    required this.theme,
    required this.isPlaying,
    required this.size,
  });

  final Track track;
  final HanamimiTheme theme;
  final bool isPlaying;
  final double size;

  @override
  State<AlbumArtWidget> createState() => _AlbumArtWidgetState();
}

class _AlbumArtWidgetState extends State<AlbumArtWidget>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _phase = 0; // seconds
  double _amplitude = 0; // 0..1, eases in/out with play state
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    windowVisible.addListener(_onWindowVisible);
    if (widget.isPlaying) _ticker.start();
  }

  void _onWindowVisible() {
    if (windowVisible.value &&
        mounted &&
        widget.isPlaying &&
        !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    // Minimized: hold still — the wobble recomposites the art layer
    // every frame for a window nobody can see. The windowVisible
    // listener restarts the ticker on restore.
    if (!windowVisible.value) {
      _ticker.stop();
      _last = Duration.zero;
      return;
    }
    final dt =
        ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    final target = widget.isPlaying ? 1.0 : 0.0;
    final speed = widget.isPlaying ? 2.0 : 1.7; // ~600ms ease to rest
    _amplitude = (_amplitude + (target - _amplitude) * dt * speed)
        .clamp(0.0, 1.0);
    if (_amplitude > 0.001) {
      _phase += dt;
      setState(() {});
    } else {
      if (_phase != 0) {
        _phase = 0;
        setState(() {});
      }
      // Wobble fully eased out: stop the ticker — an idle active ticker
      // still forces an engine frame (and NVIDIA GL swap busy-wait)
      // every vsync. didUpdateWidget restarts it when play resumes.
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  @override
  void didUpdateWidget(AlbumArtWidget old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_ticker.isActive && windowVisible.value) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void dispose() {
    windowVisible.removeListener(_onWindowVisible);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One full rock cycle every 4 seconds, ±1°.
    final angle =
        math.sin(_phase * 2 * math.pi / 4) * _amplitude * (math.pi / 180);

    // RepaintBoundary: the wobble only moves the transform, so the art
    // + shadow layer is cached and each frame is a recomposite, not a
    // repaint of a full-size image with a 24px blur shadow.
    return Transform.rotate(
      angle: angle,
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.lg),
            boxShadow: [
              BoxShadow(
                color: widget.theme.primary.withValues(alpha: 0.3),
                blurRadius: 24,
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween(begin: 0.95, end: 1.0).animate(anim),
                child: child,
              ),
            ),
            child: ArtThumb(
              key: ValueKey(widget.track.id),
              title: widget.track.album.isEmpty
                  ? widget.track.title
                  : widget.track.album,
              artPath: widget.track.albumArtPath,
              artUrl: widget.track.artUrl,
              size: widget.size,
              radius: Radii.lg,
            ),
          ),
        ),
      ),
    );
  }
}
