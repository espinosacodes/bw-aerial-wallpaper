# Black-and-white Aerial live wallpaper

Convert the macOS "Aerial" live wallpaper (the gray reef sharks one) to black and
white while keeping the animation.

## What it does

macOS Sonoma's Aerial wallpapers are short Apple-produced videos. The **lock
screen** plays the video; the **desktop** composites a static poster frame
rendered from that same video. To make everything grayscale you have to convert
both:

1. The video itself (`hue=s=0`, keeping the native frame rate and 10-bit HEVC so
   the Aerial player still recognizes it).
2. The poster BMPs the desktop actually draws.

## The lock-screen gotcha (why it can go black)

Apple's lock-screen decoder only renders an Aerial clip that carries the exact
`colr` color atom Apple ships: `nclc primaries=1, transfer=13, matrix=1`
(sRGB). When you re-encode with `ffmpeg` using VideoToolbox (or the mov muxer),
it writes `transfer=1` (bt709) instead. The result plays on the desktop but the
lock screen renders **black** the moment you lock.

The script patches the `colr` atom back to `transfer=13` (sRGB) in the finished
`.mov`, which restores the lock screen. Verify with:

```bash
ffprobe -v error -show_entries stream=color_transfer,color_primaries \
  -of default=noprint_wrappers=1 ~/Library/Application\ Support/com.apple.wallpaper/aerials/videos/<ASSET_ID>.mov
```

It should report `color_transfer=iec61966-2-1`.

## The lock-screen freeze gotcha (why it can go still)

Apple encodes Aerial clips with cinemagraph sample-group boxes (`sgpd`, `csgm`)
and a composition-to-decode timing box (`cslg`). These tell the lock-screen
renderer the clip is a looping animation. ffmpeg's mov muxer strips all three on
re-encode, so without a fix the lock screen shows a single stuck frame instead of
the moving sharks.

The script copies those cinemagraph boxes back out of the original `.mov` and
re-injects them into the re-encoded file's sample table (`stbl`), rebuilding the
box sizes up the file. The sample data (`mdat`) is untouched, so playback is
unchanged except for the loop declaration.

## Requirements

- macOS Sonoma+
- `ffmpeg` (`brew install ffmpeg`)
- Python 3 with Pillow (`brew install python && pip install pillow`)
- The Aerial wallpaper must already be selected in
  System Settings > Wallpaper, so its clip is cached locally.

## Usage

```bash
./make-bw-wallpaper.sh
```

By default it converts the gray reef sharks clip
(`3716DD4B-01C0-4F5B-8DD6-DB771EC472FB`). Pass another Aerial asset ID to target
a different one:

```bash
./make-bw-wallpaper.sh <ASSET_ID>
```

The original video is backed up to `$TMPDIR/bw-wallpaper/` so you can restore it.

To revert: copy the `orig_<ASSET_ID>.mov` backup back over the file, then
`killall WallpaperAgent`.

## How it works

The video lives in:
`~/Library/Application Support/com.apple.wallpaper/aerials/videos/<ASSET_ID>.mov`

The desktop poster frames live in the agent cache:
`~/Library/Containers/com.apple.wallpaper.agent/.../extension-com.apple.wallpaper.extension.aerials/*.bmp`

The script:

1. Backs up the original.
2. Encodes grayscale (native fps + 10-bit HEVC, `hue=s=0`).
3. Patches the `colr` atom back to Apple's sRGB value so the lock screen works.
4. Re-injects Apple's cinemagraph loop boxes so the lock screen animates.
5. Desaturates the desktop poster BMPs.
6. Swaps the files in and restarts `WallpaperAgent`.

## Notes and copyright

The Aerial videos are **copyrighted content owned by Apple**. This project in no
way redistributes them. It only converts a copy of a file that already exists on
your own machine, for your own personal use. Do not upload, share, or publish the
`.mov` files or poster images from other machines.
