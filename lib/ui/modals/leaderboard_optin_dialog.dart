import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/leaderboard_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_tokens.dart';

/// Consent + nickname flow for the global leaderboard. Nothing is sent
/// until the user picks a nickname and taps Share. Sharing the device
/// make/model is a *separate* opt-in — name-only is fine, and if the
/// device is shared it shows on both the app and web leaderboards.
Future<void> showLeaderboardOptInDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _LeaderboardOptInDialog(),
  );
}

class _LeaderboardOptInDialog extends ConsumerStatefulWidget {
  const _LeaderboardOptInDialog();

  @override
  ConsumerState<_LeaderboardOptInDialog> createState() =>
      _LeaderboardOptInDialogState();
}

class _LeaderboardOptInDialogState
    extends ConsumerState<_LeaderboardOptInDialog> {
  final _nickname = TextEditingController();
  var _shareDevice = false;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await ref
        .read(leaderboardAccountProvider.notifier)
        .connect(_nickname.text, shareDevice: _shareDevice);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = "Couldn't share right now — check your connection";
      });
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
      content: const Text("You're on the leaderboard 🌸",
          style: TextStyle(fontFamily: 'Nunito')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    return AlertDialog(
      backgroundColor: theme.surface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
      title: Text('Join the leaderboard', style: AppText.rowSongTitle(theme)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share your listening totals (minutes and songs, per '
              'platform) so you show up on the global top-10. Your play '
              'history and library are never sent — only the counts.\n\n'
              'Please use a nickname, not your real name — it will be '
              'visible to everyone on the app and the website.',
              style: AppText.caption(theme),
            ),
            const SizedBox(height: Space.s3),
            TextField(
              controller: _nickname,
              autofocus: true,
              maxLength: 24,
              onChanged: (_) => setState(() {}),
              style: AppText.body(theme),
              decoration: InputDecoration(
                labelText: 'Nickname',
                labelStyle: AppText.caption(theme),
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _shareDevice,
              onChanged: (v) => setState(() => _shareDevice = v),
              title: Text('Also share my device',
                  style: AppText.rowSongTitle(theme)),
              subtitle: Text(
                  'Optional — shows your phone/PC make & model next to '
                  'your name on both leaderboards',
                  style: AppText.caption(theme)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: AppText.rowSongTitle(theme)
                  .copyWith(color: theme.textMuted)),
        ),
        TextButton(
          onPressed:
              _busy || _nickname.text.trim().isEmpty ? null : _share,
          child: _busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: theme.primary))
              : Text('Share',
                  style: AppText.rowSongTitle(theme)
                      .copyWith(color: theme.primary)),
        ),
      ],
    );
  }
}
