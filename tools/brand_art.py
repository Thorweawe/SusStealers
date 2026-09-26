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

HOOD = (58, 52, 92)
HOOD_LIGHT = (96, 86, 146)
BODY = (76, 80, 112)
RIM = (190, 140, 255)
RED = (255, 58, 72)
LIME = (80, 239, 57)


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


def thief_art():
    """Hırsız + elindeki mürettebat, 512'lik koordinatlarda, saydam, konturlu."""
    art, d = si.new_art()
    # Bacaklar ve sırt çantası (gövdenin arkasında)
    d.rounded_rectangle(p(212, 340, 262, 418), radius=20 * S, fill=si.shade(BODY, 0.72), outline=OUT, width=LW)
    d.rounded_rectangle(p(282, 340, 332, 418), radius=20 * S, fill=si.shade(BODY, 0.72), outline=OUT, width=LW)
    d.rounded_rectangle(p(318, 196, 376, 326), radius=24 * S, fill=si.shade(HOOD, 0.8), outline=OUT, width=LW)
    # Gövde
    d.rounded_rectangle(p(196, 150, 342, 386), radius=66 * S, fill=BODY, outline=OUT, width=LW)
    # Pelerin: omuzlardan inen kapüşon kumaşı
    d.polygon(p(186, 214, 352, 214, 360, 318, 178, 318), fill=HOOD)
    d.line(p(186, 214, 178, 318), fill=OUT, width=LW)
    d.line(p(352, 214, 360, 318), fill=OUT, width=LW)
    d.line(p(178, 318, 360, 318), fill=OUT, width=int(LW * 0.9))
    # Kapüşon: gövdeden geniş kubbe, yüz açıklığı karanlık
    d.ellipse(p(176, 86, 356, 268), fill=HOOD, outline=OUT, width=LW)
    d.chord(p(176, 86, 356, 268), 200, 250, fill=HOOD_LIGHT)
    # Kenar ışığı: mor ince çizgi, karanlıkta siluet belli olsun
    d.arc(p(184, 94, 348, 260), 190, 330, fill=RIM, width=5 * S)
    d.ellipse(p(204, 132, 322, 246), fill=(12, 12, 20), outline=OUT, width=int(LW * 0.8))
    # Kırmızı vizör (parlaması aşağıda ayrı katmanda)
    d.rounded_rectangle(p(214, 164, 306, 214), radius=24 * S, fill=RED, outline=OUT, width=int(LW * 0.8))
    d.rounded_rectangle(p(226, 172, 262, 184), radius=6 * S, fill=(255, 190, 196))
    si.gloss(d, (200, 100, 240, 124), 70)
    # Kol: omuzdan öndeki ele
    d.line(p(214, 238, 184, 300), fill=OUT, width=40 * S)
    d.line(p(214, 238, 184, 300), fill=HOOD, width=28 * S)
    # Çalınan küçük mürettebat (yeşil), elin üstünde, hırsıza bakıyor
    si.crewmate(d, 156, 300, 104, LIME, 1)
    # El: mürettebatı alttan kavrayan avuç, parmaklar gövdesini yandan sarıyor
    d.ellipse(p(108, 286, 214, 326), fill=HOOD, outline=OUT, width=LW)
    for fy in (238, 258, 278):
        d.ellipse(p(182, fy - 10, 208, fy + 10), fill=HOOD_LIGHT, outline=OUT, width=int(LW * 0.7))
    # Işıltılar: parlak ganimet
    si.sparkle(d, 96, 196, 20, (255, 244, 150))
    si.sparkle(d, 122, 150, 11)
    si.sparkle(d, 396, 128, 16, (255, 244, 150))
    art = si.stamp(Image.new("RGBA", (W, W), (0, 0, 0, 0)), art, outline=6)
    # Vizör parlaması: gözler karanlıkta yanıyor
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle(p(206, 156, 314, 222), radius=30 * S, fill=RED + (170,))
    glow = glow.filter(ImageFilter.GaussianBlur(14 * S))
    return Image.alpha_composite(glow, art)


def emblem():
    size = (W, W)
    img = space(size, 7)
    # Halkanın içi biraz daha aydınlık: logo zeminden ayrılsın
    halo = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(halo).ellipse(p(66, 66, 446, 446), fill=(120, 30, 60, 120))
    img = Image.alpha_composite(img, halo.filter(ImageFilter.GaussianBlur(40 * S)))
    img = Image.alpha_composite(img, glow_ring(size, W / 2, W / 2, 196 * S, 14 * S, RED))
    art = thief_art()
    # Halkanın içine sığsın: küçült ve ortala (çizimin merkezi ~(246, 252))
    k = 0.8
    small = art.resize((int(W * k), int(W * k)), Image.LANCZOS)
    cx, cy = 246 * S * k, 252 * S * k
    img.alpha_composite(small, (int(W / 2 - cx), int(W / 2 + 8 * S - cy)))
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
    ring = glow_ring((w, h), int(w * 0.14), int(h * 0.5), int(h * 0.44), int(h * 0.028), RED)
    img = Image.alpha_composite(img, ring)
    art = thief_art().resize((int(h * 0.9), int(h * 0.9)), Image.LANCZOS)
    img.alpha_composite(art, (int(w * 0.14 - art.width / 2), int(h * 0.5 - art.height / 2 - h * 0.02)))

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
