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
    this.sampleRateHz,
    this.container,
    this.fullSpeed = false,
    required this.expiresAt,
  });

  final Uri url;
  final Map<String, String> headers;

  /// Audio codec (e.g. `opus`, `mp4a.40.2`, `flac`) — surfaced in Nerd mode.
  final String? codec;
  final int? bitrateKbps;

  /// Sample rate in Hz (e.g. 44100, 48000) — Nerd mode.
  final int? sampleRateHz;

  /// Container / extension (e.g. `webm`, `m4a`) — Nerd mode.
  final String? container;

  /// True when the CDN serves this URL faster than real time, so the
  /// visualizer's FFT extractor can decode ahead of playback for real
  /// bands. False for `n`-throttled youtube_explode URLs (synth pulse).
  final bool fullSpeed;

  final DateTime expiresAt;

  /// A safety margin so a URL that expires mid-load doesn't get reused.
  bool get isFresh =>
      DateTime.now().isBefore(expiresAt.subtract(const Duration(minutes: 5)));
}
