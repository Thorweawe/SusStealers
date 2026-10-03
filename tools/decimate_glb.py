"""
Dokulu GLB'yi (TRELLIS) UV'leri ve dokuyu koruyarak sadeleştirir: Roblox'ta
iskeletli (skinned) model TEK ağ olmalı ve ağ başına ~20k üçgen sınırı var.

    python tools/decimate_glb.py models_3d/kraken.glb models_3d/kraken_lo.glb 18000
"""
import os
import sys
import tempfile

import numpy as np
import pymeshlab
import trimesh
from PIL import Image


def main():
    src, dst, target = sys.argv[1], sys.argv[2], int(sys.argv[3])
    mesh = trimesh.load(src).to_geometry()
    tex = mesh.visual.material.baseColorTexture
    tmp = tempfile.mkdtemp()
    obj = os.path.join(tmp, "m.obj")
    # OBJ'ye yaz (wedge UV'li), MeshLab ile dokuyu koruyarak sadeleştir
    mesh.export(obj)
    ms = pymeshlab.MeshSet()
    ms.load_new_mesh(obj)
    before = ms.current_mesh().face_number()
    if before > target:
        ms.meshing_decimation_quadric_edge_collapse_with_texture(targetfacenum=target, preserveboundary=False, optimalplacement=True, extratcoordw=0.3)
        if ms.current_mesh().face_number() > target * 1.2:
            # UV dikişleri inatçıysa ikinci tur
            ms.meshing_decimation_quadric_edge_collapse_with_texture(targetfacenum=target, preserveboundary=False, optimalplacement=True, extratcoordw=0.1)
    m = ms.current_mesh()
    v = m.vertex_matrix()
    f = m.face_matrix()
    wt = m.wedge_tex_coord_matrix().reshape(-1, 3, 2) if m.has_wedge_tex_coord() else None
    # wedge UV -> köşe başına UV (köşeleri ayır)
    if wt is not None:
        verts = v[f].reshape(-1, 3)
        uvs = wt.reshape(-1, 2)
        faces = np.arange(len(verts)).reshape(-1, 3)
    else:
        verts, faces, uvs = v, f, m.vertex_tex_coord_matrix()
    # 2026-10-03 düzeltme ("petler kırık görünüyor"): her üçgen kendi köşeleriyle
    # yazılınca (köşe = 3 x üçgen) Roblox her yüzü düz gölgeliyor, ağ kırık cam
    # gibi duruyordu. Aynı konum + aynı UV'li köşeler birleşiyor, normaller konuma
    # göre (UV dikişlerinde de) yumuşak hesaplanıp dosyaya yazılıyor.
    key = np.round(np.hstack([verts, uvs]), 6)
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inverse = inverse.reshape(-1)
    verts, uvs, faces = verts[first], uvs[first], inverse[faces]
    pos = np.round(verts, 6)
    _, pinv = np.unique(pos, axis=0, return_inverse=True)
    pinv = pinv.reshape(-1)
    smooth = trimesh.Trimesh(vertices=verts, faces=faces, process=False)
    fn = smooth.face_normals * smooth.area_faces[:, None]
    acc = np.zeros((pinv.max() + 1, 3))
    for k in range(3):
        np.add.at(acc, pinv[faces[:, k]], fn)
    vn = acc[pinv]
    vn /= np.maximum(np.linalg.norm(vn, axis=1, keepdims=True), 1e-12)
    out = trimesh.Trimesh(vertices=verts, faces=faces, vertex_normals=vn, process=False)
    # Doku: TRELLIS'in alfa kanalı Roblox'ta yarı saydam yamalar yapıyordu
    if isinstance(tex, Image.Image):
        tex = tex.convert("RGB")
    out.visual = trimesh.visual.TextureVisuals(uv=uvs, material=trimesh.visual.material.PBRMaterial(baseColorTexture=tex if isinstance(tex, Image.Image) else None))
    out.export(dst, include_normals=True)
    print(f"{before} -> {len(faces)} üçgen, {dst}")


if __name__ == "__main__":
    main()
