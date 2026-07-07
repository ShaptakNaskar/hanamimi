#!/usr/bin/env bash
# Packages the Flutter Linux bundle into a self-contained AppImage
# (ARCHITECTURE-DESKTOP.md §7): app + libmpv (already bundled by
# media_kit) + standalone yt-dlp + static ffmpeg/ffprobe, so the player,
# online streaming, downloads and the visualizer work with zero system
# dependencies beyond GTK.
#
# Usage: packaging/linux/make_appimage.sh <bundle-dir> <output.AppImage>
# Needs: curl, appimagetool (fetched automatically when missing).
set -euo pipefail

BUNDLE="${1:?bundle dir (build/linux/x64/release/bundle)}"
OUT="${2:?output .AppImage path}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

APPDIR="$WORK/AppDir"
mkdir -p "$APPDIR/usr/bin"
cp -r "$BUNDLE"/. "$APPDIR/usr/bin/"

# Desktop integration. Named after the GTK application id
# (com.hanamimi.hanamimi) so Wayland compositors match app-id →
# .desktop → icon; MPRIS advertises the same DesktopEntry.
cp "$HERE/com.hanamimi.hanamimi.desktop" "$APPDIR/com.hanamimi.hanamimi.desktop"
cp "$ROOT/assets/icon/icon.png" "$APPDIR/com.hanamimi.hanamimi.png"
ln -sf usr/bin/hanamimi "$APPDIR/AppRun"

# Slim bundle: yt-dlp and ffmpeg are NOT packed in — the app
# self-fetches both on first run (DesktopBinaries), which keeps the
# AppImage under Telegram's 50 MB bot upload cap.

# appimagetool (continuous build, x86_64).
TOOL="$WORK/appimagetool"
if command -v appimagetool >/dev/null 2>&1; then
  TOOL="$(command -v appimagetool)"
else
  echo "· fetching appimagetool"
  curl -fsSL -o "$TOOL" \
    https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  chmod +x "$TOOL"
fi

echo "· building $OUT"
ARCH=x86_64 "$TOOL" --no-appstream "$APPDIR" "$OUT"
echo "done: $OUT"
