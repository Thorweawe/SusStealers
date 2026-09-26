"""
Roblox oyun sayfası küçük resimleri (thumbnail) ve oyun ikonu.

    python tools/thumbnails.py   ->  thumbnails/thumb_*.png (1920x1080)
                                     thumbnails/icon.png    (512x512)
                                     thumbnails/_preview.png

Popüler "Steal a ..." oyunlarının kapak dili: parlak zemin, dev yaratık,
elinde nadir bir şey kaçıran Roblox karakteri, "YOU!" + kırmızı ok,
gökkuşağı eşya adı ve yeşil $/s. Her şey 4K çizilip küçültülüyor.
Gerekenler: pip install pillow
"""

import math
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(ROOT, "thumbnails")
FONT = "C:/Windows/Fonts/ariblk.ttf"
W, H = 3840, 2160
OUT = (20, 18, 30)

SKIN = (252, 230, 208)
HAIR = (214, 104, 44)
JACKET = (42, 42, 52)
SHIRT = (40, 100, 236)
PANTS = (38, 92, 62)
RED = (238, 34, 44)


# ─── Renk ve maske yardımcıları ───────────────────────────────────────────


def mix(a, b, t):
    return tuple(int(round(x + (y - x) * t)) for x, y in zip(a[:3], b[:3]))


def lit(c, t):
    return mix(c, (255, 255, 255), t)


def dim(c, t):
    return mix(c, (0, 0, 0), t)


def blank(w, h):
    return Image.new("RGBA", (int(w), int(h)), (0, 0, 0, 0))


def mask(w, h):
    return Image.new("L", (int(w), int(h)), 0)


def solid(size, col, alpha):
    im = Image.new("RGBA", size, tuple(col[:3]) + (255,))
    im.putalpha(alpha)
    return im


def dilate(m, r):
    if r <= 0:
        return m
    return m.filter(ImageFilter.GaussianBlur(r / 1.8)).point(lambda v: 255 if v > 8 else 0).filter(ImageFilter.GaussianBlur(1.2))


def rounded(m, r):
    """Dışbükey köşeleri yuvarlat (blok parçalar keskin durmasın)."""
    return m.filter(ImageFilter.GaussianBlur(r)).point(lambda v: 255 if v > 127 else 0)


def shift(m, dx, dy):
    out = Image.new(m.mode, m.size, 0)
    out.paste(m, (int(dx), int(dy)))
    return out


def scale_alpha(m, a):
    return m.point(lambda v: v * a // 255)


def ramp(L, stops):
    """Gri görüntüyü renk duraklarıyla boya: stops = [(t, renk), ...]."""
    chans = []
    for i in range(3):
        lut = []
        for v in range(256):
            t = v / 255
            val = stops[-1][1][i]
            for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
                if t <= t1:
                    k = (t - t0) / (t1 - t0) if t1 > t0 else 0
                    val = c0[i] + (c1[i] - c0[i]) * max(0.0, min(1.0, k))
                    break
            lut.append(int(val))
        chans.append(L.point(lut))
    return Image.merge("RGB", chans)


_RG = Image.radial_gradient("L")


def radial_L(size, cx, cy, R):
    """(cx,cy)'de 0, R uzaklıkta ve ötesinde 255."""
    s = max(4, int(256 * R / 181))
    g = _RG.resize((s, s), Image.BILINEAR)
    base = Image.new("L", size, 255)
    base.paste(g, (int(cx - s / 2), int(cy - s / 2)))
    return base


def vgrad(size, stops):
    return ramp(Image.linear_gradient("L").resize(size, Image.BILINEAR), stops)


def hgrad(size, stops):
    return ramp(Image.linear_gradient("L").rotate(90).transpose(Image.FLIP_LEFT_RIGHT).resize(size, Image.BILINEAR), stops)


RAINBOW = [(0.0, (255, 50, 60)), (0.17, (255, 150, 30)), (0.34, (255, 235, 40)), (0.5, (70, 230, 80)),
           (0.67, (40, 200, 255)), (0.84, (110, 90, 255)), (1.0, (240, 70, 220))]


def rainbow_tex(size):
    L = Image.linear_gradient("L").rotate(-35, resample=Image.BICUBIC, fillcolor=255).resize(size, Image.BILINEAR)
    return ramp(L, RAINBOW)


def galaxy_tex(size, seed=7):
    w, h = size
    img = vgrad(size, [(0, (120, 40, 210)), (0.55, (40, 20, 120)), (1, (10, 20, 70))]).convert("RGBA")
    rng = random.Random(seed)
    neb = blank(w, h)
    d = ImageDraw.Draw(neb)
    for _ in range(9):
        x, y, r = rng.uniform(0, w), rng.uniform(0, h), rng.uniform(0.12, 0.3) * w
        col = rng.choice([(255, 80, 200), (60, 220, 255), (170, 90, 255)])
        d.ellipse([x - r, y - r, x + r, y + r], fill=col + (110,))
    img.alpha_composite(neb.filter(ImageFilter.GaussianBlur(w * 0.06)))
    d = ImageDraw.Draw(img)
    for _ in range(int(w * h / 1400)):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.choice([1, 1, 2, 2, 3, 4]) * w / 600
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, rng.randint(140, 255)))
    return img.convert("RGB")


def shaded(m, col, light=(0.3, 0.2), hi=0.45, lo=0.5, reach=1.05):
    bb = m.getbbox()
    if not bb:
        return blank(*m.size)
    x0, y0, x1, y1 = bb
    bw, bh = x1 - x0, y1 - y0
    L = radial_L(m.size, x0 + bw * light[0], y0 + bh * light[1], max(bw, bh) * reach)
    rgb = ramp(L, [(0, lit(col, hi)), (0.38, tuple(col[:3])), (1, dim(col, lo))]).convert("RGBA")
    rgb.putalpha(m)
    return rgb


# ─── Çizim tuvali ─────────────────────────────────────────────────────────


class Sprite:
    def __init__(self, w, h, ow=8):
        self.img = blank(w, h)
        self.size = self.img.size
        self.ow = ow

    def m(self):
        return mask(*self.size)

    def put(self, m, col=(255, 255, 255), ow=None, light=(0.3, 0.2), hi=0.45, lo=0.5, tex=None, flat=False,
            ocol=OUT, alpha=255):
        ow = self.ow if ow is None else ow
        if ow:
            self.img.alpha_composite(solid(self.size, ocol, dilate(m, ow)))
        if tex is not None:
            g = shaded(m, (128, 128, 128), light, 0.55, 0.6).convert("RGB")
            f = ImageChops.overlay(tex.convert("RGB").resize(self.size, Image.BILINEAR), g).convert("RGBA")
            f.putalpha(m)
        elif flat:
            f = solid(self.size, col, m)
        else:
            f = shaded(m, col, light, hi, lo)
        if alpha < 255:
            f.putalpha(scale_alpha(f.getchannel("A"), alpha))
        self.img.alpha_composite(f)

    def soft(self, box, col=(255, 255, 255), alpha=120, blur=None, clip=None):
        """Bulanık parlama/gölge lekesi (isteğe bağlı bir maskeye kırpılı)."""
        m = self.m()
        ImageDraw.Draw(m).ellipse(box, fill=alpha)
        bw = box[2] - box[0]
        m = m.filter(ImageFilter.GaussianBlur(blur if blur is not None else bw * 0.12))
        if clip is not None:
            m = ImageChops.multiply(m, clip)
        self.img.alpha_composite(solid(self.size, col, m))


def rrect(m, box, r):
    ImageDraw.Draw(m).rounded_rectangle([min(box[0], box[2]), min(box[1], box[3]), max(box[0], box[2]), max(box[1], box[3])],
                                        radius=r, fill=255)
    return m


def ell(m, box):
    ImageDraw.Draw(m).ellipse(box, fill=255)
    return m


def poly(m, pts):
    ImageDraw.Draw(m).polygon([tuple(p) for p in pts], fill=255)
    return m


def seg(m, p0, p1, w, ext=0.1):
    """p0->p1 arası köşeli uzuv (R15 blok parçası)."""
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    L = math.hypot(dx, dy) or 1
    ux, uy = dx / L, dy / L
    nx, ny = -uy, ux
    e = w * ext
    a = (p0[0] - ux * e, p0[1] - uy * e)
    b = (p1[0] + ux * e, p1[1] + uy * e)
    return poly(m, [(a[0] + nx * w / 2, a[1] + ny * w / 2), (b[0] + nx * w / 2, b[1] + ny * w / 2),
                    (b[0] - nx * w / 2, b[1] - ny * w / 2), (a[0] - nx * w / 2, a[1] - ny * w / 2)])


def step(p, ang, length):
    """Açı 0 = aşağı, pozitif = sağa."""
    a = math.radians(ang)
    return (p[0] + math.sin(a) * length, p[1] + math.cos(a) * length)


def bezier(p0, p1, p2, p3, n=60):
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        pts.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return pts


def star_pts(cx, cy, r, n=4, inner=0.28, rot=-90):
    pts = []
    for i in range(n * 2):
        a = math.radians(rot + i * 180 / n)
        rr = r if i % 2 == 0 else r * inner
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    return pts


# ─── Mürettebat (crewmate) ────────────────────────────────────────────────


def crewmate(h, col, face=1, tex=None, angry=False, mouth=False, tongue=0, sleepy=False, visor_col=(130, 205, 238), crown=False):
    """Sağa bakan mürettebat; `tongue` > 0 ise o kadar uzunlukta dil. Döner: (img, bilgi)."""
    pad = 0.14 * h
    sw = int(h * 1.3 + tongue * 1.1 + pad)
    sh = int(h * 1.18 + (0.25 * h if crown else 0))
    ow = max(5, h * 0.014)
    s = Sprite(sw, sh, ow)
    top = pad + (0.25 * h if crown else 0)
    by = top + h
    w = 0.74 * h
    cx = pad + 0.2 * h + w / 2
    dark = dim(col, 0.28)

    s.put(rrect(s.m(), (cx - w / 2 - 0.15 * h, top + 0.3 * h, cx - w / 2 + 0.12 * h, top + 0.68 * h), 0.07 * h),
          dark if tex is None else dim(col, 0.1), tex=tex)

    body = s.m()
    rrect(body, (cx - w / 2, top, cx + w / 2, by - 0.2 * h), 0.46 * w)
    rrect(body, (cx - w / 2, by - 0.45 * h, cx - 0.04 * w, by), 0.1 * h)
    rrect(body, (cx + 0.06 * w, by - 0.45 * h, cx + w / 2, by), 0.1 * h)
    s.put(body, col, tex=tex, light=(0.62, 0.18), hi=0.5, lo=0.55)
    # arka kenar ışığı
    rim = ImageChops.subtract(body, shift(body, 0.05 * h, 0.02 * h))
    s.img.alpha_composite(solid(s.size, lit(col, 0.6), scale_alpha(rim.filter(ImageFilter.GaussianBlur(h * 0.012)), 120)))
    s.soft((cx - 0.05 * w, top + 0.04 * h, cx + 0.34 * w, top + 0.17 * h), alpha=110, clip=body)

    vx0, vx1 = cx - 0.06 * w, cx + w / 2 + 0.1 * h
    vy0, vy1 = top + 0.15 * h, top + 0.43 * h
    vw = vx1 - vx0
    visor = rrect(s.m(), (vx0, vy0, vx1, vy1), 0.13 * h)
    if angry:
        # öfkeli vizör: üst kenar öne doğru eğik kesik, içi kızgın parlıyor
        cut = poly(s.m(), [(vx0 - h, vy0 - h), (vx1 + h, vy0 - h), (vx1 + 0.1 * h, vy0 + 0.15 * h), (vx0 + 0.1 * vw, vy0 - 0.005 * h), (vx0 - h, vy0 - 0.005 * h)])
        visor = ImageChops.subtract(visor, cut)
        glow_col = (255, 60, 30) if sum(col) > 200 else (255, 40, 40)
        s.img.alpha_composite(solid(s.size, glow_col, scale_alpha(visor.filter(ImageFilter.GaussianBlur(h * 0.03)), 160)))
        s.put(visor, glow_col, light=(0.6, 0.55), hi=0.8, lo=0.25)
        s.soft((vx0 + 0.35 * vw, vy0 + 0.35 * (vy1 - vy0), vx1 - 0.08 * vw, vy0 + 0.72 * (vy1 - vy0)), (255, 245, 190), 240, clip=visor)
    else:
        s.put(visor, visor_col, light=(0.62, 0.2), hi=0.6, lo=0.45)
        if sleepy:
            lid = rrect(s.m(), (vx0 - 0.02 * h, vy0 - 0.05 * h, vx1 + 0.05 * h, vy0 + 0.66 * (vy1 - vy0)), 0.1 * h)
            lid = ImageChops.multiply(lid, dilate(visor, ow * 0.6))
            s.put(lid, col, tex=tex, light=(0.6, 0.0), hi=0.35, lo=0.4)
            ImageDraw.Draw(s.img).arc((vx0 + 0.25 * vw, vy0 + 0.35 * (vy1 - vy0), vx0 + 0.85 * vw, vy0 + 0.85 * (vy1 - vy0)),
                                      15, 165, fill=OUT, width=int(ow * 1.1))
        else:
            gl = rrect(s.m(), (vx0 + 0.46 * vw, vy0 + 0.05 * h, vx0 + 0.86 * vw, vy0 + 0.115 * h), 0.03 * h)
            s.put(gl, (255, 255, 255), ow=0, flat=True, alpha=235)
            s.put(ell(s.m(), (vx0 + 0.3 * vw, vy0 + 0.055 * h, vx0 + 0.39 * vw, vy0 + 0.115 * h)), (255, 255, 255), ow=0, flat=True, alpha=200)

    info = {"visor": ((vx0 + vx1) / 2, (vy0 + vy1) / 2), "top": (cx, top), "feet": (cx, by), "center": (cx, (top + by) / 2),
            "front": (vx1, vy1)}

    if mouth:
        mx0, mx1 = cx - 0.22 * w, cx + w / 2 + 0.07 * h
        my0, my1 = top + 0.47 * h, top + 0.78 * h
        mo = ell(s.m(), (mx0, my0, mx1, my1))
        s.put(mo, (110, 0, 20), light=(0.4, 0.8), hi=0.2, lo=0.6)
        s.soft((mx0 + 0.1 * (mx1 - mx0), my0 + 0.35 * (my1 - my0), mx1 - 0.1 * (mx1 - mx0), my1 + 0.1 * h), (30, 0, 5), 200, clip=mo)
        mcx, mcy, rx, ry = (mx0 + mx1) / 2, (my0 + my1) / 2, (mx1 - mx0) / 2, (my1 - my0) / 2
        teeth = s.m()
        n = 6
        for i in range(n):
            for side in (-1, 1):
                a0 = math.pi + (i / n) * math.pi if side < 0 else (i / n) * math.pi
                a1 = a0 + math.pi / n
                am = (a0 + a1) / 2
                p0 = (mcx + math.cos(a0) * rx, mcy + math.sin(a0) * ry)
                p1 = (mcx + math.cos(a1) * rx, mcy + math.sin(a1) * ry)
                tip = (mcx + math.cos(am) * rx * 0.55, mcy + math.sin(am) * ry * 0.35)
                poly(teeth, [p0, p1, tip])
        s.put(ImageChops.multiply(teeth, mo), (250, 248, 235), ow=ow * 0.55, light=(0.5, 0.2), hi=0.3, lo=0.3)
        info["mouth"] = (mcx, mcy)
        if tongue:
            p0 = (mcx - 0.05 * h, mcy + 0.02 * h)
            tip = (mx1 + tongue, mcy - 0.05 * h)
            pts = bezier(p0, (mcx + tongue * 0.35, mcy + 0.3 * h), (mcx + tongue * 0.65, mcy - 0.35 * h), tip, 80)
            tg = s.m()
            d = ImageDraw.Draw(tg)
            for i, (x, y) in enumerate(pts):
                r = h * (0.075 - 0.04 * i / len(pts))
                d.ellipse((x - r, y - r, x + r, y + r), fill=255)
            x2, y2 = pts[-1]
            x1, y1 = pts[-4]
            ang = math.atan2(y2 - y1, x2 - x1)
            r = h * 0.06
            poly(tg, [(x2 + math.cos(ang) * r * 2.4, y2 + math.sin(ang) * r * 2.4),
                      (x2 + math.cos(ang + 1.9) * r, y2 + math.sin(ang + 1.9) * r),
                      (x2 + math.cos(ang - 1.9) * r, y2 + math.sin(ang - 1.9) * r)])
            s.put(tg, (255, 96, 140), light=(0.5, 0.1), hi=0.4, lo=0.45)
            s.img.alpha_composite(solid(s.size, (255, 220, 235), scale_alpha(ImageChops.subtract(tg, shift(tg, 0, h * 0.02)), 150)))
            info["tongue_tip"] = (x2 + math.cos(ang) * r * 2.4, y2)

    if crown:
        cy0 = top - 0.02 * h
        cw = 0.46 * w
        ccx = cx + 0.08 * w
        pts = [(ccx - cw / 2, cy0), (ccx - cw / 2 - 0.02 * h, cy0 - 0.2 * h), (ccx - cw / 4, cy0 - 0.09 * h),
               (ccx, cy0 - 0.24 * h), (ccx + cw / 4, cy0 - 0.09 * h), (ccx + cw / 2 + 0.02 * h, cy0 - 0.2 * h), (ccx + cw / 2, cy0)]
        s.put(rounded(poly(s.m(), pts), h * 0.006), (255, 200, 40), light=(0.4, 0.2), hi=0.6, lo=0.45)
        for gx, gc in ((ccx - cw / 4, (255, 60, 90)), (ccx + cw / 4, (60, 200, 255)), (ccx, (90, 255, 120))):
            gr = 0.03 * h
            s.put(ell(s.m(), (gx - gr, cy0 - 0.075 * h - gr, gx + gr, cy0 - 0.075 * h + gr)), gc, ow=ow * 0.5, hi=0.7)

    img = s.img
    if face < 0:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
        info = {k: (img.width - v[0], v[1]) for k, v in info.items()}
    return img, info


# ─── Roblox karakteri ─────────────────────────────────────────────────────


def avatar(u, pose="run", face="smug", held=None, look=1):
    """R15 blok karakter. held = crewmate() çıktısı. Döner: (img, bilgi)."""
    lift = pose == "lift"
    sw, sh = int(u * 7.4), int(u * (14 if lift else 8.6))
    ow = max(5, u * 0.07)
    s = Sprite(sw, sh, ow)
    hx, hy = sw / 2, sh - u * 2.35
    legw, armw = 0.96 * u, 0.9 * u

    def limb(start, angs, lens, w, col, joint=True):
        pts = [start]
        for a, L in zip(angs, lens):
            pts.append(step(pts[-1], a, L))
        for i in range(len(pts) - 2, -1, -1):
            m = seg(s.m(), pts[i], pts[i + 1], w * (1 - 0.04 * i))
            if joint and i > 0:
                ell(m, (pts[i][0] - w * 0.46, pts[i][1] - w * 0.46, pts[i][0] + w * 0.46, pts[i][1] + w * 0.46))
            s.put(rounded(m, u * 0.05), col if i == 0 else dim(col, 0.04), light=(0.3, 0.15))
        return pts

    # bacaklar: arka sonra ön
    if pose == "run":
        legs = [((-0.48, 0), (-38, -100)), ((0.48, 0), (52, 8))]
    else:
        legs = [((-0.5, 0), (-14, -4)), ((0.5, 0), (14, 4))]
    for (ox, oy), angs in legs:
        pts = limb((hx + ox * u, hy + oy * u - 0.1 * u), angs, (1.05 * u, 1.05 * u), legw, PANTS)
    # gövde
    torso = rrect(s.m(), (hx - u, hy - 2.05 * u, hx + u, hy + 0.12 * u), 0.2 * u)
    s.put(torso, JACKET, light=(0.35, 0.15), hi=0.25)
    shirt = poly(s.m(), [(hx - 0.36 * u, hy - 1.98 * u), (hx + 0.36 * u, hy - 1.98 * u), (hx + 0.42 * u, hy + 0.08 * u), (hx - 0.42 * u, hy + 0.08 * u)])
    s.put(shirt, SHIRT, ow=ow * 0.5, light=(0.4, 0.1), hi=0.35)
    for sx in (-1, 1):
        lap = poly(s.m(), [(hx + sx * 0.36 * u, hy - 2.0 * u), (hx + sx * 0.62 * u, hy - 2.0 * u), (hx + sx * 0.4 * u, hy - 1.2 * u)])
        s.put(lap, dim(JACKET, 0.3), ow=0, flat=True)

    shL = (hx - 1.38 * u, hy - 1.72 * u)
    shR = (hx + 1.38 * u, hy - 1.72 * u)
    hand = 0.62 * u

    def put_hand(p):
        s.put(rounded(rrect(s.m(), (p[0] - hand / 2, p[1] - hand / 2, p[0] + hand / 2, p[1] + hand / 2), 0.14 * u), u * 0.03),
              SKIN, light=(0.3, 0.2), hi=0.35, lo=0.35)

    info = {}
    if lift:
        L = limb(shL, (-168, -178), (1.0 * u, 0.95 * u), armw, JACKET)
        R = limb(shR, (168, 178), (1.0 * u, 0.95 * u), armw, JACKET)
    else:
        # üst kollar arkada, önkollar eşyanın önünde
        L = [shL, step(shL, 16, 1.0 * u)]
        R = [shR, step(shR, -16, 1.0 * u)]
        for a, b in ((L[0], L[1]), (R[0], R[1])):
            s.put(rounded(seg(s.m(), a, b, armw), u * 0.05), JACKET, light=(0.3, 0.15), hi=0.25)

    head = None

    def draw_head():
        nonlocal head
        hw, hh = 1.42 * u, 1.3 * u
        hcx = hx + 0.06 * u * look
        hcy = hy - 2.05 * u - 0.6 * u
        x0, y0, x1, y1 = hcx - hw / 2, hcy - hh / 2, hcx + hw / 2, hcy + hh / 2
        head = (x0, y0, x1, y1)
        hm = rrect(s.m(), (x0, y0, x1, y1), 0.34 * u)
        s.put(hm, SKIN, light=(0.35 + 0.1 * look, 0.25), hi=0.4, lo=0.3)
        fc = hcx + 0.1 * hw * look
        # saç (bacon)
        hair = s.m()
        ell(hair, (x0 - 0.12 * hw, y0 - 0.36 * hh, x1 + 0.12 * hw, y0 + 0.4 * hh))
        rrect(hair, (x0 - 0.13 * hw, y0, x0 + 0.14 * hw, y0 + 0.78 * hh), 0.08 * u)
        rrect(hair, (x1 - 0.1 * hw, y0, x1 + 0.13 * hw, y0 + 0.62 * hh), 0.08 * u)
        n = 6
        for i in range(n):
            xa = x0 + 0.02 * hw + i * (hw * 0.96 / n)
            xb = xa + hw * 0.96 / n
            tipx = xa + (xb - xa) * (0.25 if look > 0 else 0.75)
            poly(hair, [(xa, y0 + 0.3 * hh), (xb, y0 + 0.3 * hh), (tipx, y0 + (0.5 if i % 2 else 0.44) * hh)])
        poly(hair, [(x0 + 0.1 * hw, y0 - 0.2 * hh), (x0 - 0.3 * hw, y0 - 0.05 * hh), (x0 - 0.05 * hw, y0 + 0.2 * hh)])
        poly(hair, [(x1 - 0.1 * hw, y0 - 0.2 * hh), (x1 + 0.28 * hw, y0 + 0.02 * hh), (x1 + 0.02 * hw, y0 + 0.22 * hh)])
        hair = rounded(hair, u * 0.03)
        s.put(hair, HAIR, light=(0.4, 0.1), hi=0.4, lo=0.45)
        d = ImageDraw.Draw(s.img)
        for i in range(4):
            xs = x0 + (0.15 + i * 0.22) * hw
            d.arc((xs - 0.15 * hw, y0 - 0.3 * hh, xs + 0.15 * hw, y0 + 0.35 * hh), 200, 300, fill=dim(HAIR, 0.35), width=int(ow * 0.7))
        s.soft((x0 + 0.1 * hw, y0 - 0.3 * hh, x0 + 0.55 * hw, y0 - 0.08 * hh), alpha=120, clip=hair)

        ey = y0 + 0.58 * hh
        ex = [fc - 0.2 * hw, fc + 0.2 * hw]
        if face == "cry":
            for i, x in enumerate(ex):
                sgn = 1 if i == 0 else -1
                d.line([(x - sgn * 0.08 * hw, ey - 0.08 * hh), (x + sgn * 0.06 * hw, ey), (x - sgn * 0.08 * hw, ey + 0.08 * hh)],
                       fill=OUT, width=int(0.055 * hh), joint="curve")
                tear = rrect(s.m(), (x - 0.045 * hw, ey + 0.06 * hh, x + 0.045 * hw, y1 - 0.02 * hh), 0.04 * hw)
                s.put(tear, (110, 200, 255), ow=ow * 0.4, light=(0.4, 0.1), hi=0.6)
            for x, y, r in ((x0 - 0.18 * hw, ey - 0.05 * hh, 0.07), (x1 + 0.2 * hw, ey - 0.12 * hh, 0.08), (x1 + 0.34 * hw, ey + 0.1 * hh, 0.05)):
                drop = poly(s.m(), [(x, y - r * 2.2 * hw), (x + r * hw, y), (x - r * hw, y)])
                ell(drop, (x - r * hw, y - r * hw, x + r * hw, y + r * hw))
                s.put(drop, (110, 200, 255), ow=ow * 0.4, hi=0.6)
            mo = ell(s.m(), (fc - 0.22 * hw, y0 + 0.74 * hh, fc + 0.22 * hw, y0 + 0.96 * hh))
            s.put(mo, (120, 20, 35), ow=ow * 0.8, light=(0.5, 0.8), hi=0.2)
            s.put(ImageChops.multiply(ell(s.m(), (fc - 0.14 * hw, y0 + 0.86 * hh, fc + 0.14 * hw, y0 + 1.02 * hh)), mo), (255, 110, 130), ow=0)
            s.put(ImageChops.multiply(rrect(s.m(), (fc - 0.2 * hw, y0 + 0.72 * hh, fc + 0.2 * hw, y0 + 0.79 * hh), 4), mo), (255, 255, 255), ow=0, flat=True)
            for i, x in enumerate(ex):
                sgn = -1 if i == 0 else 1
                d.line([(x - 0.08 * hw, ey - 0.2 * hh + sgn * 0.03 * hh), (x + 0.08 * hw, ey - 0.2 * hh - sgn * 0.03 * hh)], fill=OUT, width=int(0.05 * hh))
        else:
            for x in ex:
                e = ell(s.m(), (x - 0.065 * hw, ey - 0.1 * hh, x + 0.065 * hw, ey + 0.1 * hh))
                s.put(e, OUT, ow=0, flat=True)
                s.put(ell(s.m(), (x - 0.01 * hw, ey - 0.075 * hh, x + 0.04 * hw, ey - 0.02 * hh)), (255, 255, 255), ow=0, flat=True)
            # kaşlar: biri kalkık (kendini beğenmiş)
            d.line([(ex[0] - 0.1 * hw, ey - 0.2 * hh), (ex[0] + 0.08 * hw, ey - 0.16 * hh)], fill=OUT, width=int(0.055 * hh))
            d.line([(ex[1] - 0.08 * hw, ey - 0.2 * hh), (ex[1] + 0.1 * hw, ey - 0.28 * hh)], fill=OUT, width=int(0.055 * hh))
            # sırıtış
            top_pts = [(fc - 0.24 * hw, y0 + 0.77 * hh), (fc + 0.28 * hw, y0 + 0.7 * hh)]
            bot = [(fc + 0.28 * hw - t * 0.52 * hw, y0 + 0.7 * hh + 0.07 * hh * t + math.sin(t * math.pi) * 0.14 * hh) for t in [i / 20 for i in range(21)]]
            grin = poly(s.m(), top_pts + bot)
            s.put(grin, (255, 255, 255), ow=ow * 0.8, flat=True)
            d.line([(fc - 0.2 * hw, y0 + 0.8 * hh), (fc + 0.24 * hw, y0 + 0.75 * hh)], fill=(170, 170, 180), width=int(ow * 0.5))
            s.put(ell(s.m(), (fc + 0.22 * hw, y0 + 0.66 * hh, fc + 0.33 * hw, y0 + 0.74 * hh)), (230, 170, 150), ow=0, flat=True, alpha=0)
        info["head_top"] = (hcx, y0 - 0.36 * hh)
        info["head"] = (hcx, hcy)

    if lift:
        draw_head()
        if held is not None:
            him, hinfo = held
            top_y = head[1] - 0.45 * u
            ox = int(hx - hinfo["feet"][0])
            oy = int(top_y + 0.15 * u - hinfo["feet"][1])
            s.img.alpha_composite(him, (ox, oy))
            info["held"] = (hx, oy + hinfo["center"][1])
            info["held_r"] = him.height * 0.5
        put_hand(L[-1])
        put_hand(R[-1])
    else:
        draw_head()
        if held is not None:
            him, hinfo = held
            cx, cy = hx + 0.1 * u * look, hy - 0.5 * u
            ox, oy = int(cx - hinfo["center"][0]), int(cy - hinfo["center"][1])
            s.img.alpha_composite(him, (ox, oy))
            info["held"] = (cx, cy)
            info["held_r"] = him.height * 0.5
        for sh_, a in ((L, 72), (R, -72)):
            p1 = sh_[1]
            p2 = step(p1, a, 0.95 * u)
            s.put(rounded(seg(s.m(), p1, p2, armw * 0.96), u * 0.05), JACKET, light=(0.3, 0.1), hi=0.3)
            put_hand(step(p2, a, 0.15 * u))
    info["feet"] = (hx, sh - 0.2 * u)
    return s.img, info


# ─── Yerleştirme ──────────────────────────────────────────────────────────


def comp(canvas, img, x, y):
    x, y = int(round(x)), int(round(y))
    sx, sy = max(0, -x), max(0, -y)
    if sx >= img.width or sy >= img.height:
        return
    if sx or sy:
        img = img.crop((sx, sy, img.width, img.height))
    canvas.alpha_composite(img, (x + sx, y + sy))


def place(canvas, img, anchor, at, angle=0, scale=1.0, rim=None, shadow=0, under=None):
    """Resmin `anchor` noktasını tuvalde `at`e koy. Resim-içi noktaları tuvale çeviren fonksiyon döner."""
    if scale != 1.0:
        img = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
    w0, h0 = img.size
    if angle:
        img = img.rotate(angle, Image.BICUBIC, expand=True)
    a = math.radians(angle)

    def tf(p):
        dx, dy = p[0] * scale - w0 / 2, p[1] * scale - h0 / 2
        return (img.width / 2 + dx * math.cos(a) + dy * math.sin(a), img.height / 2 - dx * math.sin(a) + dy * math.cos(a))

    ax, ay = tf(anchor)
    ox, oy = at[0] - ax, at[1] - ay

    def to_canvas(p):
        q = tf(p)
        return (q[0] + ox, q[1] + oy)

    if under:
        under(to_canvas)
    if rim:
        col, r = rim
        a_ = img.getchannel("A")
        halo = solid(img.size, col, dilate(a_, r).filter(ImageFilter.GaussianBlur(r * 0.6)))
        comp(canvas, halo, ox, oy)
    if shadow:
        sh = solid(img.size, (0, 0, 0), scale_alpha(img.getchannel("A"), shadow)).filter(ImageFilter.GaussianBlur(18))
        comp(canvas, sh, ox + 14, oy + 22)
    comp(canvas, img, ox, oy)
    return to_canvas


def aura(canvas, info, col, k=1.05, alpha=180):
    """Tutulan eşyanın arkasına parlama; place(..., under=aura_cb(...)) ile."""
    def cb(tf):
        cx, cy = tf(info["held"])
        r = info["held_r"] * k
        m = mask(W, H)
        ImageDraw.Draw(m).ellipse((cx - r, cy - r, cx + r, cy + r), fill=alpha)
        canvas.alpha_composite(solid((W, H), col, m.filter(ImageFilter.GaussianBlur(r * 0.35))))
    return cb


def ground_shadow(canvas, cx, cy, rx, ry, alpha=110):
    m = mask(W, H)
    ImageDraw.Draw(m).ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=alpha)
    canvas.alpha_composite(solid((W, H), (10, 10, 30), m.filter(ImageFilter.GaussianBlur(ry * 0.5))))


# ─── Yazı, ok, ünlem ──────────────────────────────────────────────────────


def text_art(txt, size, fill=(255, 255, 255), stroke=OUT, sw=0.13, outer=None, extrude=0.08, gloss=True):
    f = ImageFont.truetype(FONT, int(size))
    sww = int(size * sw)
    ext = int(size * extrude)
    ow_ = int(outer[1]) if outer else 0
    pad = sww + ext + ow_ + 20
    l, t, r, b = f.getbbox(txt)
    w, h = int(r - l + pad * 2), int(b - t + pad * 2)
    org = (pad - l, pad - t)
    fm = mask(w, h)
    ImageDraw.Draw(fm).text(org, txt, font=f, fill=255)
    sm = mask(w, h)
    ImageDraw.Draw(sm).text(org, txt, font=f, fill=255, stroke_width=sww, stroke_fill=255)
    full = sm.copy()
    for dy in range(1, ext + 1, 2):
        full = ImageChops.lighter(full, shift(sm, 0, dy))
    img = blank(w, h)
    if outer:
        img.alpha_composite(solid((w, h), outer[0], dilate(full, ow_)))
    img.alpha_composite(solid((w, h), dim(stroke, 0.35), full))
    img.alpha_composite(solid((w, h), stroke, sm))
    if isinstance(fill, Image.Image):
        tex = fill.resize((w, h)).convert("RGBA")
        tex.putalpha(fm)
        img.alpha_composite(tex)
    else:
        img.alpha_composite(solid((w, h), fill, fm))
    if gloss:
        top = mask(w, h)
        ImageDraw.Draw(top).rectangle((0, 0, w, pad + (b - t) * 0.42), fill=90)
        img.alpha_composite(solid((w, h), (255, 255, 255), ImageChops.multiply(top, fm)))
    return img


def put_text(canvas, txt, center, size, angle=0, **kw):
    img = text_art(txt, size, **kw)
    if angle:
        img = img.rotate(angle, Image.BICUBIC, expand=True)
    sh = solid(img.size, (0, 0, 0), scale_alpha(img.getchannel("A"), 110)).filter(ImageFilter.GaussianBlur(size * 0.05))
    comp(canvas, sh, center[0] - img.width / 2 + size * 0.03, center[1] - img.height / 2 + size * 0.06)
    comp(canvas, img, center[0] - img.width / 2, center[1] - img.height / 2)


def money_fill(size=(64, 64)):
    return vgrad(size, [(0, (200, 255, 120)), (0.5, (90, 235, 60)), (1, (30, 170, 40))])


def rainbow_fill():
    return hgrad((512, 64), RAINBOW)


def gold_fill():
    return vgrad((64, 64), [(0, (255, 250, 190)), (0.45, (255, 205, 50)), (1, (225, 130, 10))])


def arrow(canvas, p0, p1, bend, width, col=RED):
    """p0'dan p1'e kavisli kalın ok (uç p1'de)."""
    mx, my = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
    dx, dy = p1[0] - p0[0], p1[1] - p0[1]
    L = math.hypot(dx, dy)
    nx, ny = -dy / L, dx / L
    c = (mx + nx * bend, my + ny * bend)
    pts = [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0], (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1])
           for t in [i / 60 * 0.74 for i in range(61)]]
    m = mask(W, H)
    d = ImageDraw.Draw(m)
    for i, (x, y) in enumerate(pts):
        r = width / 2 * (0.7 + 0.3 * i / len(pts))
        d.ellipse((x - r, y - r, x + r, y + r), fill=255)
    bx, by = pts[-1]
    ang = math.atan2(p1[1] - by, p1[0] - bx)
    hw = width * 1.25
    d.polygon([p1, (bx + math.cos(ang + math.pi / 2) * hw, by + math.sin(ang + math.pi / 2) * hw),
               (bx + math.cos(ang - math.pi / 2) * hw, by + math.sin(ang - math.pi / 2) * hw)], fill=255)
    wr = width * 0.26
    canvas.alpha_composite(solid((W, H), (0, 0, 0), scale_alpha(shift(dilate(m, wr + 10), 12, 20), 100).filter(ImageFilter.GaussianBlur(14))))
    canvas.alpha_composite(solid((W, H), OUT, dilate(m, wr + 10)))
    canvas.alpha_composite(solid((W, H), (255, 255, 255), dilate(m, wr)))
    canvas.alpha_composite(shaded(m, col, (0.3, 0.1), 0.35, 0.45))
    canvas.alpha_composite(solid((W, H), (255, 255, 255), scale_alpha(ImageChops.subtract(m, shift(m, 0, width * 0.18)), 110)))


def exclaim(canvas, cx, cy, size, angle=0, n=2, col=RED):
    sw = int(size * (0.5 * n + 0.3))
    s = Sprite(sw, size * 1.4, 0)
    m = s.m()
    for i in range(n):
        x = size * 0.35 + i * size * 0.5
        poly(m, [(x - size * 0.16, size * 0.15), (x + size * 0.16, size * 0.15), (x + size * 0.08, size * 0.85), (x - size * 0.08, size * 0.85)])
        ell(m, (x - size * 0.12, size * 0.95, x + size * 0.12, size * 1.19))
    m = rounded(m, size * 0.03)
    s.img.alpha_composite(solid(s.size, OUT, dilate(m, size * 0.11)))
    s.img.alpha_composite(solid(s.size, (255, 255, 255), dilate(m, size * 0.075)))
    s.img.alpha_composite(shaded(m, col, (0.3, 0.1), 0.4, 0.4))
    place(canvas, s.img, (sw / 2, size * 0.7), (cx, cy), angle=angle, shadow=90)


def sparkle(canvas, cx, cy, r, col=(255, 255, 255), glow=True):
    m = mask(int(r * 4), int(r * 4))
    poly(m, star_pts(r * 2, r * 2, r))
    im = blank(r * 4, r * 4)
    if glow:
        im.alpha_composite(solid(im.size, col, scale_alpha(dilate(m, r * 0.3).filter(ImageFilter.GaussianBlur(r * 0.3)), 170)))
    im.alpha_composite(solid(im.size, (255, 255, 255), m))
    comp(canvas, im, cx - r * 2, cy - r * 2)


def zzz(canvas, x, y, size):
    for i, k in enumerate((0.55, 0.78, 1.0)):
        put_text(canvas, "Z", (x + i * size * 0.6, y - i * size * 0.75), size * k, angle=12 + i * 6,
                 fill=(255, 255, 255), stroke=(40, 90, 230), sw=0.16, extrude=0.06)


# ─── Arka planlar ─────────────────────────────────────────────────────────


def bg_burst(top, bottom, center, rays=26, ray_alpha=34, glow=(255, 255, 255), glow_r=900):
    img = vgrad((W, H), [(0, top), (1, bottom)]).convert("RGBA")
    rl = blank(W, H)
    d = ImageDraw.Draw(rl)
    R = W * 1.5
    for i in range(rays):
        a0 = i / rays * math.tau
        a1 = a0 + math.tau / rays * 0.5
        d.polygon([center, (center[0] + math.cos(a0) * R, center[1] + math.sin(a0) * R),
                   (center[0] + math.cos(a1) * R, center[1] + math.sin(a1) * R)], fill=(255, 255, 255, ray_alpha))
    img.alpha_composite(rl)
    g = mask(W, H)
    ImageDraw.Draw(g).ellipse((center[0] - glow_r, center[1] - glow_r, center[0] + glow_r, center[1] + glow_r), fill=170)
    img.alpha_composite(solid((W, H), glow, g.filter(ImageFilter.GaussianBlur(glow_r * 0.45))))
    return img


def speed_lines(canvas, center, n=60, seed=1, alpha=150, r0=1300):
    rng = random.Random(seed)
    m = mask(W, H)
    d = ImageDraw.Draw(m)
    for _ in range(n):
        a = rng.uniform(0, math.tau)
        r1 = rng.uniform(r0, r0 * 1.5)
        r2 = r1 + rng.uniform(500, 1400)
        wdt = rng.uniform(6, 20)
        ca, sa = math.cos(a), math.sin(a)
        d.polygon([(center[0] + ca * r1, center[1] + sa * r1),
                   (center[0] + ca * r2 - sa * wdt, center[1] + sa * r2 + ca * wdt),
                   (center[0] + ca * r2 + sa * wdt, center[1] + sa * r2 - ca * wdt)], fill=rng.randint(alpha // 2, alpha))
    canvas.alpha_composite(solid((W, H), (255, 255, 255), m))


def stars(canvas, n, seed, area=(0, 0, W, H), cols=((255, 255, 255), (200, 230, 255), (255, 210, 240))):
    rng = random.Random(seed)
    d = ImageDraw.Draw(canvas)
    for _ in range(n):
        x, y = rng.uniform(area[0], area[2]), rng.uniform(area[1], area[3])
        r = rng.choice([2, 3, 3, 4, 5, 7])
        d.ellipse((x - r, y - r, x + r, y + r), fill=rng.choice(cols) + (rng.randint(120, 255),))


def nebula(canvas, blobs):
    layer = blank(W, H)
    d = ImageDraw.Draw(layer)
    for x, y, r, col, a in blobs:
        d.ellipse((x - r, y - r, x + r, y + r), fill=col + (a,))
    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(220)))


def planet(canvas, cx, cy, r, col, ring=None, seed=3):
    s = Sprite(r * 3.2, r * 3.2, 10)
    c = r * 1.6
    m = ell(s.m(), (c - r, c - r, c + r, c + r))
    if ring:
        back = s.m()
        ImageDraw.Draw(back).ellipse((c - r * 1.55, c - r * 0.42, c + r * 1.55, c + r * 0.42), outline=255, width=int(r * 0.13))
        s.put(ImageChops.subtract(back, m), ring, ow=0, hi=0.4, lo=0.3)
    s.put(m, col, ow=0, light=(0.3, 0.25), hi=0.5, lo=0.65)
    rng = random.Random(seed)
    for _ in range(5):
        x, y, rr = c + rng.uniform(-0.6, 0.6) * r, c + rng.uniform(-0.6, 0.6) * r, rng.uniform(0.08, 0.2) * r
        s.put(ImageChops.multiply(ell(s.m(), (x - rr, y - rr, x + rr, y + rr * 0.8)), m), dim(col, 0.2), ow=0, hi=0.1, lo=0.2, light=(0.7, 0.8))
    if ring:
        front = s.m()
        ImageDraw.Draw(front).ellipse((c - r * 1.55, c - r * 0.42, c + r * 1.55, c + r * 0.42), outline=255, width=int(r * 0.13))
        front.paste(0, (0, 0, int(s.size[0]), int(c)))
        s.put(front, ring, ow=0, hi=0.5, lo=0.3)
    comp(canvas, s.img, cx - c, cy - c)


def floor(canvas, y, far, near, vp_x, grid=(255, 255, 255), grid_a=60, tiles=16, rows=9, curve=0):
    m = mask(W, H)
    if curve:
        ImageDraw.Draw(m).ellipse((-W * 0.4, y, W * 1.4, y + curve * 2), fill=255)
        ImageDraw.Draw(m).rectangle((0, y + curve, W, H), fill=255)
    else:
        ImageDraw.Draw(m).rectangle((0, y, W, H), fill=255)
    g = vgrad((W, H - int(y)), [(0, far), (1, near)])
    layer = blank(W, H)
    layer.paste(g, (0, int(y)))
    layer.putalpha(m)
    lines = blank(W, H)
    d = ImageDraw.Draw(lines)
    vy = y - 900
    for i in range(-tiles, tiles * 2):
        xb = W / 2 + (i - tiles / 2) * (W / tiles) * 2.2
        d.line([(vp_x + (xb - vp_x) * (y - vy) / (H * 1.2 - vy), y), (xb, H * 1.2)], fill=grid + (grid_a,), width=6)
    for j in range(1, rows):
        t = (j / rows) ** 1.8
        yy = y + (H - y) * t
        d.line([(0, yy), (W, yy)], fill=grid + (grid_a,), width=int(4 + 6 * t))
    lines.putalpha(ImageChops.multiply(lines.getchannel("A"), m))
    layer.alpha_composite(lines)
    edge = ImageChops.subtract(m, shift(m, 0, 16))
    layer.alpha_composite(solid((W, H), (255, 255, 255), scale_alpha(edge, 150)))
    canvas.alpha_composite(layer)


def vignette(canvas, strength=120):
    m = radial_L((W, H), W / 2, H / 2, W * 0.75).point(lambda v: max(0, v - 120) * strength // 135)
    canvas.alpha_composite(solid((W, H), (0, 0, 20), m))


# ─── Sahneler ─────────────────────────────────────────────────────────────


def scene_chase():
    """Dev impostor ağzı açık kovalıyor, sen gökkuşağı mürettebatla kaçıyorsun."""
    c = bg_burst((30, 150, 255), (150, 225, 255), (2700, 1000), glow_r=1000)
    speed_lines(c, (2700, 1000), 70, seed=4)
    floor(c, 1560, (190, 215, 245), (95, 120, 170), 2400, grid=(255, 255, 255), grid_a=70)

    imp, ii = crewmate(2150, (225, 25, 35), angry=True, mouth=True, tongue=900)
    ground_shadow(c, 1050, 2080, 900, 120)
    tf = place(c, imp, ii["feet"], (980, 2230), angle=-7, shadow=0, rim=((255, 255, 255), 10))

    held = crewmate(700, (255, 255, 255), tex=rainbow_tex((1000, 1000)), face=1)
    av, ai = avatar(245, "run", "smug", held=held, look=-1)
    _aura = (255, 245, 160)
    ground_shadow(c, 2980, 2010, 520, 80)
    ta = place(c, av, ai["feet"], (2980, 2020), angle=-5, rim=((255, 255, 255), 9), under=aura(c, ai, _aura))
    hc = ta(ai["held"])
    for dx, dy, r in ((-420, -300, 70), (390, -250, 55), (430, 180, 45), (-380, 260, 40), (0, -470, 35)):
        sparkle(c, hc[0] + dx, hc[1] + dy, r, (255, 240, 120))

    exclaim(c, 620, 380, 430, angle=10)
    head = ta(ai["head_top"])
    put_text(c, "YOU!", (3400, 300), 330, angle=-8)
    arrow(c, (3560, 520), (head[0] + 90, head[1] - 10), -220, 120)
    vignette(c, 70)
    return c


def scene_sleep():
    """Uyuyan dev impostorun yanından galaksi mürettebatını kaçırmak."""
    c = vgrad((W, H), [(0, (30, 10, 80)), (0.6, (110, 30, 170)), (1, (200, 60, 210))]).convert("RGBA")
    nebula(c, [(3000, 500, 700, (255, 80, 220), 110), (600, 300, 600, (80, 120, 255), 110), (2200, 1100, 900, (255, 120, 255), 90)])
    stars(c, 420, 11, (0, 0, W, 1500))
    for x, y, r in ((500, 260, 50), (3500, 180, 42), (2150, 150, 36), (1500, 520, 30)):
        sparkle(c, x, y, r, (255, 150, 255))
    floor(c, 1400, (170, 60, 220), (230, 70, 200), 2500, grid=(255, 180, 255), grid_a=80, curve=0)

    planet(c, 3450, 330, 170, (255, 170, 80), ring=(255, 230, 170))
    big, bi = crewmate(1550, (34, 32, 48), face=-1, sleepy=True, visor_col=(120, 100, 200))
    ground_shadow(c, 2900, 1990, 850, 110)
    tb = place(c, big, bi["feet"], (2900, 2030), angle=4, rim=((255, 150, 255), 12))
    v = tb(bi["visor"])
    # sümük balonu
    bub = Sprite(460, 460, 7)
    m = ell(bub.m(), (30, 30, 430, 430))
    bub.put(m, (190, 240, 255), alpha=120, hi=0.8, lo=0.0, light=(0.3, 0.25), ocol=(255, 255, 255))
    bub.soft((100, 90, 210, 170), alpha=240)
    bub.soft((300, 300, 360, 350), alpha=200)
    comp(c, bub.img, v[0] - 620, v[1] - 40)
    zzz(c, v[0] + 350, v[1] - 420, 250)

    held = crewmate(700, (30, 30, 50), face=-1, tex=galaxy_tex((1000, 1000)))
    av, ai = avatar(215, "run", "smug", held=held, look=-1)
    _aura = (200, 120, 255)
    av = av.transpose(Image.FLIP_LEFT_RIGHT)
    flipx = lambda p: (av.width - p[0], p[1])  # noqa: E731
    ground_shadow(c, 1000, 2030, 520, 80)
    ta = place(c, av, flipx(ai["feet"]), (1000, 2040), angle=5, rim=((255, 255, 255), 9), under=aura(c, {"held": flipx(ai["held"]), "held_r": ai["held_r"]}, _aura))
    hc = ta(flipx(ai["held"]))
    for dx, dy, r in ((-400, -280, 60), (380, -330, 50), (-380, 200, 40), (420, 150, 45)):
        sparkle(c, hc[0] + dx, hc[1] + dy, r, (200, 150, 255))
    head = ta(flipx(ai["head_top"]))

    put_text(c, "YOU!", (470, 330), 280, angle=10)
    arrow(c, (760, 470), (head[0] - 30, head[1] - 20), -200, 110)
    put_text(c, "AMOGUS PRIME", (1850, 250), 180, angle=-3, fill=rainbow_fill())
    put_text(c, "$18.1M/s", (1850, 450), 160, angle=-3, fill=money_fill(), stroke=(10, 70, 20))
    vignette(c, 60)
    return c


def scene_frost():
    """Buz diyarı: dev beyaz impostor arkadan uzanıyor, ağlayarak Golden Jester'la kaçıyorsun."""
    c = bg_burst((80, 180, 255), (210, 240, 255), (1300, 900), rays=20, ray_alpha=30, glow_r=900)
    rng = random.Random(21)
    snow = blank(W, H)
    d = ImageDraw.Draw(snow)
    for _ in range(260):
        x, y, r = rng.uniform(0, W), rng.uniform(0, H), rng.choice([4, 6, 8, 10, 14])
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, rng.randint(120, 230)))
    # buz kristalleri
    for x, y, hgt, a in ((250, 1500, 600, 8), (420, 1520, 380, -12), (3500, 1450, 700, -6), (3700, 1500, 420, 12), (3300, 1480, 300, 18)):
        s = Sprite(hgt * 0.8, hgt * 1.2, 8)
        cw = hgt * 0.3
        m = poly(s.m(), [(s.size[0] / 2, 10), (s.size[0] / 2 + cw, hgt * 0.35), (s.size[0] / 2 + cw * 0.8, hgt), (s.size[0] / 2 - cw * 0.8, hgt), (s.size[0] / 2 - cw, hgt * 0.35)])
        s.put(m, (150, 225, 255), light=(0.3, 0.2), hi=0.7, lo=0.35, alpha=235)
        place(c, s.img, (s.size[0] / 2, hgt), (x, y), angle=a)
    floor(c, 1450, (225, 245, 255), (160, 205, 245), 1900, grid=(255, 255, 255), grid_a=40, curve=160)

    mon, mi = crewmate(1900, (235, 242, 255), angry=True, mouth=True)
    ground_shadow(c, 900, 2050, 900, 110)
    place(c, mon, mi["feet"], (820, 2250), angle=-10, rim=((120, 200, 255), 12))

    # yuva: kaide üstünde iki mavi yumurta-mürettebat
    s = Sprite(900, 420, 9)
    s.put(rrect(s.m(), (60, 200, 840, 400), 60), (255, 200, 60), light=(0.4, 0.1), hi=0.5)
    for x, col in ((260, (120, 190, 255)), (560, (150, 215, 255))):
        cm, cinfo = crewmate(300, col, face=1 if x < 400 else -1)
        s.img.alpha_composite(cm, (int(x - cinfo["feet"][0] + 40), int(260 - cinfo["feet"][1])))
    place(c, s.img, (450, 400), (2000, 2060), rim=((255, 255, 255), 8))

    held = crewmate(640, (255, 200, 40), face=1)
    av, ai = avatar(215, "run", "cry", held=held, look=1)
    _aura = (255, 220, 80)
    ground_shadow(c, 2980, 2030, 520, 80)
    ta = place(c, av, ai["feet"], (2980, 2040), angle=-4, rim=((255, 255, 255), 9), under=aura(c, ai, _aura))
    hc = ta(ai["held"])
    for dx, dy, r in ((-420, -260, 60), (400, -300, 55), (420, 200, 40), (-400, 220, 45)):
        sparkle(c, hc[0] + dx, hc[1] + dy, r, (255, 220, 90))
    head = ta(ai["head_top"])
    c.alpha_composite(snow)

    put_text(c, "YOU!", (3440, 310), 270, angle=-10)
    arrow(c, (3230, 460), (head[0] + 60, head[1] - 20), -200, 110)
    put_text(c, "GOLDEN JESTER", (1900, 250), 170, angle=-3, fill=gold_fill(), stroke=(110, 60, 0))
    put_text(c, "$169.5M/s", (1900, 440), 150, angle=-3, fill=money_fill(), stroke=(10, 70, 20))
    exclaim(c, 330, 380, 330, angle=-10)
    vignette(c, 50)
    return c


def scene_lift():
    """Uyuyan dev mürettebatın yanında dev Triple Impostor'u başının üstüne kaldırmak."""
    c = bg_burst((255, 150, 40), (255, 225, 120), (2900, 900), rays=24, ray_alpha=40, glow=(255, 250, 200), glow_r=950)
    speed_lines(c, (2900, 900), 50, seed=9, alpha=120)
    floor(c, 1500, (255, 200, 110), (225, 130, 50), 1600, grid=(255, 240, 200), grid_a=60, curve=120)

    big, bi = crewmate(1350, (255, 130, 30), face=1, sleepy=True)
    ground_shadow(c, 1150, 2000, 800, 110)
    tb = place(c, big, bi["feet"], (1150, 2050), angle=-3, rim=((255, 255, 255), 10))
    v = tb(bi["visor"])
    zzz(c, 330, 1000, 200)

    held = crewmate(900, (150, 10, 30), face=-1, angry=True)
    av, ai = avatar(185, "lift", "smug", held=held, look=-1)
    _aura = (255, 80, 60)
    ground_shadow(c, 2950, 2060, 520, 80)
    ta = place(c, av, ai["feet"], (2850, 2080), angle=2, rim=((255, 255, 255), 9), under=aura(c, ai, _aura))
    hc = ta(ai["held"])
    for dx, dy, r in ((-620, -200, 70), (600, -350, 60), (650, 250, 45), (-560, 300, 50)):
        sparkle(c, hc[0] + dx, hc[1] + dy, r, (255, 150, 90))

    put_text(c, "TRIPLE IMPOSTOR", (1100, 230), 170, angle=-3, fill=rainbow_fill())
    put_text(c, "$5.2M/s", (1100, 430), 160, angle=-3, fill=money_fill(), stroke=(10, 70, 20))
    head = ta(ai["head"])
    put_text(c, "YOU!", (3440, 1700), 250, angle=8)
    arrow(c, (3420, 1520), (head[0] + 190, head[1] + 40), 200, 100)
    vignette(c, 50)
    return c


# ─── İkon ─────────────────────────────────────────────────────────────────


def make_icon():
    global W, H
    W0, H0 = W, H
    W = H = 2048
    try:
        c = bg_burst((255, 60, 70), (140, 0, 30), (1024, 900), rays=22, ray_alpha=40, glow=(255, 200, 120), glow_r=700)
        speed_lines(c, (1024, 900), 40, seed=2, alpha=110, r0=800)
        imp, ii = crewmate(1500, (25, 25, 35), face=-1, angry=True, mouth=True)
        place(c, imp, ii["feet"], (1380, 1750), angle=6)
        held = crewmate(560, (255, 255, 255), tex=rainbow_tex((900, 900)), face=1)
        av, ai = avatar(190, "run", "smug", held=held, look=1)
        _aura = (255, 245, 160)
        ta = place(c, av, ai["feet"], (800, 2010), angle=-4, rim=((255, 255, 255), 10), under=aura(c, ai, _aura))
        hc = ta(ai["held"])
        for dx, dy, r in ((-380, -280, 70), (360, -300, 60), (-380, 220, 45)):
            sparkle(c, hc[0] + dx, hc[1] + dy, r, (255, 240, 120))
        exclaim(c, 1720, 330, 320, angle=12)
        vignette(c, 60)
        return c.convert("RGB").resize((512, 512), Image.LANCZOS)
    finally:
        W, H = W0, H0


def main():
    os.makedirs(DEST, exist_ok=True)
    scenes = [("thumb_1_chase", scene_chase), ("thumb_2_sleep", scene_sleep), ("thumb_3_frost", scene_frost), ("thumb_4_lift", scene_lift)]
    outs = []
    for name, fn in scenes:
        img = fn().convert("RGB").resize((1920, 1080), Image.LANCZOS)
        img.save(os.path.join(DEST, name + ".png"))
        outs.append(img)
        print("ok", name)
    icon = make_icon()
    icon.save(os.path.join(DEST, "icon.png"))
    print("ok icon")
    prev = Image.new("RGB", (1920, 1080 + 540), (20, 20, 30))
    for i, im in enumerate(outs):
        prev.paste(im.resize((960, 540), Image.LANCZOS), ((i % 2) * 960, (i // 2) * 540))
    prev.paste(icon.resize((540, 540)), (0, 1080))
    prev.save(os.path.join(DEST, "_preview.png"))


if __name__ == "__main__":
    import sys
    only = sys.argv[1:]
    if only:
        os.makedirs(DEST, exist_ok=True)
        for n in only:
            if n == "icon":
                make_icon().save(os.path.join(DEST, "icon.png"))
            else:
                globals()["scene_" + n]().convert("RGB").resize((1920, 1080), Image.LANCZOS).save(os.path.join(DEST, "thumb_" + n + ".png"))
            print("ok", n)
    else:
        main()
