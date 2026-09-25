import html, re, sys
import secure as S
from secure import shield_d, house_d, st, catmull, svg
V = []
def add(n, name, why, f): V.append((n, name, why, f))
def inshield(body, a=410, cy=520):
    return lambda i, h, s: (f'<defs><clipPath id="kw"><path d="{shield_d(512, cy, a)}"/></clipPath></defs>'
                            f'<path d="{shield_d(512, cy, a)}" fill="{i}"/><g clip-path="url(#kw)">{body(i, h, s)}</g>')
add("R1", "Shield and track", "A running track inside the shield: the place you run, protected.",
    inshield(lambda i, h, s: f'<rect x="250" y="250" width="524" height="560" rx="262" fill="none" stroke="{h}" stroke-width="64"/>'
             f'<rect x="352" y="352" width="320" height="356" rx="160" fill="none" stroke="{h}" stroke-width="24" opacity=".5"/>'))
add("R2", "Shield and lanes", "Three lanes sweep round the bend inside the shield.",
    inshield(lambda i, h, s: "".join(st(f"M100 {1024 - r} A{r} {r} 0 0 1 {100 + r} 1024", 60, h, op, "butt")
                                     for r, op in ((300, 1), (430, .6), (560, .35)))))
add("R3", "Shield and route", "Your route winds up through the shield and ends in you.",
    inshield(lambda i, h, s: st(catmull([(420, 1000), (400, 800), (600, 660), (420, 500), (560, 360)]), 58, h)
             + f'<circle cx="560" cy="330" r="62" fill="{h}"/>'))
add("R4", "The road ahead", "Lanes run to the horizon inside the shield, with the sun waiting at the end.",
    inshield(lambda i, h, s: f'<circle cx="512" cy="430" r="110" fill="{h}"/><rect x="0" y="430" width="1024" height="700" fill="{i}"/>'
             + st("M100 470 H924", 30, h, .7)
             + "".join(st(f"M{x0} 1000 L{x1} 480", 34, h, op) for x0, x1, op in ((200, 470, .5), (512, 512, 1), (824, 554, .5)))))
add("R5", "Shield on the move", "The shield runs: speed lines trail behind it.",
    lambda i, h, s: f'<path d="{shield_d(600, 520, 330)}" fill="{i}"/>'
    + "".join(st(f"M{x} {y} H{x + w}", 50, i, op) for x, y, w, op in ((90, 380, 230, .35), (40, 520, 300, .6), (90, 660, 230, .35))))
def feet(i, h, s):
    b = ""
    for cx, cy, r in ((430, 640, -12), (590, 400, 12)):
        b += (f'<g transform="rotate({r} {cx} {cy})"><ellipse cx="{cx}" cy="{cy}" rx="62" ry="110" fill="{h}"/>'
              f'<ellipse cx="{cx}" cy="{cy + 150}" rx="50" ry="46" fill="{h}"/></g>')
    return b
add("R6", "Footsteps in the shield", "Two footsteps inside the shield: every step is yours alone.", inshield(feet))
def lock_track(i, h, s):
    return (st("M300 520 V400 A212 212 0 0 1 724 400 V520", 96, i, 1, "butt")
            + st("M380 520 V410 A132 132 0 0 1 644 410 V520", 26, s, 1, "butt")
            + f'<rect x="200" y="470" width="624" height="420" rx="90" fill="{i}"/>'
            + st("M280 600 H744", 26, h, .5) + st("M280 680 H744", 26, h, .8) + st("M280 760 H744", 26, h, .5))
add("R7", "Padlock track", "The shackle is the bend of a track, with its inner lane. The lock body has the straight lanes.", lock_track)
def home_run(i, h, s):
    return (f'<defs><clipPath id="kw"><path d="{house_d(512, 540, 390)}"/></clipPath></defs><path d="{house_d(512, 540, 390)}" fill="{i}" stroke="{i}" stroke-width="50" stroke-linejoin="round"/>'
            f'<g clip-path="url(#kw)">' + "".join(st(f"M{x0} 1000 L{x1} 460", 34, h, op) for x0, x1, op in ((180, 440, .5), (512, 512, 1), (844, 584, .5)))
            + f'<circle cx="512" cy="400" r="60" fill="{h}"/></g>')
add("R8", "Running home", "Lanes lead into the house: your runs come home and stay there.", home_run)

css = re.search(r"<style>(.*?)</style>", open("/tmp/icons/index.html").read(), re.S).group(1)
cards = []
for n, name, why, f in V:
    L = svg(f, uid=n)
    t = "".join(f'<figure><div class="icon {c}">{x}</div><figcaption>{cap}</figcaption></figure>' for c, x, cap in
                (("s60", L, "Home screen"), ("s29", L, "Settings"), ("s60 blur", L, "Squint"), ("s60", svg(f, dark=True, uid=n), "Dark"),
                 ("s60", svg(f, tinted=True, uid=n), "Tinted"), ("s60 watch", L, "Watch")))
    cards.append(f'<article><p class="num">{n}</p><div class="big icon">{L}</div><h2>{html.escape(name)}</h2><p class="why">{html.escape(why)}</p><div class="tests">{t}</div></article>')
open("/tmp/icons/running.html", "w").write(f'<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>endurancr: protection and running</title><style>{css}</style></head><body>'
    f'<header><h1>Protection, and running</h1><div class="lead"><p>The shield, padlock and house, each combined with running: a track, lanes, a route, the road ahead, speed lines and footsteps.</p></div></header>'
    f'<main>{"".join(cards)}</main></body></html>')
