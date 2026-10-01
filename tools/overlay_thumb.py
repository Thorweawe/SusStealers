"""
Dışarıda (yapay zeka görsel aracı / sanatçı) yapılmış YAZISIZ görselin üstüne
bizim kapak yazılarını ve reklam düzenini ekler.

    python tools/overlay_thumb.py <görsel.png> <kalıp> [ad] [left|right|band]   (son: 16:9 reklamda logo tarafı)
        kalıp: rift | rift_ring | sneak | split | starfall | bosses | kraken | leviathan | worth | none
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


def ring_arrow(c, center, r, tail, tip):
    """Kırmızı daire + ok (merak tuzağı): beyaz kenarlı, hafif gölgeli."""
    from PIL import ImageDraw, ImageFilter
    import math
    layer = Image.new("RGBA", c.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    box = [cx - r, cy - r, cx + r, cy + r]
    ang = math.atan2(tip[1] - tail[1], tip[0] - tail[0])

    def arrow_head(size, push):
        t = (tip[0] + push * math.cos(ang), tip[1] + push * math.sin(ang))
        return [t] + [(t[0] - size * math.cos(ang + k), t[1] - size * math.sin(ang + k)) for k in (-0.6, 0.6)]

    for col, w, grow in (((255, 255, 255, 255), 96, 40), ((225, 20, 35, 255), 64, 0)):
        d.ellipse(box, outline=col, width=w)
        d.line([tail, (tip[0] - 150 * math.cos(ang), tip[1] - 150 * math.sin(ang))], fill=col, width=w)
        d.polygon(arrow_head(260 + grow * 2, grow), fill=col)
    shadow = Image.new("RGBA", c.size, (0, 0, 0, 0))
    shadow.putalpha(layer.getchannel("A").point(lambda v: v * 0.55).filter(ImageFilter.GaussianBlur(18)))
    c.alpha_composite(shadow, (10, 16))
    c.alpha_composite(layer)


def apply(c, preset):
    if preset == "rift_ring":
        apply(c, "rift")
        ring_arrow(c, (1160, 1400), 500, (260, 2080), (640, 1790))
        return c
    if preset == "rift":
        V3.stack_title(c, 120, 60, [
            ("THE CREWMATE", 200, {"fill": rainbow_fill()}),
            ("1 in 50", 260, {"fill": (255, 255, 255), "stroke": (200, 20, 50)}),
            ("$40.6M/s", 220, {"fill": money_fill(), "stroke": (10, 70, 20)}),
        ])
    elif preset == "sneak":
        # Uyuyan Rift Stalker'ın dibinden SECRET kaçırma (SECRET %2 = 1 in 50)
        V3.stack_title(c, 120, 60, [
            ("SHHH...", 230, {"fill": (255, 255, 255), "stroke": (20, 60, 120)}),
            ("1 in 50", 260, {"fill": (255, 255, 255), "stroke": (200, 20, 50)}),
            ("$40.6M/s", 200, {"fill": money_fill(), "stroke": (10, 70, 20)}),
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
    elif preset == "leviathan":
        # Void Leviathan: SECRET %12 (Config.SpaceMonsters) = ~1 in 8
        V3.stack_title(c, 90, 20, [
            ("SECRET", 175, {"fill": rainbow_fill()}),
            ("1 in 8", 205, {"fill": (255, 255, 255), "stroke": (200, 20, 50)}),
            ("$40.6M/s", 145, {"fill": money_fill(), "stroke": (10, 70, 20)}),
        ])
    elif preset == "leviathan2":
        # Düzen bloklu görsel: sol üst boş, büyük başlık
        V3.stack_title(c, 120, 60, [
            ("SECRET", 240, {"fill": rainbow_fill()}),
            ("1 in 8", 280, {"fill": (255, 255, 255), "stroke": (200, 20, 50)}),
            ("$40.6M/s", 220, {"fill": money_fill(), "stroke": (10, 70, 20)}),
        ])
    elif preset == "kraken2":
        put_text(c, "SHHH...", (720, 230), 260, angle=-5, fill=(255, 255, 255), stroke=(20, 60, 120))
        put_text(c, "GOLDEN!", (720, 500), 250, angle=-5, fill=gold_fill(), stroke=(110, 60, 0))
    elif preset == "kraken":
        put_text(c, "SHHH...", (600, 180), 205, angle=-5, fill=(255, 255, 255), stroke=(20, 60, 120))
        put_text(c, "GOLDEN!", (560, 390), 185, angle=-5, fill=gold_fill(), stroke=(110, 60, 0))
    elif preset == "worth":
        put_text(c, "WORTH IT?", (2750, 230), 290, angle=-4, fill=(255, 255, 255), stroke=(180, 20, 60))
        put_text(c, "$40.6M/s", (2750, 480), 200, angle=-4, fill=money_fill(), stroke=(10, 70, 20))
    vignette(c, 30)
    return c


def make_wide_at(A, src, side):
    """ad_art.make_wide gibi; side="right" ise logo + PLAY NOW sağ altta (karakter soldaysa)."""
    if side == "band":
        # Alt bandı boş görsel (bosses): reklamda başlık yerine logo solda, PLAY NOW sağda
        S = A.S
        base = Image.open(src).convert("RGBA").resize((1920 * S, 1080 * S), Image.LANCZOS)
        A.logo(base, 560 * S, 835 * S, 0.85)
        A.play_button(base, 1420 * S, 965 * S, 1.0)
        return base.resize((1920, 1080), Image.LANCZOS).convert("RGB")
    if side != "right":
        return A.make_wide(src)
    S = A.S
    base = Image.open(src).convert("RGBA").resize((1920 * S, 1080 * S), Image.LANCZOS)
    grad = Image.new("L", (1, 256))
    for y in range(256):
        grad.putpixel((0, y), int(max(0, (y - 120) / 136) * 170))
    shade = Image.new("RGBA", base.size, (10, 10, 20, 255))
    shade.putalpha(grad.resize(base.size))
    base.alpha_composite(shade)
    A.logo(base, 1480 * S, 660 * S, 0.9)
    A.play_button(base, 1480 * S, 975 * S, 0.95)
    return base.resize((1920, 1080), Image.LANCZOS).convert("RGB")


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
    wide_side = sys.argv[4] if len(sys.argv) > 4 else "left"
    wide_src = p
    if wide_side == "band":
        # reklam sürümü başlıksız temiz kapaktan
        wide_src = os.path.join(OUT_T, f"_clean_{name}.png")
        apply(load_cover(src), "none").convert("RGB").resize((1920, 1080), Image.LANCZOS).save(wide_src)
    make_wide_at(A, wide_src, wide_side).save(os.path.join(OUT_A, f"ad_16x9_{name}.png"), optimize=True)
    A.make_square(p, 0.5).save(os.path.join(OUT_A, f"ad_1x1_{name}.png"), optimize=True)
    print("ok", p)


if __name__ == "__main__":
    main()
