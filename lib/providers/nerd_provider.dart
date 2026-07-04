import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../library/models/track.dart';
import '../online/audio_info_channel.dart';
import 'audio_provider.dart';
import 'theme_provider.dart';

/// Nerd mode: a visible SOUND-settings toggle (the target user is a
/// nerd — no reason to bury it under the 7-tap dev unlock). When on, the
/// Now-Playing screen shows codec / bitrate / sample-rate / container
/// and the live audio output route.
class NerdModeNotifier extends Notifier<bool> {
  static const _key = 'nerd_mode';

  @override
  bool build() => ref.watch(sharedPrefsProvider).getBool(_key) ?? false;

  void set(bool value) {
    state = value;
    ref.read(sharedPrefsProvider).setBool(_key, value);
  }
}

final nerdModeProvider =
    NotifierProvider<NerdModeNotifier, bool>(NerdModeNotifier.new);

/// A snapshot for the Nerd overlay.
class NerdInfo {
  const NerdInfo({
    required this.sourceLabel,
    this.codec,
    this.bitrateKbps,
    this.sampleRateHz,
    this.container,
    this.output,
  });

  /// "Local file" / "YouTube · yt-dlp" / "YouTube · explode" / "JioSaavn".
  final String sourceLabel;
  final String? codec;
  final int? bitrateKbps;
  final int? sampleRateHz;
  final String? container;
  final AudioOutput? output;
}

/// Builds the Nerd snapshot for the current track and refreshes the
/// output route every couple of seconds (it changes when headphones
/// connect). autoDispose: the poll stops when Now-Playing isn't visible.
final nerdInfoProvider = StreamProvider.autoDispose<NerdInfo?>((ref) async* {
  if (!ref.watch(nerdModeProvider)) {
    yield null;
    return;
  }
  final track = ref.watch(audioStateProvider).value?.currentTrack;
  if (track == null) {
    yield null;
    return;
  }

  final resolver = ref.read(audioHandlerProvider).engine.resolver;
  final source = await _sourceInfo(track, resolver);

  while (true) {
    final output = await AudioInfoChannel.output();
    yield NerdInfo(
      sourceLabel: source.label,
      codec: source.codec,
      bitrateKbps: source.bitrateKbps,
      sampleRateHz: source.sampleRateHz,
      container: source.container,
      output: output,
    );
    await Future.delayed(const Duration(seconds: 2));
  }
});

class _SourcePart {
  const _SourcePart({
    required this.label,
    this.codec,
    this.bitrateKbps,
    this.sampleRateHz,
    this.container,
  });
  final String label;
  final String? codec;
  final int? bitrateKbps;
  final int? sampleRateHz;
  final String? container;
}

Future<_SourcePart> _sourceInfo(Track track, dynamic resolver) async {
  // A downloaded/local file: probe the bytes for the real codec.
  final path = track.filePath;
  if (path != null) {
    final probe = await AudioInfoChannel.probe(path);
    final label = switch (track.source) {
      TrackSource.local => 'Local file',
      TrackSource.youtube => 'Downloaded · YouTube',
      TrackSource.saavn => 'Downloaded · JioSaavn',
    };
    return _SourcePart(
      label: label,
      codec: probe?.codec,
      bitrateKbps: probe?.bitrateKbps,
      sampleRateHz: probe?.sampleRateHz,
      container: null,
    );
  }

  // A live stream: reuse the resolver's cached resolution.
  final info = await resolver.streamInfo(track);
  final label = switch (track.source) {
    TrackSource.youtube =>
      info != null && info.fullSpeed == true ? 'YouTube · yt-dlp' : 'YouTube',
    TrackSource.saavn => 'JioSaavn',
    TrackSource.local => 'Local file',
  };
  return _SourcePart(
    label: label,
    codec: info?.codec,
    bitrateKbps: info?.bitrateKbps,
    sampleRateHz: info?.sampleRateHz,
    container: info?.container,
  );
}
