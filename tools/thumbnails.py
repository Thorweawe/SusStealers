"""
Roblox oyun sayfası "troll" thumbnail'ları (16:9, 1920x1080).

    python tools/thumbnails.py   ->  branding/thumbnails/thumb_1..5.png
                                     branding/thumbnails/_preview.png

Konsept: HIRSIZ mürettebat başka bir OYUNCUNUN mürettebatını çalıyor; kurban
ağlıyor. Abartılı troll suratlar, dev meme yazıları, kırmızı ok/daire — klasik
Roblox thumbnail dili. Çizim dili store_icons.py ile aynı (kalın koyu kontur,
cam vizör, gloss, uzay zemini).

Gerekenler: pip install pillow
"""

import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import store_icons as si  # noqa: E402  (FONT çözücü + shade paylaşılıyor)

SS = 2                      # supersample: 2x çiz, sonra küçült
W, H = 1920 * SS, 1080 * SS
OUT = (20, 18, 30)
FONT = si.FONT
DEST = os.path.join(si.ROOT, "branding", "thumbnails")

shade = si.shade

# Mürettebat renkleri
THIEF = (214, 40, 52)       # hırsız: agresif kırmızı
GREEN = (80, 239, 57)
YELLOW = (255, 200, 40)
BLUE = (60, 130, 240)
PINK = (235, 90, 190)
ORANGE = (240, 125, 13)
PURPLE = (150, 70, 220)
CYAN = (60, 220, 220)
VISOR = (150, 220, 242)
TEAR = (120, 205, 255)


# ─── Zemin ──────────────────────────────────────────────────────────────────

def space(seed, top=(46, 16, 70), bottom=(8, 8, 28)):
    grad = Image.linear_gradient("L").resize((W, H))
    img = Image.composite(Image.new("RGB", (W, H), bottom),
                          Image.new("RGB", (W, H), top), grad).convert("RGBA")
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for _ in range(int(W * H / 5200)):
        x, y = rng.uniform(0, W), rng.uniform(0, H)
        r = rng.choice([1, 1, 1, 2, 2, 3]) * SS
        col = rng.choice([(255, 255, 255), (170, 220, 255), (255, 200, 230)])
        d.ellipse([x - r, y - r, x + r, y + r], fill=col + (rng.randint(90, 230),))
    return img


def vignette(img):
    v = Image.new("L", (W, H), 0)
    ImageDraw.Draw(v).ellipse([-W * 0.25, -H * 0.25, W * 1.25, H * 1.25], fill=255)
    v = v.filter(ImageFilter.GaussianBlur(W * 0.12))
    dark = Image.new("RGBA", (W, H), (0, 0, 0, 130))
    dark.putalpha(Image.eval(v, lambda x: 130 - int(x * 130 / 255)))
    return Image.alpha_composite(img, dark)


# ─── Sticker konturu ─────────────────────────────────────────────────────────

def _dilate(mask, r):
    return mask.filter(ImageFilter.GaussianBlur(r)).point(lambda v: 255 if v > 12 else 0)


def stamp(layer, outline=7):
    """Katmanın etrafına kalın koyu dış kontur ekler (union siluet)."""
    edge = _dilate(layer.split()[3], outline * SS).filter(ImageFilter.GaussianBlur(0.6 * SS))
    ring = Image.new("RGBA", layer.size, OUT + (0,))
    ring.putalpha(edge)
    return Image.alpha_composite(ring, layer)


def drop_shadow(canvas, x, y, rx, ry, alpha=150):
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([x - rx, y - ry, x + rx, y + ry], fill=(0, 0, 0, alpha))
    sh = sh.filter(ImageFilter.GaussianBlur(18 * SS))
    return Image.alpha_composite(canvas, sh)


# ─── Mürettebat + ifadeler ───────────────────────────────────────────────────

def _eye(d, cx, cy, r, look=(0, 0), lw=3):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255), outline=OUT, width=lw)
    pr = r * 0.52
    px, py = cx + look[0] * r * 0.42, cy + look[1] * r * 0.42
    d.ellipse([px - pr, py - pr, px + pr, py + pr], fill=(24, 22, 34))
    d.ellipse([px - pr * 0.5, py - pr * 0.7, px - pr * 0.05, py - pr * 0.2], fill=(255, 255, 255))


def _mouth_grin(d, cx, cy, w, h, lw):
    d.pieslice([cx - w / 2, cy - h, cx + w / 2, cy + h], 0, 180, fill=(28, 20, 28), outline=OUT, width=lw)
    n = 4
    tw = w / n
    for i in range(n):
        tx = cx - w / 2 + i * tw + tw * 0.12
        d.rounded_rectangle([tx, cy - h * 0.02, tx + tw * 0.76, cy + h * 0.34],
                            radius=tw * 0.14, fill=(250, 250, 255))


def _mouth_open(d, cx, cy, w, h, lw, tongue=False):
    d.ellipse([cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2], fill=(30, 20, 26), outline=OUT, width=lw)
    if tongue:
        d.ellipse([cx - w * 0.3, cy + h * 0.02, cx + w * 0.3, cy + h * 0.55], fill=(235, 90, 110))


def expression(d, kind, vx0, vy0, vx1, vy1, top, h, w, cx, face, lw):
    """İfadeyi vizör/gövde üzerine çizer."""
    vcx, vcy = (vx0 + vx1) / 2, (vy0 + vy1) / 2
    vw, vh = vx1 - vx0, vy1 - vy0
    er = vh * 0.34
    ex = vw * 0.19
    my = top + h * 0.56
    ebw = er * 1.5

    if kind == "evil":
        _eye(d, vcx - ex, vcy + vh * 0.05, er, (face * 0.4, 0.35), lw)
        _eye(d, vcx + ex, vcy + vh * 0.05, er, (face * 0.4, 0.35), lw)
        for sx in (-1, 1):
            ix, iy = vcx + sx * ex * 0.5, vcy - er * 1.05
            ox, oy = vcx + sx * ex * 1.7, vcy - er * 1.7
            d.line([ix, iy, ox, oy], fill=OUT, width=int(lw * 1.9))
        _mouth_grin(d, cx + w * 0.05 * face, my, w * 0.62, h * 0.12, lw)
    elif kind == "cry":
        _eye(d, vcx - ex, vcy, er, (0, -0.5), lw)
        _eye(d, vcx + ex, vcy, er, (0, -0.5), lw)
        for sx in (-1, 1):
            d.arc([vcx + sx * ex - er * 1.1, vcy - er * 2.2, vcx + sx * ex + er * 1.1, vcy - er * 0.6],
                  200, 340, fill=OUT, width=int(lw * 1.6))
        for sx in (-1, 1):
            tx = vcx + sx * ex
            ty = vcy + er * 0.8
            d.polygon([(tx - er * 0.34, ty), (tx + er * 0.34, ty), (tx, ty + h * 0.16)],
                      fill=TEAR, outline=OUT, width=lw)
            d.ellipse([tx - er * 0.34, ty + h * 0.11, tx + er * 0.34, ty + h * 0.2],
                      fill=TEAR, outline=OUT, width=lw)
        _mouth_open(d, cx + w * 0.02 * face, my + h * 0.02, w * 0.34, h * 0.2, lw)
    elif kind == "shock":
        _eye(d, vcx - ex, vcy, er * 1.05, (0, 0.1), lw)
        _eye(d, vcx + ex, vcy, er * 1.05, (0, 0.1), lw)
        _mouth_open(d, cx + w * 0.02 * face, my, w * 0.26, h * 0.16, lw)
    elif kind == "laugh":
        for sx in (-1, 1):
            d.arc([vcx + sx * ex - er, vcy - er * 0.2, vcx + sx * ex + er, vcy + er * 1.4],
                  200, 340, fill=OUT, width=int(lw * 1.8))
        _mouth_grin(d, cx + w * 0.05 * face, my, w * 0.6, h * 0.13, lw)
    elif kind == "money":
        for sx in (-1, 1):
            ecx = vcx + sx * ex
            d.ellipse([ecx - er, vcy - er, ecx + er, vcy + er], fill=(255, 255, 255), outline=OUT, width=lw)
            f = ImageFont.truetype(FONT, int(er * 1.7))
            d.text((ecx, vcy), "$", font=f, anchor="mm", fill=(46, 170, 70))
        _mouth_grin(d, cx + w * 0.05 * face, my, w * 0.6, h * 0.12, lw)
    elif kind == "angry":
        _eye(d, vcx - ex, vcy + vh * 0.05, er, (face * 0.3, 0.2), lw)
        _eye(d, vcx + ex, vcy + vh * 0.05, er, (face * 0.3, 0.2), lw)
        for sx in (-1, 1):
            ix, iy = vcx + sx * ex * 0.5, vcy - er * 1.0
            ox, oy = vcx + sx * ex * 1.7, vcy - er * 1.6
            d.line([ix, iy, ox, oy], fill=OUT, width=int(lw * 1.9))
        d.rounded_rectangle([cx - w * 0.24, my - h * 0.03, cx + w * 0.24, my + h * 0.07],
                            radius=h * 0.02, fill=(28, 20, 26), outline=OUT, width=lw)


def crewmate(h, col, face=1, expr="neutral", tilt=0):
    """Tek mürettebatı kendi katmanında çizer. (layer, cx, feet_y) döner."""
    pad = int(h * 2.0)
    L = Image.new("RGBA", (pad, pad), (0, 0, 0, 0))
    d = ImageDraw.Draw(L)
    w = h * 0.72
    cx = pad / 2
    by = pad / 2 + h * 0.5           # ayak hattı
    top = by - h
    dark = shade(col, 0.68)
    lw = max(int(h * 0.032), 3)

    # sırt çantası (yüzün ters tarafı)
    bx = cx - face * (w / 2 + h * 0.03)
    x0, x1 = sorted((bx, bx - face * h * 0.2))
    d.rounded_rectangle([x0, top + h * 0.3, x1 + h * 0.12, top + h * 0.7],
                        radius=h * 0.07, fill=dark, outline=OUT, width=lw)
    # bacaklar
    d.rounded_rectangle([cx - w / 2, by - h * 0.32, cx - w * 0.07, by], radius=h * 0.08, fill=dark, outline=OUT, width=lw)
    d.rounded_rectangle([cx + w * 0.07, by - h * 0.32, cx + w / 2, by], radius=h * 0.08, fill=dark, outline=OUT, width=lw)
    # gövde
    d.rounded_rectangle([cx - w / 2, top, cx + w / 2, by - h * 0.16], radius=w * 0.47, fill=col, outline=OUT, width=lw)
    # vizör
    vx0 = cx - w * 0.08 if face > 0 else cx - w / 2 - h * 0.1
    vx1 = cx + w / 2 + h * 0.1 if face > 0 else cx + w * 0.08
    vy0, vy1 = top + h * 0.17, top + h * 0.45
    d.rounded_rectangle([vx0, vy0, vx1, vy1], radius=h * 0.13, fill=VISOR, outline=OUT, width=lw)
    hx = vx0 + (vx1 - vx0) * (0.52 if face > 0 else 0.18)
    d.rounded_rectangle([hx, vy0 + h * 0.05, hx + (vx1 - vx0) * 0.3, vy0 + h * 0.13],
                        radius=h * 0.035, fill=(235, 250, 255))
    # gövde parlaması: gövde renginin açık tonu, OPAK (yarı saydam beyaz koyu
    # konturun üstüne binince griye dönüyor — store_icons.py'nin uyardığı hata)
    sheen = tuple(min(255, int(ch * 1.5)) for ch in col[:3])
    d.ellipse([cx - w * 0.34, top + h * 0.07, cx - w * 0.12, top + h * 0.19], fill=sheen)
    # yüz ifadesi
    if expr != "neutral":
        expression(d, expr, vx0, vy0, vx1, vy1, top, h, w, cx, face, lw)

    L = stamp(L, outline=6)
    if tilt:
        L = L.rotate(tilt, resample=Image.BICUBIC, center=(cx, by))
    return L, cx, by


def place(canvas, piece, x, y, shadow=True):
    """piece=(layer, cx, feet_y); (x,y) ayak noktasına denk gelir."""
    L, cx, by = piece
    if shadow:
        canvas = drop_shadow(canvas, x, y + 10 * SS, L.width * 0.18, L.width * 0.05)
    canvas.alpha_composite(L, (int(x - cx), int(y - by)))
    return canvas


def arm(d, x0, y0, x1, y1, col, width, lw):
    """Kol: kalın yuvarlak çizgi + ucunda eldiven."""
    d.line([x0, y0, x1, y1], fill=OUT, width=int(width + lw * 2))
    d.line([x0, y0, x1, y1], fill=col, width=int(width))
    r = width * 0.75
    d.ellipse([x1 - r, y1 - r, x1 + r, y1 + r], fill=col, outline=OUT, width=lw)


# ─── Efektler: yazı, ok, daire, para ─────────────────────────────────────────

def _font(size):
    return ImageFont.truetype(FONT, int(size))


def text(canvas, xy, s, size, fill=(255, 255, 255), anchor="mm", stroke=None, rot=0, glow=None):
    stroke = stroke if stroke is not None else max(6, size * 0.09)
    pad = int(size * 1.2)
    f = _font(size)
    box = f.getbbox(s, stroke_width=int(stroke))
    lw_, lh = box[2] - box[0], box[3] - box[1]
    layer = Image.new("RGBA", (int(lw_ + pad * 2), int(lh + pad * 2)), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    ox, oy = layer.width / 2, layer.height / 2
    # yumuşak gölge
    ld.text((ox, oy + size * 0.06), s, font=f, anchor="mm", fill=(0, 0, 0, 160),
            stroke_width=int(stroke) + 2, stroke_fill=(0, 0, 0, 160))
    layer = layer.filter(ImageFilter.GaussianBlur(size * 0.03))
    ld = ImageDraw.Draw(layer)
    if glow:
        g = Image.new("RGBA", layer.size, (0, 0, 0, 0))
        ImageDraw.Draw(g).text((ox, oy), s, font=f, anchor="mm", fill=glow + (255,),
                               stroke_width=int(stroke * 1.6), stroke_fill=glow + (255,))
        layer = Image.alpha_composite(layer, g.filter(ImageFilter.GaussianBlur(size * 0.09)))
        ld = ImageDraw.Draw(layer)
    ld.text((ox, oy), s, font=f, anchor="mm", fill=fill, stroke_width=int(stroke), stroke_fill=OUT)
    if rot:
        layer = layer.rotate(rot, resample=Image.BICUBIC, expand=True)
    canvas.alpha_composite(layer, (int(xy[0] - layer.width / 2), int(xy[1] - layer.height / 2)))
    return canvas


def pill(canvas, cx, cy, w, h, col, rot=0):
    layer = Image.new("RGBA", (int(w + 40 * SS), int(h + 40 * SS)), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ox, oy = layer.width / 2, layer.height / 2
    d.rounded_rectangle([ox - w / 2, oy - h / 2, ox + w / 2, oy + h / 2], radius=h * 0.32,
                        fill=col, outline=OUT, width=int(6 * SS))
    d.rounded_rectangle([ox - w / 2 + 8 * SS, oy - h / 2 + 7 * SS, ox + w / 2 - 8 * SS, oy - h * 0.05],
                        radius=h * 0.22, fill=tuple(min(255, c + 40) for c in col[:3]))
    if rot:
        layer = layer.rotate(rot, resample=Image.BICUBIC, expand=True)
    canvas.alpha_composite(layer, (int(cx - layer.width / 2), int(cy - layer.height / 2)))
    return canvas


def arrow(canvas, x0, y0, x1, y1, col=(255, 60, 70), width=26):
    width *= SS
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ang = math.atan2(y1 - y0, x1 - x0)
    hx, hy = x1 - math.cos(ang) * width * 2.2, y1 - math.sin(ang) * width * 2.2
    d.line([x0, y0, hx, hy], fill=col, width=int(width))
    n = (math.cos(ang + math.pi / 2), math.sin(ang + math.pi / 2))
    tip = (x1, y1)
    b1 = (hx + n[0] * width * 2, hy + n[1] * width * 2)
    b2 = (hx - n[0] * width * 2, hy - n[1] * width * 2)
    d.polygon([tip, b1, b2], fill=col)
    # koyu kontur
    edge = _dilate(layer.split()[3], 5 * SS)
    ring = Image.new("RGBA", (W, H), OUT + (0,))
    ring.putalpha(edge)
    return Image.alpha_composite(Image.alpha_composite(canvas, ring), layer)


def circle_mark(canvas, cx, cy, r, col=(255, 60, 70), width=16):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.arc([cx - r, cy - r, cx + r, cy + r], -60, 250, fill=col, width=int(width * SS))
    return Image.alpha_composite(canvas, layer)


def sparkle(canvas, cx, cy, r, col=(255, 244, 150)):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    pts = []
    for i in range(8):
        a = i * math.pi / 4 - math.pi / 2
        rr = r * SS if i % 2 == 0 else r * SS * 0.3
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=col)
    return Image.alpha_composite(canvas, layer)


def cash_burst(canvas, cx, cy, seed):
    rng = random.Random(seed)
    art = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(art)
    for _ in range(14):
        x = cx + rng.uniform(-1, 1) * 340 * SS
        y = cy + rng.uniform(-1, 1) * 220 * SS
        w = rng.uniform(70, 110) * SS
        h = w * 0.55
        ang = rng.uniform(-35, 35)
        b = Image.new("RGBA", (int(w * 1.7), int(w * 1.7)), (0, 0, 0, 0))
        bd = ImageDraw.Draw(b)
        ox, oy = b.width / 2, b.height / 2
        bd.rounded_rectangle([ox - w / 2, oy - h / 2, ox + w / 2, oy + h / 2], radius=8 * SS,
                             fill=(110, 200, 90), outline=OUT, width=int(5 * SS))
        rr = h * 0.3
        bd.ellipse([ox - rr, oy - rr, ox + rr, oy + rr], fill=(80, 170, 70), outline=(50, 120, 50), width=int(3 * SS))
        f = _font(h * 0.5)
        bd.text((ox, oy), "$", font=f, anchor="mm", fill=(210, 250, 190))
        b = b.rotate(ang, resample=Image.BICUBIC)
        art.alpha_composite(b, (int(x - b.width / 2), int(y - b.height / 2)))
    return Image.alpha_composite(canvas, art)


# ─── Thumbnail'lar ───────────────────────────────────────────────────────────

def thumb_steal_run():
    """1: Hırsız kaçıyor, ağlayan kurbanı kolundan sürüklüyor. Sahibi geride bağırıyor."""
    img = space(1, top=(60, 16, 74))
    ground = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(ground).ellipse([-W * 0.2, H * 0.86, W * 1.2, H * 1.25], fill=(30, 20, 55, 255))
    img = Image.alpha_composite(img, ground)
    d = ImageDraw.Draw(img)

    # kol: hırsızdan kurbana (arkada kalsın)
    arm(d, W * 0.6, H * 0.62, W * 0.47, H * 0.66, THIEF, 30 * SS, int(9 * SS))
    # kurban: sürüklenen, ağlayan (geriye yatık)
    img = place(img, crewmate(430 * SS, GREEN, face=-1, expr="cry", tilt=28), W * 0.42, H * 0.9)
    # hırsız: koşan, sırıtan
    img = place(img, crewmate(560 * SS, THIEF, face=1, expr="evil", tilt=-10), W * 0.66, H * 0.94)
    # geride bağıran sahip
    img = place(img, crewmate(300 * SS, BLUE, face=1, expr="shock", tilt=0), W * 0.16, H * 0.9)

    img = arrow(img, W * 0.2, H * 0.5, W * 0.36, H * 0.62, width=22)
    img = sparkle(img, W * 0.72, H * 0.24, 34)
    img = vignette(img)
    img = text(img, (W * 0.5, H * 0.16), "HE STOLE MY", 150, rot=-3)
    img = text(img, (W * 0.5, H * 0.32), "CREWMATE!!", 220, fill=(255, 70, 82), glow=(120, 0, 0), rot=-3)
    img = text(img, (W * 0.18, H * 0.66), "NOOO", 96, fill=(120, 210, 255), rot=-12)
    return img


def thumb_nobody_safe():
    """2: Dev hırsız, çaldığı kurbanı havaya kaldırmış; küçükler kaçışıyor."""
    img = space(2, top=(20, 20, 80))
    d = ImageDraw.Draw(img)
    img = cash_burst(img, W * 0.7, H * 0.5, 5)
    # kaçışan küçükler
    img = place(img, crewmate(250 * SS, YELLOW, face=-1, expr="shock", tilt=14), W * 0.12, H * 0.92)
    img = place(img, crewmate(230 * SS, PINK, face=-1, expr="cry", tilt=18), W * 0.28, H * 0.95)
    # dev hırsız ortada
    img = place(img, crewmate(720 * SS, THIEF, face=1, expr="laugh"), W * 0.56, H * 1.02)
    # havaya kaldırılan kurban
    d = ImageDraw.Draw(img)
    arm(d, W * 0.56, H * 0.42, W * 0.6, H * 0.2, THIEF, 30 * SS, int(9 * SS))
    img = place(img, crewmate(300 * SS, GREEN, face=-1, expr="cry", tilt=-8), W * 0.63, H * 0.28, shadow=False)
    img = circle_mark(img, W * 0.63, H * 0.24, 220 * SS)
    img = sparkle(img, W * 0.86, H * 0.2, 30)
    img = vignette(img)
    img = text(img, (W * 0.5, H * 0.15), "NOBODY IS SAFE", 200, fill=(255, 220, 60), glow=(120, 60, 0), rot=-2)
    img = text(img, (W * 0.22, H * 0.4), "RUN!", 110, fill=(255, 90, 90), rot=-10)
    return img


def thumb_whole_crew():
    """3: Hırsız bir konveyör dolusu çalınmış mürettebatı götürüyor, para yağıyor."""
    img = space(3, top=(16, 40, 60))
    d = ImageDraw.Draw(img)
    # konveyör bandı
    band_y = H * 0.7
    d.rounded_rectangle([W * 0.14, band_y, W * 0.9, band_y + 46 * SS], radius=22 * SS,
                        fill=(70, 78, 96), outline=OUT, width=int(8 * SS))
    for x in range(int(W * 0.16), int(W * 0.9), int(60 * SS)):
        d.line([x, band_y + 8 * SS, x + 26 * SS, band_y + 38 * SS], fill=(255, 205, 60), width=int(7 * SS))
    # çalınmış mürettebat sırası
    for i, col in enumerate([BLUE, YELLOW, GREEN, PINK, ORANGE]):
        img = place(img, crewmate(230 * SS, col, face=1, expr="cry" if i % 2 else "shock"),
                    W * (0.24 + i * 0.12), band_y + 6 * SS, shadow=False)
    # hırsız önde çekiyor
    img = place(img, crewmate(560 * SS, THIEF, face=1, expr="money", tilt=-6), W * 0.86, H * 0.96)
    img = cash_burst(img, W * 0.8, H * 0.4, 9)
    img = sparkle(img, W * 0.5, H * 0.5, 26)
    img = vignette(img)
    img = text(img, (W * 0.5, H * 0.16), "STEAL THEIR", 150, rot=-2)
    img = text(img, (W * 0.5, H * 0.32), "WHOLE CREW", 210, fill=(90, 255, 120), glow=(0, 90, 20), rot=-2)
    return img


def thumb_rich_or_robbed():
    """4: Solda para üstünde zengin hırsız; sağda soyulmuş boş kaide + '?' kurban."""
    img = space(4, top=(50, 20, 60))
    d = ImageDraw.Draw(img)
    # orta ayraç
    d.line([W * 0.5, H * 0.1, W * 0.5, H * 0.9], fill=(255, 255, 255, 40), width=int(6 * SS))
    # SOL: zengin
    img = cash_burst(img, W * 0.26, H * 0.55, 2)
    d = ImageDraw.Draw(img)
    for i in range(5):
        si_cx = W * (0.16 + i * 0.04)
        d.rounded_rectangle([si_cx - 60 * SS, H * 0.8 - i * 8 * SS, si_cx + 60 * SS, H * 0.86 - i * 8 * SS],
                            radius=14 * SS, fill=(255, 200, 44), outline=OUT, width=int(5 * SS))
    img = place(img, crewmate(470 * SS, THIEF, face=1, expr="money"), W * 0.26, H * 0.86)
    # SAĞ: soyulmuş
    img = place_podium(img, W * 0.74, H * 0.86)
    img = text(img, (W * 0.74, H * 0.5), "?", 260, fill=(255, 205, 60), rot=6)
    img = place(img, crewmate(360 * SS, BLUE, face=-1, expr="cry", tilt=-6), W * 0.86, H * 0.9)
    img = vignette(img)
    img = text(img, (W * 0.27, H * 0.2), "GET RICH", 150, fill=(255, 220, 60), glow=(120, 70, 0), rot=-3)
    img = text(img, (W * 0.73, H * 0.2), "OR ROBBED", 150, fill=(255, 80, 90), glow=(120, 0, 0), rot=3)
    return img


def place_podium(img, x, y):
    d = ImageDraw.Draw(img)
    w, h = 240 * SS, 120 * SS
    col = (70, 120, 210)
    top = y - h
    d.ellipse([x - w / 2, y - w * 0.15, x + w / 2, y + w * 0.15], fill=shade(col, 0.72), outline=OUT, width=int(7 * SS))
    d.rectangle([x - w / 2, top, x + w / 2, y], fill=shade(col, 0.72))
    d.line([x - w / 2, top, x - w / 2, y], fill=OUT, width=int(7 * SS))
    d.line([x + w / 2, top, x + w / 2, y], fill=OUT, width=int(7 * SS))
    d.ellipse([x - w / 2, top - w * 0.15, x + w / 2, top + w * 0.15], fill=shade(col, 1.25), outline=OUT, width=int(7 * SS))
    return img


def thumb_trust_no_one():
    """5: Bir mürettebat, habersiz bir oyuncunun arkasına sinsice yaklaşıyor."""
    img = space(5, top=(30, 12, 44), bottom=(4, 4, 16))
    # habersiz kurban (önde, sakin)
    img = place(img, crewmate(560 * SS, YELLOW, face=-1, expr="neutral"), W * 0.38, H * 0.96)
    # arkadan sinsi hırsız (kırmızı, sırıtan) — parmak ucunda tıpış tıpış
    img = place(img, crewmate(600 * SS, THIEF, face=-1, expr="evil", tilt=6), W * 0.66, H * 0.98)
    img = circle_mark(img, W * 0.68, H * 0.62, 310 * SS)
    img = sparkle(img, W * 0.2, H * 0.24, 30)
    img = vignette(img)
    img = text(img, (W * 0.5, H * 0.17), "TRUST NO ONE", 210, fill=(255, 255, 255), glow=(120, 0, 0), rot=-2)
    img = pill(img, W * 0.5, H * 0.34, 620 * SS, 120 * SS, (214, 38, 52), rot=-2)
    img = text(img, (W * 0.5, H * 0.335), "THEY WANT YOUR CREW", 74, rot=-2)
    return img


THUMBS = [thumb_steal_run, thumb_nobody_safe, thumb_whole_crew, thumb_rich_or_robbed, thumb_trust_no_one]


def main():
    os.makedirs(DEST, exist_ok=True)
    finals = []
    for i, make in enumerate(THUMBS, 1):
        img = make().convert("RGB").resize((1920, 1080), Image.LANCZOS)
        path = os.path.join(DEST, f"thumb_{i}.png")
        img.save(path, optimize=True)
        finals.append(img)
        print("thumb_%d" % i)
    # önizleme dikey şerit
    pw = 640
    sheet = Image.new("RGB", (pw, int(pw * 9 / 16) * len(finals) + 4 * (len(finals) - 1)), (24, 22, 32))
    yy = 0
    for img in finals:
        t = img.resize((pw, int(pw * 9 / 16)), Image.LANCZOS)
        sheet.paste(t, (0, yy))
        yy += t.height + 4
    sheet.save(os.path.join(DEST, "_preview.png"))
    print("preview ok")


if __name__ == "__main__":
    main()
