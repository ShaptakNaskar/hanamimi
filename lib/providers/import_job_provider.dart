import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../online/import/import_models.dart';
import '../online/import/playlist_importer.dart';

/// The current playlist-import job. Lives here — not in the sheet — so
/// closing the sheet (or navigating away) doesn't cancel the import; it
/// keeps running and the result waits to be reviewed. This is what lets
/// the user leave the screen mid-import.
class ImportJob {
  const ImportJob({
    this.progress = const ImportProgress(phase: ImportPhase.idle),
    this.result,
    this.url,
  });

  final ImportProgress progress;
  final ImportResult? result;
  final String? url;

  bool get running =>
      progress.phase == ImportPhase.fetching ||
      progress.phase == ImportPhase.matching;
  bool get hasResult => result != null;
}

class ImportJobNotifier extends Notifier<ImportJob> {
  StreamSubscription<ImportProgress>? _sub;

  @override
  ImportJob build() => const ImportJob();

  /// Kicks off an import. Safe to fire-and-forget from the sheet: the job
  /// state updates here regardless of whether the sheet is still mounted
  /// (the provider isn't autoDispose, so it survives the sheet closing).
  Future<void> start(String url) async {
    if (state.running) return; // one at a time
    state = ImportJob(
        url: url, progress: const ImportProgress(phase: ImportPhase.fetching));

    final importer = PlaylistImporter();
    _sub = importer.progress(url).listen((p) {
      // Keep result null while it's still working.
      state = ImportJob(url: url, progress: p);
    });

    final result = await importer.run(url);
    await _sub?.cancel();
    _sub = null;

    if (result == null || result.matches.isEmpty) {
      state = ImportJob(
          url: url, progress: const ImportProgress(phase: ImportPhase.failed));
      return;
    }
    state = ImportJob(
      url: url,
      result: result,
      progress: ImportProgress(
        phase: ImportPhase.done,
        total: result.matches.length,
        matched: result.confident.length,
      ),
    );
  }

  /// Reset once the result has been committed or dismissed.
  void clear() {
    _sub?.cancel();
    _sub = null;
    state = const ImportJob();
  }
}

final importJobProvider =
    NotifierProvider<ImportJobNotifier, ImportJob>(ImportJobNotifier.new);
