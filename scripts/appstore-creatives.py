#!/usr/bin/env python3
"""App Store creative assets (iOS 27) from the screenshots in screenshots/.

Writes screenshots/appstore/creative/:
  header-21x9.png    product page header, 3840 x 1646
  search-3x2.png     search results, 3840 x 2560

Run ./scripts/screenshots.sh first. Needs Pillow. The text is centered with the
phones below it, so a header cropped at the sides still reads (Apple's advice is
to keep the focal point centered). No prices, URLs or other platforms on purpose.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SHOTS = ROOT / "screenshots"
OUT = SHOTS / "appstore" / "creative"
ICON = ROOT / "App-iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
FONT = "/System/Library/Fonts/SFNSRounded.ttf"

# The website's dark palette.
PLUM_DEEP = (36, 16, 48)
PLUM = (59, 31, 75)
LILAC = (220, 203, 232)
INK_MUTE = (195, 179, 207)

TITLE = "Run for you. Not for the feed."
LINE = "A private running plan that adapts to every run."


def font(size, weight="Semibold"):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def background(w, h):
    """Plum gradient, top to bottom, with a soft lilac glow behind the phones."""
    bg = Image.new("RGB", (w, h), PLUM_DEEP)
    top = Image.new("RGB", (w, h), PLUM)
    mask = Image.linear_gradient("L").resize((w, h)).transpose(Image.FLIP_TOP_BOTTOM)
    bg = Image.composite(top, bg, mask)
    glow = Image.new("L", (w, h), 0)
    ImageDraw.Draw(glow).ellipse((w * 0.2, h * 0.45, w * 0.8, h * 1.4), fill=110)
    glow = glow.filter(ImageFilter.GaussianBlur(h * 0.12))
    return Image.composite(Image.new("RGB", (w, h), (120, 84, 150)), bg, glow)


def rounded(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *im.size), radius, fill=255)
    out = Image.new("RGBA", im.size)
    out.paste(im.convert("RGB"), (0, 0), mask)
    return out


def phone(name, height):
    im = Image.open(SHOTS / name).convert("RGB")
    im = im.resize((round(im.width * height / im.height), height), Image.LANCZOS)
    framed = rounded(im, round(im.width * 0.12))
    # A thin edge so the black screen stands off the dark background.
    ImageDraw.Draw(framed).rounded_rectangle((0, 0, im.width - 1, im.height - 1), round(im.width * 0.12),
                                            outline=(118, 92, 140), width=max(3, im.width // 160))
    return framed


def paste_with_shadow(canvas, im, xy):
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    alpha = im.getchannel("A").point(lambda a: a * 0.55)
    shadow.paste((10, 4, 16, 255), (xy[0], xy[1] + im.height // 40), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(im.height // 45))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(im, xy)


def centered_text(draw, w, y, text, f, fill):
    x0, _, x1, _ = draw.textbbox((0, 0), text, font=f)
    draw.text(((w - (x1 - x0)) / 2 - x0, y), text, font=f, fill=fill)


def compose(w, h, title_size, phone_height, top):
    canvas = background(w, h).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    # Icon and name, then the phrase and one line under it.
    icon_size = round(title_size * 1.25)
    icon = rounded(Image.open(ICON).resize((icon_size, icon_size), Image.LANCZOS), round(icon_size * 0.225))
    name_font = font(round(title_size * 0.62))
    nx0, _, nx1, _ = draw.textbbox((0, 0), "endurancr", font=name_font)
    gap = round(title_size * 0.35)
    row = icon_size + gap + (nx1 - nx0)
    ix = (w - row) // 2
    canvas.alpha_composite(icon, (ix, top))
    draw.text((ix + icon_size + gap - nx0, top + icon_size * 0.18), "endurancr", font=name_font, fill=LILAC)

    y = top + icon_size + round(title_size * 0.45)
    centered_text(draw, w, y, TITLE, font(title_size, "Bold"), (255, 255, 255))
    y += round(title_size * 1.3)
    centered_text(draw, w, y, LINE, font(round(title_size * 0.5), "Medium"), INK_MUTE)
    y += round(title_size * 1.05)

    # Five screens, the middle one in front, running off the bottom edge.
    names = ["iphone-7-plan.png", "iphone-3-today.png", "iphone-4-run.png",
             "iphone-5-summary.png", "iphone-6-progress.png"]
    scales = [0.86, 0.93, 1.0, 0.93, 0.86]
    phones = [phone(n, round(phone_height * s)) for n, s in zip(names, scales)]
    spacing = round(phones[2].width * 1.08)
    cx = w // 2
    order = [0, 4, 1, 3, 2]  # back to front
    for i in order:
        p = phones[i]
        x = cx + (i - 2) * spacing - p.width // 2
        paste_with_shadow(canvas, p, (x, y + (phone_height - p.height) // 3))

    return canvas.convert("RGB")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    compose(3840, 1646, title_size=150, phone_height=1900, top=120).save(OUT / "header-21x9.png", optimize=True)
    compose(3840, 2560, title_size=190, phone_height=2700, top=190).save(OUT / "search-3x2.png", optimize=True)
    for f in sorted(OUT.glob("*.png")):
        im = Image.open(f)
        print(f"    {f.relative_to(ROOT)} {im.size[0]}x{im.size[1]} {im.mode}")


if __name__ == "__main__":
    main()
