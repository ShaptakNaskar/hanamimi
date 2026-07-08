#!/usr/bin/env bash
# Builds distro-native packages from the Flutter Linux bundle using fpm:
#   - .deb  (Debian / Ubuntu / Mint / Pop!_OS)
#   - .rpm  (Fedora / RHEL / openSUSE)
#
# Same staging tree as the pacman package (make_archpkg.sh): the app in
# /opt, a /usr/bin symlink, a .desktop entry and a hicolor icon. GTK is
# the only hard dependency; ffmpeg and yt-dlp self-fetch on first run
# (DesktopBinaries), so the package installs on a bare system and stays
# tiny — and, importantly, the .rpm still installs on stock Fedora,
# whose base repos don't carry ffmpeg (that lives in RPM Fusion).
#
# Usage: packaging/linux/make_fpm.sh <bundle-dir> <version> <outdir>
# Needs: fpm (+ rpmbuild for the .rpm target) — the CI installs both.
set -euo pipefail

BUNDLE="${1:?bundle dir (build/linux/x64/release/bundle)}"
VERSION="${2:?version (x.y.z)}"
OUTDIR="${3:?output directory}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

PKGNAME=hanamimi-plus

# --- staging tree ----------------------------------------------------
install -dm755 "$STAGE/opt/$PKGNAME" "$STAGE/usr/bin" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/icons/hicolor/512x512/apps"
cp -r "$BUNDLE"/. "$STAGE/opt/$PKGNAME/"
ln -s "/opt/$PKGNAME/hanamimi" "$STAGE/usr/bin/hanamimi"
cp "$HERE/com.hanamimi.hanamimi.desktop" \
  "$STAGE/usr/share/applications/com.hanamimi.hanamimi.desktop"
cp "$ROOT/assets/icon/icon.png" \
  "$STAGE/usr/share/icons/hicolor/512x512/apps/com.hanamimi.hanamimi.png"

mkdir -p "$OUTDIR"
OUT="$(cd "$OUTDIR" && pwd)"

common=(
  -s dir -C "$STAGE"
  --name "$PKGNAME"
  --version "$VERSION"
  --iteration 1
  --description "Kawaii music player - local library, YouTube & JioSaavn (Hanamimi+)"
  --url "https://github.com/ShaptakNaskar/hanamimi"
  --license "GPL3"
  --maintainer "Sappy <hanamimi@users.noreply.github.com>"
  --vendor "Sappy"
  --category "AudioVideo"
  --force
)

# --- .deb (Debian/Ubuntu package + arch names) -----------------------
fpm "${common[@]}" -t deb -a amd64 \
  --depends "libgtk-3-0" \
  --deb-recommends "ffmpeg" --deb-recommends "yt-dlp" \
  -p "$OUT/${PKGNAME}_${VERSION}-1_amd64.deb" .

# --- .rpm (Fedora/RHEL arch name; ffmpeg stays a weak dep) -----------
fpm "${common[@]}" -t rpm -a x86_64 \
  --depends "gtk3" \
  --rpm-tag "Recommends: ffmpeg" \
  -p "$OUT/${PKGNAME}-${VERSION}-1.x86_64.rpm" .

echo "done:"
ls -1 "$OUT"/${PKGNAME}_*.deb "$OUT"/${PKGNAME}-*.rpm
