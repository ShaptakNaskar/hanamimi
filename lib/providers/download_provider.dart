import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../library/models/track.dart';
import '../online/models/resolved_stream.dart';
import 'audio_provider.dart';
import 'library_provider.dart';
import 'theme_provider.dart';

enum DownloadStatus { queued, downloading, done, failed, cancelled }

/// One entry in the download manager. Immutable — the notifier swaps
/// updated copies into its list so Riverpod change detection works.
class DownloadTask {
  const DownloadTask({
    required this.track,
    required this.quality,
    this.status = DownloadStatus.queued,
    this.receivedBytes = 0,
    this.totalBytes,
    this.speedBps = 0,
  });

  final Track track;
  final StreamQuality quality;
  final DownloadStatus status;
  final int receivedBytes;
  final int? totalBytes;

  /// Rolling average bytes/second while downloading.
  final double speedBps;

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) return null; // indeterminate
    return (receivedBytes / total).clamp(0.0, 1.0);
  }

  String get key => '${track.source.name}:${track.sourceId}';

  DownloadTask copyWith({
    DownloadStatus? status,
    int? receivedBytes,
    int? totalBytes,
    double? speedBps,
  }) =>
      DownloadTask(
        track: track,
        quality: quality,
        status: status ?? this.status,
        receivedBytes: receivedBytes ?? this.receivedBytes,
        totalBytes: totalBytes ?? this.totalBytes,
        speedBps: speedBps ?? this.speedBps,
      );
}

/// Sequential download queue with live progress. One transfer at a time
/// — kind to the sources and keeps speed numbers honest. Completed
/// tasks stay listed until [clearFinished] so the user sees history for
/// the session; the durable record is the track's file_path in the DB.
class DownloadManagerNotifier extends Notifier<List<DownloadTask>> {
  bool _running = false;
  final _cancelled = <String>{};

  @override
  List<DownloadTask> build() => const [];

  /// Queues a download unless the same track is already queued/running.
  void enqueue(Track track, StreamQuality quality) {
    if (track.isPlayableOffline || track.sourceId == null) return;
    final key = '${track.source.name}:${track.sourceId}';
    final active = state.any((t) =>
        t.key == key &&
        (t.status == DownloadStatus.queued ||
            t.status == DownloadStatus.downloading));
    if (active) return;
    // Re-queue after a failure replaces the dead entry.
    state = [
      for (final t in state)
        if (t.key != key) t,
      DownloadTask(track: track, quality: quality),
    ];
    _pump();
  }

  void cancel(DownloadTask task) {
    if (task.status == DownloadStatus.downloading) {
      _cancelled.add(task.key); // the worker notices between chunks
    } else if (task.status == DownloadStatus.queued) {
      _update(task.key, (t) => t.copyWith(status: DownloadStatus.cancelled));
    }
  }

  void retry(DownloadTask task) => enqueue(task.track, task.quality);

  void clearFinished() {
    state = [
      for (final t in state)
        if (t.status == DownloadStatus.queued ||
            t.status == DownloadStatus.downloading)
          t,
    ];
  }

  void _update(String key, DownloadTask Function(DownloadTask) fn) {
    state = [for (final t in state) t.key == key ? fn(t) : t];
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = state.firstWhere(
          (t) => t.status == DownloadStatus.queued,
          orElse: () => const DownloadTask(
              track: Track(
                  id: -1, title: '', artist: '', album: '',
                  duration: Duration.zero),
              quality: StreamQuality.high),
        );
        if (next.track.id == -1) break;
        await _run(next);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _run(DownloadTask task) async {
    final key = task.key;
    _cancelled.remove(key);
    _update(key, (t) => t.copyWith(status: DownloadStatus.downloading));

    final resolver = ref.read(audioHandlerProvider).engine.resolver;
    final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/downloads');
    await dir.create(recursive: true);
    final dest =
        '${dir.path}/${task.track.source.name}_${task.track.sourceId}.audio';

    // Throttle state updates: UI-visible progress ~4×/s, not per chunk.
    var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
    var lastBytes = 0;
    var lastSpeedAt = DateTime.now();
    var speed = 0.0;

    final ok = await resolver.download(
      task.track,
      dest,
      quality: task.quality,
      isCancelled: () => _cancelled.contains(key),
      onProgress: (received, total) {
        final now = DateTime.now();
        final sinceSpeed = now.difference(lastSpeedAt).inMilliseconds;
        if (sinceSpeed >= 1000) {
          speed = (received - lastBytes) * 1000 / sinceSpeed;
          lastBytes = received;
          lastSpeedAt = now;
        }
        if (now.difference(lastEmit).inMilliseconds >= 250) {
          lastEmit = now;
          _update(
              key,
              (t) => t.copyWith(
                  receivedBytes: received,
                  totalBytes: total,
                  speedBps: speed));
        }
      },
    );

    if (ok) {
      // Stamp the file into the library so playback short-circuits to
      // disk and the Downloads tab lists it.
      final repo = await ref.read(libraryRepositoryProvider.future);
      await repo.setFilePath(task.track.id, dest);
      ref.read(libraryProvider.notifier).markDownloaded(task.track.id, dest);
      _update(
          key,
          (t) => t.copyWith(
              status: DownloadStatus.done,
              receivedBytes: t.totalBytes ?? t.receivedBytes));
    } else {
      final wasCancelled = _cancelled.remove(key);
      _update(
          key,
          (t) => t.copyWith(
              status: wasCancelled
                  ? DownloadStatus.cancelled
                  : DownloadStatus.failed));
    }
  }
}

final downloadManagerProvider =
    NotifierProvider<DownloadManagerNotifier, List<DownloadTask>>(
        DownloadManagerNotifier.new);

/// Tracks saved for offline (online-sourced, file on disk).
final downloadedTracksProvider = Provider<List<Track>>((ref) {
  final tracks = ref.watch(libraryProvider).value ?? const <Track>[];
  return [
    for (final t in tracks)
      if (!t.isLocal && t.filePath != null) t,
  ];
});

/// Persisted download-quality choice. null = ask on every download.
class DownloadQualityNotifier extends Notifier<StreamQuality?> {
  static const _key = 'download_quality';

  @override
  StreamQuality? build() {
    final name = ref.watch(sharedPrefsProvider).getString(_key);
    for (final q in StreamQuality.values) {
      if (q.name == name) return q;
    }
    return null;
  }

  void set(StreamQuality? value) {
    state = value;
    final prefs = ref.read(sharedPrefsProvider);
    value == null ? prefs.remove(_key) : prefs.setString(_key, value.name);
  }
}

final downloadQualityProvider =
    NotifierProvider<DownloadQualityNotifier, StreamQuality?>(
        DownloadQualityNotifier.new);
