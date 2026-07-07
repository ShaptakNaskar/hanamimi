# Hanamimi+ — Windows test checklist (M31)

Everything the Linux build already passed, re-checked on Windows, plus
the Windows-only SMTC bits. Automated parts: run `.\test-smtc.ps1` in
the folder with `hanamimi.exe` (it synthesizes media keys **on the
box**, so Parsec not forwarding your real keys doesn't matter).

## 0. First launch

- [ ] `hanamimi.exe` opens; window titled "Hanamimi+ 花耳", min size enforced, remembered size after restart
- [ ] With music in `%USERPROFILE%\Music`: library populates (tags + album art may fill in on the SECOND launch if ffmpeg was still downloading — the app fetches ffmpeg/ffprobe + yt-dlp into `%APPDATA%\com.hanamimi\hanamimi\bin` on first run; check that folder)
- [ ] You → MORE → **Music folders**: default entry is `%USERPROFILE%\Music`; add/remove folder works, rescan follows

## 1. SMTC / media keys — `.\test-smtc.ps1`

- [ ] All script checks PASS (session registered, play/pause/next/prev via media keys)
- [ ] **Flyout**: press a volume key — the media overlay shows title/artist/**album art**
- [ ] Flyout buttons (pause/next/prev) control the app
- [ ] **Lock screen** (Win+L while playing): media controls present and working
- [ ] Progress bar in the flyout advances roughly with playback

## 2. Playback (parity with Linux)

- [ ] Local file plays; seek bar drags; space/←/→/Ctrl+←→ shortcuts work when focused
- [ ] Crossfade (You → SOUND) audibly blends two tracks
- [ ] Visualizer shows real bands (not a uniform pulse) within ~2s of play
- [ ] Wide window ≥1240px: three panes; sidebar playlist/folder click opens it in the middle
- [ ] `F` opens immersive view (art left, lyrics right), Esc leaves
- [ ] Uniform glow — no hard color split at pane borders

## 3. Online (Hanamimi+)

- [ ] Search a song → YouTube tab → plays (first play may take a few seconds while yt-dlp downloads itself; check `%APPDATA%\com.hanamimi\hanamimi\bin\yt-dlp.exe` appears)
- [ ] JioSaavn tab search + play
- [ ] Download a track (Downloads tab shows progress; file lands under `%APPDATA%\...\downloads`)
- [ ] You → ONLINE → "Update YouTube extractor" reports a version

## 4. Rough edges to note (expected/known)

- Adaptive theme needs a track with art playing
- ffprobe missing during the very first scan → titles fall back to
  file names until a rescan after the background ffmpeg fetch finishes
- Report anything that hard-crashes with the contents of any console
  window / Event Viewer entry
