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
  var _showAdvanced = false;
  final _profileCtrl = TextEditingController();
  final _cookieCtrl = TextEditingController();

  @override
  void dispose() {
    _profileCtrl.dispose();
    _cookieCtrl.dispose();
    super.dispose();
  }

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
    final profile = _profileCtrl.text.trim();
    final cookie = await YtDlpChannel.cookiesFromBrowser(
      browser,
      profile: profile.isEmpty ? null : profile,
    );
    if (!mounted) return;
    if (cookie == null || !YtSession(cookie: cookie).looksSignedIn) {
      setState(() {
        _busy = false;
        // yt-dlp's own reason is far more useful than a blank "no
        // session" (e.g. "could not find firefox cookies database").
        _error = YtDlpChannel.lastCookieError ??
            "No signed-in YT Music session found in $browser. "
                'Log in there first, or try another browser.';
      });
      return;
    }
    await ref.read(ytAccountProvider.notifier).connect(cookie);
    if (mounted) Navigator.of(context).pop();
  }

  /// Extension-paste escape hatch: parse a pasted cookies.txt (or raw
  /// Cookie header) and connect — works for any browser/fork, including
  /// ones yt-dlp can't read (Thorium, Zen, Snap/Flatpak sandboxes).
  Future<void> _usePastedCookies() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final cookie = YtDlpChannel.cookieHeaderFromText(_cookieCtrl.text);
    if (cookie == null || !YtSession(cookie: cookie).looksSignedIn) {
      setState(() {
        _busy = false;
        _error = "That didn't contain a signed-in session (no SAPISID). "
            'Export cookies.txt for youtube.com while signed in, then '
            'paste it here.';
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
              const SizedBox(height: Space.s1),
              // Escape hatch for when the buttons above can't find a
              // session: a browser whose profile lives somewhere the
              // default lookup misses (Firefox under ~/.config/mozilla,
              // Snap/Flatpak, a Chromium fork like Thorium/Zen).
              GestureDetector(
                onTap: _busy
                    ? null
                    : () => setState(() => _showAdvanced = !_showAdvanced),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                        _showAdvanced
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 18,
                        color: theme.primary),
                    Text("It didn't find my session",
                        style: AppText.caption(theme)
                            .copyWith(color: theme.primary)),
                  ],
                ),
              ),
              if (_showAdvanced) ...[
                const SizedBox(height: Space.s2),
                Text(
                  'Point it at your profile folder, then tap your browser '
                  'above:\n'
                  '• Firefox — open about:profiles, copy the "Root '
                  'Directory".\n'
                  '• Chrome / Chromium / forks — open chrome://version, '
                  'copy the "Profile Path".',
                  style: AppText.caption(theme)
                      .copyWith(color: theme.textMuted),
                ),
                const SizedBox(height: Space.s2),
                TextField(
                  controller: _profileCtrl,
                  enabled: !_busy,
                  style: AppText.caption(theme),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '/home/you/.config/mozilla/firefox/xxxx.default',
                    hintStyle: AppText.caption(theme)
                        .copyWith(color: theme.textMuted),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.sm)),
                  ),
                ),
                const SizedBox(height: Space.s3),
                Text(
                  'Or paste cookies.txt (from a "Get cookies.txt" '
                  'extension, exported for youtube.com while signed in) — '
                  'works with any browser:',
                  style: AppText.caption(theme)
                      .copyWith(color: theme.textMuted),
                ),
                const SizedBox(height: Space.s2),
                TextField(
                  controller: _cookieCtrl,
                  enabled: !_busy,
                  maxLines: 3,
                  style: AppText.caption(theme),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '# Netscape HTTP Cookie File …',
                    hintStyle: AppText.caption(theme)
                        .copyWith(color: theme.textMuted),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.sm)),
                  ),
                ),
                const SizedBox(height: Space.s2),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    onPressed: _busy ? null : _usePastedCookies,
                    child: Text('Use pasted cookies',
                        style: AppText.caption(theme)),
                  ),
                ),
              ],
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
