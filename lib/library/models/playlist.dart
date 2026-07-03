import 'dart:ui';

class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.coverColor,
    required this.trackIds,
    required this.createdAt,
  });

  final int id;
  final String name;
  final Color coverColor;
  final List<int> trackIds;
  final DateTime createdAt;

  factory Playlist.fromRow(Map<String, Object?> r, List<int> trackIds) =>
      Playlist(
        id: r['id'] as int,
        name: r['name'] as String,
        coverColor: Color(r['cover_color'] as int),
        trackIds: trackIds,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      );
}

/// The 8 pastel cover options from DESIGN.md §9.3.
const playlistCoverColors = [
  Color(0xFFF4A7B9), // pink
  Color(0xFFD4A5E8), // lavender
  Color(0xFFA8E6CF), // mint
  Color(0xFFFFC9A3), // peach
  Color(0xFFA3D5FF), // sky
  Color(0xFFFFE7A3), // butter yellow
  Color(0xFFB5C9A3), // sage
  Color(0xFFD0CCC5), // warm grey
];
