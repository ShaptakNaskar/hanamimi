# Hanamimi 花耳

> A kawaii, offline-first music player for Android with a beagle mascot that vibes to your music.
> Built with Flutter. Named after a real dog. 🐶

Hanamimi plays the music already on your phone — no accounts, no streaming, no ads — and wraps it in a soft, living interface: mood themes, a real FFT visualizer, word-synced karaoke lyrics, a Home page that learns what you like, and a little beagle who bops her head to the beat.

> Want online streaming and desktop apps? See **Hanamimi+** (the `plus` branch) — [docs/EDITIONS.md](docs/EDITIONS.md) explains the difference. Base Hanamimi stays fully local and Play-Store-safe.

## Screenshots

| Home (recommendations) | Now Playing | Adaptive theme |
|:---:|:---:|:---:|
| ![Home](docs/screenshots/home.png) | ![Now Playing](docs/screenshots/now-playing.png) | ![Adaptive](docs/screenshots/adaptive.png) |

| Karaoke lyrics | Instrumental breaks | Folders | You | Sleep timer |
|:---:|:---:|:---:|:---:|:---:|
| ![Lyrics](docs/screenshots/lyrics-karaoke.png) | ![Interlude](docs/screenshots/lyrics-interlude.png) | ![Folders](docs/screenshots/folders.png) | ![You](docs/screenshots/you-screen.png) | ![Sleep timer](docs/screenshots/sleep-timer.png) |

## Features

**Home & recommendations** *(new in 2.0)*
- A **Home** start page with a **Jump back in** shelf (your recents) and a **For you** shelf of on-device picks
- Everything is computed **on the device**, airplane-mode safe — recency-weighted plays, a co-play/Markov matrix ("after this, you usually play that"), a skip signal, and audio-feature similarity extracted for free during the visualizer decode
- **Song radio** (seed any track into a station) and **smart shuffle** (weighted toward your favorites)
- No accounts, no network, nothing uploaded — the whole thing runs from your own library

**Player**
- Local playback via MediaStore scan — songs, albums, **folders** (VLC-style directory browsing), playlists
- Background audio with lock-screen / notification controls and media buttons
- True two-player **crossfade** (2–12 s, smoothstep ramp), shuffle / repeat / repeat-one
- Queue sheet with tap-to-jump, swipe a track right to queue it, left to add to a playlist
- Playlists with pastel or custom covers: play all, reorder, swipe-left to remove, delete with confirm
- Library-wide search across songs, albums, folders and playlists
- **Excluded folders** — hide any directory from the scan (You → More → Excluded folders)
- Registers as an audio handler — "open with Hanamimi" works from file managers and other apps
- Sleep timer with moon-phase presets; **caffeine** toggle to keep the screen awake
- **Controller + touch friendly** — finger/stylus drag-scroll and gamepad navigation for handhelds

**Lyrics (the fun part)**
- **Word-by-word karaoke highlighting** in the style of [beautiful-lyrics](https://github.com/surfbryce/beautiful-lyrics) — per-word glow, scale and lift, feathered fill edge, smooth centered scrolling
- Three sources with quality priority (**word-synced > line-synced > plain**):
  1. Lyrics embedded in the audio file itself (ID3 `USLT`/`TXXX`, FLAC comments — enhanced LRC word tags supported)
  2. Musixmatch richsync (true word timings)
  3. [LRCLIB](https://lrclib.net) (line-synced)
- Filling dot indicators during intros and instrumental breaks
- Tap any line to seek there; per-track sync offset (±0.5 s nudges) for files that are a different master than the timing source
- Source picker on the quality badge — force embedded / Musixmatch / LRCLIB per track; sources are probed on open, and ones with nothing for the song are greyed out
- Share a lyric snippet as a card

**Visualizer & mascot**
- Real FFT computed from the decoded audio itself (60 fps, 12 log-spaced bands, per-track disk cache, **no microphone permission**), styled per theme: pastel bars, radial starburst, waveform — with a sensitivity control for quiet songs
- Hanamimi the beagle is drawn and animated entirely in code (`CustomPainter`): blink scheduler, amplitude-driven head bop with lagging-ear physics, head-tilt on track change, snoring with floating z's
- A flock of optional **buddies**, each individually toggleable — parrot, cat, duck, fireflies (dark themes) — anchored to furniture around the UI
- Accessories unlocked by listen time (bow → headphones → flower → crown)

**Design**
- Four themes: **Cherry Blossom 🌸**, **Adaptive Light**, **Starry Night 🌙**, **Adaptive Dark** — the Adaptive palettes are drawn live from the current album art (Material You–style) and follow the art's brightness; first launch follows your system light/dark setting
- Sakura petals / drifting stars, caterpillar seek bar with eyes, heart-burst likes
- Nunito everywhere, nothing has a hard corner, reduce-motion aware

## Building

Requirements: Flutter 3.29+, Android SDK (minSdk 24), a device or emulator.

```bash
# debug
flutter pub get
flutter run

# signed release → install → launch (expects android/key.properties + keystore)
./build-hanamimi.sh

# reinstall the last release build without rebuilding
./build-hanamimi.sh --install
```

Release signing reads `android/key.properties` (gitignored):

```properties
storePassword=…
keyPassword=…
keyAlias=…
storeFile=../keystore/your-release.jks
```

The launcher icon is rendered from the mascot painter itself:
`flutter test test/tools/generate_icon_test.dart && dart run flutter_launcher_icons`.

## Architecture

```
lib/
├── audio/        QueueManager (two-player crossfade), audio_service handler, sleep timer
├── reco/         on-device recommender — co-play + skip logging, audio-feature
│                 vectors, blended scoring, song radio
├── library/      sqflite repository, Kotlin MediaStore scanner channel
├── lyrics/       LRC + enhanced-LRC parser, richsync parser, embedded-tag readers,
│                 Musixmatch/LRCLIB providers, quality-priority resolution
├── visualizer/   FFT band processor + per-theme painters
├── platform/     gamepad input
├── providers/    Riverpod state (audio, library, reco, lyrics, theme, mascot, …)
├── theme/        design tokens + the HanamimiTheme palettes (incl. adaptive)
└── ui/           screens (Home, Library, Now Playing, You), mascot, lyrics sheet, modals

android/…/app/    MainActivity + MediaStoreChannel.kt + FftExtractorChannel.kt
```

## Notes

- **Android only.** The visualizer decodes each track itself (`MediaExtractor`/`MediaCodec` → FFT at 60 fps, disk-cached per track) — **no microphone / RECORD_AUDIO permission**, and it stays accurate regardless of the output mix.
- Recommendations are computed entirely on-device from your own listening — nothing is ever uploaded.
- Musixmatch is accessed through its unofficial desktop-app API, best-effort with graceful fallback — intended for personal use.
- Word timings come keyed to specific releases; local files that are a different master can drift, which is what the per-track sync offset is for.

## Credits

- [beautiful-lyrics](https://github.com/surfbryce/beautiful-lyrics) and [spicy-lyrics](https://github.com/Spikerko/spicy-lyrics) — the karaoke animation language this app's lyrics view is modeled on
- [LRCLIB](https://lrclib.net) — free, keyless synced lyrics
- **oneko** — the pointer-chasing cat (she chases your taps and naps by the logo), ported from [oneko.js](https://github.com/adryd325/oneko.js) by **adryd** (reviving the classic X11 `neko`); its sprite sheet is bundled with the app. Brought over as an in-app buddy after the [Vencord oneko plugin](https://vencord.dev/plugins/oneko) by **V**. Both are GPLv3.
- **Claude Fable & Opus** — the dream team on debugging duty, for helping bring this whole thing to life 🤝
- Hanamimi — the real beagle 🐾

## License

Hanamimi is free software, licensed under the [GNU General Public License v3](LICENSE). It bundles **oneko** (GPLv3, see Credits), so the app as a whole is distributed under GPLv3.
