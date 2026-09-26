"""
Oyun içi mağaza görselleri (ShopPanel), store_icons.py ile AYNI çizim dili.

    python tools/shop_art.py      ->  shop_art/*.png  (+ store_icons/product_potion_*.png)

store_icons.py Roblox'un satın alma penceresi için tam ikon çiziyor: renkli
daire zemin + altta yazı. Mağaza kartında zemin ve yazı kartın kendisi; burada
aynı çizimler ZEMİNSİZ ve YAZISIZ, saydam PNG olarak çıkıyor (kalın kontur ve
gölge duruyor). Kart rengi arkadan görünüyor.

Ek olarak:
  - İksirler (4 tane): hem oyun içi görsel hem Roblox ürün ikonu
    (store_icons/product_potion_*.png — Creator Dashboard'a yüklenecek).
  - rays.png: beyaz ışın demeti, saydam. Oyunda ImageColor3 ile her kartın
    rengine boyanıyor; tek görsel bütün kartlara yetiyor.

Gerekenler: pip install pillow
"""

import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import store_icons as si  # noqa: E402

S, W, OUT, LW = si.S, si.W, si.OUT, si.LW
p = si.p
ROOT = si.ROOT
DEST = os.path.join(ROOT, "shop_art")
ART_SIZE = 256


# ─── İksirler ─────────────────────────────────────────────────────────────


def potion(liquid, glass=(222, 240, 250), mark=None):
    """Mantar tıpalı yuvarlak şişe; `mark` sıvının üstüne çizilen simge."""
    art, d = si.new_art()
    # Tıpa ve boyun
    d.rounded_rectangle(p(222, 58, 290, 92), radius=8 * S, fill=(170, 110, 60), outline=OUT, width=LW)
    d.rounded_rectangle(p(226, 86, 286, 170), radius=6 * S, fill=glass, outline=OUT, width=LW)
    # Gövde
    d.ellipse(p(146, 140, 366, 360), fill=glass, outline=OUT, width=LW)
    d.rectangle(p(232, 136, 280, 172), fill=glass)
    d.chord(p(160, 154, 352, 346), 0, 180, fill=liquid)
    d.chord(p(160, 154, 352, 346), 0, 180, outline=si.shade(liquid, 0.6), width=int(LW * 0.6))
    # Kabarcıklar
    for bx, by, br in [(206, 292, 11), (300, 280, 9), (250, 318, 7), (322, 312, 6)]:
        d.ellipse(p(bx - br, by - br, bx + br, by + br), fill=si.shade(liquid, 1.35))
    si.gloss(d, (174, 178, 208, 238), 170)
    if mark:
        mark(d)
    return art


def mark_text(text, col):
    def draw(d):
        si.big_text(d, (256, 286), text, 74, col)
    return draw


def mark_bolt(d):
    bolt = [(268, 228), (222, 300), (252, 300), (236, 350), (292, 276), (262, 276), (284, 228)]
    d.polygon([(x * S, y * S) for x, y in bolt], fill=(255, 226, 60), outline=OUT, width=int(LW * 0.8))


def mark_lock(d):
    d.arc(p(226, 232, 286, 292), 180, 360, fill=OUT, width=22 * S)
    d.arc(p(229, 235, 283, 289), 180, 360, fill=(210, 220, 232), width=14 * S)
    d.rounded_rectangle(p(214, 262, 298, 332), radius=12 * S, fill=(255, 200, 44), outline=OUT, width=int(LW * 0.8))
    d.ellipse(p(248, 284, 264, 300), fill=OUT)


POTIONS = {
    # anahtar: (sıvı rengi, simge, arka plan açık/koyu, ürün ikonundaki yazı)
    "Income2x": ((110, 235, 90), mark_text("2X", (255, 236, 120)), ((140, 240, 120), (15, 90, 40)), "2X INCOME"),
    "Income3x": ((255, 196, 40), mark_text("3X", (255, 255, 255)), ((255, 214, 110), (140, 80, 10)), "3X INCOME"),
    "FastSteal": ((255, 110, 70), mark_bolt, ((255, 190, 90), (150, 40, 20)), "FAST HANDS"),
    "StrongLock": ((70, 200, 255), mark_lock, ((110, 230, 230), (15, 70, 100)), "STRONG LOCK"),
}


def potion_art(key):
    liquid, mark, _, _ = POTIONS[key]
    art = potion(liquid, mark=mark)
    # Arkada yumuşak renk parlaması: şişe karta "ışık saçsın"
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(p(120, 120, 392, 392), fill=liquid + (140,))
    base = Image.alpha_composite(Image.new("RGBA", (W, W), (0, 0, 0, 0)), glow.filter(ImageFilter.GaussianBlur(34 * S)))
    return si.stamp(base, art)


def potion_store_icon(key):
    liquid, mark, (light, dark), text = POTIONS[key]
    c = si.background(light, dark, 30 + len(key))
    glow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(p(120, 110, 392, 382), fill=liquid + (150,))
    c = Image.alpha_composite(c, glow.filter(ImageFilter.GaussianBlur(30 * S)))
    c = si.stamp(c, potion(liquid, mark=mark))
    return si.label(c, text)


# ─── Zeminsiz ürün çizimleri ──────────────────────────────────────────────

PRODUCTS = {
    "DoubleIncome": si.icon_double_income,
    "ExtraPodiums": si.icon_extra_podiums,
    "TripleHatch": si.icon_triple_hatch,
    "FastSteal": si.icon_fast_steal,
    "StrongLock": si.icon_strong_lock,
    "ExtraSpin": si.icon_extra_spin,
    "SkipConveyor": si.icon_instant_spawn,
    "LuckyRoll": si.icon_mutation,
    "Cash100K": lambda: si.icon_cash(1),
    "Cash1M": lambda: si.icon_cash(2),
    "Cash10M": lambda: si.icon_cash(3),
    "InstantRebirth": si.icon_rebirth,
}


def bare(make):
    """store_icons çizimini zeminsiz ve yazısız çalıştırır."""
    old_bg, old_label = si.background, si.label
    si.background = lambda *a, **k: Image.new("RGBA", (W, W), (0, 0, 0, 0))
    si.label = lambda c, *a, **k: c
    try:
        return make()
    finally:
        si.background, si.label = old_bg, old_label


def fit(img):
    """Saydam kenarları kırpıp kareye ortalar, ART_SIZE'a küçültür."""
    box = img.split()[3].point(lambda v: 255 if v > 8 else 0).getbbox()
    if box:
        img = img.crop(box)
    side = int(max(img.size) * 1.06)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.alpha_composite(img, ((side - img.width) // 2, (side - img.height) // 2))
    return sq.resize((ART_SIZE, ART_SIZE), Image.LANCZOS)


def rays():
    """Beyaz ışın demeti (merkezden), kenara doğru sönen; saydam."""
    size = 512 * S // 2
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2
    n = 20
    for i in range(n):
        a0 = (i / n) * math.tau
        a1 = a0 + math.tau / n / 2
        d.polygon([(c, c), (c + math.cos(a0) * size, c + math.sin(a0) * size), (c + math.cos(a1) * size, c + math.sin(a1) * size)],
                  fill=(255, 255, 255, 255))
    fade = Image.radial_gradient("L").resize((size, size), Image.BICUBIC).point(lambda v: max(0, 255 - int(v * 1.25)))
    alpha = Image.composite(img.split()[3], Image.new("L", (size, size), 0), fade)
    alpha = alpha.point(lambda v: int(v * 0.55))
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    out.putalpha(alpha)
    return out.resize((512, 512), Image.LANCZOS)


def main():
    os.makedirs(DEST, exist_ok=True)
    for key, make in PRODUCTS.items():
        fit(bare(make)).save(os.path.join(DEST, key + ".png"), optimize=True)
        print(key)
    for key in POTIONS:
        fit(potion_art(key)).save(os.path.join(DEST, "Potion_" + key + ".png"), optimize=True)
        icon = potion_store_icon(key).convert("RGB").resize((512, 512), Image.LANCZOS)
        icon.save(os.path.join(si.DEST, "product_potion_" + key.lower() + ".png"), optimize=True)
        print("Potion_" + key)
    rays().save(os.path.join(DEST, "rays.png"), optimize=True)
    print("rays")

    # Önizleme: koyu zeminde hepsi
    files = sorted(f for f in os.listdir(DEST) if f.endswith(".png") and not f.startswith("_"))
    cols = 6
    rows = math.ceil(len(files) / cols)
    sheet = Image.new("RGBA", (cols * 180, rows * 180), (30, 34, 52, 255))
    for i, f in enumerate(files):
        img = Image.open(os.path.join(DEST, f)).convert("RGBA").resize((170, 170), Image.LANCZOS)
        sheet.alpha_composite(img, ((i % cols) * 180 + 5, (i // cols) * 180 + 5))
    sheet.save(os.path.join(DEST, "_preview.png"))


if __name__ == "__main__":
    main()
