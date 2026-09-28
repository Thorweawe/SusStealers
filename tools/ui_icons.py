"""
Mağaza ikonlarının son hâli: Studio'daki 3B render (saydam) + koyu dış çizgi +
isteğe bağlı kalın yazı rozeti ("2X", "+2"). 512x512, ui_art/icons/.

    python tools/ui_icons.py <render klasörü>
"""
import os
import sys

from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import thumbnails as T  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(ROOT, "ui_art", "icons")
OUT = (22, 20, 34)

BADGE = {
    "DoubleIncome": ("2X", T.money_fill),
    "ExtraPodiums": ("+2", T.gold_fill),
    "ExtraSpin": ("+1", T.gold_fill),
    "Potion_Income2x": ("2X", T.money_fill),
    "Potion_Income3x": ("3X", T.gold_fill),
}


def make(src, name):
    im = Image.open(src).convert("RGBA")
    a = im.getchannel("A")
    bb = a.point(lambda v: 255 if v > 24 else 0).getbbox()
    im = im.crop(bb)
    side = int(max(im.size) * 1.14)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.alpha_composite(im, ((side - im.width) // 2, (side - im.height) // 2))
    big = sq.resize((1024, 1024), Image.LANCZOS)
    # Koyu dış çizgi (sert) + altında yumuşak gölge
    ma = big.getchannel("A").point(lambda v: 255 if v > 60 else 0)
    ring = ma.filter(ImageFilter.MaxFilter(15)).filter(ImageFilter.GaussianBlur(1.2))
    out = Image.new("RGBA", big.size, (0, 0, 0, 0))
    shadow = Image.new("RGBA", big.size, (0, 0, 0, 0))
    shadow.putalpha(ring.point(lambda v: v * 90 // 255))
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(10)), (0, 14))
    edge = Image.new("RGBA", big.size, OUT + (0,))
    edge.putalpha(ring)
    out.alpha_composite(edge)
    out.alpha_composite(big)
    if name in BADGE:
        text, fill = BADGE[name]
        badge = T.text_art(text, 300, fill=fill(), stroke=OUT, sw=0.15, extrude=0.1)
        badge = badge.rotate(-8, expand=True)
        badge.thumbnail((470, 330))
        out.alpha_composite(badge, (1024 - badge.width - 10, 1024 - badge.height - 20))
    out.resize((512, 512), Image.LANCZOS).save(os.path.join(DEST, name + ".png"), optimize=True)
    print(name)


if __name__ == "__main__":
    os.makedirs(DEST, exist_ok=True)
    folder = sys.argv[1]
    for f in sorted(os.listdir(folder)):
        if f.startswith("icon_") and f.endswith(".png") and "_subj" not in f:
            make(os.path.join(folder, f), f[5:-4])
