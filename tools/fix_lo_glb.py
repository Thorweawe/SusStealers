"""
Sadeleştirilmiş (*_lo.glb) dosyaları onarır, yeniden sadeleştirmeden:

  - Her üçgenin ayrı köşeleri (köşe = 3 x üçgen) birleştirilir: aynı konum +
    aynı UV tek köşe. Roblox ayrı köşeli ağı düz gölgeliyor, "kırık cam" gibi
    duruyordu (2026-10-03, kullanıcı: "petler kırık gözüküyor").
  - Normaller konuma göre yumuşak hesaplanır (UV dikişlerinde de kesintisiz).
  - Dokunun alfa kanalı atılır (TRELLIS'in yarı saydam yamaları).

    python tools/fix_lo_glb.py giriş.glb çıkış.glb
    python tools/fix_lo_glb.py --dir klasör çıkış_klasörü   (tüm *_lo.glb)
"""
import os
import sys

import numpy as np
import trimesh
from PIL import Image


def fix(src: str, dst: str) -> str:
    mesh = trimesh.load(src).to_geometry()
    tex = getattr(mesh.visual.material, "baseColorTexture", None)
    verts = np.asarray(mesh.vertices)
    faces = np.asarray(mesh.faces)
    uvs = np.asarray(mesh.visual.uv) if getattr(mesh.visual, "uv", None) is not None else np.zeros((len(verts), 2))
    before = len(verts)

    key = np.round(np.hstack([verts, uvs]), 6)
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inverse = inverse.reshape(-1)
    verts, uvs, faces = verts[first], uvs[first], inverse[faces]

    _, pinv = np.unique(np.round(verts, 6), axis=0, return_inverse=True)
    pinv = pinv.reshape(-1)
    tmp = trimesh.Trimesh(vertices=verts, faces=faces, process=False)
    weighted = tmp.face_normals * tmp.area_faces[:, None]
    acc = np.zeros((pinv.max() + 1, 3))
    for k in range(3):
        np.add.at(acc, pinv[faces[:, k]], weighted)
    vn = acc[pinv]
    vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)

    out = trimesh.Trimesh(vertices=verts, faces=faces, vertex_normals=vn, process=False)
    if isinstance(tex, Image.Image):
        tex = tex.convert("RGB")
    out.visual = trimesh.visual.TextureVisuals(
        uv=uvs, material=trimesh.visual.material.PBRMaterial(baseColorTexture=tex if isinstance(tex, Image.Image) else None))
    out.export(dst, include_normals=True)
    return f"{os.path.basename(src)}: köşe {before} -> {len(verts)}, üçgen {len(faces)}"


def main():
    if sys.argv[1] == "--dir":
        src_dir, dst_dir = sys.argv[2], sys.argv[3]
        os.makedirs(dst_dir, exist_ok=True)
        for f in sorted(os.listdir(src_dir)):
            if f.endswith("_lo.glb"):
                print(fix(os.path.join(src_dir, f), os.path.join(dst_dir, f)))
    else:
        print(fix(sys.argv[1], sys.argv[2]))


if __name__ == "__main__":
    main()
