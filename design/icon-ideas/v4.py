import html, math, re
from concepts import st, catmull

# Bolder palette this time: electric violet to deep ink. Still no orange.
BASE = (("#8a4fe0", "#240c40"), "#f6f0ff", "#c9a8f2", "#240c40")
MODES = {"base": BASE,
         "dark": (("#2c1446", "#0b0414"), "#ece0fb", "#9a7cc4", "#0b0414"),
         "tinted": (("#1a1a1a", "#0a0a0a"), "#f2f2f2", "#8a8a8a", "#0a0a0a")}
V = []
def add(num, name, run, you, f): V.append((num, name, run, you, f))

def fingerprint(i, s, b):
    out = ""
    for k in range(6):
        r, L = 58 + k * 58, 70
        w, col = (46, i) if k == 5 else (30, s)
        gap_at = (17 * k + 9) % 100
        out += (f'<rect x="{512 - r}" y="{512 - L - r}" width="{2 * r}" height="{2 * L + 2 * r}" rx="{r}" fill="none" '
                f'stroke="{col}" stroke-width="{w}" stroke-linecap="round" pathLength="100" '
                f'stroke-dasharray="{88 - k * 2} {12 + k * 2}" stroke-dashoffset="{gap_at}"/>')
    return out + f'<circle cx="512" cy="512" r="34" fill="{i}"/>'
add("C1", "Fingerprint", "Six laps of a running track, nested inside each other.",
    "Together they make a fingerprint. Nobody else has yours: your runs are yours alone.", fingerprint)

def spiral(i, s, b):
    pts, b_ = [], 330 / (7 * math.pi)
    for n in range(0, 700):
        t = n / 699 * 7 * math.pi
        r = 70 + b_ * t
        pts.append((512 + r * math.cos(t - math.pi / 2), 512 + r * math.sin(t - math.pi / 2)))
    d = "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts)
    x, y = pts[-1]
    return st(d, 50, i) + f'<circle cx="512" cy="512" r="46" fill="{s}"/><circle cx="{x:.1f}" cy="{y:.1f}" r="62" fill="{i}"/>'
add("C2", "The 42 km spiral", "The whole marathon wound into one line. You start on the outside.",
    "The finish is at the heart of it, where nothing reaches. Hypnotic on purpose.", spiral)

def strobe(i, s, b):
    out = ""
    steps = [(220, 800, 56, .14), (330, 670, 76, .24), (450, 560, 100, .4), (580, 460, 128, .65)]
    for x, y, r, op in steps: out += f'<circle cx="{x}" cy="{y}" r="{r}" fill="{s}" opacity="{op}"/>'
    return out + f'<circle cx="720" cy="370" r="170" fill="{i}"/>'
add("C3", "Long exposure", "A photo with the shutter open: you, the dot, getting bigger and brighter with every stride.",
    "No privacy mark. It just feels like one person, alone, moving.", strobe)

def topo(i, s, b):
    base = [(0, -1), (.8, -.7), (1.1, .1), (.7, .8), (-.2, 1), (-1, .5), (-.9, -.4)]
    out = ""
    for k, sc in enumerate((380, 290, 200, 115)):
        pts = [(600 + x * sc * (1 + .06 * k), 470 + y * sc * .9) for x, y in base]
        out += st(catmull(pts, closed=True), 22, s, .55 + k * .12)
    route = catmull([(140, 930), (260, 820), (230, 690), (380, 620), (470, 520), (600, 470)])
    return out + st(route, 54, i) + f'<circle cx="600" cy="470" r="70" fill="{i}"/>'
add("C4", "Your own map", "Contour lines of a hill, and your route climbing it to the top.",
    "A map that only you have, drawn by your own feet.", topo)

def wall(i, s, b):
    bricks = ""
    for row, y in enumerate(range(80, 1000, 120)):
        for x in range(-120 if row % 2 else -40, 1100, 220):
            bricks += f'<rect x="{x}" y="{y}" width="196" height="96" rx="22" fill="{s}"/>'
    hole = '<circle cx="560" cy="520" r="250" fill="black"/>'
    lines = "".join(st(f"M{x0} {y} H{x1}", 34, i, .8) for x0, x1, y in ((170, 330, 450), (130, 330, 540), (190, 330, 630)))
    return (f'<defs><mask id="kw"><rect width="1024" height="1024" fill="white"/>{hole}</mask></defs>'
            f'<g mask="url(#kw)" opacity=".5">{bricks}</g>' + lines + f'<circle cx="590" cy="540" r="150" fill="{i}"/>')
add("C5", "Through the wall", "Kilometre 32, the wall every marathon runner knows. You go straight through it.",
    "The wall stays standing all around: you are through, it keeps everyone else out.", wall)

def tape(i, s, b):
    return (st("M40 640 C240 650 330 560 420 470", 58, s) + st("M984 640 C784 650 694 560 604 470", 58, s)
            + f'<circle cx="512" cy="400" r="160" fill="{i}"/>')
add("C6", "Breaking the tape", "The finish line, the moment the tape snaps. You are the dot going through.",
    "No privacy mark: it is the one moment every runner wants.", tape)

def sash(i, s, b):
    return (st("M-60 1030 L1030 -60", 300, i, 1, "butt") + st("M-60 780 L780 -60", 44, s, 1, "butt")
            + st("M244 1084 L1084 244", 44, s, 1, "butt"))
add("C7", "The race sash", "The diagonal sash on a racing vest, filling the whole icon edge to edge. Loud like a kit.",
    "No mark. Wearing it is a statement about you, not about data.", sash)

def bib(i, s, b):
    e_r = 130; a = math.radians(40)
    x1, y1 = 512 + e_r * math.cos(a), 560 + e_r * math.sin(a)
    e = (st(f"M{512 + e_r} 560 A{e_r} {e_r} 0 1 0 {x1:.1f} {y1:.1f}", 58, b) + st(f"M{512 - e_r} 560 H{512 + e_r}", 50, b))
    pins = "".join(f'<circle cx="{x}" cy="{y}" r="22" fill="{b}"/>' for x, y in ((230, 300), (794, 300), (230, 800), (794, 800)))
    return (f'<g transform="rotate(-7 512 512)"><rect x="170" y="240" width="684" height="620" rx="70" fill="{i}"/>'
            f'<rect x="170" y="240" width="684" height="130" rx="70" fill="{s}"/><rect x="170" y="300" width="684" height="70" fill="{s}"/>'
            f'{pins}{e}</g>')
add("C8", "The race bib", "A race number pinned on, tilted like it is on a moving runner, with an e instead of a number.",
    "A bib is personal: it is yours, with your name on the list. Quiet ownership, no lock needed.", bib)

def svg(f, mode="base", uid=""):
    bg, ink, soft, back = MODES[mode]
    gid = f"g{uid}{mode}"
    body = f(ink, soft, back).replace('id="kw"', f'id="kw{gid}"').replace('url(#kw)', f'url(#kw{gid})')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><defs><radialGradient id="{gid}" cx="0.3" cy="0.2" r="1">'
            f'<stop offset="0" stop-color="{bg[0]}"/><stop offset="1" stop-color="{bg[1]}"/></radialGradient></defs>'
            f'<rect width="1024" height="1024" fill="url(#{gid})"/>{body}</svg>')

css = re.search(r"<style>(.*?)</style>", open("/tmp/icons/index.html").read(), re.S).group(1)
cards = []
for num, name, run, you, f in V:
    L = svg(f, uid=num)
    cards.append(f'''<article><p class="num">{num}</p><div class="big icon">{L}</div>
<h2>{html.escape(name)}</h2><p class="why"><b>Running:</b> {html.escape(run)}<br><b>Only for you:</b> {html.escape(you)}</p><div class="tests">
<figure><div class="icon s60">{L}</div><figcaption>Home screen</figcaption></figure>
<figure><div class="icon s29">{L}</div><figcaption>Settings</figcaption></figure>
<figure><div class="icon s60 blur">{L}</div><figcaption>Squint</figcaption></figure>
<figure><div class="icon s60">{svg(f, "dark", num)}</div><figcaption>Dark</figcaption></figure>
<figure><div class="icon s60">{svg(f, "tinted", num)}</div><figcaption>Tinted</figcaption></figure>
<figure><div class="icon s60 watch">{L}</div><figcaption>Watch</figcaption></figure></div></article>''')
page = f'''<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>endurancr icons, going crazy</title><style>{css}</style></head><body>
<header><h1>Going crazy</h1><div class="lead">
<p>No safe choices this time: a louder electric violet, and ideas no other running app uses. Running is still the main thing in every one.</p></div></header>
<main>{"".join(cards)}</main></body></html>'''
open("/tmp/icons/v4.html", "w").write(page)
