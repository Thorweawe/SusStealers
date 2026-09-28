"""
Arayüz dokuları (mağaza ve sonraki pencereler): saydam PNG, ImageColor3 ile boyanıyor.

    python tools/ui_art.py  ->  ui_art/*.png

  halftone.png       256x256, döşenebilir beyaz nokta ızgarası (çapraz dizili)
  halftone_fade.png  512x512, üstte büyük altta küçülen noktalar (kart üst deseni)
  sparkle.png        128x128, dört köşeli parıltı (düşen parçacık)
  glow.png           256x256, yumuşak beyaz daire (ikon arkası hale)
  stripes.png        256x256, döşenebilir çapraz şeritler (başlık şeridi)
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(ROOT, "ui_art")
S = 4


def halftone():
    n = 256 * S
    im = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(im)
    step = 32 * S
    r = 7 * S
    for row in range(-1, n // step + 2):
        for col in range(-1, n // step + 2):
            x = col * step + (step // 2 if row % 2 else 0)
            y = row * step
            d.ellipse((x - r, y - r, x + r, y + r), fill=255)
    return im


def halftone_fade():
    n = 512 * S
    im = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(im)
    step = 30 * S
    for row in range(0, n // step + 2):
        t = row * step / n
        r = max(0.0, 1 - t) ** 1.3 * 11 * S
        if r < 1.2 * S:
            continue
        for col in range(-1, n // step + 2):
            x = col * step + (step // 2 if row % 2 else 0)
            y = row * step
            d.ellipse((x - r, y - r, x + r, y + r), fill=255)
    return im


def sparkle():
    n = 128 * S
    im = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(im)
    c = n / 2
    pts = []
    for i in range(8):
        a = i * math.pi / 4 - math.pi / 2
        rr = c * 0.95 if i % 2 == 0 else c * 0.2
        pts.append((c + math.cos(a) * rr, c + math.sin(a) * rr))
    d.polygon(pts, fill=255)
    glow = im.filter(ImageFilter.GaussianBlur(10 * S)).point(lambda v: int(v * 0.8))
    from PIL import ImageChops
    return ImageChops.lighter(im, glow)


def glow():
    n = 256 * S
    im = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(im)
    d.ellipse((n * 0.2, n * 0.2, n * 0.8, n * 0.8), fill=255)
    return im.filter(ImageFilter.GaussianBlur(n * 0.12))


def stripes():
    n = 256 * S
    im = Image.new("L", (n * 3, n * 3), 0)
    d = ImageDraw.Draw(im)
    w = 40 * S
    for k in range(-12, 24):
        x = k * n / 4
        d.polygon([(x, 0), (x + w, 0), (x + w - n * 3, n * 3), (x - n * 3, n * 3)], fill=255)
    return im.crop((n, n, 2 * n, 2 * n))


def save(mask, name, size):
    white = Image.new("RGBA", mask.size, (255, 255, 255, 0))
    white.putalpha(mask)
    white.resize((size, size), Image.LANCZOS).save(os.path.join(DEST, name + ".png"), optimize=True)
    print(name)


if __name__ == "__main__":
    os.makedirs(DEST, exist_ok=True)
    save(halftone(), "halftone", 256)
    save(halftone_fade(), "halftone_fade", 512)
    save(sparkle(), "sparkle", 128)
    save(glow(), "glow", 256)
    save(stripes(), "stripes", 256)
