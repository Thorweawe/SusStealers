"""
Roblox reklam görselleri (Ads Manager): kapak görsellerinin üstüne oyun
logosu ("STEAL A / CREWMATE") ve yeşil "PLAY NOW!" düğmesi.

    python tools/ad_art.py   ->  ads/ad_16x9_<kapak>.png  (1920x1080)
                                 ads/ad_1x1_<kapak>.png   (1080x1080)
                                 ads/_preview.png

Kaynak: thumbnails/live_thumb_*.png — oyun sayfasına YÜKLENEN kapaklar
(sarı kafalı sürüm). Kare sürümde kapak kırpılmıyor (yazıları kesiyordu):
bulanık zemin üstünde tamamı, altında logo ve düğme.
Gerekenler: pip install pillow
"""

import glob
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "thumbnails")
DEST = os.path.join(ROOT, "ads")
FONT = "C:/Windows/Fonts/ariblk.ttf"
OUT = (20, 18, 30)
S = 2  # 2 kat büyük çizilip küçültülüyor

# Kare kırpmada karakterin olduğu taraf (kapak adı -> 0 sol .. 1 sağ)
SQUARE_FOCUS = {"thumb_1_chase": 0.62, "thumb_2_sleep": 0.2, "thumb_3_frost": 0.75, "thumb_4_lift": 0.8}


def font(size):
    return ImageFont.truetype(FONT, int(size * S))


def shadow_layer(size, draw_fn, blur):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer))
    return layer.filter(ImageFilter.GaussianBlur(blur * S))


def logo(canvas, cx, top, scale):
    """ "STEAL A" kırmızı hap + beyaz "CREWMATE" (başlık ekranındaki gibi). """
    w, h = canvas.size
    d = ImageDraw.Draw(canvas)
    pill_font = font(46 * scale)
    main_font = font(120 * scale)
    pill_text = "STEAL A"
    pw = d.textlength(pill_text, font=pill_font) + 70 * scale * S
    ph = 78 * scale * S
    px0, py0 = cx - pw / 2, top
    # Gölge
    sh = shadow_layer(canvas.size, lambda sd: (
        sd.rounded_rectangle([px0, py0 + 10 * S, px0 + pw, py0 + ph + 10 * S], radius=18 * S, fill=(0, 0, 0, 140)),
        sd.text((cx, py0 + ph + 70 * scale * S + 12 * S), "CREWMATE", font=main_font, anchor="mm", fill=(0, 0, 0, 160),
                stroke_width=int(14 * scale * S), stroke_fill=(0, 0, 0, 160))), 8)
    canvas.alpha_composite(sh)
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle([px0, py0, px0 + pw, py0 + ph], radius=18 * S, fill=(214, 46, 58), outline=(255, 255, 255), width=int(6 * S))
    d.text((cx, py0 + ph / 2), pill_text, font=pill_font, anchor="mm", fill=(255, 255, 255),
           stroke_width=int(5 * scale * S), stroke_fill=(150, 20, 30))
    d.text((cx, py0 + ph + 70 * scale * S), "CREWMATE", font=main_font, anchor="mm", fill=(236, 242, 255),
           stroke_width=int(12 * scale * S), stroke_fill=OUT)


def play_button(canvas, cx, cy, scale):
    d = ImageDraw.Draw(canvas)
    f = font(64 * scale)
    text = "PLAY NOW!"
    tw = d.textlength(text, font=f)
    bw, bh = tw + 190 * scale * S, 130 * scale * S
    x0, y0 = cx - bw / 2, cy - bh / 2
    sh = shadow_layer(canvas.size, lambda sd: sd.rounded_rectangle(
        [x0, y0 + 14 * S, x0 + bw, y0 + bh + 14 * S], radius=34 * S, fill=(0, 0, 0, 150)), 8)
    canvas.alpha_composite(sh)
    d = ImageDraw.Draw(canvas)
    # Alt gölge (tıknaz düğme) + gövde + parlama
    d.rounded_rectangle([x0, y0 + 10 * S, x0 + bw, y0 + bh + 10 * S], radius=34 * S, fill=(40, 120, 30), outline=OUT, width=int(8 * S))
    d.rounded_rectangle([x0, y0, x0 + bw, y0 + bh], radius=34 * S, fill=(88, 226, 60), outline=OUT, width=int(8 * S))
    d.rounded_rectangle([x0 + 22 * S, y0 + 16 * S, x0 + bw - 22 * S, y0 + bh * 0.42], radius=20 * S, fill=(160, 250, 130))
    # Oynat üçgeni
    tx = x0 + 70 * scale * S
    ts = 38 * scale * S
    d.polygon([(tx - ts * 0.6, cy - ts), (tx - ts * 0.6, cy + ts), (tx + ts, cy)], fill=(255, 255, 255), outline=OUT, width=int(6 * S))
    d.text((cx + 50 * scale * S, cy + 4 * S), text, font=f, anchor="mm", fill=(255, 255, 255),
           stroke_width=int(9 * scale * S), stroke_fill=OUT)


def free_badge(canvas, cx, cy, scale):
    d = ImageDraw.Draw(canvas)
    r = 92 * scale * S
    pts = []
    import math
    for i in range(24):
        a = i * math.pi / 12
        rr = r if i % 2 == 0 else r * 0.82
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=(255, 210, 40), outline=OUT, width=int(7 * S))
    d.text((cx, cy - 16 * scale * S), "FREE", font=font(42 * scale), anchor="mm", fill=(255, 255, 255),
           stroke_width=int(6 * scale * S), stroke_fill=OUT)
    d.text((cx, cy + 30 * scale * S), "TO PLAY", font=font(24 * scale), anchor="mm", fill=(255, 255, 255),
           stroke_width=int(5 * scale * S), stroke_fill=OUT)


def make_wide(src):
    base = Image.open(src).convert("RGBA").resize((1920 * S, 1080 * S), Image.LANCZOS)
    # Alt kenarda koyu geçiş: yazılar okunsun
    grad = Image.new("L", (1, 256))
    for y in range(256):
        grad.putpixel((0, y), int(max(0, (y - 120) / 136) * 170))
    shade = Image.new("RGBA", base.size, (10, 10, 20, 255))
    shade.putalpha(grad.resize(base.size))
    base.alpha_composite(shade)
    logo(base, 520 * S, 700 * S, 0.95)
    play_button(base, 1420 * S, 960 * S, 1.0)
    return base.resize((1920, 1080), Image.LANCZOS).convert("RGB")


def make_square(src, focus):
    full = Image.open(src).convert("RGBA")
    side = 1080 * S
    # Zemin: kapağın büyütülmüş, bulanık ve koyulaşmış hâli
    bg = full.resize((int(side * 16 / 9), side), Image.LANCZOS)
    left = (bg.width - side) // 2
    bg = bg.crop((left, 0, left + side, side)).filter(ImageFilter.GaussianBlur(28 * S))
    bg.alpha_composite(Image.new("RGBA", bg.size, (10, 10, 24, 110)))
    # Kapağın tamamı üstte, kenarlı kart gibi
    w = side - 60 * S
    h = int(w * 9 / 16)
    card = full.resize((w, h), Image.LANCZOS)
    x0, y0 = 30 * S, 36 * S
    sh = shadow_layer(bg.size, lambda sd: sd.rounded_rectangle(
        [x0, y0 + 14 * S, x0 + w, y0 + h + 14 * S], radius=30 * S, fill=(0, 0, 0, 170)), 10)
    bg.alpha_composite(sh)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=30 * S, fill=255)
    bg.paste(card, (x0, y0), mask)
    ImageDraw.Draw(bg).rounded_rectangle([x0, y0, x0 + w, y0 + h], radius=30 * S, outline=(255, 255, 255), width=int(6 * S))
    logo(bg, 540 * S, y0 + h + 40 * S, 0.9)
    play_button(bg, 540 * S, 960 * S, 0.95)
    return bg.resize((1080, 1080), Image.LANCZOS).convert("RGB")


def main():
    os.makedirs(DEST, exist_ok=True)
    wides, squares = [], []
    for src in sorted(glob.glob(os.path.join(SRC, "live_thumb_*.png"))):
        name = os.path.splitext(os.path.basename(src))[0].replace("live_", "")
        wide = make_wide(src)
        wide.save(os.path.join(DEST, f"ad_16x9_{name}.png"), optimize=True)
        square = make_square(src, SQUARE_FOCUS.get(name, 0.5))
        square.save(os.path.join(DEST, f"ad_1x1_{name}.png"), optimize=True)
        wides.append(wide)
        squares.append(square)
        print(name)
    # Önizleme: üstte yataylar, altta kareler
    sheet = Image.new("RGB", (4 * 480 + 50, 270 + 20 + 360 + 30), (30, 30, 36))
    for i, im in enumerate(wides):
        sheet.paste(im.resize((480, 270)), (10 + i * 490, 10))
    for i, im in enumerate(squares):
        sheet.paste(im.resize((360, 360)), (10 + i * 490, 300))
    sheet.save(os.path.join(DEST, "_preview.png"))


if __name__ == "__main__":
    main()
