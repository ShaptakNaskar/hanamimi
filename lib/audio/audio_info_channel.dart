import '../platform/web/web_media.dart';

/// Codec/bitrate for the Nerd bar, web edition. The browser doesn't
/// expose a demuxer, so this is honest arithmetic instead of a probe:
/// codec from the filename, average bitrate from size ÷ duration.
class AudioProbe {
  const AudioProbe({this.codec, this.bitrateKbps, this.sampleRateHz});

  final String? codec;
  final int? bitrateKbps;
  final int? sampleRateHz;
}

/// Where the sound goes. On the web that's simply the tab.
class AudioOutput {
  const AudioOutput({required this.route, this.name});

  final String route;
  final String? name;
}

class AudioInfoChannel {
  static Future<AudioProbe?> probe(String path) async {
    final file = WebMedia.fileForUrl(path);
    if (file == null) return null;
    final dot = file.name.lastIndexOf('.');
    final ext =
        dot < 0 ? null : file.name.substring(dot + 1).toUpperCase();
    final duration = await WebMedia.probeDuration(path);
    final kbps = duration == null || duration.inMilliseconds == 0
        ? null
        : (file.size * 8 / duration.inMilliseconds).round();
    return AudioProbe(codec: ext, bitrateKbps: kbps);
  }

  static Future<AudioOutput?> output() async =>
      const AudioOutput(route: 'Browser', name: 'Web Audio');
}
