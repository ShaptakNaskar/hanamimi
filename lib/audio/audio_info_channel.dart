import 'package:flutter/services.dart';

/// Where the audio mix is going right now (Nerd mode). See
/// android/.../AudioInfoChannel.kt.
class AudioOutput {
  const AudioOutput({required this.route, this.name, this.sampleRateHz});

  /// "Bluetooth" / "Wired" / "USB" / "Speaker".
  final String route;
  final String? name;
  final int? sampleRateHz;
}

/// Decoded facts about a local audio file (Nerd mode).
class FileAudioInfo {
  const FileAudioInfo({
    this.codec,
    this.sampleRateHz,
    this.channels,
    this.bitrateKbps,
  });

  final String? codec;
  final int? sampleRateHz;
  final int? channels;
  final int? bitrateKbps;
}

/// Thin, never-throwing wrapper over the native audio-info channel.
class AudioInfoChannel {
  static const _ch = MethodChannel('hanamimi/audio_info');

  static Future<AudioOutput?> output() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('output');
      if (m == null) return null;
      return AudioOutput(
        route: (m['route'] as String?) ?? 'Speaker',
        name: m['name'] as String?,
        sampleRateHz: (m['sampleRate'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Probes a local file's audio track via MediaExtractor.
  static Future<FileAudioInfo?> probe(String path) async {
    try {
      final m = await _ch
          .invokeMapMethod<String, dynamic>('probe', {'path': path});
      if (m == null) return null;
      final bitrate = (m['bitrate'] as num?)?.toInt();
      return FileAudioInfo(
        codec: m['codec'] as String?,
        sampleRateHz: (m['sampleRate'] as num?)?.toInt(),
        channels: (m['channels'] as num?)?.toInt(),
        // Native reports bits/sec; nerd overlay wants kbps.
        bitrateKbps: bitrate == null ? null : (bitrate / 1000).round(),
      );
    } catch (_) {
      return null;
    }
  }
}
