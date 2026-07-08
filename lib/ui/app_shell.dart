import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../audio/models/playback_session.dart';
import '../library/models/track.dart';
import '../platform/desktop/desktop_bootstrap.dart';
import '../providers/audio_provider.dart';
import '../providers/buddy_provider.dart';
import '../providers/desktop_shell_provider.dart';
import '../providers/import_job_provider.dart';
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
import 'components/mascot/oneko.dart';
import 'components/mini_player.dart';
import 'components/shared/bottom_nav.dart';
import 'components/shared/particle_overlay.dart';
import 'modals/import_playlist_sheet.dart';
import 'modals/lyrics_sheet.dart';
import 'modals/update_dialog.dart';
import 'screens/desktop_immersive_screen.dart';
import 'screens/downloads_screen.dart';
import 'screens/library_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/you_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver, WindowListener {
  int _index = 0;
  int _previousIndex = 0;

  // Engine trouble ("Can't play these tracks") surfaces as a toast.
  StreamSubscription<String>? _errorSub;

  // VLC-style resume ticker: the saved session waiting to be resumed,
  // shown as a dismissible banner above the mini player (not a modal).
  PlaybackSession? _pendingResume;
  Timer? _resumeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Desktop keyboard transport: global handler (not Shortcuts) so a
    // focused search field keeps its spaces — _onKey bows out while an
    // EditableText has focus.
    if (isDesktop) {
      HardwareKeyboard.instance.addHandler(_onKey);
      // Intercept the window close (title-bar X, taskbar "Close",
      // Alt+F4) so we tear down libmpv before the process dies —
      // otherwise its audio thread keeps looping the last buffer and
      // screeches on the way out.
      windowManager.setPreventClose(true);
      windowManager.addListener(this);
    }
    // Offer to resume the previous session once, after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferResume());
    // One update check per launch; surfaces the changelog dialog when a
    // newer CI release exists.
    ref.listenManual(updateCheckProvider, (_, next) {
      final update = next.value;
      if (update != null && mounted) {
        showUpdateDialog(context, update);
      }
    });
    // A background playlist import finished — let the user jump to review
    // (they may have left the import sheet while it ran).
    ref.listenManual(importJobProvider, (prev, next) {
      if (next.hasResult && !(prev?.hasResult ?? false) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.md)),
          content: const Text('Playlist ready to review 🐰',
              style: TextStyle(fontFamily: 'Nunito')),
          action: SnackBarAction(
              label: 'Review',
              onPressed: () => showImportPlaylistSheet(context)),
        ));
      }
    });
    // If the user starts playing something else, the offer is moot —
    // drop the banner (the new session overwrites the saved one anyway).
    ref.listenManual(audioStateProvider, (_, next) {
      if (_pendingResume != null && (next.value?.isPlaying ?? false)) {
        _resumeTimer?.cancel();
        setState(() => _pendingResume = null);
      }
    });
    _errorSub = ref
        .read(audioHandlerProvider)
        .engine
        .errors
        .stream
        .listen((message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md)),
        content:
            Text(message, style: const TextStyle(fontFamily: 'Nunito')),
      ));
    });
  }

  @override
  void dispose() {
    if (isDesktop) {
      HardwareKeyboard.instance.removeHandler(_onKey);
      windowManager.removeListener(this);
    }
    WidgetsBinding.instance.removeObserver(this);
    _errorSub?.cancel();
    _resumeTimer?.cancel();
    super.dispose();
  }

  /// Close requested (X, taskbar Close, Alt+F4). Because we set
  /// preventClose, the window stays up until we destroy it — so stop and
  /// dispose the engine first, releasing the libmpv audio device
  /// cleanly, then let the window (and process) go.
  @override
  void onWindowClose() async {
    try {
      await ref.read(audioHandlerProvider).engine.dispose();
    } catch (_) {
      // Never let a teardown hiccup wedge the window open.
    }
    await windowManager.destroy();
  }

  /// Desktop shortcuts: space play/pause, ←/→ seek 5 s, Ctrl+←/→
  /// prev/next, Esc backs out of overlays, 1–4 jump tabs.
  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    // Typing wins — no transport hijack while a text field has focus.
    if (FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>() !=
        null) {
      return false;
    }
    final engine = ref.read(audioHandlerProvider).engine;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.mediaPlayPause:
        engine.state.isPlaying ? engine.pause() : engine.play();
      case LogicalKeyboardKey.arrowRight when ctrl:
      case LogicalKeyboardKey.mediaTrackNext:
        engine.next();
      case LogicalKeyboardKey.arrowLeft when ctrl:
      case LogicalKeyboardKey.mediaTrackPrevious:
        engine.previous();
      case LogicalKeyboardKey.arrowRight:
        engine.seek(engine.position + const Duration(seconds: 5));
      case LogicalKeyboardKey.arrowLeft:
        final target = engine.position - const Duration(seconds: 5);
        engine.seek(target.isNegative ? Duration.zero : target);
      case LogicalKeyboardKey.escape:
        // Immersive Now Playing (or any pushed route/dialog) first,
        // then the middle-pane lyrics, then in-screen overlays.
        final navigator = Navigator.of(context, rootNavigator: true);
        if (navigator.canPop()) {
          navigator.pop();
        } else if (ref.read(desktopLyricsOpenProvider)) {
          ref.read(desktopLyricsOpenProvider.notifier).close();
        } else if (!BackStack.pop() && _index != 0) {
          _onNavChanged(0);
        }
      case LogicalKeyboardKey.keyF:
        // Immersive full-window Now Playing (like Spotify's F11 view).
        final nav = Navigator.of(context, rootNavigator: true);
        if (!nav.canPop() &&
            ref.read(audioStateProvider).value?.currentTrack != null) {
          nav.push(DesktopImmersiveScreen.route());
        }
      case LogicalKeyboardKey.keyL:
        // Middle-pane lyrics (the Now Playing panel's chevron).
        if (ref.read(audioStateProvider).value?.currentTrack != null) {
          ref.read(desktopLyricsOpenProvider.notifier).toggle();
        }
      case LogicalKeyboardKey.digit1:
        _onNavChanged(0);
      case LogicalKeyboardKey.digit2:
        _onNavChanged(1);
      case LogicalKeyboardKey.digit3:
        _onNavChanged(2);
      case LogicalKeyboardKey.digit4:
        _onNavChanged(3);
      default:
        return false;
    }
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Back to the foreground: an OEM battery freeze can leave the seek bar
    // stalled and the FFT extraction dead. Snap the position to truth and
    // re-arm the visualizer watchdog.
    ref.read(audioHandlerProvider).engine.onAppResumed();
    ref.read(appResumeTickProvider.notifier).bump();
  }

  static const _screens = [
    LibraryScreen(),
    NowPlayingScreen(),
    DownloadsScreen(),
    YouScreen(),
  ];

  void _onNavChanged(int i) {
    // Navigating anywhere dismisses the middle-pane lyrics — otherwise
    // the sidebar switched the pane underneath while the lyrics kept
    // covering it, so You/Albums/folders looked dead (user-reported).
    ref.read(desktopLyricsOpenProvider.notifier).close();
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
    if (mounted) _onNavChanged(1); // jump to Now Playing
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
    // Wide desktop windows trade the bottom nav for a left rail
    // (ARCHITECTURE-DESKTOP.md §5); a narrow window keeps the phone
    // layout, which maps cleanly onto it.
    // Width decides, not platform: tablets and unfolded foldables get
    // the same shell as a desktop window of that size (a stretched
    // phone layout on a 1280dp tablet looked sparse and wrong).
    final wide = MediaQuery.sizeOf(context).width >= 880;

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

    final playerStrip = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ResumeTicker(
          session: _pendingResume,
          theme: theme,
          onPlay: _acceptResume,
          onDismiss: _dismissResume,
        ),
        // Hidden on the Playing tab — the full screen is already there.
        if (_index != 1) MiniPlayer(onOpen: () => _onNavChanged(1)),
      ],
    );

    // Desktop layouts (ARCHITECTURE-DESKTOP.md §5): Now Playing is a
    // permanent right-hand panel instead of a tab, so a wide window
    // reads as a desktop music player, not a stretched phone. At full
    // width the slim rail grows into the Spotify-style "Your Library"
    // sidebar (folders + playlists driving the middle pane); the mini
    // player never exists on desktop — the panel IS the player.
    final width = MediaQuery.sizeOf(context).width;
    final threePane = width >= 1240;
    final contentIndex = _index == 1 ? 0 : _index;

    // The Now Playing panel, with the expand-to-immersive affordance.
    final nowPlayingPanel = SizedBox(
      width: 400,
      child: Stack(
        children: [
          const NowPlayingScreen(panel: true),
          Positioned(
            top: Space.s2,
            right: Space.s2,
            child: IconButton(
              tooltip: 'Immersive view',
              onPressed: () => Navigator.of(context, rootNavigator: true)
                  .push(DesktopImmersiveScreen.route()),
              icon: Icon(Icons.open_in_full_rounded,
                  size: 18, color: theme.textMuted),
            ),
          ),
        ],
      ),
    );

    // Lyrics take over the middle pane (Spotify-style) when the Now
    // Playing panel's chevron opens them; the karaoke view is the same
    // widget the phone sheet uses — full word-sync, source, offset.
    final lyricsTrack = ref.watch(audioStateProvider).value?.currentTrack;
    final lyricsOpen =
        ref.watch(desktopLyricsOpenProvider) && lyricsTrack != null;

    final middlePane = Expanded(
      child: Column(
        children: [
          Expanded(
            child: lyricsOpen
                ? LyricsView(
                    key: const ValueKey('desktop-lyrics'),
                    track: lyricsTrack,
                    sheetChrome: false,
                    onClose: () =>
                        ref.read(desktopLyricsOpenProvider.notifier).close(),
                  )
                : KeyedSubtree(
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
        nowPlayingPanel,
      ],
    );

    // One uniform art glow under every pane, one whole-window particle
    // field over it, then the panes.
    Widget wideBackground = Stack(
      fit: StackFit.expand,
      children: [
        const BackdropWash(),
        // Isolated so its 60 fps ticker repaints only its own layer,
        // not the blur below or the panes above.
        RepaintBoundary(
          child: ParticleOverlay(
            theme: theme,
            fireflies: ref.watch(buddyEnabledProvider('fireflies')),
          ),
        ),
        wideBody,
      ],
    );
    // The "cat" buddy has no mini player to nap on here, so on desktop it
    // wakes up as oneko and chases the pointer across the whole window.
    if (isDesktop && ref.watch(buddyEnabledProvider('cat'))) {
      wideBackground = OnekoLayer(child: wideBackground);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onSystemBack();
      },
      child: wide
          ? Scaffold(body: wideBackground)
          : Scaffold(
              body: content,
              bottomNavigationBar: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  playerStrip,
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
