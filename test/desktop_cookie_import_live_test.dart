@TestOn('linux')
@Tags(['online'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hanamimi/platform/desktop/desktop_ytdlp.dart';
import 'package:hanamimi/reco/yt_session.dart';

/// Live check for the desktop browser-cookie import (M41). Exercises the
/// REAL yt-dlp invocation against a Firefox profile passed via
/// HANA_FF_PROFILE, then asserts the parsed header carries a signed-in
/// session. Skipped by default (needs a logged-in profile on the box);
/// run with:
///   HANA_FF_PROFILE=~/.config/mozilla/firefox/xxxx.default-release \
///     flutter test --run-skipped -t online test/desktop_cookie_import_live_test.dart
void main() {
  test('cookiesFromBrowser(firefox, profile) yields a signed-in session',
      () async {
    final profile = Platform.environment['HANA_FF_PROFILE'];
    if (profile == null || !Directory(profile).existsSync()) {
      markTestSkipped('set HANA_FF_PROFILE to a logged-in Firefox profile');
      return;
    }
    final cookie =
        await DesktopYtDlp.cookiesFromBrowser('firefox', profile: profile);
    // `flutter test` has no platform channels, so the app-support dir
    // (where the bundled binary lives) can't be resolved — that's a
    // harness limit, not a failure of this code. Skip rather than red.
    if (DesktopYtDlp.lastCookieError == 'yt-dlp is not available.') {
      markTestSkipped('no yt-dlp binary resolvable in the test harness');
      return;
    }
    expect(cookie, isNotNull,
        reason: 'extraction failed: ${DesktopYtDlp.lastCookieError}');
    expect(YtSession(cookie: cookie!).looksSignedIn, isTrue,
        reason: 'no SAPISID in the imported cookie header');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('cookieHeaderFromText parses a Netscape cookies.txt paste', () {
    const paste = '# Netscape HTTP Cookie File\n'
        '.youtube.com\tTRUE\t/\tTRUE\t0\tSAPISID\tabc123\n'
        '.youtube.com\tTRUE\t/\tTRUE\t0\tPREF\tf1=xyz\n';
    final header = DesktopYtDlp.cookieHeaderFromText(paste);
    expect(header, isNotNull);
    expect(YtSession(cookie: header!).looksSignedIn, isTrue);
  });

  test('cookieHeaderFromText accepts a raw Cookie header paste', () {
    const raw = 'SAPISID=abc123; __Secure-3PAPISID=abc123; PREF=f1=xyz';
    expect(DesktopYtDlp.cookieHeaderFromText(raw), isNotNull);
  });

  test('cookieHeaderFromText rejects junk with no session', () {
    expect(DesktopYtDlp.cookieHeaderFromText('hello world'), isNull);
    expect(DesktopYtDlp.cookieHeaderFromText(''), isNull);
  });
}
