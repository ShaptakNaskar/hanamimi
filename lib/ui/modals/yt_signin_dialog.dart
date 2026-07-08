import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../online/ytdlp_channel.dart';
import '../../providers/theme_provider.dart';
import '../../providers/yt_account_provider.dart';
import '../../reco/yt_session.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_tokens.dart';
import '../screens/yt_login_screen.dart';

/// Tier 3 consent (ARCHITECTURE-RECOMMENDATIONS.md §4). States the deal
/// plainly — "Google will know everything you play here, that's the
/// point" — and recommends a burner account. Android continues into the
/// cookie-login WebView; desktop imports cookies from an installed
/// browser via yt-dlp (Firefox preferred).
Future<void> showYtSignInDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _YtSignInDialog(),
  );
}

class _YtSignInDialog extends ConsumerStatefulWidget {
  const _YtSignInDialog();

  @override
  ConsumerState<_YtSignInDialog> createState() => _YtSignInDialogState();
}

class _YtSignInDialogState extends ConsumerState<_YtSignInDialog> {
  var _busy = false;
  String? _error;

  Future<void> _androidLogin() async {
    final ok = await Navigator.of(context).push(YtLoginScreen.route());
    if (!mounted) return;
    if (ok == true) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = 'Sign-in cancelled or no session captured');
    }
  }

  Future<void> _desktopImport(String browser) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final cookie = await YtDlpChannel.cookiesFromBrowser(browser);
    if (!mounted) return;
    if (cookie == null || !YtSession(cookie: cookie).looksSignedIn) {
      setState(() {
        _busy = false;
        _error = "No signed-in YT Music session found in $browser. "
            'Log in there first, or try another browser.';
      });
      return;
    }
    await ref.read(ytAccountProvider.notifier).connect(cookie);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    return AlertDialog(
      backgroundColor: theme.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg)),
      title: Text('Sign in to YT Music', style: AppText.rowSongTitle(theme)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This connects your own YouTube Music account so Home can '
              'show your personalized picks — Quick Picks, mixes, your '
              'mixes-for-you.\n\n'
              'Google will see that this is you. By default Hanamimi '
              'only *reads* your feed — playback still goes through the '
              'anonymous path, so nothing you play here is added to your '
              'history unless you turn that on later.\n\n'
              'Because this uses your real account with an unofficial '
              'API, a throwaway / secondary Google account is the safe '
              'choice.',
              style: AppText.caption(theme),
            ),
            if (_error != null) ...[
              const SizedBox(height: Space.s3),
              Text(_error!,
                  style: AppText.caption(theme)
                      .copyWith(color: theme.accent)),
            ],
            if (!Platform.isAndroid) ...[
              const SizedBox(height: Space.s3),
              Text('Import your session from a browser you’re logged in on:',
                  style: AppText.caption(theme)),
              const SizedBox(height: Space.s2),
              Wrap(
                spacing: Space.s2,
                children: [
                  for (final b in const ['firefox', 'chrome', 'chromium',
                    'brave', 'edge'])
                    OutlinedButton(
                      onPressed: _busy ? null : () => _desktopImport(b),
                      child: Text(b[0].toUpperCase() + b.substring(1),
                          style: AppText.caption(theme)),
                    ),
                ],
              ),
              const SizedBox(height: Space.s1),
              Text('Firefox works most reliably.',
                  style: AppText.caption(theme)
                      .copyWith(color: theme.textMuted)),
            ],
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
        if (Platform.isAndroid)
          TextButton(
            onPressed: _busy ? null : _androidLogin,
            child: Text('Continue',
                style: AppText.rowSongTitle(theme)
                    .copyWith(color: theme.primary)),
          )
        else if (_busy)
          Padding(
            padding: const EdgeInsets.all(Space.s2),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: theme.primary),
            ),
          ),
      ],
    );
  }
}
