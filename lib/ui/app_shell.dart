import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/models/playback_session.dart';
import '../library/models/track.dart';
import '../platform/gamepad_service.dart';
import '../providers/audio_provider.dart';
import '../providers/buddy_provider.dart';
import 'components/mascot/oneko.dart';
import '../providers/session_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/update_provider.dart';
import '../theme/app_theme.dart';
import '../theme/hanamimi_theme.dart';
import '../theme/theme_tokens.dart';
import '../utils/back_stack.dart';
import '../utils/duration_ext.dart';
import 'components/desktop/backdrop_wash.dart';
import 'components/desktop/library_sidebar.dart';
import 'components/mini_player.dart';
import 'components/shared/bottom_nav.dart';
import 'components/shared/particle_overlay.dart';
import 'modals/battery_prompt_dialog.dart';
import 'modals/update_dialog.dart';
import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/you_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  int _index = 0;
  int _previousIndex = 0;

  // VLC-style resume ticker: the saved session waiting to be resumed,
  // shown as a dismissible banner above the mini player (not a modal).
  PlaybackSession? _pendingResume;
  Timer? _resumeTimer;

  // Couch-mode gamepad → focus/transport.
  GamepadService? _gamepad;

  /// True while Hanamimi is foregrounded — gates gamepad input so a game
  /// in front can't drive the player.
  bool _appActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Couch mode: a gamepad drives focus + transport (ROG Ally etc.),
    // but only while Hanamimi is the active window.
    _gamepad = GamepadService(
      isActive: () => _appActive,
      onDirection: (dir) =>
          FocusManager.instance.primaryFocus?.focusInDirection(dir),
      onActivate: () {
        final ctx = FocusManager.instance.primaryFocus?.context;
        if (ctx != null) Actions.maybeInvoke(ctx, const ActivateIntent());
      },
      onBack: _onSystemBack,
      onPlayPause: () {
        final engine = ref.read(audioHandlerProvider).engine;
        engine.state.isPlaying ? engine.pause() : engine.play();
      },
      onNext: () => ref.read(audioHandlerProvider).engine.next(),
      onPrevious: () => ref.read(audioHandlerProvider).engine.previous(),
    )..start();
    // Offer to resume the previous session once, after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferResume());
    // First launch: ask for the battery-optimization exemption up front.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => maybeShowBatteryPrompt(context, ref));
    // If the user starts playing something else, the offer is moot —
    // drop the banner (the new session overwrites the saved one anyway).
    ref.listenManual(audioStateProvider, (_, next) {
      if (_pendingResume != null && (next.value?.isPlaying ?? false)) {
        _resumeTimer?.cancel();
        setState(() => _pendingResume = null);
      }
    });
    // One update check per launch (main-v releases only) → changelog dialog.
    ref.listenManual(updateCheckProvider, (_, next) {
      final update = next.value;
      if (update != null && mounted) showUpdateDialog(context, update);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeTimer?.cancel();
    _gamepad?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Gate gamepad input on foreground: while another window/game is in
    // front (inactive/paused/hidden), the raw joystick still fires but we
    // don't want it skipping tracks (user-reported).
    _appActive = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed) return;
    // Back to the foreground: an OEM battery freeze can leave the seek bar
    // stalled and the FFT extraction dead. Snap the position to truth and
    // re-arm the visualizer watchdog.
    ref.read(audioHandlerProvider).engine.onAppResumed();
    ref.read(appResumeTickProvider.notifier).bump();
  }

  // Home is the start page (index 0); Library stays a pure list one tab
  // away (ARCHITECTURE-RECOMMENDATIONS.md §5).
  static const _screens = [
    HomeScreen(),
    LibraryScreen(),
    NowPlayingScreen(),
    YouScreen(),
  ];

  /// The Now Playing tab index.
  static const _playingIndex = 2;

  void _onNavChanged(int i) {
    if (i == _index) return;
    setState(() {
      _previousIndex = _index;
      _index = i;
    });
  }

  /// System back: first give any open in-app view (search overlay, inline
  /// folder/playlist detail) the chance to close, then step back to the
  /// Library tab, and only exit once back is pressed there.
  void _onSystemBack() {
    if (BackStack.pop()) return;
    if (_index != 0) {
      _onNavChanged(0);
      return;
    }
    SystemNavigator.pop();
  }

  /// Surface the resume ticker if the last session was more than a few
  /// seconds in (resuming a barely-started track isn't worth a prompt).
  /// The banner auto-dismisses after a while so it never lingers.
  void _maybeOfferResume() {
    final session = ref.read(savedSessionProvider);
    final track = session?.current;
    if (session == null ||
        track == null ||
        session.position < const Duration(seconds: 5)) {
      return;
    }
    setState(() => _pendingResume = session);
    _resumeTimer = Timer(const Duration(seconds: 12), _dismissResume);
  }

  Future<void> _acceptResume() async {
    final session = _pendingResume;
    if (session == null) return;
    _resumeTimer?.cancel();
    setState(() => _pendingResume = null);
    await ref
        .read(audioHandlerProvider)
        .engine
        .restoreSession(session, autoPlay: true);
    if (mounted) _onNavChanged(_playingIndex); // jump to Now Playing
  }

  void _dismissResume() {
    if (_pendingResume == null) return;
    _resumeTimer?.cancel();
    // Forget it so the same stale session doesn't nag next launch.
    clearSavedSession(ref);
    if (mounted) setState(() => _pendingResume = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    // Content slides in from the direction of travel (DESIGN.md §8).
    final slideFromRight = _index > _previousIndex;
    // Width decides the shell, not platform: a tablet (or unfolded
    // foldable) gets the same rail/three-pane layout as a desktop window
    // of that size, so it never reads as a stretched phone. A narrow
    // window keeps the phone layout it maps cleanly onto.
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 880;
    final threePane = width >= 1240;
    // In the wide shell, Now Playing is a permanent right-hand panel
    // instead of a tab — its tab index shows Home in the middle instead.
    final contentIndex = _index == _playingIndex ? 0 : _index;

    final content = AnimatedSwitcher(
      duration: Anim.tabSlide,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, animation) {
        final isIncoming = child.key == ValueKey(_index);
        final beginX = isIncoming
            ? (slideFromRight ? 0.15 : -0.15)
            : (slideFromRight ? -0.15 : 0.15);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(beginX, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(_index),
        child: _screens[_index],
      ),
    );

    // The cat chases your taps and drags across the whole shell (the
    // full oneko), napping where the finger last was — unless follow
    // is off, in which case she sleeps beside the edition logo.
    final onekoChase = ref.watch(buddyEnabledProvider('cat')) &&
        ref.watch(catFollowProvider);

    if (!wide) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onSystemBack();
        },
        child: Scaffold(
          body: onekoChase ? OnekoLayer(child: content) : content,
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ResumeTicker(
                session: _pendingResume,
                theme: theme,
                onPlay: _acceptResume,
                onDismiss: _dismissResume,
              ),
              // Hidden on the Playing tab — the full screen is already there.
              if (_index != _playingIndex)
                MiniPlayer(onOpen: () => _onNavChanged(_playingIndex)),
              HanamimiBottomNav(
                activeIndex: _index,
                onChanged: _onNavChanged,
                theme: theme,
              ),
            ],
          ),
        ),
      );
    }

    // Wide shell: Now Playing is a permanent right-hand panel, the middle
    // pane holds the active screen, and the left edge is the slim rail
    // (≥880) or the full "Your Library" sidebar (≥1240). One art-glow
    // wash + particle field sit under every pane so no boundary reads as
    // a jump into a different color; the mini player never exists here —
    // the panel IS the player.
    final middlePane = Expanded(
      child: Column(
        children: [
          Expanded(
            child: KeyedSubtree(
              key: ValueKey(contentIndex),
              child: _screens[contentIndex],
            ),
          ),
          _ResumeTicker(
            session: _pendingResume,
            theme: theme,
            onPlay: _acceptResume,
            onDismiss: _dismissResume,
          ),
        ],
      ),
    );

    final wideBody = Row(
      children: [
        if (threePane)
          LibrarySidebar(activeIndex: contentIndex, onNav: _onNavChanged)
        else
          HanamimiSideRail(
            activeIndex: contentIndex,
            onChanged: _onNavChanged,
            theme: theme,
            showPlaying: false,
          ),
        middlePane,
        // No divider: the panel's art wash fades out at its left edge,
        // so the panes blend instead of splitting at a hard line.
        const SizedBox(
          width: 400,
          child: NowPlayingScreen(panel: true),
        ),
      ],
    );

    final wideBackground = Stack(
      fit: StackFit.expand,
      children: [
        const BackdropWash(),
        // Isolated so its 60 fps ticker repaints only its own layer, not
        // the blur below or the panes above.
        RepaintBoundary(
          child: ParticleOverlay(
            theme: theme,
            fireflies: ref.watch(buddyEnabledProvider('fireflies')),
          ),
        ),
        wideBody,
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onSystemBack();
      },
      child: Scaffold(
          body: onekoChase
              ? OnekoLayer(child: wideBackground)
              : wideBackground),
    );
  }
}

/// VLC-style resume banner: a slim bar above the mini player. Slides in
/// when there's a session to resume, PLAY restores it, tapping the ✕
/// (or the auto-timeout) forgets it.
class _ResumeTicker extends StatelessWidget {
  const _ResumeTicker({
    required this.session,
    required this.theme,
    required this.onPlay,
    required this.onDismiss,
  });

  final PlaybackSession? session;
  final HanamimiTheme theme;
  final VoidCallback onPlay;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: session == null
          ? const SizedBox(width: double.infinity)
          : _bar(session!.current!),
    );
  }

  Widget _bar(Track track) {
    return Material(
      color: theme.surface,
      child: Container(
        decoration: BoxDecoration(
          border:
              Border(top: BorderSide(color: theme.divider, width: 0.5)),
        ),
        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s2, Space.s2),
        child: Row(
          children: [
            Icon(Icons.history_rounded, size: 18, color: theme.primary),
            const SizedBox(width: Space.s2),
            Expanded(
              child: RichText(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  style: AppText.caption(theme),
                  children: [
                    const TextSpan(text: 'Resume playback of '),
                    TextSpan(
                      text: track.title,
                      style: AppText.caption(theme)
                          .copyWith(color: theme.textPrimary),
                    ),
                    TextSpan(text: '  ·  ${session!.position.mmss}?'),
                  ],
                ),
              ),
            ),
            TextButton(
              onPressed: onPlay,
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: Space.s3)),
              child: Text('PLAY',
                  style: AppText.rowSongTitle(theme).copyWith(
                      color: theme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5)),
            ),
            InkResponse(
              onTap: onDismiss,
              radius: 20,
              child: Padding(
                padding: const EdgeInsets.all(Space.s1),
                child: Icon(Icons.close, size: 18, color: theme.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
