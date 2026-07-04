import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/models/playback_session.dart';
import '../library/models/track.dart';
import '../providers/audio_provider.dart';
import '../providers/session_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import '../theme/theme_tokens.dart';
import '../utils/duration_ext.dart';
import 'components/mini_player.dart';
import 'components/shared/bottom_nav.dart';
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

  @override
  void initState() {
    super.initState();
    // VLC-style: offer to resume the previous session once, after the
    // first frame so a dialog can be shown.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferResume());
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
    super.dispose();
  }

  static const _screens = [
    LibraryScreen(),
    NowPlayingScreen(),
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

  /// Prompt to pick up where the last session left off. Only offered
  /// when the track was more than a few seconds in — resuming a song
  /// that had barely started isn't worth a dialog.
  Future<void> _maybeOfferResume() async {
    final session = ref.read(savedSessionProvider);
    final track = session?.current;
    if (session == null ||
        track == null ||
        session.position < const Duration(seconds: 5)) {
      return;
    }
    if (!mounted) return;
    final resume = await _showResumeDialog(session, track);
    if (resume == true) {
      await ref.read(audioHandlerProvider).engine.restoreSession(session);
      if (mounted) _onNavChanged(1); // jump to Now Playing, paused at position
    } else {
      // Forget it so the same stale session doesn't nag next launch.
      clearSavedSession(ref);
    }
  }

  Future<bool?> _showResumeDialog(PlaybackSession session, Track track) {
    final theme = ref.read(currentThemeProvider);
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
        title: Text('Pick up where you left off?',
            style: AppText.rowSongTitle(theme)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(track.title,
                style: AppText.rowSongTitle(theme)
                    .copyWith(color: theme.primary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: Space.s1),
            Text('${track.artist} · ${session.position.mmss}',
                style: AppText.caption(theme),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Not now',
                style: AppText.rowSongTitle(theme)
                    .copyWith(color: theme.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Resume',
                style: AppText.rowSongTitle(theme)
                    .copyWith(color: theme.primary)),
          ),
        ],
      ),
    );
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
