import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/track.dart';
import '../../providers/audio_provider.dart';
import '../../providers/power_provider.dart';
import '../../providers/sleep_timer_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/visualizer_provider.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../../utils/duration_ext.dart';
import '../components/mascot/oneko.dart';
import '../components/now_playing/visualizer_widget.dart';
import '../components/now_playing/wipe_reveal.dart';

/// The stare screen — one surface, two skins, flipped by the 💡 button.
///
/// * **Blackout** (dark, the default): the bedside amp — OLED-black
///   canvas, a big dim clock, the oneko cat asleep in the corner (she
///   stirs on track change instead of a text notification), a brightness
///   floor you can pin off with the eye, muted meters.
/// * **Visualizer** (light): the same meters in full album color over a
///   blurred art wash, no clock, no dim — just the pretty visualization
///   to stare at.
///
/// Opened dark from the Blackout button, light from tapping the Now
/// Playing / immersive visualizer; the lightbulb toggles between the two
/// in place. One module instead of two near-identical screens.
///
/// Affordable as an always-on surface because the visualizer's ticker
/// gating (the constant-CPU fix) already stops all motion when frames
/// settle. Screen stays awake; tap anywhere for controls, ✕ to leave.
class BlackoutScreen extends ConsumerStatefulWidget {
  const BlackoutScreen({super.key, this.light = false});

  /// Initial skin: false = Blackout (dark), true = Visualizer (light).
  final bool light;

  static Route<void> route({bool light = false}) => PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, __, ___) => BlackoutScreen(light: light),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      );

  @override
  ConsumerState<BlackoutScreen> createState() => _BlackoutScreenState();
}

class _BlackoutScreenState extends ConsumerState<BlackoutScreen> {
  Timer? _clock;
  Timer? _controlsHide;
  var _now = DateTime.now();
  var _controlsVisible = false;
  var _stir = 0;
  int? _lastTrackId;

  /// Which skin is showing — starts from the entry point, the 💡 flips it.
  late bool _light = widget.light;

  /// Caffeine's state, cached on every build — dispose() must not touch
  /// ref (a throw there silently skipped the system restores below and
  /// left the phone stuck fullscreen + awake until force stop,
  /// user-reported).
  var _caffeineOn = false;
  var _restored = false;

  @override
  void initState() {
    super.initState();
    _scheduleClock();
    PowerChannel.setKeepScreenOn(true);
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    // The dimming is a scrim INSIDE this screen (see build), not a
    // window-brightness override. The screen_brightness override left
    // Nothing OS refusing slider input after exit — "the top app is
    // controlling brightness" — until the whole app was killed
    // (user-reported). On an OLED over a pure-black canvas the scrim
    // dims emitted light just the same, and it cannot outlive the
    // route by construction.
  }

  /// Puts the system back the way we found it: edge-to-edge UI, screen
  /// allowed to sleep (unless Caffeine ☕ holds it). Idempotent; runs at
  /// pop time via PopScope while the route is fully alive, with
  /// dispose() as the fallback for any exit that skips the pop path.
  void _restoreSystem() {
    if (_restored) return;
    _restored = true;
    if (Platform.isAndroid) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (!_caffeineOn) PowerChannel.setKeepScreenOn(false);
  }

  /// Ticks exactly on the minute — 1 rebuild/min, not a polling loop.
  void _scheduleClock() {
    final now = DateTime.now();
    final nextMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute + 1,
    );
    _clock = Timer(nextMinute.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleClock();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _controlsHide?.cancel();
    _restoreSystem();
    super.dispose();
  }

  void _tap() {
    setState(() => _controlsVisible = !_controlsVisible);
    _armHide();
  }

  /// (Re)starts the auto-hide countdown while the overlay is up.
  void _armHide() {
    _controlsHide?.cancel();
    if (_controlsVisible) {
      _controlsHide = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _controlsVisible = false);
      });
    }
  }

  /// Analog needles wear the big bedside-dial size; the LED VU and bars
  /// read as a stretched wall of pixels that tall — they keep their Now
  /// Playing proportion (user report).
  double _vizHeight(VisualizerStyle style) => switch (style) {
        VisualizerStyle.vuMeters => 200.0,
        VisualizerStyle.ledVu => 56.0,
        _ => 64.0,
      };

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final audio = ref.watch(audioStateProvider).value;
    final track = audio?.currentTrack;
    _caffeineOn = ref.watch(caffeineProvider);
    final timer = ref.watch(sleepTimerProvider);
    // Eye lock (dark only): keep the meters at full brightness (no
    // auto-dim) so you can just stare. Scrim drops to 0 when this is on
    // OR the transport is up.
    final undim = ref.watch(blackoutUndimProvider);
    final style = ref.watch(blackoutStyleProvider);
    final isVu = style == VisualizerStyle.vuMeters ||
        style == VisualizerStyle.ledVu;
    final isLed = style == VisualizerStyle.ledVu;
    // Crossfade (light skin): wipe the art wash + title across to the
    // incoming song in step with the audio, so the stare view doesn't
    // sit on the previous track while the next one is already playing.
    final incoming = audio?.crossfadeIncomingTrack;
    final xfT = ref.read(audioHandlerProvider).engine.crossfadeT;

    // The cat is the notification: stir her when the track changes.
    if (track != null && track.id != _lastTrackId) {
      if (_lastTrackId != null) _stir++;
      _lastTrackId = track.id;
    }

    final dim = Colors.white.withValues(alpha: 0.55);
    final dimmer = Colors.white.withValues(alpha: 0.30);
    // Chrome tint: album-legible in light, soft white in the dark.
    final tint = _light ? theme.textPrimary : dim;
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');

    return PopScope(
      // Any pop — ✕ button, back gesture, predictive back — restores
      // the system BEFORE the route starts tearing down.
      onPopInvokedWithResult: (_, __) => _restoreSystem(),
      child: Scaffold(
        // Hard black underneath — the OLED canvas of the dark skin; the
        // light skin's art wash fades in over it.
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Light skin: blurred album wash. Fades in/out over the
              // black as the 💡 flips, so the toggle glides.
              IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity: _light ? 1 : 0,
                  // Dark skin never shows the wash — don't pay to decode
                  // and blur album art for the bedside amp.
                  child: !_light
                      ? const SizedBox.shrink()
                      : track == null
                          ? Container(color: theme.background)
                          : incoming != null
                              ? ValueListenableBuilder<double>(
                                  valueListenable: xfT,
                                  builder: (_, t, __) {
                                    final e =
                                        Curves.easeInOut.transform(t);
                                    return Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        _ArtWash(track: track, theme: theme),
                                        WipeReveal(
                                          progress: e,
                                          child: _ArtWash(
                                              track: incoming, theme: theme),
                                        ),
                                      ],
                                    );
                                  },
                                )
                              : _ArtWash(track: track, theme: theme),
                ),
              ),
              // The content — ONE layout for both skins, so the 💡
              // choreographs pieces instead of swapping screens: the
              // clock block fades (dark only), the meters slide between
              // their two seats, the title fades (light only).
              _body(theme, track, style, timer, dim, dimmer, hh, mm,
                  incoming, xfT),
              // The corner cat — the real oneko chase brain chasing a
              // hardcoded "cursor": her corner seat when the room is
              // dark, a spot past the left edge when it lights up. She
              // walks in, settles, fidgets and naps on her own logic,
              // and a track change stirs her by nudging the target.
              Positioned.fill(
                child: IgnorePointer(
                  child: BlackoutOneko(
                    present: !_light,
                    stir: _stir,
                    seat: (area) => Offset(
                      area.width - Space.s6 - 16,
                      area.height - Space.s6 - 16,
                    ),
                  ),
                ),
              ),
              // The brightness floor (dark skin only), as pixels instead
              // of a window override: dims while idle, lifts when the
              // transport is up (or the eye is locked) so buttons stay
              // crisp. Always in the tree so the dim eases away when the
              // 💡 flips to light instead of vanishing in one frame.
              IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 400),
                  opacity:
                      (_light || _controlsVisible || undim) ? 0.0 : 0.45,
                  child: Container(color: Colors.black),
                ),
              ),
              // Tap-to-reveal chrome; fades itself away after 5 s.
              AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: _controlsVisible ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Stack(
                    children: [
                      // Top-right: light/dark toggle, then leave.
                      Positioned(
                        top: Space.s6,
                        right: Space.s6,
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: _light
                                  ? 'Dim to Blackout'
                                  : 'Light it up',
                              icon: Icon(
                                _light
                                    ? Icons.lightbulb_rounded
                                    : Icons.lightbulb_outline_rounded,
                                color: _light ? theme.primary : dim,
                              ),
                              onPressed: () {
                                setState(() => _light = !_light);
                                _armHide();
                              },
                            ),
                            IconButton(
                              tooltip: 'Close',
                              icon: Icon(Icons.close_rounded, color: tint),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),
                      // Top-left: switch the visualization, and its
                      // per-style knobs (VU source, LED look). The eye
                      // (undim lock) only means anything in the dark.
                      Positioned(
                        top: Space.s6,
                        left: Space.s6,
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Switch visualization',
                              icon:
                                  Icon(Icons.equalizer_rounded, color: tint),
                              onPressed: () {
                                final styles = VisualizerStyle.values;
                                final current =
                                    ref.read(blackoutStyleProvider);
                                ref.read(blackoutStyleProvider.notifier).set(
                                      styles[(current.index + 1) %
                                          styles.length],
                                    );
                                _armHide();
                              },
                            ),
                            if (isVu)
                              _pill(
                                Icons.tune_rounded,
                                ref.watch(vuSplitProvider)
                                    ? 'Bass / treble'
                                    : 'Loudness',
                                tint,
                                () {
                                  final on = ref.read(vuSplitProvider);
                                  ref.read(vuSplitProvider.notifier).set(!on);
                                  _armHide();
                                },
                              ),
                            if (isLed)
                              _pill(
                                ref.watch(ledVuDiscreteProvider)
                                    ? Icons.view_week_rounded
                                    : Icons.gradient_rounded,
                                ref.watch(ledVuDiscreteProvider)
                                    ? 'Segments'
                                    : 'Solid',
                                tint,
                                () {
                                  final on = ref.read(ledVuDiscreteProvider);
                                  ref
                                      .read(ledVuDiscreteProvider.notifier)
                                      .set(!on);
                                  _armHide();
                                },
                              ),
                            if (!_light)
                              IconButton(
                                tooltip: undim
                                    ? 'Let the screen dim'
                                    : 'Keep the meters bright',
                                icon: Icon(
                                  undim
                                      ? Icons.remove_red_eye_rounded
                                      : Icons.remove_red_eye_outlined,
                                  color: undim
                                      ? Colors.white.withValues(alpha: 0.75)
                                      : dim,
                                ),
                                onPressed: () {
                                  ref
                                      .read(blackoutUndimProvider.notifier)
                                      .toggle();
                                  _armHide();
                                },
                              ),
                          ],
                        ),
                      ),
                      if (timer.isActive)
                        Align(
                          alignment: const Alignment(0, 0.62),
                          child: TextButton.icon(
                            onPressed: () {
                              ref.read(sleepTimerProvider.notifier).cancel();
                              _armHide();
                            },
                            icon: Icon(Icons.bedtime_off_rounded,
                                size: 16, color: tint),
                            label: Text('Cancel sleep timer',
                                style: TextStyle(
                                  fontFamily: 'Nunito',
                                  fontSize: 13,
                                  color: tint,
                                )),
                          ),
                        ),
                      Align(
                        alignment: const Alignment(0, 0.82),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              iconSize: 34,
                              icon: Icon(Icons.skip_previous_rounded,
                                  color: tint),
                              onPressed: () => ref
                                  .read(audioHandlerProvider)
                                  .skipToPrevious(),
                            ),
                            const SizedBox(width: Space.s4),
                            IconButton(
                              iconSize: 44,
                              icon: Icon(
                                (audio?.isPlaying ?? false)
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: _light
                                    ? theme.primary
                                    : Colors.white.withValues(alpha: 0.75),
                              ),
                              onPressed: () {
                                final h = ref.read(audioHandlerProvider);
                                (audio?.isPlaying ?? false)
                                    ? h.pause()
                                    : h.play();
                              },
                            ),
                            const SizedBox(width: Space.s4),
                            IconButton(
                              iconSize: 34,
                              icon:
                                  Icon(Icons.skip_next_rounded, color: tint),
                              onPressed: () =>
                                  ref.read(audioHandlerProvider).skipToNext(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One merged layout for both skins, so the 💡 flip choreographs the
  /// pieces instead of swapping screens:
  ///
  /// * the clock block (clock, song line, sleep status) fades in as the
  ///   room goes dark and out as it lights up;
  /// * the meters are ONE widget that glides between the light skin's
  ///   centered seat and the dark skin's below-the-clock seat — they
  ///   keep dancing through the ride;
  /// * the title/artist under the meters fades with the light skin (and
  ///   still wipes across to the incoming song during a crossfade).
  Widget _body(
    HanamimiTheme theme,
    Track? track,
    VisualizerStyle style,
    SleepTimerState timer,
    Color dim,
    Color dimmer,
    String hh,
    String mm,
    Track? incoming,
    ValueNotifier<double> xfT,
  ) {
    Widget titleBlock() {
      if (track == null) return const SizedBox.shrink();
      if (incoming == null) {
        return _titleArtist(track, theme);
      }
      return ValueListenableBuilder<double>(
        valueListenable: xfT,
        builder: (_, t, __) {
          final e = Curves.easeInOut.transform(t);
          return Stack(
            alignment: Alignment.center,
            children: [
              WipeReveal(
                  progress: e,
                  invert: true,
                  child: _titleArtist(track, theme)),
              WipeReveal(progress: e, child: _titleArtist(incoming, theme)),
            ],
          );
        },
      );
    }

    return LayoutBuilder(builder: (context, c) {
      // Landscape (short) screens: the portrait stack — clock high,
      // meters at 42% — collides on ~400 dp of height (the song line
      // landed inside the VU dials, user screenshot). The bedside amp
      // goes side-by-side instead: clock block left, meters right. The
      // meters' AnimatedAlign carries the 💡 choreography either way.
      final compact = c.maxHeight < 560 && c.maxWidth > c.maxHeight;

      final clockBlock = Column(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          if (!compact) const Spacer(flex: 3),
          Text(
            '$hh:$mm',
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 72,
              fontWeight: FontWeight.w200,
              letterSpacing: 4,
              color: dim,
            ),
          ),
          if (track != null) ...[
            const SizedBox(height: Space.s2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s6),
              child: Text(
                '${track.title} — ${track.artist}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  color: dimmer,
                ),
              ),
            ),
          ],
          if (timer.isActive) ...[
            const SizedBox(height: Space.s4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bedtime_rounded, size: 13, color: dimmer),
                const SizedBox(width: Space.s2),
                Text(
                  switch (timer.mode) {
                    SleepMode.countdown => timer.isFading
                        ? 'fading out…'
                        : 'sleeping in ${timer.remaining!.mmss}',
                    SleepMode.endOfTrack => 'sleeping when this song ends',
                    SleepMode.off => '',
                  },
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    letterSpacing: 1,
                    color: dimmer,
                  ),
                ),
              ],
            ),
          ],
          if (!compact) const Spacer(flex: 5),
        ],
      );

      return Stack(
        fit: StackFit.expand,
        children: [
          // Bedside clock block — dark only. Its own half in landscape.
          AnimatedOpacity(
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOut,
            opacity: _light ? 0 : 1,
            child: compact
                ? Align(
                    alignment: const Alignment(-0.65, -0.1),
                    child: clockBlock,
                  )
                : clockBlock,
          ),
          // The meters, sliding between their two seats: centered in the
          // light; below the clock (portrait) or the right half
          // (landscape) in the dark. Width eases with them; `muted`
          // swaps the palette at the flip — the motion carries the
          // moment.
          AnimatedAlign(
            duration: const Duration(milliseconds: 550),
            curve: Curves.easeInOutCubic,
            alignment: _light
                ? Alignment.center
                : compact
                    ? const Alignment(0.75, 0)
                    : const Alignment(0, 0.42),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 550),
              curve: Curves.easeInOutCubic,
              constraints: BoxConstraints(
                  maxWidth: _light
                      ? 640
                      : compact
                          ? math.max(280.0, c.maxWidth * 0.42)
                          : 520),
              padding: const EdgeInsets.symmetric(horizontal: Space.s6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  VisualizerWidget(
                    height: _vizHeight(style),
                    styleOverride: style,
                    // Bedside palette in the dark: never album-art
                    // accents, nothing bright enough to sting at night.
                    muted: !_light,
                  ),
                  if (track != null) ...[
                    const SizedBox(height: Space.s6),
                    // Title rides with the meters; visible in the light.
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 450),
                      curve: Curves.easeOut,
                      opacity: _light ? 1 : 0,
                      child: titleBlock(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _titleArtist(Track t, HanamimiTheme theme) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: theme.textPrimary,
            ),
          ),
          const SizedBox(height: Space.s1),
          Text(
            t.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontSize: 13,
              color: theme.textMuted,
            ),
          ),
        ],
      );

  Widget _pill(IconData icon, String label, Color tint, VoidCallback onTap) =>
      TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: tint),
        label: Text(
          label,
          style: TextStyle(fontFamily: 'Nunito', fontSize: 12, color: tint),
        ),
      );
}

/// Heavy-blur album wash behind the meters, with a theme scrim so the
/// color reads as an ambient field, not a busy photo.
class _ArtWash extends StatelessWidget {
  const _ArtWash({required this.track, required this.theme});

  final Track track;
  final HanamimiTheme theme;

  ImageProvider? _art() {
    final artPath = track.albumArtPath;
    final artUrl = track.artUrl;
    ImageProvider? image;
    if (artPath != null) {
      image = FileImage(File(artPath));
    } else if (artUrl != null) {
      image = NetworkImage(artUrl);
    }
    return image == null ? null : ResizeImage(image, width: 200);
  }

  @override
  Widget build(BuildContext context) {
    final image = _art();
    // RepaintBoundary keeps the big blur out of the 60 fps meter frames.
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        child: KeyedSubtree(
          key: ValueKey(track.albumArtPath ?? track.artUrl ?? 'no-art'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: theme.background),
              if (image != null)
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
                  child: Image(image: image, fit: BoxFit.cover),
                ),
              Container(color: theme.background.withValues(alpha: 0.62)),
            ],
          ),
        ),
      ),
    );
  }
}
