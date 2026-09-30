"""
TikTok düzenleyici: yapay zeka sesi + altyazı + oynanış kaydı -> 9:16 video.

    python tools/tiktok_voice.py     # önce ses (tiktok/voice/)
    python tools/tiktok_edit.py      # -> tiktok/steal_story_16plus.mp4

Her çekim tiktok/voice/lines.json'daki bir satır. Çekimin görüntüsü:
  tiktok/raw/<ad>.mp4 / .mov varsa  -> senin oynanış kaydın (baştan, gerekirse döngü;
                                        başlangıç saniyesi tiktok/raw/offsets.json'da)
  yoksa                              -> çizimlerden hareketli sahne (thumbnails_v2)
Böylece video hep çıkıyor; kayıtları ekleyip yeniden çalıştırınca gerçek oynanışlı olur.

Stil eski TikTok'larla aynı: ortada kalın beyaz altyazı, vurgulu kelime renkli,
her çekim başında hafif yakınlaşma "vuruşu", sonda STEAL A CREWMATE kartı.
"""

import json
import math
import os
import subprocess
import sys

from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import imageio_ffmpeg  # noqa: E402
import thumbnails as T  # noqa: E402
import thumbnails_v2 as V  # noqa: E402

ROOT = T.ROOT
TT = os.path.join(ROOT, "tiktok")
RAW = os.path.join(TT, "raw")
VOICE = os.path.join(TT, "voice")
OUT = os.path.join(TT, "steal_story_16plus.mp4")
FW, FH, FPS = 1080, 1920, 30
GAP = 0.18        # satırlar arası nefes
END_HOLD = 1.4    # bitiş kartı sesten sonra ekranda kalsın

FILLS = {
    "red": lambda: (255, 70, 80),
    "cyan": lambda: (110, 225, 255),
    "yellow": lambda: (255, 222, 60),
    "rainbow": T.rainbow_fill,
}


# ─── Yardımcılar ─────────────────────────────────────────────────────────


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def pop(t, start, dur=0.22):
    k = (t - start) / dur
    if k <= 0:
        return 0.0
    if k >= 1:
        return 1.0
    return 1.18 * math.sin(k * math.pi / 2) if k < 0.7 else 1.18 - (k - 0.7) / 0.3 * 0.18


def paste_center(frame, img, cx, cy, scale=1.0):
    if scale <= 0.01:
        return
    im = img if scale == 1.0 else img.resize((max(1, int(img.width * scale)), max(1, int(img.height * scale))), Image.BILINEAR)
    frame.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))


def crop(scene, cx, cy, zoom, shake=(0, 0)):
    """16:9 4K sahneden 9:16 pencere (merkez, yakınlaşma: 1 = tam yükseklik)."""
    h = scene.height / zoom
    w = h * FW / FH
    x0 = min(max(0, cx - w / 2 + shake[0]), scene.width - w)
    y0 = min(max(0, cy - h / 2 + shake[1]), scene.height - h)
    return scene.crop((int(x0), int(y0), int(x0 + w), int(y0 + h))).resize((FW, FH), Image.BILINEAR)


def caption_img(text, key, color, size=112, max_w=1000):
    """Eski TikTok stili: kalın beyaz, siyah kontur; vurgulu kelime(ler) renkli. İki satıra dengeli bölünür."""
    if not text:
        return None
    words = text.split()
    keys = key.split() if key else []
    imgs = []
    i = 0
    while i < len(words):
        if keys and words[i:i + len(keys)] == keys:
            w = " ".join(keys)
            fill = FILLS[color]()
            imgs.append(trim(T.text_art(w, size * 1.12, fill=fill, stroke=(15, 12, 22), sw=0.12, extrude=0.06)))
            i += len(keys)
        else:
            imgs.append(trim(T.text_art(words[i], size, fill=(255, 255, 255), stroke=(15, 12, 22), sw=0.12, extrude=0.06)))
            i += 1
    space = size * 0.22
    total = sum(im.width for im in imgs) + space * (len(imgs) - 1)
    # dengeli iki satır (tek satır sığıyorsa tek)
    lines = [imgs]
    if total > max_w:
        best, best_diff = 1, 1e9
        for cut in range(1, len(imgs)):
            a = sum(im.width for im in imgs[:cut]) + space * (cut - 1)
            b = sum(im.width for im in imgs[cut:]) + space * (len(imgs) - cut - 1)
            if max(a, b) < best_diff:
                best, best_diff = cut, max(a, b)
        lines = [imgs[:best], imgs[best:]]
    lw = [sum(im.width for im in ln) + space * (len(ln) - 1) for ln in lines]
    lh = [max(im.height for im in ln) for ln in lines]
    W_ = int(max(lw)) + 10
    H_ = int(sum(lh) + size * 0.08 * (len(lines) - 1)) + 10
    canvas = Image.new("RGBA", (W_, H_), (0, 0, 0, 0))
    y = 0
    for ln, w, h in zip(lines, lw, lh):
        x = (W_ - w) / 2
        for im in ln:
            canvas.alpha_composite(im, (int(x), int(y + (h - im.height) / 2)))
            x += im.width + space
        y += h + size * 0.08
    if canvas.width > max_w:
        k = max_w / canvas.width
        canvas = canvas.resize((int(canvas.width * k), int(canvas.height * k)), Image.LANCZOS)
    return canvas


def trim(im):
    """Yazı görselinin boş kenarlarını at (kelime aralığı doğru ölçülsün)."""
    box = im.getchannel("A").getbbox()
    return im.crop(box) if box else im


# ─── Kayıt okuma ─────────────────────────────────────────────────────────


def raw_path(name):
    for ext in (".mp4", ".mov", ".MP4", ".MOV"):
        p = os.path.join(RAW, name + ext)
        if os.path.exists(p):
            return p
    return None


class RawClip:
    """Oynanış kaydından kareler: 9:16'yı dolduracak şekilde ölçekle + kırp."""

    def __init__(self, path, start):
        self.path, self.start = path, start
        self.gen = None
        self._open()

    def _open(self):
        self.gen = imageio_ffmpeg.read_frames(self.path, output_params=["-ss", str(self.start)] if False else None,
                                              input_params=["-ss", str(self.start)])
        meta = next(self.gen)
        self.size = meta["size"]
        self.fps = meta.get("fps") or 30
        self.t = 0.0
        self.last = None

    def frame_at(self, t):
        # kaydı FPS'ye göre ilerlet (kaynak fps farklı olabilir)
        while self.last is None or self.t < t:
            try:
                data = next(self.gen)
            except StopIteration:
                self._open()   # bitti: başa sar
                data = next(self.gen)
            self.last = Image.frombytes("RGB", self.size, data)
            self.t += 1 / self.fps
        im = self.last
        k = max(FW / im.width, FH / im.height)
        im = im.resize((int(im.width * k + 1), int(im.height * k + 1)), Image.BILINEAR)
        x0, y0 = (im.width - FW) // 2, (im.height - FH) // 2
        return im.crop((x0, y0, x0 + FW, y0 + FH))


# ─── Çizim yedekleri (kayıt yoksa) ───────────────────────────────────────


_scenes = {}


def scene(key):
    if key not in _scenes:
        print("  sahne çiziliyor:", key)
        _scenes[key] = {
            "chomp": lambda: V.scene_chomp("smug", "none"),
            "planets": lambda: V.scene_planets(False),
            "starfall": lambda: V.scene_starfall(False),
            "kraken": lambda: V.scene_kraken(""),
        }[key]().convert("RGB")
    return _scenes[key]


def art_frame(name, t, dur):
    k = t / max(dur, 0.01)
    if name == "hook":       # canavarın gözleri, yavaş yakınlaşma
        return crop(scene("chomp"), 1150, 1080, 1.35 + 0.25 * k)
    if name == "fly":        # gezegenlerin üstünden süzül
        return crop(scene("planets"), 700 + 2000 * ease(k), 1080, 1.15)
    if name == "grab":       # gökkuşağı mürettebat
        return crop(scene("chomp"), 3000, 1250, 1.25 + 0.2 * k)
    if name == "chase":      # ağız + sarsıntı
        amp = 34 * (1 - k) + 10
        return crop(scene("chomp"), 1500, 1250, 1.45 + 0.2 * k, (math.sin(t * 61) * amp, math.cos(t * 47) * amp))
    if name == "escape":     # dev gezegende zafer
        return crop(scene("planets"), 3350, 1080, 1.1 + 0.15 * k)
    if name == "event":      # yıldız yağmuru
        return crop(scene("starfall"), 1500 + 1100 * ease(k), 1080, 1.05)
    if name == "ask":        # canavar ve sen, geri çekilen kamera
        return crop(scene("chomp"), 2300, 1080, 1.25 - 0.2 * k)
    bg = crop(scene("starfall"), 2600, 1080, 1.0).filter(ImageFilter.GaussianBlur(10))
    return Image.blend(bg, Image.new("RGB", bg.size, (10, 20, 60)), 0.35)


# ─── Ses ────────────────────────────────────────────────────────────────


def build_audio(lines, durs):
    """Satırları çekim sürelerine göre sessizlikle doldurup tek parça yap."""
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    tmp = os.path.join(TT, "_audio")
    os.makedirs(tmp, exist_ok=True)
    listfile = os.path.join(tmp, "list.txt")
    with open(listfile, "w", encoding="utf-8") as lf:
        for i, (ln, d) in enumerate(zip(lines, durs)):
            out = os.path.join(tmp, f"p{i:02d}.wav")
            subprocess.run([ff, "-y", "-loglevel", "error", "-i", os.path.join(VOICE, ln["file"]),
                            "-af", f"apad=whole_dur={d:.3f},atrim=0:{d:.3f}", "-ar", "48000", "-ac", "2", out], check=True)
            lf.write(f"file '{out}'\n")
    full = os.path.join(tmp, "voice.wav")
    subprocess.run([ff, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", listfile, "-c", "copy", full], check=True)
    return full


# ─── Ana akış ───────────────────────────────────────────────────────────


def main():
    with open(os.path.join(VOICE, "lines.json"), encoding="utf-8") as f:
        lines = json.load(f)["lines"]
    offsets = {}
    op = os.path.join(RAW, "offsets.json")
    if os.path.exists(op):
        with open(op, encoding="utf-8") as f:
            offsets = json.load(f)
    durs = [ln["seconds"] + GAP + (END_HOLD if ln["name"] == "end" else 0) for ln in lines]
    audio = build_audio(lines, durs)

    caps = [caption_img(ln["caption"], ln["key"], ln["color"]) for ln in lines]
    title_a = T.text_art("STEAL A", 110, fill=(255, 255, 255), stroke=(200, 30, 50))
    title_b = T.text_art("CREWMATE", 148, fill=(255, 255, 255))
    event = V_pill("NEW EVENT: STARFALL", 64)
    search = T.text_art("search it on Roblox", 70, fill=(255, 235, 120), stroke=(60, 40, 0), sw=0.1)
    # Oyundaki TIKTOK kodu (Config.Codes): girişe sebep + TikTok'tan gelenleri sayma
    code = V_pill("CODE: TIKTOK = FREE EGG", 58)

    tmpv = os.path.join(TT, "_audio", "video.mp4")
    writer = imageio_ffmpeg.write_frames(tmpv, (FW, FH), fps=FPS, codec="libx264", quality=8, pix_fmt_out="yuv420p",
                                         macro_block_size=8)
    writer.send(None)
    used = []
    for ln, d, cap in zip(lines, durs, caps):
        name = ln["name"]
        src = raw_path(name) if name != "end" else None
        clip = RawClip(src, float(offsets.get(name, 0))) if src else None
        used.append(f"{name}: {'KAYIT ' + os.path.basename(src) if src else 'çizim'}")
        for i in range(int(round(d * FPS))):
            t = i / FPS
            base = clip.frame_at(t) if clip else art_frame(name, t, d)
            # çekim başında yakınlaşma vuruşu
            z = 1 + 0.10 * max(0.0, 1 - t / 0.25)
            if z > 1.001:
                w, h = int(FW * z), int(FH * z)
                base = base.resize((w, h), Image.BILINEAR).crop(((w - FW) // 2, (h - FH) // 2, (w - FW) // 2 + FW, (h - FH) // 2 + FH))
            frame = base.convert("RGBA")
            if name == "end":
                paste_center(frame, event, FW / 2, 420, pop(t, 0.05))
                paste_center(frame, title_a, FW / 2, 820, pop(t, 0.2))
                paste_center(frame, title_b, FW / 2, 980, pop(t, 0.35))
                paste_center(frame, search, FW / 2, 1330, pop(t, 0.8))
                paste_center(frame, code, FW / 2, 1470, pop(t, 1.1))
            elif cap is not None:
                paste_center(frame, cap, FW / 2, 470, pop(t, 0.02))
            writer.send(frame.convert("RGB").tobytes())
        print(" ", used[-1])
    writer.close()

    ff = imageio_ffmpeg.get_ffmpeg_exe()
    subprocess.run([ff, "-y", "-loglevel", "error", "-i", tmpv, "-i", audio, "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
                    "-shortest", "-movflags", "+faststart", OUT], check=True)
    print("ok", OUT, f"{sum(durs):.1f}s")


def V_pill(s, size):
    t = T.text_art(s, size, fill=(255, 255, 255), stroke=(0, 0, 0), sw=0.05, extrude=0.0, gloss=False)
    pw, ph = t.width + size * 0.8, t.height + size * 0.35
    im = Image.new("RGBA", (int(pw + 16), int(ph + 16)), (0, 0, 0, 0))
    from PIL import ImageDraw
    ImageDraw.Draw(im).rounded_rectangle((8, 8, pw + 8, ph + 8), radius=ph / 2, fill=(12, 12, 16, 235), outline=(255, 255, 255, 255), width=5)
    im.alpha_composite(t, (int((im.width - t.width) / 2), int((im.height - t.height) / 2)))
    return im


if __name__ == "__main__":
    main()
