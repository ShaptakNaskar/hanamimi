import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_handler.dart';
import '../audio/models/audio_state.dart';

/// Injected in main() after AudioService.init.
final audioHandlerProvider = Provider<HanamimiAudioHandler>(
  (ref) => throw UnimplementedError('overridden in main'),
);

final audioStateProvider = StreamProvider<AudioState>(
  (ref) => ref.watch(audioHandlerProvider).engine.stateStream,
);

final positionProvider = StreamProvider<Duration>(
  (ref) => ref.watch(audioHandlerProvider).engine.positionStream,
);

/// Buffered position — the seek bar draws a lighter overlay up to here.
final bufferedProvider = StreamProvider<Duration>(
  (ref) => ref.watch(audioHandlerProvider).engine.bufferedStream,
);

/// Bumped every time the app returns to the foreground. Widgets that must
/// self-heal after a background freeze (the visualizer re-kicks its FFT
/// extraction, etc.) watch this. Kept on web for the visualizer's
/// watchdog; browser tab restores bump it from the shell.
class AppResumeTick extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final appResumeTickProvider =
    NotifierProvider<AppResumeTick, int>(AppResumeTick.new);
