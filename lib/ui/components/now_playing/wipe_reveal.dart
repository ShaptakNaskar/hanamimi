import 'package:flutter/material.dart';

/// Reveals [child] with a soft-edged vertical wipe that sweeps in from the
/// RIGHT as [progress] goes 0→1 — the crossfade's incoming song "writes
/// over" the outgoing one from right to left. The feathered edge keeps the
/// sweep gentle rather than a hard line. Shared by the phone Now Playing
/// screen and the desktop immersive screen.
///
/// [invert] shows the LEFT portion (the outgoing side of the sweep) instead
/// of the right — layer an inverted copy of the OUTGOING content beneath the
/// incoming so the two never overlap where they're transparent (text).
class WipeReveal extends StatelessWidget {
  const WipeReveal({
    super.key,
    required this.progress,
    required this.child,
    this.invert = false,
  });

  final double progress;
  final Widget child;
  final bool invert;

  /// Width of the soft reveal edge, as a fraction of the child's width.
  static const _feather = 0.2;

  @override
  Widget build(BuildContext context) {
    // The reveal edge travels from the right (x=1 at p=0) off the left
    // (x=-feather at p=1); everything to its right shows the incoming.
    final edge = 1.0 - progress * (1.0 + _feather);
    final lo = edge.clamp(0.0, 1.0);
    var hi = (edge + _feather).clamp(0.0, 1.0);
    if (hi <= lo) hi = (lo + 0.0001).clamp(0.0, 1.0);
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: invert
            ? const [
                Colors.white,
                Colors.white,
                Colors.transparent,
                Colors.transparent,
              ]
            : const [
                Colors.transparent,
                Colors.transparent,
                Colors.white,
                Colors.white,
              ],
        stops: [0.0, lo, hi, 1.0],
      ).createShader(rect),
      child: child,
    );
  }
}
