"""Magenta zeminli 3x3 ikon sayfasını keser ve saydamlaştırır.
    python icon_sheet.py <sayfa.png> <çıktı klasörü> ad1 ... ad9"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

src, out, names = sys.argv[1], sys.argv[2], sys.argv[3:]
os.makedirs(out, exist_ok=True)
im = Image.open(src).convert("RGB")
w, h = im.size
for k, name in enumerate(names):
    r, c = divmod(k, 3)
    cell = np.asarray(im.crop((c * w // 3, r * h // 3, (c + 1) * w // 3, (r + 1) * h // 3))).astype(int)
    R, G, B = cell[..., 0], cell[..., 1], cell[..., 2]
    # magentaya yakın: kırmızı ve mavi yüksek, yeşil düşük
    mag = (R > 150) & (B > 150) & (G < 110) & (np.abs(R - B) < 90)
    lab, n = ndimage.label(mag)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(edge))
    bg = ndimage.binary_dilation(bg, iterations=2)
    # Komşu hücreden taşan kırıntı: hücre kenarına değen, en büyüğe göre küçük parçalar
    fg = ~bg
    flab, fn = ndimage.label(fg)
    if fn > 1:
        sizes = ndimage.sum(fg, flab, range(1, fn + 1))
        big = sizes.max()
        border = set(np.unique(np.concatenate([flab[0], flab[-1], flab[:, 0], flab[:, -1]]))) - {0}
        for i, sz in enumerate(sizes, start=1):
            if sz < big and i in border:
                bg |= flab == i
    alpha = Image.fromarray(np.where(bg, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1))
    rgb = cell.copy()
    # kenarda kalan pembe sızıntıyı nötrle
    band = ndimage.binary_dilation(bg, iterations=5) & ~bg  # yalnız kenar şeridi
    spill = band & (R > G + 60) & (B > G + 60)
    rgb[spill, 0] = np.minimum(R[spill], G[spill] + 40)
    rgb[spill, 2] = np.minimum(B[spill], G[spill] + 40)
    o = Image.fromarray(rgb.astype(np.uint8)).convert("RGBA")
    o.putalpha(alpha)
    bbox = o.getbbox()
    if bbox:
        o = o.crop(bbox)
    side = max(o.size)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(o, ((side - o.width) // 2, (side - o.height) // 2), o)
    sq.resize((512, 512), Image.LANCZOS).save(os.path.join(out, name + ".png"), optimize=True)
    print(name)
