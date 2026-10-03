"""Boss iskeletli modellerini (*_rig.glb) ham TRELLIS çıktısından yeniden üretir
(2026-10-03, "boss'lar köşeli/kırık"): ham ağ ≤20k üçgense olduğu gibi, değilse
18k'ya sadeleştirilir → fix_lo_glb (ortak köşe + yumuşak normal + doku taşırma)
→ auto_rig. Eski *_rig dosyalarına dokunmaz; çıktı models_3d/_fix3/bosses/.
    python tools/rebuild_bosses.py"""
import os, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import trimesh
from fix_lo_glb import fix

ROOT = os.path.join(HERE, '..', 'models_3d')
OUT = os.path.join(ROOT, '_fix3', 'bosses')
os.makedirs(OUT, exist_ok=True)
BOSSES = ['chomper', 'glorp', 'sandmaw', 'riftstalker', 'voidleviathan', 'frostwyrm',
          'crystalgolem', 'solarphoenix', 'blackhole', 'galaxytitan']
for n in BOSSES:
    src = os.path.join(ROOT, n + '.glb')
    faces = len(trimesh.load(src).to_geometry().faces)
    mid = src
    if faces > 20000:
        mid = os.path.join(OUT, '_tmp_' + n + '.glb')
        subprocess.run([sys.executable, os.path.join(HERE, 'decimate_glb.py'), src, mid, '18000'], check=True, capture_output=True)
    fixed = os.path.join(OUT, n + '_lo.glb')
    fix(mid, fixed)
    if mid != src:
        os.remove(mid)
    r = subprocess.run([sys.executable, os.path.join(HERE, 'auto_rig.py'), fixed, os.path.join(OUT, n + '_rig.glb')],
                       capture_output=True, text=True)
    print(n, 'ham', faces, r.stdout.strip() or r.stderr.strip()[-300:], flush=True)
