import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
/// and karaoke-style synced lines: the active line fills word by word,
/// past words stay bright, upcoming words are dim, and scrolling keeps
/// the active line centered with a smooth glide (no page jumps).
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

class _LyricsSheetBody extends ConsumerWidget {
  const _LyricsSheetBody({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final lyrics = ref.watch(lyricsProvider(track.id));

    return ClipRRect(
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (track.albumArtPath != null &&
              File(track.albumArtPath!).existsSync())
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child:
                  Image.file(File(track.albumArtPath!), fit: BoxFit.cover),
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
                Text(track.title,
                    style: AppText.rowSongTitle(theme),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(track.artist, style: AppText.caption(theme)),
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
                            ? _KaraokeLines(lyrics: l, theme: theme)
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

/// A word with resolved start/end used by the fill animation.
class _TimedWord {
  _TimedWord(this.text, this.start, this.end);
  final String text;
  final Duration start;
  final Duration end;
}

class _KaraokeLines extends ConsumerStatefulWidget {
  const _KaraokeLines({required this.lyrics, required this.theme});

  final Lyrics lyrics;
  final HanamimiTheme theme;

  @override
  ConsumerState<_KaraokeLines> createState() => _KaraokeLinesState();
}

class _KaraokeLinesState extends ConsumerState<_KaraokeLines>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final Ticker _ticker;
  late final List<List<_TimedWord>> _timedLines;

  // Last position report from the player, and when we received it —
  // the ticker extrapolates between reports so the word fill glides
  // instead of stepping at the stream's update rate.
  Duration _lastPosition = Duration.zero;
  late final Stopwatch _sinceReport = Stopwatch();
  int _scrolledTo = -2;

  static const _lineExtent = 72.0;

  @override
  void initState() {
    super.initState();
    _timedLines = [
      for (var i = 0; i < widget.lyrics.lines.length; i++)
        _resolveWords(widget.lyrics.lines, i),
    ];
    _ticker = createTicker((_) => setState(() {}))..start();
  }

  /// Real word timings when the source has them; otherwise synthesized:
  /// the line's estimated sing time (capped by the next line's start)
  /// is distributed across words proportionally to their length.
  List<_TimedWord> _resolveWords(List<LyricLine> lines, int index) {
    final line = lines[index];
    final nextStart = index + 1 < lines.length
        ? lines[index + 1].timestamp
        : line.timestamp + const Duration(seconds: 5);

    if (line.hasWordTimings) {
      final words = line.words!;
      return [
        for (var w = 0; w < words.length; w++)
          _TimedWord(
            words[w].text,
            words[w].start,
            w + 1 < words.length ? words[w + 1].start : nextStart,
          ),
      ];
    }

    final tokens =
        line.text.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return [];
    final gapMs =
        (nextStart - line.timestamp).inMilliseconds.clamp(400, 30000);
    // ~350ms per word + lead-in, but never longer than the actual gap.
    final singMs =
        (tokens.length * 350 + 500).clamp(400, gapMs).toDouble();
    final totalChars =
        tokens.fold<int>(0, (sum, t) => sum + t.length).toDouble();
    final result = <_TimedWord>[];
    var cursorMs = line.timestamp.inMilliseconds.toDouble();
    for (final token in tokens) {
      final wordMs = singMs * (token.length / totalChars);
      result.add(_TimedWord(
        token,
        Duration(milliseconds: cursorMs.round()),
        Duration(milliseconds: (cursorMs + wordMs).round()),
      ));
      cursorMs += wordMs;
    }
    return result;
  }

  Duration get _smoothPosition {
    final playing =
        ref.read(audioStateProvider).value?.isPlaying ?? false;
    if (!playing) return _lastPosition;
    return _lastPosition + _sinceReport.elapsed;
  }

  void _autoScroll(int active) {
    if (active == _scrolledTo || !_scroll.hasClients) return;
    _scrolledTo = active;
    _scroll.animateTo(
      (active.clamp(0, 1 << 20)) * _lineExtent,
      duration: const Duration(milliseconds: 550),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Re-sync the extrapolation base on every player report.
    ref.listen(positionProvider, (_, next) {
      final pos = next.value;
      if (pos != null) {
        _lastPosition = pos;
        _sinceReport
          ..reset()
          ..start();
      }
    });

    final theme = widget.theme;
    final lines = widget.lyrics.lines;
    final position = _smoothPosition;
    final active = LrcParser.activeLine(lines, position);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoScroll(active));

    final bright = theme.isDark ? Colors.white : theme.textPrimary;

    return LayoutBuilder(builder: (context, constraints) {
      final pad = constraints.maxHeight / 2 - _lineExtent / 2;
      return Stack(
        children: [
          // Soft spotlight behind the vertically-centered active line.
          Align(
            alignment: Alignment.center,
            child: Container(
              height: 44,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  theme.primary.withValues(alpha: 0),
                  theme.primary.withValues(alpha: 0.14),
                  theme.primary.withValues(alpha: 0),
                ]),
              ),
            ),
          ),
          ListView.builder(
            controller: _scroll,
            physics: const BouncingScrollPhysics(),
            padding:
                EdgeInsets.symmetric(vertical: pad, horizontal: Space.s6),
            itemCount: lines.length,
            itemExtent: _lineExtent,
            itemBuilder: (context, i) {
              final isActive = i == active;
              final isPast = i < active;
              return RepaintBoundary(
                child: AnimatedScale(
                  scale: isActive ? 1.0 : 0.92,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOut,
                  child: Center(
                    child: isActive
                        ? _KaraokeLine(
                            words: _timedLines[i],
                            position: position,
                            bright: bright,
                            dim: bright.withValues(alpha: 0.35),
                          )
                        : Text(
                            lines[i].text,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body(theme).copyWith(
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              color: bright.withValues(
                                  alpha: isPast ? 0.30 : 0.50),
                            ),
                          ),
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

/// The active line: words wrap naturally; each sung word is bright,
/// the word being sung right now fills left-to-right, upcoming words
/// stay dim.
class _KaraokeLine extends StatelessWidget {
  const _KaraokeLine({
    required this.words,
    required this.position,
    required this.bright,
    required this.dim,
  });

  final List<_TimedWord> words;
  final Duration position;
  final Color bright;
  final Color dim;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Nunito',
      fontSize: TypeScale.activeLyric,
      fontWeight: FontWeight.w700,
      height: 1.25,
    );

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 5,
      runSpacing: 2,
      children: [
        for (final word in words)
          _WordFill(
            text: word.text,
            fraction: _fraction(word),
            bright: bright,
            dim: dim,
            style: style,
          ),
      ],
    );
  }

  double _fraction(_TimedWord word) {
    if (position >= word.end) return 1;
    if (position <= word.start) return 0;
    final total = (word.end - word.start).inMilliseconds;
    if (total <= 0) return 1;
    return (position - word.start).inMilliseconds / total;
  }
}

class _WordFill extends StatelessWidget {
  const _WordFill({
    required this.text,
    required this.fraction,
    required this.bright,
    required this.dim,
    required this.style,
  });

  final String text;
  final double fraction;
  final Color bright;
  final Color dim;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    if (fraction <= 0) return Text(text, style: style.copyWith(color: dim));
    if (fraction >= 1) {
      return Text(text, style: style.copyWith(color: bright));
    }
    return Stack(
      children: [
        Text(text, style: style.copyWith(color: dim)),
        ClipRect(
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: fraction,
            child: Text(text, style: style.copyWith(color: bright)),
          ),
        ),
      ],
    );
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
