"""
ChatGPT'den gelen VFX sayfasını (siyah zemin, beyaz sprite) saydam PNG'lere
böler: parlaklık = alfa, renk beyaz (oyunda ParticleEmitter.Color boyar).
Izgara ad sayısından: 4 ad = 2x2, 9 ad = 3x3.

    python tools/vfx_slice.py vfx_art/_sheet2_raw.png flame snowflake spark crystal
    python tools/vfx_slice.py vfx_art/_sheetA_raw.png leaf note paw wrench feather badge atom alert cloud
"""
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter


def main():
    src, names = sys.argv[1], sys.argv[2:]
    n = 3 if len(names) > 4 else 2
    im = Image.open(src).convert("L")
    w, h = im.size
    for k, name in enumerate(names[: n * n]):
        r, c = divmod(k, n)
        cell = im.crop((c * w // n, r * h // n, (c + 1) * w // n, (r + 1) * h // n))
        cw, ch = cell.size
        m = int(cw * 0.035)
        mask = Image.new("L", cell.size, 0)
        ImageDraw.Draw(mask).rectangle([m, m, cw - m, ch - m], fill=255)
        mask = mask.filter(ImageFilter.GaussianBlur(m / 2))
        a = ImageChops.multiply(cell, mask).point(lambda v: 0 if v < 6 else v)
        out = Image.new("RGBA", cell.size, (255, 255, 255, 0))
        out.putalpha(a)
        out.resize((512, 512), Image.LANCZOS).save(f"vfx_art/vfx_{name}.png", optimize=True)
        print(name)


if __name__ == "__main__":
    main()
