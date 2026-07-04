import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_info_channel.dart';
import 'audio_provider.dart';
import 'theme_provider.dart';

/// Nerd mode: a visible SOUND-settings toggle. When on, the Now-Playing
/// screen shows codec / bitrate / sample-rate plus the live audio
/// output route. (Local-file variant — the plus branch adds stream
/// metadata for online sources.)
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
    this.output,
  });

  final String sourceLabel;
  final String? codec;
  final int? bitrateKbps;
  final int? sampleRateHz;
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

  // Probe the file's real codec/bitrate/sample-rate via MediaExtractor.
  final probe = await AudioInfoChannel.probe(track.filePath);

  while (true) {
    final output = await AudioInfoChannel.output();
    yield NerdInfo(
      sourceLabel: 'Local file',
      codec: probe?.codec,
      bitrateKbps: probe?.bitrateKbps,
      sampleRateHz: probe?.sampleRateHz,
      output: output,
    );
    await Future.delayed(const Duration(seconds: 2));
  }
});
