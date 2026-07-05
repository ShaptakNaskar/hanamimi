import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/models/playback_session.dart';
import '../library/models/track.dart';
import '../providers/audio_provider.dart';
import '../providers/import_job_provider.dart';
import '../providers/session_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/update_provider.dart';
import '../theme/app_theme.dart';
import '../theme/hanamimi_theme.dart';
import '../theme/theme_tokens.dart';
import '../utils/duration_ext.dart';
import 'components/mini_player.dart';
import 'components/shared/bottom_nav.dart';
import 'modals/import_playlist_sheet.dart';
import 'modals/update_dialog.dart';
import 'screens/downloads_screen.dart';
import 'screens/library_screen.dart';
import 'screens/now_playing_screen.dart';
import 'screens/you_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  int _previousIndex = 0;

  // Tabs visited before the current one; system back walks this before
  // it's allowed to close the app.
  final List<int> _navHistory = [];

  // Engine trouble ("Can't play these tracks") surfaces as a toast.
  StreamSubscription<String>? _errorSub;

  // VLC-style resume ticker: the saved session waiting to be resumed,
  // shown as a dismissible banner above the mini player (not a modal).
  PlaybackSession? _pendingResume;
  Timer? _resumeTimer;

  @override
  void initState() {
    super.initState();
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
    _errorSub?.cancel();
    _resumeTimer?.cancel();
    super.dispose();
  }

  static const _screens = [
    LibraryScreen(),
    NowPlayingScreen(),
    DownloadsScreen(),
    YouScreen(),
  ];

  void _onNavChanged(int i) {
    if (i == _index) return;
    setState(() {
      _previousIndex = _index;
      _navHistory.add(_index);
      _index = i;
    });
  }

  void _goBack() {
    if (_navHistory.isEmpty) return;
    setState(() {
      _previousIndex = _index;
      _index = _navHistory.removeLast();
    });
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

    return PopScope(
      canPop: _navHistory.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        body: AnimatedSwitcher(
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
        ),
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
            if (_index != 1) MiniPlayer(onOpen: () => _onNavChanged(1)),
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
