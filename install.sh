#!/usr/bin/env bash
#
# YouTube 3D Vision - one-command installer (macOS / Linux)
#
# Does everything: downloads the add-on, unpacks it, gets a browser that can
# load it automatically, and opens YouTube with 3D already switched on.
#
# Why its own browser? Chrome removed the ability to auto-load an unpacked
# add-on in version 137 (a security change), so this installs "Chrome for
# Testing", which is the same browser but keeps that ability. It is a separate
# copy - your normal Chrome is not touched.
#
# Usage:  bash install.sh
# Optional overrides (for testing):  YT3D_BASE, YT3D_DIR
#
set -euo pipefail

BASE="${YT3D_BASE:-https://pj9811193-create.github.io/my-files}"
DEST="${YT3D_DIR:-$HOME/YouTube3DVision}"
BUILD="9"                      # matches the published archive build stamp
CFT_VERSION="154.0.8037.92"

say() { printf '%s\n' "$*"; }
die() { printf '%s\n' "✗ $*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin) OS="mac" ;;
  Linux)  OS="linux" ;;
  *) die "This installer supports macOS and Linux. On Windows use install.bat." ;;
esac
case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  *)             ARCH="x64" ;;
esac

command -v curl  >/dev/null 2>&1 || die "curl is required (it ships with macOS and most Linux systems)."
command -v unzip >/dev/null 2>&1 || die "unzip is required (it ships with macOS and most Linux systems)."

mkdir -p "$DEST"
cd "$DEST"

# ---------------------------------------------------------------- 1. download
say "• Downloading the 3D add-on…"
tmp="$DEST/.download"
rm -rf "$tmp"; mkdir -p "$tmp"
i=0
while : ; do
  # (a missing part is how we detect the end of the list - keep it quiet)
  if ! curl -fsSL "$BASE/youtube-3d-vision.zip.part$i?v=$BUILD" -o "$tmp/part$i" 2>/dev/null; then break; fi
  i=$((i + 1))
done
[ "$i" -gt 0 ] || die "Could not download the add-on from $BASE (check your internet connection)."
: > "$DEST/yt3d.zip"
for ((n = 0; n < i; n++)); do cat "$tmp/part$n" >> "$DEST/yt3d.zip"; done
rm -rf "$tmp"
say "  got $i pieces ($(du -h "$DEST/yt3d.zip" | cut -f1))"

# ----------------------------------------------------------------- 2. unpack
say "• Unpacking…"
rm -rf "$DEST/youtube-3d-vision"
unzip -oq "$DEST/yt3d.zip" -d "$DEST" || die "Unpacking failed."
[ -f "$DEST/youtube-3d-vision/manifest.json" ] || die "The unpacked add-on looks incomplete."
rm -f "$DEST/yt3d.zip"

# --------------------------------------------------- 3. a browser that can load it
BROWSER=""
for c in \
  "$DEST/chrome-$OS$([ "$OS" = mac ] && echo "-$ARCH")/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing" \
  "$DEST/chrome-$OS$([ "$OS" = linux ] && echo "64")/chrome" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium" \
  "$(command -v chromium 2>/dev/null || true)" \
  "$(command -v chromium-browser 2>/dev/null || true)" ; do
  [ -n "$c" ] && [ -x "$c" ] && BROWSER="$c" && break
done

if [ -z "$BROWSER" ]; then
  say "• Fetching a browser that can load the 3D add-on (Chrome for Testing, ~150 MB, one time)…"
  case "$OS" in
    mac)   ZURL="https://storage.googleapis.com/chrome-for-testing-public/$CFT_VERSION/mac-$ARCH/chrome-mac-$ARCH.zip"; DIR="chrome-mac-$ARCH" ;;
    linux) ZURL="https://storage.googleapis.com/chrome-for-testing-public/$CFT_VERSION/linux64/chrome-linux64.zip";     DIR="chrome-linux64" ;;
  esac
  curl -fL --progress-bar "$ZURL" -o "$DEST/cft.zip" || die "Could not download the browser."
  unzip -oq "$DEST/cft.zip" -d "$DEST" || die "Could not unpack the browser."
  rm -f "$DEST/cft.zip"
  if [ "$OS" = mac ]; then BROWSER="$DEST/$DIR/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing";
  else BROWSER="$DEST/$DIR/chrome"; fi
fi
[ -x "$BROWSER" ] || die "No usable browser found."

# ------------------------------------------------------------------ 4. launch
# Start the browser first, then open YouTube a few seconds later: the add-on
# needs a moment to come up, and a page opened in that first instant would not
# get it. (Second launch with the same profile just opens a tab.)
say "• Starting the browser with 3D built in…"
"$BROWSER" --load-extension="$DEST/youtube-3d-vision" --user-data-dir="$DEST/profile" \
  --no-first-run --no-default-browser-check --no-default-browser-check about:blank >/dev/null 2>&1 &
sleep 5
"$BROWSER" --load-extension="$DEST/youtube-3d-vision" --user-data-dir="$DEST/profile" \
  "https://www.youtube.com" >/dev/null 2>&1 &

say ""
say "✓ Done. YouTube is opening now."
say "  • Open any normal video - the 3D switches itself on after a few seconds."
say "  • Put on red-cyan glasses (or pick Side-by-side in the panel for a 3D TV / headset)."
say "  • To run it again later: $BROWSER --load-extension=\"$DEST/youtube-3d-vision\" --user-data-dir=\"$DEST/profile\""
say "  • Nothing was installed into your normal Chrome, and nothing is uploaded anywhere."
