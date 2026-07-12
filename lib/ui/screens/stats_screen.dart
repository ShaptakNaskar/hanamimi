import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/models/track.dart';
import '../../providers/leaderboard_provider.dart';
import '../../providers/night_mode_provider.dart';
import '../../providers/stats_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/hanamimi_theme.dart';
import '../../theme/theme_tokens.dart';
import '../modals/leaderboard_optin_dialog.dart';

/// "Listening stats" — per-platform + cumulative counts, plus the opt-in
/// global leaderboard (top 10). Time is always tracked locally; only
/// *sharing* is a choice, and it always goes through the consent dialog.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const StatsScreen());

  static String _fmt(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final stats = ref.watch(listenStatsProvider);
    final account = ref.watch(leaderboardAccountProvider);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.surface,
        title: Text(
            'Listening stats'
                .whisper(ref.watch(nightModeActiveProvider)),
            style: AppText.rowSongTitle(theme)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(Space.s4),
        children: [
          // Cumulative headline.
          Container(
            padding: const EdgeInsets.all(Space.s4),
            decoration: BoxDecoration(
              color: theme.surface,
              borderRadius: BorderRadius.circular(Radii.lg),
              border: Border.all(color: theme.divider, width: 0.5),
            ),
            child: Column(
              children: [
                Text(_fmt(stats.totalSeconds),
                    style: AppText.screenTitle(theme)
                        .copyWith(color: theme.primary)),
                Text('${stats.totalSongs} songs across everything',
                    style: AppText.caption(theme)),
              ],
            ),
          ),
          const SizedBox(height: Space.s4),
          _PlatformRow(
            label: 'On device',
            icon: Icons.folder_outlined,
            seconds: stats.secondsFor(TrackSource.local),
            songs: stats.songsFor(TrackSource.local),
            theme: theme,
            fmt: _fmt,
          ),
          _PlatformRow(
            label: 'YouTube',
            icon: Icons.smart_display_outlined,
            seconds: stats.secondsFor(TrackSource.youtube),
            songs: stats.songsFor(TrackSource.youtube),
            theme: theme,
            fmt: _fmt,
          ),
          _PlatformRow(
            label: 'JioSaavn',
            icon: Icons.radio_outlined,
            seconds: stats.secondsFor(TrackSource.saavn),
            songs: stats.songsFor(TrackSource.saavn),
            theme: theme,
            fmt: _fmt,
          ),
          const SizedBox(height: Space.s6),

          // Leaderboard opt-in / status.
          Row(
            children: [
              Text('LEADERBOARD', style: AppText.sectionLabel(theme)),
              const Spacer(),
              if (account.optedIn)
                TextButton(
                  onPressed: () async {
                    final ok = await ref
                        .read(leaderboardAccountProvider.notifier)
                        .upload();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        behavior: SnackBarBehavior.floating,
                        content: Text(ok ? 'Stats synced 🌸' : 'Sync failed',
                            style: const TextStyle(fontFamily: 'Nunito')),
                      ));
                    }
                    ref.invalidate(leaderboardProvider);
                  },
                  child: Text('Sync now',
                      style: AppText.caption(theme)
                          .copyWith(color: theme.primary)),
                ),
            ],
          ),
          const SizedBox(height: Space.s2),
          if (account.optedIn)
            Text('Sharing as ${account.nickname} — tap below to stop',
                style: AppText.caption(theme))
          else
            Text(
              'See how you stack up against other listeners. Sharing is '
              'opt-in — please use a nickname, not your real name.',
              style: AppText.caption(theme),
            ),
          const SizedBox(height: Space.s3),
          if (!account.optedIn)
            _CtaButton(
              label: 'Join the leaderboard',
              theme: theme,
              onTap: () => showLeaderboardOptInDialog(context),
            )
          else
            _CtaButton(
              label: 'Stop sharing',
              theme: theme,
              filled: false,
              onTap: () =>
                  ref.read(leaderboardAccountProvider.notifier).disconnect(),
            ),
          const SizedBox(height: Space.s6),

          const _LeaderboardList(),
        ],
      ),
    );
  }
}

class _PlatformRow extends StatelessWidget {
  const _PlatformRow({
    required this.label,
    required this.icon,
    required this.seconds,
    required this.songs,
    required this.theme,
    required this.fmt,
  });

  final String label;
  final IconData icon;
  final int seconds;
  final int songs;
  final HanamimiTheme theme;
  final String Function(int) fmt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s2),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.textMuted),
          const SizedBox(width: Space.s3),
          Expanded(
              child: Text(label, style: AppText.rowSongTitle(theme))),
          Text('${fmt(seconds)} · $songs',
              style: AppText.caption(theme)),
        ],
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({
    required this.label,
    required this.theme,
    required this.onTap,
    this.filled = true,
  });

  final String label;
  final HanamimiTheme theme;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: Sizes.inputHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? theme.primary : theme.surface,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: filled
              ? null
              : Border.all(color: theme.divider, width: 0.5),
        ),
        child: Text(label,
            style: AppText.rowSongTitle(theme).copyWith(
                color: filled ? Colors.white : theme.textPrimary)),
      ),
    );
  }
}

class _LeaderboardList extends ConsumerWidget {
  const _LeaderboardList();

  static String _fmt(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(currentThemeProvider);
    final board = ref.watch(leaderboardProvider);
    return board.when(
      loading: () =>
          Center(child: CircularProgressIndicator(color: theme.primary)),
      error: (_, __) => Text('Leaderboard unavailable right now',
          style: AppText.caption(theme)),
      data: (rows) {
        if (rows.isEmpty) {
          return Text('No one on the board yet — be the first!',
              style: AppText.caption(theme));
        }
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.s1),
                child: Row(
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text('${i + 1}',
                          style: AppText.rowSongTitle(theme).copyWith(
                              color: i < 3 ? theme.primary : theme.textMuted)),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rows[i].device.isEmpty
                                ? rows[i].nickname
                                : '${rows[i].nickname} · ${rows[i].device}',
                            style: AppText.rowSongTitle(theme),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Taste compatibility (3.0 #5): estimated from
                          // opt-in MinHash fingerprints, % only.
                          Text(
                              rows[i].isSelf
                                  ? '${rows[i].totalSongs} songs · you!'
                                  : rows[i].compat != null
                                      ? '${rows[i].totalSongs} songs · '
                                          '${rows[i].compat}% taste match'
                                      : '${rows[i].totalSongs} songs',
                              style: AppText.caption(theme)),
                        ],
                      ),
                    ),
                    Text(_fmt(rows[i].totalSeconds),
                        style: AppText.rowSongTitle(theme)
                            .copyWith(color: theme.primary)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
