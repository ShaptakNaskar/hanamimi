import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/sleep_timer_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../../utils/duration_ext.dart';
import '../components/mascot/hanamimi_widget.dart';
import '../screens/blackout_screen.dart';

/// Bottom sheet with the 2×2 moon presets (DESIGN.md §9.8).
/// Moon phases scale with duration: crescent = short, full = long.
void showSleepTimerModal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _SleepTimerBody(),
  );
}

class _Preset {
  const _Preset(this.label, this.icon, this.duration);
  final String label;
  final IconData icon;
  final Duration? duration; // null = end of track
}

const _presets = [
  _Preset('15 minutes', Icons.brightness_3, Duration(minutes: 15)),
  _Preset('30 minutes', Icons.brightness_2, Duration(minutes: 30)),
  _Preset('1 hour', Icons.brightness_1, Duration(hours: 1)),
  _Preset('End of track', Icons.music_note_outlined, null),
];

class _SleepTimerBody extends ConsumerWidget {
  const _SleepTimerBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final timer = ref.watch(sleepTimerProvider);
    final alsoBlackout = ref.watch(blackoutOnSleepProvider);

    void start(_Preset p) {
      final notifier = ref.read(sleepTimerProvider.notifier);
      if (p.duration == null) {
        notifier.startEndOfTrack();
      } else {
        notifier.startCountdown(p.duration!);
      }
      // Fall into the bedside-amp screen if they've opted in. Pop the
      // sheet first, then push Blackout onto the same navigator.
      if (ref.read(blackoutOnSleepProvider)) {
        final nav = Navigator.of(context);
        nav.pop();
        nav.push(BlackoutScreen.route());
      }
    }

    return Padding(
      padding: EdgeInsets.only(
        left: Space.s4,
        right: Space.s4,
        top: Space.s4,
        bottom: MediaQuery.of(context).padding.bottom + Space.s6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Sleep timer',
                  style: TextStyle(
                      fontFamily: 'Nunito',
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: theme.textPrimary)),
              const Spacer(),
              InkResponse(
                onTap: () => Navigator.pop(context),
                radius: 20,
                child: Icon(Icons.close, color: theme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: Space.s2),
          const Center(
            child:
                HanamimiMascot(state: MascotState.sleeping, size: 84),
          ),
          const SizedBox(height: Space.s4),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Space.s3,
            crossAxisSpacing: Space.s3,
            childAspectRatio: 2.2,
            children: [
              for (final p in _presets)
                _PresetTile(
                  preset: p,
                  theme: theme,
                  active: _isActive(timer, p),
                  onTap: () => start(p),
                ),
            ],
          ),
          const SizedBox(height: Space.s3),
          _BlackoutToggle(
            theme: theme,
            value: alsoBlackout,
            onChanged: (v) =>
                ref.read(blackoutOnSleepProvider.notifier).set(v),
          ),
          AnimatedSize(
            duration: Anim.minTransition,
            child: !timer.isActive
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: Space.s4),
                    child: Column(
                      children: [
                        Center(
                          child: Text(
                            switch (timer.mode) {
                              SleepMode.countdown => timer.isFading
                                  ? 'Fading out… sweet dreams'
                                  : 'Sleeping in ${timer.remaining!.mmss}',
                              SleepMode.endOfTrack =>
                                'Sleeping when this song ends',
                              SleepMode.off => '',
                            },
                            style: AppText.body(theme)
                                .copyWith(color: theme.primary),
                          ),
                        ),
                        const SizedBox(height: Space.s3),
                        Center(
                          child: TextButton(
                            onPressed: () => ref
                                .read(sleepTimerProvider.notifier)
                                .cancel(),
                            child: Text('Cancel timer',
                                style: AppText.button(theme)
                                    .copyWith(color: theme.textMuted)),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  bool _isActive(SleepTimerState s, _Preset p) {
    if (!s.isActive) return false;
    if (p.duration == null) return s.mode == SleepMode.endOfTrack;
    // Highlight the nearest preset at/above the remaining time.
    return s.mode == SleepMode.countdown &&
        s.remaining != null &&
        s.remaining! <= p.duration! &&
        !_presets.any((q) =>
            q.duration != null &&
            q.duration! < p.duration! &&
            s.remaining! <= q.duration!);
  }
}

class _BlackoutToggle extends StatelessWidget {
  const _BlackoutToggle({
    required this.theme,
    required this.value,
    required this.onChanged,
  });

  final HanamimiTheme theme;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Space.s2, vertical: Space.s2),
        child: Row(
          children: [
            Icon(Icons.bedtime_rounded,
                size: 20,
                color: value ? theme.primary : theme.textMuted),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fade into Blackout',
                      style: AppText.button(theme).copyWith(
                          color: value
                              ? theme.primary
                              : theme.textPrimary)),
                  const SizedBox(height: 2),
                  Text('A dark clock and VU meters while it winds down',
                      style: AppText.caption(theme)),
                ],
              ),
            ),
            Switch(
              value: value,
              activeColor: theme.primary,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.theme,
    required this.active,
    required this.onTap,
  });

  final _Preset preset;
  final HanamimiTheme theme;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Anim.minTransition,
        decoration: BoxDecoration(
          color: active
              ? theme.primary.withValues(alpha: 0.2)
              : theme.background,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: active ? theme.primary : theme.divider,
            width: active ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(preset.icon,
                size: 20,
                color: active ? theme.primary : theme.textMuted),
            const SizedBox(width: Space.s2),
            Text(preset.label,
                style: AppText.button(theme).copyWith(
                    color:
                        active ? theme.primary : theme.textPrimary)),
          ],
        ),
      ),
    );
  }
}
