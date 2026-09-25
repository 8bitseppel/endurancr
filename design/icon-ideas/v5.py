import html, math, re
from concepts import st
from v4 import svg

V = []
def add(num, name, why, f): V.append((num, name, why, f))

def drop(i, s, b):
    d = "M512 130 C560 250 790 470 790 640 A278 278 0 0 1 234 640 C234 470 464 250 512 130 Z"
    return (f'<g transform="rotate(18 512 560)"><path d="{d}" fill="{i}"/>'
            + st("M360 650 Q352 540 420 460", 54, s) + "</g>")
add("D1", "Sweat drop", "One big drop of sweat, leaning into the wind. Endurance is effort, and this is what it looks like.", drop)

def laurel(i, s, b):
    out, cx, cy, r = "", 512, 540, 310
    for side in (-1, 1):
        out += st(f"M{cx + side * r * math.sin(math.radians(16)):.0f} {cy + r * math.cos(math.radians(16)):.0f} "
                  f"A{r} {r} 0 0 {0 if side > 0 else 1} {cx + side * r * math.sin(math.radians(150)):.0f} {cy + r * math.cos(math.radians(150)):.0f}", 24, i)
        for k in range(6):
            t = math.radians(30 + k * 22)
            for off, tilt, col in ((1.16, 30, i), (.86, -30, s)):
                x, y = cx + side * r * off * math.sin(t), cy + r * off * math.cos(t)
                tang = math.degrees(math.atan2(-math.sin(t), side * math.cos(t)))
                out += (f'<ellipse cx="{x:.1f}" cy="{y:.1f}" rx="36" ry="78" fill="{col}" '
                        f'transform="rotate({tang - 90 + side * tilt:.1f} {x:.1f} {y:.1f})"/>')
    return out
add("D2", "The laurel", "The marathon was born in Greece, and the winner got a laurel wreath. Every finish in the app is yours to crown.", laurel)

def laces(i, s, b):
    loop = lambda k: (f"M512 500 C{512 + k * 130} 340 {512 + k * 360} 340 {512 + k * 330} 500 "
                      f"C{512 + k * 300} 640 {512 + k * 130} 600 512 500")
    tail = lambda k: f"M512 520 C{512 + k * 40} 660 {512 + k * 130} 760 {512 + k * 210} 880"
    return (st(loop(-1), 76, i) + st(loop(1), 76, s) + st(tail(-1), 64, s) + st(tail(1), 64, i)
            + f'<circle cx="512" cy="506" r="74" fill="{i}"/>')
add("D3", "Tie your laces", "A shoelace bow, the last thing you do before every run.", laces)

SHOE = ["..xxxx..........",
        "..xxxxx.........",
        "..xxxxxx........",
        "..xxwxxxx.......",
        "..xxxwxxxx......",
        "..xxxxwxxxxxx...",
        "..xxxxxxxxxxxxx.",
        "..xxxxxxxxxxxxxx",
        ".sssssssssssssss",
        ".ssssssssssssss."]
def pixels(i, s, b):
    c = 50; ox = (1024 - 16 * c) // 2 - 10; oy = (1024 - len(SHOE) * c) // 2 + 30
    col = {"x": i, "s": s, "w": b}
    out = "".join(f'<rect x="{ox + x * c}" y="{oy + y * c}" width="{c + 1}" height="{c + 1}" fill="{col[ch]}"/>'
                  for y, row in enumerate(SHOE) for x, ch in enumerate(row) if ch != ".")
    for y, x0, n, op in ((3, -2, 2, .5), (5, -3, 3, .35), (7, -1, 1, .6)):
        out += "".join(f'<rect x="{ox + (x0 + k) * c}" y="{oy + y * c}" width="{c - 6}" height="{c - 6}" fill="{s}" opacity="{op}"/>' for k in range(n))
    return out
add("D4", "8-bit sneaker", "A running shoe in pixels, speeding off like in an old arcade game. Playful, and a wink at 8bitseppel.", pixels)

def cadence(i, s, b):
    out = ""
    for k in range(11):
        x = 172 + k * 68; h = 120 + 200 * math.sin(math.pi * (k + .5) / 11)
        up = k % 2 == 0
        y0, y1 = (512 - 20, 512 - 20 - h) if up else (512 + 20, 512 + 20 + h * .7)
        out += st(f"M{x} {y0:.0f} V{y1:.0f}", 44, i if up else s, 1)
    return out
add("D5", "Cadence", "Left, right, left, right: your steps as a rhythm, left foot up and right foot down, building to the middle of the run.", cadence)

def wing(i, s, b):
    out = ""
    for k, (L, a) in enumerate(((600, 186), (520, 170), (430, 154), (330, 138))):
        x0, y0 = 760, 380
        x1, y1 = x0 + L * math.cos(math.radians(a)), y0 + L * math.sin(math.radians(a))
        out += st(f"M{x0} {y0} L{x1:.0f} {y1:.0f}", 110 - k * 6, i if k % 2 == 0 else s)
    return out + f'<circle cx="770" cy="385" r="100" fill="{i}"/>'
add("D6", "One wing", "Hermes, the messenger with wings on his feet. Just one wing, swept back by speed.", wing)

def stopwatch(i, s, b):
    r = 300; cx, cy = 512, 580; a = math.radians(-90 + 300)
    x, y = cx + 210 * math.cos(a), cy + 210 * math.sin(a)
    return (f'<rect x="452" y="150" width="120" height="84" rx="30" fill="{i}"/>' + st(f"M512 230 V290", 50, i, 1, "butt")
            + st("M760 300 L810 250", 50, i)
            + f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{i}" stroke-width="64"/>'
            f'<path d="M{cx} {cy} V{cy - 210} A210 210 0 1 1 {x:.1f} {y:.1f} Z" fill="{s}"/>')
add("D7", "Split time", "A stopwatch, most of the way round. The filled part is the plan you have already done.", stopwatch)

def medal(i, s, b):
    return (f'<path d="M250 60 H420 L600 480 H430 Z" fill="{s}"/><path d="M774 60 H604 L424 480 H594 Z" fill="{i}"/>'
            f'<circle cx="512" cy="660" r="240" fill="{i}"/><circle cx="512" cy="660" r="170" fill="none" stroke="{b}" stroke-width="22"/>'
            f'<circle cx="512" cy="660" r="64" fill="{s}"/>')
add("D8", "Finisher medal", "The medal at the end of the race, still on its ribbon. The goal the whole app is built around.", medal)

css = re.search(r"<style>(.*?)</style>", open("/tmp/icons/index.html").read(), re.S).group(1)
cards = []
for num, name, why, f in V:
    L = svg(f, uid=num)
    cards.append(f'''<article><p class="num">{num}</p><div class="big icon">{L}</div>
<h2>{html.escape(name)}</h2><p class="why">{html.escape(why)}</p><div class="tests">
<figure><div class="icon s60">{L}</div><figcaption>Home screen</figcaption></figure>
<figure><div class="icon s29">{L}</div><figcaption>Settings</figcaption></figure>
<figure><div class="icon s60 blur">{L}</div><figcaption>Squint</figcaption></figure>
<figure><div class="icon s60">{svg(f, "dark", num)}</div><figcaption>Dark</figcaption></figure>
<figure><div class="icon s60">{svg(f, "tinted", num)}</div><figcaption>Tinted</figcaption></figure>
<figure><div class="icon s60 watch">{L}</div><figcaption>Watch</figcaption></figure></div></article>''')
page = f'''<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>endurancr icons, fresh</title><style>{css}</style></head><body>
<header><h1>Completely fresh</h1><div class="lead">
<p>Nothing from before: no track, no e, no road, no dot, no sun, no spiral, no shield. Eight new things a runner knows.</p></div></header>
<main>{"".join(cards)}</main></body></html>'''
open("/tmp/icons/v5.html", "w").write(page)
