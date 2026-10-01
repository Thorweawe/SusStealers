"""
Dışarıda (yapay zeka görsel aracı / sanatçı) yapılmış YAZISIZ görselin üstüne
bizim kapak yazılarını ve reklam düzenini ekler.

    python tools/overlay_thumb.py <görsel.png> <kalıp> [ad]
        kalıp: rift | split | starfall | bosses | worth | none
    ->  thumbnails/final/thumb_<ad>.png (1920x1080) + ads/final/ad_16x9_/ad_1x1_<ad>.png

Yazılar oyundaki gerçek sayılarla (Config): Rift Stalker'da SECRET %2 = "1 in 50",
The Crewmate $40.6M/s. Görsel 16:9 değilse ortadan kırpılıp dolduruluyor.
"""

import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import thumbnails as T  # noqa: E402
import thumbnails_v2 as V  # noqa: E402
import thumbnails_v3 as V3  # noqa: E402
from thumbnails import W, H, money_fill, put_text, rainbow_fill, gold_fill, vignette  # noqa: E402

OUT_T = os.path.join(T.ROOT, "thumbnails", "final")
OUT_A = os.path.join(T.ROOT, "ads", "final")


def load_cover(path):
    im = Image.open(path).convert("RGBA")
    k = max(W / im.width, H / im.height)
    im = im.resize((int(im.width * k + 1), int(im.height * k + 1)), Image.LANCZOS)
    x0, y0 = (im.width - W) // 2, (im.height - H) // 2
    return im.crop((x0, y0, x0 + W, y0 + H))


def apply(c, preset):
    if preset == "rift":
        V3.stack_title(c, 120, 60, [
            ("THE CREWMATE", 200, {"fill": rainbow_fill()}),
            ("1 in 50", 260, {"fill": (255, 255, 255), "stroke": (200, 20, 50)}),
            ("$40.6M/s", 220, {"fill": money_fill(), "stroke": (10, 70, 20)}),
        ])
    elif preset == "split":
        put_text(c, "RIFT STALKER", (900, 250), 170, angle=-4, fill=(255, 90, 110), stroke=(60, 0, 20))
        put_text(c, "1 in 50", (900, 470), 200, angle=-4, fill=(255, 255, 255), stroke=(60, 20, 90))
        put_text(c, "$40.6M/s", (3050, 240), 240, angle=-4, fill=money_fill(), stroke=(10, 70, 20))
    elif preset == "starfall":
        V.ribbon(c, "NEW EVENT!", (900, 300), 150, angle=-6)
        put_text(c, "STARFALL", (1000, 620), 300, angle=-6, fill=gold_fill(), stroke=(110, 60, 0))
        put_text(c, "LIMITED!", (1000, 900), 150, angle=-6, fill=(255, 255, 255), stroke=(200, 30, 60))
    elif preset == "bosses":
        put_text(c, "CAN YOU ROB THEM ALL?", (W / 2, H - 260), 230, angle=-2, fill=(255, 255, 255), stroke=(170, 10, 40))
    elif preset == "worth":
        put_text(c, "WORTH IT?", (2750, 230), 290, angle=-4, fill=(255, 255, 255), stroke=(180, 20, 60))
        put_text(c, "$40.6M/s", (2750, 480), 200, angle=-4, fill=money_fill(), stroke=(10, 70, 20))
    vignette(c, 30)
    return c


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return
    src, preset = sys.argv[1], sys.argv[2]
    name = sys.argv[3] if len(sys.argv) > 3 else os.path.splitext(os.path.basename(src))[0]
    os.makedirs(OUT_T, exist_ok=True)
    os.makedirs(OUT_A, exist_ok=True)
    img = apply(load_cover(src), preset).convert("RGB").resize((1920, 1080), Image.LANCZOS)
    p = os.path.join(OUT_T, f"thumb_{name}.png")
    img.save(p)
    import ad_art as A
    A.make_wide(p).save(os.path.join(OUT_A, f"ad_16x9_{name}.png"), optimize=True)
    A.make_square(p, 0.5).save(os.path.join(OUT_A, f"ad_1x1_{name}.png"), optimize=True)
    print("ok", p)


if __name__ == "__main__":
    main()
