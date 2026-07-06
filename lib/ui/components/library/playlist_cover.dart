import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../library/models/playlist.dart';
import '../../../library/models/track.dart';
import '../../../providers/library_provider.dart';

/// A playlist's cover square. Priority: the user-picked image, else a
/// 2×2 collage of the first four distinct track arts, else the first
/// art alone, else the pastel colour block with the initial.
class PlaylistCover extends ConsumerWidget {
  const PlaylistCover({
    super.key,
    required this.playlist,
    required this.size,
    this.borderRadius,
    this.fontSize = 28,
  });

  final Playlist playlist;
  final double size;
  final BorderRadius? borderRadius;
  final double fontSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final radius = borderRadius ?? BorderRadius.circular(8);

    final custom = playlist.coverImagePath;
    if (custom != null && File(custom).existsSync()) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.file(File(custom),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * 3).round(),
            gaplessPlayback: true),
      );
    }

    // Distinct arts in playlist order; four fill the collage.
    final byId = {
      for (final t in ref.watch(libraryProvider).value ?? <Track>[]) t.id: t
    };
    final arts = <String>[];
    for (final id in playlist.trackIds) {
      final path = byId[id]?.albumArtPath;
      if (path != null && !arts.contains(path) && File(path).existsSync()) {
        arts.add(path);
        if (arts.length == 4) break;
      }
    }

    Widget art(String path, double edge) => Image.file(File(path),
        width: edge,
        height: edge,
        fit: BoxFit.cover,
        cacheWidth: (edge * 3).round(),
        gaplessPlayback: true);

    if (arts.length == 4) {
      final half = size / 2;
      // Positioned quadrants inside a fixed SizedBox: flex rows either
      // stretched to the parent's width (collage sat off-center, right
      // corners unclipped) or overflowed by a rounding pixel.
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              for (final (i, path) in arts.indexed)
                Positioned(
                  left: (i % 2) * half,
                  top: (i ~/ 2) * half,
                  width: half,
                  height: half,
                  child: art(path, half),
                ),
            ],
          ),
        ),
      );
    }
    if (arts.isNotEmpty) {
      return ClipRRect(borderRadius: radius, child: art(arts.first, size));
    }

    return Container(
      width: size,
      height: size,
      decoration:
          BoxDecoration(color: playlist.coverColor, borderRadius: radius),
      alignment: Alignment.center,
      child: Text(
        playlist.name.isEmpty ? '♪' : playlist.name[0].toUpperCase(),
        style: TextStyle(
          fontFamily: 'Nunito',
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}
