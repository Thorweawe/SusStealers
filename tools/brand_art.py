"""
Topluluk (Roblox Community) görselleri: logo (emblem) ve kapak fotoğrafı.

    python tools/brand_art.py   ->  branding/emblem.png (1024x1024)
                                    branding/cover.png  (1440x456)

Çizim dili store_icons.py ile aynı (kalın koyu kontur, parlama, gölge).
Konsept: kapüşonlu, kırmızı vizörlü bir hırsız mürettebat elinde çaldığı
küçük yeşil mürettebatı tutuyor; çevresinde kırmızı neon halka, arkada uzay.
"""

import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import store_icons as si  # noqa: E402

S, W, OUT, LW = si.S, si.W, si.OUT, si.LW
p = si.p
DEST = os.path.join(si.ROOT, "branding")
FONT = si.FONT

RED = (255, 58, 72)       # neon halka ve vizör
RING = RED
HOOD = (70, 60, 112)      # kapüşonlu gövde: kafa ve gövde AYNI renk, tek siluet
HOOD_RIM = (132, 116, 196) # yüz açıklığının kapüşon kenarı
RIM = (190, 150, 255)     # arka kenar ışığı
FACE = (14, 12, 22)       # kapüşonun içi (karanlık)
LOOT = (80, 239, 57)      # çalınan mürettebat: yeşil


def space(size, seed, top=(26, 18, 52), bottom=(4, 6, 16)):
    """Mor-laciverte kararan uzay zemini + yıldızlar."""
    w, h = size
    grad = Image.linear_gradient("L").resize((w, h))
    img = Image.composite(Image.new("RGB", (w, h), bottom), Image.new("RGB", (w, h), top), grad).convert("RGBA")
    d = ImageDraw.Draw(img)
    rng = random.Random(seed)
    for _ in range(int(w * h / 2600)):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        r = rng.choice([1, 1, 1, 2, 2, 3]) * (w / 1024)
        col = rng.choice([(255, 255, 255), (170, 220, 255), (255, 200, 230)])
        d.ellipse([x - r, y - r, x + r, y + r], fill=col + (rng.randint(90, 230),))
    return img


def glow_ring(size, cx, cy, r, width, color):
    """Neon halka: bulanık parlama + keskin çizgi + ince beyaz iç çizgi."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color + (255,), width=int(width * 2.2))
    glow = layer.filter(ImageFilter.GaussianBlur(width * 1.6))
    ring = Image.new("RGBA", size, (0, 0, 0, 0))
    rd = ImageDraw.Draw(ring)
    rd.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color + (255,), width=int(width))
    inner = r - width * 0.15
    rd.ellipse([cx - inner, cy - inner, cx + inner, cy + inner], outline=(255, 235, 235, 200), width=max(2, int(width * 0.18)))
    out = Image.alpha_composite(glow, glow)
    return Image.alpha_composite(out, ring)


def crewmate(d, cx, by, h, col, face=1, pack=0.16, visor=True):
    """store_icons.crewmate'in aynısı; tek fark sırt çantası daha ince (`pack`, boya oranı)."""
    w = h * 0.72
    top = by - h
    dark = si.shade(col, 0.68)
    lw = max(int(LW * h / 200), 3 * S)
    bx = cx - face * (w / 2 - h * 0.04)
    x0, x1 = sorted((bx, bx - face * h * pack))
    d.rounded_rectangle(p(x0 - face * h * 0.0, top + h * 0.3, x1, top + h * 0.68), radius=h * 0.06 * S,
                        fill=dark, outline=OUT, width=lw)
    d.rounded_rectangle(p(cx - w / 2, by - h * 0.32, cx - w * 0.07, by), radius=h * 0.08 * S, fill=dark, outline=OUT, width=lw)
    d.rounded_rectangle(p(cx + w * 0.07, by - h * 0.32, cx + w / 2, by), radius=h * 0.08 * S, fill=dark, outline=OUT, width=lw)
    d.rounded_rectangle(p(cx - w / 2, top, cx + w / 2, by - h * 0.16), radius=w * 0.47 * S, fill=col, outline=OUT, width=lw)
    if visor:
        vx0 = cx - w * 0.08 if face > 0 else cx - w / 2 - h * 0.1
        vx1 = cx + w / 2 + h * 0.1 if face > 0 else cx + w * 0.08
        d.rounded_rectangle(p(vx0, top + h * 0.17, vx1, top + h * 0.45), radius=h * 0.13 * S, fill=(150, 220, 242), outline=OUT, width=lw)
        hx = vx0 + (vx1 - vx0) * (0.52 if face > 0 else 0.18)
        d.rounded_rectangle(p(hx, top + h * 0.22, hx + (vx1 - vx0) * 0.3, top + h * 0.3), radius=h * 0.035 * S, fill=(235, 250, 255))
    si.gloss(d, (cx - w * 0.36, top + h * 0.06, cx - w * 0.12, top + h * 0.14), 90)


def thief_art():
    """
    Kapüşonlu hırsız, elinde çaldığı yeşil mürettebat.

    Kafa (kapüşon) ve gövde TEK siluet ve TEK renk: mürettebatın fasulye
    gövdesi, üst yarısı kapüşon. Eskiden kapüşon gövdeden geniş ve ayrı
    renkteydi, pelerin ayrı konturluydu — parçalar birbirine uymuyordu.
    Kapüşon hissini yüz açıklığının çevresindeki kalın açık renkli kenar ve
    karanlık iç veriyor; kırmızı vizör karanlıkta parlıyor.
    """
    art, d = si.new_art()
    cx, by, h = 290, 424, 300
    w = h * 0.72
    top = by - h
    lw = max(int(LW * h / 200), 3 * S)

    # Gövde + kafa: tek fasulye, vizörsüz
    crewmate(d, cx, by, h, HOOD, -1, visor=False)
    # Yüz açıklığı: kapüşon kenarı (açık halka) + karanlık iç
    ox0, ox1 = cx - w * 0.47, cx + w * 0.16
    oy0, oy1 = top + h * 0.1, top + h * 0.5
    d.ellipse(p(ox0, oy0, ox1, oy1), fill=HOOD_RIM, outline=OUT, width=lw)
    inset = h * 0.055
    d.ellipse(p(ox0 + inset, oy0 + inset, ox1 - inset, oy1 - inset), fill=FACE)
    # Kırmızı vizör, karanlığın içinde
    vx0, vx1 = ox0 + w * 0.08, ox1 - w * 0.1
    vy0, vy1 = top + h * 0.22, top + h * 0.35
    d.rounded_rectangle(p(vx0, vy0, vx1, vy1), radius=h * 0.065 * S, fill=RED, outline=OUT, width=int(lw * 0.8))
    d.rounded_rectangle(p(vx0 + w * 0.06, vy0 + h * 0.025, vx0 + w * 0.26, vy0 + h * 0.055),
                        radius=h * 0.015 * S, fill=(255, 196, 200))
    # Arka kenar ışığı: mor ince yay, karanlıkta siluet belli olsun
    d.arc(p(cx - w / 2 + 6, top + 6, cx + w / 2 - 6, top + h * 0.7), 270, 350, fill=RIM, width=5 * S)

    # Çalınan küçük mürettebat (yeşil), iki eldivenle (gövde renginde) tutuluyor
    small_h = 124
    small_w = small_h * 0.72
    scx, sby = cx - w * 0.5, by - h * 0.14
    crewmate(d, scx, sby, small_h, LOOT, -1)
    for mx, my in ((scx - small_w * 0.62, sby - small_h * 0.42), (scx + small_w * 0.6, sby - small_h * 0.36)):
        d.ellipse(p(mx - 20, my - 17, mx + 20, my + 17), fill=HOOD, outline=OUT, width=lw)
        si.gloss(d, (mx - 12, my - 11, mx - 2, my - 5), 110)

    # Işıltılar: parlak ganimet
    si.sparkle(d, scx - small_w * 0.55, sby - small_h - 18, 22, (255, 244, 150))
    si.sparkle(d, scx - small_w * 0.95, sby - small_h * 0.55, 11)
    si.sparkle(d, cx + w * 0.72, top + h * 0.02, 18, (255, 244, 150))

    art = si.stamp(Image.new("RGBA", (W, W), (0, 0, 0, 0)), art, outline=6)
    # Vizör parlaması: karanlıkta yanan kırmızı
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle(p(vx0 - 10, vy0 - 10, vx1 + 10, vy1 + 10), radius=30 * S, fill=RED + (160,))
    glow = glow.filter(ImageFilter.GaussianBlur(12 * S))
    return Image.alpha_composite(glow, art)


def fit_into(canvas, art, cx, cy, diameter):
    """Çizimin dolu kısmını `diameter` karesine sığdırıp (cx, cy)'ye ortalar."""
    box = art.split()[3].point(lambda v: 255 if v > 12 else 0).getbbox()
    piece = art.crop(box)
    k = diameter / max(piece.size)
    piece = piece.resize((max(1, int(piece.width * k)), max(1, int(piece.height * k))), Image.LANCZOS)
    canvas.alpha_composite(piece, (int(cx - piece.width / 2), int(cy - piece.height / 2)))


def emblem():
    size = (W, W)
    img = space(size, 7)
    # Halkanın içi hafif kırmızı-mor: logo zeminden ayrılsın, halkayla bütünleşsin
    halo = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(halo).ellipse(p(66, 66, 446, 446), fill=(110, 30, 70, 140))
    img = Image.alpha_composite(img, halo.filter(ImageFilter.GaussianBlur(40 * S)))
    img = Image.alpha_composite(img, glow_ring(size, W / 2, W / 2, 196 * S, 14 * S, RING))
    fit_into(img, thief_art(), W / 2, W / 2 + 6 * S, 318 * S)
    return img.convert("RGB").resize((1024, 1024), Image.LANCZOS)


def outlined_text(canvas, xy, text, size, fill, stroke, anchor="lm"):
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    f = ImageFont.truetype(FONT, size)
    # Yumuşak gölge
    d.text((xy[0], xy[1] + size * 0.08), text, font=f, anchor=anchor, fill=(0, 0, 0, 150),
           stroke_width=stroke + 2, stroke_fill=(0, 0, 0, 150))
    layer = layer.filter(ImageFilter.GaussianBlur(size * 0.05))
    d = ImageDraw.Draw(layer)
    d.text(xy, text, font=f, anchor=anchor, fill=fill, stroke_width=stroke, stroke_fill=OUT)
    canvas.alpha_composite(layer)
    return f.getbbox(text, anchor=anchor, stroke_width=stroke)


def cover():
    k = 2  # 2 kat büyük çiz, sonra küçült
    w, h = 1440 * k, 456 * k
    img = space((w, h), 11, top=(40, 14, 58), bottom=(8, 10, 30))
    # Sağda büyük pembe-mor gezegen
    planet = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    pd = ImageDraw.Draw(planet)
    pd.ellipse([w * 0.78, h * 0.35, w * 1.25, h * 1.9], fill=(150, 60, 200, 255))
    pd.ellipse([w * 0.8, h * 0.38, w * 1.25, h * 1.9], fill=(170, 80, 220, 255))
    img = Image.alpha_composite(img, planet)
    ring = glow_ring((w, h), int(w * 0.14), int(h * 0.5), int(h * 0.44), int(h * 0.028), RING)
    img = Image.alpha_composite(img, ring)
    fit_into(img, thief_art(), w * 0.14, h * 0.5 + h * 0.01, h * 0.66)

    # Başlık: kırmızı "STEAL A" rozeti + dev "CREWMATE"
    x0 = int(w * 0.3)
    badge = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    bd = ImageDraw.Draw(badge)
    bw, bh = int(h * 0.62), int(h * 0.17)
    by = int(h * 0.16)
    bd.rounded_rectangle([x0, by, x0 + bw, by + bh], radius=int(bh * 0.28), fill=(214, 38, 52), outline=OUT, width=int(8 * k))
    bd.rounded_rectangle([x0 + 10 * k, by + 8 * k, x0 + bw - 10 * k, by + bh * 0.42], radius=int(bh * 0.2), fill=(240, 90, 100))
    badge = badge.rotate(2.5, center=(x0 + bw / 2, by + bh / 2), resample=Image.BICUBIC)
    img = Image.alpha_composite(img, badge)
    outlined_text(img, (x0 + bw / 2, by + bh / 2), "STEAL A", int(bh * 0.62), (255, 255, 255), int(7 * k), anchor="mm")
    outlined_text(img, (x0 - 6 * k, int(h * 0.52)), "CREWMATE", int(h * 0.22), (255, 255, 255), int(12 * k))
    outlined_text(img, (x0, int(h * 0.74)), "Steal crewmates  •  Build your crew  •  Trust no one",
                  int(h * 0.058), (255, 214, 90), int(4 * k))

    # Sağ altta küçük mürettebat sırası (bant) ve dolar işaretleri
    crew = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    cd = ImageDraw.Draw(crew)
    cd.rounded_rectangle(p(40, 330, 480, 356), radius=13 * S, fill=(70, 78, 96), outline=OUT, width=LW)
    for x in range(60, 470, 34):
        cd.line(p(x, 336, x + 14, 350), fill=(255, 205, 60), width=5 * S)
    for i, (x, col) in enumerate([(100, (60, 130, 240)), (210, (255, 200, 40)), (320, (240, 125, 13)), (430, (230, 80, 190))]):
        si.crewmate(cd, x, 330, 120, col, 1 if i % 2 == 0 else -1)
    crew = si.stamp(Image.new("RGBA", (W, W), (0, 0, 0, 0)), crew, outline=5)
    crew = crew.crop((0, int(W * 0.35), W, int(W * 0.72)))
    cw = int(w * 0.235)
    crew = crew.resize((cw, int(cw * crew.height / crew.width)), Image.LANCZOS)
    img.alpha_composite(crew, (int(w * 0.75), int(h * 0.4)))
    for sx, sy, sr in [(0.93, 0.18, 30), (0.63, 0.12, 20), (0.97, 0.52, 18)]:
        s = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        si.sparkle(ImageDraw.Draw(s), w * sx / S, h * sy / S, sr * k / S, (255, 244, 150))
        img = Image.alpha_composite(img, s)
    return img.convert("RGB").resize((1440, 456), Image.LANCZOS)


def main():
    os.makedirs(DEST, exist_ok=True)
    emblem().save(os.path.join(DEST, "emblem.png"), optimize=True)
    cover().save(os.path.join(DEST, "cover.png"), optimize=True)
    print("ok")


if __name__ == "__main__":
    main()
