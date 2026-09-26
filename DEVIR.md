# Devir notları

Karşı tarafın bilmesi gereken işler. **En yeni en üstte.** Her oturumun
başında `git pull` sonrası oku; kuralı README'de ("İki kişi çalışırken").

Kayıt kalıbı:

```
## YYYY-AA-GG — Kim (kimin şeridine yazıldı)
- Ne değişti, hangi dosyalar
- Karşı tarafın yapması / bilmesi gereken
```

---

## 2026-09-26 (17) — Batur (Yusuf'un şeridine ve haritaya da yazıldı)

- **Pet simgeleri büyüdü** (hâlâ bulanık görünüyordu: ViewportFrame çözünürlüğü ekrandaki
  boyutu kadar). `PetPanel` kartı 96x108 → 96x120, simge 38 → 50 px; `EggPanel` küçük
  hücre 66x76 → 66x84, simge 32 → 44 px; `UiKit.PetIcon` kamerası yaklaştı (2.35 → 2.05).
- **Admin odası sandalyeleri masaya dönük** (`tools/map/rooms.luau`): `chair(x, d, color,
  yaw?)` artık dönüş alıyor; Admin'dekiler 90 / -90. Security'deki monitöre bakan aynı kaldı.

## 2026-09-26 (16) — Batur (Yusuf'un şeridine yazıldı)

**Pet simgeleri gerçek 3B model** (`UiKit.PetIcon` yeni; `PetPanel`, `EggPanel`, `Index`, `HatchFX`):
- Eski `UiKit.PetFigure` biçimi 30 px yuvarlak kutulardan çiziyordu: bulanık duruyordu
  ve aynı biçimli petler (Tiny UFO / Pulsar) birbirinin aynısıydı. `PetIcon(parent, size,
  key, silhouette?)` petin `PetModel`'ini ViewportFrame'de gösteriyor (mutasyon rengi ve
  boyut anahtardan), `silhouette` verilince düz siluet (bulunmamış pet). Model kurulamazsa
  `PetFigure`'e düşüyor; `PetFigure` duruyor.
- Not: Studio MCP `screen_capture` ViewportFrame çizmiyor (şapka önizlemeleri de boş
  çıkıyor) — oyunda gözle kontrol et.
- Birleştirme (Fuse) sistemi DEĞİŞMEDİ: 3 aynı pet → aynı petin Big'i (×2.5) → Huge (×5)
  → Titan (×10); nadirlik yükselmiyor.

## 2026-09-26 (15) — Batur (Yusuf'un şeridine de yazıldı)

**Petler 25 → 56, her pet farklı stat** (`Config.Pets`, `PetModel.luau`, `EggPanel.luau`, `Index.luau`):
- Her yumurtada her kademede 1-3 pet (Supply 12, Skeld 14, Polus 15, Void 15). Eski
  kimlikler aynı; 31 yeni pet (DuctTape, Keycard, O2Sprout, VentKing, PolusYeti, TinyUfo,
  BlackHole, StarWhale...). Her birine `PetModel` FORMS + ayırt edici DETAILS eklendi.
- **Pet tipi** (`PET_STYLE`): `balanced` 1/1, `earner` gelir ×1.15 hız ×0.8, `runner`
  gelir ×0.85 hız ×1.25. Aynı yumurtanın aynı kademesindeki petler farklı tipte. Aralık
  dar: üst kademenin en zayıfı alt kademenin en güçlüsünden hâlâ iyi (test ediyor).
- Kademe şansları DEĞİŞMEDİ; kademe çekildikten sonra kademedeki pet eşit şansla.
  **`Config.GetPetChance(eggId, petId)`** petin kendi şansı (kademe şansı / pet sayısı);
  yumurta paneli ve indeks artık bunu gösteriyor (eskiden her pete kademenin tamamını
  yazıyordu).
- `EggPanel`: 8'den çok petli yumurtada ızgara 5 sütun + küçük hücre (panele sığsın);
  AUTO-DELETE satırları kademe başına bir tane (eskiden pet başınaydı).
- `GetEggPets` sırası: kademe, sonra gelir, sonra kimlik (sabit sıra).
- Test "her yumurtanın kendi takımı" çoklu pete göre yeniden yazıldı.

## 2026-09-26 (14) — Batur (Yusuf'un şeridine de yazıldı)

**1. Ekipman dengesi** (`Config.Gear`, `GearService.luau`) — Yusuf, senin aletlerin:
- Stun Gun 45 menzil / 3 sn / 10 sn → **30 / 2.5 sn / 20 sn**; Emergency Button bekleme
  30 → **45 sn**; Slap Glove 2.5 → **4 sn**. Fiyatlar aynı (bir kez alınıyor, fiyat gücü
  değil zamanı belirliyor; denge bekleme süresiyle).
- **Taşırken Stun Gun ve Emergency Button kullanılmıyor** (kaçan hırsız kovalayanı dondurmasın).
- **Vurulan oyuncu `Config.GearHitImmunity` (3 sn) tekrar vurulmuyor** (`GearService.IsImmune`);
  vuran "still dazed" uyarısı alıyor.

**2. Gezen impostor artık titremiyor** (`RogueService.luau`, `MapLife.luau`):
- Eskiden çapalı kök her karede ışınlanıyordu → istemcide titreme. Şimdi görünmez
  `HumanoidRootPart` + `Humanoid:MoveTo` ile fizikle yürüyor (sunucu sahibi), Roblox
  istemcide yumuşatıyor. Oturma/düşme/ölme durumları kapalı, parçalar CanTouch=false.
- Görsel gövde köke `RogueBob` (Weld) ile bağlı; Among Us yalpalamasını istemci
  (`MapLife.waddleRogue`) o kaynağın C0'ını YEREL oynatarak veriyor (hıza göre).
- `Rogue` tipinde `root` artık HumanoidRootPart; `visual` (model kökü) ve `humanoid` eklendi.

**3. Test düzeltmesi:** "Pet: otomatik silme" testi Supply Egg'e Legendary eklenince
rastgele düşüyordu; beklenti artık petin kademesine göre. Testler 160/160.

## 2026-09-26 (13) — Batur (Yusuf'un şeridine ve haritaya da yazıldı)

- `GearPanel.luau`: Stun Gun kartında "cd 10s" → "cooldown 10s" (diğer kartlarla aynı).
- `tools/map/lobby.luau`: çarkın başındaki sarı mürettebat odaya (oyunculara) bakıyor
  (-150° → 20°). Studio'daki model de çevrildi.
- Yusuf: 624c5b0 (ekipman yenileme) için DEVIR kaydı yoktu; ekipman dengesi konuşuluyor
  (cooldown/menzil değişebilir), GearService'e dokunmadan önce pull'la.

## 2026-09-25 (12) — Batur (Yusuf'un şeridine ve haritaya da yazıldı)

**1. Görsel netlik** (`src/client/RarityFX.luau`, `tools/map/finish.luau`): nadir
karakterlerin ışığı küçüldü (Mythic: 25 → 15 stud menzil, 2.3 → 1.2 parlaklık), Mythic
mızrakları ince ve yarı saydam, parçacık ve duman azaldı; Bloom 0.7/1.6 → 0.45/2.0.
Pembe ışık artık bütün üssü boyamıyor, kafesteki karakter görünüyor.

**2. Bakım tünelleri** (`tools/map/tunnels.luau` yeni, `kit.luau` M.TUNNEL_*, `station.luau`):
iki üs sırasının arkasında (x=48 ve x=312, merkeze simetrik) korkuluklu rampa zemine
iniyor, tünel sıraların ve koridorun altından geçip öbür sıranın arkasından çıkıyor.
Taşırken de girilebiliyor (vent'ten farkı), yol bulucu içinden geçiyor. Güverte
(Deck), karın (Belly) ve orta blok (BellyMid) artık tünel boşluklu kuruluyor
(`K.boxHoles`); BellyMid alt/üst diye ikiye bölündü. Harita denetimi 0 çakışma.

**3. Admin masası** (`tools/map/admin.luau` yeni, `src/server/AdminMapService.luau` yeni):
Cafeteria'nın kuzey ucunda, panoların önünde masa. Ekranında harita; her oda/üs için
içindeki oyuncu sayısı kadar nokta (tam yer değil). Başkasının üssünde biri varsa o üs
kırmızı, gezen impostor kırmızı nokta, tünel ayrı bölge. Her şey sunucuda çiziliyor
(SurfaceGui dünyada), istemci kodu yok. Bölgeler çalışma anında Decor'dan ölçülüyor.
Not: üst yüzdeki SurfaceGui'nin "yukarısı" parçanın -X'i; ekran parçası 90° döndürüldü.

Harita bölümleri: `SECTIONS`'a "admin" ve "tunnels" eklendi. Testler 151/151.

## 2026-09-25 (11) — Batur (Yusuf'un şeridine yazıldı)

**Üsse tehdit uyarı bandı** (`src/client/AlertBanner.luau`, `init.client.luau`):
- Çalınma, gezen impostor ve sabotaj uyarıları artık alttaki bildirim yığınında
  değil, ekranın **üst-ortasında büyük bant** (başlık + tek satır, açılışta sarsılma,
  nabız atan kenar). Olay şeridinin altında (y=118), yeni uyarı eskisinin yerini alıyor.
- `Notify` işleyicisi: `kind` "rogue" / "sabotage" **ve** isError ise bant, değilse toast.
  StealAlert → "YOU'VE BEEN ROBBED!" bandı (toast kaldırıldı).
- Sunucu tarafı kısaltıldı: StealService kurbana ayrıca toast göndermiyor (bant yeter);
  RogueService / SabotageService kurban mesajları banda sığacak kadar kısa.

## 2026-09-24 (10) — Batur (Yusuf'un şeridine yazıldı)

- `TaskGames.luau` Swipe Card kabul aralığı %30 daraltıldı: `SWIPE_MIN, SWIPE_MAX`
  0.5-1.3 → **0.62-1.18** sn (orta nokta 0.9 aynı; gamepad otomatik kaydırması 0.9'da).

## 2026-09-24 (9) — Batur (yalnızca sunucu/shared)

**Gezen impostor NPC** (`src/server/RogueService.luau`, `Config.Rogue*`):
- 5-9 dk'da bir (olay yokken) rastgele bir vent'ten kırmızı "ROGUE IMPOSTOR" çıkıyor,
  rastgele bir oyuncunun dolu kaidesine yürüyor, 8 sn hackliyor, karakterin kopyasını
  kafasına alıp ≥150 stud uzaktaki bir vent'e kaçıyor (~12 sn kovalamaca).
- **Kilit işe yaramıyor.** Yalnızca üssün SAHİBİ durdurabiliyor (E basılı, 1 sn);
  başkası basınca "Only X can stop this" uyarısı.
- Durdurursa: gelirine göre ödül (120 sn'lik gelir, en az $5K) + yakalama sayacı.
- Kaçarsa: karakter kaidede kalıyor ama **5 dk para üretmiyor** (kaidede
  `OfflineUntil` sunucu saati + `OfflineUnit`; `EconomyService.GetIncome` atlıyor),
  karakter soluk, üstünde "STOLEN m:ss". Karakter değişirse (satıldı/çalındı) biter.
- Hareket sunucuda, model kök parçaya kaynaklı. İstemci kodu gerekmedi.
- Not: bu oyunda `BillboardGui.AlwaysOnTop = true` etiketler çizilmiyor; kapalı kullan.
- Bildirim türü `rogue` (Config.NotifyCues). Testler 149/149.

## 2026-09-24 (8) — Batur (Yusuf'un şeridine de yazıldı)

**1. ChatTitles düzeltildi:** `TextChatService.OnIncomingMessage` OKUNMUYOR artık
(Roblox okumada hata veriyordu). Başka modül mesaj değiştirmek isterse
`ChatTitles.AddTransform(fn(message, properties))` — unvan ondan sonra ekleniyor.
Callback'i başka yerde **atama**, ezersin.

**2. Sabotaj eşyaları** (oyun içi parayla, tek kullanımlık, Envanter → **SABOTAGE**
sekmesi, `src/client/SabotagePanel.luau`):
- Blackout 20 sn (üssün ışıkları sönüyor, orada çalma %30 hızlı), Lock Jam 30 sn
  (kilitlenemiyor, kilitliyse 3 sn'de düşüyor), Comms Jam 45 sn (kurbana çalındı
  uyarısı gitmiyor).
- Kullanan **25 dk** bekliyor (profilde `lastSabotageAt`, çıkıp girince sıfırlanmıyor);
  aynı üsse 90 sn'de bir; kaidesi boş üsse olmaz; türü başına en fazla 3.
- Fiyat gelire göre (`Config.Sabotages`, `GetSabotagePrice`).
- Sunucu: `SabotageService` (yeni), `StealService` nitelik okuyor (Blackout,
  LockJam, CommsJam) — birbirini require etmiyorlar. Yeni remote `SabotageAction`
  (Net gerekçesi yazılı, test sınırı 17). Nitelikler: oyuncuda `Sabotages`,
  `SabotageReadyAt`, `SabotageShieldUntil`, `CommsJam`; üste `Blackout`, `LockJam`.
- Testler 146/146.

## 2026-09-24 (7) — Batur (Yusuf'un şeridine ve haritaya da yazıldı)

Önce: Yusuf'un bulut oturumu `claude/game-mechanics-ui-updates-fj05yq` branch'ine
pushlamıştı; Studio zaten o hâldeydi. **main'e fast-forward birleştirildi**, testler
Studio'da 142/142 (bulut oturumu koşamamıştı).

**1. Olaylar:** Impostor artık **rastgele** — her saat 2 kez, sabit olayların
pencerelerine (uyarı dahil) ve birbirine 15 dk'dan yakın olmayan anlarda; her
sunucu kendi zarını atıyor (`Config.PlanRandomEvent`, `EventDef.random/perHour`).
Uyarı yok, çizelgede yok. `EventFX` çizelgesi yalnızca **sıradaki** sabit olayı
gösteriyor (başlık NEXT EVENT).

**2. Gezen mürettebat (`MapLife`):** 8 kişi, PathfindingService ile her yere
(koridor, odalar, lobi, kanatlar, ek odalar) yürüyor, %30 ihtimalle boş bir
koltuğa oturuyor. Eşya içine düşen karolar hedef değil; 3 kez yol bulamayan
başka karoya taşınıyor. Oyuncu oturunca mürettebat kalkıyor.

**3. Uyarı lambaları duvara monte** (`polish.luau`): duvar yüzü ışınla ölçülüyor,
arka plaka + kol + kubbe. Harita denetimi 0 çakışma.

**4. Asteroit konsolunda da sarı "!"** (`TaskGames`, `AsteroidReadyAt`).

**5. Fix Wiring ve Swipe Card baştan (`TaskGames`):** kablo sürükle-bırak (metal
pano, soket lambaları, kıvılcım sesi; gamepad'de A ile seç/bağla); kart cüzdandan
çıkıp sürükleniyor, hız okunuyor (TOO FAST / TOO SLOW / BAD READ / ACCEPTED,
0.5–1.3 sn). `SoundFX.TaskSound` + 4 yeni ses (Roblox lisanslı).

---

## 2026-09-24 (6) — Claude (bulut oturumu): oyun mekaniği + arayüz turu (iki şeride de yazıldı)

Kullanıcı istedi, iki şeritte birden çalışıldı. **Studio'ya basılmadı** (bulut
oturumu, Studio yok): dosyaları sync ile bas, **haritayı yeniden kur** (aşağıda),
sonra testleri koş. Yeni testler eklendi ama Studio'da koşulmadı.

**1. $100'da kilitlenme (sunucu — `ConveyorService`, `Config`)**
- Geliri 0 olan oyuncunun bandına artık YALNIZCA alabileceği karakterler geliyor
  (`Config.RollAffordableUnit`); mutasyon fiyatı bütçeyi aşarsa düz geliyor.
  Geliri olan ama art arda `Config.ConveyorPityAfter` (3) karakteri alamayan
  oyuncuya da bir sonraki çekiliş bütçesine uygun. Garantili mutasyon (Robux)
  bu kuralın dışında.

**2. Bant saati: gri çıtalar karakterlerle birlikte (sunucu + istemci)**
- `Config.ConveyorLifetime` / `Config.ConveyorSpeed` KALKTI. Yerine
  `Config.ConveyorBeltSpeed` (2.75 stud/sn) + `GetConveyorBeltSpeed(level)`:
  Conveyor Speed yükseltmesi artık bandı da hızlandırıyor (seviye başına +%3.5,
  tavan x1.8 — en hızlıda karakter bantta ~12 sn).
- Her üssün tek bir yol sayacı var; `Conveyor` parçasına `BeltSpeed/BeltDistance/
  BeltStamp` (sunucu saati) nitelikleri yazılıyor. Karakter bir çıtanın üstünde,
  kapağın İÇİNDEN doğup ağızdan çıkıyor; ağızdan çıkana kadar promptu kapalı
  (`OnBelt` niteliği, `PromptFilter` buna bakıyor).
- Yeni istemci modülü `ConveyorFX.luau`: çıtaları ve bandın üstündeki karakterleri
  aynı saatle her karede çiziyor. `DecorFX` artık `BeltSlat`'lara dokunmuyor.
- Çıta sayısı `Config.ConveyorSlats` = haritadaki (bays.luau) sayı; değişirse ikisi birden.

**3. Koltukla ışınlanma** — `Lobby.luau` (RETURN TO MY BASE), `PlotService.Unseat`
(+ `TeleportToPlot`), `VentService`: ışınlamadan önce oyuncu koltuktan kaldırılıyor.

**4. Haritada içinden geçilen hiçbir şey yok (tools/map — YENİDEN KUR)**
- `kit.luau` katılık kuralı değişti: `collide = false` artık yok sayılıyor (map
  dosyalarından da temizlendi). Geçirgen olan yalnızca: `ghost = true`, saydamlığı
  >= 0.7 (cam hariç), yere yatık ince kaplamalar (yükseklik <= 0.6).
- Konveyör kapakları (Hatch/Intake) KATI; `AllowInPlot` niteliğiyle işaretli,
  `check.luau` bunları "oyun alanı ihlali" saymıyor.
- `exterior.luau` → hepsi `ghost` (dış uzay). MedBay tarama halkası `ghost`.
- PlotService: üst kat korkulukları, satıcı, kilit kubbesi, kilitli bonus kaide katı.

**5. Merdiven yeniden tasarlandı (`PlotService.buildUpperFloor`)**
- Her kat merdiveni ÖNDEN (giriş tarafı) başlayıp ARKAYA tırmanıyor, katlar aynı
  yönde üst üste. Arka sahanlık güverteye bağlanıyor; 3. katın merdiveni 2. katın
  ön sahanlığından başlıyor. İki yanda katı korkuluk, basamak burnunda sarı şerit,
  alnında ışık, dipte oklar, tepede "FLOOR N" kemeri. `buildUpperFloor`'a `floor`
  parametresi eklendi. Kilitli katta SurfaceGui'ler de kapanıyor.

**6. Kafeterya kapısındaki kasa yığını ve havada duran uyarı lambası kaldırıldı** (`polish.luau`).

**7. Yumurta stilleri** — yeni `EggStyle.luau`: Supply (karton + koli bandı, zıplıyor),
Skeld (vizör + anten, dönüyor), Polus (kar + buz kristalleri, kar yağıyor), Void
(hale + yörüngede küreler, nabız). Kuluçkadaki yumurtalar istemcide süsleniyor
(harita kurulmadan çalışıyor), `DecorFX` Hatchery.EggN'i artık süzdürmüyor.
`HatchFX` açılışı yumurtanın stiline göre (sarsıntı / hızlanan dönüş / donma /
içine çökme + saçılan parçalar). **Sunucu:** `PetHatched`'in 3. argümanı yumurta
açılışında artık yumurta kimliği (`PetService.TryHatch`, `GiveEggRoll`).

**8. Envanter** — yeni `Inventory.luau`: PETS → POTIONS → STYLE → TITLES sekmeleri tek
pencerede (B tuşu). `PetPanel`, `CosmeticPanel`, `Menus` artık `host` alıp sayfa olarak
kuruluyor (`UiKit.Page`); host verilmezse eski pencere hâli duruyor. `MenuDock`'u
artık Envanter kuruyor: sağ ortada ENVANTER, hemen altında REBIRTH (72x78).
Topbar CLUTTER'a `InventoryPanel`, `EventSchedule` eklendi. `DeviceLayout`:
MenuDock dokunmatik kaldırmadan çıktı, `EventSchedule` girdi; WINDOW_FIT 840x600.
UiKit: `Page`, `Backpack`, `Canvas/Shape/Ring` dışa açık, `IconButton`'a boyut.

**9. Olay çizelgesi (sağ alt)** — `EventFX`: bütün olaylar, çizimle ikonları ve geri
sayımları; süren olay üstte büyük kartta. Üst ortadaki "Next: ..." satırı kalktı
(üst şerit yalnızca olay sürerken).

**Haritayı yeniden kurmak:** README "Harita" bölümündeki komutla bütün bölümler
(polish dahil, en sonda). Denetim `çakışan yüz: 0 | oyun alanı ihlali: 0` vermeli.

## 2026-09-24 (5) — Batur: kozmetikler (Yusuf'un şeridine de yazıldı)

**Ne:** 10 şapka (Sprout → Halo) ve 4 iz (Stardust → Rainbow), oyun içi parayla,
10K'dan 10B'ye. Kalıcı, güç vermiyor; geç oyun için para çukuru.
- `Config.Cosmetics` (tanımlar), `src/shared/CosmeticModel.luau` (görünüş — hazır
  varlık yok, önizleme ile başındaki aynı kod).
- Sunucu: `CosmeticService` — satın alma / takma, karaktere sunucuda takılıyor
  (herkes görüyor), şapka takılıyken avatarın kendi şapkaları gizleniyor.
  Profil: `cosmetics`, `hat`, `trail` (DataService sanitize ediyor).
- Yeni client→server remote **`CosmeticAction`**(action, id) — tek remote'ta
  buy/equip/unequip; gerekçesi Net.luau'da, test sınırı 16.
- İstemci: `CosmeticPanel.luau` — STYLE penceresi (dönen 3B önizleme, HATS/TRAILS
  sekmeleri). Düğmesi sağdaki MenuDock'ta 5. sırada (dock 5 düğmeye uzatıldı).
  Topbar CLUTTER'a `CosmeticPanel` eklendi. UiPreview: `Style`.
- Tasarımı değiştirmekte serbestsin.

---

## 2026-09-24 (4) — Batur: ek odalar ve görevler (harita + Yusuf'un şeridi)

**Harita:** istasyonun güney duvarında, yan koridorların (x=60 ve x=300) ucunda iki
yeni kapı ve arkalarında küçük iki oda:
- `STORAGE` (batı): yakıt tankı → **Fuel Engines**, kablo panosu → **Fix Wiring**
- `LABORATORY` (doğu): kart okuyucu → **Swipe Card**
- Yeni bölüm `tools/map/annex.luau` (SECTIONS'ta `wings`'ten sonra); kapılar
  `station.luau` güney duvarında; ölçüler `kit.luau` → `M.ANNEX_*`.
- `polish.luau`: ön duvardaki ventler kapının yanına kaydı, kapılı koridorlarda
  ön duvar lambası yok. Harita denetimi: çakışan yüz 0.

**Sunucu:** `TaskService` (MinigameService'in aynı kalıbı): konsollar `TaskId`
niteliğiyle bulunuyor, başlangıç sunucuda, en kısa süre / bekleme / yakınlık
sunucuda. Ödül 60 sn'lik gelir, görev başına 10 dk. Config: `Config.Tasks`.
Yeni client→server remote **`TaskDone`** (gerekçesi Net.luau'da, test sınırı 15).

**İstemci:** `TaskGames.luau` — üç mini oyun penceresi + konsol üstünde sarı "!"
(görev hazırsa). Topbar CLUTTER'a `TaskGame` eklendi. UiPreview: Fuel/Wiring/Card.

Not: haritayı Studio'da kurmak için `HttpService.HttpEnabled`'ı geçici açtım
(sync köprüsü ancak öyle çalışıyor), iş bitince kapattım.

---

## 2026-09-24 (3) — Batur: sunucu olayları (Yusuf'un şeridine de yazıldı)

**Sunucu — `EventService` (yeni):** UTC saatine hizalı, bütün sunucularda aynı anda.

| Olay | Zaman | Etki |
|---|---|---|
| Emergency Meeting | her saat :15, 2 dk | herkese 2x gelir |
| Lights Sabotage | her saat :45, 90 sn | çalma süresi ×0.6, istemcide karanlık |
| Reactor Meltdown | 3 saatte bir :30, 60 sn | üslerin dışında rastgele 6 çekirdek; nakit / %15 karakter |
| Impostor Among Us | 2 saatte bir :00, 1 dk | rastgele oyuncu herkesin gördüğü impostor; yakalanırsa yakalayan ona %3-5 öder (en fazla 200k) |

- 30 sn önce uyarı. Ayarlar `Config.Events` ve altındaki sabitler.
- `StealService`: `SetEventHoldMultiplier`, `OnCaught` eklendi. `EconomyService`:
  `workspace.EventIncomeMul` çarpanı.
- İstemciye workspace nitelikleriyle gidiyor (`EventId`, `EventEndsAt`, `NextEvent*`);
  yeni remote yok.

**İstemci — `EventFX.luau` (yeni):** üst ortada olay şeridi + geri sayım, olay yokken
"Next: ... in mm:ss"; Lights Sabotage'ta yerel karartma. Tasarımını değiştirmekte serbestsin.

**Düzeltildi (aynı gün, sonraki commit):** Fast Steal pass'i / Fast Hands iksiri pratikte
işe yaramıyordu (sunucu kısa basışı kabul ediyor, istemcideki prompt tam süreyi bekliyordu).
Şimdi: pass %40, iksir %20 hızlı (üst üste binmiyor), en az 1 sn (`Config.MinStealHold`).
Sunucu oyuncuya `StealHoldMul`, çalma promptuna `BaseHold` niteliği yazıyor;
`PromptFilter` (istemci) kendi ekranında süreyi `Config.GetPersonalStealHold` ile kısaltıyor.
ShopPanel'deki pass açıklaması güncellendi.

---

## 2026-09-24 (2) — Batur (Yusuf'un şeridine ve haritaya da yazıldı)

**Harita — `tools/map/polish.luau` (yeni bölüm, SECTIONS'ın EN SONUNDA):**
- Oda tabelaları (tavandan sarkan, iki yüzlü), orta boşlukta kasa yığını,
  duvarlarda kırmızı uyarı lambaları, 6 yeni vent kapağı (landmarks'taki
  kapağın kopyası), küçük/tavan/zemin parçalarında gölge kapalı (4196 → 1878).
- Malzemelere dokunulmadı (kit'in SmoothPlastic kuralı).
- Studio'ya doğrudan uygulandı (Decor.Polish). **Haritayı yeniden kurarsan
  polish'i de çalıştır**, yoksa tabelalar/ventler gider ve ventler kapanır.

**Sunucu:** `VentService` — eşli kapaklar (VentPair A-D), taşırken kullanılamıyor,
8 sn bekleme. Config: `VentCooldown`, `VentHoldTime`.

**İstemci:**
- Yeni `MapLife.luau`: uyarı lambalarını yakıp söndürüyor, koridorda 4 süs
  mürettebat geziyor (istemciye özel, çarpışmasız).
- Sesler: asteroit oyununa lazer + kaya kırılma sesi; Music'te dron/nabız sesleri
  yerine Roblox lisanslı müzik; gıcırtılı fon dronu kapalı (`AMBIENT_ENABLED`),
  makine uğultusu yarıya indi. Arayüz/alarm seslerine dokunulmadı.

---

## 2026-09-24 — Batur (Yusuf'un şeridine de yazıldı: `src/client/*`)

Cihaz uyumu (telefon/tablet/konsol) ve arkadaş bonusu. Testler 126/126 temiz,
Studio ile repo aynı.

**İstemci — bilmen gereken tek önemli şey:**
- `init.client`'taki `screen` artık **ScreenGui değil**, içindeki ölçek
  katmanı `DeviceRoot` (Frame + UIScale). Paneller aynen çalışıyor. Ama:
  - `screen.Parent` artık PlayerGui değil → PlayerGui lazımsa
    `player:WaitForChild("PlayerGui")` kullan (TutorialUI ve Topbar'da düzelttim).
  - `AbsoluteSize` / fare konumu ekran pikseli, panel içi konumlar ölçeksiz birim.
    Çeviri: `screen:GetAttribute("Scale")` ile böl (AsteroidGame'de düzelttim).
- Yeni `DeviceLayout.luau`: ölçek ekrana göre (en fazla 1, masaüstünde görünüm
  aynı). Dokunmatikte `StatBar`, `SideRail`, `Tutorial`, `MenuDock` joystick/zıplama
  düğmesinin üstüne kayıyor — adlarını değiştirirsen `TOUCH_LIFT` listesini de güncelle.
- Gamepad: pencere açılınca seçim ilk düğmeye geçiyor (`UiKit.OnWindowOpened`);
  ekipman çubuğunda L1/R1 ile geçiş.
- Topbar'a en sola **Davet** düğmesi (Roblox davet penceresi).
- Nakit hapının alt satırı arkadaş bonusunu gösteriyor: `+$X/s · friends +10%`.

**Sunucu:** `FriendService` — aynı sunucudaki her arkadaş +%5 gelir, tavan +%15.
Oyuncuya `FriendBonus` / `FriendsHere` nitelikleri yazılıyor. Config'e
`FriendBonusPerFriend`, `FriendBonusMax` ve `friend` bildirim sesi eklendi.

---

## 2026-09-24 — Batur

- **Yeni kural:** Karşı taraf çalışmıyorken onun şeridine de yazılabilir;
  iş sonunda buraya kayıt düşülür. README'ye eklendi.
- **Yusuf'a — hata, `src/client/ChatTitles.luau:89`:** `TextChatService.OnIncomingMessage`
  okunuyor; Roblox bu callback'in okunmasına izin vermiyor. Panel kurulamıyor,
  unvanlar sohbette çıkmıyor. Output:
  `ChatTitles paneli kurulamadi: OnIncomingMessage is a callback member of TextChatService; you can only set the callback value, get is not available`.
  Önceki değeri okumadan doğrudan atama yapılmalı.
- Durum: Studio ile repo birebir aynı, sunucu testleri 124/124 temiz.
- Robux ürün / rozet ID'leri ve sunucu boyutu yayın öncesine ertelendi.
