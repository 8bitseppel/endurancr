import html, math, re
import v2
from v2 import svg, st, catmull, along
from secure import shield_d, house_d

V = []
def add(num, name, run, hint, f): V.append((num, name, run, hint, f))

def small_shield(cx, cy, a, col, edge=None, w=0):
    ring = f' stroke="{edge}" stroke-width="{w}" stroke-linejoin="round"' if edge else ""
    return f'<path d="{shield_d(cx, cy, a)}" fill="{col}"{ring}/>'

def small_house(cx, cy, a, col, edge=None, w=0):
    ring = f' stroke="{edge}" stroke-width="{w}"' if edge else ""
    return f'<path d="{house_d(cx, cy, a)}" fill="{col}"{ring} stroke-linejoin="round"/>'

def e_with(inner):
    def f(i, s, b):
        body = v2.forward_e(i, s, b)
        return body.replace("</g>", inner(i, s, b) + "</g>")
    return f
add("B1", "The forward e, you inside", "The e leans forward and runs on out of the frame.",
    "You, the dot, sit safe inside the letter, sheltered by it.", lambda i, s, b: v2.forward_e(i, s, b) + f'<circle cx="596" cy="384" r="58" fill="{s}"/>')
add("B2", "The forward e, shield inside", "The same forward e.",
    "The space inside the e holds a small shield, the size of a detail.", e_with(lambda i, s, b: small_shield(520, 386, 74, s)))

def track_path(r=225, cx0=392, cx1=632, cy=512):
    d = f"M512 {cy + r} H{cx1} A{r} {r} 0 0 0 {cx1} {cy - r} H{cx0} A{r} {r} 0 0 0 {cx0} {cy + r} Z"
    seg = [("L", (512, cy + r), (cx1, cy + r)), ("A", (cx1, cy), r, math.pi / 2, -math.pi / 2),
           ("L", (cx1, cy - r), (cx0, cy - r)), ("A", (cx0, cy), r, -math.pi / 2, -3 * math.pi / 2),
           ("L", (cx0, cy + r), (512, cy + r))]
    return d, seg

def track_around(i, s, b):
    d, _ = track_path()
    return (f'<path d="{d}" fill="none" stroke="{i}" stroke-width="100"/>'
            f'<path d="{d}" fill="none" stroke="{b}" stroke-width="10" stroke-dasharray="0" opacity="0"/>'
            f'<circle cx="512" cy="512" r="92" fill="{s}"/>')
add("B3", "The track around you", "A running track, one whole lap.",
    "You are the dot in the infield: the track closes all the way round you, nothing gets in or out.", track_around)

def track_shield(i, s, b):
    d, seg = track_path(); x, y = along(seg, .72)
    return (f'<path d="{d}" fill="none" stroke="{s}" stroke-width="96" opacity=".45"/>'
            f'<path d="{d}" pathLength="100" stroke-dasharray="72 100" fill="none" stroke="{i}" stroke-width="96"/>'
            + small_shield(x, y, 110, i, b, 26))
add("B4", "On the track, shield as runner", "A 400 m track, most of the lap done.",
    "The runner on the bend is a small shield instead of a dot.", track_shield)

def road_home(i, s, b):
    body = v2.long_road(i, s, b)
    body = re.sub(r'<path d="M292 470 A220 220 0 0 1 732 470 Z"[^>]*/>', "", body)
    return small_house(512, 360, 112, i) + body
add("B5", "The road home", "A road running to the horizon.",
    "Where the sun would rise there is a house: every run ends at home, on your phone.", road_home)

def lane_e_you(i, s, b):
    return v2.lane_e(i, s, b) + f'<circle cx="512" cy="424" r="46" fill="{i}"/>'
add("B6", "The e as lanes, you inside", "The e drawn as two lanes of a track bend.",
    "You, the dot, in the middle of the lanes, wrapped by them.", lane_e_you)

def loop_home(i, s, b):
    pts = [(512, 150), (790, 230), (880, 480), (760, 760), (520, 850), (260, 800), (150, 560), (230, 300)]
    return st(catmull(pts, closed=True), 92, i) + small_house(520, 846, 96, i, b, 30)
add("B7", "The loop back home", "Your route as one bold loop.",
    "It starts and finishes at a small house: the run comes back home with you, and stays there.", loop_home)

def move_held(i, s, b):
    body = v2.dot_trail(i, s, b)
    return body + small_shield(690, 506, 104, b)
add("B8", "On the move, shield at the core", "You, the dot, with the lanes streaming behind.",
    "Inside the dot, a small shield: protection is at your core, not on show.", move_held)

css = re.search(r"<style>(.*?)</style>", open("/tmp/icons/index.html").read(), re.S).group(1)
cards = []
for num, name, run, hint, f in V:
    L = svg(f, uid=num)
    cards.append(f'''<article><p class="num">{num}</p><div class="big icon">{L}</div>
<h2>{html.escape(name)}</h2><p class="why"><b>Running:</b> {html.escape(run)}<br><b>Only for you:</b> {html.escape(hint)}</p><div class="tests">
<figure><div class="icon s60">{L}</div><figcaption>Home screen</figcaption></figure>
<figure><div class="icon s29">{L}</div><figcaption>Settings</figcaption></figure>
<figure><div class="icon s60 blur">{L}</div><figcaption>Squint</figcaption></figure>
<figure><div class="icon s60">{svg(f, "dark", num)}</div><figcaption>Dark</figcaption></figure>
<figure><div class="icon s60">{svg(f, "tinted", num)}</div><figcaption>Tinted</figcaption></figure>
<figure><div class="icon s60 watch">{L}</div><figcaption>Watch</figcaption></figure></div></article>''')
page = f'''<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>endurancr icons, round 5</title><style>{css}</style></head><body>
<header><h1>Running first, only for you second</h1><div class="lead">
<p>The strongest running shapes from the last round, each with the privacy idea added back as a detail: small, inside the running shape, never the main thing.
Three ways of saying it: you are held inside the shape (B1, B3, B6), a small shield or house takes a detail's place (B2, B4, B8), or the run ends at home (B5, B7).</p></div></header>
<main>{"".join(cards)}</main></body></html>'''
open("/tmp/icons/v3.html", "w").write(page)
