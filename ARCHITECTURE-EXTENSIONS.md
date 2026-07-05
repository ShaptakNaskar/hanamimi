# Hanamimi (花耳) — SpotiFLAC Extension Host (feasibility + plan)

> Can Hanamimi become **compatible with the SpotiFLAC extension repo** so
> a user (who supplies their own repo link) can pull **lossless FLAC**
> from Amazon/Deezer/Qobuz/Tidal/SoundCloud/YT-Music? **Researched the
> real registry + a real extension package — verdict: technically very
> feasible.** This is the spec.
>
> **Status: research / planning. Not implemented.** Milestone **M32**,
> **plus-only, opt-in, ships no link.**

---

## 1. What the repo actually is (verified, not guessed)

Downloaded a live `registry.json` and unpacked a real extension.

**`registry.json`** — `{ version, updated_at, extensions: [ … ] }`. Each
entry: `id, name, display_name, version, description, download_url,
category (download|integration), tags, min_app_version`. Providers seen:
**amazon, deezer, qobuz-web, tidal-web, soundcloud, ytmusic, apple-music,
spotify-web, pandora** — several tagged `lossless`.

**An extension** (`download_url` → `soundcloud.spotiflac-ext`) is a
**ZIP** containing exactly two things:

- **`manifest.json`** (declarative):
  ```
  type: ["metadata_provider","download_provider"]
  minAppVersion, skipLyrics
  permissions: { network: [host allowlist…], storage: true, file: true }
  qualityOptions: [{ id:"mp3_128", label, description }]
  capabilities: { downloadFallbackTier, shareUrlTemplates, … }
  searchBehavior: { placeholder, filters:[tracks/albums/artists/playlists] }
  urlHandler: { patterns: ["soundcloud.com"] }
  settings: []          # where a provider asks for a token
  ```
- **`index.js`** (plain **synchronous ES5** JavaScript) that ends with:
  ```js
  registerExtension({
    initialize, cleanup,
    searchTracks, customSearch, getTrack, getAlbum, getArtist,
    getPlaylist, enrichTrack, handleUrl,
    checkAvailability, download, getDownloadUrl
  });
  ```

## 2. The host API the JS expects (the whole surface)

The `index.js` only touches the outside world through a few **injected
globals** — this is the entire contract we'd implement:

| Global | Used as | Notes |
|---|---|---|
| `log` | `log.info/debug/warn/error(...)` | trivial → our logger |
| `storage` | `storage.get(k)` / `storage.set(k,v)` | per-extension KV (string) |
| `utils` | `utils.randomUserAgent()` | small helper bag |
| `http` | `var r = http.get(url, {headers,…})` | **synchronous**; returns `{status, body, headers}` |
| `file` (permission) | used by `download` to write bytes | write to `outputPath` |

`download(trackID, quality, outputPath, onProgress)` → returns
`{success, error_message, error_type}` (or success + real format). The
host supplies `outputPath` + an `onProgress(fraction)` callback; the
extension fetches the stream (and, for DRM'd providers, **decrypts in the
JS**) and writes the file.

**Key implementation fact: `http.get` is synchronous** (`var r =
http.get(...)`, used inline). So the JS must run somewhere it can block —
i.e. a **background isolate**, with the host bridging `http.get` to a
blocking Dart HTTP call.

## 3. How Hanamimi becomes a compatible host

```
lib/online/extensions/
├── registry.dart          # fetch user's registry.json, list/install
├── ext_package.dart       # download .sflx ZIP → cache index.js+manifest
├── ext_host.dart          # flutter_js runtime + injected globals
│                          #   (log/storage/utils/http/file), allowlist
├── ext_provider.dart      # wraps a loaded extension as a MusicProvider
└── ext_download.dart      # checkAvailability + download → download mgr
```

- **JS engine:** [`flutter_js`](https://pub.dev/packages/flutter_js)
  (QuickJS on Android). ES5 + no DOM → runs as-is.
- **Isolate:** run each extension on a background isolate so the
  synchronous `http.get`/`file` host calls can block on Dart I/O without
  freezing the UI.
- **Host globals:** implement `log`, `storage` (namespaced per extension
  id, backed by sqflite/prefs), `utils.randomUserAgent`, and `http.get`
  (dio) — **enforcing `manifest.permissions.network`** (reject hosts not
  in the allowlist). Provide the `file` write used by `download`.
- **Mapping onto our world:** the registered methods slot into existing
  Hanamimi interfaces —
  - `searchTracks` / `customSearch` → a `MusicProvider.search`
  - `getPlaylist` / `handleUrl` → the **playlist importer** (this is why
    it lives near import): paste an Amazon/Tidal/Deezer link → import.
  - `getTrack` / `enrichTrack` → metadata + **ISRC** (great for our
    matcher).
  - `checkAvailability` + `download` → a `StreamResolver`/download-manager
    backend that writes the FLAC via the extension.
- **Reference:** SpotiFLAC-Mobile is **MIT + open** — read the exact host
  signatures, the sync-http option shape, and the `download` decryption
  contract straight from its source (MIT → our GPLv3 is fine).

## 4. Costs & risks (bounded, but real)

| Risk | Assessment |
|---|---|
| Exact host contract | Small surface (§2), but a **moving target** — `minAppVersion` per extension (Amazon 4.7.0). Target one host version; verify against the newest extensions. |
| Decryption | Confirm Deezer/Qobuz/Tidal decrypt **in-JS** (portable) vs. a native helper (must replicate, e.g. Blowfish). SoundCloud is a direct stream (easy). |
| Tokens | Qobuz/Tidal/Amazon/Apple use `manifest.settings` for the user's own token/subscription; surface those as extension settings. |
| Reliability | Community extensions rate-limit / region-lock / change; treat as best-effort with fallback to our normal sources. |
| App size | `flutter_js`/QuickJS adds a native lib (~a few MB). plus-only, acceptable. |
| **Legal** | It's a lossless ripper for paid services — the real constraint (§5). |

## 5. Legal guardrails (non-negotiable — as the user framed it)

- **plus-only, opt-in, OFF by default.**
- **Ship no registry link and no default provider.** The user must find
  and paste the repo URL themselves. Hanamimi is only a *compatible
  host* — it distributes neither the ripper extensions nor their
  endpoints. This is the shield.
- **Enforce each manifest's `network` allowlist** (an extension can only
  talk to its declared hosts).
- **Clear legal/consent notice** on enabling the feature and on adding a
  repo.
- Never on `main` (Play-Store edition).

## 5b. Licensing — MIT vs GPLv3 (can we legally do this?)

Two *separate* legal axes; don't conflate them.

**(a) The open-source license of the code we adapt.**
- **MIT** = permissive: use / modify / distribute (even in closed
  software), the only duty is to **keep the copyright + license notice**.
- **GPLv3** = copyleft: anything you distribute that *incorporates* GPLv3
  code becomes GPLv3, and you must **offer the source**.
- **MIT is GPL-compatible, one-way.** MIT code can be pulled **into** a
  GPLv3 project; the combined work is GPLv3, and you keep the MIT notice
  on the MIT-origin files. **So adapting SpotiFLAC-Mobile's MIT Dart into
  Hanamimi+ (GPLv3) is fine — no violation** — as long as we preserve
  their MIT notice on the adapted files. (The reverse — GPL into MIT —
  would be the problem; not our direction.)

**(b) The extensions in the repo (the `.sflx`/`index.js` files).**
- We **do not** copy or ship them — the **user** fetches them at runtime
  from a repo **they** supply. Hanamimi is a *host that runs* them, like a
  browser running a page's JS. A host is **not a derivative work** of the
  content it loads, so those extensions' licenses **don't bind our code**.
  The BYO-repo model keeps them out of our licensing entirely.

**(c) The thing that is NOT a software-license issue: copyright / ToS.**
Ripping lossless from Tidal/Qobuz/Deezer is a **copyright / terms-of-
service** matter, orthogonal to MIT/GPL. The open-source licensing is
clean; the *use* is what the §5 guardrails (opt-in, ship-no-link,
plus-only, consent notice) exist to distance us from.

**Bottom line:** licensing-wise we're clear — MIT→GPLv3 adaptation is
allowed (keep the notice), and we never redistribute the extensions. The
only real exposure is the ripping-use question, which the guardrails
address.

## 6. Milestone

- **M32 — Extension host**: `flutter_js` runtime + host globals
  (log/storage/utils/http/file, allowlist-enforced) on a background
  isolate; user-supplied `registry.json` install flow; extensions mapped
  to search / playlist-import / download; opt-in, plus-only, ships no
  link, legal notice. *Verify: with a user-provided repo, an extension
  loads, searches, imports a playlist, and downloads a real FLAC; disabled
  by default and absent from main.*

Phasing: **P1** metadata/search + playlist import (lower risk, no
download); **P2** the `download`/decrypt path (FLAC to disk).

Non-goals: bundling any repo/provider/credentials; a built-in extension
store; extensions on main.

---

*Document version: 0.1 — research/planning. Companion to
ARCHITECTURE-IMPORT.md §7f. Findings from unpacking a live registry +
`soundcloud.spotiflac-ext`. Last updated: July 2026.*
