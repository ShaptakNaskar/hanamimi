# Hanamimi vs Hanamimi+ — which one?

Hanamimi ships in two editions. Same kawaii player, same themes, same
mascot, same real-audio visualizer — they differ only in **where the
music can come from**.

| | **Hanamimi** | **Hanamimi+** |
|---|:---:|:---:|
| Play your **local / on-device** music | ✅ | ✅ |
| Themes, mascot, FFT visualizer, crossfade | ✅ | ✅ |
| Synced & karaoke lyrics | ✅ | ✅ |
| Liked songs, playlists, folders, sleep timer | ✅ | ✅ |
| Resume last song, Nerd mode, pause-on-call | ✅ | ✅ |
| **Search & stream from YouTube** | — | ✅ |
| **Search & stream from JioSaavn** | — | ✅ |
| **Download online songs for offline** | — | ✅ |
| Self-updating extractor (embedded yt-dlp) | — | ✅ |
| In-app updates | — | ✅ |
| **License** | (standard) | **GPLv3** |
| **Where to get it** | Play Store *(planned)* | Sideload APK / Desktop *(GitHub Releases)* |

### In one line

- **Hanamimi** is the clean, **offline-only** player for the music
  already on your device. It's the edition headed for the Play Store.
- **Hanamimi+** is everything above **plus** online search, streaming
  and downloads from YouTube & JioSaavn (via an embedded, self-updating
  `yt-dlp`).

### Why are they separate?

Hanamimi+ links `yt-dlp` (GPLv3) and talks to unofficial endpoints, so
it can't go on the Play Store — it's distributed as a sideload APK and,
soon, a desktop app. The base **Hanamimi** stays policy-clean for the
store. Pick + if you want online music; pick base if you only play your
own files (or want the Play Store install).

> Both editions install **side by side** — `com.hanamimi.app` (base) and
> `com.hanamimi.app.plus` (+) don't conflict, so you can run both.

*Releases: <https://github.com/ShaptakNaskar/hanamimi/releases>*
