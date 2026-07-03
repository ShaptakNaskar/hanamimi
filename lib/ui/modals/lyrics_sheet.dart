import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/track.dart';
import '../../lyrics/lrc_parser.dart';
import '../../lyrics/models/lyric_line.dart';
import '../../providers/audio_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/mascot/hanamimi_widget.dart';

/// Slide-up sheet (85% height) with the blurred album art as backdrop
/// and position-synced lines (DESIGN.md §9.9).
void showLyricsSheet(BuildContext context, Track track) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _LyricsSheetBody(track: track),
    ),
  );
}

class _LyricsSheetBody extends ConsumerStatefulWidget {
  const _LyricsSheetBody({required this.track});

  final Track track;

  @override
  ConsumerState<_LyricsSheetBody> createState() => _LyricsSheetBodyState();
}

class _LyricsSheetBodyState extends ConsumerState<_LyricsSheetBody> {
  final _scroll = ScrollController();
  int _lastActive = -2;

  static const _lineExtent = 56.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll(int active) {
    if (active == _lastActive || !_scroll.hasClients) return;
    _lastActive = active;
    _scroll.animateTo(
      (active.clamp(0, 1 << 20)) * _lineExtent,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final lyrics = ref.watch(lyricsProvider(widget.track.id));

    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred album art backdrop.
          if (widget.track.albumArtPath != null &&
              File(widget.track.albumArtPath!).existsSync())
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Image.file(File(widget.track.albumArtPath!),
                  fit: BoxFit.cover),
            )
          else
            ColoredBox(color: theme.background),
          ColoredBox(
              color: (theme.isDark ? Colors.black : theme.background)
                  .withValues(alpha: 0.72)),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: Space.s3),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.textMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
                const SizedBox(height: Space.s3),
                Text(widget.track.title,
                    style: AppText.rowSongTitle(theme),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(widget.track.artist, style: AppText.caption(theme)),
                const SizedBox(height: Space.s3),
                Expanded(
                  child: lyrics.when(
                    loading: () => Center(
                        child: CircularProgressIndicator(
                            color: theme.primary)),
                    error: (_, __) => _NoLyrics(theme: theme),
                    data: (l) => l == null || l.isEmpty
                        ? _NoLyrics(theme: theme)
                        : l.isSynced
                            ? _SyncedLines(
                                lyrics: l,
                                theme: theme,
                                controller: _scroll,
                                lineExtent: _lineExtent,
                                onActiveLine: _autoScroll,
                              )
                            : _PlainLines(lyrics: l, theme: theme),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncedLines extends ConsumerWidget {
  const _SyncedLines({
    required this.lyrics,
    required this.theme,
    required this.controller,
    required this.lineExtent,
    required this.onActiveLine,
  });

  final Lyrics lyrics;
  final HanamimiTheme theme;
  final ScrollController controller;
  final double lineExtent;
  final ValueChanged<int> onActiveLine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final active = LrcParser.activeLine(lyrics.lines, position);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => onActiveLine(active));

    return LayoutBuilder(builder: (context, constraints) {
      final pad = constraints.maxHeight / 2 - lineExtent / 2;
      return Stack(
        children: [
          // Soft spotlight behind the vertically-centered active line.
          Align(
            alignment: Alignment.center,
            child: Container(
              height: 36,
              width: double.infinity,
              color: theme.primary.withValues(alpha: 0.15),
            ),
          ),
          ListView.builder(
            controller: controller,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(
                vertical: pad, horizontal: Space.s6),
            itemCount: lyrics.lines.length,
            itemExtent: lineExtent,
            itemBuilder: (context, i) {
              final isActive = i == active;
              final isPast = i < active;
              return Center(
                child: AnimatedDefaultTextStyle(
                  duration: Anim.minTransition,
                  style: (isActive
                          ? AppText.activeLyric(theme)
                          : AppText.body(theme))
                      .copyWith(
                    color: theme.textPrimary.withValues(
                        alpha: isActive ? 1.0 : (isPast ? 0.4 : 0.7)),
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                  child: Text(
                    lyrics.lines[i].text,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
        ],
      );
    });
  }
}

class _PlainLines extends StatelessWidget {
  const _PlainLines({required this.lyrics, required this.theme});

  final Lyrics lyrics;
  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(
          vertical: Space.s6, horizontal: Space.s6),
      itemCount: lyrics.lines.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.s1),
        child: Text(lyrics.lines[i].text,
            style: AppText.body(theme), textAlign: TextAlign.center),
      ),
    );
  }
}

class _NoLyrics extends StatelessWidget {
  const _NoLyrics({required this.theme});

  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HanamimiMascot(state: MascotState.paused, size: 90),
          const SizedBox(height: Space.s3),
          Text('No lyrics found', style: AppText.body(theme)),
          Text('This one\'s just for listening',
              style: AppText.caption(theme)),
        ],
      ),
    );
  }
}
