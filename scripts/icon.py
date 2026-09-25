#!/usr/bin/env python3
"""Draws the endurancr icon: a finisher medal on its ribbon, on electric violet.
Writes website/logo.svg and favicon.svg and renders the app icons (iPhone light,
dark, tinted, Apple Watch) and the website PNGs.

Needs Python 3 with Playwright (pip install playwright; playwright install chromium).
Run from the repository root: python3 scripts/icon.py
"""
import asyncio
from pathlib import Path

THEMES = {
    "light": dict(bg=("#8a4fe0", "#240c40"), ink="#f6f0ff", soft="#c9a8f2", back="#240c40"),
    "dark": dict(bg=("#2c1446", "#0b0414"), ink="#ece0fb", soft="#9a7cc4", back="#0b0414"),
    "tinted": dict(bg=("#000000", "#000000"), ink="#ffffff", soft="#8a8a8a", back="#000000"),
}


def medal(t, ring=True):
    body = (f'<path d="M280 90 H430 L604 500 H444 Z" fill="{t["soft"]}"/>'
            f'<path d="M744 90 H594 L420 500 H580 Z" fill="{t["ink"]}"/>'
            f'<circle cx="512" cy="670" r="232" fill="{t["ink"]}"/>')
    if ring:
        body += f'<circle cx="512" cy="670" r="166" fill="none" stroke="{t["back"]}" stroke-width="22"/>'
    return body + f'<circle cx="512" cy="670" r="{64 if ring else 90}" fill="{t["soft"]}"/>'


def svg(theme, rounded, ring=True):
    t = THEMES[theme]
    corner = ' rx="230"' if rounded else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-label="endurancr">'
            f'<defs><radialGradient id="g" cx="0.3" cy="0.2" r="1"><stop offset="0" stop-color="{t["bg"][0]}"/>'
            f'<stop offset="1" stop-color="{t["bg"][1]}"/></radialGradient></defs>'
            f'<rect width="1024" height="1024"{corner} fill="url(#g)"/>{medal(t, ring)}</svg>')


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
    # The favicon drops the thin ring, which would blur at 16 to 32 pixels.
    Path("website/favicon.svg").write_text(svg("light", rounded=True, ring=False))
    ios = "App-iOS/Assets.xcassets/AppIcon.appiconset"
    watch = "App-watchOS/Assets.xcassets/AppIcon.appiconset"
    asyncio.run(render([
        (svg("light", False), 1024, f"{ios}/AppIcon.png", False),
        (svg("dark", False), 1024, f"{ios}/AppIcon-Dark.png", False),
        (svg("tinted", False), 1024, f"{ios}/AppIcon-Tinted.png", False),
        (svg("light", False), 1024, f"{watch}/AppIcon-Watch.png", False),
        (svg("light", False), 180, "website/apple-touch-icon.png", False),
        (svg("light", True), 512, "website/icon-512.png", True),
        (svg("light", True, ring=False), 32, "website/favicon-32.png", True),
    ]))


if __name__ == "__main__":
    main()
