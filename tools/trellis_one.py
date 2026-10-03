"""Tek konsepti TRELLIS'e verip birkaç tohumla .glb üretir, açık kenar
(delik) sayısını yazar. python tools/trellis_one.py <konsept.png> <çıktı_önek> [tohumlar...]"""
import os, shutil, sys
import numpy as np
import trimesh
from gradio_client import Client, handle_file
from huggingface_hub import get_token

src, prefix = sys.argv[1], sys.argv[2]
seeds = [int(s) for s in sys.argv[3:]] or [0]


def holes(p):
    m = trimesh.load(p, force='mesh')
    m.merge_vertices(merge_tex=True, merge_norm=True)
    _, c = np.unique(m.edges_sorted, axis=0, return_counts=True)
    return int((c == 1).sum()), len(m.faces)


c = Client("trellis-community/TRELLIS", verbose=False, token=get_token())
try:
    c.predict(api_name="/start_session")
except Exception:
    pass
pre = c.predict(image=handle_file(src), api_name="/preprocess_image")
for seed in seeds:
    try:
        r = c.predict(image=handle_file(pre if isinstance(pre, str) else pre["path"]), multiimages=[], seed=seed,
                      ss_guidance_strength=7.5, ss_sampling_steps=12, slat_guidance_strength=3.0, slat_sampling_steps=12,
                      multiimage_algo="stochastic", mesh_simplify=0.95, texture_size=1024, api_name="/generate_and_extract_glb")
        glb = r[2] if isinstance(r[2], str) else r[1]
        dst = f'{prefix}_s{seed}.glb'
        shutil.copy(glb, dst)
        print('seed', seed, holes(dst), flush=True)
    except Exception as ex:
        print('seed', seed, 'ERR', ex, flush=True)
