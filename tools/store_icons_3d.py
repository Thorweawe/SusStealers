"""
Roblox mağaza ikonları (gamepass + developer product), 3B render sürümü.
Işınlı arka plan (store_icons.background), ortada 3B ikon (ui_art/icons,
tools/ui_icons.py çıktısı), altta kalın yazı. Pass ikonları Roblox'ta daire
kırpılıyor: resim ve yazı ortadaki dairenin içinde.

    python tools/store_icons_3d.py   ->  store_icons/<ad>.png + _preview_3d.png
"""
import math
import os
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import store_icons as SI  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONS = os.path.join(ROOT, "ui_art", "icons")
DEST = os.path.join(ROOT, "store_icons")

# ad: (ikon, yazı, açık renk, koyu renk, yazı rengi)
ITEMS = {
    "pass_season_pass": ("Nav_Pass", "SEASON PASS", (190, 110, 255), (70, 30, 140), (255, 226, 80)),
    "pass_rainbow_rocket": ("Pass_Rainbow", "RAINBOW FLAME", (120, 200, 255), (60, 40, 150), (255, 255, 255)),
    "product_5_spins": ("SpinPack", "5 SPINS", (255, 120, 190), (140, 30, 110), (255, 226, 80)),
    "product_server_luck": ("ServerLuck", "SERVER LUCK", (120, 230, 120), (20, 110, 50), (255, 244, 150)),
    "product_shrink_everyone": ("Troll_Tiny", "SHRINK ALL", (255, 140, 200), (150, 30, 100), (255, 255, 255)),
    "product_moon_gravity": ("Troll_Moon", "MOON GRAVITY", (130, 150, 255), (30, 40, 120), (255, 255, 255)),
    "product_impostor_alarm": ("Troll_Alarm", "IMPOSTOR ALARM", (255, 110, 110), (130, 20, 30), (255, 230, 90)),
}


def make(icon, text, light, dark, fill, seed):
    W = SI.W
    c = SI.background(light, dark, seed)
    art = Image.open(os.path.join(ICONS, icon + ".png")).convert("RGBA")
    size = int(W * 0.64)
    art = art.resize((size, size), Image.LANCZOS)
    c.alpha_composite(art, ((W - size) // 2, int(W * 0.05)))
    c = SI.label(c, text, y=410, maxw=380, size=62, fill=fill)
    return c


def main():
    os.makedirs(DEST, exist_ok=True)
    thumbs = []
    for i, (name, spec) in enumerate(ITEMS.items()):
        img = make(*spec, seed=i + 7).convert("RGB").resize((512, 512), Image.LANCZOS)
        img.save(os.path.join(DEST, name + ".png"), optimize=True)
        thumbs.append(img)
        print(name)
    cols = 4
    rows = math.ceil(len(thumbs) / cols)
    sheet = Image.new("RGB", (cols * 260, rows * 260), (30, 30, 36))
    mask = Image.new("L", (256, 256), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, 255, 255], fill=255)
    for i, img in enumerate(thumbs):
        sheet.paste(img.resize((256, 256), Image.LANCZOS), ((i % cols) * 260 + 2, (i // cols) * 260 + 2), mask)
    sheet.save(os.path.join(DEST, "_preview_3d.png"))


if __name__ == "__main__":
    main()
