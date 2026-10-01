# Gezegen Savunması (Planet Defense) — Plan

Durum: **taslak, commit/Studio yok** (Batur onay verene kadar). Yusuf başka işte.

**Anahtar:** `DefenseConfig.Live = false` → canlı oyunda mod tamamen kapalı (PILOT istemi yok, remote her şeyi reddediyor, istemci hiçbir şey kurmuyor). Studio'da test için açık. Batur "aç" deyince `true`.

## Döngü (oyuncunun gözünden)

1. Gemide **Navigasyon** odasındaki pilot paneline git → `PILOT` istemi → gezegen listesi
   (uzaydaki gezegenlerle aynı: Gloopus, Candorra, … rebirth gezegenleri rebirth kilidiyle).
2. Gezegen seç → **iniş animasyonu** (ekran kararır, gemi gezegene alçalıyor, toz, rampa açılıyor).
3. Gezegen yüzeyi: **inik gemi** + yanında dükkânlar + önünde **savaş alanı**. Zemin ilk gezegen
   (Gloopus) tarzında: kraterler, parlayan bitkiler; renkler gezegenin kendi paleti.
4. Rampadaki **KOMUTA** istemi → kamera alanın üstüne geçer (taktik görünüm).
5. Alttaki ekip şeridinden kaidedeki crewmate'leri seç, alana koy. Koyulan crewmate kaideden
   ayrılır (kaidede "ON MISSION", gelir durur).
6. Dalgadan önce düşmanın **gireceği kapı sabit**, **izleyeceği yol her dalga farklı**
   (sol kanat, zikzak, ikiye bölünme, sürü…); yol önceden ok ile gösterilir, oyuncu
   crewmate'lerin yerini değiştirebilir. `START WAVE`.
7. Dalga biter → "NEXT WAVE ▶" ya da "RETREAT". Her dalga daha zor; sonsuz.
8. Her **5 dalga = 1 bölüm (sektör)**. Bölüm bitince yıldız + altın, **kontrol noktası** kaydedilir.
   Sonraki girişte "Bölüm N'den devam" ya da daha geriden başlama seçeneği.
   → Oyuncuya sordurtan soru: *girsem mi, önce crew'u mu güçlendireyim, kaldığım yerden mi devam?*

## Kayıp ve hastane

- Dalgada canı biten crewmate **düşer** → **hastaneye** gider (kaidede "IN HOSPITAL", gelir yok).
- Gemi gövdesi (hull) sıfırlanırsa dalga kaybedilir: sahada ayakta kalan **hepsi** düşer, koşu biter.
- Hastanede (gezegendeki hastaneci): **REVIVE** = o crewmate'in **15 dk'lık kazancı**, o anki bütün
  çarpanlarla (rebirth, pass x2, iksir, pet, arkadaş, etkinlik…) — ya da **LET GO** (silinir, kaide boşalır).
- Oyundan çıkan/düşen oyuncu dalga ortasındaysa dalga kaybedilmiş sayılır (kaçış hilesi olmasın).
  Dalga arasında çıkarsa crewmate'ler kaideye döner.

## Yıldız ve altın (yeni para birimi: Gold)

- Bölüm (5 dalga) içinde kayıp: 0 → ★★★, 1-2 → ★★, 3+ → ★.
- Altın **yalnızca yeni yıldız** için (3 yıldız mantığı): ★=30, ★★=60, ★★★=100. Bir bölümde 1★
  aldıysan sonra 3★ yapınca farkı (70) alırsın. Tekrar oynamak altın kasmaya yaramaz → binler birikmez.
- Üst gezegenlerde yıldız başına biraz fazla (gezegen başına +%10).

## Crewmate rolleri

Her kademede 4 crewmate var → her kademede farklı roller:

| Rol | Ne yapar |
|---|---|
| Brawler (yakın dövüş) | Önüne gelen düşmanı durdurur, vurur |
| Guard (tank) | Çok can, çevresindeki düşmanları kendine çeker |
| Shooter (uzakçı) | Uzaktan ateş |
| Assassin | Az can, tek hedefe çok hasar, en güçlü düşmanı seçer |
| Medic | En yaralı müttefiki iyileştirir |

**Güç**: daha çok kazandıran biraz daha güçlü ama fark küçük:
`güç = 1 + 0.05 × log10(saniyelik gelir × mutasyon)` → Red Crewmate ≈1.0, Secret ≈1.4,
en iyi Celestial ≈1.7. Asıl güç **altınla alınan yükseltmelerden** ve yerleşimden geliyor —
oyunu bitiren oyuncu da ilk bölümleri tek tıkla geçemesin.

## Düşmanlar (gezegenin renginde küçük yaratıklar)

Grub (sıradan) · Skitter (hızlı) · Spitter (uzaktan tükürür, crewmate'lere vurur) ·
Brute (tank) · her 5. dalgada **Boss** (gezegen canavarının yavrusu). Dalga büyüdükçe sayı,
can ve hasar artıyor; gezegen ilerledikçe taban zorluk artıyor.

## Gezegendeki dükkânlar (altınla)

- **Hospital** (hastaneci): revive (nakit), let go.
- **Armory** (gearcı): rol yükseltmeleri (Brawler/Guard/Shooter/Assassin/Medic can+hasar, 10 seviye).
- **Command Shop** (shopçu): sahaya konabilecek crewmate sayısı (4 → 9), gemi gövdesi (hull).
- **Market** (marketçi): savaşta tek kullanımlık destekler (Orbital Strike, Med Drop, Barricade).

## Teknik

| Parça | Dosya | Not |
|---|---|---|
| Ayarlar | `src/shared/DefenseConfig.luau` (yeni) | Roller, düşmanlar, dalga üretimi, altın, dükkân fiyatları |
| Simülasyon | `src/shared/DefenseSim.luau` (yeni) | Saf veri, 10 Hz, deterministik (test edilebilir) |
| Düşman modeli | `src/shared/EnemyModel.luau` (yeni) | Parçadan yaratık |
| Sunucu | `src/server/DefenseService.luau` (yeni) | Koşu, yerleştirme, altın, hastane, dükkânlar, remote doğrulama |
| Dünya | `src/server/PlanetWorldService.luau` (yeni) | Gezegen yüzeyi, inik gemi, dükkânlar; gezegen başına ilk inişte kuruluyor (uzak koordinat) |
| İstemci | `src/client/DefenseFX.luau`, `DefenseUI.luau` (yeni) | İniş animasyonu, taktik kamera, düşman/crewmate çizimi, HUD, dükkân pencereleri |
| Değişen | DataService (profil `defense`, kaide `away`), PlotService (ON MISSION / IN HOSPITAL), EconomyService (gelir saymıyor), SellService (satılamaz), init.server, init.client, Net | |

- **Herkes kendi savaşı**: harita tek, savaş sunucuda veri olarak dönüyor, yalnızca sahibine
  gönderiliyor; istemci kendi düşmanlarını çiziyor. 8 oyuncu = sıfır fizik yükü.
- Sunucu otoriter: istemci yalnızca "şunu şuraya koy / başlat / geri çekil / satın al" diyor.

## Aşamalar

1. **Çekirdek**: DefenseConfig + DefenseSim + profil alanları + kaide away durumu + testler. ← başladı
2. **Sunucu**: DefenseService (koşu, altın, hastane, dükkân), PILOT istemi, gezegen dünyası.
3. **İstemci**: iniş animasyonu, taktik görünüm, çizim, HUD, dükkân/hastane pencereleri.
4. **Cila**: sesler, düşman animasyonları, Market destekleri, gezegene özel boss, denge.

## Kararlar (Batur)

- Şimdilik **tek harita** (ilk gezegen), pilotta E → doğrudan iniş.
- Aynı anda çok oyuncu: **herkese ayrı arena** (gezegenin kopyası), birbirine karışmıyor.
- Oyuncu da savaşabiliyor: **ışın kılıcı** (Armory, altınla, 5 seviye).

- Rebirth atınca hastanedeki crewmate'ler de gidiyor (kaideler boşalıyor): **kalsın**.
- Altın ve Armory yükseltmeleri rebirth'te **sıfırlanmıyor**.
- Yusuf'un yeni 3B modelleri (işi bitince) dükkân/düşman/gemi görünümlerinde kullanılacak.

## Doğrulama

- Bütün yeni/değişen dosyalar Studio'da derleniyor (yalnızca derleme, yere yazılmadı).
- Simülasyon dengesi Studio'da ölçüldü (yukarıdaki sayılar).
- `tests/ServerTests2.luau` "V. Gezegen savunması": 9 vaka (plan, güç, yıldız/altın, sim,
  kayıt, yerleştir/geri çekil, kayıp→hastane→revive/let go, dükkân, gezegen kilidi).
  Studio'ya aktarılınca koşulacak.
