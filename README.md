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

The script desaturates both locations and restarts `WallpaperAgent`.

## Notes and copyright

The Aerial videos are **copyrighted content owned by Apple**. This project in no
way redistributes them. It only converts a copy of a file that already exists on
your own machine, for your own personal use. Do not upload, share, or publish the
`.mov` files or poster images from other machines.
