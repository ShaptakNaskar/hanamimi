import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/cat_mode_provider.dart';
import '../../providers/companion_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/mascot_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../../theme/themes.dart';
import '../components/mascot/hanamimi_widget.dart';
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
          Text('You', style: AppText.screenTitle(theme)),
          const SizedBox(height: Space.s6),
          Text('MOOD', style: AppText.sectionLabel(theme)),
          const SizedBox(height: Space.s3),
          GridView.count(
            crossAxisCount: 2,
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
                  onTap: () =>
                      ref.read(currentThemeProvider.notifier).setTheme(t.id),
                ),
            ],
          ),
          const SizedBox(height: Space.s8),
          Text('YOUR COMPANION', style: AppText.sectionLabel(theme)),
          const SizedBox(height: Space.s3),
          const _CompanionCard(),
          const SizedBox(height: Space.s8),
          Text('SOUND', style: AppText.sectionLabel(theme)),
          const SizedBox(height: Space.s3),
          const _SoundSettings(),
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
                  unlocked: isUnlocked(info, listened),
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
            subtitle: Text('Hanamimi 花耳 0.1 — named after a real dog',
                style: AppText.caption(theme)),
          ),
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
