"""
Roblox mağaza ikonları (gamepass + developer product), 512x512 PNG.

    python tools/store_icons.py      ->  store_icons/*.png

Oyun içindeki dükkân ikonlarını kendisi çiziyor; bunlar yalnızca Roblox'un
satın alma penceresinde ve oyun sayfasının Store bölümünde görünüyor.
Pass ikonları Roblox'ta DAİRE olarak kırpılıyor: her şey ortadaki dairenin
içinde tutuldu. 4 kat büyük çizilip küçültülüyor (kenarlar yumuşak olsun).
Gerekenler: pip install pillow
"""

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 4
W = 512 * S
OUT = (22, 20, 34)
LW = 6 * S
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(ROOT, "store_icons")
FONT = "C:/Windows/Fonts/ariblk.ttf"


def p(*v):
    return [x * S for x in v]


def shade(c, k):
    return tuple(max(0, min(255, int(x * k))) for x in c[:3])


# ─── Katmanlar ────────────────────────────────────────────────────────────


def background(light, dark, seed):
    grad = Image.radial_gradient("L").resize((W, W), Image.BICUBIC)
    base = Image.composite(Image.new("RGB", (W, W), dark), Image.new("RGB", (W, W), light), grad).convert("RGBA")
    rays = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(rays)
    c = W / 2
    n = 18
    for i in range(n):
        a0 = (i / n) * math.tau
        a1 = a0 + math.tau / n / 2
        d.polygon([(c, c), (c + math.cos(a0) * W, c + math.sin(a0) * W), (c + math.cos(a1) * W, c + math.sin(a1) * W)],
                  fill=(255, 255, 255, 20))
    rng = random.Random(seed)
    for _ in range(40):
        x, y, r = rng.uniform(0, W), rng.uniform(0, W), rng.uniform(1.2, 3.2) * S
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, rng.randint(60, 160)))
    return Image.alpha_composite(base, rays)


def dilate(mask, r):
    return mask.filter(ImageFilter.GaussianBlur(r)).point(lambda v: 255 if v > 10 else 0)


def stamp(canvas, art, outline=5.5):
    """Sanat katmanını kalın dış kontur ve gölgeyle bas."""
    edge = dilate(art.split()[3], outline * S).filter(ImageFilter.GaussianBlur(0.6 * S))
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 120), (0, 10 * S), edge)
    shadow = shadow.filter(ImageFilter.GaussianBlur(7 * S))
    canvas = Image.alpha_composite(canvas, shadow)
    ring = Image.new("RGBA", (W, W), OUT + (0,))
    ring.putalpha(edge)
    canvas = Image.alpha_composite(canvas, ring)
    canvas = Image.alpha_composite(canvas, art)
    shine = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shine)
    for box, alpha in GLOSS:
        sd.ellipse(p(*box), fill=(255, 255, 255, alpha))
    GLOSS.clear()
    return Image.alpha_composite(canvas, shine)


def fit_font(text, maxw, size):
    while size > 10:
        f = ImageFont.truetype(FONT, size * S)
        if f.getlength(text) <= maxw * S:
            return f
        size -= 2
    return ImageFont.truetype(FONT, size * S)


def label(canvas, text, y=402, maxw=370, size=66, fill=(255, 255, 255)):
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    f = fit_font(text, maxw, size)
    d.text((W / 2, y * S + 5 * S), text, font=f, anchor="mm", fill=(0, 0, 0, 110), stroke_width=9 * S, stroke_fill=(0, 0, 0, 110))
    layer = layer.filter(ImageFilter.GaussianBlur(3 * S))
    d = ImageDraw.Draw(layer)
    d.text((W / 2, y * S), text, font=f, anchor="mm", fill=fill, stroke_width=8 * S, stroke_fill=OUT)
    return Image.alpha_composite(canvas, layer)


def big_text(d, xy, text, size, fill):
    f = ImageFont.truetype(FONT, size * S)
    d.text((xy[0] * S, xy[1] * S), text, font=f, anchor="mm", fill=fill, stroke_width=7 * S, stroke_fill=OUT)


def new_art():
    art = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    return art, ImageDraw.Draw(art)


# ─── Parçalar ─────────────────────────────────────────────────────────────


# Parlamalar ayrı katmanda: ImageDraw yarı saydamı karıştırmıyor, piksele
# yazıyor — sanatın üstüne çizilince alttaki koyu kontur görünüp griye dönüyordu
GLOSS = []


def gloss(d, box, alpha=110):
    GLOSS.append((box, alpha))


def coin(d, cx, cy, r, dollar=True):
    d.ellipse(p(cx - r, cy - r, cx + r, cy + r), fill=(255, 200, 44), outline=OUT, width=LW)
    ri = r * 0.76
    d.ellipse(p(cx - ri, cy - ri, cx + ri, cy + ri), fill=(246, 172, 22), outline=(205, 128, 8), width=int(LW * 0.8))
    if dollar:
        big_text(d, (cx, cy + r * 0.04), "$", int(r * 1.15), (255, 228, 120))
    gloss(d, (cx - r * 0.62, cy - r * 0.72, cx - r * 0.12, cy - r * 0.42), 120)


def coin_flat(d, cx, cy, w, h=None):
    """Yandan görünen yassı para (yığın için)."""
    h = h or w * 0.36
    t = h * 0.5
    d.rounded_rectangle(p(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2 + t), radius=h / 2 * S, fill=(214, 140, 10), outline=OUT, width=LW)
    d.ellipse(p(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), fill=(255, 200, 44), outline=OUT, width=LW)
    d.ellipse(p(cx - w * 0.32, cy - h * 0.3, cx + w * 0.32, cy + h * 0.3), outline=(214, 150, 20), width=int(LW * 0.7))


def coin_stack(d, cx, by, w, n):
    h = w * 0.36
    for i in range(n):
        coin_flat(d, cx, by - h * 0.55 - i * h * 0.55, w, h)


def bill(d, cx, cy, w, h, angle=0):
    layer = Image.new("RGBA", (int(w * S * 1.6), int(w * S * 1.6)), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ox, oy = layer.width / 2, layer.height / 2
    ld.rounded_rectangle([ox - w / 2 * S, oy - h / 2 * S, ox + w / 2 * S, oy + h / 2 * S], radius=8 * S, fill=(110, 200, 90), outline=OUT, width=LW)
    ld.rounded_rectangle([ox - w / 2 * S + 12 * S, oy - h / 2 * S + 10 * S, ox + w / 2 * S - 12 * S, oy + h / 2 * S - 10 * S],
                         radius=5 * S, outline=(60, 140, 60), width=int(LW * 0.6))
    rr = h * 0.3 * S
    ld.ellipse([ox - rr, oy - rr, ox + rr, oy + rr], fill=(80, 170, 70), outline=(50, 120, 50), width=int(LW * 0.6))
    f = ImageFont.truetype(FONT, int(h * 0.42 * S))
    ld.text((ox, oy), "$", font=f, anchor="mm", fill=(210, 250, 190))
    layer = layer.rotate(angle, resample=Image.BICUBIC)
    return layer, (int(cx * S - layer.width / 2), int(cy * S - layer.height / 2))


def paste(art, piece):
    layer, pos = piece
    art.alpha_composite(layer, pos)


def crewmate(d, cx, by, h, col, face=1):
    w = h * 0.72
    top = by - h
    dark = shade(col, 0.68)
    lw = max(int(LW * h / 200), 3 * S)
    bx = cx - face * (w / 2 + h * 0.03)
    d.rounded_rectangle(p(min(bx, bx - face * h * 0.2), top + h * 0.3, max(bx, bx - face * h * 0.2) + h * 0.12, top + h * 0.7),
                        radius=h * 0.07 * S, fill=dark, outline=OUT, width=lw)
    d.rounded_rectangle(p(cx - w / 2, by - h * 0.32, cx - w * 0.07, by), radius=h * 0.08 * S, fill=dark, outline=OUT, width=lw)
    d.rounded_rectangle(p(cx + w * 0.07, by - h * 0.32, cx + w / 2, by), radius=h * 0.08 * S, fill=dark, outline=OUT, width=lw)
    d.rounded_rectangle(p(cx - w / 2, top, cx + w / 2, by - h * 0.16), radius=w * 0.47 * S, fill=col, outline=OUT, width=lw)
    vx0 = cx - w * 0.08 if face > 0 else cx - w / 2 - h * 0.1
    vx1 = cx + w / 2 + h * 0.1 if face > 0 else cx + w * 0.08
    d.rounded_rectangle(p(vx0, top + h * 0.17, vx1, top + h * 0.45), radius=h * 0.13 * S, fill=(150, 220, 242), outline=OUT, width=lw)
    hx = vx0 + (vx1 - vx0) * (0.52 if face > 0 else 0.18)
    d.rounded_rectangle(p(hx, top + h * 0.22, hx + (vx1 - vx0) * 0.3, top + h * 0.3), radius=h * 0.035 * S, fill=(235, 250, 255))
    gloss(d, (cx - w * 0.36, top + h * 0.06, cx - w * 0.12, top + h * 0.14), 90)


def sparkle(d, cx, cy, r, col=(255, 255, 255)):
    pts = []
    for i in range(8):
        a = i * math.pi / 4 - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.28
        pts.append(((cx + math.cos(a) * rr) * S, (cy + math.sin(a) * rr) * S))
    d.polygon(pts, fill=col)


def egg(d, cx, cy, w, h, col, spot, seed):
    d.ellipse(p(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), fill=col, outline=OUT, width=LW)
    rng = random.Random(seed)
    for _ in range(4):
        sx = cx + rng.uniform(-0.28, 0.28) * w
        sy = cy + rng.uniform(-0.25, 0.3) * h
        r = rng.uniform(0.08, 0.13) * w
        d.ellipse(p(sx - r, sy - r * 0.85, sx + r, sy + r * 0.85), fill=spot)
    gloss(d, (cx - w * 0.3, cy - h * 0.36, cx - w * 0.08, cy - h * 0.18), 150)


def podium(d, cx, by, w, h, col):
    top = by - h
    eh = w * 0.3
    side = shade(col, 0.72)
    d.rectangle(p(cx - w / 2, top, cx + w / 2, by), fill=side)
    d.ellipse(p(cx - w / 2, by - eh / 2, cx + w / 2, by + eh / 2), fill=side, outline=OUT, width=LW)
    d.rectangle(p(cx - w / 2 + 3, top, cx + w / 2 - 3, by), fill=side)
    d.line(p(cx - w / 2, top, cx - w / 2, by), fill=OUT, width=LW)
    d.line(p(cx + w / 2, top, cx + w / 2, by), fill=OUT, width=LW)
    d.rectangle(p(cx - w / 2 + 3, top + h * 0.35, cx + w / 2 - 3, top + h * 0.5), fill=(255, 205, 60))
    d.ellipse(p(cx - w / 2, top - eh / 2, cx + w / 2, top + eh / 2), fill=shade(col, 1.25), outline=OUT, width=LW)


# ─── İkonlar ──────────────────────────────────────────────────────────────


def icon_double_income():
    c = background((120, 230, 110), (18, 96, 48), 1)
    art, d = new_art()
    paste(art, bill(d, 190, 250, 190, 100, 18))
    coin(d, 236, 215, 118)
    big_text(d, (360, 292), "2X", 118, (255, 84, 84))
    c = stamp(c, art)
    return label(c, "INCOME")


def icon_extra_podiums():
    c = background((120, 190, 255), (20, 50, 130), 2)
    art, d = new_art()
    podium(d, 165, 330, 128, 78, (70, 120, 210))
    podium(d, 347, 330, 128, 78, (70, 120, 210))
    crewmate(d, 165, 252, 110, (80, 239, 57), 1)
    crewmate(d, 347, 252, 110, (240, 125, 13), -1)
    big_text(d, (256, 92), "+2", 116, (120, 255, 110))
    c = stamp(c, art)
    return label(c, "PODIUMS")


def icon_triple_hatch():
    c = background((210, 150, 255), (70, 20, 130), 3)
    art, d = new_art()
    egg(d, 150, 250, 120, 150, (150, 230, 255), (70, 150, 230), 1)
    egg(d, 362, 250, 120, 150, (255, 190, 225), (230, 90, 160), 2)
    egg(d, 256, 212, 150, 190, (255, 244, 214), (150, 90, 230), 3)
    d.line(p(200, 190, 226, 212, 246, 186, 268, 214, 290, 190, 312, 208), fill=OUT, width=LW, joint="curve")
    sparkle(d, 256, 86, 30, (255, 240, 140))
    sparkle(d, 95, 145, 18)
    sparkle(d, 420, 150, 20)
    c = stamp(c, art)
    return label(c, "TRIPLE HATCH")


def icon_fast_steal():
    c = background((255, 190, 90), (150, 40, 20), 4)
    art, d = new_art()
    for i, (y, x0, x1) in enumerate([(150, 70, 175), (215, 45, 150), (280, 80, 170)]):
        d.rounded_rectangle(p(x0, y - 9, x1, y + 9), radius=9 * S, fill=(255, 255, 255, 230), outline=OUT, width=int(LW * 0.7))
    bolt = [(300, 40), (170, 215), (252, 215), (208, 345), (360, 160), (274, 160), (330, 40)]
    d.polygon([(x * S, y * S) for x, y in bolt], fill=(255, 222, 50), outline=OUT, width=LW)
    d.polygon([(x * S, y * S) for x, y in [(300, 60), (205, 195), (232, 195), (310, 60)]], fill=(255, 250, 190))
    c = stamp(c, art)
    return label(c, "FAST STEAL")


def icon_strong_lock():
    c = background((110, 230, 230), (15, 70, 100), 5)
    art, d = new_art()
    d.arc(p(168, 58, 344, 234), 180, 360, fill=OUT, width=48 * S)
    d.rectangle(p(168, 140, 216, 210), fill=OUT)
    d.rectangle(p(296, 140, 344, 210), fill=OUT)
    d.arc(p(174, 64, 338, 228), 180, 360, fill=(200, 210, 225), width=36 * S)
    d.rectangle(p(174, 144, 210, 210), fill=(200, 210, 225))
    d.rectangle(p(302, 144, 338, 210), fill=(200, 210, 225))
    d.rounded_rectangle(p(130, 182, 382, 345), radius=34 * S, fill=(255, 196, 40), outline=OUT, width=LW)
    d.rounded_rectangle(p(150, 200, 362, 222), radius=10 * S, fill=(255, 226, 120))
    d.ellipse(p(234, 238, 278, 282), fill=OUT)
    d.polygon(p(242, 270, 270, 270, 280, 318, 232, 318), fill=OUT)
    for x in (156, 356):
        d.ellipse(p(x - 8, 320 - 8, x + 8, 320 + 8), fill=(214, 140, 10))
    c = stamp(c, art)
    return label(c, "STRONG LOCK")


def icon_extra_spin():
    c = background((255, 160, 210), (130, 20, 80), 6)
    art, d = new_art()
    wheel(d, 256, 215, 128)
    big_text(d, (378, 318), "+1", 84, (255, 240, 120))
    c = stamp(c, art)
    return label(c, "EXTRA SPIN")


def wheel(d, cx, cy, r):
    cols = [(230, 50, 60), (255, 200, 40), (80, 220, 80), (60, 130, 240), (160, 80, 230), (255, 140, 30), (60, 220, 220), (255, 110, 190)]
    d.ellipse(p(cx - r - 14, cy - r - 14, cx + r + 14, cy + r + 14), fill=(240, 240, 250), outline=OUT, width=LW)
    for i, col in enumerate(cols):
        d.pieslice(p(cx - r, cy - r, cx + r, cy + r), i * 45 - 90, (i + 1) * 45 - 90, fill=col, outline=OUT, width=int(LW * 0.7))
    for i in range(8):
        a = math.radians(i * 45 - 90)
        x, y = cx + math.cos(a) * (r + 7), cy + math.sin(a) * (r + 7)
        d.ellipse(p(x - 6, y - 6, x + 6, y + 6), fill=(255, 230, 120), outline=OUT, width=2 * S)
    d.ellipse(p(cx - 30, cy - 30, cx + 30, cy + 30), fill=(245, 245, 255), outline=OUT, width=LW)
    d.ellipse(p(cx - 12, cy - 12, cx + 12, cy + 12), fill=(230, 50, 60))
    d.polygon(p(cx - 26, cy - r - 44, cx + 26, cy - r - 44, cx, cy - r + 8), fill=(230, 50, 60), outline=OUT, width=LW)


def icon_instant_spawn():
    c = background((120, 220, 255), (15, 60, 120), 7)
    art, d = new_art()
    d.rounded_rectangle(p(96, 322, 416, 352), radius=15 * S, fill=(70, 78, 96), outline=OUT, width=LW)
    for x in range(118, 400, 36):
        d.line(p(x, 328, x + 14, 346), fill=(255, 205, 60), width=5 * S)
    crewmate(d, 256, 322, 230, (197, 17, 17), 1)
    sparkle(d, 118, 140, 30, (255, 245, 150))
    sparkle(d, 400, 110, 24)
    sparkle(d, 408, 240, 16, (255, 245, 150))
    c = stamp(c, art)
    return label(c, "INSTANT SPAWN")


def icon_mutation():
    c = background((240, 140, 255), (80, 20, 120), 8)
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(p(120, 110, 392, 382), fill=(140, 255, 150, 150))
    c = Image.alpha_composite(c, glow.filter(ImageFilter.GaussianBlur(30 * S)))
    art, d = new_art()
    d.rounded_rectangle(p(222, 58, 290, 92), radius=8 * S, fill=(170, 110, 60), outline=OUT, width=LW)
    d.rounded_rectangle(p(226, 86, 286, 170), radius=6 * S, fill=(220, 240, 250), outline=OUT, width=LW)
    d.ellipse(p(156, 140, 356, 340), fill=(220, 240, 250), outline=OUT, width=LW)
    d.rectangle(p(232, 136, 280, 172), fill=(220, 240, 250))
    d.chord(p(170, 154, 342, 326), 10, 170, fill=(90, 240, 110))
    d.chord(p(170, 154, 342, 326), 10, 170, outline=(40, 150, 60), width=int(LW * 0.6))
    for bx, by, br in [(220, 270, 12), (262, 296, 8), (296, 262, 10), (248, 250, 6)]:
        d.ellipse(p(bx - br, by - br, bx + br, by + br), fill=(210, 255, 210))
    gloss(d, (180, 180, 214, 240), 170)
    sparkle(d, 120, 120, 26, (255, 250, 160))
    sparkle(d, 392, 150, 20)
    c = stamp(c, art)
    return label(c, "MUTATION")


def icon_cash(size):
    c = background((140, 240, 120), (15, 90, 40), 9 + size)
    art, d = new_art()
    if size == 1:
        paste(art, bill(d, 300, 250, 170, 92, -14))
        coin_stack(d, 200, 320, 118, 4)
    elif size == 2:
        paste(art, bill(d, 256, 200, 190, 100, 10))
        paste(art, bill(d, 280, 240, 190, 100, -8))
        coin_stack(d, 150, 330, 110, 5)
        coin_stack(d, 360, 330, 110, 3)
        coin(d, 256, 262, 64)
    else:
        for i, (x, y, a) in enumerate([(160, 170, 20), (350, 170, -18), (256, 150, 4), (200, 215, -6), (315, 215, 10)]):
            paste(art, bill(d, x, y, 180, 96, a))
        coin_stack(d, 110, 335, 100, 5)
        coin_stack(d, 402, 335, 100, 5)
        coin_stack(d, 200, 345, 108, 3)
        coin_stack(d, 312, 345, 108, 3)
        coin(d, 256, 262, 84)
        sparkle(d, 90, 110, 26, (255, 250, 160))
        sparkle(d, 426, 104, 22)
    c = stamp(c, art)
    return label(c, ["", "SMALL CASH", "MEDIUM CASH", "HUGE CASH"][size])


def icon_rebirth():
    c = background((255, 180, 90), (140, 40, 10), 13)
    art, d = new_art()
    rebirth_arrows(d, 256, 215, 112)
    crewmate(d, 256, 275, 120, (255, 255, 255), 1)
    c = stamp(c, art)
    return label(c, "REBIRTH")


def rebirth_arrows(d, cx, cy, r):
    for a0, a1 in [(-35, 95), (145, 275)]:
        d.arc(p(cx - r, cy - r, cx + r, cy + r), a0, a1, fill=OUT, width=52 * S)
        d.arc(p(cx - r + 6, cy - r + 6, cx + r - 6, cy + r - 6), a0 + 1, a1 - 1, fill=(255, 220, 70), width=40 * S)
        a = math.radians(a1)
        tx, ty = cx + math.cos(a) * (r - 26), cy + math.sin(a) * (r - 26)
        tang = a + math.pi / 2
        n = (math.cos(a), math.sin(a))
        t = (math.cos(tang), math.sin(tang))
        pts = [(tx + n[0] * 42 - t[0] * 4, ty + n[1] * 42 - t[1] * 4), (tx - n[0] * 42 - t[0] * 4, ty - n[1] * 42 - t[1] * 4),
               (tx + t[0] * 46, ty + t[1] * 46)]
        d.polygon([(x * S, y * S) for x, y in pts], fill=(255, 220, 70), outline=OUT, width=LW)


# ─── Rozetler ─────────────────────────────────────────────────────────────
# Rozetler de daire kırpılıyor; kenardaki altın halka onları pass'lerden ayırıyor.


def badge_ring(c):
    layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse(p(10, 10, 502, 502), outline=OUT, width=26 * S)
    d.ellipse(p(14, 14, 498, 498), outline=(255, 205, 60), width=16 * S)
    d.ellipse(p(20, 20, 492, 492), outline=(255, 240, 160), width=3 * S)
    return Image.alpha_composite(c, layer)


def flame(d, cx, by, h, col):
    pts = []
    for i in range(120):
        t = i / 120 * math.tau
        x = math.sin(t) * abs(math.sin(t / 2)) ** 1.4
        y = -math.cos(t)
        pts.append(((cx + x * h * 0.42) * S, (by - h / 2 + y * h / 2) * S))
    d.polygon(pts, fill=col, outline=OUT, width=LW)


def finish_badge(c, art, text):
    c = stamp(c, art)
    c = label(c, text, y=392, maxw=330, size=58)
    return badge_ring(c)


def badge_first_heist():
    c = background((255, 130, 120), (120, 20, 30), 21)
    art, d = new_art()
    crewmate(d, 236, 330, 220, (197, 17, 17), 1)
    coin(d, 350, 250, 58)
    sparkle(d, 120, 130, 28, (255, 245, 150))
    sparkle(d, 392, 120, 22)
    return finish_badge(c, art, "FIRST HEIST")


def badge_reborn():
    c = background((255, 180, 90), (140, 40, 10), 22)
    art, d = new_art()
    rebirth_arrows(d, 256, 205, 112)
    crewmate(d, 256, 265, 120, (255, 255, 255), 1)
    return finish_badge(c, art, "REBORN")


def badge_millionaire():
    c = background((140, 240, 120), (15, 90, 40), 23)
    art, d = new_art()
    paste(art, bill(d, 170, 230, 170, 92, 16))
    paste(art, bill(d, 345, 230, 170, 92, -16))
    coin(d, 256, 200, 105)
    big_text(d, (256, 318), "$1M", 76, (255, 230, 90))
    return finish_badge(c, art, "MILLIONAIRE")


def badge_billionaire():
    c = background((255, 225, 120), (150, 90, 10), 24)
    art, d = new_art()
    for x, y, a in [(160, 190, 20), (350, 190, -18), (256, 170, 4)]:
        paste(art, bill(d, x, y, 170, 92, a))
    coin_stack(d, 130, 330, 96, 5)
    coin_stack(d, 382, 330, 96, 5)
    coin(d, 256, 230, 82)
    d.polygon(p(196, 132, 196, 78, 226, 106, 256, 66, 286, 106, 316, 78, 316, 132), fill=(255, 205, 40), outline=OUT, width=LW)
    big_text(d, (256, 318), "$1B", 76, (255, 245, 170))
    return finish_badge(c, art, "BILLIONAIRE")


def badge_red_handed():
    c = background((120, 170, 255), (20, 30, 110), 25)
    art, d = new_art()
    crewmate(d, 250, 335, 205, (107, 47, 187), 1)
    d.rounded_rectangle(p(335, 60, 385, 190), radius=18 * S, fill=(240, 50, 60), outline=OUT, width=LW)
    d.ellipse(p(335, 204, 385, 254), fill=(240, 50, 60), outline=OUT, width=LW)
    return finish_badge(c, art, "RED-HANDED")


def badge_robbed():
    c = background((170, 180, 200), (40, 44, 60), 26)
    art, d = new_art()
    podium(d, 256, 330, 190, 90, (70, 120, 210))
    big_text(d, (256, 150), "?", 170, (255, 205, 60))
    for x, y in [(150, 120), (362, 130)]:
        d.line(p(x - 16, y - 16, x + 16, y + 16), fill=OUT, width=10 * S)
        d.line(p(x - 16, y + 16, x + 16, y - 16), fill=OUT, width=10 * S)
    return finish_badge(c, art, "ROBBED")


def badge_full_house():
    c = background((120, 190, 255), (20, 50, 130), 27)
    art, d = new_art()
    for x, col, face in [(130, (80, 239, 57), 1), (382, (240, 125, 13), -1)]:
        podium(d, x, 330, 110, 66, (70, 120, 210))
        crewmate(d, x, 262, 98, col, face)
    podium(d, 256, 316, 120, 80, (70, 120, 210))
    crewmate(d, 256, 234, 118, (19, 46, 209), 1)
    sparkle(d, 256, 70, 26, (255, 245, 150))
    return finish_badge(c, art, "FULL HOUSE")


def badge_secret():
    c = background((120, 70, 180), (10, 5, 25), 28)
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(p(110, 80, 402, 372), fill=(200, 120, 255, 170))
    c = Image.alpha_composite(c, glow.filter(ImageFilter.GaussianBlur(34 * S)))
    art, d = new_art()
    crewmate(d, 256, 335, 225, (26, 24, 38), 1)
    big_text(d, (372, 122), "?", 120, (220, 160, 255))
    sparkle(d, 118, 120, 26, (230, 190, 255))
    sparkle(d, 398, 110, 22)
    return finish_badge(c, art, "SECRET")


def badge_streak():
    c = background((255, 160, 90), (130, 20, 10), 29)
    art, d = new_art()
    flame(d, 256, 330, 280, (255, 110, 30))
    flame(d, 256, 326, 190, (255, 215, 60))
    big_text(d, (256, 262), "x5", 96, (255, 255, 255))
    return finish_badge(c, art, "STREAK")


def badge_lucky_spinner():
    c = background((255, 160, 210), (130, 20, 80), 30)
    art, d = new_art()
    wheel(d, 256, 215, 118)
    sparkle(d, 96, 110, 26, (255, 245, 150))
    sparkle(d, 420, 250, 22)
    return finish_badge(c, art, "LUCKY SPIN")


ICONS = {
    "pass_2x_income": icon_double_income,
    "pass_extra_podiums": icon_extra_podiums,
    "pass_triple_hatch": icon_triple_hatch,
    "pass_fast_steal": icon_fast_steal,
    "pass_strong_lock": icon_strong_lock,
    "product_extra_spin": icon_extra_spin,
    "product_instant_spawn": icon_instant_spawn,
    "product_guaranteed_mutation": icon_mutation,
    "product_small_cash": lambda: icon_cash(1),
    "product_medium_cash": lambda: icon_cash(2),
    "product_huge_cash": lambda: icon_cash(3),
    "product_instant_rebirth": icon_rebirth,
}

BADGES = {
    "badge_first_heist": badge_first_heist,
    "badge_reborn": badge_reborn,
    "badge_millionaire": badge_millionaire,
    "badge_billionaire": badge_billionaire,
    "badge_caught_red_handed": badge_red_handed,
    "badge_robbed": badge_robbed,
    "badge_full_house": badge_full_house,
    "badge_secret_collector": badge_secret,
    "badge_streak_master": badge_streak,
    "badge_lucky_spinner": badge_lucky_spinner,
}


def main():
    os.makedirs(DEST, exist_ok=True)
    build(ICONS, "_preview.png")
    build(BADGES, "_preview_badges.png")


def build(group, preview):
    thumbs = []
    for name, make in group.items():
        img = make().convert("RGB").resize((512, 512), Image.LANCZOS)
        img.save(os.path.join(DEST, name + ".png"), optimize=True)
        thumbs.append(img)
        print(name)
    # Önizleme: hepsi bir arada, daire kırpmasıyla (Roblox pass'i böyle gösteriyor)
    cols = 4
    rows = math.ceil(len(thumbs) / cols)
    sheet = Image.new("RGB", (cols * 260, rows * 260), (30, 30, 36))
    mask = Image.new("L", (256, 256), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, 255, 255], fill=255)
    for i, img in enumerate(thumbs):
        sheet.paste(img.resize((256, 256), Image.LANCZOS), ((i % cols) * 260 + 2, (i // cols) * 260 + 2), mask)
    sheet.save(os.path.join(DEST, preview))


if __name__ == "__main__":
    main()
