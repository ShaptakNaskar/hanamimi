import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/track.dart';
import '../../online/models/resolved_stream.dart';
import '../../providers/audio_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/library/art_thumb.dart';

/// Downloads tab: live transfers (progress / speed / size) on top,
/// the offline collection below, with total storage in the header.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final tasks = ref.watch(downloadManagerProvider);
    final downloaded = ref.watch(downloadedTracksProvider);

    final active = [
      for (final t in tasks)
        if (t.status == DownloadStatus.queued ||
            t.status == DownloadStatus.downloading)
          t,
    ];
    final finished = [
      for (final t in tasks)
        if (t.status == DownloadStatus.failed ||
            t.status == DownloadStatus.cancelled)
          t,
    ];

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        children: [
          const SizedBox(height: Space.s6),
          Text('Downloads', style: AppText.screenTitle(theme)),
          const SizedBox(height: Space.s1),
          _StorageLine(downloaded: downloaded, theme: theme),
          const SizedBox(height: Space.s4),
          if (active.isNotEmpty || finished.isNotEmpty) ...[
            Text('ACTIVE', style: AppText.sectionLabel(theme)),
            const SizedBox(height: Space.s2),
            for (final task in active)
              _ActiveDownloadCard(task: task, theme: theme),
            for (final task in finished)
              _FailedDownloadCard(task: task, theme: theme),
            const SizedBox(height: Space.s6),
          ],
          Text('SAVED FOR OFFLINE', style: AppText.sectionLabel(theme)),
          const SizedBox(height: Space.s2),
          if (downloaded.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s8),
              child: Column(
                children: [
                  Icon(Icons.download_for_offline_outlined,
                      size: 44, color: theme.textMuted),
                  const SizedBox(height: Space.s3),
                  Text('Nothing saved yet', style: AppText.body(theme)),
                  const SizedBox(height: Space.s1),
                  Text(
                    'Download songs from search to play them offline',
                    style: AppText.caption(theme),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < downloaded.length; i++)
              _DownloadedRow(
                track: downloaded[i],
                theme: theme,
                onTap: () => ref
                    .read(audioHandlerProvider)
                    .playTracks(downloaded, startIndex: i),
              ),
          const SizedBox(height: Space.s12),
        ],
      ),
    );
  }
}

/// "12 songs · 84 MB on device"
class _StorageLine extends StatelessWidget {
  const _StorageLine({required this.downloaded, required this.theme});

  final List<Track> downloaded;
  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context) {
    var bytes = 0;
    for (final t in downloaded) {
      final path = t.filePath;
      if (path == null) continue;
      try {
        bytes += File(path).lengthSync();
      } catch (_) {}
    }
    final n = downloaded.length;
    return Text(
      n == 0
          ? 'Songs you save live here'
          : '$n song${n == 1 ? '' : 's'} · ${formatBytes(bytes)} on device',
      style: AppText.caption(theme),
    );
  }
}

class _ActiveDownloadCard extends ConsumerWidget {
  const _ActiveDownloadCard({required this.task, required this.theme});

  final DownloadTask task;
  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloading = task.status == DownloadStatus.downloading;
    final received = formatBytes(task.receivedBytes);
    final total =
        task.totalBytes == null ? null : formatBytes(task.totalBytes!);

    return Container(
      margin: const EdgeInsets.only(bottom: Space.s2),
      padding: const EdgeInsets.all(Space.s3),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: theme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ArtThumb(
                title: task.track.title,
                artPath: task.track.albumArtPath,
                artUrl: task.track.artUrl,
                size: 40,
                radius: Radii.sm,
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.track.title,
                        style: AppText.rowSongTitle(theme),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(
                      downloading
                          ? '${task.quality == StreamQuality.low ? 'Low' : 'High'} quality'
                              ' · ${formatBytes(task.speedBps.round())}/s'
                          : 'Waiting…',
                      style: AppText.caption(theme),
                    ),
                  ],
                ),
              ),
              InkResponse(
                onTap: () =>
                    ref.read(downloadManagerProvider.notifier).cancel(task),
                radius: 18,
                child: Icon(Icons.close, size: 18, color: theme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: Space.s2),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: downloading ? task.progress : null,
              minHeight: 5,
              color: theme.primary,
              backgroundColor: theme.divider.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: Space.s1),
          Text(
            total == null ? received : '$received of $total',
            style: AppText.caption(theme).copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _FailedDownloadCard extends ConsumerWidget {
  const _FailedDownloadCard({required this.task, required this.theme});

  final DownloadTask task;
  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cancelled = task.status == DownloadStatus.cancelled;
    return Container(
      margin: const EdgeInsets.only(bottom: Space.s2),
      padding: const EdgeInsets.symmetric(
          horizontal: Space.s3, vertical: Space.s2),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: theme.divider, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(cancelled ? Icons.block : Icons.error_outline,
              size: 18, color: theme.textMuted),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.track.title,
                    style: AppText.rowSongTitle(theme),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(cancelled ? 'Cancelled' : "Couldn't download",
                    style: AppText.caption(theme)),
              ],
            ),
          ),
          TextButton(
            onPressed: () =>
                ref.read(downloadManagerProvider.notifier).retry(task),
            child: Text('Retry',
                style: AppText.rowSongTitle(theme)
                    .copyWith(color: theme.primary)),
          ),
        ],
      ),
    );
  }
}

class _DownloadedRow extends ConsumerWidget {
  const _DownloadedRow({
    required this.track,
    required this.theme,
    required this.onTap,
  });

  final Track track;
  final HanamimiTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var size = '';
    final path = track.filePath;
    if (path != null) {
      try {
        size = formatBytes(File(path).lengthSync());
      } catch (_) {}
    }
    final playing =
        ref.watch(audioStateProvider).value?.currentTrack?.id == track.id;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.md),
      child: SizedBox(
        height: Sizes.trackRowHeight,
        child: Row(
          children: [
            ArtThumb(
              title: track.title,
              artPath: track.albumArtPath,
              artUrl: track.artUrl,
              size: Sizes.trackRowHeight - Space.s3 * 2,
              radius: Radii.sm,
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title,
                      style: AppText.rowSongTitle(theme).copyWith(
                          color: playing ? theme.primary : null),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    '${track.artist}${size.isEmpty ? '' : ' · $size'}',
                    style: AppText.caption(theme),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            InkResponse(
              onTap: () => _confirmDelete(context, ref),
              radius: 20,
              child: Padding(
                padding: const EdgeInsets.all(Space.s2),
                child: Icon(Icons.delete_outline,
                    size: 20, color: theme.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.lg)),
        title: Text('Remove download?', style: AppText.rowSongTitle(theme)),
        content: Text(
          '"${track.title}" stays in your playlists and can still stream — '
          'only the offline copy is deleted.',
          style: AppText.caption(theme),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Keep',
                style: AppText.rowSongTitle(theme)
                    .copyWith(color: theme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Remove',
                style: AppText.rowSongTitle(theme)
                    .copyWith(color: theme.primary)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(libraryProvider.notifier).removeDownload(track);
    }
  }
}

/// "84 MB", "1.2 GB" — shared by the storage line and transfer cards.
String formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024).toStringAsFixed(0)} KB';
}
