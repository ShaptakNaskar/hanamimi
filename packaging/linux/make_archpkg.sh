#!/usr/bin/env bash
# Packages the Flutter Linux bundle as a pacman package
# (hanamimi-plus-<ver>-1-x86_64.pkg.tar.zst) installable with
# `sudo pacman -U`. Pure-bash packaging (fakeroot tar, no makepkg), so
# it runs on the Ubuntu CI runners too.
#
# Usage: packaging/linux/make_archpkg.sh <bundle-dir> <version> <outdir>
set -euo pipefail

BUNDLE="${1:?bundle dir (build/linux/x64/release/bundle)}"
VERSION="${2:?version (x.y.z)}"
OUTDIR="${3:?output directory}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PKGNAME=hanamimi-plus
PKGDIR="$WORK/pkg"

# --- payload ---------------------------------------------------------
install -dm755 "$PKGDIR/opt/$PKGNAME" "$PKGDIR/usr/bin" \
  "$PKGDIR/usr/share/applications" \
  "$PKGDIR/usr/share/icons/hicolor/512x512/apps" \
  "$PKGDIR/usr/share/licenses/$PKGNAME"
cp -r "$BUNDLE"/. "$PKGDIR/opt/$PKGNAME/"

# No bundled helpers: ffmpeg and yt-dlp come from the repos like a
# proper Arch package (see depend lines below).

ln -s "/opt/$PKGNAME/hanamimi" "$PKGDIR/usr/bin/hanamimi"
cp "$HERE/com.hanamimi.hanamimi.desktop" \
  "$PKGDIR/usr/share/applications/com.hanamimi.hanamimi.desktop"
cp "$ROOT/assets/icon/icon.png" \
  "$PKGDIR/usr/share/icons/hicolor/512x512/apps/com.hanamimi.hanamimi.png"

# --- metadata --------------------------------------------------------
SIZE=$(du -sb "$PKGDIR" | cut -f1)
cat > "$PKGDIR/.PKGINFO" <<EOF
pkgname = $PKGNAME
pkgbase = $PKGNAME
pkgver = $VERSION-1
pkgdesc = Kawaii music player - local library, YouTube & JioSaavn (Hanamimi+)
url = https://github.com/ShaptakNaskar/hanamimi
builddate = $(date +%s)
packager = Sappy <hanamimi@users.noreply.github.com>
size = $SIZE
arch = x86_64
license = GPL3
depend = gtk3
depend = ffmpeg
depend = yt-dlp
EOF

cat > "$PKGDIR/.MTREE.tmp" <<'EOF'
EOF
rm -f "$PKGDIR/.MTREE.tmp"
# .MTREE (pacman reads it for -Qkk verification; bsdtar generates it).
( cd "$PKGDIR" && LANG=C bsdtar -czf .MTREE --format=mtree \
    --options='!all,use-set,type,uid,gid,mode,time,size,md5,sha256,link' \
    .PKGINFO opt usr )

# --- package ---------------------------------------------------------
mkdir -p "$OUTDIR"
# Absolute path: the packaging subshell cd's into the staging dir,
# where a relative OUTDIR doesn't exist (CI: "No such file or
# directory" + "bsdtar: Write error").
OUT="$(cd "$OUTDIR" && pwd)/$PKGNAME-$VERSION-1-x86_64.pkg.tar.zst"
# stdout redirect, not -o: Ubuntu's zstd won't read stdin with -o and
# the broken pipe surfaced as a bare "bsdtar: Write error" on CI.
( cd "$PKGDIR" && LANG=C bsdtar -cf - .MTREE .PKGINFO opt usr \
    | zstd -19 -T0 -q > "$OUT" )
echo "done: $OUT"
echo "install with: sudo pacman -U $OUT"
