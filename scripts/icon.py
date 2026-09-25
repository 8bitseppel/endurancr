#!/usr/bin/env python3
"""Draws the endurancr icon: a sun of running lanes with a keyhole, mirrored in
water, centred and filling the icon. Writes website/logo.svg and renders the app
icons (iPhone light, dark, tinted, Apple Watch) and the website PNGs.

Needs Python 3 with Playwright (pip install playwright; playwright install chromium).
Run from the repository root: python3 scripts/icon.py
"""
import asyncio
import math
from pathlib import Path

C = 512
LANES = ((425, 18, .28), (335, 52, 1), (245, 18, .28))  # radius, width, opacity
MIRROR = (.14, .22, .14)

THEMES = {
    "light": dict(bg=("#f4eef8", "#dccbe8"), ink="#3b1f4b", hole="#f4eef8"),
    "dark": dict(bg=("#5a3a6e", "#241030"), ink="#f4eef8", hole="#2b1638"),
    "tinted": dict(bg=("#000000", "#000000"), ink="#ffffff", hole="#000000"),
}


def arc(r, upper):
    sweep = 1 if upper else 0
    return f"M{C - r} {C} A{r} {r} 0 0 {sweep} {C + r} {C}"


def stroke(d, w, op, ink):
    return (f'<path d="{d}" fill="none" stroke="{ink}" stroke-width="{w}" '
            f'stroke-linecap="round" opacity="{op}"/>')


def keyhole(cx, cy, r, ink, hole):
    return (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{ink}"/>'
            f'<circle cx="{cx}" cy="{cy - 0.18 * r:.1f}" r="{0.26 * r:.1f}" fill="{hole}"/>'
            f'<path d="M{cx - 0.13 * r:.1f} {cy - 0.05 * r:.1f} L{cx - 0.22 * r:.1f} {cy + 0.5 * r:.1f} '
            f'H{cx + 0.22 * r:.1f} L{cx + 0.13 * r:.1f} {cy - 0.05 * r:.1f} Z" fill="{hole}"/>')


def svg(theme, rounded):
    t = THEMES[theme]
    corner = ' rx="230"' if rounded else ""
    body = "".join(stroke(arc(r, True), w, op, t["ink"]) for r, w, op in LANES)
    body += "".join(stroke(arc(r, False), w, op, t["ink"]) for (r, w, _), op in zip(LANES, MIRROR))
    body += stroke(f"M60 {C} H964", 18, .45, t["ink"])
    body += keyhole(C, 398, 100, t["ink"], t["hole"])
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-label="endurancr">'
            f'<defs><radialGradient id="g" cx="0.5" cy="0.34" r="0.72"><stop offset="0" stop-color="{t["bg"][0]}"/>'
            f'<stop offset="1" stop-color="{t["bg"][1]}"/></radialGradient></defs>'
            f'<rect width="1024" height="1024"{corner} fill="url(#g)"/>{body}</svg>')


async def render(jobs):
    from playwright.async_api import async_playwright
    async with async_playwright() as p:
        browser = await p.chromium.launch()
        page = await browser.new_page(viewport={"width": 1024, "height": 1024})
        for markup, size, out, transparent in jobs:
            await page.set_viewport_size({"width": size, "height": size})
            sized = markup.replace("<svg ", f'<svg width="{size}" height="{size}" ', 1)
            await page.set_content(
                f'<html><body style="margin:0;background:transparent">{sized}</body></html>')
            await page.screenshot(path=out, omit_background=transparent)
        await browser.close()


def main():
    Path("website/logo.svg").write_text(svg("light", rounded=True))
    ios = "App-iOS/Assets.xcassets/AppIcon.appiconset"
    watch = "App-watchOS/Assets.xcassets/AppIcon.appiconset"
    asyncio.run(render([
        (svg("light", False), 1024, f"{ios}/AppIcon.png", False),
        (svg("dark", False), 1024, f"{ios}/AppIcon-Dark.png", False),
        (svg("tinted", False), 1024, f"{ios}/AppIcon-Tinted.png", False),
        (svg("light", False), 1024, f"{watch}/AppIcon-Watch.png", False),
        (svg("light", False), 180, "website/apple-touch-icon.png", False),
        (svg("light", True), 512, "website/icon-512.png", True),
    ]))


if __name__ == "__main__":
    main()
