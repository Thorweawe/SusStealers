"""
Reklam ve oyun sayfası kapakları — 2. set (2026-10-01).

    python tools/thumbnails_v2.py            ->  thumbnails/v2/*.png (1920x1080) + _preview.png
    python tools/thumbnails_v2.py chomp      ->  yalnızca bir sahne

Neden yeni set (Ads Manager, 28 gün):
  - Parlak 2D çizgi film kapaklar (ilk kampanyalar) %2.4-2.8 tıklanma aldı,
    koyu mor/mavi 3D uzay çekimleri %1.3-1.8. Roblox'un koyu arayüzünde koyu
    görsel kayboluyor -> hepsi PARLAK ve DOYGUN renkli.
  - Ama eski 2D setin sahneleri (dev sarı kafa, dev uyuyan mürettebat) artık
    oyunda yok. Yeni set ŞİMDİKİ temada: uzay, gezegenler, oyundaki canavarlar
    (pembe Chomper, Nebula Kraken), gezegen gezegen büyüyen ödül, STARFALL.
  - Reklam telefonda küçük görünüyor: tek odak, dev nesne, en fazla 2-3 kelime.

Çizim araçları tools/thumbnails.py'den (aynı stil ve kalite).
"""

import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import thumbnails as T  # noqa: E402
from thumbnails import (  # noqa: E402
    OUT, W, H, Sprite, arrow, aura, avatar, blank, crewmate, ell, exclaim, gold_fill,
    ground_shadow, mask, money_fill, place, planet, poly, put_text, rainbow_fill, rainbow_tex, rrect, seg, solid,
    sparkle, speed_lines, stars, text_art, vgrad, vignette, zzz, nebula, dim, lit,
)

DEST = os.path.join(T.ROOT, "thumbnails", "v2")


# ─── Pembe Chomper (oyundaki 2. canavar) ────────────────────────────────


def chomper(h, col=(255, 92, 176)):
    """Sağa bakan, ağzı kocaman açık pembe top canavar. Döner: (img, bilgi)."""
    sw, sh = int(h * 1.55), int(h * 1.45)
    s = Sprite(sw, sh, max(6, h * 0.016))
    cx, cy, R = h * 0.7, h * 0.82, h * 0.55
    horn = (255, 205, 60)
    for bx, lean in ((cx - 0.28 * h, -1), (cx + 0.12 * h, 1)):
        m = s.m()
        for i in range(31):
            t = i / 30
            x = bx + lean * math.sin(t * 1.6) * 0.16 * h
            y = cy - R * 0.72 - t * 0.42 * h
            r = (1 - t) * 0.1 * h + 0.018 * h
            ell(m, (x - r, y - r, x + r, y + r))
        s.put(m, horn, light=(0.35, 0.1), hi=0.55)
    for fx in (cx - 0.3 * h, cx + 0.18 * h):
        s.put(ell(s.m(), (fx - 0.14 * h, cy + R * 0.8, fx + 0.14 * h, cy + R * 1.08)), dim(col, 0.1), light=(0.3, 0.1))
    body = ell(s.m(), (cx - R, cy - R, cx + R, cy + R))
    s.put(body, col, light=(0.3, 0.2), hi=0.5, lo=0.45)
    s.soft((cx - R * 0.75, cy - R * 0.8, cx - R * 0.15, cy - R * 0.35), alpha=150, clip=body)
    s.put(ell(s.m(), (cx - R * 0.8, cy + R * 0.05, cx + R * 0.2, cy + R * 0.92)), lit(col, 0.45), ow=0, light=(0.3, 0.1), hi=0.3)
    mx0, my0, mx1, my1 = cx - R * 0.05, cy - R * 0.42, cx + R * 1.08, cy + R * 0.55
    s.put(ell(s.m(), (mx0, my0, mx1, my1)), (120, 10, 40), light=(0.5, 0.8), hi=0.15, lo=0.3)
    s.put(ell(s.m(), (mx0 + R * 0.2, my1 - R * 0.42, mx1 - R * 0.25, my1 - R * 0.02)), (255, 110, 150), ow=s.ow * 0.6, light=(0.3, 0.1))
    mcx, mcy = (mx0 + mx1) / 2, (my0 + my1) / 2
    rx, ry = (mx1 - mx0) / 2, (my1 - my0) / 2
    tooth = s.m()
    for k in range(7):
        a = math.radians(200 + k * 22)
        bx, by = mcx + math.cos(a) * rx * 0.97, mcy + math.sin(a) * ry * 0.97
        tw = 0.085 * h
        poly(tooth, [(bx - tw / 2, by - 4), (bx + tw / 2, by - 4), (bx, by + 0.14 * h)])
    for k in range(5):
        a = math.radians(35 + k * 27)
        bx, by = mcx + math.cos(a) * rx * 0.95, mcy + math.sin(a) * ry * 0.95
        tw = 0.075 * h
        poly(tooth, [(bx - tw / 2, by + 4), (bx + tw / 2, by + 4), (bx, by - 0.12 * h)])
    s.put(tooth, (255, 255, 250), ow=s.ow * 0.6, light=(0.3, 0.1), hi=0.3)
    eyes = ((cx - 0.12 * h, cy - R * 1.28, 0.13 * h), (cx + 0.18 * h, cy - R * 1.2, 0.11 * h), (cx - 0.4 * h, cy - R * 1.02, 0.09 * h))
    for ex, ey, er in eyes:
        s.put(seg(s.m(), (ex, ey + er * 0.5), (cx + (ex - cx) * 0.4, cy - R * 0.7), 0.045 * h, ext=0), dim(col, 0.05), light=(0.3, 0.1))
    for ex, ey, er in eyes:
        s.put(ell(s.m(), (ex - er, ey - er, ex + er, ey + er)), (255, 255, 255), light=(0.3, 0.2), hi=0.4, lo=0.3)
        pr = er * 0.5
        px, py = ex + er * 0.35, ey + er * 0.25
        s.put(ell(s.m(), (px - pr, py - pr, px + pr, py + pr)), (25, 20, 35), ow=0, flat=True)
        s.put(ell(s.m(), (px - pr * 0.1, py - pr * 0.75, px + pr * 0.5, py - pr * 0.15)), (255, 255, 255), ow=0, flat=True)
    ex, ey, er = eyes[0]
    s.put(seg(s.m(), (ex - er * 1.1, ey - er * 1.25), (ex + er * 1.05, ey - er * 0.7), 0.05 * h, ext=0.2), (120, 20, 70), light=(0.3, 0.1))
    return s.img, {"feet": (cx, cy + R * 1.05), "mouth": (mx1 - R * 0.1, mcy), "top": (cx, cy - R * 1.6)}


# ─── Nebula Kraken (oyundaki 3. canavar) ─────────────────────────────────


def kraken(h, col=(175, 95, 255), sleepy=True):
    """Mor ahtapot: yuvarlak kafa, altı kıvrık dokunaç. Döner: (img, bilgi)."""
    sw, sh = int(h * 1.9), int(h * 1.35)
    s = Sprite(sw, sh, max(6, h * 0.016))
    cx, cy, R = sw / 2, h * 0.5, h * 0.42
    tip = lit(col, 0.35)
    for ex, lift in ((-0.85, 0.1), (-0.55, 0.3), (-0.2, 0.42), (0.2, 0.42), (0.55, 0.3), (0.85, 0.1)):
        p0 = (cx + ex * R * 0.5, cy + R * 0.55)
        p3 = (cx + ex * h * 0.92, cy + R * 0.55 + lift * h * 0.75)
        p1 = (cx + ex * R * 0.9, cy + R * 1.4)
        p2 = (p3[0] - ex * h * 0.05, p3[1] - h * 0.35)
        pts = T.bezier(p0, p1, p2, p3, 50)
        m = s.m()
        for i, (x, y) in enumerate(pts):
            rr = h * (0.11 - 0.075 * i / len(pts))
            ell(m, (x - rr, y - rr, x + rr, y + rr))
        s.put(m, col, light=(0.3, 0.15), hi=0.45, lo=0.45)
        cups = s.m()
        for i in range(8, len(pts) - 4, 7):
            x, y = pts[i]
            rr = h * (0.035 - 0.02 * i / len(pts))
            ell(cups, (x - rr, y - rr + h * 0.03, x + rr, y + rr + h * 0.03))
        s.put(cups, tip, ow=0, light=(0.3, 0.1), hi=0.3)
    head = ell(s.m(), (cx - R, cy - R * 1.15, cx + R, cy + R * 0.85))
    s.put(head, col, light=(0.3, 0.2), hi=0.5, lo=0.45)
    s.soft((cx - R * 0.65, cy - R * 1.0, cx - R * 0.05, cy - R * 0.45), alpha=150, clip=head)
    for bx, by, br in ((0.35, -0.6, 0.12), (0.55, -0.2, 0.08), (-0.5, -0.1, 0.07)):
        s.put(ell(s.m(), (cx + (bx - br) * R, cy + (by - br) * R, cx + (bx + br) * R, cy + (by + br) * R)), lit(col, 0.3), ow=0, flat=True)
    ey = cy + R * 0.05
    for ex in (cx - R * 0.42, cx + R * 0.42):
        er = R * 0.3
        if sleepy:
            # kapalı göz: göz kapağı yarım daire + kirpik çizgisi
            s.put(ell(s.m(), (ex - er, ey - er, ex + er, ey + er)), (230, 245, 255), light=(0.3, 0.2), hi=0.3)
            lid = ell(s.m(), (ex - er * 1.05, ey - er * 1.05, ex + er * 1.05, ey + er * 1.05))
            lid.paste(0, (0, int(ey + er * 0.1), s.size[0], s.size[1]))
            s.put(lid, dim(col, 0.12), ow=s.ow * 0.6, light=(0.3, 0.1))
            ImageDraw.Draw(s.img).line([(ex - er * 0.9, ey + er * 0.1), (ex + er * 0.9, ey + er * 0.1)], fill=OUT, width=int(R * 0.07))
        else:
            s.put(ell(s.m(), (ex - er, ey - er, ex + er, ey + er)), (255, 255, 255), light=(0.3, 0.2), hi=0.3)
            s.put(ell(s.m(), (ex - er * 0.45, ey - er * 0.45, ex + er * 0.45, ey + er * 0.45)), OUT, ow=0, flat=True)
    feet_y = cy + R * 0.55 + 0.42 * h * 0.75 + h * 0.08
    return s.img, {"feet": (cx, feet_y), "top": (cx, cy - R * 1.15), "head": (cx, cy)}


# ─── Yardımcılar ─────────────────────────────────────────────────────────


def space_bg(top, bottom, blobs, glow_at, glow=(255, 255, 255), glow_r=900, seed=7, n_stars=480):
    """PARLAK uzay: doygun degrade, renkli bulutsu, yıldızlar, ışık patlaması
    (koyu uzay reklam listesinde kayboluyordu; parlak olan öne çıkıyor)."""
    c = vgrad((W, H), [(0, top), (1, bottom)]).convert("RGBA")
    nebula(c, blobs)
    g = mask(W, H)
    ImageDraw.Draw(g).ellipse((glow_at[0] - glow_r, glow_at[1] - glow_r, glow_at[0] + glow_r, glow_at[1] + glow_r), fill=190)
    c.alpha_composite(solid((W, H), glow, g.filter(ImageFilter.GaussianBlur(glow_r * 0.45))))
    stars(c, n_stars, seed, (0, 0, W, H * 0.8))
    return c


def planet_ground(canvas, y, top_col, bottom_col, seed=4, rim=(255, 255, 255)):
    """Ayakların altında bir gezegenin kavisli, kraterli yüzeyi."""
    m = mask(W, H)
    ImageDraw.Draw(m).ellipse((-W * 0.35, y, W * 1.35, y + W * 1.1), fill=255)
    fill = vgrad((W, H), [(0, top_col), (y / H, top_col), (1, bottom_col)]).convert("RGBA")
    fill.putalpha(m)
    canvas.alpha_composite(fill)
    edge = ImageChops.subtract(m, T.shift(m, 0, 22))
    canvas.alpha_composite(solid((W, H), rim, edge.point(lambda v: int(v * 0.6)).filter(ImageFilter.GaussianBlur(6))))
    rng = random.Random(seed)
    d = blank(W, H)
    dd = ImageDraw.Draw(d)
    for _ in range(10):
        x = rng.uniform(0, W)
        yy = rng.uniform(y + 90, H - 40)
        rx = rng.uniform(80, 220) * (0.6 + (yy - y) / H)
        dd.ellipse((x - rx, yy - rx * 0.28, x + rx, yy + rx * 0.28), fill=dim(bottom_col, 0.25) + (150,))
        dd.ellipse((x - rx * 0.8, yy - rx * 0.24, x + rx * 0.8, yy + rx * 0.12), fill=dim(bottom_col, 0.4) + (120,))
    d.putalpha(ImageChops.multiply(d.getchannel("A"), m))
    canvas.alpha_composite(d)


def shooting_star(canvas, head, direction, length, width, col):
    """Kuyruklu kayan yıldız: parlak baş, sönen geniş kuyruk."""
    dx, dy = direction
    L = math.hypot(dx, dy)
    ux, uy = dx / L, dy / L
    m = mask(W, H)
    d = ImageDraw.Draw(m)
    n = 40
    for i in range(n):
        t = i / n
        x, y = head[0] - ux * length * t, head[1] - uy * length * t
        r = width * (1 - t) ** 1.3
        d.ellipse((x - r, y - r, x + r, y + r), fill=int(230 * (1 - t) ** 1.5))
    canvas.alpha_composite(solid((W, H), col, m.filter(ImageFilter.GaussianBlur(width * 0.5))))
    canvas.alpha_composite(solid((W, H), (255, 255, 255), m.point(lambda v: int(v * 0.7)).filter(ImageFilter.GaussianBlur(width * 0.15))))
    sparkle(canvas, head[0], head[1], width * 1.6, col)


def ribbon(canvas, txt, center, size, angle, col=(235, 40, 50)):
    """Rozet şerit (NEW EVENT! gibi): kalın konturlu renkli dikdörtgen üstünde yazı."""
    t = text_art(txt, size, fill=(255, 255, 255), stroke=dim(col, 0.55), sw=0.1, extrude=0.05)
    pw, ph = t.width + size * 0.9, t.height + size * 0.35
    s = Sprite(pw + 40, ph + 40, max(8, size * 0.07))
    s.put(rrect(s.m(), (20, 20, pw + 20, ph + 20), size * 0.25), col, light=(0.3, 0.1), hi=0.4, lo=0.35)
    s.img.alpha_composite(t, (int((pw + 40 - t.width) / 2), int((ph + 40 - t.height) / 2)))
    place(canvas, s.img, (s.size[0] / 2, s.size[1] / 2), center, angle=angle, shadow=90)


def star_crewmate(h):
    """STARBORN mürettebat: açık mavi, üstünde yıldız benekleri, sarı vizör."""
    tex = Image.new("RGBA", (1000, 1000), (150, 215, 255, 255))
    d = ImageDraw.Draw(tex)
    rng = random.Random(5)
    for _ in range(70):
        x, y, r = rng.uniform(0, 1000), rng.uniform(0, 1000), rng.choice([6, 9, 12, 16])
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, 255))
    for _ in range(12):
        x, y = rng.uniform(80, 920), rng.uniform(80, 920)
        d.polygon(T.star_pts(x, y, 40, n=4, inner=0.3), fill=(255, 250, 200, 255))
    return crewmate(h, (150, 215, 255), face=1, tex=tex.filter(ImageFilter.GaussianBlur(1.5)), visor_col=(255, 245, 190))


def pill(canvas, txt, center, size):
    """Siyah yuvarlak hap üstünde beyaz yazı (sosyal medya "POV:" görünümü)."""
    t = text_art(txt, size, fill=(255, 255, 255), stroke=(0, 0, 0), sw=0.05, extrude=0.0, gloss=False)
    pw, ph = t.width + size * 0.8, t.height + size * 0.3
    s = Sprite(pw + 30, ph + 30, 6)
    s.put(rrect(s.m(), (15, 15, pw + 15, ph + 15), ph / 2), (15, 15, 20), flat=True, ocol=(255, 255, 255))
    s.img.alpha_composite(t, (int((pw + 30 - t.width) / 2), int((ph + 30 - t.height) / 2)))
    place(canvas, s.img, (s.size[0] / 2, s.size[1] / 2), center, angle=-4, shadow=80)


# ─── Sahneler ────────────────────────────────────────────────────────────


def scene_chomp(face="cry", headline="secret"):
    """Pembe Chomper ağzını açmış, sen gökkuşağı SECRET mürettebatla kaçıyorsun.

    face: "cry" (panik) / "smug" (kendinden emin — 16+ kitle için)
    headline: "secret" (SECRET! + $/s) / "pov" (POV: meme formatı) / "worth" (WORTH IT? risk sorusu)
    """
    c = space_bg((110, 40, 200), (255, 120, 200), [(700, 500, 800, (255, 90, 200), 130), (3200, 300, 700, (120, 170, 255), 120),
                                                  (2900, 1000, 800, (255, 200, 120), 110)], (2950, 900), glow=(255, 240, 200), glow_r=1050)
    speed_lines(c, (2950, 900), 55, seed=3, alpha=110)
    planet(c, 1950, 1250, 110, (120, 220, 255), ring=(255, 255, 255))
    planet_ground(c, 1640, (255, 150, 205), (170, 60, 150))

    mon, mi = chomper(1500)
    ground_shadow(c, 1050, 2080, 900, 120)
    place(c, mon, mi["feet"], (1080, 2150), angle=-10, rim=((255, 255, 255), 12))

    held = crewmate(820, (255, 255, 255), tex=rainbow_tex((1000, 1000)), face=1)
    av, ai = avatar(245, "run", face, held=held, look=1)
    ground_shadow(c, 3000, 2090, 560, 85)
    ta = place(c, av, ai["feet"], (3000, 2110), angle=-6, rim=((255, 255, 255), 10), under=aura(c, ai, (255, 250, 170), k=1.2, alpha=220))
    hc = ta(ai["held"])
    for dx, dy, r in ((-480, -330, 80), (460, -300, 65), (470, 230, 50), (-430, 280, 45), (0, -520, 40)):
        sparkle(c, hc[0] + dx, hc[1] + dy, r, (255, 240, 120))

    exclaim(c, 330, 420, 400, angle=-10)
    if headline == "pov":
        # TikTok'un "POV:" kalıbı: siyah hap üstünde beyaz, altında dev SECRET
        pill(c, "POV: YOU STOLE A", (2750, 170), 120)
        put_text(c, "SECRET!", (2750, 400), 300, angle=-4, fill=rainbow_fill())
        put_text(c, "$1.2B/s", (2250, 640), 160, angle=-4, fill=money_fill(), stroke=(10, 70, 20))
    elif headline == "worth":
        put_text(c, "WORTH IT?", (2700, 230), 290, angle=-4, fill=(255, 255, 255), stroke=(180, 20, 60))
        put_text(c, "$1.2B/s", (2750, 480), 200, angle=-4, fill=money_fill(), stroke=(10, 70, 20))
    else:
        put_text(c, "SECRET!", (2750, 230), 310, angle=-4, fill=rainbow_fill())
        put_text(c, "$1.2B/s", (2750, 470), 190, angle=-4, fill=money_fill(), stroke=(10, 70, 20))
    vignette(c, 40)
    return c


def scene_starfall():
    """STARFALL etkinliği: yıldızlar yağıyor, sen dev STARBORN mürettebatı kaldırıyorsun."""
    c = space_bg((20, 50, 160), (110, 200, 255), [(700, 400, 700, (160, 90, 255), 120), (3300, 350, 650, (80, 200, 255), 120),
                                                 (2600, 900, 800, (255, 255, 255), 70)], (2650, 800), glow=(220, 245, 255), glow_r=900, seed=17)
    planet(c, 3550, 300, 170, (255, 190, 90), ring=(255, 235, 180))
    for head, dirv, ln, wd in (((1450, 1180), (1, 1.1), 900, 60), ((2150, 480), (1, 1.2), 700, 42), ((3350, 1000), (1, 1.15), 650, 38),
                               ((700, 1450), (1, 1.2), 600, 34), ((3750, 700), (1, 1.3), 420, 26)):
        shooting_star(c, head, dirv, ln, wd, (140, 220, 255))
    planet_ground(c, 1700, (150, 205, 255), (60, 100, 210), seed=8)
    # yere düşmüş dev yıldız (sol alt): parlayan krater + ışıltılar
    g = mask(W, H)
    ImageDraw.Draw(g).ellipse((600, 1380, 1700, 1980), fill=200)
    c.alpha_composite(solid((W, H), (190, 235, 255), g.filter(ImageFilter.GaussianBlur(160))))
    st = Sprite(700, 700, 12)
    st.put(poly(st.m(), T.star_pts(350, 350, 320, n=5, inner=0.5)), (255, 225, 90), light=(0.3, 0.2), hi=0.55, lo=0.35)
    place(c, st.img, (350, 600), (1150, 1840), angle=-14, rim=((255, 255, 255), 12))
    for x, y, r in ((700, 1450, 60), (1600, 1380, 55), (1500, 1900, 40), (820, 1880, 45)):
        sparkle(c, x, y, r, (255, 240, 150))

    held = star_crewmate(760)
    av, ai = avatar(180, "lift", "smug", held=held, look=1)
    ground_shadow(c, 2650, 2090, 520, 80)
    ta = place(c, av, ai["feet"], (2650, 2110), angle=3, rim=((255, 255, 255), 10), under=aura(c, ai, (190, 235, 255), k=1.3, alpha=240))
    hc = ta(ai["held"])
    for dx, dy, r in ((-600, -200, 85), (580, -330, 70), (640, 230, 55), (-560, 330, 55), (0, -560, 50)):
        sparkle(c, hc[0] + dx, hc[1] + dy, r, (200, 240, 255))

    ribbon(c, "NEW EVENT!", (900, 300), 150, angle=-6)
    put_text(c, "STARFALL", (1000, 620), 300, angle=-6, fill=gold_fill(), stroke=(110, 60, 0))
    put_text(c, "LIMITED!", (1000, 900), 150, angle=-6, fill=(255, 255, 255), stroke=(200, 30, 60))
    vignette(c, 35)
    return c


def scene_planets():
    """Gezegen gezegen büyüyen ödül (oyundaki ilerleme): her gezegende daha nadir mürettebat."""
    c = space_bg((20, 90, 210), (90, 200, 255), [(600, 600, 700, (120, 90, 255), 120), (3300, 500, 800, (80, 230, 255), 110),
                                                (2000, 300, 700, (255, 150, 240), 90)], (3300, 800), glow=(255, 255, 230), glow_r=1000, seed=21)
    steps = [
        (430, 1900, 190, (120, 230, 120), 280, (190, 196, 210), "$10/s", 120),
        (1180, 1760, 250, (255, 140, 200), 380, (70, 210, 90), "$900/s", 135),
        (1960, 1600, 310, (130, 190, 255), 490, (70, 150, 255), "$50K/s", 150),
        (2750, 1430, 370, (255, 190, 90), 600, (255, 200, 40), "$8M/s", 170),
    ]
    for x, gy, pr, pcol, hgt, col, label, ts in steps:
        planet(c, x, gy + pr * 0.92, pr, pcol)
        cm, ci = crewmate(hgt, col, face=1)
        place(c, cm, ci["feet"], (x, gy + 20), rim=((255, 255, 255), 8))
        put_text(c, label, (x, gy - hgt - 70), ts, angle=-3, fill=money_fill(), stroke=(10, 70, 20))
    planet(c, 3480, 1900, 470, (190, 110, 255), ring=(255, 230, 170))
    held = crewmate(430, (255, 255, 255), tex=rainbow_tex((1000, 1000)), face=-1)
    av, ai = avatar(128, "lift", "smug", held=held, look=-1)
    ta = place(c, av, ai["feet"], (3480, 1470), rim=((255, 255, 255), 9), under=aura(c, ai, (255, 250, 170), k=1.3, alpha=240))
    hc = ta(ai["held"])
    for dx, dy, r in ((-420, -150, 65), (400, -280, 55), (-400, 230, 45), (420, 220, 45)):
        sparkle(c, hc[0] + dx, hc[1] + dy, r, (255, 240, 120))
    put_text(c, "$1B/s", (3300, 190), 230, angle=-4, fill=money_fill(), stroke=(10, 70, 20))
    arrow(c, (330, 1300), (2250, 560), -330, 140, col=(60, 210, 70))
    vignette(c, 35)
    return c


def scene_kraken(hush="SHHH..."):
    """Uyuyan Nebula Kraken'in dibinden GOLDEN mürettebatı aşırmak (sessiz ol!)."""
    c = space_bg((20, 140, 210), (70, 225, 205), [(900, 500, 800, (120, 255, 200), 120), (3000, 400, 800, (170, 110, 255), 130),
                                                 (2200, 1100, 700, (255, 255, 255), 60)], (1000, 900), glow=(240, 255, 220), glow_r=950, seed=31)
    planet(c, 1900, 420, 110, (255, 170, 90), ring=(255, 235, 180))
    planet_ground(c, 1660, (130, 160, 255), (70, 60, 190), seed=12)

    big, bi = kraken(1400, sleepy=True)
    ground_shadow(c, 2700, 2060, 1000, 120)
    tb = place(c, big, bi["feet"], (2720, 2150), angle=2, rim=((255, 255, 255), 12))
    t = tb(bi["top"])
    zzz(c, t[0] + 330, t[1] + 180, 220)

    held = crewmate(760, (255, 200, 40), face=1)
    av, ai = avatar(245, "run", "smug", held=held, look=1)
    av = av.transpose(Image.FLIP_LEFT_RIGHT)
    flipx = lambda p: (av.width - p[0], p[1])  # noqa: E731
    ground_shadow(c, 950, 2060, 540, 85)
    ta = place(c, av, flipx(ai["feet"]), (950, 2080), angle=5, rim=((255, 255, 255), 10),
               under=aura(c, {"held": flipx(ai["held"]), "held_r": ai["held_r"]}, (255, 230, 90), k=1.2, alpha=230))
    hc = ta(flipx(ai["held"]))
    for dx, dy, r in ((-420, -300, 70), (420, -330, 60), (-420, 230, 45), (440, 200, 50)):
        sparkle(c, hc[0] + dx, hc[1] + dy, r, (255, 225, 90))
    put_text(c, hush, (950, 250), 250, angle=6, fill=(255, 255, 255), stroke=(20, 60, 120))
    put_text(c, "GOLDEN!", (2650, 200), 250, angle=-4, fill=gold_fill(), stroke=(110, 60, 0))
    vignette(c, 40)
    return c


SCENES = [
    ("1_chomp", scene_chomp), ("2_starfall", scene_starfall), ("3_planets", scene_planets), ("4_kraken", scene_kraken),
    # 16+ kitle (reklam yalnızca 16+'ya gösteriliyor): çocuksu panik yerine özgüven,
    # meme dili (POV, SUS) ve risk sorusu. A/B için aynı sahnenin varyantları.
    ("5_pov", lambda: scene_chomp("smug", "pov")),
    ("6_worthit", lambda: scene_chomp("smug", "worth")),
    ("7_sus", lambda: scene_kraken("SUS...")),
]


def main(only=None):
    os.makedirs(DEST, exist_ok=True)
    for f in os.listdir(DEST):
        if f.startswith("thumb_") and not only:
            os.remove(os.path.join(DEST, f))
    outs = []
    for name, fn in SCENES:
        if only and name.split("_", 1)[1] not in only:
            continue
        img = fn().convert("RGB").resize((1920, 1080), Image.LANCZOS)
        img.save(os.path.join(DEST, "thumb_" + name + ".png"))
        outs.append(img)
        print("ok", name)
    if not only:
        prev = Image.new("RGB", (1920, 1080), (20, 20, 30))
        for i, im in enumerate(outs):
            prev.paste(im.resize((960, 540), Image.LANCZOS), ((i % 2) * 960, (i // 2) * 540))
        prev.save(os.path.join(DEST, "_preview.png"))


if __name__ == "__main__":
    main(sys.argv[1:])
