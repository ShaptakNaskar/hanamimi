import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/buddy_provider.dart';
import '../../../providers/desktop_shell_provider.dart';
import '../../../providers/library_provider.dart';
import '../../../providers/mascot_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../../providers/update_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/hanamimi_theme.dart';
import '../../../theme/theme_tokens.dart';
import '../mascot/hanamimi_widget.dart';
import '../library/playlist_cover.dart';

/// Spotify-style "Your Library" sidebar for the three-pane desktop
/// shell (M31): pinned Liked Songs, then playlists and folders.
/// Selecting a collection asks the middle pane (LibraryScreen) to open
/// it via [desktopCollectionProvider]; the icon strip on top swaps the
/// middle pane between Songs / Downloads / You.
class LibrarySidebar extends ConsumerWidget {
  const LibrarySidebar({
    super.key,
    required this.activeIndex,
    required this.onNav,
  });

  /// AppShell tab index of the middle pane (0 Library, 2 Downloads, 3 You).
  final int activeIndex;
  final ValueChanged<int> onNav;

  void _openCollection(WidgetRef ref, void Function() open) {
    open();
    // The collection lives in the Library pane — make sure it's showing
    // and not buried under the middle-pane lyrics.
    ref.read(desktopLyricsOpenProvider.notifier).close();
    if (activeIndex != 0) onNav(0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final playlists = ref.watch(playlistsProvider).value ?? [];
    final folders = ref.watch(foldersProvider);
    final likedCount =
        (ref.watch(libraryProvider).value ?? []).where((t) => t.liked).length;
    final request = ref.watch(desktopCollectionProvider);

    return Container(
      width: 280,
      decoration: BoxDecoration(
        // Translucent over the shell-wide art glow (BackdropWash): the
        // pane reads as a soft layer, not a hard block of another color.
        color: theme.surface.withValues(alpha: 0.35),
        border: Border(
            right: BorderSide(
                color: theme.divider.withValues(alpha: 0.4), width: 0.5)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.s4, Space.s4, Space.s4, Space.s2),
              child: Row(
                children: [
                  if (ref.watch(buddyEnabledProvider('beagle'))) ...[
                    HanamimiMascot(
                        state: ref.watch(mascotStateProvider), size: 28),
                    const SizedBox(width: Space.s2),
                  ],
                  Expanded(
                    child: Text(
                      ref.watch(editionNameProvider).value ?? 'Hanamimi',
                      style:
                          AppText.screenTitle(theme).copyWith(fontSize: 20),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.s3, vertical: Space.s1),
              child: Row(
                children: [
                  _NavChip(
                    icon: Icons.music_note_outlined,
                    label: 'Songs',
                    active: activeIndex == 0 && request == null,
                    theme: theme,
                    onTap: () {
                      ref.read(desktopCollectionProvider.notifier).clear();
                      onNav(0);
                    },
                  ),
                  _NavChip(
                    icon: Icons.download_outlined,
                    label: 'Downloads',
                    active: activeIndex == 2,
                    theme: theme,
                    onTap: () => onNav(2),
                  ),
                  _NavChip(
                    icon: Icons.pets_outlined,
                    label: 'You',
                    active: activeIndex == 3,
                    theme: theme,
                    onTap: () => onNav(3),
                  ),
                ],
              ),
            ),
            Divider(height: Space.s3, color: theme.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.s4, Space.s2, Space.s4, Space.s2),
              child: Text('YOUR LIBRARY', style: AppText.sectionLabel(theme)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: Space.s4),
                children: [
                  _SidebarRow(
                    active: request?.type == DesktopCollectionType.liked,
                    theme: theme,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.accent,
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      child: const Icon(Icons.favorite,
                          size: 20, color: Colors.white),
                    ),
                    title: 'Liked songs',
                    subtitle: '$likedCount track${likedCount == 1 ? '' : 's'}',
                    onTap: () => _openCollection(
                        ref,
                        ref.read(desktopCollectionProvider.notifier)
                            .openLiked),
                  ),
                  if (playlists.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          Space.s4, Space.s3, Space.s4, Space.s1),
                      child: Text('PLAYLISTS',
                          style: AppText.sectionLabel(theme)),
                    ),
                    for (final playlist in playlists)
                      _SidebarRow(
                        active: request?.type ==
                                DesktopCollectionType.playlist &&
                            request?.playlistId == playlist.id,
                        theme: theme,
                        leading: PlaylistCover(
                            playlist: playlist, size: 40, fontSize: 14),
                        title: playlist.name,
                        subtitle:
                            '${playlist.trackIds.length} song${playlist.trackIds.length == 1 ? '' : 's'}',
                        onTap: () => _openCollection(
                            ref,
                            () => ref
                                .read(desktopCollectionProvider.notifier)
                                .openPlaylist(playlist.id)),
                      ),
                  ],
                  if (folders.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                          Space.s4, Space.s3, Space.s4, Space.s1),
                      child:
                          Text('FOLDERS', style: AppText.sectionLabel(theme)),
                    ),
                    for (final folder in folders)
                      _SidebarRow(
                        active:
                            request?.type == DesktopCollectionType.folder &&
                                request?.folderPath == folder.path,
                        theme: theme,
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: theme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(Radii.sm),
                          ),
                          child: Icon(Icons.folder_rounded,
                              size: 20, color: theme.primary),
                        ),
                        title: folder.name,
                        subtitle:
                            '${folder.tracks.length} song${folder.tracks.length == 1 ? '' : 's'}',
                        onTap: () => _openCollection(
                            ref,
                            () => ref
                                .read(desktopCollectionProvider.notifier)
                                .openFolder(folder.path)),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  const _NavChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.theme,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final HanamimiTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: active
              ? theme.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.md),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Radii.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s2),
              child: Column(
                children: [
                  Icon(icon,
                      size: 20,
                      color: active ? theme.primary : theme.textMuted),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 10,
                      fontWeight:
                          active ? FontWeight.w700 : FontWeight.w500,
                      color: active ? theme.primary : theme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({
    required this.active,
    required this.theme,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool active;
  final HanamimiTheme theme;
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? theme.primary.withValues(alpha: 0.10)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Space.s4, vertical: Space.s2),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.sm),
                child: leading,
              ),
              const SizedBox(width: Space.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.rowSongTitle(theme).copyWith(
                        color: active ? theme.primary : theme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: AppText.caption(theme),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
