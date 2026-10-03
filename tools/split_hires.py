"""Büyük dokulu (ör. 2048) TRELLIS ağını Roblox'a hazırlar: fix_lo_glb
(ortak köşe + normal + doku taşırma) sonra yüzler DOKU bölgelerine (UV
dörtte birleri) göre ayrılıyor; her parça kendi dokusunu (en çok 1024)
taşıyor. Roblox doku başına 1024 sınırını aşmadan büyük nesneler (ana
gemi) 4 kat net. Parça başına ≤19k üçgen.
    python tools/split_hires.py <ham.glb> <çıktı.glb> [ızgara=2]"""
import os, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import trimesh
from PIL import Image
from fix_lo_glb import fix

src, dst = sys.argv[1], sys.argv[2]
grid = int(sys.argv[3]) if len(sys.argv) > 3 else 2
tmp = os.path.join(tempfile.gettempdir(), 'split_hires_tmp.glb')
fix(src, tmp)
mesh = trimesh.load(tmp).to_geometry()
tex = mesh.visual.material.baseColorTexture.convert('RGB')
W, H = tex.size
uv = np.asarray(mesh.visual.uv)
faces = np.asarray(mesh.faces)
fuv = uv[faces]                      # (F,3,2)
cen = fuv.mean(axis=1)
cell = np.clip((cen * grid).astype(int), 0, grid - 1)
key = cell[:, 0] * grid + cell[:, 1]
scene = trimesh.Scene()
n = 0
for k in np.unique(key):
    idx = np.nonzero(key == k)[0]
    for chunk in np.array_split(idx, int(np.ceil(len(idx) / 19000))):
        f = faces[chunk]
        used = np.unique(f)
        remap = -np.ones(len(uv), dtype=int)
        remap[used] = np.arange(len(used))
        cuv = uv[used]
        u0, v0 = cuv.min(axis=0); u1, v1 = cuv.max(axis=0)
        pad = 4 / W
        u0, v0 = max(0, u0 - pad), max(0, v0 - pad)
        u1, v1 = min(1, u1 + pad), min(1, v1 + pad)
        # görüntü satırı: v=1 üstte
        box = (int(u0 * W), int((1 - v1) * H), int(np.ceil(u1 * W)), int(np.ceil((1 - v0) * H)))
        crop = tex.crop(box)
        s = min(1, 1024 / max(crop.size))
        if s < 1:
            crop = crop.resize((max(1, round(crop.size[0] * s)), max(1, round(crop.size[1] * s))), Image.LANCZOS)
        # kırpılan bölge piksel kenarına yuvarlandı: UV'yi gerçek kutuya göre eşle
        bu0, bu1 = box[0] / W, box[2] / W
        bv1, bv0 = 1 - box[1] / H, 1 - box[3] / H
        nuv = np.column_stack([(cuv[:, 0] - bu0) / (bu1 - bu0), (cuv[:, 1] - bv0) / (bv1 - bv0)])
        sub = trimesh.Trimesh(vertices=mesh.vertices[used], faces=remap[f],
                              vertex_normals=mesh.vertex_normals[used], process=False)
        sub.visual = trimesh.visual.TextureVisuals(uv=nuv, material=trimesh.visual.material.PBRMaterial(baseColorTexture=crop))
        scene.add_geometry(sub, geom_name=f'part{n}')
        print(f'part{n}: {len(chunk)} üçgen, doku {crop.size}', flush=True)
        n += 1
scene.export(dst)
print(len(faces), 'üçgen ->', n, 'parça', dst)
