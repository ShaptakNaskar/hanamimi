# iOS implementation checkpoint

Implemented on `plus` from the committed 3.2 baseline after saving the Living Music work in the named `pre-ios` stash. The current version is 3.3.0. The `ios-build` workflow now builds an unsigned IPA on a GitHub-hosted Mac; native acceptance and the `main` port remain pending.

## Provider audit

- JioSaavn is our own Dart HTTPS/DES implementation, not an Android plugin. It has no native iOS dependency. CDN availability and AAC playback still need a device smoke test.
- [youtube_explode_dart 3.1.0](https://pub.dev/packages/youtube_explode_dart/versions/3.1.0) supports iOS. The iOS resolver restricts its audio choices to MP4/AAC instead of WebM/Opus.
- Our yt-dlp implementation embeds an Android library or launches a desktop subprocess. Neither is used on iOS. The Dart resolver remains available; extractor updates/browser-cookie extraction are unavailable on iOS. YouTube extraction remains best effort and can be throttled or rejected upstream.
- [just_audio](https://pub.dev/packages/just_audio), audio_service and audio_session provide mobile playback, interruptions and lock-screen controls. iOS explicitly takes that path instead of initializing libmpv, a desktop window or desktop SQLite.
- file_selector_ios's pinned implementation uses the document picker's import mode (owned temporary copy). We stream that copy into the managed library; no external provider URL is persisted.

## Imports

You → Import music, or the empty Library action:

1. Import from Files copies selected audio into Documents/Music.
2. Receive over Wi-Fi binds only the iOS Wi-Fi interface (`en0`, IPv4), shows a temporary capability link, and serves a self-contained browser uploader. Copy the entire link, including its fragment. Select up to 100 files; the browser uploads sequentially with progress and cancellation.
3. Files/Finder sharing exposes Documents. Place audio in Music and rescan to validate and adopt it.

Limits: MP3, AAC/M4A, FLAC, WAV and AIFF candidates, native AVFoundation validation, 2 GiB per upload, bounded streaming, no archives/resume. Format support is conditional on Apple's decoder and has not yet been measured on a device. The first version has file selection rather than a custom drag/drop target. Receiving lasts at most 30 minutes, requires the import sheet to remain open, prevents auto-lock, and stops on backgrounding, sheet close or detected address changes. A fresh start requires a fresh link. HTTP is unencrypted: use trusted Wi-Fi. IPv6-only networks, hotspot interface variants, Bonjour and TLS are deferred.

A SHA-256 filename prefix identifies a recording across retries, renames and sandbox relocation; different content with the same filename is retained separately. Original filenames remain readable after the prefix. Completed files move atomically from private staging and are recovered by rescanning if indexing was interrupted. No partial file enters the library. Missing iOS recordings keep their DB relationships; replay fails through the existing unreadable-file handling until the recording is restored. Metadata/artwork come from AVFoundation. The database, credentials and staging remain outside the exposed Documents directory. Actual music is durable user data; keep a separate copy before deleting/re-signing the app.

Native PCM decode writes a temporary stereo 44.1 kHz float file, then reuses the existing worker FFT, cache format and Slow Dance analysis. The native decode limit is 2 GiB of PCM, and temporary disk space is required. Cancellation and next-launch cleanup remove incomplete PCM/staging; cache hits avoid decoding. This is a deliberate first implementation; streaming native PCM is the upgrade path if device disk/latency measurements require it. No microphone permission is used.

## Next: Mac build and acceptance

The runner uses bundle ID `com.hanamimi.app.plus`, iOS 15+, CocoaPods and Swift, with background audio and Files/Finder sharing configured. Signing team and credentials are deliberately unset. It retains the legacy Flutter AppDelegate lifecycle to avoid requiring Flutter 3.41's implicit-engine API.

On the authorized Mac: install the agreed Flutter SDK and CocoaPods, run `flutter pub get`, then `cd ios && pod install`, and compile with `flutter build ios --release --no-codesign`. Configure signing before generating a device-installable IPA. [Flutter's iOS build documentation](https://docs.flutter.dev/deployment/ios) requires macOS/Xcode. An unsigned `.app` zipped as an IPA is not proof of installability.

No Xcode/Swift typecheck, signed device install, provider playback, LAN reachability, background/lock-screen audio, codec/FFT parity, Bluetooth, file protection or upgrade/re-sign preservation has been verified here. These are acceptance work for the Mac/device stage, not completed V4-15 gates. The existing release workflow is untouched; iOS builds are separate Actions artifacts.

Linux regression verification uses a separately installed preview and isolated profile because the stashed 4.0 application owns a newer DB schema. Never launch this 3.2-based checkpoint against that 4.0 profile. Restore the named stash only after reconciling the overlapping audio/library/UI edits.

## Local verification (10 November 2026)

103 Flutter tests passed; 3 online tests skipped. The analyzer reports the same 9 pre-existing diagnostics. Linux release built and the parallel `hanamimi-ios-preview 3.2.0.ios1-1` package was installed and launched under an isolated profile. A Linux debug launch and hot reload succeeded. The existing gamepad plugin emits a platform-thread warning under the debug harness; no new Dart exception was observed. The regular `hanamimi-plus 4.0.0.22-1` install was preserved. No AIN065 was attached, so Android installation was skipped.

These checks used the installed Flutter 3.47.4/Dart 3.13.3. There are no new dependencies; the committed dependency lock is preserved. Compatibility with CI's older pinned Flutter 3.29.3 still needs checking on the Mac build path; the local build is not evidence of that compatibility. No Swift compiler/Xcode or iOS device is available here. This original checkpoint preceded the 3.3.0 version bump and Mac CI workflow. No push, tag or release was performed.

## Unsigned IPA workflow (3.3.0)

`.github/workflows/ios-build.yml` runs on relevant pushes to `plus` and supports manual **Run workflow** dispatch. It uses `macos-15`, Xcode 16.4 and the existing CI pin of Flutter 3.29.3. It resolves packages, runs Flutter tests, builds the physical-device release app with `--no-codesign`, and packages `Payload/Runner.app` into an IPA. The iOS build number is this workflow's run number, independent of Android release numbering. No Apple certificates, provisioning profiles or signing secrets are required by CI.

Download the `hanamimi-plus-3.3.0-ios-unsigned-<run>` artifact from the successful workflow run and extract GitHub's artifact ZIP to get `hanamimi-plus-3.3.0-unsigned.ipa`. Import that IPA into your external signing/sideloading tool (for example, AltStore or Sideloadly), which must sign the app and its embedded frameworks with a valid identity/profile before installation. The raw unsigned IPA cannot be installed directly. Account limits, provisioning renewal and device compatibility still apply; app data preservation must be checked before replacing an existing sideload.

Artifacts are retained for 14 days. The workflow has read-only repository permissions and does not create tags or publish a GitHub Release. A successful Actions run establishes native compilation and IPA packaging; actual signing/sideloading still requires a device test.

The 3.3.0 workflow passed actionlint and a packaging self-check for version extraction, IPA layout, ZIP integrity and symlink preservation. The 3.3.0 Linux preview was rebuilt and installed alongside the existing 4.0 host package using its separate profile.

The first Mac run passed its Flutter tests (89 passed, 2 skipped) but failed native compilation in screen_brightness_ios 2.1.4, which uses Flutter scene-delegate APIs absent from Flutter 3.29.3. The iOS implementation is pinned to 2.1.2 through dependency_overrides; the parent package and other platforms retain their existing versions. Native compilation must be rerun to validate the fix.
