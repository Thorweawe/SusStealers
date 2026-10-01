"""
Resimden-3D (TRELLIS) GLB'sini Roblox'a hazırlar: 180° çevirir (yüz -Z'ye,
oyundaki canavar yönü), tabanı y=0'a oturtur, boyu `height` stud yapar ve
yüzleri bölgelere ayırır (Body / Lower ...) — her bölge ayrı ağ: hem Roblox'un ağ başına
~20k üçgen sınırı hem de ayrı kemiğe bağlanabilen parçalar için.

    python tools/split_mesh.py models_3d/chomper.glb chomper 17
    -> models_3d/<ad>_roblox.glb  (Studio: Import 3D)

Bölgeler aşağıdaki REGIONS'ta, normalleştirilmiş uzayda (boy 1, taban 0,
x merkezli) tanımlı.
"""
import json
import sys

import numpy as np
import trimesh

REGIONS = {
    # ad: (xmin, xmax, ymin, ymax) — çevrilmiş uzayda; ilk eşleşen kazanır
    # Kollar gövdeden temiz ayrılmıyor (gövde kol kadar geniş): Chomper tek
    # parça; sadece Roblox'un ağ başına ~20k üçgen sınırı için alt/üst yarı.
    "chomper": {
        "Lower": (-9, 9, -1, 0.45),
    },
}


def main():
    src, name, height = sys.argv[1], sys.argv[2], float(sys.argv[3])
    m = trimesh.load(src).to_geometry()
    # 180° Y: (x, z) -> (-x, -z)
    m.apply_transform(trimesh.transformations.rotation_matrix(np.pi, [0, 1, 0]))
    lo, hi = m.bounds
    k = 1.0 / (hi[1] - lo[1])
    cx, cz = (lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2
    m.apply_translation([-cx, -lo[1], -cz])
    m.apply_scale(k)
    fc = m.triangles_center
    label = np.array(["Body"] * len(fc), dtype=object)
    for part, (x0, x1, y0, y1) in REGIONS.get(name, {}).items():
        sel = (label == "Body") & (fc[:, 0] >= x0) & (fc[:, 0] <= x1) & (fc[:, 1] >= y0) & (fc[:, 1] <= y1)
        label[sel] = part
    m.apply_scale(height)
    scene = trimesh.Scene()
    info = {}
    for part in ["Body"] + list(REGIONS.get(name, {}).keys()):
        idx = np.nonzero(label == part)[0]
        sub = m.submesh([idx], append=True)
        scene.add_geometry(sub, node_name=part, geom_name=part)
        lo, hi = sub.bounds
        info[part] = {"tris": int(len(idx)), "center": ((lo + hi) / 2).round(3).tolist(), "size": (hi - lo).round(3).tolist()}
    out = f"models_3d/{name}_roblox.glb"
    scene.export(out)
    json.dump(info, open(f"models_3d/{name}_parts.json", "w"), indent=1)
    print(out)
    print(json.dumps(info, indent=1))


if __name__ == "__main__":
    main()
