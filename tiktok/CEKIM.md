# TikTok: 16+ hikâye videosu

Hazır video: `tiktok/steal_story_16plus.mp4` (9:16, ~23 sn, yapay zeka sesli).
Şu an çizimlerle; aşağıdaki kısa kayıtları çekip `tiktok/raw/` klasörüne
koyunca aynı ses ve altyazıyla **gerçek oynanışlı** sürümü çıkar:

```bash
python tools/tiktok_edit.py
```

Ses değişecekse önce `python tools/tiktok_voice.py` (metinler o dosyada).

## Çekim listesi (telefonda dikey ekran kaydı, sesli olabilir, altyazısız)

Her kayıt ~4-5 sn yeterli, video kendisi keser. Dosya adı tam böyle olsun:

| Dosya | Ses (Brian) | Ne çek |
|---|---|---|
| `hook.mp4` | "They told me not to steal from the space monster." | Uyuyan canavarın yakın plan görüntüsü (Chomper ya da Kraken) |
| `fly.mp4` | "So obviously, I flew straight to its planet." | Launch Bay'den uzaya çıkış, gezegene uçuş |
| `grab.mp4` | "Grabbed the rarest crewmate it had." | Nadir (tercihen SECRET / mutasyonlu) mürettebatı kapma anı |
| `chase.mp4` | "And yeah. It woke up." | Canavar uyanıp kovalıyor (en heyecanlı an) |
| `escape.mp4` | "Made it back with half a second to spare." | Gemiye kıl payı dönüş, CLOSE CALL / kaide |
| `event.mp4` | "And this week, stars are literally falling from the sky." | STARFALL SHOWER sırasında yıldız yakalama (Cuma'dan sonra çekilir) |
| `ask.mp4` | "Would you risk it? Yes or no." | Canavar ve sen tek karede, ya da çalınan mürettebat kaidede |

Bitiş kartı otomatik: NEW EVENT: STARFALL · STEAL A CREWMATE · search it on Roblox ·
CODE: TIKTOK = FREE EGG.

Kaydın iyi kısmı ortadaysa başlangıç saniyesini `tiktok/raw/offsets.json`'a yaz:
`{"chase": 2.5, "grab": 1.0}`

Çekerken:
- Oyunun **telefon** sürümünden çek; eski videolar da öyleydi, HUD dikeyde düzgün duruyor.
- Hiç kayıt yoksa o çekim çizimle kalır, video yine çıkar.

## Paylaşım (TikTok, İngilizce)

**Açıklama:**
> would you risk it for a SECRET? 😳 game: Steal a Crewmate on Roblox · code TIKTOK = free egg

**Hashtag'ler (5-6 tane yeter):**
`#roblox #robloxgames #robloxfyp #gaming #fyp #stealabrainrot`

- `#stealabrainrot` aynı türde, çok aranan bir etiket. Kitlesi büyük, bu yüzden var.
- "Among Us" markası metinlerde kullanılmıyor (DEVIR 22), o yüzden #amongus yok.

**Ses:** videonun kendi sesi (Brian) açık kalsın. TikTok'ta trend bir müziği **%10-15** seviyede
arkaya ekle; trend ses erişimi artırıyor, seslendirmeyi bastırmasın.

**Saat:** 16+ kitle ABD akşamı aktif. Hafta içi TR **01:00-03:00** (ABD doğu 18:00-20:00).
Cuma/Cumartesi TR **02:00-04:00**.

**Yorumlar:** ilk saatte gelen her yoruma cevap ver. "yes/no" yorumlarına "which planet would you rob first?" gibi soruyla dön; yorum zinciri erişimi uzatıyor.

**Ölçüm:** Roblox'ta `TIKTOK` kodunu kaç kişinin girdiği = TikTok'tan gelen oyuncu.
