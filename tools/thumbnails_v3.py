"""
Kapaklar — 3. set (2026-10-01): popüler oyunların kapaklarından ALINAN DERSLER
bizim temaya uyarlandı (kopya değil).

    python tools/thumbnails_v3.py        ->  thumbnails/v3/*.png + ads/v3/*.png + _preview.png

Referanslar ve aldığımız şey:
  Ride A Pet (bizimle aynı tür)   -> yaratık kadrajı dolduruyor ve kenardan taşıyor, dinamik
                                     açı + hız çizgileri, abartılı yüz, sol üstte üst üste
                                     "AD / 1 in X / $/s", çapraz beyaz çizgili önce/sonra bölme
  +1 Speed Keyboard Escape        -> mekanik tek bakışta; etrafta uçuşan "+1" -> bizde "+$"
  Forsaken (16+ kitle)            -> sinematik ışık, kenar ışığı, karakter dizisi ızgarası
  Slayers 2                       -> köşe "NEW" şeridi (Starfall'da var)
Sayılar oyundan (Config): Rift Stalker'da SECRET %2 = "1 in 50"; The Crewmate $40.6M/s.
"""

import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import thumbnails as T  # noqa: E402
import thumbnails_v2 as V  # noqa: E402
from thumbnails import (  # noqa: E402
    OUT, W, H, Sprite, aura, avatar, crewmate, ell, gold_fill, ground_shadow, mask, money_fill, place, poly,
    put_text, rainbow_fill, rainbow_tex, rrect, seg, solid, sparkle, speed_lines, text_art, vgrad, vignette,
    dim, lit,
)

DEST = os.path.join(T.ROOT, "thumbnails", "v3")
ADS = os.path.join(T.ROOT, "ads", "v3")


# ─── Rift Stalker (oyundaki 5. canavar; SECRET %2) ──────────────────────


def rift_stalker(h, awake=True):
    """Sağa bakan solgun dev örümcek: uzun eklemli bacaklar, camgöbeği parlayan benekler ve gözler."""
    sw, sh = int(h * 2.3), int(h * 1.6)
    s = Sprite(sw, sh, max(6, h * 0.014))
    cx, cy = h * 1.0, h * 0.72
    ground = cy + h * 0.82
    pale, joint, glow = (232, 238, 244), (88, 94, 108), (80, 230, 255)

    def leg(hip, knee, foot, back):
        """Organik, incelen kavisli bacak: kalçadan dizine kalın, dizden ayağa sivri."""
        col = dim(pale, 0.25) if back else pale
        m = s.m()
        pts = T.bezier(hip, (hip[0] + (knee[0] - hip[0]) * 0.4, knee[1] - h * 0.05), knee, knee, 160)
        pts += T.bezier(knee, (knee[0] + (foot[0] - knee[0]) * 0.55, knee[1] + (foot[1] - knee[1]) * 0.2), foot, foot, 200)[1:]
        n = len(pts)
        for i, (x, y) in enumerate(pts):
            rr = h * (0.042 - 0.034 * i / n) * (0.85 if back else 1.0)
            ell(m, (x - rr, y - rr, x + rr, y + rr))
        s.put(T.rounded(m, h * 0.006), col, light=(0.3, 0.1), hi=0.45, lo=0.5)
        # diz çıkıntısı ve koyu uç
        r = h * 0.034
        s.put(ell(s.m(), (knee[0] - r, knee[1] - r, knee[0] + r, knee[1] + r)), dim(col, 0.15), light=(0.3, 0.2), hi=0.5)
        tip = s.m()
        for x, y in pts[-40:]:
            rr = h * 0.012
            ell(tip, (x - rr, y - rr, x + rr, y + rr))
        s.put(tip, joint, ow=0, flat=True)

    hipx, hipy = cx + h * 0.18, cy + h * 0.02
    spreads = [(-1.0, -0.5), (-0.5, -0.62), (0.3, -0.62), (0.9, -0.5)]
    # arka bacaklar (koyu), sonra gövde, sonra ön bacaklar
    for k, (fx, ky) in enumerate(spreads):
        leg((hipx - h * 0.05 + k * h * 0.04, hipy - h * 0.03), (hipx + fx * h * 0.55, cy + ky * h), (hipx + fx * h * 1.05 + h * 0.1, ground - h * 0.06), True)
    # karın
    ab = ell(s.m(), (cx - h * 0.7, cy - h * 0.3, cx - h * 0.02, cy + h * 0.26))
    s.put(ab, pale, light=(0.3, 0.2), hi=0.5, lo=0.4)
    rng = random.Random(3)
    spots = s.m()
    for _ in range(9):
        x, y, r = cx - h * rng.uniform(0.75, 0.15), cy + h * rng.uniform(-0.28, 0.2), h * rng.uniform(0.025, 0.05)
        ell(spots, (x - r, y - r, x + r, y + r))
    from PIL import ImageChops
    spots = ImageChops.multiply(spots, ab)
    s.img.alpha_composite(solid(s.size, glow, spots.filter(ImageFilter.GaussianBlur(h * 0.02))))
    s.put(spots, lit(glow, 0.4), ow=0, flat=True)
    # göğüs + kafa
    s.put(ell(s.m(), (cx - h * 0.05, cy - h * 0.18, cx + h * 0.45, cy + h * 0.2)), pale, light=(0.3, 0.2), hi=0.45)
    hx_, hy_, hr = cx + h * 0.58, cy + h * 0.0, h * 0.23
    head = ell(s.m(), (hx_ - hr, hy_ - hr, hx_ + hr, hy_ + hr))
    s.put(head, pale, light=(0.3, 0.2), hi=0.45)
    # dişler
    for dy_ in (-0.05, 0.05):
        s.put(poly(s.m(), [(hx_ + hr * 0.7, hy_ + dy_ * h), (hx_ + hr * 1.5, hy_ + dy_ * h + h * 0.06), (hx_ + hr * 0.9, hy_ + dy_ * h + h * 0.1)]),
              (60, 64, 76), light=(0.3, 0.1))
    # gözler: altılı küme, uyanıksa parlıyor
    eye_col = glow if awake else (120, 140, 160)
    eyes = s.m()
    for ex, ey_, er in ((0.3, -0.38, 0.3), (0.66, -0.3, 0.26), (0.12, -0.02, 0.2), (0.5, 0.02, 0.24), (0.8, 0.1, 0.17), (0.34, 0.34, 0.16)):
        x, y, r = hx_ + ex * hr, hy_ + ey_ * hr, er * hr
        ell(eyes, (x - r, y - r, x + r, y + r))
    if awake:
        s.img.alpha_composite(solid(s.size, glow, eyes.filter(ImageFilter.GaussianBlur(h * 0.05))))
        s.img.alpha_composite(solid(s.size, glow, eyes.filter(ImageFilter.GaussianBlur(h * 0.015))))
    s.put(eyes, eye_col, ow=s.ow * 0.5, light=(0.4, 0.3), hi=0.7)
    for k, (fx, ky) in enumerate(spreads):
        leg((hipx + h * 0.08 + k * h * 0.04, hipy + h * 0.04), (hipx + fx * h * 0.5 + h * 0.15, cy + ky * h * 0.85), (hipx + fx * h * 0.95 + h * 0.3, ground), False)
    return s.img, {"feet": (cx, ground), "head": (hx_, hy_), "top": (cx, cy - h * 0.75)}


# ─── Yardımcılar ─────────────────────────────────────────────────────────


def money_pops(canvas, center, texts, seed=1, spread=(600, 420)):
    """Keyboard Escape'in "+1"leri gibi: çalınanın etrafında uçuşan "+$" sayıları."""
    rng = random.Random(seed)
    for i, t in enumerate(texts):
        a = -math.pi * 0.9 + i * (math.pi * 1.8 / max(1, len(texts) - 1))
        x = center[0] + math.cos(a) * spread[0] * rng.uniform(0.85, 1.1)
        y = center[1] + math.sin(a) * spread[1] * rng.uniform(0.85, 1.1) - 120
        put_text(canvas, t, (x, y), rng.choice([95, 110, 125]), angle=rng.uniform(-14, 14), fill=money_fill(), stroke=(10, 70, 20))


def depth_blur(canvas, r=5):
    return canvas.filter(ImageFilter.GaussianBlur(r))


def stack_title(canvas, x, y, lines):
    """Ride A Pet'in sol üst yığını: ad / 1 in X / $/s — sola hizalı gibi dursun diye merkezleri kaydır."""
    for txt, size, kw in lines:
        img = text_art(txt, size, **kw)
        place(canvas, img, (0, img.height / 2), (x, y + img.height / 2), angle=-4)
        y += img.height * 0.78


# ─── Sahneler ────────────────────────────────────────────────────────────


def scene_rift():
    """Rift Stalker arkadan uzanıyor, sen SECRET'le kameraya doğru kaçıyorsun (şok!)."""
    c = V.space_bg((70, 30, 120), (255, 130, 60), [(700, 400, 800, (255, 90, 120), 120), (3200, 500, 700, (255, 180, 80), 120),
                                                  (2800, 900, 900, (255, 240, 200), 110)], (2800, 900), glow=(255, 245, 210), glow_r=1100, seed=41)
    V.planet_ground(c, 1650, (255, 175, 95), (160, 65, 45), seed=9)
    c = depth_blur(c, 6)
    speed_lines(c, (2800, 950), 70, seed=6, alpha=120)
    mon, mi = rift_stalker(1350, awake=True)
    ground_shadow(c, 1250, 2020, 1100, 120)
    place(c, mon, mi["feet"], (1150, 2100), angle=-4, rim=((255, 240, 220), 12))
    held = crewmate(900, (255, 255, 255), tex=rainbow_tex((1000, 1000)), face=1)
    av, ai = avatar(290, "run", "shock", held=held, look=1)
    ground_shadow(c, 2900, 2120, 640, 90)
    ta = place(c, av, ai["feet"], (2900, 2250), angle=-5, rim=((255, 255, 255), 12), under=aura(c, ai, (255, 250, 190), k=1.25, alpha=235))
    hc = ta(ai["held"])
    for dx, dy, r in ((-560, -380, 85), (520, -360, 70), (560, 260, 55), (-520, 300, 50)):
        sparkle(c, hc[0] + dx, hc[1] + dy, r, (255, 240, 140))
    money_pops(c, (hc[0] + 60, hc[1]), ["+$40M", "+$40M", "+$40M"], seed=4, spread=(700, 520))
    stack_title(c, 120, 60, [
        ("THE CREWMATE", 200, {"fill": rainbow_fill()}),
        ("1 in 50", 260, {"fill": (255, 255, 255), "stroke": (200, 20, 50)}),
        ("$40.6M/s", 220, {"fill": money_fill(), "stroke": (10, 70, 20)}),
    ])
    vignette(c, 55)
    return c


def scene_split():
    """Önce/sonra (Ride A Pet'in yumurta->ejderha bölmesi): uyuyan canavarın SECRET'i -> senin servetin."""
    # SOL: gece, uyuyan Rift Stalker, yerde parlayan SECRET
    left = V.space_bg((15, 25, 80), (70, 60, 170), [(900, 700, 800, (120, 80, 255), 120)], (1100, 1300), glow=(200, 180, 255), glow_r=700, seed=5)
    V.planet_ground(left, 1700, (120, 110, 210), (50, 40, 120), seed=3)
    mon, mi = rift_stalker(1150, awake=False)
    place(left, mon, mi["feet"], (1000, 1950), angle=0, rim=((190, 170, 255), 10))
    sec, si = crewmate(520, (255, 255, 255), tex=rainbow_tex((1000, 1000)), face=1)
    g = mask(W, H)
    ImageDraw.Draw(g).ellipse((1300, 1350, 2000, 2050), fill=220)
    left.alpha_composite(solid((W, H), (255, 250, 200), g.filter(ImageFilter.GaussianBlur(120))))
    place(left, sec, si["feet"], (1650, 2000), rim=((255, 255, 255), 10))
    T.zzz(left, 1500, 700, 200)
    put_text(left, "RIFT STALKER", (900, 250), 170, angle=-4, fill=(255, 90, 110), stroke=(60, 0, 20))
    put_text(left, "1 in 50", (900, 470), 200, angle=-4, fill=(255, 255, 255), stroke=(60, 20, 90))

    # SAĞ: altın patlama, sen SECRET'i kaldırıyorsun, para yağıyor
    right = T.bg_burst((255, 200, 50), (255, 130, 40), (3000, 950), rays=26, ray_alpha=45, glow=(255, 255, 220), glow_r=1000)
    V.planet_ground(right, 1760, (255, 215, 120), (220, 120, 50), seed=6)
    held = crewmate(760, (255, 255, 255), tex=rainbow_tex((1000, 1000)), face=-1)
    av, ai = avatar(200, "lift", "smug", held=held, look=-1)
    ta = place(right, av, ai["feet"], (3050, 2120), angle=3, rim=((255, 255, 255), 10), under=aura(right, ai, (255, 255, 200), k=1.3, alpha=240))
    hc = ta(ai["held"])
    money_pops(right, (hc[0], hc[1] + 200), ["+$40M", "+$40M", "+$40M", "+$40M"], seed=8, spread=(700, 520))
    put_text(right, "$40.6M/s", (3050, 240), 240, angle=-4, fill=money_fill(), stroke=(10, 70, 20))

    # çapraz beyaz ayraç
    m = mask(W, H)
    ImageDraw.Draw(m).polygon([(0, 0), (2150, 0), (1850, H), (0, H)], fill=255)
    out = right.copy()
    out.paste(left, (0, 0), m)
    d = ImageDraw.Draw(out)
    d.line([(2150, -20), (1850, H + 20)], fill=OUT, width=70)
    d.line([(2150, -20), (1850, H + 20)], fill=(255, 255, 255), width=46)
    vignette(out, 40)
    return out


def boss_panel(kind, pw, ph):
    """Tek boss yüzü, sinematik: koyu renkli zemin, kenar ışığı, yakın plan."""
    tones = {"chomp": ((90, 10, 50), (255, 80, 160)), "kraken": ((30, 10, 90), (170, 100, 255)),
             "rift": ((20, 40, 70), (90, 230, 255)), "imp": ((70, 5, 10), (255, 60, 60))}
    a, b = tones[kind]
    c = vgrad((W, H), [(0, dim(a, 0.3)), (1, a)]).convert("RGBA")
    g = mask(W, H)
    ImageDraw.Draw(g).ellipse((W / 2 - 1100, H / 2 - 900, W / 2 + 1100, H / 2 + 900), fill=200)
    c.alpha_composite(solid((W, H), b, g.filter(ImageFilter.GaussianBlur(500))))
    if kind == "chomp":
        img, info = V.chomper(760)
        place(c, img, info["feet"], (W / 2 - 60, H / 2 + 560), angle=-6, rim=(b, 16))
    elif kind == "kraken":
        img, info = V.kraken(700, sleepy=False)
        place(c, img, info["head"], (W / 2, H / 2 - 40), rim=(b, 16))
    elif kind == "rift":
        img, info = rift_stalker(900)
        place(c, img, info["head"], (W / 2 + 180, H / 2 - 40), rim=(b, 16))
    else:
        img, info = crewmate(900, (220, 20, 40), face=1, angry=True, mouth=True)
        place(c, img, info["feet"], (W / 2 - 40, H / 2 + 620), angle=-6, rim=(b, 16))
    vignette(c, 140)
    x0, y0 = (W - pw) / 2, (H - ph) / 2
    return c.crop((int(x0), int(y0), int(x0 + pw), int(y0 + ph)))


def scene_bosses():
    """Forsaken'ın karakter ızgarası gibi: dört boss yüzü, beyaz kalın çerçeveler, 16+ meydan okuma."""
    c = vgrad((W, H), [(0, (25, 5, 15)), (1, (70, 10, 25))]).convert("RGBA")
    pad, top, bottom = 70, 70, 560
    pw = int((W - pad * 5) / 4)
    ph = H - top - bottom
    for i, kind in enumerate(("chomp", "kraken", "rift", "imp")):
        panel = boss_panel(kind, pw, ph).convert("RGBA")
        x, y = pad + i * (pw + pad), top
        angle = (-2, 1.5, -1.5, 2)[i]
        frame = Image.new("RGBA", (pw + 40, ph + 40), (255, 255, 255, 255))
        frame.alpha_composite(panel, (20, 20))
        place(c, frame, (frame.width / 2, frame.height / 2), (x + pw / 2, y + ph / 2), angle=angle, shadow=110)
    put_text(c, "CAN YOU ROB THEM ALL?", (W / 2, H - 290), 230, angle=-2, fill=(255, 255, 255), stroke=(170, 10, 40))
    vignette(c, 60)
    return c


SCENES = [("8_rift", scene_rift), ("9_split", scene_split), ("10_bosses", scene_bosses)]


def main(only=None):
    os.makedirs(DEST, exist_ok=True)
    os.makedirs(ADS, exist_ok=True)
    import ad_art as A
    outs = []
    for name, fn in SCENES:
        if only and name.split("_", 1)[1] not in only:
            continue
        img = fn().convert("RGB").resize((1920, 1080), Image.LANCZOS)
        p = os.path.join(DEST, "thumb_" + name + ".png")
        img.save(p)
        A.make_wide(p).save(os.path.join(ADS, "ad_16x9_thumb_" + name + ".png"), optimize=True)
        A.make_square(p, 0.5).save(os.path.join(ADS, "ad_1x1_thumb_" + name + ".png"), optimize=True)
        outs.append(img)
        print("ok", name)
    if not only:
        prev = Image.new("RGB", (1920, 1080), (20, 20, 30))
        for i, im in enumerate(outs):
            prev.paste(im.resize((960, 540), Image.LANCZOS), ((i % 2) * 960, (i // 2) * 540))
        prev.save(os.path.join(DEST, "_preview.png"))


if __name__ == "__main__":
    main(sys.argv[1:])
