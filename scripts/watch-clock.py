#!/usr/bin/env python3
"""Sets the clock on the Apple Watch screenshots and recordings to 10:09.

The iPhone Simulator takes a fixed status bar time (`simctl status_bar`), the
watch Simulator doesn't, so its clock shows whatever time the screenshots were
taken. This paints over the clock in the top right corner, in the watch's own
font (SF Compact Rounded, matched to the Simulator's pixels), on each still
and on every frame of each recording, then rebuilds the GIFs.

Run by ./scripts/screenshots.sh after the watch shots. Needs Pillow and ffmpeg.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "screenshots"
BUILD = ROOT / "build/screenshots"
TIME = "10:09"

FONT = "/System/Library/Fonts/SFCompactRounded.ttf"
# Matched on a 416 x 496 Series 11 (46 mm) screenshot: size and weight at 4x,
# right edge and top of the digits in screen pixels.
SIZE_4X, WEIGHT, RIGHT, TOP = 138, 600, 383.5, 40
BOX = (294, 32, 394, 72)   # the clock and some margin, clear of the title below


def clock_mask(size):
    """The time as white-on-black alpha, rendered at 4x and scaled down."""
    w, h = size
    font = ImageFont.truetype(FONT, SIZE_4X)
    font.set_variation_by_axes([WEIGHT])
    big = Image.new("L", (w * 4, h * 4), 0)
    draw = ImageDraw.Draw(big)
    x0, y0, x1, _ = draw.textbbox((0, 0), TIME, font=font)
    draw.text((RIGHT * 4 - x1, TOP * 4 - y0), TIME, font=font, fill=255)
    return big.resize((w, h), Image.LANCZOS)


def patch(im, mask):
    """Paints the box with the background just left of it, row by row (the Today
    screen has a gradient), then draws the time on top."""
    im = im.convert("RGB")
    px = im.load()
    x0, y0, x1, y1 = BOX
    for y in range(y0, y1):
        bg = px[x0 - 2, y]
        for x in range(x0, x1):
            px[x, y] = bg
    white = Image.new("RGB", im.size, (255, 255, 255))
    return Image.composite(white, im, mask)


def patch_video(mov, gif):
    with tempfile.TemporaryDirectory() as tmp:
        frames = Path(tmp)
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(mov), "-vf", "fps=30",
                        str(frames / "f%05d.png")], check=True)
        mask = None
        for f in sorted(frames.glob("f*.png")):
            im = Image.open(f)
            if im.size != (416, 496):
                sys.exit(f"{mov.name}: expected 416x496 frames, got {im.size}")
            mask = mask or clock_mask(im.size)
            patch(im, mask).save(f)
        patched = frames / "patched.mov"
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", "30", "-i", str(frames / "f%05d.png"),
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "12", str(patched)], check=True)
        patched.replace(mov)
    # Same GIF settings as screenshots.sh.
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(mov), "-vf",
                    "fps=25,scale=312:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];"
                    "[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle", str(gif)], check=True)


def main():
    for png in sorted(OUT.glob("watch-*.png")):
        im = Image.open(png)
        patch(im, clock_mask(im.size)).save(png)
        print(f"    {png.relative_to(ROOT)} at {TIME}")
    for mov in sorted(BUILD.glob("watch-*.mov")):
        patch_video(mov, OUT / f"{mov.stem}.gif")
        print(f"    {mov.relative_to(ROOT)} and its GIF at {TIME}")


if __name__ == "__main__":
    main()
