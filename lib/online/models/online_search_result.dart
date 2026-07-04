import '../../library/models/track.dart';

/// Lightweight provider search hit — not a [Track]: no DB row exists
/// until the user acts on it (ARCHITECTURE-ONLINE.md §3.3).
class OnlineSearchResult {
  const OnlineSearchResult({
    required this.source,
    required this.sourceId,
    required this.title,
    required this.artist,
    this.album = '',
    required this.duration,
    this.artUrl,
  });

  final TrackSource source;
  final String sourceId;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final String? artUrl;
}
