"""
Ham TRELLIS çıktılarından (models_3d/<klasör>/<Ad>.glb) oyuna girecek *_lo.glb'leri
yeniden üretir (2026-10-03, "kırık/çatlak görünüyor"):

  - 20 000 üçgenin altındaki ham ağ HİÇ sadeleştirilmiyor (Roblox sınırı 20k);
    sadeleştirme UV dikişlerini bozup dokuda siyah/beyaz çatlaklar açıyordu.
  - Üstündekiler hafifçe (15k, büyük savunma gemileri 19k) sadeleştiriliyor.
  - Sonra tools/fix_lo_glb.py: ortak köşe + yumuşak normal + alfasız, taşırılmış doku.

    python tools/rebuild_from_raw.py çıkış_klasörü
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "models_3d")
sys.path.insert(0, HERE)
from fix_lo_glb import fix  # noqa: E402

import trimesh  # noqa: E402

# ham ad -> çıktı adı (_lo); klasör başına adlandırma geleneği
PREFIX = {"defense": "def", "gear": "gear", "hats2": "hat"}
LOWER = {"pets", "event", "starfall"}  # bu klasörlerde *_lo adları küçük harf
LIMIT = 20000
TARGET = {"defense": 19000}


def out_name(folder: str, raw: str) -> str:
    base = raw[:-4]
    if folder in LOWER:
        base = base.lower()
    return PREFIX.get(folder, "") + base + "_lo.glb"


def main():
    out_dir = sys.argv[1]
    for folder in ["crew", "pets", "props", "hats2", "event", "starfall", "gear", "defense"]:
        src_dir = os.path.join(ROOT, folder)
        dst_dir = os.path.join(out_dir, folder)
        os.makedirs(dst_dir, exist_ok=True)
        for f in sorted(os.listdir(src_dir)):
            if not f.endswith(".glb") or f.endswith("_lo.glb") or f.endswith("_rig.glb"):
                continue
            name = out_name(folder, f)
            # yalnız oyunda kullanılan (önceden *_lo'su olan) modeller
            if not os.path.exists(os.path.join(src_dir, name)):
                continue
            src = os.path.join(src_dir, f)
            faces = len(trimesh.load(src).to_geometry().faces)
            mid = src
            if faces > LIMIT:
                mid = os.path.join(dst_dir, "_tmp_" + name)
                subprocess.run([sys.executable, os.path.join(HERE, "decimate_glb.py"), src, mid,
                                str(TARGET.get(folder, 15000))], check=True, capture_output=True)
            print(folder, fix(mid, os.path.join(dst_dir, name)), "(ham " + str(faces) + ")", flush=True)
            if mid != src:
                os.remove(mid)


if __name__ == "__main__":
    main()
