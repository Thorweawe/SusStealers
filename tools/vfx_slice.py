"""
ChatGPT'den gelen 2x2 VFX sayfasını (siyah zemin, beyaz sprite) dört saydam
PNG'ye böler: parlaklık = alfa, renk beyaz (oyunda ParticleEmitter.Color boyar).

    python tools/vfx_slice.py vfx_art/_sheet2_raw.png flame snowflake spark crystal
"""
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter


def main():
    src, names = sys.argv[1], sys.argv[2:6]
    im = Image.open(src).convert("L")
    w, h = im.size
    for k, name in enumerate(names):
        r, c = divmod(k, 2)
        cell = im.crop((c * w // 2, r * h // 2, (c + 1) * w // 2, (r + 1) * h // 2))
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
