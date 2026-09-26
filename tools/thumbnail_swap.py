"""
Oyun sayfası thumbnail'ları: dev crewmate yerine BAŞKA BİR OYUNCU.

    python tools/thumbnail_swap.py            ->  branding/thumbnails/thumb_1..4.png (1920x1080)
                                                  branding/thumbnails/icon.png       (512x512)
                                                  branding/thumbnails/_preview.png
    python tools/thumbnail_swap.py thumb_3    ->  sadece birini yeniden üret

Kaynaklar branding/thumbnails/src/ altında (orijinal thumbnail'lar). Her
görselde dev crewmate = crewmate'i çalınan DİĞER OYUNCU. Onu siliyoruz
(GrabCut maskesi + inpaint), yerine aynı parlak/plastik stilde dev bir Roblox
oyuncusu çiziyoruz. Orijinalin güzel parçaları (köpekbalığı ağzı + dil, "!!",
"Zzz", balon, kaide, YOU! karakteri, yazılar) piksel piksel korunuyor.

Gerekenler: pip install pillow numpy opencv-python-headless
"""

import math
import os

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "branding", "thumbnails", "src")
DEST = os.path.join(ROOT, "branding", "thumbnails")

SS = 2                      # avatar 2x çiziliyor, sonra küçülüyor (yumuşak kenar)
OUT = (26, 20, 32)          # koyu kontur (orijinallerdeki gibi)


# ─── Maskeler ───────────────────────────────────────────────────────────────

def fill_holes(m):
    cs, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    out = np.zeros_like(m)
    cv2.drawContours(out, cs, -1, 255, -1)
    return out


def largest(m):
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    if n <= 1:
        return m
    k = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    return np.where(lab == k, 255, 0).astype(np.uint8)


def poly_mask(shape, poly):
    m = np.zeros(shape[:2], np.uint8)
    cv2.fillPoly(m, [np.array(poly, np.int32)], 255)
    return m


def grabcut(bgr, poly, iters=6):
    """Kaba poligon içindeki dev crewmate'in sıkı maskesi."""
    m = np.full(bgr.shape[:2], cv2.GC_BGD, np.uint8)
    cv2.fillPoly(m, [np.array(poly, np.int32)], cv2.GC_PR_FGD)
    bgd, fgd = np.zeros((1, 65)), np.zeros((1, 65))
    cv2.grabCut(bgr, m, None, bgd, fgd, iters, cv2.GC_INIT_WITH_MASK)
    fg = np.where((m == 1) | (m == 3), 255, 0).astype(np.uint8)
    return fill_holes(largest(fg))


def dilate(m, r):
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))
    return cv2.dilate(m, k)


def erode(m, r):
    k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * r + 1, 2 * r + 1))
    return cv2.erode(m, k)


def white_sticker(bgr, box, thr=215, grow=7, dark=110, min_area=900):
    """Beyaz çerçeveli çıkartma (!!, Zzz): beyazı bul, içini doldur; dıştaki
    ince koyu konturu da al ama onun ötesindeki zemini alma."""
    x0, y0, x1, y1 = box
    sub = bgr[y0:y1, x0:x1]
    w = np.where(sub.min(axis=2) >= thr, 255, 0).astype(np.uint8)
    w = cv2.morphologyEx(w, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    inside = fill_holes(w)
    n, lab, st, _ = cv2.connectedComponentsWithStats(inside)
    for i in range(1, n):       # ince parıltı/kenar parçalarını at, harfler kalsın
        if st[i, cv2.CC_STAT_AREA] < min_area:
            inside[lab == i] = 0
    rim = dilate(inside, grow) & np.where(sub.max(axis=2) < dark, 255, 0).astype(np.uint8)
    m = np.zeros(bgr.shape[:2], np.uint8)
    m[y0:y1, x0:x1] = inside | rim
    return m


def hsv(bgr):
    return [c.astype(np.int32) for c in cv2.split(cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV))]


def tongue_mask(bgr, poly):
    """Pembe dil + kendi koyu konturu."""
    h, s, v = hsv(bgr)
    pink = ((h >= 155) & (h <= 176) & (s > 50) & (v > 140)).astype(np.uint8) * 255
    pink = largest(pink & poly_mask(bgr.shape, poly))
    darkpx = (v < 110).astype(np.uint8) * 255
    return pink | (dilate(pink, 9) & darkpx)


def not_body(bgr, poly, body_fn, clean=3):
    """Poligon içinde gövde rengi OLMAYAN pikseller (ağız, dil, kontur)."""
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV).astype(np.int32)
    body = body_fn(hsv[..., 0], hsv[..., 1], hsv[..., 2])
    m = np.where(body, 0, 255).astype(np.uint8) & poly_mask(bgr.shape, poly)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((clean, clean), np.uint8))
    return m


# ─── Plastik gölgelendirme ──────────────────────────────────────────────────

def shade(mask, color, bevel=0.12, gloss=0.55, light=(-0.55, -0.85), spec=(0.30, 0.16, 0.24, 0.09)):
    """Maskeyi 3D plastik gibi boyar: kenar bombesi + ışık gradyanı + parlama.
    mask: uint8 (0/255). (rgb float HxWx3, alpha float HxW) döner, bbox'a kırpılı değil."""
    H, W = mask.shape
    ys, xs = np.nonzero(mask > 127)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    pad = 4
    x0, y0 = max(0, x0 - pad), max(0, y0 - pad)
    x1, y1 = min(W, x1 + pad), min(H, y1 + pad)
    m = (mask[y0:y1, x0:x1] > 127).astype(np.uint8)
    bw, bh = x1 - x0, y1 - y0
    bv = max(4.0, bevel * min(bw, bh))
    dist = cv2.distanceTransform(m, cv2.DIST_L2, 5)
    h = np.sin(np.clip(dist / bv, 0, 1) * np.pi / 2)
    h = cv2.GaussianBlur(h, (0, 0), 1.5)
    gy, gx = np.gradient(h)
    nx, ny, nz = -gx * bv * 0.8, -gy * bv * 0.8, np.ones_like(h)
    n = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    L = np.array([light[0], light[1], 1.1])
    L = L / np.linalg.norm(L)
    diff = (nx * L[0] + ny * L[1] + nz * L[2]) / n
    fac = 0.50 + 0.62 * np.clip(diff, -0.3, 1.0) / L[2]
    Y, X = np.mgrid[0:bh, 0:bw].astype(np.float32)
    glob = 1.10 - 0.36 * (0.35 * X / bw + 0.65 * Y / bh)
    rgb = np.array(color, np.float32)[None, None, :] * (glob * fac)[..., None]
    # parlama: sol üstte yumuşak beyaz leke
    sx, sy, rx, ry = spec
    sp = np.zeros((bh, bw), np.float32)
    cv2.ellipse(sp, (int(bw * sx), int(bh * sy)), (int(bw * rx), int(bh * ry)), -12, 0, 360, 1.0, -1)
    sp = cv2.GaussianBlur(sp, (0, 0), max(2.0, min(bw, bh) * 0.05)) * gloss * m
    rgb = rgb + (255 - rgb) * sp[..., None]
    out = np.zeros((H, W, 3), np.float32)
    out[y0:y1, x0:x1] = np.clip(rgb, 0, 255)
    return out, (mask.astype(np.float32) / 255.0)


class Layer:
    """Avatarın çizildiği 2x RGBA tuval (float)."""

    def __init__(self, w, h):
        self.W, self.H = w * SS, h * SS
        self.rgb = np.zeros((self.H, self.W, 3), np.float32)
        self.a = np.zeros((self.H, self.W), np.float32)
        self.union = np.zeros((self.H, self.W), np.uint8)

    def over(self, rgb, a):
        a = a[..., None] if a.ndim == 2 else a
        self.rgb = rgb * a + self.rgb * (1 - a)
        self.a = a[..., 0] + self.a * (1 - a[..., 0])

    def mask(self, draw_fn):
        im = Image.new("L", (self.W, self.H), 0)
        draw_fn(ImageDraw.Draw(im), SS)
        return np.array(im)

    def part(self, mask, color, outline=7, **kw):
        """Konturlu + gölgeli parça ekle (arkadan öne sırayla çağır)."""
        ring = dilate(mask, int(outline * SS))
        self.over(np.broadcast_to(np.array(OUT, np.float32), self.rgb.shape), ring.astype(np.float32) / 255.0)
        rgb, a = shade(mask, color, **kw)
        self.over(rgb, a)
        self.union |= ring

    def pil(self, draw_fn):
        """Düz PIL çizimi (yüz detayları) üstte."""
        im = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 0))
        draw_fn(ImageDraw.Draw(im), SS)
        arr = np.array(im).astype(np.float32)
        self.over(arr[..., :3], arr[..., 3] / 255.0)

    def glow_image(self, im):
        arr = np.array(im).astype(np.float32)
        self.over(arr[..., :3], arr[..., 3] / 255.0)

    def to_image(self, glow=(255, 255, 255), glow_r=14, glow_a=0.85):
        rgba = np.dstack([self.rgb, self.a * 255]).clip(0, 255).astype(np.uint8)
        im = Image.fromarray(rgba, "RGBA")
        if glow:
            g = Image.fromarray(dilate(self.union, int(glow_r * SS * 0.6)), "L").filter(
                ImageFilter.GaussianBlur(glow_r * SS * 0.5))
            g = g.point(lambda v: int(min(255, v * 1.6) * glow_a))
            base = Image.new("RGBA", im.size, glow + (0,))
            base.putalpha(g)
            im = Image.alpha_composite(base, im)
        return im.resize((self.W // SS, self.H // SS), Image.LANCZOS)


# ─── Roblox oyuncusu parçaları ───────────────────────────────────────────────

def rrect(box, r):
    def f(d, s):
        x0, y0, x1, y1 = box
        d.rounded_rectangle([x0 * s, y0 * s, x1 * s, y1 * s], radius=r * s, fill=255)
    return f


def poly(pts):
    def f(d, s):
        d.polygon([(x * s, y * s) for x, y in pts], fill=255)
    return f


def union(*fns):
    def f(d, s):
        for g in fns:
            g(d, s)
    return f


def glowing_eye(L, pts, ow=7, core=(255, 244, 190), mid=(255, 110, 40), edge=(225, 30, 30), glow=(255, 60, 40)):
    """Kızgın parlayan göz: dışarı taşan kırmızı parıltı + sarımsı merkez."""
    s = SS
    P = [(x * s, y * s) for x, y in pts]
    xs = [p[0] for p in P]
    ys = [p[1] for p in P]
    cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    g = Image.new("RGBA", (L.W, L.H), (0, 0, 0, 0))
    ImageDraw.Draw(g).polygon(P, fill=glow + (230,))
    L.glow_image(g.filter(ImageFilter.GaussianBlur(max(w, h) * 0.16)))
    m = Image.new("L", (L.W, L.H), 0)
    ImageDraw.Draw(m).polygon(P, fill=255)
    L.over(np.broadcast_to(np.array(OUT, np.float32), L.rgb.shape),
           dilate(np.array(m), int(ow * s)).astype(np.float32) / 255.0)
    # radyal renk: merkez sıcak sarı -> turuncu -> kırmızı kenar
    Y, X = np.mgrid[0:L.H, 0:L.W].astype(np.float32)
    dd = np.sqrt(((X - cx) / (w * 0.55)) ** 2 + ((Y - cy + h * 0.08) / (h * 0.62)) ** 2)
    t = np.clip(dd, 0, 1)[..., None]
    c0, c1, c2 = (np.array(c, np.float32) for c in (core, mid, edge))
    rgb = np.where(t < 0.5, c0 + (c1 - c0) * (t / 0.5), c1 + (c2 - c1) * ((t - 0.5) / 0.5))
    L.over(rgb, np.array(m).astype(np.float32) / 255.0)


def brow(L, pts, col=OUT):
    L.pil(lambda d, s: d.polygon([(x * s, y * s) for x, y in pts], fill=col + (255,)))


def sleepy_eye(L, cx, cy, w, lw=16):
    """Kapalı göz: aşağı bakan yay + iki kirpik."""
    def f(d, s):
        d.arc([(cx - w / 2) * s, (cy - w * 0.45) * s, (cx + w / 2) * s, (cy + w * 0.35) * s],
              20, 160, fill=OUT + (255,), width=int(lw * s))
        for k in (-1, 1):
            ex, ey = cx + k * w * 0.46, cy + w * 0.02
            d.line([ex * s, ey * s, (ex + k * w * 0.12) * s, (ey + w * 0.12) * s], fill=OUT + (255,), width=int(lw * 0.7 * s))
    L.pil(f)


def hair(L, head, col, bang=0.28, tips=0.40, side=0.52, up=0, teeth=6, seed=1):
    """Roblox saçı: başı saran kubbe, alnı örten sivri kakül, yan perçemler,
    istenirse yukarı dikenler. Üstüne birkaç koyu tel çizgisi."""
    x0, y0, x1, y1 = head
    w, h = x1 - x0, y1 - y0
    rng = np.random.default_rng(seed)
    top = y0 - h * 0.12
    parts = [rrect((x0 - w * 0.04, top, x1 + w * 0.04, y0 + h * bang), min(w, h) * 0.32),
             rrect((x0 - w * 0.05, y0 + h * 0.02, x0 + w * 0.09, y0 + h * side), w * 0.04),
             rrect((x1 - w * 0.09, y0 + h * 0.02, x1 + w * 0.05, y0 + h * side), w * 0.04)]
    fringe = [(x0 - w * 0.04, y0 + h * bang * 0.55)]
    for i in range(teeth):
        a = x0 + w * (i / teeth)
        b = x0 + w * ((i + 0.55 + rng.uniform(-0.12, 0.12)) / teeth)
        fringe += [(a, y0 + h * bang), (b, y0 + h * (tips + rng.uniform(-0.03, 0.03)))]
    fringe += [(x1, y0 + h * bang), (x1 + w * 0.04, y0 + h * bang * 0.55)]
    parts.append(poly(fringe))
    for i in range(up):
        px = x0 + w * (0.12 + 0.72 * i / max(1, up - 1))
        parts.append(poly([(px - w * 0.10, top + h * 0.12), (px + w * 0.06, top - h * 0.17),
                           (px + w * 0.11, top + h * 0.12)]))
    L.part(L.mask(union(*parts)), col, bevel=0.08, gloss=0.5)
    dark = shade_c(col, 0.62) + (255,)

    def strands(d, s):
        for i in range(4):
            cx = x0 + w * (0.22 + 0.17 * i)
            r = w * 0.06
            d.arc([(cx - r) * s, (top + h * 0.08) * s, (cx + r) * s, (top + h * 0.08 + r * 1.6) * s],
                  200, 340, fill=dark, width=int(max(3, w * 0.008) * s))
    L.pil(strands)


def text_mask(bgr, box, hues, rim=12):
    """Renkli başlık/fiyat yazısı + koyu konturu (renk aralığına göre)."""
    x0, y0, x1, y1 = box
    h, s, v = (c[y0:y1, x0:x1] for c in hsv(bgr))
    col = np.zeros(h.shape, bool)
    for lo, hi in hues:
        col |= (h >= lo) & (h <= hi)
    col = (col & (s > 70) & (v > 60)).astype(np.uint8) * 255
    col = cv2.morphologyEx(col, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    dark = (v < 115).astype(np.uint8) * 255
    k = col | (dilate(col, rim) & dark)
    m = np.zeros(bgr.shape[:2], np.uint8)
    m[y0:y1, x0:x1] = k
    return m


# ─── Görseller ──────────────────────────────────────────────────────────────

def mouth_mask(bgr, giant, poly, body_fn, inset=22):
    """Dev gövdenin içindeki ağız: gövde rengi olmayan her şey, delikleri dolu."""
    m = not_body(bgr, poly, body_fn) & erode(giant, inset)
    return fill_holes(largest(m))


def compose(src_rgb, avatar, giant, protect, post=None, halo=26):
    """giant alanını (+ parıltı payı) inpaint et, avatarı koy, korunanları geri bas."""
    bgr = cv2.cvtColor(src_rgb, cv2.COLOR_RGB2BGR)
    base = cv2.inpaint(bgr, dilate(giant, halo), 14, cv2.INPAINT_TELEA)
    base = Image.fromarray(cv2.cvtColor(base, cv2.COLOR_BGR2RGB)).convert("RGBA")
    base.alpha_composite(avatar)
    if post:
        base = post(base)
    keep = Image.fromarray(cv2.GaussianBlur(protect, (0, 0), 1.0), "L")
    base.paste(Image.fromarray(src_rgb), (0, 0), keep)
    return base.convert("RGB")


def red_body(h, s, v):
    return ((h >= 172) | (h <= 8)) & (s > 120) & (v > 110)


def white_body(h, s, v):
    return (s < 45) & (v > 150)


def black_body(h, s, v):
    return v < 75


def overlay(bgr, box, drop_fn, min_area=60):
    """Kutudaki bindirme (yazı, kaide...): drop_fn'e uymayan pikseller, delik dolu."""
    x0, y0, x1, y1 = box
    h, s, v = (c[y0:y1, x0:x1] for c in hsv(bgr))
    k = np.where(drop_fn(h, s, v), 0, 255).astype(np.uint8)
    k = cv2.morphologyEx(k, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(k)
    keep = np.zeros_like(k)
    for i in range(1, n):
        if st[i, cv2.CC_STAT_AREA] >= min_area:
            keep[lab == i] = 255
    m = np.zeros(bgr.shape[:2], np.uint8)
    m[y0:y1, x0:x1] = fill_holes(keep)
    return m


def bubble_mask(bgr, box):
    x0, y0, x1, y1 = box
    h, s, v = (c[y0:y1, x0:x1] for c in hsv(bgr))
    k = ((s < 70) & (v > 185)).astype(np.uint8) * 255
    m = np.zeros(bgr.shape[:2], np.uint8)
    m[y0:y1, x0:x1] = dilate(fill_holes(largest(k)), 2)
    return m


def load(name):
    src = np.array(Image.open(os.path.join(SRC, name)).convert("RGB"))
    return src, cv2.cvtColor(src, cv2.COLOR_RGB2BGR)


def snow(img, area, seed, n=90):
    """Karlı sahnede yeni çizilen alanın üstüne de kar serp."""
    rng = np.random.default_rng(seed)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ys, xs = np.nonzero(area)
    for i in rng.choice(len(xs), n, replace=False):
        r = rng.uniform(3, 7.5)
        x, y = xs[i], ys[i]
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, int(rng.uniform(170, 240))))
    return Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(0.8)))


def angry_face(L, x0, x1, ey, eh=150, lift=0):
    """İki parlayan kızgın göz + çatık kaş. x0..x1 yüz genişliği, ey göz üstü."""
    w = x1 - x0
    ew = w * 0.36
    gl, gr = x0 + w * 0.02, x1 - w * 0.02
    ow = max(3, eh * 0.045)
    glowing_eye(L, [(gl, ey), (gl + ew, ey + eh * 0.40), (gl + ew * 0.96, ey + eh * 0.93),
                    (gl + ew * 0.40, ey + eh), (gl, ey + eh * 0.72)], ow)
    glowing_eye(L, [(gr, ey), (gr - ew, ey + eh * 0.40), (gr - ew * 0.96, ey + eh * 0.93),
                    (gr - ew * 0.40, ey + eh), (gr, ey + eh * 0.72)], ow)
    t = eh * 0.34
    brow(L, [(gl - w * 0.05, ey - eh * 0.55 - lift), (gl + ew * 1.05, ey - eh * 0.02),
             (gl + ew * 1.0, ey - eh * 0.02 + t), (gl - w * 0.06, ey - eh * 0.55 - lift + t)])
    brow(L, [(gr + w * 0.05, ey - eh * 0.55 - lift), (gr - ew * 1.05, ey - eh * 0.02),
             (gr - ew * 1.0, ey - eh * 0.02 + t), (gr + w * 0.06, ey - eh * 0.55 - lift + t)])


def sleep_mouth(L, cx, cy, w):
    L.pil(lambda d, s: d.ellipse([(cx - w / 2) * s, (cy - w * 0.36) * s, (cx + w / 2) * s, (cy + w * 0.36) * s],
                                 fill=(70, 24, 36, 255), outline=OUT + (255,), width=int(8 * s)))


def cap(L, head, col, brim_left=True):
    """Ters kasket: kubbe + bant + yana taşan siperlik."""
    x0, y0, x1, y1 = head
    w = x1 - x0
    dome = union(lambda d, s: d.chord([(x0 - w * 0.02) * s, (y0 - w * 0.08) * s, (x1 + w * 0.02) * s, (y0 + w * 0.42) * s],
                                      180, 360, fill=255),
                 rrect((x0 - w * 0.03, y0 + w * 0.02, x1 + w * 0.03, y0 + w * 0.16), w * 0.05))
    bx = x0 - w * 0.2 if brim_left else x1 + w * 0.2
    brim = rrect((min(bx, x0 + w * 0.1), y0 + w * 0.06, max(bx, x0 + w * 0.1), y0 + w * 0.16) if brim_left else
                 (min(bx, x1 - w * 0.1), y0 + w * 0.06, max(bx, x1 - w * 0.1), y0 + w * 0.16), w * 0.05)
    L.part(L.mask(brim), shade_c(col, 0.8), bevel=0.3, gloss=0.3)
    L.part(L.mask(dome), col, bevel=0.14, gloss=0.55)


def shade_c(c, k):
    return tuple(max(0, min(255, int(x * k))) for x in c)


def thumb_1():
    """Kızgın 'noob': seni crewmate'iyle yakaladı, dili sana uzanıyor."""
    src, bgr = load("1.webp")
    giant = grabcut(bgr, [(0, 285), (165, 285), (190, 110), (330, 30), (560, 15), (770, 55), (910, 160),
                          (985, 300), (1125, 350), (1135, 510), (1040, 575), (1015, 770), (965, 905),
                          (945, 1080), (0, 1080)])
    mouth = mouth_mask(bgr, giant, [(345, 560), (1000, 555), (1000, 910), (600, 925), (420, 870), (340, 700)],
                       red_body)
    tongue = tongue_mask(bgr, [(540, 600), (1330, 590), (1330, 700), (1000, 920), (540, 920)])
    bang = white_sticker(bgr, (165, 40, 420, 335), grow=4)
    protect = mouth | tongue | bang

    L = Layer(src.shape[1], src.shape[0])
    L.part(L.mask(rrect((-60, 905, 1180, 1200), 90)), (22, 104, 196), bevel=0.10, gloss=0.35)
    L.part(L.mask(rrect((40, 25, 1090, 975), 260)), (246, 206, 56), bevel=0.11, gloss=0.6)
    angry_face(L, 470, 1000, 330)
    return compose(src, L.to_image(), giant, protect)


def thumb_2():
    """Uyuyan oyuncu: Amogus Prime'ı sen kaptın, o hâlâ horluyor."""
    src, bgr = load("2.webp")
    giant = grabcut(bgr, [(1015, 350), (1150, 330), (1240, 250), (1420, 215), (1600, 250), (1700, 360),
                          (1730, 440), (1850, 450), (1860, 740), (1760, 760), (1750, 1000), (1720, 1060),
                          (1120, 1060), (1110, 720), (1030, 600)])
    zzz = white_sticker(bgr, (1380, 0, 1665, 320), grow=3)
    bub = bubble_mask(bgr, (935, 455, 1170, 690))
    price = text_mask(bgr, (715, 165, 1135, 280), [(35, 85)])
    protect = zzz | bub | price

    L = Layer(src.shape[1], src.shape[0])
    skin, hood, pants = (255, 214, 172), (62, 58, 80), (44, 54, 100)
    L.part(L.mask(rrect((1150, 870, 1415, 1060), 30)), pants, bevel=0.14, gloss=0.3)
    L.part(L.mask(rrect((1435, 870, 1700, 1060), 30)), pants, bevel=0.14, gloss=0.3)
    L.part(L.mask(rrect((985, 625, 1115, 930), 34)), hood, bevel=0.18, gloss=0.35)
    L.part(L.mask(rrect((1735, 625, 1865, 930), 34)), hood, bevel=0.18, gloss=0.35)
    L.part(L.mask(rrect((1090, 600, 1760, 905), 50)), hood, bevel=0.10, gloss=0.4)
    L.part(L.mask(rrect((1025, 245, 1715, 665), 150)), skin, bevel=0.12, gloss=0.55)
    hair(L, (1025, 245, 1715, 665), (38, 32, 50), bang=0.27, tips=0.40, side=0.5, seed=2)
    sleepy_eye(L, 1195, 450, 118)
    sleepy_eye(L, 1395, 450, 118)
    sleep_mouth(L, 1300, 560, 58)
    return compose(src, L.to_image(glow=(255, 150, 250)), giant, protect)


def thumb_3():
    """Kızgın sarışın oyuncu: Golden Jester'ını çaldın, seni gördü."""
    src, bgr = load("3.webp")
    giant = grabcut(bgr, [(0, 380), (175, 375), (200, 250), (330, 175), (520, 160), (690, 200), (800, 300),
                          (880, 380), (990, 505), (985, 575), (880, 650), (900, 850), (800, 1080), (0, 1080)])
    _, _, v = hsv(bgr)
    ring = ((v < 100).astype(np.uint8) * 255) & poly_mask(src.shape, [(300, 625), (885, 625), (885, 960), (300, 960)])
    n, lab, st, _ = cv2.connectedComponentsWithStats(ring)
    big = np.zeros_like(ring)
    for i in range(1, n):       # ağız çerçevesi + koyu kırmızı yıldız birlikte
        if st[i, cv2.CC_STAT_AREA] > 1500:
            big[lab == i] = 255
    mouth = fill_holes(cv2.morphologyEx(big, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8)))
    # dolu ağız bloğu kalın; ona yapışık ince vizör konturu açmayla düşüyor
    mouth = cv2.morphologyEx(mouth, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (19, 19)))
    bang = white_sticker(bgr, (60, 65, 260, 300), grow=2)
    text = text_mask(bgr, (530, 50, 1370, 285), [(8, 35), (35, 85)], rim=8)
    pod = grabcut(bgr, [(840, 820), (1160, 820), (1165, 920), (1205, 930), (1205, 1040), (795, 1040),
                        (795, 925), (840, 910)], iters=5)
    protect = mouth | bang | text | pod

    L = Layer(src.shape[1], src.shape[0])
    skin, shirt = (255, 208, 166), (40, 150, 90)
    L.part(L.mask(rrect((-80, 930, 1060, 1250), 90)), shirt, bevel=0.10, gloss=0.35)
    L.part(L.mask(rrect((20, 250, 990, 1000), 240)), skin, bevel=0.11, gloss=0.55)
    hair(L, (20, 250, 990, 1000), (250, 198, 64), bang=0.17, tips=0.25, side=0.42, up=4, teeth=7, seed=3)
    angry_face(L, 440, 960, 470)
    return compose(src, L.to_image(glow=(235, 250, 255)), giant, protect,
                   post=lambda im: snow(im, dilate(giant, 20), 3))


def thumb_4():
    """Uyuyan kasketli oyuncu: Triple Impostor'unu kaldırıp götürüyorsun."""
    src, bgr = load("4.webp")
    giant = grabcut(bgr, [(220, 520), (340, 510), (360, 420), (440, 350), (600, 325), (760, 380), (830, 440),
                          (945, 470), (950, 660), (860, 700), (860, 1045), (310, 1045), (320, 820),
                          (220, 810)])
    zzz = white_sticker(bgr, (125, 275, 360, 545), grow=3)
    price = text_mask(bgr, (365, 160, 730, 275), [(35, 85)])
    protect = zzz | price

    L = Layer(src.shape[1], src.shape[0])
    skin, shirt, pants = (176, 116, 78), (56, 170, 96), (48, 50, 72)
    L.part(L.mask(rrect((330, 880, 590, 1045), 30)), pants, bevel=0.14, gloss=0.3)
    L.part(L.mask(rrect((610, 880, 870, 1045), 30)), pants, bevel=0.14, gloss=0.3)
    L.part(L.mask(rrect((200, 715, 325, 935), 34)), shirt, bevel=0.18, gloss=0.35)
    L.part(L.mask(rrect((875, 715, 1000, 935), 34)), shirt, bevel=0.18, gloss=0.35)
    L.part(L.mask(rrect((305, 690, 895, 905), 50)), shirt, bevel=0.10, gloss=0.4)
    L.part(L.mask(rrect((300, 360, 945, 730), 150)), skin, bevel=0.12, gloss=0.5)
    cap(L, (300, 360, 945, 730), (40, 110, 225), brim_left=True)
    sleepy_eye(L, 660, 540, 118)
    sleepy_eye(L, 850, 540, 118)
    sleep_mouth(L, 760, 645, 56)
    return compose(src, L.to_image(), giant, protect)


def icon():
    """Oyun ikonu: kızgın noob, crewmate'ini kucaklayıp kaçan YOU."""
    src, bgr = load("5.png")
    giant = grabcut(bgr, [(135, 180), (175, 105), (260, 55), (370, 40), (460, 90), (512, 140), (512, 400),
                          (470, 440), (330, 440), (300, 400), (150, 240)])
    you = poly_mask(src.shape, [(165, 232), (180, 218), (230, 214), (256, 225), (271, 246), (268, 280), (262, 300),
                                (275, 308), (300, 322), (305, 335), (300, 356), (286, 382), (290, 412), (300, 478),
                                (290, 492), (245, 492), (240, 470), (214, 455), (160, 452), (130, 452), (96, 445),
                                (88, 425), (92, 398), (125, 393), (120, 315), (160, 298), (178, 292), (170, 265)])
    h, s_, v = hsv(bgr)
    area = poly_mask(src.shape, [(262, 238), (400, 238), (400, 365), (262, 365)]) & ~you
    teeth = (s_ < 80) & (v > 165)
    star = ((h >= 165) | (h <= 10)) & (s_ > 90) & (v > 45) & (v < 200)
    core = cv2.morphologyEx(((teeth | star).astype(np.uint8) * 255) & area, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
    core = fill_holes(largest(core))
    mouth = core | (dilate(core, 3) & ((v < 70).astype(np.uint8) * 255))
    bang = white_sticker(bgr, (370, 20, 480, 135), grow=3)
    protect = you | mouth | bang

    L = Layer(src.shape[1], src.shape[0])
    L.part(L.mask(rrect((110, 385, 560, 600), 30)), (22, 104, 196), outline=3.5, bevel=0.10, gloss=0.35)
    L.part(L.mask(rrect((140, 40, 505, 410), 95)), (246, 206, 56), outline=3.5, bevel=0.11, gloss=0.6)
    angry_face(L, 175, 470, 140, eh=62)
    return compose(src, L.to_image(glow_r=7), giant, protect, halo=10)


THUMBS = {"thumb_1": thumb_1, "thumb_2": thumb_2, "thumb_3": thumb_3, "thumb_4": thumb_4, "icon": icon}


def preview(names):
    """Hepsi bir arada: 4 thumbnail 2x2 + yanında ikon."""
    tw, th = 640, 360
    sheet = Image.new("RGB", (tw * 2 + 12 + 300, th * 2 + 4), (24, 22, 32))
    thumbs = [n for n in names if n.startswith("thumb_")]
    for i, n in enumerate(thumbs):
        im = Image.open(os.path.join(DEST, n + ".png")).resize((tw, th), Image.LANCZOS)
        sheet.paste(im, ((i % 2) * (tw + 4), (i // 2) * (th + 4)))
    if "icon" in names:
        ic = Image.open(os.path.join(DEST, "icon.png")).resize((280, 280), Image.LANCZOS)
        sheet.paste(ic, (tw * 2 + 18, (sheet.height - 280) // 2))
    sheet.save(os.path.join(DEST, "_preview.png"))


def main():
    import sys
    cv2.setRNGSeed(0)           # GrabCut her seferinde aynı maskeyi versin
    os.makedirs(DEST, exist_ok=True)
    only = sys.argv[1:]
    for name, make in THUMBS.items():
        if only and name not in only:
            continue
        make().save(os.path.join(DEST, name + ".png"), optimize=True)
        print(name)
    if not only:
        preview(list(THUMBS))
        print("_preview")


if __name__ == "__main__":
    main()
