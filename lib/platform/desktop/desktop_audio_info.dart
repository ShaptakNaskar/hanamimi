import 'dart:convert';
import 'dart:io';

import '../../online/audio_info_channel.dart';
import 'desktop_binaries.dart';

/// Desktop implementation of the Nerd-mode audio-info contract:
/// ffprobe stands in for MediaExtractor, and the output route comes
/// from PulseAudio/PipeWire's default sink (Linux; Windows reports a
/// plain system-output route until SMTC work lands).
class DesktopAudioInfo {
  static Future<FileAudioInfo?> probe(String path) async {
    try {
      final res = await Process.run(DesktopBinaries.find('ffprobe'), [
        '-v', 'quiet',
        '-print_format', 'json',
        '-show_format',
        '-show_streams',
        '-select_streams', 'a:0',
        path,
      ]);
      if (res.exitCode != 0) return null;
      final info = jsonDecode(res.stdout as String) as Map<String, dynamic>;
      final streams = (info['streams'] as List?) ?? const [];
      if (streams.isEmpty) return null;
      final audio = streams.first as Map<String, dynamic>;
      final format = (info['format'] as Map<String, dynamic>?) ?? const {};
      final bitrate = int.tryParse(audio['bit_rate'] as String? ?? '') ??
          int.tryParse(format['bit_rate'] as String? ?? '');
      return FileAudioInfo(
        codec: audio['codec_name'] as String?,
        sampleRateHz: int.tryParse(audio['sample_rate'] as String? ?? ''),
        channels: (audio['channels'] as num?)?.toInt(),
        bitrateKbps: bitrate == null ? null : (bitrate / 1000).round(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<AudioOutput?> output() async {
    if (!Platform.isLinux) return const AudioOutput(route: 'Speaker');
    try {
      // Default sink name, then its row in the short list for the rate:
      // "55  alsa_output.pci-0000.analog-stereo  ...  s32le 2ch 48000Hz ..."
      final def = await Process.run('pactl', ['get-default-sink']);
      if (def.exitCode != 0) return const AudioOutput(route: 'Speaker');
      final sink = (def.stdout as String).trim();

      int? rateHz;
      final list = await Process.run('pactl', ['list', 'short', 'sinks']);
      if (list.exitCode == 0) {
        for (final line in const LineSplitter().convert(list.stdout as String)) {
          if (!line.contains(sink)) continue;
          final match = RegExp(r'(\d+)Hz').firstMatch(line);
          rateHz = int.tryParse(match?.group(1) ?? '');
          break;
        }
      }

      final lower = sink.toLowerCase();
      final route = lower.contains('bluez')
          ? 'Bluetooth'
          : lower.contains('usb')
              ? 'USB'
              : lower.contains('hdmi')
                  ? 'HDMI'
                  : 'Speaker';
      return AudioOutput(route: route, name: sink, sampleRateHz: rateHz);
    } catch (_) {
      return const AudioOutput(route: 'Speaker');
    }
  }
}
