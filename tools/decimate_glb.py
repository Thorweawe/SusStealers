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
        ms.meshing_decimation_quadric_edge_collapse_with_texture(targetfacenum=target, preserveboundary=True, optimalplacement=True)
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
    out = trimesh.Trimesh(vertices=verts, faces=faces, process=False)
    out.merge_vertices(merge_tex=False, merge_norm=True) if False else None
    out.visual = trimesh.visual.TextureVisuals(uv=uvs, material=trimesh.visual.material.PBRMaterial(baseColorTexture=tex if isinstance(tex, Image.Image) else None))
    out.export(dst)
    print(f"{before} -> {len(faces)} üçgen, {dst}")


if __name__ == "__main__":
    main()
