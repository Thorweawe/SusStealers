# Profesyonel kapak: yapay zeka görsel aracı + bizim yazılar

Popüler oyunların (Ride A Pet vb.) kapakları Blender'da render edilmiş ya da
yapay zekayla üretilmiş 3D görseller. Python çizimi ve Studio ekran görüntüsü
o kaliteye çıkmıyor (denendi). Yol:

1. Aşağıdaki komutu **ChatGPT (görsel üretimi), Gemini ya da Midjourney**'ye ver.
2. Canavarlar oyundakine benzesin diye **referans görselleri ekle**:
   `thumbnails/space3d/1_leviathan.png`, `2_chomper.png`, `3_kraken.png`, `4_stalker.png`.
   Komutun başına: *"Match the monster designs in the attached images."*
3. 4-6 tane üret, en iyisini seç. **Görselde yazı OLMASIN** (yapay zeka yazıyı bozuyor).
4. Seçtiğin görseli bana at ya da kendin çalıştır:
   ```bash
   python tools/overlay_thumb.py indirilen.png rift rift_ai
   ```
   Kapak `thumbnails/final/`'e, reklam sürümleri (logo + PLAY NOW, 16:9 ve 1:1) `ads/final/`'e çıkar.

Marka notu: komutlarda "Among Us" yok (DEVIR 22). Crewmate'i genel bir
"kapsül gövdeli uzay adamı" olarak tarif ediyoruz.

## Ortak stil (her komutun sonuna ekle)

> High-quality 3D render in the style of top Roblox game thumbnails. Roblox avatar with a blocky R15 body and classic brown "bacon hair", big expressive cartoon face. Glossy plastic materials, cinematic rim lighting, vibrant saturated colors, shallow depth of field, slight motion blur, dramatic low camera angle. 16:9, no text, no logos.

## 1. RIFT (kalıp: `rift`, ana tahmin)

> A Roblox avatar with a terrified screaming face sprints toward the camera, hugging a glowing pearl-white capsule-shaped little astronaut buddy (rounded bean body, light-blue visor, tiny backpack) that sparkles with rainbow light. Right behind him a gigantic pale-white spider monster with very long thin jointed legs, glowing cyan spots on its body and a cluster of glowing cyan eyes lunges at him. Orange-red alien planet surface with craters, bright magenta-to-orange nebula sky, a big glowing planet on the horizon, speed lines, dust kicking up. Leave empty sky in the top-left third for text.

## 2. SPLIT (kalıp: `split`)

> Split-screen composition divided by a diagonal white line. LEFT (night, blue-purple): the same giant pale spider monster sleeping with dim eyes, guarding a glowing rainbow capsule astronaut buddy on the ground. RIGHT (bright golden light rays): a smug Roblox avatar holding the rainbow capsule buddy above his head while green cash flies around. Keep the top-left and top-right corners fairly empty for text.

## 3. STARFALL (kalıp: `starfall`, etkinlik haftası)

> A happy Roblox avatar lifts a glowing light-blue capsule astronaut buddy covered in tiny stars above his head on a blue moon surface. Bright blue night sky full of falling shooting stars with long glowing trails, a ringed orange planet in the corner, sparkles everywhere. Leave the left half of the sky empty for a title.

## 4. BOSSES (kalıp: `bosses`, 16+ için)

> Four dramatic close-up portraits side by side in thick white comic-panel frames on a dark red background, each a different space monster lit with intense colored rim light: a pink round monster with a huge toothy mouth and eyes on stalks, a purple octopus with big glowing eyes, a pale long-legged spider with glowing cyan eyes, and a red capsule-shaped impostor with a sharp-toothed mouth. Cinematic, slightly creepy but fun. Leave the bottom fifth empty for a title.

## Sanatçıya yaptırmak istersen

Fiverr / Roblox Talent Hub / X'te "roblox thumbnail" arat; yaygın fiyat **15-60 $**, 2-3 gün.
Bu dosyadaki komutlar brief olarak verilebilir. Yazısız teslim iste, yazıyı biz ekleriz.
