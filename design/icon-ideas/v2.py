import html, math, re
from concepts import st, catmull

# Default is the deep purple (research rule 6); dark goes darker; tinted is mono.
THEMES = {
    "base": (("#6a4482", "#2a1238"), "#f4eef8", "#c8a9e0", "#2a1238"),
    "dark": (("#2e1a3c", "#0e0614"), "#e9ddf3", "#9a7cb4", "#0e0614"),
    "tinted": (("#1a1a1a", "#0a0a0a"), "#f2f2f2", "#8a8a8a", "#0a0a0a"),
}
V = []
def add(num, name, why, f): V.append((num, name, why, f))

def along(segments, frac):
    """Point at a fraction of a path made of ('L', p0, p1) and ('A', centre, r, a0, a1) pieces."""
    lens = [math.dist(s[1], s[2]) if s[0] == "L" else abs(s[4] - s[3]) * s[2] for s in segments]
    left = frac * sum(lens)
    for s, n in zip(segments, lens):
        if left <= n:
            k = left / n
            if s[0] == "L": return (s[1][0] + (s[2][0] - s[1][0]) * k, s[1][1] + (s[2][1] - s[1][1]) * k)
            a = s[3] + (s[4] - s[3]) * k; return (s[1][0] + s[2] * math.cos(a), s[1][1] + s[2] * math.sin(a))
        left -= n

def forward_e(i, s, b):
    r = 270; a = math.radians(40); x1, y1 = 512 + r * math.cos(a), 512 + r * math.sin(a)
    return (f'<g transform="translate(512 512) skewX(-12) translate(-512 -512)">'
            + st(f"M782 512 A{r} {r} 0 1 0 {x1:.1f} {y1:.1f} L{x1 + 150:.1f} {y1 + 30:.1f}", 112, i)
            + st("M262 512 H782", 96, i) + "</g>")
add("A1", "The forward e", "The first letter, leaning forward like a runner, its tail running on out of the frame. The way Runna and Strava use one bold letter or mark.", forward_e)

def long_road(i, s, b):
    dash = "".join(f'<path d="M{512 - w} {y} L{512 + w} {y} L{512 + w * .8} {y - h} L{512 - w * .8} {y - h} Z" fill="{b}"/>'
                   for y, w, h in ((930, 22, 120), (730, 14, 70), (600, 9, 40), (520, 6, 22)))
    return (f'<path d="M292 470 A220 220 0 0 1 732 470 Z" fill="{i}"/>'
            f'<path d="M150 950 L494 470 L530 470 L874 950 Z" fill="{s}"/>' + dash
            + st("M120 470 H904", 26, i, .5))
f_road = long_road
add("A2", "The long road", "A road that bends away to the horizon, the sun where it ends. Endurance is the distance still ahead.", long_road)

def on_track(i, s, b):
    r, cx0, cx1, cy = 225, 392, 632, 512
    d = f"M512 {cy + r} H{cx1} A{r} {r} 0 0 0 {cx1} {cy - r} H{cx0} A{r} {r} 0 0 0 {cx0} {cy + r} Z"
    seg = [("L", (512, cy + r), (cx1, cy + r)), ("A", (cx1, cy), r, math.pi / 2, -math.pi / 2),
           ("L", (cx1, cy - r), (cx0, cy - r)), ("A", (cx0, cy), r, -math.pi / 2, -3 * math.pi / 2),
           ("L", (cx0, cy + r), (512, cy + r))]
    x, y = along(seg, .72)
    return (f'<path d="{d}" fill="none" stroke="{s}" stroke-width="96" opacity=".45"/>'
            f'<path d="{d}" pathLength="100" stroke-dasharray="72 100" fill="none" stroke="{i}" stroke-width="96"/>'
            f'<circle cx="{x:.1f}" cy="{y:.1f}" r="104" fill="{i}"/><circle cx="{x:.1f}" cy="{y:.1f}" r="44" fill="{b}"/>')
add("A3", "On the track", "A 400 m track, most of the lap done, you on the bend. The loop closes on itself, a quiet hint that nothing leaves it.", on_track)

def rising(i, s, b):
    return (st("M170 860 C440 860 600 640 700 470", 70, s, .6)
            + st("M170 720 C440 720 640 460 850 230", 130, i)
            + f'<circle cx="806" cy="274" r="0" fill="{i}"/>')
add("A4", "Getting fitter", "Two curves rising, last block and this one, the bold one pulling ahead. Progress over weeks, not a single run.", rising)

def lane_e(i, s, b):
    out = []
    for r, w, col, op in ((300, 92, i, 1), (170, 56, s, 1)):
        a = math.radians(40); x1, y1 = 512 + r * math.cos(a), 512 + r * math.sin(a)
        out.append(st(f"M{512 + r} 512 A{r} {r} 0 1 0 {x1:.1f} {y1:.1f}", w, col, op, "butt"))
    return "".join(out) + st("M212 512 H812", 80, i, 1, "butt")
add("A5", "The e as lanes", "The e drawn as two lanes of a track bend, the bar across it like a finish line.", lane_e)

def dot_trail(i, s, b):
    t = ""
    for k, (y, x0, w, op) in enumerate(((380, 160, 50, .35), (500, 110, 66, .6), (620, 180, 50, .35))):
        t += st(f"M{x0} {y} Q{420} {y - 40 + k * 20} {560} {y + (0 if k == 1 else (40 if k == 0 else -40))}", w, s, op)
    return t + f'<circle cx="690" cy="500" r="170" fill="{i}"/>'
add("A6", "On the move", "You, the dot, with the lanes streaming behind. Pure speed, nothing else.", dot_trail)

def planes(i, s, b):
    p = lambda x, h, col, op: (f'<rect x="{x}" y="{812 - h}" width="190" height="{h}" rx="60" fill="{col}" opacity="{op}" '
                               f'transform="skewX(-22)" style="transform-origin:512px 812px"/>')
    return p(60, 420, s, .7) + p(230, 560, i, .9) + p(400, 700, s, .55)
add("A7", "Building up", "Three glassy bars leaning forward, each taller: weeks of training stacking up. The layered look Proton uses, turned into running.", planes)

def endless(i, s, b):
    pts = [(512, 512), (650, 350), (820, 330), (880, 500), (800, 680), (640, 660), (512, 512),
           (384, 364), (224, 344), (144, 524), (204, 694), (374, 674)]
    return (st(catmull(pts, closed=True), 96, s, .5)
            + st(catmull([(144, 524), (204, 694), (374, 674), (512, 512), (650, 350), (820, 330), (880, 500)]), 96, i)
            + f'<circle cx="880" cy="500" r="0"/>')
add("A8", "Endless loop", "A route drawn as an infinity loop: endurance, run after run. Half of it is done in bold.", endless)

def svg(f, mode="base", uid=""):
    bg, ink, soft, back = THEMES[mode]
    gid = f"g{uid}{mode}"
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><defs><radialGradient id="{gid}" cx="0.5" cy="0.3" r="0.8">'
            f'<stop offset="0" stop-color="{bg[0]}"/><stop offset="1" stop-color="{bg[1]}"/></radialGradient></defs>'
            f'<rect width="1024" height="1024" fill="url(#{gid})"/>{f(ink, soft, back)}</svg>')

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

tile = lambda bg, fg: f'<div class="icon s60 fake" style="background:{bg};display:grid;place-items:center"><div style="width:58%;height:58%;border-radius:30%;background:{fg}"></div></div>'
rivals = [tile("#fc4c02", "#fff"), tile("linear-gradient(135deg,#0f3b3a,#050b0b)", "#fff"), tile("#000", "#e2231a"),
          tile("#fff", "#d10a11"), tile("linear-gradient(#1a73c8,#8a9aa8)", "#1a73c8")]
shelf = "".join(f'<div class="homerow">{rivals[0]}{rivals[1]}<div class="icon s60">{svg(f, uid="h" + n)}</div>{rivals[2]}{rivals[3]}{rivals[4]}<span>{n}</span></div>'
                for n, _, _, f in V)

page = f'''<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>endurancr icons, round 4</title><style>{css}
.lead table{{border-collapse:collapse;font-size:.88rem;margin:10px 0}} .lead td{{padding:3px 12px 3px 0;vertical-align:top}}</style></head><body>
<header><h1>Running first</h1><div class="lead">
<p>This time I looked up the real App Store icons of 25 running and privacy apps. What I learned:</p>
<table>
<tr><td><b>Strava, COROS, Runna</b></td><td>The ones that read best: one bold mark filling about 60 to 75% of the square, on one strong colour.</td></tr>
<tr><td><b>Pacer, Garmin Connect</b></td><td>The ones that read worst: several objects, text, badges and 3D.</td></tr>
<tr><td><b>Nike Run Club, adidas</b></td><td>Use words, which only works with a famous brand.</td></tr>
<tr><td><b>Apple Workout, WorkOutDoors</b></td><td>Already use the running figure, and Apple Fitness has the rings. Both are taken.</td></tr>
<tr><td><b>Signal, Proton, DuckDuckGo</b></td><td>Privacy apps that show no lock or shield at all. They earn trust with calm colour and simple shapes.</td></tr>
<tr><td><b>Colour</b></td><td>Running apps use orange, red, blue, green and teal. Purple is free.</td></tr>
</table>
<p>So these ideas are about running only, on a deep purple background (Apple advises against a pale one), with one bold shape and nothing that belongs to someone else.
Apple's rules: at most four layers, no text, no shadows or gloss (iOS adds the glass), rounded bold shapes, and it must survive the watch circle.
Privacy is left to the colour and the words in the App Store. Only A3 hints at it.</p></div></header>
<main>{"".join(cards)}</main>
<h3>Next to the other running apps (Strava, Runna, COROS, Polar, Garmin)</h3><div class="home">{shelf}</div></body></html>'''
open("/tmp/icons/v2.html", "w").write(page)
