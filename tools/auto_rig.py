"""
Kendi otomatik iskeletimiz (UniRig yedeği): dokulu tek parça GLB'ye kemik ve
deri ağırlığı ekler, Roblox'un okuduğu iskeletli (skinned) GLB yazar.

    python tools/auto_rig.py models_3d/kraken_lo.glb models_3d/kraken_rig.glb [--preview out.png]

Yöntem (geometriden, kemik adı/şablon gerekmez):
  1. Ağ vokselleniyor ve içi dolduruluyor.
  2. Uzaklık dönüşümü: yüzeyden en uzak (kalın) bölge = GÖVDE çekirdeği;
     çekirdeğin şişirilmişi gövde, geri kalan ince parçalar = UZUV.
  3. Her uzuv bileşeni için gövdeye değdiği yerden başlayarak voksel BFS ile
     "uzuv boyunca uzaklık" ölçülüyor; eşit aralıklı dilimlerin ağırlık
     merkezleri kemik zinciri (kıvrık dokunaç da doğru izleniyor).
  4. Köşe ağırlığı: köşenin en yakın dolu vokselinin uzuv/uzaklık değerinden;
     dilimler arasında doğrusal, gövdeye geçişte yumuşak.
Kemik adları: Root, L<uzuv>_<sıra>. Kemikler dönüşsüz (bind = öteleme).
"""
import argparse
import io
import json
import struct
from collections import deque

import numpy as np
import pygltflib
import trimesh
from PIL import Image
from scipy import ndimage
from scipy.spatial import cKDTree

SEG = 3          # uzuv başına kemik sayısı
RES = 72         # en uzun eksende voksel sayısı
CORE = 0.42      # çekirdek eşiği (en kalın noktanın oranı)
MIN_LIMB = 0.004
BRANCH = 0.22    # uzuv dibinden bu oran uzaklıkta dallara ayrılıyor # dolu hacmin bu oranından küçük uzuvlar gövdeye katılıyor


def build_rig(mesh: trimesh.Trimesh):
    V = mesh.vertices
    lo, hi = V.min(0), V.max(0)
    pitch = (hi - lo).max() / RES
    vox = mesh.voxelized(pitch).fill()
    filled = vox.matrix.copy()
    origin = vox.transform[:3, 3]  # voksel (0,0,0) merkezi

    dist = ndimage.distance_transform_edt(filled)
    core = dist >= CORE * dist.max()
    # açma: çekirdeği eşik kadar şişir -> gövde (kalın kısımlar)
    r = int(np.ceil(CORE * dist.max())) + 1
    ball = ndimage.generate_binary_structure(3, 1)
    body = ndimage.binary_dilation(core, structure=ball, iterations=r) & filled
    limbs = filled & ~body
    lab, n = ndimage.label(limbs, structure=np.ones((3, 3, 3)))
    total = filled.sum()

    def center(idx):
        return origin + np.asarray(idx, float) * pitch

    core_pts = center(np.argwhere(core))
    root_pos = core_pts.mean(0) if len(core_pts) else (lo + hi) / 2

    bones = [{"name": "Root", "parent": -1, "pos": root_pos}]
    limb_info = {}  # etiket -> (bone indeksleri, geodezik uzunluk, uzaklık haritası)
    geo = np.full(filled.shape, -1.0)
    limb_id = np.zeros(filled.shape, int)
    body_d = ndimage.binary_dilation(body, structure=ball)
    kept = 0
    for k in range(1, n + 1):
        cells = np.argwhere(lab == k)
        if len(cells) < MIN_LIMB * total:
            continue
        mask = lab == k
        # gövdeye değen hücrelerden BFS
        start = [tuple(c) for c in cells if body_d[tuple(c)]]
        if not start:
            continue
        q = deque()
        for c in start:
            geo[c] = 0
            q.append(c)
        while q:
            c = q.popleft()
            for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)):
                nb = (c[0] + d[0], c[1] + d[1], c[2] + d[2])
                if 0 <= nb[0] < mask.shape[0] and 0 <= nb[1] < mask.shape[1] and 0 <= nb[2] < mask.shape[2]:
                    if mask[nb] and geo[nb] < 0:
                        geo[nb] = geo[c] + 1
                        q.append(nb)
        g = geo[mask]
        D = g.max()
        if D < 3:
            geo[mask] = -1
            continue
        # Dallar: gövdeden biraz uzaklaşınca birbirinden ayrılan kollar
        # (dokunaçlar dipte halka gibi birleşik) ayrı uzuv sayılıyor.
        t = BRANCH * D
        sub, m = ndimage.label(mask & (geo > t), structure=np.ones((3, 3, 3)))
        branches = []
        for j in range(1, m + 1):
            bc = np.argwhere(sub == j)
            if len(bc) >= MIN_LIMB * total:
                branches.append(bc)
        if not branches:
            branches = [cells]
        # dip bölgesi en yakın dala
        btree = cKDTree(np.concatenate(branches))
        owner = np.concatenate([np.full(len(bc), bi) for bi, bc in enumerate(branches)])
        base_cells = cells[geo[tuple(cells.T)] <= t] if len(branches) > 1 else np.zeros((0, 3), int)
        groups = [list(map(tuple, bc)) for bc in branches]
        if len(base_cells):
            _, ni = btree.query(base_cells)
            for c, o in zip(map(tuple, base_cells), owner[ni]):
                groups[o].append(c)
        for grp in groups:
            gc = np.array(grp)
            gg = geo[tuple(gc.T)]
            L = gg.max()
            if L < 3:
                continue
            kept += 1
            limb_id[tuple(gc.T)] = kept
            idxs = []
            parent = 0
            for sgi in range(SEG):
                band = (gg >= L * sgi / SEG) & (gg <= L * (sgi + 0.35) / SEG + 1)
                pts = center(gc[band]) if band.any() else center(gc[:1])
                bi = len(bones)
                bones.append({"name": f"L{kept}_{sgi + 1}", "parent": parent, "pos": pts.mean(0)})
                idxs.append(bi)
                parent = bi
            limb_info[kept] = (idxs, L)

    # Köşe ağırlıkları: en yakın dolu voksel
    fcells = np.argwhere(filled)
    tree = cKDTree(center(fcells))
    _, near = tree.query(V)
    nc = fcells[near]
    J = np.zeros((len(V), 4), np.uint16)
    W = np.zeros((len(V), 4), np.float32)
    J[:, 0] = 0
    W[:, 0] = 1
    for i, c in enumerate(map(tuple, nc)):
        k = limb_id[c]
        if k == 0 or k not in limb_info or geo[c] < 0:
            continue
        idxs, D = limb_info[k]
        s = geo[c] / D * SEG  # 0..SEG
        seg = min(int(s), SEG - 1)
        f = s - seg
        if seg == 0 and s < 0.35:
            # gövdeye geçiş: kök ile ilk kemik arası
            t = s / 0.35
            J[i, :2] = (0, idxs[0])
            W[i, :2] = (1 - t, t)
        elif seg < SEG - 1 and f > 0.6:
            t = (f - 0.6) / 0.4
            J[i, :2] = (idxs[seg], idxs[seg + 1])
            W[i, :2] = (1 - t * 0.5, t * 0.5)
        else:
            J[i, 0] = idxs[seg]
            W[i, 0] = 1
    W /= W.sum(1, keepdims=True)
    return bones, J, W, kept


def write_glb(mesh, bones, J, W, dst):
    V = mesh.vertices.astype(np.float32)
    N = mesh.vertex_normals.astype(np.float32)
    UV = mesh.visual.uv.astype(np.float32).copy()
    UV[:, 1] = 1 - UV[:, 1]  # glTF: v aşağı
    I = mesh.faces.astype(np.uint32).ravel()
    tex = mesh.visual.material.baseColorTexture
    png = io.BytesIO()
    (tex if isinstance(tex, Image.Image) else Image.new("RGB", (4, 4), (200, 200, 200))).convert("RGB").save(png, "PNG")
    png = png.getvalue()

    # Ters bağlama: kemikler dönüşsüz, bind = öteleme(pos)
    ibm = np.zeros((len(bones), 16), np.float32)
    for i, b in enumerate(bones):
        m = np.eye(4, dtype=np.float32)
        m[:3, 3] = -b["pos"]
        ibm[i] = m.T.ravel()  # glTF sütun-öncelikli

    blobs = [V.tobytes(), N.tobytes(), UV.tobytes(), J.tobytes(), W.tobytes(), I.tobytes(), ibm.tobytes(), png]
    offs, buf = [], b""
    for bl in blobs:
        pad = (-len(buf)) % 4
        buf += b"\0" * pad
        offs.append(len(buf))
        buf += bl
    g = pygltflib.GLTF2()
    g.buffers = [pygltflib.Buffer(byteLength=len(buf))]
    targets = [34962, 34962, 34962, 34962, 34962, 34963, None, None]
    for k, bl in enumerate(blobs):
        bv = pygltflib.BufferView(buffer=0, byteOffset=offs[k], byteLength=len(bl))
        if targets[k]:
            bv.target = targets[k]
        g.bufferViews.append(bv)
    n = len(V)
    g.accessors = [
        pygltflib.Accessor(bufferView=0, componentType=5126, count=n, type="VEC3", min=V.min(0).tolist(), max=V.max(0).tolist()),
        pygltflib.Accessor(bufferView=1, componentType=5126, count=n, type="VEC3"),
        pygltflib.Accessor(bufferView=2, componentType=5126, count=n, type="VEC2"),
        pygltflib.Accessor(bufferView=3, componentType=5123, count=n, type="VEC4"),
        pygltflib.Accessor(bufferView=4, componentType=5126, count=n, type="VEC4"),
        pygltflib.Accessor(bufferView=5, componentType=5125, count=len(I), type="SCALAR"),
        pygltflib.Accessor(bufferView=6, componentType=5126, count=len(bones), type="MAT4"),
    ]
    g.images = [pygltflib.Image(bufferView=7, mimeType="image/png")]
    g.textures = [pygltflib.Texture(source=0)]
    g.materials = [pygltflib.Material(pbrMetallicRoughness=pygltflib.PbrMetallicRoughness(baseColorTexture=pygltflib.TextureInfo(index=0), metallicFactor=0, roughnessFactor=0.6))]
    g.meshes = [pygltflib.Mesh(primitives=[pygltflib.Primitive(attributes=pygltflib.Attributes(POSITION=0, NORMAL=1, TEXCOORD_0=2, JOINTS_0=3, WEIGHTS_0=4), indices=5, material=0)])]
    # düğümler: 0 = ağ, 1.. = kemikler
    nodes = [pygltflib.Node(name="Body", mesh=0, skin=0)]
    for i, b in enumerate(bones):
        ppos = bones[b["parent"]]["pos"] if b["parent"] >= 0 else np.zeros(3)
        nodes.append(pygltflib.Node(name=b["name"], translation=(b["pos"] - ppos).astype(float).tolist(), children=[]))
    for i, b in enumerate(bones):
        if b["parent"] >= 0:
            nodes[b["parent"] + 1].children.append(i + 1)
    g.nodes = nodes
    g.skins = [pygltflib.Skin(joints=[i + 1 for i in range(len(bones))], inverseBindMatrices=6, skeleton=1)]
    g.scenes = [pygltflib.Scene(nodes=[0, 1])]
    g.scene = 0
    g.set_binary_blob(buf)
    g.save_binary(dst)


def preview(mesh, bones, J, out):
    """Önden/yandan: köşeler baskın kemiğe göre renkli, kemikler beyaz."""
    from PIL import ImageDraw
    V = mesh.vertices
    lo, hi = V.min(0), V.max(0)
    S = 360
    rng = np.random.default_rng(3)
    pal = (rng.random((len(bones), 3)) * 200 + 55).astype(int)
    pal[0] = (90, 90, 90)
    img = Image.new("RGB", (S * 2, S), (20, 20, 20))
    d = ImageDraw.Draw(img)
    span = (hi - lo).max()
    for view, (a, b) in enumerate(((0, 1), (2, 1))):
        for i in np.argsort(V[:, 2 if view == 0 else 0]):
            x = (V[i, a] - lo[a]) / span * (S - 20) + 10 + view * S
            y = S - 10 - (V[i, b] - lo[b]) / span * (S - 20)
            d.point((x, y), fill=tuple(pal[J[i, 0]]))
        for bi, bn in enumerate(bones):
            p = bn["pos"]
            x = (p[a] - lo[a]) / span * (S - 20) + 10 + view * S
            y = S - 10 - (p[b] - lo[b]) / span * (S - 20)
            d.ellipse((x - 3, y - 3, x + 3, y + 3), fill=(255, 255, 255))
            if bn["parent"] >= 0:
                q = bones[bn["parent"]]["pos"]
                d.line((x, y, (q[a] - lo[a]) / span * (S - 20) + 10 + view * S, S - 10 - (q[b] - lo[b]) / span * (S - 20)), fill=(255, 255, 255))
    img.save(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--preview")
    ap.add_argument("--core", type=float, default=None)
    a = ap.parse_args()
    if a.core is not None:
        globals()["CORE"] = a.core
    mesh = trimesh.load(a.src).to_geometry()
    bones, J, W, kept = build_rig(mesh)
    write_glb(mesh, bones, J, W, a.dst)
    print(json.dumps({"bones": len(bones), "limbs": kept, "verts": len(mesh.vertices)}))
    if a.preview:
        preview(mesh, bones, J, a.preview)


if __name__ == "__main__":
    main()
