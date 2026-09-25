import math, html
BG = ("#f4eef8", "#dccbe8"); INK = "#3b1f4b"; MID = "#9a80ae"
DBG = ("#5a3a6e", "#241030"); DINK = "#f4eef8"; DHOLE = "#2b1638"

def keyhole(cx, cy, a, col, hole=None):
    """The mark that replaced the keyhole: a solid dot, you or the sun."""
    r = a if hole else a * 1.25
    return f'<circle cx="{cx}" cy="{cy}" r="{r:.1f}" fill="{col}"/>'

def st(d, w, col, op=1, cap="round"):
    return f'<path d="{d}" fill="none" stroke="{col}" stroke-width="{w}" stroke-linecap="{cap}" stroke-linejoin="round" opacity="{op}"/>'

def pt(cx, cy, r, deg): return (cx + r * math.cos(math.radians(deg)), cy + r * math.sin(math.radians(deg)))

def catmull(points, closed=False):
    P = points + points[:3] if closed else [points[0]] + points + [points[-1]]
    d = f"M{P[1][0]:.1f} {P[1][1]:.1f}" if closed else f"M{points[0][0]:.1f} {points[0][1]:.1f}"
    rng = range(1, len(P) - 2)
    for i in rng:
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d += f" C{c1[0]:.1f} {c1[1]:.1f} {c2[0]:.1f} {c2[1]:.1f} {p2[0]:.1f} {p2[1]:.1f}"
    return d

# Each concept: f(ink, bg_hole, soft) -> svg body. soft = the lighter ink used for secondary parts.
C = {}

def c1(i, h, s):  # Track
    return (f'<rect x="120" y="282" width="784" height="460" rx="230" fill="none" stroke="{i}" stroke-width="84"/>'
            f'<rect x="232" y="394" width="560" height="236" rx="118" fill="none" stroke="{s}" stroke-width="30"/>'
            + keyhole(512, 470, 46, i))
C["N1"] = ("The track", "A running track seen from above, filling the width. You are the dot in the infield.", c1)

def c2(i, h, s):  # Window
    clip = '<clipPath id="kw"><circle cx="512" cy="512" r="380"/></clipPath>'
    inner = (f'<rect width="1024" height="1024" fill="{i}"/>'
             f'<circle cx="512" cy="560" r="170" fill="{h}"/>'
             f'<rect x="0" y="560" width="1024" height="500" fill="{i}"/>'
             f'<path d="M250 640 H774" stroke="{h}" stroke-width="40" stroke-linecap="round" opacity=".7"/>'
             f'<path d="M330 730 H694" stroke="{h}" stroke-width="40" stroke-linecap="round" opacity=".45"/>'
             f'<path d="M420 820 H604" stroke="{h}" stroke-width="40" stroke-linecap="round" opacity=".25"/>')
    return f'<defs>{clip}</defs><g clip-path="url(#kw)">{inner}</g>'
C["N2"] = ("The window", "One big round window, and through it a sun rising over water.", c2)

def c3(i, h, s):  # Bold sunrise
    y = 610
    b = f'<path d="M232 {y} A280 280 0 0 1 792 {y} Z" fill="{i}"/>'
    b += st(f"M122 {y} A390 390 0 0 1 902 {y}", 56, s)
    b += st(f"M110 {y + 70} H914", 44, i)
    b += st(f"M230 {y + 160} H794", 44, s)
    b += st(f"M360 {y + 250} H664", 44, s, .6)
    return b
C["N3"] = ("Bold sunrise", "A solid half sun on the horizon, nothing cut out of it, one thick lane around it, the water below in three strokes.", c3)

def c4(i, h, s):  # Lane bend
    b = ""
    for r, op in ((330, 1), (500, .55), (670, .28)):
        b += st(f"M0 {1024 - r} A{r} {r} 0 0 1 {r} 1024", 92, i, op, "butt")
    b += keyhole(740, 280, 120, i, h)
    return b
C["N4"] = ("The bend", "Three lanes sweep round the bend from the corner. The dot is the sun ahead of you.", c4)

def c5(i, h, s):  # e as a track
    r = 300
    x1, y1 = pt(512, 512, r, 38)
    b = st(f"M812 512 A{r} {r} 0 1 0 {x1:.1f} {y1:.1f}", 104, i)
    b += st("M250 512 H812", 90, i)
    tx, ty = math.sin(math.radians(38)), -math.cos(math.radians(38))
    b += f'<circle cx="{x1 + 110 * tx:.1f}" cy="{y1 + 110 * ty:.1f}" r="52" fill="{s}"/>'
    return b
C["N5"] = ("The e", "The first letter, drawn like a lap: the bar is the finish line and the dot is you, just coming out of it.", c5)

def c6(i, h, s):  # Route loop
    pts = [(512, 150), (790, 230), (880, 480), (760, 760), (520, 870), (260, 800), (150, 560), (230, 300)]
    b = st(catmull(pts, closed=True), 70, s)
    part = [(230, 300), (512, 150), (790, 230), (880, 480), (760, 760)]
    b += st(catmull(part), 70, i)
    b += f'<circle cx="760" cy="760" r="62" fill="{i}"/>'
    b += keyhole(512, 470, 120, i, h)
    return b
C["N6"] = ("The loop", "Your route as one thick loop, half run, half ahead. The dot in the middle is you.", c6)

def c7(i, h, s):  # Sun over water
    bars = "".join(f'<rect x="0" y="{y}" width="1024" height="{w}" fill="black"/>' for y, w in ((600, 44), (690, 40), (770, 36)))
    mask = f'<mask id="kw"><rect width="1024" height="1024" fill="white"/>{bars}</mask>'
    return f'<defs>{mask}</defs><circle cx="512" cy="512" r="360" fill="{i}" mask="url(#kw)"/>'
C["N7"] = ("The sun, on the water", "One big disc, nothing else, its lower part broken by three lines of water. Bold like Headspace.", c7)

def c8(i, h, s):  # Pace dial
    r = 320
    a0, a1, a2 = 135, 330, 405
    p0, p1, p2 = pt(512, 540, r, a0), pt(512, 540, r, a1), pt(512, 540, r, a2)
    b = st(f"M{p0[0]:.1f} {p0[1]:.1f} A{r} {r} 0 1 1 {p2[0]:.1f} {p2[1]:.1f}", 96, s)
    b += st(f"M{p0[0]:.1f} {p0[1]:.1f} A{r} {r} 0 1 1 {p1[0]:.1f} {p1[1]:.1f}", 96, i)
    b += keyhole(512, 520, 130, i, h)
    return b
C["N8"] = ("The dial", "A thick ring, filled most of the way round, like a week that is going well. You are the dot at the centre.", c8)

def c9(i, h, s):  # Mirror, bold
    y = 560
    b = st(f"M172 {y} A340 340 0 0 1 852 {y}", 100, i)
    b += st(f"M852 {y} A340 340 0 0 1 172 {y}", 100, s, .55)
    b += st(f"M70 {y} H954", 38, i)
    b += keyhole(512, 420, 125, i, h)
    return b
C["N9"] = ("Mirror, bold", "Today's icon rebuilt thick: one heavy lane, its reflection, and the sun as a solid dot.", c9)

def c10(i, h, s):  # Striped sun
    clip = '<clipPath id="ss"><circle cx="512" cy="512" r="370"/></clipPath>'
    bars = ""
    y = 142
    for hgt, gap in ((290, 22), (86, 30), (66, 38), (50, 46), (36, 52), (24, 0)):
        bars += f'<rect x="0" y="{y}" width="1024" height="{hgt}" fill="{i}"/>'
        y += hgt + gap
    return f'<defs>{clip}</defs><g clip-path="url(#ss)">{bars}</g>'
C["N10"] = ("Striped sun", "A full sun, cut into lines that thin out as it sinks, like lanes seen from the stand.", c10)

def svg(key, dark=False, tinted=False, watch=False):
    _, _, f = C[key]
    if tinted:
        bg, ink, hole, soft = ("#111", "#111"), "#f2f2f2", "#111", "#8a8a8a"
    elif dark:
        bg, ink, hole, soft = DBG, DINK, DHOLE, "#9a80ae"
    else:
        bg, ink, hole, soft = BG, INK, BG[0], MID
    gid = f"g{key}{int(dark)}{int(tinted)}{int(watch)}"
    body = f(ink, hole, soft).replace('id="kw"', f'id="kw{gid}"').replace('url(#kw)', f'url(#kw{gid})') \
        .replace('id="ss"', f'id="ss{gid}"').replace('url(#ss)', f'url(#ss{gid})')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'
            f'<defs><radialGradient id="{gid}" cx="0.5" cy="0.34" r="0.72"><stop offset="0" stop-color="{bg[0]}"/>'
            f'<stop offset="1" stop-color="{bg[1]}"/></radialGradient></defs>'
            f'<rect width="1024" height="1024" fill="url(#{gid})"/>{body}</svg>')

rows = []
for k, (name, why, _) in C.items():
    light = svg(k)
    rows.append(f'''<article>
  <p class="num">{k}</p>
  <div class="big icon">{light}</div>
  <h2>{html.escape(name)}</h2><p class="why">{html.escape(why)}</p>
  <div class="tests">
    <figure><div class="icon s60">{light}</div><figcaption>Home screen</figcaption></figure>
    <figure><div class="icon s29">{light}</div><figcaption>Settings</figcaption></figure>
    <figure><div class="icon s60 blur">{light}</div><figcaption>Squint</figcaption></figure>
    <figure><div class="icon s60">{svg(k, dark=True)}</div><figcaption>Dark</figcaption></figure>
    <figure><div class="icon s60">{svg(k, tinted=True)}</div><figcaption>Tinted</figcaption></figure>
    <figure><div class="icon s60 watch">{light}</div><figcaption>Watch</figcaption></figure>
  </div>
</article>''')

others = ['<div class="icon s60 fake" style="background:linear-gradient(#fc5a2a,#e8340c)"></div>',
          '<div class="icon s60 fake" style="background:linear-gradient(#2fd36b,#0b9d45)"></div>',
          '<div class="icon s60 fake" style="background:linear-gradient(#3aa0ff,#1466e0)"></div>',
          '<div class="icon s60 fake" style="background:#111"></div>']
home = "".join(f'<div class="homerow">{others[0]}{others[1]}<div class="icon s60">{svg(k)}</div>{others[2]}{others[3]}<span>{k}</span></div>' for k in C)

page = f'''<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>endurancr icon ideas</title>
<style>
body{{margin:0;font:16px/1.45 -apple-system,system-ui,sans-serif;background:#f6f2f8;color:#241030}}
header{{padding:48px 40px 8px;max-width:1200px;margin:auto}} h1{{font-size:2.4rem;margin:0 0 8px}}
.lead{{max-width:760px;color:#5a4a66}} .lead li{{margin:4px 0}}
main{{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:28px;padding:24px 40px 40px;max-width:1200px;margin:auto}}
article{{background:#fff;border-radius:28px;padding:24px;box-shadow:0 10px 30px rgba(36,16,48,.08)}}
.num{{font-weight:700;color:#9a80ae;margin:0 0 10px}} h2{{margin:16px 0 4px;font-size:1.2rem}} .why{{margin:0;color:#5a4a66;font-size:.95rem}}
.icon svg{{display:block;width:100%;height:100%}} .icon{{overflow:hidden;border-radius:22.5%}}
.big{{width:200px;height:200px;box-shadow:0 18px 40px rgba(36,16,48,.25)}}
.tests{{display:flex;gap:10px;flex-wrap:wrap;margin-top:18px;align-items:flex-end}}
.tests figure{{margin:0;text-align:center;font-size:.72rem;color:#7a6a86}} .tests figcaption{{margin-top:4px}}
.s60{{width:60px;height:60px}} .s29{{width:29px;height:29px;margin:0 auto}} .blur{{filter:blur(3px)}} .watch{{border-radius:50%}}
.home{{background:linear-gradient(160deg,#4b6cb7,#182848);border-radius:32px;padding:26px;max-width:1120px;margin:0 auto 60px}}
.homerow{{display:flex;gap:22px;align-items:center;margin:10px 0}} .homerow span{{color:#fff;opacity:.7;font-weight:600}}
h3{{max-width:1200px;margin:10px auto;padding:0 40px}}
</style></head><body>
<header><h1>Ten new icon ideas</h1>
<div class="lead"><p>What I took from Apple's guidance and from icons that read well at a glance (Strava, Nike Run Club, Apple Fitness, Workout, Headspace):</p>
<ul><li>One bold shape that fills most of the square. The home screen shows it at 60 points, Settings at 29.</li>
<li>Thick strokes only. Thin lines vanish at small sizes, which is why today's icon looks small.</li>
<li>It should still be recognisable blurred, in dark, in tinted grey, and inside the watch circle.</li>
<li>No text, no baked-in shadows or gloss: iOS 26 adds the glass itself.</li></ul>
<p>Each card shows those tests under the large icon. Further down, every idea sits among other apps on a home screen.</p></div></header>
<main>{"".join(rows)}</main>
<h3>Among other apps</h3><div class="home">{home}</div>
</body></html>'''
open("/tmp/icons/index.html", "w").write(page)
