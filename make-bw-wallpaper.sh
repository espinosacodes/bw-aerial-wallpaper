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

echo "[1/5] Backing up original video..."
cp -p "$VIDEO" "$TMP_DIR/orig_$ASSET_ID.mov"

echo "[2/5] Encoding grayscale (native frame rate, 4K, HEVC 10-bit)..."
# hue=s=0 desaturates. We keep the native fps and 10-bit codec so the Aerial
# player recognizes the file.
# CRITICAL: Apple's lock-screen decoder only renders the Aerial clips that carry
# the exact colr color atom (nclc primaries=1, transfer=13, matrix=1, i.e. sRGB).
# VideoToolbox and ffmpeg's mov muxer force bt709 (transfer=1), which makes the
# lock screen render BLACK. We patch the colr atom back to Apple's value below.
# NOTE: this takes several minutes on Apple Silicon.
ffmpeg -y -hide_banner -loglevel error \
  -i "$VIDEO" \
  -vf "hue=s=0" \
  -c:v hevc_videotoolbox -c:a copy -tag:v hvc1 \
  "$TMP_DIR/bw_$ASSET_ID.mov"

echo "[3/5] Restoring the Apple colr color atom (prevents black lock screen)..."
python3 - "$TMP_DIR/bw_$ASSET_ID.mov" "$TMP_DIR/bw_colrfix_$ASSET_ID.mov" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
data = bytearray(open(src, 'rb').read())
i = data.find(b'colrnclc')
if i == -1:
    print("WARN: no colr nclc atom found; skipping color fix"); sys.exit(0)
# 'colr'(4) + 'nclc'(4) + primaries(2) + transfer(2) + matrix(2)
data[i + 10] = 0   # transfer high byte -> 0
data[i + 11] = 13  # transfer low byte -> 13 (iec61966-2-1 sRGB)
open(dst, 'wb').write(data)
print("colr atom -> primaries=%d transfer=%d matrix=%d"
      % (int.from_bytes(data[i+8:i+10], 'big'),
         int.from_bytes(data[i+10:i+12], 'big'),
         int.from_bytes(data[i+12:i+14], 'big')))
PY

echo "[4/6] Injecting Apple's cinemagraph loop boxes (makes the lock screen animate)..."
# ffmpeg's mov muxer strips Apple's cinemagraph sample-group boxes (sgpd/csgm/cslg).
# Without them the lock screen renders a single stuck frame instead of the looping
# animation. We copy those boxes from the original into the re-encoded stbl.
python3 - "$TMP_DIR/orig_$ASSET_ID.mov" "$TMP_DIR/bw_colrfix_$ASSET_ID.mov" "$TMP_DIR/bw_$ASSET_ID.final.mov" <<'PY'
import sys, struct

def children(d, start, end):
    p, res = start, []
    while p + 8 <= end:
        sz, typ = struct.unpack('>I4s', d[p:p+8]); typ = typ.decode('latin1')
        hdr, full = 8, sz
        if sz == 1:
            full = struct.unpack('>Q', d[p+8:p+16])[0]; hdr = 16
        if sz == 0:
            full = end - p
        res.append((typ, p, full)); p += full
    return res

def stbl(d):
    for t, p, f in children(d, 0, len(d)):
        if t == 'moov':
            for t2, p2, f2 in children(d, p+8, p+f):
                if t2 == 'trak':
                    for t3, p3, f3 in children(d, p2+8, p2+f2):
                        if t3 == 'mdia':
                            for t4, p4, f4 in children(d, p3+8, p3+f3):
                                if t4 == 'minf':
                                    for t5, p5, f5 in children(d, p4+8, p4+f4):
                                        if t5 == 'stbl':
                                            return dict(moov=p, trak=p2, mdia=p3,
                                                        minf=p4, stbl=p5,
                                                        moovsz=f, traksz=f2,
                                                        mdiasz=f3, minfsz=f4, stblsz=f5)
    return None

def payloads(d, s, sz):
    return {t: d[p+8:p+f] for t, p, f in children(d, s+8, s+sz)}

def box(typ, payload):
    return struct.pack('>I4s', 8 + len(payload), typ.encode()) + payload

orig, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
o, g = open(orig, 'rb').read(), open(src, 'rb').read()

# Apple cinemagraph boxes from the original's stbl (loop metadata, not frame order)
oi = stbl(o); oc = payloads(o, oi['stbl'], oi['stblsz'])
cinema = b''.join(oc[t] for t in ('sgpd', 'csgm', 'cslg') if t in oc)
if not cinema:
    print("WARN: no cinemagraph boxes found; skipping injection"); open(dst, 'wb').write(g); sys.exit(0)

gi = stbl(g); gb = payloads(g, gi['stbl'], gi['stblsz'])
new_stbl = gb['stsd'] + cinema + gb['stts'] + gb['stss'] + gb['stsc'] + gb['stsz'] + gb['stco']
stbl_box = box('stbl', new_stbl)

mp = payloads(g, gi['minf'], gi['minfsz'])
minf_box = box('minf', b''.join(box(t, mp[t]) for t in ('vmhd', 'hdlr', 'dinf')) + stbl_box)
mdp = payloads(g, gi['mdia'], gi['mdiasz'])
mdia_box = box('mdia', b''.join(box(t, mdp[t]) for t in ('mdhd', 'hdlr')) + minf_box)
tp = payloads(g, gi['trak'], gi['traksz'])
trak_box = box('trak', b''.join(box(t, tp[t]) for t in ('tkhd', 'edts')) + mdia_box)
mop = payloads(g, gi['moov'], gi['moovsz'])

def ordered(payload, keep):
    return b''.join(box(t, payload[t]) for t in keep if t in payload)
moov_box = box('moov', ordered(mop, ('mvhd',)) + trak_box + ordered(mop, ('udta',)))

out = g[:28] + g[28:28 + 8 + struct.unpack('>I', g[24:28])[0]] + moov_box
open(dst, 'wb').write(out)
print("injected cinemagraph boxes (%d bytes); wrote %s" % (len(cinema), dst))
PY

echo "[5/6] Backing up and desaturating the desktop poster BMPs..."
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
im.convert("L").convert("RGB").save(p)
PY
    echo "   desaturated $(basename "$bmp")"
  fi
done

echo "[6/6] Swapping in the grayscale video and restarting the wallpaper daemon..."
cp -p "$TMP_DIR/bw_$ASSET_ID.final.mov" "$VIDEO"
killall WallpaperAgent 2>/dev/null || true
sleep 2
echo "Done. The lock-screen animation and the desktop poster are now grayscale."
