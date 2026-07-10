import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/media_store_channel.dart';
import '../../platform/desktop/desktop_bootstrap.dart';
import '../../platform/desktop/desktop_library.dart';
import '../../online/models/resolved_stream.dart';
import '../../online/ytdlp_channel.dart';
import '../../providers/buddy_provider.dart';
import '../../providers/cat_mode_provider.dart';
import '../../providers/companion_provider.dart';
import '../../providers/dev_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/mascot_provider.dart';
import '../../providers/nerd_provider.dart';
import '../../providers/reco_provider.dart';
import '../../providers/yt_account_provider.dart';
import '../../providers/online_settings_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/power_provider.dart';
import '../../providers/update_provider.dart';
import '../../providers/visualizer_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../../theme/themes.dart';
import '../components/mascot/buddies.dart';
import '../components/mascot/hanamimi_widget.dart';
import '../components/mascot/oneko.dart';
import '../modals/about_dialog.dart';
import '../modals/update_dialog.dart';
import '../modals/yt_signin_dialog.dart';
import 'stats_screen.dart';
import '../components/mascot/mascot_painter.dart';

class YouScreen extends ConsumerWidget {
  const YouScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        children: [
          const SizedBox(height: Space.s6),
          // Same header as the Library: mascot + edition wordmark (+
          // parrot + sleeping cat) — replaced the plain "You" title.
          // Hidden in the three-pane shell, where the sidebar already
          // wears the identity (duplicated side by side otherwise).
          if (MediaQuery.sizeOf(context).width < 1240) ...[
            Row(
              children: [
                if (ref.watch(buddyEnabledProvider('beagle'))) ...[
                  HanamimiMascot(
                      state: ref.watch(mascotStateProvider), size: 30),
                  const SizedBox(width: Space.s2),
                ],
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Text(
                        ref.watch(editionNameProvider).value ?? 'Hanamimi',
                        style: AppText.screenTitle(theme)
                            .copyWith(fontSize: 22)),
                    if (ref.watch(buddyEnabledProvider('parrot')))
                      const Positioned(
                          left: 0,
                          right: 0,
                          top: -15,
                          child: HeaderParrot()),
                  ],
                ),
                if (ref.watch(buddyEnabledProvider('cat')) &&
                    (!isDesktop || !ref.watch(catFollowProvider))) ...[
                  const SizedBox(width: Space.s1),
                  const SleepingOneko(),
                ],
              ],
            ),
            const SizedBox(height: Space.s6),
          ],
          Text('MOOD', style: AppText.sectionLabel(theme)),
          const SizedBox(height: Space.s3),
          // Max-extent, not fixed-count: a 2-column grid across a wide
          // desktop pane inflated each theme card to phone-screen size
          // (user: "why is the theme selection so big wtf").
          GridView.extent(
            maxCrossAxisExtent: 280,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Space.s3,
            crossAxisSpacing: Space.s3,
            childAspectRatio: 1.6,
            children: [
              for (final t in allThemes)
                _ThemeTile(
                  tile: t,
                  active: t.id == theme.id,
                  onTap: () => ref
                      .read(selectedThemeIdProvider.notifier)
                      .setTheme(t.id),
                ),
            ],
          ),
          const SizedBox(height: Space.s8),
          Text('YOUR COMPANION', style: AppText.sectionLabel(theme)),
          const SizedBox(height: Space.s3),
          const _CompanionCard(),
          const SizedBox(height: Space.s8),
          Text('BUDDIES', style: AppText.sectionLabel(theme)),
          const SizedBox(height: Space.s3),
          const _BuddiesCard(),
          const SizedBox(height: Space.s8),
          Text('SOUND', style: AppText.sectionLabel(theme)),
          const SizedBox(height: Space.s3),
          const _SoundSettings(),
          const SizedBox(height: Space.s8),
          Text('ONLINE', style: AppText.sectionLabel(theme)),
          const SizedBox(height: Space.s3),
          const _OnlineSettings(),
          const SizedBox(height: Space.s8),
          Text('MORE', style: AppText.sectionLabel(theme)),
          const SizedBox(height: Space.s3),
          const _MoreCard(),
          const SizedBox(height: Space.s12),
        ],
      ),
    );
  }
}

class _CompanionCard extends ConsumerWidget {
  const _CompanionCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final listened = ref.watch(listenTimeProvider);
    final active = ref.watch(activeAccessoryProvider);
    final devUnlockAll = ref.watch(devModeProvider).allAccessories;

    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: theme.divider, width: 0.5),
      ),
      child: Column(
        children: [
          HanamimiMascot(
            state: ref.watch(mascotStateProvider),
            size: 130,
            fullBody: true,
            accessory: ref.watch(catModeProvider).enabled
                ? Accessory.catEars
                : active,
          ),
          const SizedBox(height: Space.s2),
          Text(
            '${listened.inHours}h ${listened.inMinutes.remainder(60)}m listened together',
            style: AppText.caption(theme),
          ),
          const SizedBox(height: Space.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final info in accessoryCatalog)
                _AccessoryChip(
                  info: info,
                  unlocked: devUnlockAll || isUnlocked(info, listened),
                  active: active == info.accessory,
                  onTap: () => ref
                      .read(activeAccessoryProvider.notifier)
                      .toggle(info.accessory),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Per-buddy switches (Requests.txt #20 follow-up): every code-drawn
/// pet — the beagle included — can be tucked away individually. The
/// beagle keeps her spots in this tab, on share cards and in the
/// sleep-timer modal; her toggle covers the header and Now Playing.
class _BuddiesCard extends ConsumerWidget {
  const _BuddiesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final disabled = ref.watch(buddyTogglesProvider);

    return Container(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: theme.divider, width: 0.5),
      ),
      child: Column(
        children: [
          for (final info in buddyCatalog) ...[
            SwitchListTile(
              secondary: SizedBox(
                width: 34,
                height: 30,
                child: _buddyPreview(info.id),
              ),
              title: Text(info.name, style: AppText.rowSongTitle(theme)),
              subtitle: Text(info.home, style: AppText.caption(theme)),
              value: !disabled.contains(info.id),
              onChanged: (on) => ref
                  .read(buddyTogglesProvider.notifier)
                  .setEnabled(info.id, on),
            ),
            // Desktop cat sub-toggle: chase the pointer, or sleep by
            // the logo (mobile has no pointer — she always sleeps).
            if (info.id == 'cat' &&
                isDesktop &&
                !disabled.contains('cat'))
              SwitchListTile(
                contentPadding:
                    const EdgeInsets.only(left: Space.s8, right: 16),
                title: Text('Chase the pointer',
                    style: AppText.rowSongTitle(theme)),
                subtitle: Text('Off: she sleeps beside the logo',
                    style: AppText.caption(theme)),
                value: ref.watch(catFollowProvider),
                onChanged: (on) =>
                    ref.read(catFollowProvider.notifier).set(on),
              ),
          ],
        ],
      ),
    );
  }

  /// A still of each buddy so the row shows who it's about.
  Widget _buddyPreview(String id) {
    switch (id) {
      case 'beagle':
        return const HanamimiMascot(state: MascotState.idle, size: 30);
      case 'parrot':
        return CustomPaint(painter: ParrotPainter(0.75));
      case 'cat':
        return CustomPaint(painter: CatPainter(0.25));
      case 'duck':
        return CustomPaint(painter: DuckPainter(0));
      case 'fireflies':
        return CustomPaint(painter: FireflyPreviewPainter(0));
      case 'rabbit':
        return CustomPaint(painter: RabbitPainter(0));
      default:
        return const SizedBox.shrink();
    }
  }
}

class _AccessoryChip extends ConsumerWidget {
  const _AccessoryChip({
    required this.info,
    required this.unlocked,
    required this.active,
    required this.onTap,
  });

  final AccessoryInfo info;
  final bool unlocked;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    return GestureDetector(
      onTap: unlocked
          ? onTap
          : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.md)),
                content: Text(info.unlockLabel,
                    style: const TextStyle(fontFamily: 'Nunito')),
              )),
      child: Opacity(
        opacity: unlocked ? 1 : 0.35,
        child: Column(
          children: [
            AnimatedContainer(
              duration: Anim.minTransition,
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: theme.background,
                shape: BoxShape.circle,
                border: Border.all(
                  color: active ? theme.primary : theme.divider,
                  width: active ? 2 : 0.5,
                ),
              ),
              child: unlocked
                  ? CustomPaint(
                      painter: _AccessoryPreviewPainter(info.accessory))
                  : Icon(Icons.lock_outline,
                      size: 18, color: theme.textMuted),
            ),
            const SizedBox(height: Space.s1),
            SizedBox(
              width: 64,
              child: Text(
                unlocked ? info.name : '${info.unlockHours}h',
                style: AppText.caption(theme).copyWith(fontSize: 10),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tiny mascot head wearing just the accessory, as a chip preview.
class _AccessoryPreviewPainter extends CustomPainter {
  _AccessoryPreviewPainter(this.accessory);

  final Accessory accessory;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = MascotPainter(
      pose: const MascotPose(
          eyes: EyeKind.smile, brow: BrowKind.none, mouth: MouthKind.neutral),
      accessory: accessory,
    );
    canvas.save();
    // Zoom on the top half of the head where accessories sit.
    canvas.translate(size.width * 0.5, size.height * 0.62);
    canvas.scale(0.55);
    canvas.translate(-60, -60);
    painter.paint(canvas, const Size(120, 132));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AccessoryPreviewPainter old) =>
      old.accessory != accessory;
}

class _MoreCard extends ConsumerWidget {
  const _MoreCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);

    return Container(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: theme.divider, width: 0.5),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.bar_chart_rounded,
                size: 20, color: theme.textMuted),
            title: Text('Listening stats',
                style: AppText.rowSongTitle(theme)),
            subtitle: Text('Your minutes & songs, and the leaderboard',
                style: AppText.caption(theme)),
            onTap: () =>
                Navigator.of(context).push(StatsScreen.route()),
          ),
          Divider(height: 0.5, color: theme.divider),
          ListTile(
            leading:
                Icon(Icons.refresh, size: 20, color: theme.textMuted),
            title: Text('Rescan library',
                style: AppText.rowSongTitle(theme)),
            onTap: () {
              ref.read(libraryProvider.notifier).rescan();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.md)),
                content: const Text('Scanning your music…',
                    style: TextStyle(fontFamily: 'Nunito')),
              ));
            },
          ),
          // Desktop points at folders (no MediaStore to index for us).
          if (!Platform.isAndroid) ...[
            Divider(height: 0.5, color: theme.divider),
            ListTile(
              leading: Icon(Icons.create_new_folder_outlined,
                  size: 20, color: theme.textMuted),
              title: Text('Music folders',
                  style: AppText.rowSongTitle(theme)),
              subtitle: Text('Folders the library scans',
                  style: AppText.caption(theme)),
              onTap: () => _showMusicFoldersSheet(context, ref, theme),
            ),
          ],
          Divider(height: 0.5, color: theme.divider),
          ListTile(
            leading: Icon(Icons.folder_off_outlined,
                size: 20, color: theme.textMuted),
            title: Text('Excluded folders',
                style: AppText.rowSongTitle(theme)),
            subtitle: Text('Hide folders from your library',
                style: AppText.caption(theme)),
            onTap: () => _showExcludedFoldersSheet(context, ref, theme),
          ),
          // Hidden until unlocked by tapping the mascot 7 times.
          if (ref.watch(catModeProvider).unlocked) ...[
            Divider(height: 0.5, color: theme.divider),
            ListTile(
              leading: const Text('🐱', style: TextStyle(fontSize: 16)),
              title: Text('Cat Mode', style: AppText.rowSongTitle(theme)),
              trailing: Switch(
                value: ref.watch(catModeProvider).enabled,
                onChanged: (on) =>
                    ref.read(catModeProvider.notifier).setEnabled(on),
              ),
            ),
          ],
          Divider(height: 0.5, color: theme.divider),
          ListTile(
            leading: Icon(Icons.info_outline,
                size: 20, color: theme.textMuted),
            title: Text('About', style: AppText.rowSongTitle(theme)),
            subtitle: Text(
                ref.watch(appVersionLabelProvider).value ?? 'Hanamimi+ 花耳',
                style: AppText.caption(theme)),
            onTap: () => showAboutHanamimi(context),
          ),
          Divider(height: 0.5, color: theme.divider),
          ListTile(
            leading: Icon(Icons.system_update_outlined,
                size: 20, color: theme.textMuted),
            title:
                Text('Check for updates', style: AppText.rowSongTitle(theme)),
            subtitle: Text('New builds land on GitHub Releases',
                style: AppText.caption(theme)),
            onTap: () async {
              final update = await ref.refresh(updateCheckProvider.future);
              if (!context.mounted) return;
              if (update != null) {
                await showUpdateDialog(context, update);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.md)),
                  content: const Text("You're up to date 🐾",
                      style: TextStyle(fontFamily: 'Nunito')),
                ));
              }
            },
          ),
          // Battery optimization is an Android concept — desktop has no
          // Doze/App-Standby, so the row is meaningless noise there.
          if (Platform.isAndroid) ...[
            Divider(height: 0.5, color: theme.divider),
            const _KeepPlayingRow(),
          ],
          if (ref.watch(devModeProvider).enabled) ...[
            Divider(height: 0.5, color: theme.divider),
            const _DevOptions(),
          ],
        ],
      ),
    );
  }
}

/// "Keep playing in background" — offers the battery-optimization
/// exemption so OEM battery killers don't pause playback (and leave the
/// seek bar stuck) when the app is backgrounded.
class _KeepPlayingRow extends ConsumerWidget {
  const _KeepPlayingRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final ignored = ref.watch(batteryOptIgnoredProvider).value ?? true;
    return ListTile(
      leading: Icon(Icons.battery_saver_outlined,
          size: 20, color: theme.textMuted),
      title: Text('Keep playing in background',
          style: AppText.rowSongTitle(theme)),
      subtitle: Text(
        ignored
            ? "Allowed — the system won't pause your music"
            : 'Tap to stop the system killing playback',
        style: AppText.caption(theme),
      ),
      trailing: ignored
          ? Icon(Icons.check_circle_outline, size: 18, color: theme.primary)
          : Icon(Icons.chevron_right, size: 18, color: theme.textMuted),
      onTap: ignored
          ? null
          : () async {
              await PowerChannel.requestIgnoreBatteryOptimizations();
              ref.invalidate(batteryOptIgnoredProvider);
            },
    );
  }
}

/// Desktop: manage the folders the library scans. Rescans on close if
/// the set changed.
Future<void> _showMusicFoldersSheet(
    BuildContext context, WidgetRef ref, HanamimiTheme theme) async {
  final before = ref.read(musicFoldersProvider);
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.7,
      child: _MusicFoldersSheet(),
    ),
  );
  if (!setEquals(before, ref.read(musicFoldersProvider))) {
    ref.read(libraryProvider.notifier).rescan();
  }
}

class _MusicFoldersSheet extends ConsumerWidget {
  const _MusicFoldersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final folders = ref.watch(musicFoldersProvider).toList()..sort();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Music folders',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.textPrimary)),
            const SizedBox(height: Space.s1),
            Text('Your library is built from the songs inside these folders',
                style: AppText.caption(theme)),
            const SizedBox(height: Space.s2),
            Expanded(
              child: folders.isEmpty
                  ? Center(
                      child: Text('No folders yet — add your music folder',
                          style: AppText.body(theme)))
                  : ListView.builder(
                      itemCount: folders.length,
                      itemBuilder: (context, i) {
                        final path = folders[i];
                        final name =
                            path.substring(path.lastIndexOf('/') + 1);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.folder_outlined,
                              size: 20, color: theme.textMuted),
                          title: Text(name.isEmpty ? path : name,
                              style: AppText.rowSongTitle(theme),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(path,
                              style: AppText.caption(theme),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            icon: Icon(Icons.close,
                                size: 18, color: theme.textMuted),
                            onPressed: () => ref
                                .read(musicFoldersProvider.notifier)
                                .remove(path),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: Space.s2),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.md)),
                ),
                onPressed: () async {
                  final dir = await getDirectoryPath();
                  if (dir != null) {
                    ref.read(musicFoldersProvider.notifier).add(dir);
                  }
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add folder',
                    style: TextStyle(
                        fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the excluded-folders manager; rescans on close if the
/// selection changed so the library reflects it right away.
Future<void> _showExcludedFoldersSheet(
    BuildContext context, WidgetRef ref, HanamimiTheme theme) async {
  final before = ref.read(excludedFoldersProvider);
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.7,
      child: _ExcludedFoldersSheet(),
    ),
  );
  if (!setEquals(before, ref.read(excludedFoldersProvider))) {
    ref.read(libraryProvider.notifier).rescan();
  }
}

/// Every device folder that contains music (straight from MediaStore,
/// so already-excluded folders stay listed and can be re-included).
class _ExcludedFoldersSheet extends ConsumerStatefulWidget {
  const _ExcludedFoldersSheet();

  @override
  ConsumerState<_ExcludedFoldersSheet> createState() =>
      _ExcludedFoldersSheetState();
}

class _ExcludedFoldersSheetState
    extends ConsumerState<_ExcludedFoldersSheet> {
  List<(String, String, int)>? _folders; // (path, name, song count)
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Fresh index query (not the DB) so already-excluded folders stay
      // listed: MediaStore on Android, a plain walk on desktop.
      final paths = Platform.isAndroid
          ? [
              for (final s in await MediaStoreChannel.queryTracks())
                s['filePath'] as String? ?? '',
            ]
          : await DesktopLibrary.listAudioFiles(
              ref.read(musicFoldersProvider));
      final counts = <String, int>{};
      for (final path in paths) {
        final slash = path.lastIndexOf('/');
        final dir = slash <= 0 ? '/' : path.substring(0, slash);
        counts[dir] = (counts[dir] ?? 0) + 1;
      }
      // Keep excluded folders visible even if their files vanished.
      for (final dir in ref.read(excludedFoldersProvider)) {
        counts.putIfAbsent(dir, () => 0);
      }
      final folders = counts.entries.map((e) {
        final name = e.key.substring(e.key.lastIndexOf('/') + 1);
        return (e.key, name.isEmpty ? '/' : name, e.value);
      }).toList()
        ..sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
      if (mounted) setState(() => _folders = folders);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    final excluded = ref.watch(excludedFoldersProvider);
    final folders = _folders;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(Space.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Excluded folders',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: theme.textPrimary)),
            const SizedBox(height: Space.s1),
            Text('Songs in switched-off folders are left out of your library',
                style: AppText.caption(theme)),
            const SizedBox(height: Space.s2),
            Expanded(
              child: _failed
                  ? Center(
                      child: Text('Couldn\'t read your music folders',
                          style: AppText.body(theme)))
                  : folders == null
                      ? Center(
                          child: CircularProgressIndicator(
                              color: theme.primary))
                      : folders.isEmpty
                          ? Center(
                              child: Text('No music folders found',
                                  style: AppText.body(theme)))
                          : ListView.builder(
                              itemCount: folders.length,
                              itemBuilder: (context, i) {
                                final (path, name, count) = folders[i];
                                return SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: !excluded.contains(path),
                                  title: Text(name,
                                      style: AppText.rowSongTitle(theme),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Text(
                                    '$count song${count == 1 ? '' : 's'} · $path',
                                    style: AppText.caption(theme),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onChanged: (_) => ref
                                      .read(excludedFoldersProvider.notifier)
                                      .toggle(path),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hidden developer tools (7 taps on About).
class _DevOptions extends ConsumerWidget {
  const _DevOptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final dev = ref.watch(devModeProvider);

    void toast(String message) =>
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.md)),
          content:
              Text(message, style: const TextStyle(fontFamily: 'Nunito')),
        ));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(
              left: Space.s4, top: Space.s3, bottom: Space.s1),
          child: Row(
            children: [
              Text('DEVELOPER', style: AppText.sectionLabel(theme)),
            ],
          ),
        ),
        ListTile(
          leading: const Text('🎀', style: TextStyle(fontSize: 16)),
          title: Text('Unlock all accessories',
              style: AppText.rowSongTitle(theme)),
          trailing: Switch(
            value: dev.allAccessories,
            onChanged: (on) =>
                ref.read(devModeProvider.notifier).setAllAccessories(on),
          ),
        ),
        ListTile(
          leading:
              Icon(Icons.lyrics_outlined, size: 20, color: theme.textMuted),
          title:
              Text('Clear lyrics cache', style: AppText.rowSongTitle(theme)),
          subtitle: Text('Refetch all lyrics on next open',
              style: AppText.caption(theme)),
          onTap: () async {
            final repo = await ref.read(libraryRepositoryProvider.future);
            await repo.clearLyricsCache();
            toast('Lyrics cache cleared');
          },
        ),
        ListTile(
          leading:
              Icon(Icons.timer_outlined, size: 20, color: theme.textMuted),
          title: Text('Hide developer options',
              style: AppText.rowSongTitle(theme)),
          onTap: () {
            ref.read(devModeProvider.notifier).disable();
            toast('Developer mode off');
          },
        ),
      ],
    );
  }
}

class _OnlineSettings extends ConsumerWidget {
  const _OnlineSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final enabled = ref.watch(onlineEnabledProvider);
    final quality = ref.watch(streamQualityProvider);
    final meteredQuality = ref.watch(meteredQualityProvider);
    final cacheMb = ref.watch(streamCacheSizeProvider);

    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: theme.divider, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Online features',
                        style: AppText.rowSongTitle(theme)),
                    Text('Search & stream from YouTube and JioSaavn',
                        style: AppText.caption(theme)),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (on) =>
                    ref.read(onlineEnabledProvider.notifier).set(on),
              ),
            ],
          ),
          AnimatedSize(
            duration: Anim.minTransition,
            child: !enabled
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      Divider(height: Space.s6, color: theme.divider),
                      _QualityRow(
                        label: 'Streaming quality',
                        subtitle: 'Higher uses more data',
                        value: quality == StreamQuality.high ? 'High' : 'Low',
                        onTap: () => ref
                            .read(streamQualityProvider.notifier)
                            .set(quality == StreamQuality.high
                                ? StreamQuality.low
                                : StreamQuality.high),
                        theme: theme,
                      ),
                      Divider(height: Space.s6, color: theme.divider),
                      _QualityRow(
                        label: 'On mobile data',
                        subtitle: 'Quality when off Wi-Fi',
                        value: switch (meteredQuality) {
                          MeteredQuality.low => 'Low',
                          MeteredQuality.high => 'High',
                          MeteredQuality.matchWifi => 'Use Wi-Fi setting',
                        },
                        onTap: () {
                          const order = MeteredQuality.values;
                          final next = order[
                              (meteredQuality.index + 1) % order.length];
                          ref
                              .read(meteredQualityProvider.notifier)
                              .set(next);
                        },
                        theme: theme,
                      ),
                      Divider(height: Space.s6, color: theme.divider),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Stream cache',
                              style: AppText.rowSongTitle(theme)),
                          Text('Recently streamed songs replay data-free',
                              style: AppText.caption(theme)),
                          Row(
                            children: [
                              Icon(Icons.sd_storage_outlined,
                                  size: 16, color: theme.primary),
                              Expanded(
                                child: Slider(
                                  value: cacheMb
                                      .toDouble()
                                      .clamp(128, 2048),
                                  min: 128,
                                  max: 2048,
                                  divisions: 15,
                                  onChanged: (v) => ref
                                      .read(streamCacheSizeProvider.notifier)
                                      .set(v.round()),
                                ),
                              ),
                              SizedBox(
                                width: 56,
                                child: Text(
                                  cacheMb >= 1024
                                      ? '${(cacheMb / 1024).toStringAsFixed(1)} GB'
                                      : '$cacheMb MB',
                                  style: AppText.caption(theme),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Divider(height: Space.s6, color: theme.divider),
                      _QualityRow(
                        label: 'Download quality',
                        subtitle: 'Used when saving songs offline',
                        value: switch (ref.watch(downloadQualityProvider)) {
                          null => 'Ask every time',
                          StreamQuality.low => 'Low',
                          StreamQuality.high => 'High',
                        },
                        onTap: () {
                          final current = ref.read(downloadQualityProvider);
                          ref.read(downloadQualityProvider.notifier).set(
                              switch (current) {
                            null => StreamQuality.low,
                            StreamQuality.low => StreamQuality.high,
                            StreamQuality.high => null,
                          });
                        },
                        theme: theme,
                      ),
                      Divider(height: Space.s6, color: theme.divider),
                      const _UpdateExtractorTile(),
                      Divider(height: Space.s6, color: theme.divider),
                      const _YtMusicTile(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Pulls a fresh yt-dlp at runtime (M28). This is the escape hatch when
/// YouTube changes something and extraction breaks — no app update
/// needed. Spins while updating; toasts the new version.
class _UpdateExtractorTile extends ConsumerStatefulWidget {
  const _UpdateExtractorTile();

  @override
  ConsumerState<_UpdateExtractorTile> createState() =>
      _UpdateExtractorTileState();
}

class _UpdateExtractorTileState extends ConsumerState<_UpdateExtractorTile> {
  bool _busy = false;

  Future<void> _update() async {
    if (_busy) return;
    setState(() => _busy = true);
    final version = await YtDlpChannel.update();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      content: Text(
        version != null
            ? 'YouTube extractor updated · yt-dlp $version'
            : "Couldn't update the extractor",
        style: const TextStyle(fontFamily: 'Nunito'),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    return InkWell(
      onTap: _busy ? null : _update,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Update YouTube extractor',
                    style: AppText.rowSongTitle(theme)),
                Text('Fixes playback if YouTube changes — no app update',
                    style: AppText.caption(theme)),
              ],
            ),
          ),
          _busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: theme.primary),
                )
              : Icon(Icons.system_update_alt,
                  size: 20, color: theme.primary),
        ],
      ),
    );
  }
}

/// Tier 3 (ARCHITECTURE-RECOMMENDATIONS.md §4): YT Music sign-in.
/// Connected state exposes the read-only feedback-loop toggle; sign-out
/// wipes the encrypted cookie.
class _YtMusicTile extends ConsumerWidget {
  const _YtMusicTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final account = ref.watch(ytAccountProvider).value ?? YtAccount.none;
    return Column(
      children: [
        InkWell(
          onTap: () async {
            if (!account.connected) {
              await showYtSignInDialog(context);
              return;
            }
            await ref.read(ytAccountProvider.notifier).disconnect();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.md)),
                content: const Text('YT Music signed out — cookie wiped',
                    style: TextStyle(fontFamily: 'Nunito')),
              ));
            }
          },
          borderRadius: BorderRadius.circular(Radii.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('YT Music account',
                        style: AppText.rowSongTitle(theme)),
                    Text(
                      account.connected
                          ? 'Signed in — personalized picks on Home. '
                              'Tap to sign out'
                          : 'Opt-in: your real feed (a burner account '
                              'is wise)',
                      style: AppText.caption(theme),
                    ),
                  ],
                ),
              ),
              Icon(
                account.connected ? Icons.link_off : Icons.smart_display_outlined,
                size: 20,
                color: account.connected ? theme.primary : theme.textMuted,
              ),
            ],
          ),
        ),
        if (account.connected) ...[
          const SizedBox(height: Space.s3),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Report plays to YT history',
                        style: AppText.caption(theme)
                            .copyWith(fontWeight: FontWeight.w700)),
                    Text(
                        'Off = read-only (playback stays anonymous). '
                        'On trains your YT recommendations.',
                        style: AppText.caption(theme)),
                  ],
                ),
              ),
              Switch(
                value: account.reportPlays,
                onChanged: (on) => ref
                    .read(ytAccountProvider.notifier)
                    .setReportPlays(on),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final String subtitle;
  final String value;
  final VoidCallback onTap;
  final HanamimiTheme theme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.rowSongTitle(theme)),
                Text(subtitle, style: AppText.caption(theme)),
              ],
            ),
          ),
          Text(value,
              style: AppText.rowSongTitle(theme)
                  .copyWith(color: theme.primary)),
          Icon(Icons.chevron_right, size: 18, color: theme.textMuted),
        ],
      ),
    );
  }
}

class _SoundSettings extends ConsumerWidget {
  const _SoundSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final crossfadeSeconds = ref.watch(crossfadeProvider);
    final enabled = crossfadeSeconds > 0;

    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: theme.divider, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Crossfade',
                        style: AppText.rowSongTitle(theme)),
                    Text('Blend the end of a song into the next',
                        style: AppText.caption(theme)),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: (on) =>
                    ref.read(crossfadeProvider.notifier).set(on ? 6 : 0),
              ),
            ],
          ),
          AnimatedSize(
            duration: Anim.minTransition,
            child: !enabled
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: [
                      const SizedBox(height: Space.s2),
                      Row(
                        children: [
                          Icon(Icons.pets,
                              size: 16, color: theme.primary),
                          Expanded(
                            child: Slider(
                              value: crossfadeSeconds.toDouble(),
                              min: 2,
                              max: 12,
                              divisions: 10,
                              onChanged: (v) => ref
                                  .read(crossfadeProvider.notifier)
                                  .set(v.round()),
                            ),
                          ),
                          SizedBox(
                            width: 28,
                            child: Text('${crossfadeSeconds}s',
                                style: AppText.caption(theme)),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          Divider(height: Space.s6, color: theme.divider),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Visualizer sensitivity',
                  style: AppText.rowSongTitle(theme)),
              Text('Turn up for songs that barely move it',
                  style: AppText.caption(theme)),
              Row(
                children: [
                  Icon(Icons.graphic_eq, size: 16, color: theme.primary),
                  Expanded(
                    child: Slider(
                      value: ref
                          .watch(visualizerSensitivityProvider)
                          .clamp(0.5, 3.0)
                          .toDouble(),
                      min: 0.5,
                      max: 3.0,
                      divisions: 10,
                      onChanged: (v) => ref
                          .read(visualizerSensitivityProvider.notifier)
                          .set(v),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${ref.watch(visualizerSensitivityProvider).toStringAsFixed(2)}×',
                      style: AppText.caption(theme),
                    ),
                  ),
                ],
              ),
              Text('Reactivity', style: AppText.rowSongTitle(theme)),
              Text('Jumpy needle up high, silky-smooth down low',
                  style: AppText.caption(theme)),
              Row(
                children: [
                  Icon(Icons.bolt, size: 16, color: theme.primary),
                  Expanded(
                    child: Slider(
                      value: ref
                          .watch(visualizerReactivityProvider)
                          .clamp(0.5, 3.0)
                          .toDouble(),
                      min: 0.5,
                      max: 3.0,
                      divisions: 10,
                      onChanged: (v) => ref
                          .read(visualizerReactivityProvider.notifier)
                          .set(v),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${ref.watch(visualizerReactivityProvider).toStringAsFixed(2)}×',
                      style: AppText.caption(theme),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Divider(height: Space.s6, color: theme.divider),
          _QualityRow(
            label: 'Visualizer style',
            subtitle: 'How the music dances',
            value: _visualizerStyleNames[
                ref.watch(effectiveVisualizerStyleProvider)]!,
            theme: theme,
            onTap: () {
              const order = VisualizerStyle.values;
              final current = ref.read(effectiveVisualizerStyleProvider);
              ref.read(visualizerStyleOverrideProvider.notifier).set(
                  order[(order.indexOf(current) + 1) % order.length]);
            },
          ),
          if (ref.watch(effectiveVisualizerStyleProvider) !=
              VisualizerStyle.bars) ...[
            Divider(height: Space.s6, color: theme.divider),
            _QualityRow(
              label: 'VU source',
              subtitle: 'What the meters listen to',
              value: ref.watch(vuSplitProvider)
                  ? 'Bass & treble'
                  : 'Loudness',
              theme: theme,
              onTap: () => ref
                  .read(vuSplitProvider.notifier)
                  .set(!ref.read(vuSplitProvider)),
            ),
          ],
          if (ref.watch(effectiveVisualizerStyleProvider) ==
              VisualizerStyle.ledVu) ...[
            Divider(height: Space.s6, color: theme.divider),
            _QualityRow(
              label: 'LED look',
              subtitle: 'Segmented or smooth',
              value: ref.watch(ledVuDiscreteProvider)
                  ? 'Discrete LEDs'
                  : 'Continuous bar',
              theme: theme,
              onTap: () => ref
                  .read(ledVuDiscreteProvider.notifier)
                  .set(!ref.read(ledVuDiscreteProvider)),
            ),
          ],
          Divider(height: Space.s6, color: theme.divider),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Autoplay', style: AppText.rowSongTitle(theme)),
                    Text(
                        'When the queue ends, keep going with '
                        'similar songs',
                        style: AppText.caption(theme)),
                  ],
                ),
              ),
              Switch(
                value: ref.watch(autoplayProvider),
                onChanged: (_) =>
                    ref.read(autoplayProvider.notifier).toggle(),
              ),
            ],
          ),
          Divider(height: Space.s6, color: theme.divider),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Smart shuffle', style: AppText.rowSongTitle(theme)),
                    Text(
                        'Shuffle leans toward your favorites — '
                        'computed on this device',
                        style: AppText.caption(theme)),
                  ],
                ),
              ),
              Switch(
                value: ref.watch(smartShuffleProvider),
                onChanged: (_) =>
                    ref.read(smartShuffleProvider.notifier).toggle(),
              ),
            ],
          ),
          Divider(height: Space.s6, color: theme.divider),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Nerd mode', style: AppText.rowSongTitle(theme)),
                    Text('Show codec, bitrate & audio output on Now Playing',
                        style: AppText.caption(theme)),
                  ],
                ),
              ),
              Switch(
                value: ref.watch(nerdModeProvider),
                onChanged: (on) =>
                    ref.read(nerdModeProvider.notifier).set(on),
              ),
            ],
          ),
          Divider(height: Space.s6, color: theme.divider),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Equalizer', style: AppText.rowSongTitle(theme)),
                    Text('Coming soon', style: AppText.caption(theme)),
                  ],
                ),
              ),
              Switch(value: false, onChanged: null),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeTile extends ConsumerWidget {
  const _ThemeTile({
    required this.tile,
    required this.active,
    required this.onTap,
  });

  final HanamimiTheme tile;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Anim.minTransition,
        padding: const EdgeInsets.all(Space.s3),
        decoration: BoxDecoration(
          color: tile.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: active ? theme.primary : theme.divider,
            width: active ? 2 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(tile.emoji, style: const TextStyle(fontSize: 20)),
            Text(
              tile.name,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: tile.textPrimary,
              ),
            ),
            Row(
              children: [
                for (final c in [tile.primary, tile.secondary, tile.accent])
                  Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.only(right: Space.s1),
                    decoration:
                        BoxDecoration(color: c, shape: BoxShape.circle),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

const _visualizerStyleNames = <VisualizerStyle, String>{
  VisualizerStyle.bars: 'Bars',
  VisualizerStyle.vuMeters: 'VU meters',
  VisualizerStyle.ledVu: 'LED VU meter',
};

