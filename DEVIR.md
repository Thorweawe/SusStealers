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

## 2026-09-28 (34) — Batur (Yusuf'un şeridine de yazıldı)

**Gezegen yolu doldu + eski UI'lar yeni dilde.** Studio'ya aktarıldı, **169/169 test temiz**.

- **Gezegen yolu** (c34740d, `SpaceBonusService` yeni, `shared/SpaceField` Routes/Rings/StardustSpots/CrateSpots/RockClusters):
  hız halkaları (içinden geçince kısa hız patlaması, `SpaceFX` stepRings), yıldız tozu kümeleri (+$),
  tedarik sandıkları (büyük para, bazen iksir), asteroit kuşakları, Launch Bay'de gezegen panosu.
  Toplama sunucuda (yakınlık, 10 Hz); istemci efekti `SpaceFX` "bonus". Değerler `Config.SpaceBonus`.
- **Golden Comet olayı** (`EventService` "Comet", rastgele saatte 1): uzaydan altın kuyruklu yıldız geçiyor,
  ilk dokunan para + mutasyonlu mürettebat alıyor. `EventFX`'e ikon/alt yazı eklendi; eski Impostor satırları silindi.
- **UI yenileme** (`UiKit.Modernize` / `UiKit.ModernizeText`): `UiKit.Window` ile açılan bütün pencereler
  (Gear, Index, TaskGame, AsteroidGame, Admin...) ve `UiKit.Page` sayfaları (Pet, Style...) otomatik mağaza dilinde:
  lacivert gövde, kalın koyu kenar, FredokaOne + kontur yazılar, ROW satırlar kart. Rebirth, Transit (Lobby),
  AlertBanner, AutoHatch elle bağlandı; HUD (DeviceRoot), üst şerit, açılış ekranı yalnızca yazı.
  **Yeni panel yazarken:** Gotham kullanırsan otomatik FredokaOne'a dönüyor; koyu yazıya kontur eklenmiyor.
  `CardKit.skin` kullanan pencereler eskisi gibi (skin, Modernize'ın iç kenarını siliyor).

---

## 2026-09-28 (33) — Batur (Yusuf'un şeridine de yazıldı)

**Oyuncudan çalma KALKTI.** Karakterler yalnızca uzaydaki canavarlardan çalınıyor.
Studio'ya aktarıldı, **166/166 test temiz**.

- **Silinenler:** `StealService` (yerine yalnızca yürüme/koşma: `MovementService`), `SabotageService`,
  `SabotagePanel`, `CarryGuide`, `ThiefTrail`; remote'lar `StealAlert`, `SabotageAction`;
  Impostor Hunt olayı (oyuncu impostor); kilit, çalma serisi, kurban sınırı, "Stop Thief".
  Kayıttaki `sabotages` alanı yok sayılıyor; `robbed/caught/maxStreak` sayaçları kalktı.
- **Ekipman canavarlara karşı** (`GearService` + `SpaceService.HitMonsters`): Stun Gun dondurur,
  Slap Glove iter, Emergency Button çevredekileri savurur. Sersemleyen canavar kimseyi yakalamıyor,
  kovalamaya yeniden yavaş başlıyor. İstemci efekti `GearFX` "monster".
- **Robux ürünleri yeniden amaçlandı (kimlikler aynı):**
  - Fast Steal pass'i / Fast Hands iksiri → uzayda kapma hızlı.
  - Strong Lock pass'i / Reinforced Lock iksiri → **Monster Shield**: yakalanınca bir kez kurtarır (60 sn).
  - **Roblox panelinde adları/açıklamaları güncellenmeli** (Batur).
- **Yükseltmeler yeniden** (`Config.Upgrades`, kategorili, `UpgradePanel` kaydırılabilir 3 bölüm):
  - Space Capsule
  - **Training Console** (yeni istasyon: kapsülün SOLUNDA `Trainer`, prompt `TrainingPrompt`; mini oyunu kolaylaştırır)
  - Quick Hands (kapma)
  - **Jet Boost** (uzayda Q / BOOST düğmesi, `SpaceFX`)
  - Stealth Suit (geç uyanma, kısa menzil)
  - Lucky Scanner (çalınan mutasyonlu olabilir)
  - Crew Morale (gelir)

  Unit Guard / Carry Speed / Lock Power kalktı; harcanan para yüklemede iade (`Config.RetiredUpgrades`).
- **Kapsül mini oyunu zorlaştı** (`CapsuleFX`: dar alan, hızlı kayma); Training Console kolaylaştırıyor.
  **Kapsül eğrisi:** 120 hıza ~3.2 sa (ortalama mini oyun), eskiden 4.6–6.5 sa.
- **Petlerin hız bonusu** artık uzayda uçuş hızına ekleniyor (`Config.GetFlightSpeed`); canavar eşiği yine kapsül hızı.
  Sol alttaki gösterge "SPACE SPEED".
- **Unvanlar yeniden** (`Config.Titles`, 20 unvan):
  - Nadirlik kademeli, zorlaşan hedefler (10 → 10.000 soygun, hız, antrenman, sersemletme, mutasyon, koleksiyon, son canavar).
  - Başın üstünde nadirlik renginde etiket (`TitleTags`, Mythic/Secret parlıyor), sohbette nadirlik rengi.
  - Efsanevi ve üstü herkese duyuruluyor.
  - Yeni sayaçlar: `trainings`, `stunned`, `thrown`, `mutatedSteals`, `bossSteals`, `bestPlanet`.
- **Görevler:** Steal/Catch yerine Train, Stun, Mutated.
- **Rozetler:**
  - First Heist ilk teslimde.
  - Caught Red-Handed gezen impostoru durdurunca.
  - "Robbed" → Yeeted, "Streak Master" → Heist Master (ikisinin kimliği 0).
- **Öğretici 10 adım:** soygun, ikinci soygun, kapsül, mini oyun, çark, yükseltme, Chomper (`Planet2`), pet, gear, görev.
- Skor tablosundaki "Stolen" artık uzay teslimlerini sayıyor.

## 2026-09-27 (32) — Batur (Yusuf'un şeridine ve haritaya da yazıldı)

Batur telefondan istedi, Claude oturumu (bulut) yazdı. **Studio'ya aktarılmadı,
testler koşulmadı** — Studio'da: önce `git pull`, Studio'dakini dosyaya çek ve
`git diff` (fark varsa dur), sonra aktar, **haritayı yeniden kur** ve testleri koş.

- **Canavar gezegene gömülmüyor** (`SpaceService`): kovalama hedefi oyuncunun gövde
  yüksekliği kadar altı olduğu için plato hizasında kaçanın peşinde canavar
  platoya/küreye giriyor, "çıkmaya çalışırken" takılıp geç çıkıyordu.
  - `keepOffPlanets`: mesanın içindeyse tepesine, kürenin içindeyse yüzeyine itiyor
    (bütün gezegenler). Yerinde sayarsa `outwardFrom` ile kenardan kayıyor.
  - Hareket tek yerde: `moveMonster`.
  - Yakalama/atak mesafesi `reachPoint`: ayaktan tepeye dikey gövdenin oyuncuya en
    yakın noktası (canavar artık platonun altına inemediği için).
- **Kapsülde hep uçuyor** (`CapsuleFX`): içerideyken poz bırakılmıyor, WASD/joystick
  tüpün içinde uçuruyor (`FLOAT_SPEED` 9). Kapıya doğru kenara gelince alçalıp
  bırakıyor, yürüyerek çıkılıyor; kapıda 1.2 sn durursa yeniden havalanıyor.
  `moving()` yerine `moveInput()` (kameraya göre yön).
- **Speed Coil uzayda işlemiyor** (`StealService.applyWalkSpeed`): `InSpace` ya da
  `SpaceCarry` varken bobin hızı sayılmıyor; SpaceService bu nitelikler değişince
  `RefreshSpeed` çağırıyor. `SpaceFX` uçuşa, güverteden koşarak çıkılsa bile uzay
  hızından hızlı başlamıyor.
- **Üst şerit düğmeleri simetrik** (`Topbar`): üç ikon aynı boy (`ICON` 28; eskiden
  24/30/28), Davet'teki mürettebat ortada (0.42'deydi), "+" köşede rozet.
  **Mobilde olay çizelgesi** düğmelerle dikeyde ortalı (`DeviceLayout.besideTopbar`;
  eskiden üst kenar hizalıydı, ölçekli başlık düğmelerin üst yarısında kalıyordu).
- **Üs alanı genişledi:** `Config.PlotSpacing` 120 → 136, `PlotRowSpacing` 116 → 128;
  `kit.luau` `ROOM_HX` artık `(PLOT_SPACING - 36) / 2` (42 → 50, koridor yine 36).
  - `Config.Space.GateX` ve `Landing.X` ızgaradan türetiliyor (180 → 204).
    `SpaceField.InSafe` doğu sınırı da (450 → 498).
  - Haritada sabit kalan iki yer türetildi: tavan cam şeridi (`station.luau`) ve
    dış kanatçıklar (`exterior.luau`).
  - **Harita yeniden kurulmadan oyun açılırsa üsler odalara oturmaz.** README "Harita"
    komutunu çalıştır; `check.luau` raporu `cakisan yuz: 0 | oyun alani ihlali: 0` olmalı.
- **Biraz daha kolay:** `Capsule.Rate` 0.14 → 0.15, `Space.GrabHold` 1.2 → 1.0,
  `CrewRespawn` 9 → 8, `CatchRadius` 7 → 6.5, `LungeCooldown` 3.5 → 4; mini oyun
  alanı %38 → %40.
- **Oyun ve grup açıklamaları** yeni temaya göre: `ROBLOX-ACIKLAMALAR.md`.
- **Testler:** "Uzay: canavar gezegenin içine gömülmüyor" (yeni; `_KeepOffPlanets`,
  `_StepToward`, `_MonsterPosition`, `_ResetMonster`), bobin testine uzay kontrolleri.

## 2026-09-27 (31) — Yusuf (Batur'un şeridine de yazıldı: uzay yürüyüşü yeniden, konveyör kalktı)

Yusuf'un istediği düzen (30)'daki uzay yürüyüşünden farklıydı; onun kodunun üstüne kuruldu.
Yusuf "Batur şu an çalışmıyor, dönüştür" dedi. Studio'daki kopya (30)'dan önceki haldeydi,
çakışma yoktu. Studio'ya aktarıldı, **175/175 test temiz**; kovalama, yakalama ve fırlatma
oyunda denendi.

- **Konveyör kalktı.** Karakterler artık yalnızca uzaydaki canavarlardan (ve oyunculardan) çalınıyor.
  - `ConveyorService` ve `ConveyorFX` silindi.
  - "conveyor"/"lucky" ürünleri ile çarkın "spawn"/"mutation" ödülleri karakteri doğrudan kaideye koyuyor:
    `SpaceService.GrantUnit`. Boş kaide yoksa false döner, makbuz sonra yeniden denenir.
  - `Config.Conveyor*` alanları ve `GetConveyorInterval` kalktı.
  - `RollUnit`/`RarityUnlock` duruyor ama artık kullanılmıyor.
- **Launch Bay:** kuzey duvarın ortası açık.
  - Kapı kafeteryanın tam karşısında (`tools/map/station.luau`, `Config.Space.GateX/Width/Height`).
  - Kuzey kapıda polish'in kasaları ve lambası artık yok.
  - Dışarıdaki güverte (`workspace.SpaceZone.LaunchBay`) çalışma anında SpaceService'te kuruluyor.
  - Güverte ve gemi güvenli bölge: canavar giremez, taşınan karakter burada teslim edilir.
  - Kafeteryadaki eski hava kilidi (`SpaceAirlock`) Start'ta siliniyor.
- **Uzay:** tek sırada, bir sağda bir solda 6 gezegen (`Config.SpaceMonsters`). Tepelerinde canavar, önlerinde 5 kayıp mürettebat.
  - Canavarlar, gereken uzay hızıyla: Glorp 16, Chomper 28, Nebula Kraken 44, Sand Maw 64, Rift Stalker 90, Void Leviathan 120.
  - Her canavarın nadirlik havuzu kendi (`odds`); karakter `Config.RollSpaceUnit` ile çekiliyor.
  - Güverteden çıkan oyuncu uçuyor: istemci tarafında (`SpaceFX`), LinearVelocity + AlignOrientation ile, kamera yönünde, "SpaceSpeed" hızında.
  - Asteroitler ve `SpaceHit` remote'u kalktı (istemciden dinlenen remote sayısı bir azaldı).
- **Çalma → kovalama → yakalama:**
  - Mürettebata 1.2 sn basılı tutulunca karakter sırtına geçiyor (`SpaceCarry`) ve o gezegenin canavarı kükreyip kovalıyor.
  - Kovalama hızı `need`'e kadar çıkıyor.
  - Yakalanınca canavar oyuncuyu eliyle tutuyor (`SpaceGrabbed` niteliği, `SpaceFX` "grab"), sonra gemiye fırlatıyor (`SpaceField.ThrowPath` → `Config.Space.Landing`). Karakter gezegendeki yerine dönüyor.
  - Sunucu, fırlatmanın sonunda oyuncuyu inişe koyarak yedekliyor.
  - Teslimde hile payı var: grab anından sonra "yol / (hız × 1.7)" süre geçmiş olmalı.
- **Canavar ağda tek parça:** `SpaceZone.Monsters.MonsterN.Root` görünmez; State ve Target nitelikte.
  - Modeli ve iskelet animasyonunu istemci kuruyor: `shared/MonsterModel`, kemikler Attachment. Sunucu MonsterModel'i require etmiyor.
- **Uzay kapsülü:** her üssün arkasında, konveyörün eski yerinde.
  - PlotService, `shared/CapsuleModel` ile kuruyor; üs modelinde adı `Capsule`.
  - Sahibi içinde durunca uzay hızı artıyor (`CapsuleService`, `Config.GetCapsuleGain`, azalan getiri).
  - Hız profilde kalıcı: `profile.spaceSpeed`, rebirth'te sıfırlanmıyor.
  - Kapsülün seviyesi yeni **SpaceCapsule** yükseltmesi; ConveyorSpeed'in yerini aldı. Eski ConveyorSpeed seviyeleri sanitize'da kapsüle taşınıyor.
  - Kapsülün yanındaki konsolda `CapsulePrompt` var (PromptFilter OWN_ONLY).
  - Oyuncu nitelikleri: `SpaceSpeed`, `InCapsule`, `CapsuleGain`.
- **Öğretici:**
  - İlk iki adım uzaydan çalmak (hint `SpaceGate`).
  - Üçüncü adım kapsülde antrenman (check `spaceSpeed`, hint `Capsule`).
  - (30)'un "Space" adımı kalktı.
  - Görev "Buy … off the conveyor" yerine "Heist" geldi (stat `salvaged`).
- **Diğer dosyalar:**
  - StealService: InSpace hız dalı kalktı; uçuşta WalkSpeed kullanılmıyor.
  - Uzaya çıkan gemi hırsızının karakteri `KnockDrop` ile sahibine dönüyor.
  - RogueService engel listesinde Conveyor yerine Capsule.
  - Makine uğultusu kapsülün kubbesinde.
- **Aynı gün, ikinci tur:**
  - Gezegenler arası mesafe açıldı (z adımı 280, x 40/320). Arka plandaki dev dekor gezegeni (`exterior.luau`) daha uzağa alındı.
  - Uzak canavar görseli (0,0,0)'da, yani 1. üsste kalıyordu; artık kurulur kurulmaz yerine konuyor.
  - Uçuş girişi sağlamlaştırıldı: WASD kamera yatayında, kontrol modülü boşsa klavye / MoveDirection yedek.
- **Kapsül ikinci tur:**
  - Büyüdü (R 7.5, H 16) ve üssün zemininin DIŞINA, arkaya taşındı (üs kenarından 11 stud geride, oda boşluğunda).
  - İçinde karakter uçma pozunda süzülüyor.
  - Stardew balık tutma tarzı mini oyun var: roketi yeşil alanda tut, çubuk dolunca 10 sn'lik kazanç bir anda gelir.
  - Yeni client→server remote **`CapsuleCatch`**. Sınırları `CapsuleService.TryCatch`'te: kendi kapsülünde, ısınma 3 sn, bekleme 8 sn. Gerekçesi Net.luau'da.
- **Üçüncü tur: konveyörden kalanlar yeni temaya göre ayarlandı.**
  - **Satış:** `SellRefundFactor` 0.5'ten 0.25'e indi. Karakterler bedava çalındığı için "çal-sat" para musluğuydu; satış artık kaide açmak için.
  - **Kilitlenme koruması kalktı** (`EconomyService`). Geliri 0 olana en ucuz karakterin parasını veriyordu; karakterler artık bedava.
  - **Çark:**
    - "Instant Spawn" ve "Guaranteed Mutation" yerine **Free Crewmate** ve **Mutated Crewmate**; "Free Unit" yerine **Jackpot Crewmate** (bir üst canavarın havuzundan).
    - Üçü de `SpaceService.GrantUnit(player, mutated, bonusTier)` ile. Boş kaide yoksa satış değeri kadar nakit veriliyor. Yeni: `SpaceService.PoolFor`.
    - Dilim yazıları: CREWMATE / MUTATED / JACKPOT.
  - **İndeks:** "Cost / Pays back" yerine **Value / Steal from** (o nadirliği veren ilk canavar). İpucu yazısı da güncellendi.
  - **Mağaza:** "Mutation" ürününün açıklaması "A mutated crewmate on your podium" oldu.
  - **PromptStyle:** konveyör için yapılan "yapışkan kart" (BuyPrompt) artık gezegendeki `HeistPrompt`'ta. Beş mürettebat yan yanayken kart titremiyor.
  - Config'ten `RarityUnlock`, `GetUnitWeight`, `RollUnit` ve `RollAffordableUnit` silindi. `LOOK.belt`, DecorFX'teki BeltSlat istisnası, yorumlar ve README güncellendi.
- **Dördüncü tur (oyun testinden gelen geri bildirim):**
  - **Gezegen geometrisi:** kürenin tepesi platodan taşıyordu, canavar ve mürettebat kürenin içinde görünmüyordu. Küre artık platonun altında; plato kalın bir mesa (`SpaceField.PlanetCenter` / `PlateauDepth`).
  - **Uçuş animasyonu** (`src/client/FlyPose.luau`, yeni): KeyframeSequence ile süzülme ve süper kahraman klipleri, hıza göre karışıyor. SpaceFX'te öne yatış en fazla 45°, CapsuleFX'te 42°.
  - **Denge:** gezegen araları giderek açılıyor (310 → 550; 6. gezegen z -2450, sınır -2650). Arka plan gezegeni de uzağa alındı.
  - **Canavar başına `wake` ve `lunge`:** ileri canavarlar daha çabuk uyanıyor; yakına gelince 0.8 sn boyunca need × lunge hızla atılıyor (`LungeRange` / `LungeTime` / `LungeCooldown`). İstemcide "X LUNGES!" çıkıyor.
  - **Mini oyun bonusu:** 7.5 sn'lik kazanç, bekleme 6 sn.
  - **Mini oyun kolaylaştı:** alan %38, roket ve alan yavaş, çubuk daha hızlı doluyor.
  - **Uzay kartı** yalnızca öğretici sürerken görünüyor ("studs" yazısı yok). Tehlike kenarı her zaman çalışıyor.
  - **Hotbar:** eldeki aletin adı ve "CLICK TO USE" yazısı kalktı; yalnızca beklemede basınca "READY IN".
  - **Gear'lar uzayda ÇALIŞMIYOR** (kullanıcı kararı): uzaydayken `GearService.Use` "Gear doesn't work in space" deyip reddediyor. Bir ara canavarı sersemletme eklenmişti; geri alındı (`StunMonsters` yok).
  - **Ghost Serum kaldırıldı** ("çok güçlü"): `Config.RetiredGear.GhostSerum` = 75M iade. Dükkân kaideleri yeniden kuruldu (`wings`).
  - **Kapsül eğrisi** üçüncü kez ayarlandı: Rate 0.14, Growth 1.14, Ref 20, Pow 3.4. Mini oyunsuz son canavara ~7 saat (4 dk / 14 dk / 42 dk / 2 sa / 4 sa).
  - **Petler uzayda** sahibinin arkasında süzülüyor, gölgesiz (`PetFollow`).
  - **Olaylar:**
    - Lights Sabotage canavarları yarı kör yapıyor (`LightsOutWakeMul` 2.5, `LightsOutChaseMul` 0.85, `SpaceService.SetEventMods`).
    - Reactor Meltdown çekirdekleri uzaya savruluyor (`SpaceService.RandomSpacePoint`); karakter ödülü `GrantUnit(bonusTier 1)`.
    - Yeni **Mutation Storm** (`Storm`, 2 saatte bir :05, 2 dk): gezegendeki herkes mutasyonlu. EventFX'te ikonu ve yazısı var.
  - `SpaceService.GrantUnit` artık (ad, kimlik) dönüyor.
- **Testler:** `SpaceService.SetPaused` ve `CapsuleService.SetPaused` Run'da duraklatılıyor. 177/177 temiz.
- **Batur'a:** denge sayıları ilk tahmin; oynayınca ayarlanmalı:
  - `need`, `odds`, `Config.Capsule`, kapsül fiyatı (4000 × 2.3^sv).
  - 1. kat tavanıyla (sv 6) 120'ye ~1 saat.

## 2026-09-27 (30) — Batur (Yusuf'un şeridine de yazıldı)

- **Uzay yürüyüşü (yeni):** kimse yokken de çalma heyecanı olsun diye.
  - Kafeteryanın kuzeydoğu pah duvarında **hava kilidi** (`workspace.SpaceAirlock`, "Space Walk" promptu).
  - Gemiden uzakta **uzay alanı** (`workspace.SpaceZone`, kalıcı, çalışma anında kuruluyor):
    rıhtım → asteroitli kaya yolu (12 studluk boşluklar) → Void Beast yuvası (6 balon, 3 canavar).
  - Balondan mürettebat kap (1 sn) → canavarlar kükreyip kovalıyor (16 → 24.5 hız) → rıhtıma
    varınca üssün boş kaidesine. Yakalanırsa / asteroit çarparsa / düşerse karakter balonuna döner.
  - Uzayda hızlar ayrı (`Config.Space`): yürüme 24, koşma 32, taşıma 22, taşırken koşma 27;
    `StealService.applyWalkSpeed` "InSpace"/"SpaceCarry" niteliklerine bakıyor. Yerçekimi 55 istemcide.
  - Asteroitler deterministik (`shared/SpaceField`): istemci çiziyor ve çarpmayı bildiriyor
    (`SpaceHit`, yalnızca oyuncunun aleyhine), sunucu aynı formülle doğruluyor.
  - İstemci: `SpaceFX` (asteroitler, şerit uyarıları, görev kartı + ok, tehlike kenarı, savrulma).
    Taşınan model adı `SpaceCarry` (gemideki `CarriedUnit` sistemleri karışmasın).
- **Öğretici:** çalma adımından sonra "Rescue a lost crewmate" (sayaç `profile.salvaged`, hint `Airlock`).
  Yalnızken çalma adımı atlanınca uzay yürüyüşünü öneriyor. `TutorialUI` uzaydayken ok/ışın çizmiyor.
- Studio'ya aktarıldı, 176 test temiz; kovalama ve yakalama oyunda ölçülerek denendi.

## 2026-09-27 (29) — Batur

- **Taşıma hızı ikinci tur:** yükseltme en fazla +2, pet en fazla +1, tavan 10 (normal 16).
  HUD'daki "pets +x" tavanlı değeri yazıyor.
- **Karakter etiketi (`UnitModel.BuildLabel`) yeni tarz:** üstte renkli nadirlik (+ mutasyon),
  beyaz ad, yeşil gelir; FredokaOne + koyu kontur. `moving` (üçüncü argüman, `ConveyorService`)
  sabit piksel boyutlu: dünya ölçüsünde TextScaled kayan karakterde titriyordu.
- Studio'ya aktarıldı, 172 test temiz.

## 2026-09-27 (28) — Batur (Yusuf'un şeridine yazıldı)

- **Ekonomi (`Config.UnitPriceScale` 1.5, `Config.UnitIncomeScale` nadirliğe göre 0.75–0.55):**
  Units tablosu elle yazılmış haliyle duruyor, hemen altında ölçekleniyor ve yuvarlanıyor.
  Amorti ~2–3 kat uzadı (Common ~100s, Epic ~350s, Secret ~890s).
- **Öğretici 9 adım:** sonuna Task (görev konsolu), Hatch (Hatchery Egg1), Gear (dükkân tezgâhı).
  Sayaçlar: `TaskReady_*` nitelikleri, `profile.petsFound`, `profile.gear`. Ödüller bir sonraki
  adımın fiyatını karşılıyor (test "her adım karşılanabiliyor"). **Eskiden bitiren oyuncular
  (adım 6) yeni üç adımı görüyor.** `TutorialUI.resolveHint` yeni hint'leri de buluyor.
- **Hotbar** öğretici kartı açıkken kartın sağına kayıyor; **bildirimler** kartın üstüne çıkıyor.
- Studio'ya aktarıldı, 172 test temiz.

## 2026-09-27 (27) — Batur (Yusuf'un şeridine yazıldı)

- **Bildirimler (`Toasts.luau`, yeni):** alttaki gri kutular ekipman çubuğunun üstüne biniyordu.
  Artık CardKit kartı (yeşil/kırmızı, kalın konturlu yazı), çubuğun ve ekipman adının üstünde;
  en fazla 3. `init.client` eski `toastHolder` kodu kalktı, `showToast` aynı imzayla duruyor.
- **Ekipman geri bildirimi (`Hotbar`):** kuşanılı ekipmanın adı + "CLICK/TAP TO USE" çubuğun
  üstünde; kullanınca yuva zıplıyor, bekleme perdesi + saniye; beklerken basınca sallanıyor,
  "READY IN 3s". Kullanım anı sunucunun `GearFX` "use" yankısından.
- **Taşıma rehberi (`CarryGuide`):** "123 studs" yazısı kalktı; CardKit ok + "RETURN TO YOUR BASE!".
- **"Stop Thief" yalnızca soyulana:** sunucu promptun `OwnerId` niteliğini yazıyor,
  `PromptFilter` başkalarında kapatıyor (hırsız kendi sırtında görüyordu).
- **Durdurulan hırsızın karakteri çalındığı kaideye dönüyor** (ilk boş kaideye gidiyordu,
  "kayboluyor" sanılıyordu). Test: `StealService._StartCarry`.
- **Taşıma hızı dengesi (`Config.GetCarryWalkSpeed`):** yükseltme azalan getirili (en fazla +3),
  pet en fazla +1.5, toplam tavan 12 (eskiden 15). Upgrade paneli 2 ondalık.
- **Öğretici:** çark adımı yükseltmeden önce ve ödülü 95 bin (en ucuz yükseltme 100 bin, önceki
  ödüller ~10 bindi, yeni oyuncu "Buy an upgrade"da takılıyordu). Çalma adımı rakip olsa da en
  fazla `Config.TutorialStealGiveUpSeconds` (120). Yeni adımın uzun metni ayrıca bildirim olarak
  gitmiyor (kart zaten gösteriyor), yalnızca "Next: ...". Uzun bildirimler iki satır.
- **Rogue impostor** bildirimi yalnızca hedef üssün sahibine (başkalarına "X'in üssüne geliyor" gitmiyor).

## 2026-09-27 (26) — Batur (Yusuf'un şeridine yazıldı)

- **Mobil olay çizelgesi** üst çubukta, UI gizleme (göz) düğmesinin sağında (`DeviceLayout`
  TOUCH_PLACE `beside = "topbar"`); süren olay şeridi onun altına iniyor (`EventFX`).
  Not: `AbsolutePosition` bütün ScreenGui'lerde aynı eksende (IgnoreGuiInset fark etmiyor).
- **Mobil RUN düğmesi** Roblox'un zıplama düğmesinin sol altında (`Sprint`, JumpButton'ın
  gerçek yerinden; ekran boyu değişince yeniden).

## 2026-09-27 (25) — Batur (Yusuf'un şeridine ve haritaya da yazıldı)

- **Çarkın bedava çevirmesi çalışmıyordu:** `PromptGuard.Validate` yalnızca parçadaki promptu
  kabul ediyordu; çark promptu Attachment'ta (SpinPromptPoint). Artık Attachment da geçerli
  (WorldPosition). Test eklendi. **Promptu Attachment'a koyarsan bu yüzden çalışıyor.**
- **Tutorial:** hedef nesne istemciye yüklenmeden gelirse (ilk adım, StreamingEnabled) istemci
  ipucundan kendisi buluyor; "studs" yazısı kalktı. Çalma adımında çalınacak rakip yoksa
  `Config.TutorialAloneSkipSeconds` (15) sonra adım kendiliğinden geçiyor.
- **Crew listesi** (`Leaderboard`): avatar yüzleri (headshot), üs rengi halka ve kart, CardKit.
- **Menus (Potions/Titles), RewardsPanel** CardKit ile yeniden (mantık aynı).
- **İksir ürün kimlikleri** girildi (mağazada SOON kalktı). Kapak görselleri `thumbnails/`.
- **Laboratuvar panosu** korkuluğun önüne alındı (`annex.luau`), yazı duvarda kalıyordu.

## 2026-09-26 (24) — Batur (Yusuf'un şeridine de yazıldı)

- **`Config.Developers`** (ATCIKM, 48yusuf): sıralamalarda görünmüyorlar
  (`Config.LeaderboardHidden`, `GlobalBoardService` süzüyor; TOP CREW kürsüsü de),
  sohbette **[DEVELOPER]** unvanı (`Config.DeveloperTitle`; `TitleService` "Title" niteliğine
  yazıyor, `ChatTitles` kırmızı-altın çiziyor). Unvan menüsünde yok.
- **`Config.ServerSize = 8`:** başlık ekranı Studio'da bunu yazıyor (MaxPlayers 60 veriyordu).
- **EventFX mağaza dilinde:** olay şeridi ve sağ alt çizelge CardKit kartları.

## 2026-09-26 (23) — Batur (Yusuf'un şeridine ve haritaya da yazıldı)

- **Rogue impostor fiziksiz:** Humanoid yok. Sunucu zemine oturtulmuş rotayı modelin
  `RogueTrack` niteliğine yazıyor (`shared/RogueTrack`), `MapLife` her karede o rotadan
  yürütüyor; yalpalama yürünen yola bağlı, ayak hizası etrafında. Kök adı `RogueRoot`.
- **Bant satın alma kartı sabit** (`PromptStyle`, `STICKY` = BuyPrompt): en yakın karakter
  değişince kart yeniden çizilmiyor, yeni karaktere kayıyor.
- **Üst kat:** güverte altı lambaları aşağı bakan spot (PointLight üst katın zeminine sızıp
  parlama yapıyordu), duvar lambaları spot; kilitli kat ışıkları `Light` sınıfıyla kapanıyor.
  **Kolonlar** alt kattaki eşyalara (konveyör girişi, kilit konsolu, kulübe) giriyordu:
  `PlotService.clearColumns` kaydırıyor/kaldırıyor.
- **Şans çarkı:** `Config.SpinWheelSlices` (12 dilim → ödül), `SpinService` dilimleri boyayıp
  yazı ekliyor; açı sunucu saatinden (`shared/WheelSpin`, `DecorFX`), çark kazanılan dilimde
  duruyor, ödül mesajı o anda. `Config.SpinDuration` 4 → 5.
- **Top Crew kürsüsü:** TOP EARNERS'ın ilk üçünün gerçek Roblox karakterleri
  (`GlobalBoardService`). Haritadaki sabit Among Us karakterleri kalktı (`lobby.luau`).
- **`client/CardKit`:** mağaza görünüşünün ortak parçaları (skin, card, button, bar, badge).
  **UpgradePanel, QuestPanel, Inventory kabuğu** bununla yeniden kuruldu (mantık aynı).
  ShopPanel kendi kopyasını kullanıyor, dokunulmadı.
- **Karakterlere özel aksesuar** (`UnitModel` EXTRAS; `noHat` olanlarda nadirlik şapkası yok),
  **indeks gerçek 3B model** (`UiKit.UnitIcon`).
- **TutorialUI baştan:** Kaptan rehber (daktilo), adım afişi, konfetili kutlama, final, hedefe
  ışık hattı (Beam), CardKit kart. Sunucu ve remote aynı.
- **Harita pencereleri lombozu** (`kit.luau` K.wall): station/lobby/wings/annex yeniden kuruldu.
  Not: SurfaceGui **Glass malzemeli** parçada çizilmiyor, önünde Glass olan da siyah kalıyor.
- **`UiKit.IconButton`** yazısı satır kırmıyor, en az 5 punto (küçük ekranda "INVENTO").
- **Testler:** pass önbelleği test boyunca "yok" (`MonetizationService._SetPassCache`) — pass
  kimlikleri girilince oyunun sahibi pass'lere sahip çıkıp gelir/çalma testleri bozuluyordu.
- Studio'ya Claude oturumunun MCP araç listesi boş geldiği için doğrudan StudioMCP istemcisiyle
  yüklendi (oturum açılırken Studio bağlı değilse liste boş kalıyor; önce Studio'yu aç).

## 2026-09-26 (22) — Yusuf (Batur'un şeridine de yazıldı)

- **Oyunun adı "Steal a Crewmate"** (başlık ekranı). Marka riski yüzünden görünen adlarda
  Among Us izi kalmadı: "Impostor Among Us" olayı → "Impostor Hunt", Skeld Egg → Station Egg,
  Polus Egg → Frost Egg, The Skeld → The Starship, Polus Outpost → Frost Outpost. **Kimlikler
  aynı** (SkeldEgg, PolusEgg, TheSkeld...) — kayıtlar bozulmuyor.
- **Kodlar:** `Config.Codes` (RELEASE, CREWMATE, SUS), `RewardService.RedeemCode`; istemci
  `RewardClaim` remote'unun "code" türüyle istiyor (yeni istemci→sunucu remote YOK), sonuç
  `CodeResult` (sunucu→istemci). Kayıtta `profile.codes`. Mağazada CODES bölümü.
- **Impostor NPC uçmuyor:** bantların ve kaidelerin üstüne basamak gibi çıkıyordu. `RogueService`
  kaide/bantlara PathfindingModifier ("RogueAvoid", yol maliyeti sonsuz) ve çarpışma grubu
  ("RogueObstacle" ↔ "RogueNPC" çarpışmıyor) koyuyor. Oyuncular etkilenmiyor.
- **`Config.HatchDuration` 3.5 → 4.5** (açılış gerilimi + sesler); sunucu da bu kadar bekliyor.
- İstemci: `PromptStyle` (bütün ProximityPrompt'lar oyunun kart tasarımıyla; yumurtalar hariç),
  mobilde olay çizelgesi üst ortada, telefon/tablet yalnızca yatay (`StarterGui.ScreenOrientation`
  = LandscapeSensor, place ayarı da).

## 2026-09-26 (21) — Yusuf (Batur'un şeridine de yazıldı)

- **Mağaza baştan (`ShopPanel`):** yeşil başlık, FEATURED / PASSES / MONEY / POTIONS / BOOSTS
  bölümleri, sağda bölüm düğmeleri, ışınlı renkli kartlar, büyük Robux düğmeleri.
- **Kart görselleri:** `tools/shop_art.py` (store_icons.py'nin çizimleri, zeminsiz/yazısız +
  iksirler + `rays`) → `shop_art/*.png`. Studio Import Queue ile yüklendi, kimlikler
  `ShopPanel.luau` içindeki `ART` tablosunda. Import Queue **Türkçe karakterli yoldan
  (Masaüstü) yükleyemiyor**; PNG'leri önce ASCII bir klasöre kopyala.
- **İksirler Robux ile (sunucu):** `Config.Products` içinde `kind = "potion"` 4 ürün (id = 0,
  mağazada SOON). `PotionService` "potion" ödülünü kaydediyor: envantere giriyor, o iksir
  doluysa hemen içiliyor (parası ödenen ürün boşa gitmesin). Ürün ikonları:
  `store_icons/product_potion_*.png`.
- **Instant Spawn mağazadan kalktı** (`Config.Products.SkipConveyor` silindi); ConveyorService'in
  "conveyor" ödülü duruyor.
- **Pass/ürün kimlikleri girildi** (5 pass, 7 ürün). **Testler artık gerçek kayda yazmıyor**
  (`DataService._SetSavingPaused`); eskiden deneme parası oyuncu kaydına geçiyordu.

## 2026-09-26 (20) — Batur (Yusuf'un şeridine yazıldı)

- **`UiKit.IconButton` yazısı büyüdü ve sığdırılıyor:** TextSize 13 + TextScaled +
  UITextSizeConstraint (9-13). HUD küçük ekranda `DeviceScale` ~0.78 ile küçülüyor;
  `Inventory.luau` "INVENTORY"yi 10 puntoya indiriyordu, ekranda ~6 piksel kalıp bulanık
  görünüyordu. O override kaldırıldı. REBIRTH / TITLES / POTIONS da aynı düğmeyi kullanıyor.

## 2026-09-26 (19) — Batur

- **Petler 56'dan tekrar 25'e döndü** (Batur istedi): `Config.Pets` 0cb45d5 öncesi liste
  (her yumurtada kademe başına tek pet, hepsi dengeli), `PetModel` de eski hali. `PET_STYLE`,
  `GetPetChance`, çok petli ızgara duruyor — ileride pet eklenirse hazır. Kayıtta silinen
  petlerin anahtarları yüklemede zaten atılıyor (`ParsePetKey`/`GetPet`).
- **Lucky Spin promptu** artık çark göbeğinde değil, kaidenin ön yüzünde göz hizasında
  (`SpinPromptPoint` Attachment). Göbek yüksekte olduğu için yaklaşınca ekran dışına çıkıyor,
  Roblox da promptu gizliyordu — yazı ancak yukarı bakınca çıkıyordu.

## 2026-09-26 (18) — Batur (Yusuf'un şeridine ve haritaya da yazıldı)

- **`EggPanel`: CanvasGroup kaldırıldı** (düz Frame + açılışta UIScale büyümesi). CanvasGroup
  içeriği düşük çözünürlüklü dokuya çiziyordu: 3B pet simgeleri ve yazılar bulanıktı; ayrıca
  kendi boyutunu (340 px) kesiyordu — 15 petli yumurtada son satır ve **E/R/T düğmeleri
  görünmüyordu**. Şimdi net ve tam. (Yeni UI'da ViewportFrame'i CanvasGroup içine koyma.)
- **Üslerin 2./3. katı aşırı parlaktı:** tavan panelleri (y≈52, üslerin üstündekiler) menzil
  58 / 1.6 ile zemin katı ucundan, üst katları tam güçle vuruyordu. `tools/map/station.luau`
  oda panelleri → **40 / 1.2** (koridor panelleri aynı). `PlotService.buildUpperFloor` üst kat
  yürüme yüzeylerini kata göre %10 koyulaştırıyor. Harita denetimi 0, testler 160/160.

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
