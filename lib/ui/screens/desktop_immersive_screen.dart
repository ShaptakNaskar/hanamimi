import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lyrics/lrc_parser.dart';
import '../../providers/audio_provider.dart';
import '../../providers/lyrics_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../components/now_playing/playback_controls.dart';
import '../components/now_playing/seek_bar_widget.dart';
import '../components/now_playing/visualizer_widget.dart';
import '../modals/queue_sheet.dart';
import '../modals/sleep_timer_modal.dart';

/// Full-window desktop Now Playing (M31, the user's "image 3"):
/// blurred album art fills the window, big art + seek + controls +
/// visualizer breathe on the left, and oversized synced lyrics scroll
/// on the right — the spicy-lyrics look, in Hanamimi's own voice.
/// Esc or the collapse button returns to the three-pane shell.
class DesktopImmersiveScreen extends ConsumerWidget {
  const DesktopImmersiveScreen({super.key});

  static Route<void> route() => PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, __, ___) => const DesktopImmersiveScreen(),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final audio = ref.watch(audioStateProvider).value;
    final track = audio?.currentTrack;

    if (track == null) {
      // Track cleared while immersive — nothing to show, fall back.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      });
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: theme.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _ImmersiveBackground(track: track, theme: theme),
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: Space.s6),
                        child: _LeftColumn(
                            track: track, theme: theme, ref: ref),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.only(right: Space.s6),
                    child: _ImmersiveLyrics(track: track, theme: theme),
                  ),
                ),
              ],
            ),
          ),
          // Collapse, top-right — mirrors the expand affordance.
          Positioned(
            top: Space.s3,
            right: Space.s3,
            child: IconButton(
              tooltip: 'Back to library (Esc)',
              onPressed: () => Navigator.of(context).pop(),
              icon: Icon(Icons.close_fullscreen_rounded,
                  size: 20, color: theme.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Heavy-blur art wash. Softer overlay than the phone Now Playing so
/// the cover's color really owns the room (spicy-lyrics energy).
class _ImmersiveBackground extends StatelessWidget {
  const _ImmersiveBackground({required this.track, required this.theme});

  final dynamic track;
  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context) {
    final artPath = track.albumArtPath as String?;
    final artUrl = track.artUrl as String?;
    ImageProvider? image;
    if (artPath != null) {
      image = FileImage(File(artPath));
    } else if (artUrl != null) {
      image = NetworkImage(artUrl);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        if (image != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: Image(image: image, fit: BoxFit.cover),
          ),
        Container(color: theme.background.withValues(alpha: 0.72)),
      ],
    );
  }
}

class _LeftColumn extends ConsumerStatefulWidget {
  const _LeftColumn(
      {required this.track, required this.theme, required this.ref});

  final dynamic track;
  final HanamimiTheme theme;
  final WidgetRef ref;

  @override
  ConsumerState<_LeftColumn> createState() => _LeftColumnState();
}

class _LeftColumnState extends ConsumerState<_LeftColumn> {
  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final track = widget.track;
    final audio = ref.watch(audioStateProvider).value;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final duration = audio?.duration ?? Duration.zero;
    final engine = ref.read(audioHandlerProvider).engine;

    final artPath = track.albumArtPath as String?;
    final artUrl = track.artUrl as String?;

    return LayoutBuilder(builder: (context, constraints) {
      final artSize = (constraints.maxHeight * 0.42).clamp(160.0, 380.0);
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: artSize,
            height: artSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.lg),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
              image: artPath != null
                  ? DecorationImage(
                      image: FileImage(File(artPath)), fit: BoxFit.cover)
                  : artUrl != null
                      ? DecorationImage(
                          image: NetworkImage(artUrl), fit: BoxFit.cover)
                      : null,
              color: theme.surface,
            ),
            child: artPath == null && artUrl == null
                ? Icon(Icons.music_note, size: 64, color: theme.textMuted)
                : null,
          ),
          const SizedBox(height: Space.s6),
          Text(
            track.title as String,
            style: AppText.npSongTitle(theme).copyWith(fontSize: 24),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.s1),
          Text(
            track.artist as String,
            style: AppText.npArtist(theme),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.s6),
          SeekBarWidget(
            position: position,
            duration: duration,
            theme: theme,
            onSeek: engine.seek,
          ),
          const SizedBox(height: Space.s4),
          PlaybackControls(
            onSleepTimer: () => showSleepTimerModal(context),
            onQueue: () => showQueueSheet(context),
          ),
          const SizedBox(height: Space.s6),
          const VisualizerWidget(height: 64),
        ],
      );
    });
  }
}

/// Oversized synced lyrics, active line lit, neighbors dimmed by
/// distance; tap a line to seek (honoring the per-track sync offset).
class _ImmersiveLyrics extends ConsumerStatefulWidget {
  const _ImmersiveLyrics({required this.track, required this.theme});

  final dynamic track;
  final HanamimiTheme theme;

  @override
  ConsumerState<_ImmersiveLyrics> createState() => _ImmersiveLyricsState();
}

class _ImmersiveLyricsState extends ConsumerState<_ImmersiveLyrics> {
  final _scroll = ScrollController();
  final _lineKeys = <int, GlobalKey>{};
  int _active = -1;
  Timer? _clock;
  Duration _lastReported = Duration.zero;
  final _sinceReport = Stopwatch();

  @override
  void initState() {
    super.initState();
    // Extrapolated position clock (the lyrics-sheet pattern) so the
    // highlight glides between the player's position reports.
    _clock = Timer.periodic(const Duration(milliseconds: 120), (_) {
      _tick();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Duration get _offset => Duration(
      milliseconds: ref
              .read(sharedPrefsProvider)
              .getInt('lyrics_offset_${widget.track.id}') ??
          0);

  void _tick() {
    final lyrics = ref
        .read(lyricsProvider(widget.track.id as int))
        .value;
    if (lyrics == null || !lyrics.isSynced || !mounted) return;
    final playing =
        ref.read(audioStateProvider).value?.isPlaying ?? false;
    final position = playing
        ? _lastReported + _sinceReport.elapsed
        : _lastReported;
    final active =
        LrcParser.activeLine(lyrics.lines, position + _offset);
    if (active != _active) {
      setState(() => _active = active);
      final key = _lineKeys[active];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.38,
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeInOutCubic,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    ref.listen(positionProvider, (_, next) {
      final pos = next.value;
      if (pos != null) {
        _lastReported = pos;
        _sinceReport
          ..reset()
          ..start();
      }
    });
    final lyricsAsync = ref.watch(lyricsProvider(widget.track.id as int));

    return lyricsAsync.when(
      loading: () => Center(
          child: CircularProgressIndicator(color: theme.primary)),
      error: (_, __) => _empty(theme),
      data: (lyrics) {
        if (lyrics == null || lyrics.lines.isEmpty) return _empty(theme);
        final engine = ref.read(audioHandlerProvider).engine;
        return ShaderMask(
          // Feather the top/bottom so lines dissolve instead of clipping.
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [0.0, 0.12, 0.85, 1.0],
          ).createShader(rect),
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
            controller: _scroll,
            padding: EdgeInsets.symmetric(
              vertical: MediaQuery.sizeOf(context).height * 0.35,
            ),
            itemCount: lyrics.lines.length,
            itemBuilder: (context, i) {
              final line = lyrics.lines[i];
              final isActive = lyrics.isSynced && i == _active;
              final distance = _active < 0 ? 1 : (i - _active).abs();
              final opacity = !lyrics.isSynced
                  ? 0.8
                  : isActive
                      ? 1.0
                      : (0.55 - distance * 0.07).clamp(0.18, 0.55);
              _lineKeys[i] ??= GlobalKey();
              return InkWell(
                key: _lineKeys[i],
                onTap: lyrics.isSynced
                    ? () {
                        final target = line.timestamp - _offset;
                        engine.seek(
                            target.isNegative ? Duration.zero : target);
                      }
                    : null,
                borderRadius: BorderRadius.circular(Radii.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: Space.s3, horizontal: Space.s3),
                  child: AnimatedScale(
                    scale: isActive ? 1.0 : 0.97,
                    alignment: Alignment.centerLeft,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                    child: AnimatedOpacity(
                      opacity: opacity,
                      duration: const Duration(milliseconds: 350),
                      child: Text(
                        line.text.isEmpty ? '· · ·' : line.text,
                        style: TextStyle(
                          fontFamily: 'Nunito',
                          fontSize: 34,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: isActive
                              ? theme.textPrimary
                              : theme.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _empty(HanamimiTheme theme) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lyrics_outlined, size: 42, color: theme.textMuted),
            const SizedBox(height: Space.s3),
            Text('No lyrics found', style: AppText.body(theme)),
            const SizedBox(height: Space.s1),
            Text('Enjoy the visualizer instead 🌸',
                style: AppText.caption(theme)),
          ],
        ),
      );
}
