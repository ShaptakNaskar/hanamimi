import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/audio_handler.dart';
import '../audio/models/audio_state.dart';
import 'library_provider.dart';

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

/// Records play counts as tracks start.
final playCountRecorderProvider = Provider<void>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final sub = handler.engine.trackStarted.stream.listen((track) async {
    final repo = await ref.read(libraryRepositoryProvider.future);
    await repo.recordPlay(track.id);
  });
  ref.onDispose(sub.cancel);
});
