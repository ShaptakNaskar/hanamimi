/// User streaming-quality setting (ONLINE settings card, M27).
enum StreamQuality { low, high }

/// A playable stream URL, valid until [expiresAt]. Never persisted —
/// YouTube URLs die after ~6 h; always re-resolve at play time.
class ResolvedStream {
  const ResolvedStream({
    required this.url,
    this.headers = const {},
    this.codec,
    this.bitrateKbps,
    required this.expiresAt,
  });

  final Uri url;
  final Map<String, String> headers;
  final String? codec;
  final int? bitrateKbps;
  final DateTime expiresAt;

  /// A safety margin so a URL that expires mid-load doesn't get reused.
  bool get isFresh =>
      DateTime.now().isBefore(expiresAt.subtract(const Duration(minutes: 5)));
}
