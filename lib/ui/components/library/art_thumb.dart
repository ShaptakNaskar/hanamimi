import 'dart:io';

import 'package:flutter/material.dart';

/// Album art thumbnail with the DESIGN.md placeholder: a soft gradient
/// generated deterministically from the title, with the first letter
/// as a centered glyph.
class ArtThumb extends StatelessWidget {
  const ArtThumb({
    super.key,
    required this.title,
    this.artPath,
    required this.size,
    required this.radius,
  });

  final String title;
  final String? artPath;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    // No existsSync here — synchronous disk IO on every list-row build
    // makes scrolling jank. Missing files fall through to the
    // placeholder via errorBuilder instead.
    final child = artPath == null
        ? _placeholder()
        : Image.file(
            File(artPath!),
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: (size * 3).round(),
            errorBuilder: (_, __, ___) => _placeholder(),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: child,
    );
  }

  /// Deterministic soft pastel: hue from the title's hash.
  Widget _placeholder() {
    final hue = (title.hashCode % 360).abs().toDouble();
    final base = HSLColor.fromAHSL(1, hue, 0.55, 0.82).toColor();
    final deep = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.5, 0.7).toColor();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [base, deep],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        title.isEmpty ? '?' : title[0].toUpperCase(),
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}
