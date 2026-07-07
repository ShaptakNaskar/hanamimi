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
      final def = await Process.run('pactl', ['get-default-sink']);
      if (def.exitCode != 0) return const AudioOutput(route: 'Speaker');
      final sink = (def.stdout as String).trim();

      // The raw sink id ("alsa_output.pci-0000_06_00.6.HiFi__Speaker__sink")
      // is plumbing, not a name (user: "wtf is alsa output pci"). The
      // sink's Description is the human string the OS volume UI shows —
      // walk `pactl list sinks` to the default sink's block and read it.
      int? rateHz;
      String? description;
      final list = await Process.run('pactl', ['list', 'sinks']);
      if (list.exitCode == 0) {
        var inOurSink = false;
        for (final raw
            in const LineSplitter().convert(list.stdout as String)) {
          final line = raw.trim();
          if (line.startsWith('Name:')) {
            inOurSink = line.substring(5).trim() == sink;
          } else if (inOurSink && line.startsWith('Description:')) {
            description = line.substring(12).trim();
          } else if (inOurSink && line.startsWith('Sample Specification:')) {
            final match = RegExp(r'(\d+)Hz').firstMatch(line);
            rateHz = int.tryParse(match?.group(1) ?? '');
            break; // got everything we need
          }
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
      return AudioOutput(
          route: route, name: description, sampleRateHz: rateHz);
    } catch (_) {
      return const AudioOutput(route: 'Speaker');
    }
  }
}
