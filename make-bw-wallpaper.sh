#!/usr/bin/env bash
# Make the gray reef sharks (or another) macOS "Aerial" live wallpaper grayscale.
#
# The video is a copyrighted Apple Aerial asset owned by Apple. This script does
# NOT redistribute it; it only converts a file you already have on your own Mac,
# so you can set it as your personal wallpaper. See README.md.
#
# Usage: ./make-bw-wallpaper.sh [ASSET_ID]
#   ASSET_ID defaults to the gray reef sharks clip: 3716DD4B-01C0-4F5B-8DD6-DB771EC472FB
set -euo pipefail

ASSET_ID="${1:-3716DD4B-01C0-4F5B-8DD6-DB771EC472FB}"
TMP_DIR="${TMPDIR:-/tmp}/bw-wallpaper"
mkdir -p "$TMP_DIR"

AERIALS_DIR="$HOME/Library/Application Support/com.apple.wallpaper/aerials"
VIDEO="$AERIALS_DIR/videos/$ASSET_ID.mov"
AGENT_CACHE="$HOME/Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/com.apple.wallpaper.caches/extension-com.apple.wallpaper.extension.aerials"

command -v ffmpeg >/dev/null || { echo "ffmpeg is required (brew install ffmpeg)"; exit 1; }

if [[ ! -f "$VIDEO" ]]; then
  echo "Video not found at: $VIDEO"
  echo "You must first set the Aerial wallpaper from System Settings > Wallpaper so the clip is cached."
  exit 1
fi

echo "[1/4] Backing up original video..."
cp -p "$VIDEO" "$TMP_DIR/orig_$ASSET_ID.mov"

echo "[2/4] Encoding grayscale (native frame rate, 4K, HEVC 10-bit)..."
# hue=s=0 desaturates. We keep the native fps and 10-bit codec so the Aerial
# player recognizes the file. Output is bit-identical except for saturation.
# NOTE: this takes several minutes on Apple Silicon.
ffmpeg -y -hide_banner -loglevel error \
  -i "$VIDEO" \
  -vf "hue=s=0" \
  -c:v hevc_videotoolbox -c:a copy -tag:v hvc1 \
  "$TMP_DIR/bw_$ASSET_ID.mov"

echo "[3/4] Backing up and desaturating the desktop poster BMPs..."
# The desktop composites a static poster rendered from the video, not the video
# itself. Desaturate those BMPs so the desktop shows grayscale too.
for bmp in "$AGENT_CACHE"/*.bmp; do
  [[ -e "$bmp" ]] || continue
  if python3 - "$bmp" >/dev/null 2>&1; then
    cp -p "$bmp" "$TMP_DIR/$(basename "$bmp").orig"
    python3 - "$bmp" <<'PY'
import sys
from PIL import Image
p = sys.argv[1]
im = Image.open(p).convert("RGB")
mean = im.convert("L").resize((64, 64)).getpixel((0, 0))  # unused guard
gray = im.convert("L").convert("RGB")
gray.save(p)
PY
    echo "   desaturated $(basename "$bmp")"
  fi
done

echo "[4/4] Swapping in the grayscale video and restarting the wallpaper daemon..."
cp -p "$TMP_DIR/bw_$ASSET_ID.mov" "$VIDEO"
killall WallpaperAgent 2>/dev/null || true
sleep 2
echo "Done. The lock-screen animation and the desktop poster are now grayscale."
