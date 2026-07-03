import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/mascot_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../../theme/themes.dart';
import '../components/mascot/hanamimi_widget.dart';

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
          Container(
            padding: const EdgeInsets.all(Space.s4),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: theme.divider, width: 0.5),
            ),
            child: Center(
              child: HanamimiMascot(
                state: ref.watch(mascotStateProvider),
                size: 130,
                fullBody: true,
              ),
            ),
          ),
          const SizedBox(height: Space.s8),
          Text('SOUND', style: AppText.sectionLabel(theme)),
          const SizedBox(height: Space.s3),
          const _SoundSettings(),
          const SizedBox(height: Space.s12),
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
