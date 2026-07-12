import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../history/history_resolver.dart';
import '../../library/models/listen_event.dart';
import '../../library/models/track.dart';
import '../../providers/audio_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/night_mode_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';

/// "Listening history" — the append-only log (3.0 #7), newest first,
/// grouped by day. Rows are snapshots: tapping one re-resolves it
/// against the current library (path → identity → online stream), so
/// history stays browsable — and mostly playable — even after files
/// move or vanish.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const HistoryScreen());

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  static const _pageSize = 60;

  final _events = <ListenEvent>[];
  final _goneRowIds = <int>{}; // resolution failed this session
  var _loading = false;
  var _exhausted = false;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _exhausted) return;
    setState(() => _loading = true);
    final repo = await ref.read(libraryRepositoryProvider.future);
    final rows = await repo.listenHistoryPage(
        limit: _pageSize, offset: _events.length);
    if (!mounted) return;
    setState(() {
      _events.addAll(rows.map(ListenEvent.fromRow));
      _exhausted = rows.length < _pageSize;
      _loading = false;
    });
  }

  Future<void> _play(ListenEvent event) async {
    final resolved = await resolveHistoryPlay(ref, event);
    if (!mounted) return;
    final track = resolved.track;
    if (track == null) {
      setState(() => _goneRowIds.add(event.id));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('"${event.title}" isn\'t around anymore — '
            'file not found'),
      ));
      return;
    }
    await ref.read(audioHandlerProvider).playTracks([track]);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.surface,
        title: Text(
            'Listening history'
                .whisper(ref.watch(nightModeActiveProvider)),
            style: AppText.rowSongTitle(theme)),
      ),
      body: _events.isEmpty && _exhausted
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.s6),
                child: Text(
                  'Nothing here yet — play something and\n'
                  'your history starts writing itself ♪',
                  textAlign: TextAlign.center,
                  style: AppText.caption(theme),
                ),
              ),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.extentAfter < 600) _loadMore();
                return false;
              },
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(vertical: Space.s2),
                itemCount: _events.length + (_exhausted ? 0 : 1),
                itemBuilder: (context, i) {
                  if (i >= _events.length) {
                    return const Padding(
                      padding: EdgeInsets.all(Space.s4),
                      child:
                          Center(child: CircularProgressIndicator()),
                    );
                  }
                  final event = _events[i];
                  final header = _dayHeaderIfFirst(i);
                  final row = _HistoryRow(
                    event: event,
                    theme: theme,
                    gone: _goneRowIds.contains(event.id),
                    onTap: () => _play(event),
                  );
                  if (header == null) return row;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            Space.s4, Space.s4, Space.s4, Space.s1),
                        child: Text(
                            header.whisper(ref
                                .watch(nightModeActiveProvider)),
                            style: AppText.sectionLabel(theme)),
                      ),
                      row,
                    ],
                  );
                },
              ),
            ),
    );
  }

  /// Day label when [i] is the first event of its calendar day.
  String? _dayHeaderIfFirst(int i) {
    final day = _dayOf(_events[i].playedAt);
    if (i > 0 && _dayOf(_events[i - 1].playedAt) == day) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final md = '${day.day} ${months[day.month - 1]}';
    return day.year == today.year ? md : '$md ${day.year}';
  }

  static DateTime _dayOf(DateTime t) =>
      DateTime(t.year, t.month, t.day);
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.event,
    required this.theme,
    required this.gone,
    required this.onTap,
  });

  final ListenEvent event;
  final HanamimiTheme theme;
  final bool gone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time =
        '${event.playedAt.hour.toString().padLeft(2, '0')}:${event.playedAt.minute.toString().padLeft(2, '0')}';
    final sourceGlyph = switch (event.source) {
      TrackSource.local => Icons.folder_rounded,
      TrackSource.youtube => Icons.smart_display_rounded,
      TrackSource.saavn => Icons.cloud_rounded,
    };

    return Opacity(
      opacity: gone ? 0.45 : 1,
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: theme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Icon(
            gone ? Icons.music_off_rounded : Icons.music_note_rounded,
            color: theme.primary,
            size: 22,
          ),
        ),
        title: Text(event.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.rowSongTitle(theme)),
        subtitle: Text(
          event.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.rowArtist(theme),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(time, style: AppText.timestamp(theme)),
            const SizedBox(height: 2),
            Icon(sourceGlyph, size: 14, color: theme.textMuted),
          ],
        ),
      ),
    );
  }
}
