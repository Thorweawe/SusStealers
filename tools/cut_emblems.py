"""Magenta zeminli amblem sayfasını (ChatGPT, düzenli ızgara) tek tek saydam PNG'lere böler.
    python tools/cut_emblems.py <sheet.png> <çıktı klasörü> <sütun> <ad1,ad2,...>
Her bağlı leke ağırlık merkezinin düştüğü hücreye ait; komşunun taşan parçası maskeleniyor."""
import os, sys
import numpy as np
from PIL import Image
from scipy import ndimage

src, out, cols, names = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4].split(',')
rows = (len(names) + cols - 1) // cols
img = Image.open(src).convert('RGBA')
im = np.asarray(img).astype(np.int32)
r, g, b = im[..., 0], im[..., 1], im[..., 2]
dist = np.sqrt((255 - r) ** 2 + g ** 2 + (255 - b) ** 2)
# Zemin = kenardan taşan magentaya yakın bölge (flood fill). Amblemin kalın
# koyu konturu dolguyu durduruyor; içerideki mor/pembe renkler korunuyor.
near = dist < 130
nl, _ = ndimage.label(near)
edge = np.unique(np.concatenate([nl[0], nl[-1], nl[:, 0], nl[:, -1]]))
bg = np.isin(nl, edge[edge > 0])
# amblemler arasında kapalı kalan küçük magenta adacıkları da zemin
sizes = ndimage.sum(near, nl, range(1, nl.max() + 1))
big = np.nonzero(sizes > 1500)[0] + 1
bg |= np.isin(nl, big) & (dist < 60)
alpha = np.where(bg, np.clip((dist - 45) / 85, 0, 1), 1.0)
fg = ndimage.binary_opening(alpha > 0.5, iterations=1)
lab, n = ndimage.label(fg)
H, W = fg.shape
# satır bantları: ön planın dikey izdüşümündeki boşluklardan
prof = fg.sum(axis=1) > 3
bands, inb = [], False
for y, v in enumerate(prof):
    if v and not inb: start, inb = y, True
    elif not v and inb:
        if y - start > 40: bands.append((start, y))
        inb = False
if inb: bands.append((start, H))
assert len(bands) == rows, bands
# Lekeler birbirine değebiliyor (parıltılar): her piksel en yakın hücre merkezine ait
cw = W / cols
colidx = np.minimum(cols - 1, (np.arange(W) / cw).astype(int))
rgb = im[..., :3].copy()
spill = bg & (alpha < 1) & (r > g + 30) & (b > g + 30)
for ch in (0, 2):
    c = rgb[..., ch]
    c[spill] = np.minimum(c[spill], g[spill] + (c[spill] - g[spill]) // 3)
os.makedirs(out, exist_ok=True)
for i, name in enumerate(names):
    ri, ci = i // cols, i % cols
    a0, a1 = bands[ri]
    mask = np.zeros_like(fg)
    mask[a0:a1, :] = fg[a0:a1, :] & (colidx == ci)[None, :]
    # hücreye taşan küçük komşu kırıntılarını at: en büyük leke + ona yakınlar
    l2, n2 = ndimage.label(ndimage.binary_dilation(mask, iterations=4))
    if n2 > 1:
        sz = ndimage.sum(mask, l2, range(1, n2 + 1))
        mask &= l2 == (np.argmax(sz) + 1)
    mask = ndimage.binary_dilation(mask, iterations=2)
    ys, xs = np.nonzero(mask)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    a = (alpha * mask * 255).astype(np.uint8)
    rgba = np.dstack([rgb.astype(np.uint8), a])[y0:y1, x0:x1]
    crop = Image.fromarray(rgba, 'RGBA')
    w, h = crop.size
    side = max(w, h) + 8
    canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    canvas.paste(crop, ((side - w) // 2, (side - h) // 2))
    canvas.resize((256, 256), Image.LANCZOS).save(os.path.join(out, name + '.png'))
print(len(names), 'kesildi', len(bands), 'satir')
