# iOS implementation checkpoint

Implemented on `plus` from the committed 3.2 baseline after saving the Living Music work in the named `pre-ios` stash. The current version is 3.4.0. The release workflow now builds and attaches an unsigned IPA on a GitHub-hosted Mac; native acceptance and the `main` port remain pending.

## Provider audit

- JioSaavn is our own Dart HTTPS/DES implementation, not an Android plugin. It has no native iOS dependency. CDN availability and AAC playback still need a device smoke test.
- [youtube_explode_dart 3.1.0](https://pub.dev/packages/youtube_explode_dart/versions/3.1.0) supports iOS. The iOS resolver restricts its audio choices to MP4/AAC instead of WebM/Opus.
- Our yt-dlp implementation embeds an Android library or launches a desktop subprocess. Neither is used on iOS. The Dart resolver remains available; extractor updates/browser-cookie extraction are unavailable on iOS. YouTube extraction remains best effort and can be throttled or rejected upstream.
- [just_audio](https://pub.dev/packages/just_audio), audio_service and audio_session provide mobile playback, interruptions and lock-screen controls. iOS explicitly takes that path instead of initializing libmpv, a desktop window or desktop SQLite.
- file_selector_ios's pinned implementation uses the document picker's import mode (owned temporary copy). We stream that copy into the managed library; no external provider URL is persisted.

## Imports

You → Import music, or the empty Library action:

1. Import from Files copies selected audio into Documents/Music.
2. Receive over Wi-Fi binds only the iOS Wi-Fi interface (`en0`, IPv4), shows a plain local address such as `192.168.1.20:54321`, and serves a self-contained browser uploader. Open that address directly. The browser manages the upload session using an HttpOnly, SameSite=Strict cookie; no token appears in the address or JavaScript. Select up to 100 files; the browser uploads sequentially with progress and cancellation.
3. Files/Finder sharing exposes Documents. Place audio in Music and rescan to validate and adopt it.

Limits: MP3, AAC/M4A, FLAC, WAV and AIFF candidates, native AVFoundation validation, 2 GiB per upload, bounded streaming, no archives/resume. Format support is conditional on Apple's decoder and has not yet been measured on a device. The first version has file selection rather than a custom drag/drop target. Receiving lasts at most 30 minutes, requires the import sheet to remain open, prevents auto-lock, and stops on backgrounding, sheet close or detected address changes. Restarting receiving invalidates the previous browser session; reopen the displayed address. HTTP is unencrypted: use trusted Wi-Fi. IPv6-only networks, hotspot interface variants, Bonjour and TLS are deferred.

A SHA-256 filename prefix identifies a recording across retries, renames and sandbox relocation; different content with the same filename is retained separately. Original filenames remain readable after the prefix. Completed files move atomically from private staging and are recovered by rescanning if indexing was interrupted. No partial file enters the library. Missing iOS recordings keep their DB relationships; replay fails through the existing unreadable-file handling until the recording is restored. Metadata/artwork come from AVFoundation. The database, credentials and staging remain outside the exposed Documents directory. Actual music is durable user data; keep a separate copy before deleting/re-signing the app.

Native PCM decode writes a temporary stereo 44.1 kHz float file, then reuses the existing worker FFT, cache format and Slow Dance analysis. The native decode limit is 2 GiB of PCM, and temporary disk space is required. Cancellation and next-launch cleanup remove incomplete PCM/staging; cache hits avoid decoding. This is a deliberate first implementation; streaming native PCM is the upgrade path if device disk/latency measurements require it. No microphone permission is used.

## Next: Mac build and acceptance

The runner uses bundle ID `com.hanamimi.app.plus`, iOS 15+, CocoaPods and Swift, with background audio and Files/Finder sharing configured. Signing team and credentials are deliberately unset. It retains the legacy Flutter AppDelegate lifecycle to avoid requiring Flutter 3.41's implicit-engine API.

On the authorized Mac: install the agreed Flutter SDK and CocoaPods, run `flutter pub get`, then `cd ios && pod install`, and compile with `flutter build ios --release --no-codesign`. Configure signing before generating a device-installable IPA. [Flutter's iOS build documentation](https://docs.flutter.dev/deployment/ios) requires macOS/Xcode. An unsigned `.app` zipped as an IPA is not proof of installability.

The 3.3.0 runner compiled successfully with Xcode 16.4 and Flutter 3.29.3 in Actions run 42783220267. Signed device install, provider playback, LAN reachability, background/lock-screen audio, codec/FFT parity, Bluetooth, file protection and upgrade/re-sign preservation still require device acceptance. V4-15 is not complete.

Linux regression verification uses a separately installed preview and isolated profile because the stashed 4.0 application owns a newer DB schema. Never launch this 3.2-based checkpoint against that 4.0 profile. Restore the named stash only after reconciling the overlapping audio/library/UI edits.

## Local verification (10 November 2026)

103 Flutter tests passed; 3 online tests skipped. The analyzer reports the same 9 pre-existing diagnostics. Linux release built and the parallel `hanamimi-ios-preview 3.2.0.ios1-1` package was installed and launched under an isolated profile. A Linux debug launch and hot reload succeeded. The existing gamepad plugin emits a platform-thread warning under the debug harness; no new Dart exception was observed. The regular `hanamimi-plus 4.0.0.22-1` install was preserved. No AIN065 was attached, so Android installation was skipped.

These checks used the installed Flutter 3.47.4/Dart 3.13.3. There are no new dependencies; the committed dependency lock is preserved. Compatibility with CI's older pinned Flutter 3.29.3 still needs checking on the Mac build path; the local build is not evidence of that compatibility. No Swift compiler/Xcode or iOS device is available here. This original checkpoint preceded the 3.3.0 version bump and Mac CI workflow. No push, tag or release was performed.

## Unsigned IPA releases (3.4.0)

Following SpeedoME's release pattern, `release.yml` calls `ios-build.yml` after creating the plus draft release. The Mac job receives the exact release version, build number and tag, runs tests, builds the unsigned physical-device app, packages `Payload/Runner.app` and uploads `hanamimi-plus-<version>-unsigned.ipa` directly to that draft release. Plus publication waits for Android, Windows, Linux and iOS; it also checks that the expected `.ipa` asset exists before making the release public. The iOS job no longer starts a duplicate independent build on every push.

Download the `.ipa` directly from **GitHub Releases → Assets**. It still needs external signing before sideloading. CI uses no Apple certificates or provisioning profiles. The matching IPA remains available as an Actions artifact for 14 days; manual **Run workflow** builds produce an artifact without publishing a release. A manual build uses the pubspec version and workflow run number.

The reusable Mac job retains `macos-15`, Xcode 16.4 and Flutter 3.29.3. Screen brightness's iOS implementation stays at 2.1.2 and device_info_plus at 12.3.0 to match that toolchain. Account limits, provisioning renewal and device compatibility still apply; check data preservation before replacing an existing sideload.

The 3.3.0 workflow passed actionlint and a packaging self-check for version extraction, IPA layout, ZIP integrity and symlink preservation. The 3.3.0 Linux preview was rebuilt and installed alongside the existing 4.0 host package using its separate profile.

The first Mac run passed its Flutter tests (89 passed, 2 skipped) but failed native compilation in screen_brightness_ios 2.1.4, which uses Flutter scene-delegate APIs absent from Flutter 3.29.3. The iOS implementation is pinned to 2.1.2 through dependency_overrides; the parent package and other platforms retain their existing versions. Native compilation must be rerun to validate the fix.

The second Mac run cleared the brightness compiler errors and again passed Flutter tests, then failed in device_info_plus 12.4.0: its isiOSAppOnVision call requires the iOS 26.1 SDK, unavailable in Xcode 16.4. Pin device_info_plus to 12.3.0 to retain the selected Xcode/Flutter toolchain; the app does not use the removed visionOS field. Local analysis remains at the same nine baseline diagnostics. Native compilation must be rerun for acceptance.
