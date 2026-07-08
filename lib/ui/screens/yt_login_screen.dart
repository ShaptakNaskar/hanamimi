import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/theme_provider.dart';
import '../../providers/yt_account_provider.dart';
import '../../reco/yt_session.dart';
import '../../theme/app_theme.dart';

/// Tier 3 cookie login (ARCHITECTURE-RECOMMENDATIONS.md §4). An in-app
/// WebView — NOT device Chrome: Chrome Custom Tabs never share cookies
/// with the host app, so only an embedded WebView can capture the
/// session. Google's "this browser may not be secure" block on WebView
/// logins is dodged with a desktop-Firefox user-agent (the standard
/// InnerTune/OuterTune workaround).
class YtLoginScreen extends ConsumerStatefulWidget {
  const YtLoginScreen({super.key});

  static Route<bool> route() =>
      MaterialPageRoute(builder: (_) => const YtLoginScreen());

  // A real desktop-browser UA so the Google login flow doesn't reject
  // the WebView as an "insecure browser".
  static const _ua =
      'Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0';

  @override
  ConsumerState<YtLoginScreen> createState() => _YtLoginScreenState();
}

class _YtLoginScreenState extends ConsumerState<YtLoginScreen> {
  final _cookieManager = CookieManager.instance();
  var _capturing = false;

  /// Once the user has landed back on music.youtube.com signed in, pull
  /// the cookie jar; SAPISID present ⇒ a usable session.
  Future<void> _tryCapture() async {
    if (_capturing) return;
    _capturing = true;
    try {
      final cookies = await _cookieManager.getCookies(
          url: WebUri('https://music.youtube.com'));
      final header =
          cookies.map((c) => '${c.name}=${c.value}').join('; ');
      if (YtSession(cookie: header).looksSignedIn) {
        await ref.read(ytAccountProvider.notifier).connect(header);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
    } catch (_) {}
    _capturing = false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(currentThemeProvider);
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.surface,
        title: Text('Sign in to YT Music',
            style: AppText.rowSongTitle(theme)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: AppText.caption(theme)),
          ),
        ],
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(
            url: WebUri(
                'https://accounts.google.com/ServiceLogin?service=youtube&continue=https://music.youtube.com/')),
        initialSettings: InAppWebViewSettings(
          userAgent: YtLoginScreen._ua,
          javaScriptEnabled: true,
        ),
        onLoadStop: (controller, url) {
          // Back on YT Music ⇒ likely signed in; check the jar.
          if (url != null && url.host.contains('music.youtube.com')) {
            _tryCapture();
          }
        },
      ),
    );
  }
}
