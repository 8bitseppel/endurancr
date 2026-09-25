import html, math, re, sys
sys.argv = ["x"]
import concepts as K  # reuses the helpers (and rewrites index.html, harmless)
from concepts import st, pt, catmull, BG, INK, MID, DBG, DINK, DHOLE

# ---- the marks -------------------------------------------------------------
def shield_d(cx, cy, a):
    return (f"M{cx} {cy - a} Q{cx + .45 * a} {cy - .72 * a} {cx + .85 * a} {cy - .72 * a} L{cx + .85 * a} {cy} "
            f"Q{cx + .85 * a} {cy + .62 * a} {cx} {cy + a} Q{cx - .85 * a} {cy + .62 * a} {cx - .85 * a} {cy} "
            f"L{cx - .85 * a} {cy - .72 * a} Q{cx - .45 * a} {cy - .72 * a} {cx} {cy - a} Z")

def house_d(cx, cy, a):
    return f"M{cx} {cy - a} L{cx + a} {cy - .12 * a} V{cy + a} H{cx - a} V{cy - .12 * a} Z"

def shield(cx, cy, a, col): return f'<path d="{shield_d(cx, cy, a)}" fill="{col}"/>'

def house(cx, cy, a, col):
    return f'<path d="{house_d(cx, cy, a)}" fill="{col}" stroke="{col}" stroke-width="{.14 * a:.1f}" stroke-linejoin="round"/>'

def padlock(cx, cy, a, col):
    w = .26 * a
    return (f'<rect x="{cx - .8 * a:.1f}" y="{cy - .12 * a:.1f}" width="{1.6 * a:.1f}" height="{1.12 * a:.1f}" rx="{.2 * a:.1f}" fill="{col}"/>'
            + st(f"M{cx - .48 * a:.1f} {cy - .1 * a:.1f} V{cy - .42 * a:.1f} A{.48 * a:.1f} {.48 * a:.1f} 0 0 1 {cx + .48 * a:.1f} {cy - .42 * a:.1f} V{cy - .1 * a:.1f}", w, col, 1, "butt"))

def key(cx, cy, a, col):
    w = .24 * a
    return (f'<circle cx="{cx - .5 * a:.1f}" cy="{cy}" r="{.36 * a:.1f}" fill="none" stroke="{col}" stroke-width="{w:.1f}"/>'
            + st(f"M{cx - .14 * a:.1f} {cy} H{cx + a:.1f}", w, col, 1, "butt")
            + st(f"M{cx + .62 * a:.1f} {cy} V{cy + .36 * a:.1f} M{cx + .9 * a:.1f} {cy} V{cy + .3 * a:.1f}", w, col, 1, "butt"))

def closed_eye(cx, cy, a, col):
    w = .2 * a
    b = st(f"M{cx - a} {cy - .1 * a} Q{cx} {cy + .75 * a} {cx + a} {cy - .1 * a}", w, col)
    for dx, dy in ((-.62, .32), (0, .45), (.62, .32)):
        b += st(f"M{cx + dx * a:.1f} {cy + dy * a:.1f} L{cx + dx * 1.2 * a:.1f} {cy + (dy + .38) * a:.1f}", w, col)
    return b

MARKS = [("Shield", "protection, safe from harm", shield),
         ("Padlock", "locked, secure, sealed", padlock),
         ("Key", "access, only you hold it", key),
         ("Closed eye", "private, nobody is watching", closed_eye),
         ("House", "local, it stays at home on your phone", house)]

# ---- logos with a mark ------------------------------------------------------
V = []
def add(num, name, why, f): V.append((num, name, why, f))

def water(i, h, y0, gap=90):
    return "".join(st(f"M{512 - w} {y0 + k * gap} H{512 + w}", 40, h, op) for k, (w, op) in enumerate(((260, .7), (180, .45), (90, .25))))

def s_window(shape):
    def f(i, h, s):
        d = shield_d(512, 520, 400) if shape == "shield" else house_d(512, 540, 380)
        inner = (f'<rect width="1024" height="1024" fill="{i}"/><circle cx="512" cy="600" r="160" fill="{h}"/>'
                 f'<rect x="0" y="600" width="1024" height="500" fill="{i}"/>' + water(i, h, 670))
        return f'<defs><clipPath id="kw"><path d="{d}"/></clipPath></defs><g clip-path="url(#kw)">{inner}</g>'
    return f
add("S1", "Shield window", "The window is a shield. Inside, the sun rises over water: protected, and yours.", s_window("shield"))
add("S2", "Home window", "The window is a house: your runs stay at home, on your phone. The sun rises inside.", s_window("house"))

def s_shield_water(i, h, s):
    bars = "".join(f'<rect x="0" y="{y}" width="1024" height="{w}" fill="black"/>' for y, w in ((610, 42), (700, 38), (782, 34)))
    return (f'<defs><mask id="kw"><rect width="1024" height="1024" fill="white"/>{bars}</mask></defs>'
            f'<path d="{shield_d(512, 520, 410)}" fill="{i}" mask="url(#kw)"/>')
add("S3", "Shield on the water", "N7 as a shield: one solid shape, its foot broken by three lines of water.", s_shield_water)

def s_sun_lock(i, h, s):
    bars = "".join(f'<rect x="0" y="{y}" width="1024" height="{w}" fill="black"/>' for y, w in ((650, 40), (730, 36), (802, 32)))
    return (st("M352 470 V330 A160 160 0 0 1 672 330 V470", 84, s, 1, "butt")
            + f'<defs><mask id="kw"><rect width="1024" height="1024" fill="white"/>{bars}</mask></defs>'
            f'<circle cx="512" cy="600" r="290" fill="{i}" mask="url(#kw)"/>')
add("S4", "The sun is a padlock", "The sun on the water, with a shackle over it: the whole icon is a lock.", s_sun_lock)

def s_dial_lock(i, h, s):
    return (st("M300 520 V400 A212 212 0 0 1 724 400 V520", 96, s, 1, "butt")
            + f'<rect x="200" y="470" width="624" height="420" rx="90" fill="{i}"/>'
            + f'<circle cx="512" cy="680" r="70" fill="{h}"/>')
add("S5", "Padlock, plain", "Just a big padlock, with a sun where the keyhole would be.", s_dial_lock)

def s_striped_shield(i, h, s):
    bars, y = "", 110
    for hgt, gap in ((300, 24), (90, 32), (70, 40), (54, 48), (40, 54), (40, 0)):
        bars += f'<rect x="0" y="{y}" width="1024" height="{hgt}" fill="{i}"/>'; y += hgt + gap
    return f'<defs><clipPath id="kw"><path d="{shield_d(512, 520, 410)}"/></clipPath></defs><g clip-path="url(#kw)">{bars}</g>'
add("S6", "Striped shield", "N10 as a shield: a sun cut into lines that thin out, like lanes and water.", s_striped_shield)

def s_track(markf, name, why):
    def f(i, h, s):
        return (f'<rect x="120" y="282" width="784" height="460" rx="230" fill="none" stroke="{i}" stroke-width="84"/>'
                f'<rect x="232" y="394" width="560" height="236" rx="118" fill="none" stroke="{s}" stroke-width="30"/>'
                + markf(512, 512, 80, i))
    return f
add("S7", "Track with a shield", "The running track from above, a shield in the infield.", s_track(shield, "", ""))
add("S8", "Track with a padlock", "The running track from above, a padlock in the infield.", s_track(padlock, "", ""))

def s_bend(markf, a=130):
    def f(i, h, s):
        b = "".join(st(f"M0 {1024 - r} A{r} {r} 0 0 1 {r} 1024", 92, i, op, "butt") for r, op in ((330, 1), (500, .55), (670, .28)))
        return b + markf(730, 290, a, i)
    return f
add("S9", "Bend and shield", "Lanes round the bend, heading for a shield.", s_bend(shield))
add("S10", "Bend and home", "Lanes round the bend, heading home: everything stays on your phone.", s_bend(house, 120))

def s_loop(markf, a):
    def f(i, h, s):
        pts = [(512, 150), (790, 230), (880, 480), (760, 760), (520, 870), (260, 800), (150, 560), (230, 300)]
        b = st(catmull(pts, closed=True), 70, s) + st(catmull([(230, 300), (512, 150), (790, 230), (880, 480), (760, 760)]), 70, i)
        return b + f'<circle cx="760" cy="760" r="62" fill="{i}"/>' + markf(512, 500, a, i)
    return f
add("S11", "Loop around a padlock", "Your route as one loop, closed around a padlock.", s_loop(padlock, 150))
add("S12", "Loop around a closed eye", "Your route loops around a closed eye: nobody is watching this run.", s_loop(closed_eye, 170))

def s_dial(markf, a):
    def f(i, h, s):
        r = 320; p0, p1, p2 = pt(512, 540, r, 135), pt(512, 540, r, 330), pt(512, 540, r, 405)
        return (st(f"M{p0[0]:.1f} {p0[1]:.1f} A{r} {r} 0 1 1 {p2[0]:.1f} {p2[1]:.1f}", 96, s)
                + st(f"M{p0[0]:.1f} {p0[1]:.1f} A{r} {r} 0 1 1 {p1[0]:.1f} {p1[1]:.1f}", 96, i) + markf(512, 530, a, i))
    return f
add("S13", "Dial and key", "A week that is going well, with a key at the centre: only you hold it.", s_dial(key, 150))
add("S14", "Dial and shield", "The weekly dial, with a shield at the centre.", s_dial(shield, 150))

def s_mirror(i, h, s):
    y = 580
    return (st(f"M172 {y} A340 340 0 0 1 852 {y}", 100, i) + st(f"M852 {y} A340 340 0 0 1 172 {y}", 100, s, .55)
            + st(f"M70 {y} H954", 38, i) + shield(512, 400, 130, i))
add("S15", "Mirror and shield", "The heavy lane and its reflection, with a shield rising where the sun was.", s_mirror)

def s_e(i, h, s):
    r = 300; x1, y1 = pt(512, 512, r, 38)
    return (st(f"M812 512 A{r} {r} 0 1 0 {x1:.1f} {y1:.1f}", 104, i) + st("M250 512 H812", 90, i)
            + shield(x1 + 60, y1 - 50, 70, s))
add("S16", "The e and a shield", "The e as a lap, and a small shield where it opens.", s_e)

# ---- page -------------------------------------------------------------------
def svg(f, dark=False, tinted=False, uid=""):
    if tinted: bg, ink, hole, soft = ("#111", "#111"), "#f2f2f2", "#111", "#8a8a8a"
    elif dark: bg, ink, hole, soft = DBG, DINK, DHOLE, "#9a80ae"
    else: bg, ink, hole, soft = BG, INK, BG[0], MID
    gid = f"g{uid}{int(dark)}{int(tinted)}"
    body = f(ink, hole, soft).replace('id="kw"', f'id="kw{gid}"').replace('url(#kw)', f'url(#kw{gid})')
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><defs><radialGradient id="{gid}" cx="0.5" cy="0.34" r="0.72">'
            f'<stop offset="0" stop-color="{bg[0]}"/><stop offset="1" stop-color="{bg[1]}"/></radialGradient></defs>'
            f'<rect width="1024" height="1024" fill="url(#{gid})"/>{body}</svg>')

css = re.search(r"<style>(.*?)</style>", open("/tmp/icons/index.html").read(), re.S).group(1)
marks = "".join(f'<figure class="mark"><div class="icon s96">{svg(lambda i, h, s, m=m: m(512, 512, 330, i), uid="m" + str(k))}</div>'
                f'<figcaption><b>{n}</b>{html.escape(w)}</figcaption></figure>' for k, (n, w, m) in enumerate(MARKS))
cards = []
for num, name, why, f in V:
    L = svg(f, uid=num)
    cards.append(f'''<article><p class="num">{num}</p><div class="big icon">{L}</div>
<h2>{html.escape(name)}</h2><p class="why">{html.escape(why)}</p><div class="tests">
<figure><div class="icon s60">{L}</div><figcaption>Home screen</figcaption></figure>
<figure><div class="icon s29">{L}</div><figcaption>Settings</figcaption></figure>
<figure><div class="icon s60 blur">{L}</div><figcaption>Squint</figcaption></figure>
<figure><div class="icon s60">{svg(f, dark=True, uid=num)}</div><figcaption>Dark</figcaption></figure>
<figure><div class="icon s60">{svg(f, tinted=True, uid=num)}</div><figcaption>Tinted</figcaption></figure>
<figure><div class="icon s60 watch">{L}</div><figcaption>Watch</figcaption></figure></div></article>''')
page = f'''<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8"><title>endurancr icons with protection</title><style>{css}
.marks{{display:flex;gap:26px;flex-wrap:wrap;max-width:1120px;margin:10px auto 0;padding:0 40px}} .mark{{margin:0;width:190px}}
.mark figcaption{{font-size:.9rem;color:#5a4a66;margin-top:8px}} .mark b{{display:block;color:#241030}} .s96{{width:96px;height:96px}}</style></head><body>
<header><h1>Protection, without the keyhole</h1><div class="lead">
<p>Other words for security, and the mark I drew for each. They are all solid and thick, so they still read on the home screen.</p></div></header>
<div class="marks">{marks}</div>
<header><h1 style="font-size:1.8rem;margin-top:30px">The logos, with a mark</h1><div class="lead">
<p>Where it works, the mark became the shape of the whole icon (S1 to S6) rather than a small badge. Each card has the same tests as before.</p></div></header>
<main>{"".join(cards)}</main></body></html>'''
open("/tmp/icons/secure.html", "w").write(page)
