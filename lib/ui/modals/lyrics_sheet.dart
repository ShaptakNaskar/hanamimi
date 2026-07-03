import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/track.dart';
import '../../lyrics/lyrics_service.dart';
import '../../lyrics/models/lyric_line.dart';
import '../../providers/library_provider.dart';
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

class _LyricsSheetBody extends ConsumerStatefulWidget {
  const _LyricsSheetBody({required this.track});

  final Track track;

  @override
  ConsumerState<_LyricsSheetBody> createState() => _LyricsSheetBodyState();
}

class _LyricsSheetBodyState extends ConsumerState<_LyricsSheetBody> {
  Duration _offsetFor(int trackId) => Duration(
      milliseconds:
          ref.read(sharedPrefsProvider).getInt('lyrics_offset_$trackId') ??
              0);

  void _adjustOffset(int trackId, int deltaMs) {
    final ms = (_offsetFor(trackId).inMilliseconds + deltaMs)
        .clamp(-15000, 15000);
    ref.read(sharedPrefsProvider).setInt('lyrics_offset_$trackId', ms);
    setState(() {});
  }

  Future<void> _selectSource(Track track, LyricsSource? source) async {
    final prefs = ref.read(sharedPrefsProvider);
    final key = 'lyrics_source_${track.id}';
    if (source == null) {
      await prefs.remove(key); // back to auto
    } else {
      // The picker only offers sources it verified, so no re-check here.
      await prefs.setString(key, source.name);
    }
    ref.invalidate(lyricsProvider(track.id));
    if (mounted) setState(() {});
  }

  void _showSourcePicker(BuildContext context, Track track) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _SourcePickerSheet(
        track: track,
        onSelect: (source) => _selectSource(track, source),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    // Follow playback: if the song changes while the sheet is open,
    // show the new song's lyrics instead of going stale.
    final track =
        ref.watch(audioStateProvider).value?.currentTrack ?? widget.track;
    final lyrics = ref.watch(lyricsProvider(track.id));
    final offset = _offsetFor(track.id);

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
              // Small decode: it's blurred to a wash anyway, and full-res
              // art here makes the raster thread struggle (freezes on
              // surface re-creation, e.g. after the notification shade).
              child: Image.file(File(track.albumArtPath!),
                  fit: BoxFit.cover, cacheWidth: 200, gaplessPlayback: true),
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
                if (lyrics.value != null) ...[
                  const SizedBox(height: Space.s1),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => _showSourcePicker(context, track),
                        child:
                            _QualityBadge(lyrics: lyrics.value!, theme: theme),
                      ),
                      if (lyrics.value!.isSynced) ...[
                        const SizedBox(width: Space.s2),
                        _OffsetControl(
                          offset: offset,
                          theme: theme,
                          onAdjust: (delta) =>
                              _adjustOffset(track.id, delta),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: Space.s3),
                Expanded(
                  child: lyrics.when(
                    loading: () => Center(
                        child: CircularProgressIndicator(
                            color: theme.primary)),
                    error: (_, __) => _NoLyrics(
                        theme: theme,
                        onPickSource: () =>
                            _showSourcePicker(context, track)),
                    data: (l) => l == null || l.isEmpty
                        ? _NoLyrics(
                            theme: theme,
                            onPickSource: () =>
                                _showSourcePicker(context, track))
                        : l.isSynced
                            ? _KaraokeLines(
                                key: ValueKey(track.id),
                                lyrics: l,
                                theme: theme,
                                offset: offset,
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

/// Nudges lyric timing for this track: − plays lyrics earlier, + later.
/// For local files that are a different master than the timing source.
class _OffsetControl extends StatelessWidget {
  const _OffsetControl({
    required this.offset,
    required this.theme,
    required this.onAdjust,
  });

  final Duration offset;
  final HanamimiTheme theme;
  final ValueChanged<int> onAdjust;

  @override
  Widget build(BuildContext context) {
    final seconds = offset.inMilliseconds / 1000;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s1),
      decoration: BoxDecoration(
        color: theme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
            color: theme.divider.withValues(alpha: 0.8), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _nudge(Icons.remove, () => onAdjust(-500)),
          GestureDetector(
            onLongPress: () => onAdjust(-offset.inMilliseconds),
            child: Text(
              '${seconds >= 0 ? '+' : ''}${seconds.toStringAsFixed(1)}s',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: offset == Duration.zero
                    ? theme.textPrimary
                    : theme.accent,
              ),
            ),
          ),
          _nudge(Icons.add, () => onAdjust(500)),
        ],
      ),
    );
  }

  Widget _nudge(IconData icon, VoidCallback onTap) => InkResponse(
        onTap: onTap,
        radius: 16,
        child: Padding(
          padding: const EdgeInsets.all(Space.s1),
          child: Icon(icon, size: 14, color: theme.textPrimary),
        ),
      );
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.lyrics, required this.theme});

  final Lyrics lyrics;
  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context) {
    final label = switch (lyrics.quality) {
      2 => 'Word-synced',
      1 => 'Line-synced',
      _ => 'Unsynced',
    };
    final sourceName = switch (lyrics.source) {
      LyricsSource.embedded => 'embedded',
      LyricsSource.musixmatch => 'Musixmatch',
      LyricsSource.lrclib => 'LRCLIB',
    };
    // Sits on the blurred album-art backdrop: needs a solid surface
    // chip so it stays legible on every theme.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: 3),
      decoration: BoxDecoration(
        color: theme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
          color: theme.primary
              .withValues(alpha: lyrics.quality == 2 ? 0.9 : 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            lyrics.quality == 2 ? Icons.graphic_eq : Icons.notes,
            size: 11,
            color: theme.primary,
          ),
          const SizedBox(width: 3),
          Text(
            '$label · $sourceName',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: theme.textPrimary,
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

/// One slot in the scrolling list: either a lyric line or an interlude
/// (intro / instrumental break) rendered as filling dots.
class _Entry {
  _Entry.line(this.lineIndex, this.start) : interludeEnd = null;
  _Entry.interlude(this.start, Duration this.interludeEnd)
      : lineIndex = null;

  final int? lineIndex;
  final Duration start;
  final Duration? interludeEnd;

  bool get isInterlude => lineIndex == null;
}

class _KaraokeLines extends ConsumerStatefulWidget {
  const _KaraokeLines({
    super.key,
    required this.lyrics,
    required this.theme,
    this.offset = Duration.zero,
  });

  final Lyrics lyrics;
  final HanamimiTheme theme;

  /// Per-track sync nudge: positive = lyrics wait longer (for files
  /// with extra intro silence vs. the version the timings match).
  final Duration offset;

  @override
  ConsumerState<_KaraokeLines> createState() => _KaraokeLinesState();
}

class _KaraokeLinesState extends ConsumerState<_KaraokeLines>
    with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  late final Ticker _ticker;
  late final List<List<_TimedWord>> _timedLines;
  late final List<_Entry> _entries;

  // Last position report from the player, and when we received it —
  // the ticker extrapolates between reports so the word fill glides
  // instead of stepping at the stream's update rate.
  Duration _lastPosition = Duration.zero;
  late final Stopwatch _sinceReport = Stopwatch();
  Duration _builtPosition = Duration.zero;
  int _scrolledTo = -2;

  static const _lineExtent = 72.0;

  /// Intro shorter than this just shows dim upcoming lines.
  static const _introInterlude = Duration(seconds: 3);

  /// Vocal gap that earns an instrumental-break indicator.
  static const _gapInterlude = Duration(seconds: 7);

  @override
  void initState() {
    super.initState();
    final lines = widget.lyrics.lines;
    _timedLines = [
      for (var i = 0; i < lines.length; i++) _resolveWords(lines, i),
    ];
    _entries = _buildEntries(lines);

    // Seed from the player's current position so opening the sheet
    // mid-song doesn't flash the first line.
    _lastPosition = ref.read(positionProvider).value ?? Duration.zero;
    _sinceReport.start();

    // Skip frames where the position hasn't moved (paused, buffering)
    // instead of rebuilding the whole line list at the display rate.
    _ticker = createTicker((_) {
      final pos = _smoothPosition;
      if (pos == _builtPosition) return;
      _builtPosition = pos;
      setState(() {});
    })..start();
  }

  /// When the singing of line [index] actually stops: richsync `te`,
  /// or the end of the last (possibly synthesized) word.
  Duration _lineEnd(int index) {
    final end = widget.lyrics.lines[index].end;
    if (end != null) return end;
    final words = _timedLines[index];
    return words.isEmpty
        ? widget.lyrics.lines[index].timestamp
        : words.last.end;
  }

  List<_Entry> _buildEntries(List<LyricLine> lines) {
    final entries = <_Entry>[];
    if (lines.isNotEmpty && lines.first.timestamp >= _introInterlude) {
      entries.add(_Entry.interlude(Duration.zero, lines.first.timestamp));
    }
    for (var i = 0; i < lines.length; i++) {
      entries.add(_Entry.line(i, lines[i].timestamp));
      if (i + 1 < lines.length) {
        final vocalEnd = _lineEnd(i);
        if (lines[i + 1].timestamp - vocalEnd >= _gapInterlude) {
          entries.add(_Entry.interlude(vocalEnd, lines[i + 1].timestamp));
        }
      }
    }
    return entries;
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
      // Richsync tells us when the vocal ends; sources without a line
      // end get the last word capped at 2s so a trailing word never
      // keeps filling through an instrumental break.
      final lastEnd = line.end ??
          _min(nextStart, words.last.start + const Duration(seconds: 2));
      return [
        for (var w = 0; w < words.length; w++)
          _TimedWord(
            words[w].text,
            words[w].start,
            w + 1 < words.length ? words[w + 1].start : lastEnd,
          ),
      ];
    }
    final lineEnd = line.end ?? nextStart;

    final tokens =
        line.text.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return [];
    final gapMs =
        (lineEnd - line.timestamp).inMilliseconds.clamp(400, 30000);
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

  static Duration _min(Duration a, Duration b) => a < b ? a : b;

  /// Tap a line → jump the song there. The offset is added back since
  /// entry times live in lyrics-time, not player-time.
  void _seekToEntry(_Entry entry) {
    var target = entry.start + widget.offset;
    if (target < Duration.zero) target = Duration.zero;
    ref.read(audioHandlerProvider).seek(target);
    // Snap the local clock immediately so the highlight doesn't lag
    // behind the tap while waiting for the next position report.
    _lastPosition = target;
    _sinceReport
      ..reset()
      ..start();
  }

  Duration get _smoothPosition {
    final playing =
        ref.read(audioStateProvider).value?.isPlaying ?? false;
    final raw =
        playing ? _lastPosition + _sinceReport.elapsed : _lastPosition;
    return raw - widget.offset;
  }

  /// Last entry whose start has passed, or -1 before everything.
  int _activeEntry(Duration position) {
    var lo = -1, hi = _entries.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_entries[mid].start <= position) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
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
    final active = _activeEntry(position);
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
            itemCount: _entries.length,
            itemExtent: _lineExtent,
            itemBuilder: (context, i) {
              final entry = _entries[i];
              final isActive = i == active;
              final isPast = i < active;

              if (entry.isInterlude) {
                return RepaintBoundary(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _seekToEntry(entry),
                    child: _InterludeDots(
                      start: entry.start,
                      end: entry.interludeEnd!,
                      position: position,
                      active: isActive,
                      color: bright,
                    ),
                  ),
                );
              }

              final lineIndex = entry.lineIndex!;
              return RepaintBoundary(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _seekToEntry(entry),
                  child: AnimatedScale(
                  scale: isActive ? 1.0 : 0.92,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOut,
                  child: Center(
                    child: isActive
                        ? _KaraokeLine(
                            words: _timedLines[lineIndex],
                            position: position,
                            bright: bright,
                            dim: bright.withValues(alpha: 0.35),
                          )
                        : Text(
                            lines[lineIndex].text,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            // beautiful-lyrics line opacities:
                            // idle 0.51, sung ~0.50.
                            style: AppText.body(theme).copyWith(
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                              color: bright.withValues(
                                  alpha: isPast ? 0.45 : 0.51),
                            ),
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

/// Instrumental indicator: three dots that fill across the break, with
/// a gentle breathing pulse while active (Beautiful Lyrics-style).
class _InterludeDots extends StatelessWidget {
  const _InterludeDots({
    required this.start,
    required this.end,
    required this.position,
    required this.active,
    required this.color,
  });

  final Duration start;
  final Duration end;
  final Duration position;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final totalMs = (end - start).inMilliseconds;
    final progress = totalMs <= 0
        ? 1.0
        : ((position - start).inMilliseconds / totalMs).clamp(0.0, 1.0);
    // Ease the last two seconds out so the dots feel like a lead-in.
    final breathe = active
        ? 1.0 + 0.12 * math.sin(position.inMilliseconds / 320)
        : 1.0;

    return Center(
      child: Transform.scale(
        scale: breathe,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var d = 0; d < 3; d++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(
                      alpha: !active
                          ? 0.18
                          : progress >= (d + 1) / 3
                              ? 0.9
                              : 0.25,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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

/// Animation curves ported from beautiful-lyrics (SyllableVocals.ts):
/// while a word is being sung it scales 0.95 → 1.025 (peak at 70% of
/// its duration) → 1.0, lifts slightly, and glows — with a feathered
/// gradient fill edge instead of a hard clip.
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

    final t = fraction;
    final scale = t < 0.7
        ? lerpDouble(0.95, 1.025, t / 0.7)!
        : lerpDouble(1.025, 1.0, (t - 0.7) / 0.3)!;
    final fontSize = style.fontSize ?? 18;
    final lift = (t < 0.9
            ? lerpDouble(0.010, -0.017, t / 0.9)!
            : lerpDouble(-0.017, 0, (t - 0.9) / 0.1)!) *
        fontSize;
    final glow = t < 0.15
        ? t / 0.15
        : t < 0.6
            ? 1.0
            : 1 - (t - 0.6) / 0.4;

    final glowing = style.copyWith(
      color: bright,
      shadows: [
        Shadow(
          color: bright.withValues(alpha: 0.65 * glow),
          blurRadius: fontSize * 0.7 * glow,
        ),
      ],
    );

    return Transform.translate(
      offset: Offset(0, lift),
      child: Transform.scale(
        scale: scale,
        child: Stack(
          children: [
            Text(text, style: style.copyWith(color: dim)),
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => LinearGradient(
                colors: const [Colors.white, Colors.transparent],
                stops: [
                  (t - 0.12).clamp(0.0, 1.0),
                  (t + 0.12).clamp(0.0, 1.0),
                ],
              ).createShader(rect),
              child: Text(text, style: glowing),
            ),
          ],
        ),
      ),
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
  const _NoLyrics({required this.theme, this.onPickSource});

  final HanamimiTheme theme;
  final VoidCallback? onPickSource;

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
          if (onPickSource != null) ...[
            const SizedBox(height: Space.s2),
            TextButton(
              onPressed: onPickSource,
              child: Text(
                'Try another source',
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: theme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Source picker that probes each provider first: sources with nothing
/// for this song are greyed out and labeled instead of silently doing
/// nothing when tapped.
class _SourcePickerSheet extends ConsumerStatefulWidget {
  const _SourcePickerSheet({required this.track, required this.onSelect});

  final Track track;
  final ValueChanged<LyricsSource?> onSelect;

  @override
  ConsumerState<_SourcePickerSheet> createState() =>
      _SourcePickerSheetState();
}

class _SourcePickerSheetState extends ConsumerState<_SourcePickerSheet> {
  // Missing key = still probing.
  final Map<LyricsSource, bool> _available = {};

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    final repo = await ref.read(libraryRepositoryProvider.future);
    final service = LyricsService(repo);
    for (final source in LyricsSource.values) {
      // Fire concurrently; each row updates as its answer lands.
      service.fetchFromSource(widget.track, source).then((lyrics) {
        if (mounted) setState(() => _available[source] = lyrics != null);
      }).catchError((_) {
        if (mounted) setState(() => _available[source] = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final current = ref
        .read(sharedPrefsProvider)
        .getString('lyrics_source_${widget.track.id}');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lyrics source',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.textPrimary)),
            const SizedBox(height: Space.s2),
            for (final (name, source, subtitle) in [
              ('Auto', null, 'Best available quality'),
              (
                'Embedded',
                LyricsSource.embedded,
                'From the audio file\'s own tags'
              ),
              (
                'Musixmatch',
                LyricsSource.musixmatch,
                'Word-synced (online)'
              ),
              ('LRCLIB', LyricsSource.lrclib, 'Line-synced (online)'),
            ])
              _buildRow(theme, name, source, subtitle, current),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(HanamimiTheme theme, String name, LyricsSource? source,
      String subtitle, String? current) {
    // Auto is always offered; concrete sources once verified.
    final available = source == null ? true : _available[source];
    final probing = available == null;
    final selected = (current == null && source == null) ||
        (source != null && current == source.name);

    return ListTile(
      enabled: available ?? false,
      title: Text(name,
          style: AppText.rowSongTitle(theme).copyWith(
            color: (available ?? false)
                ? theme.textPrimary
                : theme.textMuted.withValues(alpha: 0.6),
          )),
      subtitle: Text(
        available == false ? 'Not found for this song' : subtitle,
        style: AppText.caption(theme),
      ),
      trailing: probing
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: theme.textMuted),
            )
          : selected
              ? Icon(Icons.check, size: 20, color: theme.primary)
              : null,
      onTap: (available ?? false)
          ? () {
              Navigator.pop(context);
              widget.onSelect(source);
            }
          : null,
    );
  }
}
