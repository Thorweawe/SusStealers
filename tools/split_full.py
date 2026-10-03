"""Yüksek çözünürlüklü TRELLIS ağını SADELEŞTİRMEDEN Roblox'a hazırlar:
fix_lo_glb (ortak köşe + yumuşak normal + doku taşırma) sonra yüzler x
eksenine göre ≤19k'lık dilimlere bölünüp aynı dokuyu paylaşan ayrı ağlar
olarak tek GLB'ye yazılır (Roblox: ağ başına ~20k sınırı). Sadeleştirmenin
UV dikişlerinde açtığı siyah çatlaklar olmuyor.
    python tools/split_full.py <ham.glb> <çıktı.glb>"""
import os, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import numpy as np
import trimesh
from fix_lo_glb import fix

src, dst = sys.argv[1], sys.argv[2]
tmp = os.path.join(tempfile.gettempdir(), 'split_full_tmp.glb')
fix(src, tmp)
mesh = trimesh.load(tmp).to_geometry()
n = len(mesh.faces)
k = int(np.ceil(n / 19000))
order = np.argsort(mesh.triangles_center[:, 0])
scene = trimesh.Scene()
for i, chunk in enumerate(np.array_split(order, k)):
    sub = mesh.submesh([np.sort(chunk)], append=True)
    scene.add_geometry(sub, geom_name=f'part{i}')
scene.export(dst)
print(n, 'üçgen ->', k, 'parça', dst)
