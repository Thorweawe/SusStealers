"""
Şans çarkının yüzü (dönen görsel) ve işaretçisi. Dilim sırası ve renkleri
Config.SpinWheelSlices / SpinSliceLook ile aynı olmalı: dilim i, tepeden saat
yönünde (i-1)*30 .. i*30 derece.

    python tools/ui_wheel.py  ->  ui_art/wheel_face.png, ui_art/wheel_pointer.png
"""
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import thumbnails as T  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "ui_art")
OUT = (22, 20, 34)

SLICES = ["SmallCash", "Spawn", "MedCash", "Mutation", "SmallCash", "HugeCash",
          "MedCash", "Spawn", "SmallCash", "Mutation", "MedCash", "FreeUnit"]
LOOK = {
    "SmallCash": ((88, 200, 74), "CASH", "Cash100K"),
    "MedCash": ((40, 150, 230), "BIG CASH", "Cash1M"),
    "HugeCash": ((255, 190, 30), "HUGE CASH", "Cash10M"),
    "Spawn": ((245, 120, 30), "CREWMATE", "Crewmate"),
    "Mutation": ((160, 80, 235), "MUTATED", "LuckyRoll"),
    "FreeUnit": ((230, 45, 70), "JACKPOT", "Jackpot"),
}


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def face():
    N = 2048
    c = N / 2
    R = N / 2 - 4
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    n = len(SLICES)
    w = 360 / n
    radial = T.radial_L((N, N), c, c, R)  # 0 merkez, 255 kenar
    for i, sid in enumerate(SLICES):
        col, _, _ = LOOK[sid]
        start = -90 + i * w
        m = Image.new("L", (N, N), 0)
        ImageDraw.Draw(m).pieslice((c - R, c - R, c + R, c + R), start, start + w, fill=255)
        light = T.ramp(radial, [(0, mix(col, (255, 255, 255), 0.35)), (0.55, col), (1, mix(col, (0, 0, 0), 0.3))]).convert("RGBA")
        # Dilimde ikinci ton: dış kuşak koyu
        light.putalpha(m)
        img.alpha_composite(light)
    # Noktalı doku (hafif)
    dots = Image.open(os.path.join(ART, "halftone.png")).convert("RGBA").resize((160, 160))
    tile = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    for y in range(0, N, 160):
        for x in range(0, N, 160):
            tile.alpha_composite(dots, (x, y))
    disc = Image.new("L", (N, N), 0)
    ImageDraw.Draw(disc).ellipse((c - R, c - R, c + R, c + R), fill=255)
    tile.putalpha(ImageChops.multiply(tile.getchannel("A").point(lambda v: v * 40 // 255), disc))
    img.alpha_composite(tile)
    # Dilim ayırıcıları: koyu kenarlı altın çizgiler
    lines = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(lines)
    for i in range(n):
        a = math.radians(-90 + i * w)
        d.line([(c, c), (c + math.cos(a) * R, c + math.sin(a) * R)], fill=255, width=18)
    img.alpha_composite(Image.new("RGBA", (N, N), OUT + (255,)), (0, 0), ) if False else None
    dark = Image.new("RGBA", (N, N), OUT + (0,))
    dark.putalpha(lines.filter(ImageFilter.MaxFilter(9)))
    img.alpha_composite(dark)
    gold = Image.new("RGBA", (N, N), (255, 226, 120, 0))
    gold.putalpha(lines)
    img.alpha_composite(gold)
    # İkonlar ve yazılar
    for i, sid in enumerate(SLICES):
        col, text, icon = LOOK[sid]
        mid = -90 + (i + 0.5) * w
        a = math.radians(mid)
        ic = Image.open(os.path.join(ART, "icons", icon + ".png")).convert("RGBA").resize((350, 350), Image.LANCZOS)
        ic = ic.rotate(-(mid + 90), Image.BICUBIC, expand=True)
        r = R * 0.58
        img.alpha_composite(ic, (int(c + math.cos(a) * r - ic.width / 2), int(c + math.sin(a) * r - ic.height / 2)))
        label = T.text_art(text, 120, fill=(255, 255, 255), stroke=OUT, sw=0.18, extrude=0.06)
        label.thumbnail((int(R * 0.36), 130))
        label = label.rotate(-(mid + 90), Image.BICUBIC, expand=True)
        r = R * 0.87
        img.alpha_composite(label, (int(c + math.cos(a) * r - label.width / 2), int(c + math.sin(a) * r - label.height / 2)))
    # Dış koyu kenar
    edge = Image.new("L", (N, N), 0)
    ImageDraw.Draw(edge).ellipse((c - R, c - R, c + R, c + R), outline=255, width=14)
    ring = Image.new("RGBA", (N, N), OUT + (0,))
    ring.putalpha(edge)
    img.alpha_composite(ring)
    return img.resize((1024, 1024), Image.LANCZOS)


def pointer():
    N = 512
    m = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(m)
    # Aşağı bakan damla: üstte daire, altta sivri uç
    d.ellipse((96, 30, 416, 350), fill=255)
    d.polygon([(120, 250), (392, 250), (256, 500)], fill=255)
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    outline = Image.new("RGBA", (N, N), OUT + (0,))
    outline.putalpha(m.filter(ImageFilter.MaxFilter(25)))
    img.alpha_composite(outline)
    white = Image.new("RGBA", (N, N), (255, 255, 255, 0))
    white.putalpha(m.filter(ImageFilter.MaxFilter(11)))
    img.alpha_composite(white)
    body = T.shaded(m, (235, 50, 60), (0.35, 0.2), 0.45, 0.45)
    img.alpha_composite(body)
    hl = Image.new("L", (N, N), 0)
    ImageDraw.Draw(hl).ellipse((160, 80, 280, 170), fill=170)
    hi = Image.new("RGBA", (N, N), (255, 255, 255, 0))
    hi.putalpha(ImageChops.multiply(hl.filter(ImageFilter.GaussianBlur(18)), m))
    img.alpha_composite(hi)
    return img.resize((256, 256), Image.LANCZOS)


if __name__ == "__main__":
    face().save(os.path.join(ART, "wheel_face.png"), optimize=True)
    pointer().save(os.path.join(ART, "wheel_pointer.png"), optimize=True)
    print("ok")
