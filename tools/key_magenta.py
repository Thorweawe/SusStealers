"""Magenta zeminli tek görseli (ChatGPT) saydam PNG'ye çevirir: zemin kenardan
flood fill ile bulunuyor (koyu kontur içeriyi koruyor), sonra kırpılıp en
fazla 1024 px'e küçültülüyor (Roblox sınırı).
    python tools/key_magenta.py <girdi.png> <çıktı.png> [en büyük kenar]"""
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

src, dst = sys.argv[1], sys.argv[2]
limit = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
im = np.asarray(Image.open(src).convert('RGB')).astype(np.int32)
r, g, b = im[..., 0], im[..., 1], im[..., 2]
dist = np.sqrt((255 - r) ** 2 + g ** 2 + (255 - b) ** 2)
near = dist < 130
lab, n = ndimage.label(near)
edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
bg = np.isin(lab, edge[edge > 0])
sizes = ndimage.sum(near, lab, range(1, n + 1))
bg |= np.isin(lab, np.nonzero(sizes > 1500)[0] + 1) & (dist < 60)
alpha = np.where(bg, np.clip((dist - 45) / 85, 0, 1), 1.0)
rgb = im.copy()
spill = bg & (alpha < 1) & (r > g + 30) & (b > g + 30)
for ch in (0, 2):
    c = rgb[..., ch]
    c[spill] = np.minimum(c[spill], g[spill] + (c[spill] - g[spill]) // 3)
out = Image.fromarray(np.dstack([np.clip(rgb, 0, 255), (alpha * 255)]).astype(np.uint8), 'RGBA')
box = out.getchannel('A').point(lambda v: 255 if v > 8 else 0).getbbox()
out = out.crop(box)
s = min(1, limit / max(out.size))
if s < 1:
    out = out.resize((round(out.size[0] * s), round(out.size[1] * s)), Image.LANCZOS)
out.save(dst)
print(dst, out.size)
