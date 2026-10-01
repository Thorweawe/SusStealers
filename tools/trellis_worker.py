"""
Klasördeki *_concept.png'leri sırayla TRELLIS'e (Hugging Face, kullanıcının
girişli hesabı) gönderip <ad>.glb yapar; yeni konsept geldikçe devam eder.
Klasörde STOP dosyası olunca biter.

    python tools/trellis_worker.py models_3d/crew
"""
import os
import shutil
import sys
import time

from gradio_client import Client, handle_file
from huggingface_hub import get_token


def convert(c, src, dst):
    pre = c.predict(image=handle_file(src), api_name="/preprocess_image")
    r = c.predict(image=handle_file(pre if isinstance(pre, str) else pre["path"]), multiimages=[], seed=0,
                  ss_guidance_strength=7.5, ss_sampling_steps=12, slat_guidance_strength=3.0, slat_sampling_steps=12,
                  multiimage_algo="stochastic", mesh_simplify=0.95, texture_size=1024, api_name="/generate_and_extract_glb")
    glb = r[2] if isinstance(r[2], str) else r[1]
    shutil.copy(glb, dst)
    vid = r[0]["video"] if isinstance(r[0], dict) else r[0]
    if vid and os.path.exists(vid):
        shutil.copy(vid, dst.replace(".glb", "_preview.mp4"))


def main():
    folder = sys.argv[1]
    c = Client("trellis-community/TRELLIS", verbose=False, token=get_token())
    try:
        c.predict(api_name="/start_session")
    except Exception:
        pass
    failed = set()
    while True:
        todo = sorted(f for f in os.listdir(folder) if f.endswith("_concept.png")
                      and not os.path.exists(os.path.join(folder, f.replace("_concept.png", ".glb"))) and f not in failed)
        if not todo:
            if os.path.exists(os.path.join(folder, "STOP")):
                break
            time.sleep(15)
            continue
        f = todo[0]
        dst = os.path.join(folder, f.replace("_concept.png", ".glb"))
        try:
            convert(c, os.path.join(folder, f), dst)
            print("ok", f, flush=True)
        except Exception as e:
            print("HATA", f, str(e)[:200], flush=True)
            if "quota" in str(e).lower():
                break
            failed.add(f)
    print("bitti", flush=True)


if __name__ == "__main__":
    main()
