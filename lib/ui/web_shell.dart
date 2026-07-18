import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../audio/models/queue_mode.dart';
import '../platform/web/web_library.dart';
import '../providers/audio_provider.dart';
import '../providers/buddy_provider.dart';
import '../providers/library_provider.dart';
import '../providers/night_mode_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_theme.dart';
import '../theme/hanamimi_theme.dart';
import '../theme/theme_tokens.dart';
import 'components/library/track_row.dart';
import 'components/mascot/hanamimi_widget.dart';
import 'components/mascot/oneko.dart';
import 'components/mascot/oneko_tips.dart';
import 'modals/web_settings_sheet.dart';
import 'screens/now_playing_screen.dart';
import 'screens/web_immersive_screen.dart';

/// The web demo's whole chrome (per Sappy's mockup): a slim sidebar —
/// wordmark, settings, your picked folders and their songs, and the
/// GitHub plug — beside a full-bleed Now Playing. The resident oneko
/// sleeps on the sidebar header and wakes up with tips.
///
/// Narrow windows (a phone browser) tuck the sidebar into a drawer.
class WebShell extends ConsumerWidget {
  const WebShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final narrow = MediaQuery.sizeOf(context).width < 700;

    // The full oneko chases pointer/touches across the whole shell
    // (buddies setting) — the sidebar cat naps regardless.
    final chase = ref.watch(buddyEnabledProvider('cat')) &&
        ref.watch(catFollowProvider);

    final content = narrow
        ? Stack(
            children: [
              const NowPlayingScreen(),
              // Drawer handle floating over the top-left corner.
              Positioned(
                top: Space.s3,
                left: Space.s3,
                child: SafeArea(
                  child: Builder(
                    builder: (context) => IconButton(
                      tooltip: 'Your music',
                      icon: Icon(Icons.menu_rounded,
                          color: theme.textPrimary),
                      style: IconButton.styleFrom(
                        backgroundColor:
                            theme.surface.withValues(alpha: 0.8),
                      ),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                ),
              ),
            ],
          )
        : Row(
            children: [
              const SizedBox(width: 300, child: _Sidebar()),
              Container(width: 0.5, color: theme.divider),
              // The plus desktop immersive layout: player column left,
              // giant synced lyrics right. ClipRect because the art
              // wash's big blur paints past its bounds (tinted the
              // sidebar) — blurs don't self-clip.
              const Expanded(
                  child: ClipRect(child: WebImmersiveNowPlaying())),
            ],
          );

    return Scaffold(
      backgroundColor: theme.background,
      drawer: narrow
          ? Drawer(
              backgroundColor: theme.background,
              child: const SafeArea(child: _Sidebar()),
            )
          : null,
      body: chase ? OnekoLayer(child: content) : content,
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  static const _github = 'https://github.com/ShaptakNaskar/hanamimi';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final night = ref.watch(nightModeActiveProvider);
    final folders = ref.watch(webLibraryProvider);
    final progress = ref.watch(importProgressProvider);
    final playingId =
        ref.watch(audioStateProvider).value?.currentTrack?.id;

    return Material(
      color: theme.surface.withValues(alpha: 0.35),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: mascot-logo + wordmark + settings; the tips cat
          // sleeps on the header's roof.
          Padding(
            padding:
                const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s3, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    HanamimiMascot(
                      state: MascotState.idle,
                      size: 30,
                      onTap: () {},
                    ),
                    const SizedBox(width: Space.s2),
                    Expanded(
                      child: Text(
                        'Hanamimi'.whisper(night),
                        style: AppText.screenTitle(theme)
                            .copyWith(fontSize: 20),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Settings',
                      icon: Icon(Icons.settings_outlined,
                          size: 20, color: theme.textMuted),
                      onPressed: () => showWebSettingsSheet(context),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: Space.s2),
                    child: OnekoTips(theme: theme),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.s2),
          // Pickers.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            child: Row(
              children: [
                Expanded(
                  child: _PickButton(
                    icon: Icons.folder_open_rounded,
                    label: 'Open folder'.whisper(night),
                    theme: theme,
                    onTap: () =>
                        ref.read(webLibraryProvider.notifier).addFolder(),
                  ),
                ),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: _PickButton(
                    icon: Icons.library_music_outlined,
                    label: 'Add songs'.whisper(night),
                    theme: theme,
                    onTap: () =>
                        ref.read(webLibraryProvider.notifier).addFiles(),
                  ),
                ),
              ],
            ),
          ),
          if (progress != null)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s4, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(
                    value: progress.total == 0
                        ? null
                        : progress.done / progress.total,
                    minHeight: 3,
                    color: theme.primary,
                    backgroundColor: theme.divider,
                  ),
                  const SizedBox(height: Space.s1),
                  Text(
                    'reading tags… ${progress.done}/${progress.total}',
                    style: AppText.caption(theme),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Space.s3),
          // The library — or a friendly nudge to fill it.
          Expanded(
            child: folders.isEmpty
                ? _EmptyLibrary(theme: theme, night: night)
                : _FolderList(
                    folders: folders,
                    theme: theme,
                    playingId: playingId,
                  ),
          ),
          // The plug — this demo's other job.
          _PlugCard(theme: theme, night: night, github: _github),
        ],
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({
    required this.icon,
    required this.label,
    required this.theme,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final HanamimiTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.primary,
        side: BorderSide(color: theme.divider),
        padding: const EdgeInsets.symmetric(
            vertical: Space.s2, horizontal: Space.s2),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md)),
      ),
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontFamily: 'Nunito', fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.theme, required this.night});

  final HanamimiTheme theme;
  final bool night;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Space.s6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.eject_rounded,
              size: 40, color: theme.textMuted.withValues(alpha: 0.6)),
          const SizedBox(height: Space.s3),
          Text(
            'Drop your music in'.whisper(night),
            textAlign: TextAlign.center,
            style: AppText.rowSongTitle(theme),
          ),
          const SizedBox(height: Space.s2),
          Text(
            'Pick a folder (or a few songs) and they play right here. '
                    'Nothing is uploaded — the files never leave this tab.'
                .whisper(night),
            textAlign: TextAlign.center,
            style: AppText.caption(theme).copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _FolderList extends ConsumerWidget {
  const _FolderList({
    required this.folders,
    required this.theme,
    required this.playingId,
  });

  final List<WebFolder> folders;
  final HanamimiTheme theme;
  final int? playingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    final night = ref.watch(nightModeActiveProvider);
    final all = ref.watch(allTracksProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: Space.s4),
      children: [
        // Shuffle everything — one tap, music on.
        Padding(
          padding:
              const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s2),
          child: FilledButton.icon(
            onPressed: all.isEmpty
                ? null
                : () => handler.playTracks(all, mode: QueueMode.shuffle),
            style: FilledButton.styleFrom(
              backgroundColor: theme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: Space.s2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.pill)),
            ),
            icon: const Icon(Icons.shuffle_rounded, size: 16),
            label: Text(
              'Shuffle all'.whisper(night),
              style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ),
        for (final folder in folders) ...[
          Padding(
            padding:
                const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s2, 0),
            child: Row(
              children: [
                Icon(Icons.folder_rounded, size: 15, color: theme.primary),
                const SizedBox(width: Space.s2),
                Expanded(
                  child: Text(
                    '${folder.name} · ${folder.tracks.length}'
                        .whisper(night),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.sectionLabel(theme),
                  ),
                ),
                InkResponse(
                  onTap: () => ref
                      .read(webLibraryProvider.notifier)
                      .removeFolder(folder.name),
                  radius: 14,
                  child: Padding(
                    padding: const EdgeInsets.all(Space.s1),
                    child:
                        Icon(Icons.close, size: 14, color: theme.textMuted),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < folder.tracks.length; i++)
            TrackRow(
              track: folder.tracks[i],
              theme: theme,
              isPlaying: folder.tracks[i].id == playingId,
              onTap: () =>
                  handler.playTracks(folder.tracks, startIndex: i),
              onAddToQueue: () =>
                  handler.engine.addToQueue(folder.tracks[i]),
            ),
        ],
      ],
    );
  }
}

class _PlugCard extends StatelessWidget {
  const _PlugCard({
    required this.theme,
    required this.night,
    required this.github,
  });

  final HanamimiTheme theme;
  final bool night;
  final String github;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(Space.s3),
      padding: const EdgeInsets.all(Space.s3),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: theme.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Liking the demo?'.whisper(night),
            style: AppText.rowSongTitle(theme),
          ),
          const SizedBox(height: Space.s1),
          Text(
            'The full Hanamimi is a real player for Android, Linux and '
                    'Windows — this page is just its little sister.'
                .whisper(night),
            style: AppText.caption(theme).copyWith(height: 1.35),
          ),
          const SizedBox(height: Space.s2),
          FilledButton.icon(
            onPressed: () => launchUrl(Uri.parse(github),
                mode: LaunchMode.externalApplication),
            style: FilledButton.styleFrom(
              backgroundColor: theme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: Space.s2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(Radii.md)),
            ),
            icon: const Icon(Icons.code_rounded, size: 16),
            label: Text(
              'Get it on GitHub'.whisper(night),
              style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
