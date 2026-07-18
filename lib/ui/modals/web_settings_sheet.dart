import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/buddy_provider.dart';
import '../../providers/night_mode_provider.dart';
import '../../providers/nerd_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/visualizer_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../../theme/themes.dart';
import 'about_dialog.dart';

/// The web demo's one settings surface: mood (themes), visualizer
/// knobs, playback handoff, night mode, buddies, About. A compact
/// remix of the You tab for a player that is only a player.
Future<void> showWebSettingsSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.85,
      child: _WebSettingsBody(),
    ),
  );
}

class _WebSettingsBody extends ConsumerWidget {
  const _WebSettingsBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final night = ref.watch(nightModeActiveProvider);
    final autoGain = ref.watch(visualizerAutoGainProvider);
    final styleOverride = ref.watch(visualizerStyleOverrideProvider);
    final crossfade = ref.watch(crossfadeProvider);
    final slowDance = ref.watch(slowDanceProvider);

    Widget section(String label) => Padding(
          padding:
              const EdgeInsets.fromLTRB(Space.s4, Space.s6, Space.s4, Space.s2),
          child:
              Text(label.whisper(night), style: AppText.sectionLabel(theme)),
        );

    Widget toggle(String title, String? caption, bool value,
            void Function(bool) onChanged) =>
        SwitchListTile(
          value: value,
          onChanged: onChanged,
          // Track wears the theme; the thumb stays its contrasting
          // default — activeColor (= thumb) in primary melted the whole
          // switch into one blob (user report).
          activeTrackColor: theme.primary,
          inactiveTrackColor: theme.divider.withValues(alpha: 0.5),
          inactiveThumbColor: theme.textMuted,
          dense: true,
          title: Text(title.whisper(night),
              style: AppText.rowSongTitle(theme)),
          subtitle: caption == null
              ? null
              : Text(caption.whisper(night), style: AppText.caption(theme)),
        );

    return Material(
      color: theme.background,
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(Radii.lg)),
      child: ListView(
        padding: const EdgeInsets.only(bottom: Space.s8),
        children: [
          const SizedBox(height: Space.s3),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.divider,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
            ),
          ),
          section('Mood'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            child: Wrap(
              spacing: Space.s2,
              runSpacing: Space.s2,
              children: [
                for (final t in allThemes) _ThemeChip(theme: theme, entry: t),
              ],
            ),
          ),
          section('Visualizer'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            child: SegmentedButton<VisualizerStyle?>(
              segments: const [
                ButtonSegment(value: null, label: Text('Theme')),
                ButtonSegment(
                    value: VisualizerStyle.bars, label: Text('Bars')),
                ButtonSegment(
                    value: VisualizerStyle.vuMeters, label: Text('VU')),
                ButtonSegment(
                    value: VisualizerStyle.ledVu, label: Text('LED')),
              ],
              selected: {styleOverride},
              onSelectionChanged: (s) => ref
                  .read(visualizerStyleOverrideProvider.notifier)
                  .set(s.first),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor:
                    theme.primary.withValues(alpha: 0.18),
                selectedForegroundColor: theme.primary,
                foregroundColor: theme.textMuted,
                side: BorderSide(color: theme.divider),
                textStyle: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          toggle(
            'Auto gain',
            'each song\'s own loudness fills the meters',
            autoGain,
            (v) => ref.read(visualizerAutoGainProvider.notifier).set(v),
          ),
          if (!autoGain)
            _SliderRow(
              label: 'Sensitivity',
              theme: theme,
              value: ref.watch(visualizerSensitivityProvider),
              min: 0.5,
              max: 3,
              onChanged: (v) =>
                  ref.read(visualizerSensitivityProvider.notifier).set(v),
            ),
          _SliderRow(
            label: 'Reactivity',
            theme: theme,
            value: ref.watch(visualizerReactivityProvider),
            min: 0.5,
            max: 3,
            onChanged: (v) =>
                ref.read(visualizerReactivityProvider.notifier).set(v),
          ),
          toggle(
            'VU shows bass & treble',
            'off = true left/right loudness, like a real VU',
            ref.watch(vuSplitProvider),
            (v) => ref.read(vuSplitProvider.notifier).set(v),
          ),
          toggle(
            'LED meter segments',
            'off = continuous gradient bar',
            ref.watch(ledVuDiscreteProvider),
            (v) => ref.read(ledVuDiscreteProvider.notifier).set(v),
          ),
          section('Playback'),
          _SliderRow(
            label: crossfade == 0
                ? 'Crossfade off'
                : 'Crossfade ${crossfade}s',
            theme: theme,
            value: crossfade.toDouble(),
            min: 0,
            max: 12,
            divisions: 12,
            onChanged: (v) =>
                ref.read(crossfadeProvider.notifier).set(v.round()),
          ),
          toggle(
            'Slow Dance',
            'reads where the song\'s energy dies and times the fade itself',
            slowDance,
            (v) => ref.read(slowDanceProvider.notifier).set(v),
          ),
          toggle(
            'Melt away',
            'idle listening fades the controls until it\'s just art + music',
            ref.watch(meltAwayProvider),
            (_) => ref.read(meltAwayProvider.notifier).toggle(),
          ),
          toggle(
            'Nerd mode',
            'codec · bitrate chips on Now Playing',
            ref.watch(nerdModeProvider),
            (v) => ref.read(nerdModeProvider.notifier).set(v),
          ),
          section('Night'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            child: SegmentedButton<NightModeSetting>(
              segments: const [
                ButtonSegment(
                    value: NightModeSetting.auto, label: Text('Auto')),
                ButtonSegment(
                    value: NightModeSetting.always, label: Text('Always')),
                ButtonSegment(
                    value: NightModeSetting.never, label: Text('Never')),
              ],
              selected: {ref.watch(nightModeSettingProvider)},
              onSelectionChanged: (s) => ref
                  .read(nightModeSettingProvider.notifier)
                  .set(s.first),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor:
                    theme.primary.withValues(alpha: 0.18),
                selectedForegroundColor: theme.primary,
                foregroundColor: theme.textMuted,
                side: BorderSide(color: theme.divider),
                textStyle: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s1, Space.s4, 0),
            child: Text(
              'after midnight the palette dims to embers, the copy '
                      'whispers in lowercase, and the volume rides a little '
                      'gentler.'
                  .whisper(night),
              style: AppText.caption(theme),
            ),
          ),
          section('Buddies'),
          toggle(
            'Hanamimi',
            'the beagle on Now Playing',
            ref.watch(buddyEnabledProvider('beagle')),
            (v) => ref
                .read(buddyTogglesProvider.notifier)
                .setEnabled('beagle', v),
          ),
          toggle(
            'Cat chases your pointer',
            'off = she naps on the sidebar instead (she does that anyway)',
            ref.watch(catFollowProvider),
            (v) => ref.read(catFollowProvider.notifier).set(v),
          ),
          toggle(
            'Fireflies',
            'glow on the dark themes',
            ref.watch(buddyEnabledProvider('fireflies')),
            (v) => ref
                .read(buddyTogglesProvider.notifier)
                .setEnabled('fireflies', v),
          ),
          const SizedBox(height: Space.s4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.s4),
            child: OutlinedButton(
              onPressed: () => showAboutHanamimi(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.primary,
                side: BorderSide(color: theme.divider),
                padding: const EdgeInsets.symmetric(vertical: Space.s3),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(Radii.md)),
              ),
              child: Text('About Hanamimi'.whisper(night),
                  style: const TextStyle(
                      fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeChip extends ConsumerWidget {
  const _ThemeChip({required this.theme, required this.entry});

  final HanamimiTheme theme; // the live theme (for chrome colors)
  final HanamimiTheme entry; // the theme this chip selects

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedThemeIdProvider) == entry.id;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () =>
          ref.read(selectedThemeIdProvider.notifier).setTheme(entry.id),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.s3, vertical: Space.s2),
        decoration: BoxDecoration(
          color: entry.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: selected ? theme.primary : theme.divider,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(entry.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: Space.s2),
            Text(
              entry.name,
              style: TextStyle(
                fontFamily: 'Nunito',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: entry.textPrimary,
              ),
            ),
            // The three palette dots, like the mood cards.
            const SizedBox(width: Space.s2),
            for (final c in [entry.primary, entry.secondary, entry.accent])
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: c, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.theme,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final HanamimiTheme theme;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final void Function(double) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: AppText.caption(theme)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              activeColor: theme.primary,
              inactiveColor: theme.divider,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
