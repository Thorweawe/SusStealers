"""
TikTok seslendirmesi (yapay zeka sesi, Microsoft nöral: edge-tts).

    python tools/tiktok_voice.py   ->  tiktok/voice/line_XX.mp3 + tiktok/voice/lines.json (süreler)

Kitle 16+ (oyun şimdilik yalnızca 16+): çocuksu heyecan yerine kuru espri,
kısa cümleler, "ben yaptım" anlatısı (story time) ve sonda yorum sorusu.
Her satır bir çekim; tools/tiktok_edit.py satırları ve süreleri buradan okuyor.
"""

import asyncio
import json
import os
import subprocess

import edge_tts
import imageio_ffmpeg

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tiktok", "voice")
VOICE = "en-US-BrianNeural"   # rahat, doğal; 16+ için "reklam sesi" gibi değil
RATE = "+12%"                 # TikTok temposu

# (çekim adı, seslendirme, altyazı, vurgulu kelime, vurgu rengi)
LINES = [
    ("hook",    "They told me not to steal from the space monster.",  "they said DON'T steal from the space monster", "DON'T", "red"),
    ("fly",     "So obviously, I flew straight to its planet.",       "so obviously I flew straight to its PLANET", "PLANET", "cyan"),
    ("grab",    "Grabbed the rarest crewmate it had.",                "grabbed the RAREST crewmate it had", "RAREST", "rainbow"),
    ("chase",   "And yeah. It woke up.",                               "and yeah... it WOKE UP", "WOKE UP", "red"),
    ("escape",  "Made it back with half a second to spare.",         "made it back with HALF A SECOND to spare", "HALF A SECOND", "yellow"),
    ("event",   "And this week, stars are literally falling from the sky.", "this week stars are FALLING from the sky", "FALLING", "cyan"),
    ("ask",     "Would you risk it? Yes or no.",                       "would you RISK IT? yes or no", "RISK IT?", "yellow"),
    ("end",     "Steal a Crewmate. It's on Roblox.",                   "", "", ""),
]


def duration(path: str) -> float:
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    r = subprocess.run([ff, "-hide_banner", "-i", path], capture_output=True, text=True)
    for line in r.stderr.splitlines():
        if "Duration:" in line:
            h, m, s = line.split("Duration:")[1].split(",")[0].strip().split(":")
            return int(h) * 3600 + int(m) * 60 + float(s)
    return 0.0


async def main():
    os.makedirs(OUT, exist_ok=True)
    meta = []
    for i, (name, speech, caption, key, color) in enumerate(LINES, start=1):
        path = os.path.join(OUT, f"line_{i:02d}_{name}.mp3")
        await edge_tts.Communicate(speech, VOICE, rate=RATE).save(path)
        d = duration(path)
        meta.append({"name": name, "file": os.path.basename(path), "speech": speech, "caption": caption,
                     "key": key, "color": color, "seconds": round(d, 3)})
        print(f"ok {name}: {d:.2f}s")
    with open(os.path.join(OUT, "lines.json"), "w", encoding="utf-8") as f:
        json.dump({"voice": VOICE, "rate": RATE, "lines": meta}, f, indent=2)


if __name__ == "__main__":
    asyncio.run(main())
