"""
TikTok / Shorts kısa videosu (9:16, 1080x1920, 30 fps) — 16+ kitle için POV kalıbı.

    python tools/tiktok_pov.py   ->  tiktok/pov_secret.mp4
                                     tiktok/overlays/*.png  (kendi oynanış kaydına koymak için şeffaf yazılar)

Akış (10 sn, ses yok — TikTok'ta trend bir ses eklenecek, erişimi o artırıyor):
  0.0-2.0  karakter gökkuşağı SECRET'le: "POV: you just stole a" + SECRET + $1.2B/s
  2.0-2.5  kamera sert sola kayıyor (hareket bulanıklığı) -> canavar
  2.5-4.8  Chomper'ın ağzına yakınlaş, sarsıntı, "RUN!!"
  4.8-5.3  geri kayış
  5.3-7.4  "WORTH IT?" (risk sorusu -> yorumlara cevap yazdırır)
  7.4-10   bitiş kartı: STEAL A CREWMATE, STARFALL etkinliği, "search on Roblox"
Sahneler tools/thumbnails_v2.py'den (aynı çizimler).
"""

import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import imageio_ffmpeg  # noqa: E402
import thumbnails as T  # noqa: E402
import thumbnails_v2 as V  # noqa: E402

ROOT = T.ROOT
OUTDIR = os.path.join(ROOT, "tiktok")
FW, FH, FPS = 1080, 1920, 30
DUR = 10.0


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def pop(t, start, dur=0.35):
    """0 -> 1.15 -> 1 zıplayan ölçek (yazı belirmesi)."""
    k = (t - start) / dur
    if k <= 0:
        return 0.0
    if k >= 1:
        return 1.0
    return math.sin(k * math.pi * 0.75) * 1.15 if k < 0.66 else 1.15 - (k - 0.66) / 0.34 * 0.15


def txt(s, size, **kw):
    return T.text_art(s, size, **kw)


def paste_center(frame, img, cx, cy, scale=1.0, angle=0):
    if scale <= 0.01:
        return
    im = img
    if scale != 1.0:
        im = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.LANCZOS)
    if angle:
        im = im.rotate(angle, Image.BICUBIC, expand=True)
    frame.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))


def crop_at(scene, cx, zoom, shake=(0, 0)):
    """16:9 4K sahneden 9:16 pencere: merkez x, yakınlaşma (1 = tam yükseklik)."""
    h = scene.height / zoom
    w = h * FW / FH
    x0 = max(0, min(scene.width - w, cx - w / 2)) + shake[0]
    y0 = max(0, min(scene.height - h, scene.height - h)) + shake[1]
    x0 = max(0, min(scene.width - w, x0))
    y0 = max(0, min(scene.height - h, y0))
    return scene.crop((int(x0), int(y0), int(x0 + w), int(y0 + h))).resize((FW, FH), Image.BILINEAR)


def pill_img(s, size):
    t = txt(s, size, fill=(255, 255, 255), stroke=(0, 0, 0), sw=0.05, extrude=0.0, gloss=False)
    pw, ph = t.width + size * 0.8, t.height + size * 0.35
    im = Image.new("RGBA", (int(pw + 16), int(ph + 16)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((8, 8, pw + 8, ph + 8), radius=ph / 2, fill=(12, 12, 16, 235), outline=(255, 255, 255, 255), width=5)
    im.alpha_composite(t, (int((im.width - t.width) / 2), int((im.height - t.height) / 2)))
    return im


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    print("sahneler çiziliyor...")
    chomp = V.scene_chomp("smug", "none").convert("RGB")
    star = V.scene_starfall().convert("RGB")

    # Yazılar (bir kez çizilip her karede ölçekleniyor)
    pov = pill_img("POV: you just stole a", 70)
    secret = txt("SECRET", 190, fill=T.rainbow_fill())
    money = txt("$1.2B/s", 130, fill=T.money_fill(), stroke=(10, 70, 20))
    run = txt("RUN!!", 230, fill=(255, 255, 255), stroke=(200, 20, 40))
    worth = txt("WORTH IT?", 170, fill=(255, 255, 255), stroke=(180, 20, 60))
    comment = pill_img("comment YES or NO", 56)
    title_a = txt("STEAL A", 110, fill=(255, 255, 255), stroke=(200, 30, 50))
    title_b = txt("CREWMATE", 148, fill=(255, 255, 255))
    event = pill_img("NEW EVENT: STARFALL", 64)
    search = txt("search it on Roblox", 70, fill=(255, 235, 120), stroke=(60, 40, 0), sw=0.1)

    # Canavar ağzı ve avatar merkezleri (4K sahnede, thumbnails_v2 yerleşimiyle)
    AV_X, MON_X, MOUTH_X = 3000, 1150, 1500

    ff = imageio_ffmpeg.get_ffmpeg_exe()
    out = os.path.join(OUTDIR, "pov_secret.mp4")
    writer = imageio_ffmpeg.write_frames(out, (FW, FH), fps=FPS, codec="libx264", quality=8,
                                         pix_fmt_out="yuv420p", macro_block_size=8)
    writer.send(None)
    n = int(DUR * FPS)
    for i in range(n):
        t = i / FPS
        shake = (0, 0)
        if t < 2.0:
            frame = crop_at(chomp, AV_X, 1.0 + 0.08 * t / 2.0)
        elif t < 2.5:
            k = ease((t - 2.0) / 0.5)
            cx = AV_X + (MOUTH_X - AV_X) * k
            # hareket bulanıklığı: birkaç komşu pencerenin ortalaması
            frames = [crop_at(chomp, cx + dx, 1.1) for dx in range(-160, 161, 40)]
            frame = frames[0]
            for j, f in enumerate(frames[1:], start=2):
                frame = Image.blend(frame, f, 1 / j)
        elif t < 4.8:
            k = (t - 2.5) / 2.3
            amp = 26 * (1 - k) + 8
            shake = (math.sin(t * 61) * amp, math.cos(t * 47) * amp * 0.6)
            frame = crop_at(chomp, MOUTH_X - 150 * k, 1.1 + 0.35 * ease(k), shake)
        elif t < 5.3:
            k = ease((t - 4.8) / 0.5)
            cx = MOUTH_X - 150 + (AV_X - MOUTH_X + 150) * k
            frames = [crop_at(chomp, cx + dx, 1.45 - 0.35 * k) for dx in (-100, 0, 100)]
            frame = Image.blend(Image.blend(frames[0], frames[1], 0.5), frames[2], 0.33)
        elif t < 7.4:
            frame = crop_at(chomp, AV_X, 1.1 + 0.05 * (t - 5.3))
        else:
            frame = crop_at(star, 2600, 1.0).filter(ImageFilter.GaussianBlur(10))
            frame = Image.blend(frame, Image.new("RGB", frame.size, (10, 20, 60)), 0.35)
        frame = frame.convert("RGBA")

        if t < 2.0:
            paste_center(frame, pov, FW / 2, 170, pop(t, 0.1))
            paste_center(frame, secret, FW / 2, 340, pop(t, 0.35), angle=-4)
            paste_center(frame, money, FW / 2, 490, pop(t, 0.9), angle=-4)
        elif 2.6 <= t < 4.8:
            paste_center(frame, run, FW / 2, 330, pop(t, 2.7, 0.25) * (1 + 0.05 * math.sin(t * 20)), angle=-6)
        elif 5.3 <= t < 7.4:
            paste_center(frame, worth, FW / 2, 250, pop(t, 5.4), angle=-4)
            paste_center(frame, money, FW / 2, 420, pop(t, 5.8), angle=-4)
            paste_center(frame, comment, FW / 2, 1650, pop(t, 6.3))
        elif t >= 7.4:
            paste_center(frame, event, FW / 2, 420, pop(t, 7.5))
            paste_center(frame, title_a, FW / 2, 820, pop(t, 7.7), angle=-3)
            paste_center(frame, title_b, FW / 2, 980, pop(t, 7.85), angle=-3)
            paste_center(frame, search, FW / 2, 1500, pop(t, 8.3))
        writer.send(frame.convert("RGB").tobytes())
        if i % 60 == 0:
            print(f"  {t:.1f}s")
    writer.close()
    print("ok", out)

    # Kendi oynanış kaydına konacak şeffaf yazılar (CapCut'ta üst katman)
    od = os.path.join(OUTDIR, "overlays")
    os.makedirs(od, exist_ok=True)
    for name, parts in (
        ("1_pov_secret", [(pov, 170), (secret, 340), (money, 490)]),
        ("2_run", [(run, 330)]),
        ("3_worth_it", [(worth, 250), (money, 420), (comment, 1650)]),
        ("4_end_card", [(event, 420), (title_a, 820), (title_b, 980), (search, 1500)]),
        ("5_sus", [(txt("SUS...", 200, fill=(255, 255, 255), stroke=(20, 60, 120)), 330),
                   (txt("GOLDEN", 170, fill=T.gold_fill(), stroke=(110, 60, 0)), 540)]),
    ):
        im = Image.new("RGBA", (FW, FH), (0, 0, 0, 0))
        for img, y in parts:
            paste_center(im, img, FW / 2, y, 1.0, angle=-3)
        im.save(os.path.join(od, name + ".png"))
    print("ok overlays")


if __name__ == "__main__":
    main()
