# Arkadaşın Claude'una atılacak güncelleme

Aşağıdaki metni olduğu gibi kopyalayıp arkadaşın Claude Code oturumuna yapıştırsın.
(İlk tanışma promptu `ARKADAS-ICIN-PROMPT.md`'de; bu onun üstüne gelen durum notu.)

---

Selam. Aynı Roblox projesinde (**Sus Stealers**) çalışıyoruz. Son commit'inden
(`6c21398`, koridorlar) sonra karşı taraf sunucuya epey şey ekledi. Önce
`git pull`, sonra aşağıyı oku.

## ÖNCE ŞUNU YAP — beş panel oyunda görünmüyor

`src/client/init.client.luau` içinde **hiçbiri çağrılmıyor**. Modüller
Studio'da ve repoda duruyor ama bağlanmadıkları için oyuncu hiçbirini
görmüyor. Karşı taraf bilerek dokunmadı: `init.client.luau` senin şeridin
ve bir kez üstüne yazılıp iş kaybedilmişti.

`screen` (ScreenGui) kurulduktan sonra, dosyanın alt tarafındaki diğer
`Create(screen)` çağrılarının yanına:

```lua
local TutorialUI = require(script.TutorialUI)
local QuestPanel = require(script.QuestPanel)
local Menus      = require(script.Menus)
local HudToggle  = require(script.HudToggle)

local tutorial = TutorialUI.Create(screen)
local quests   = QuestPanel.Create(screen)
local menus    = Menus.Create(screen)
local hud      = HudToggle.Create(screen)  -- EN SONA
```

`HudToggle` **en sonda** olmalı: diğer panelleri adıyla bulup gizliyor,
önce çalışırsa henüz yaratılmamış olanları göremez.

Bir de en üstlerde bir yere:

```lua
require(script.ChatTitles).Start()
```

Bu unvanlar commit'inden beri bağlanmayı bekliyor; o olmadan unvanlar
sohbette hiç görünmüyor.

Hepsi `Create(screen)` kalıbında, `{ Destroy }` dönüyor, döngüde
güncellenmeleri gerekmiyor (olay güdümlüler).

## Paneller ne yapıyor, nerede duruyor

| Modül | Yer | İş |
|---|---|---|
| `TutorialUI` | Sol alt + dünyada ok | Öğretici adımı, hedefin üstünde ok, uzaktaysa pusula + mesafe |
| `QuestPanel` | Sol, nakit satırının altı | 30dk / 3sa / günlük görevler, katlanabilir |
| `Menus` | Sağ, üs panelinin altı | Unvan seçimi + iksir envanteri (sekmeli tek pencere) |
| `HudToggle` | Sağ üst | Kalabalık yapanları gizle, `H` tuşu da çalışıyor |
| `ChatTitles` | — | Sohbette isimden önce unvan |

**Bunlar senin şeridinde.** Yerleşim, renk, animasyon, hepsini istediğin
gibi değiştir ya da baştan yaz. Sunucu tarafı sadece veri gönderiyor,
görünümle ilgili hiçbir varsayımı yok. Karşı taraf onları "çalışan bir
taslak" olarak bıraktı, son hali senin kararın.

Yerleşimde çakışma olabilir, bir göz at:
- `QuestPanel` sol tarafta `y=104`'ten başlıyor — nakit/gelir satırlarının
  altı. Sohbet de sol üstte, ona denk gelirse aşağı al.
- `HudToggle` sağda `x = -292` — üs panelinin (260 geniş) solu.
- `Menus` düğmeleri sağda `y=136` — üs panelinin altı.

## Sunucuda ne değişti

Hepsi çalışıyor ve test edildi. **91 test / 560 kontrol, hepsi geçiyor.**

**Öğretici** (`TutorialService`) — 6 adım: karakter al → ikinci kaideyi
doldur → birinden çal → üssünü kilitle → yükseltme al → çarkı çevir.
Ödüllü, kendiliğinden ilerliyor. Eski kayıtlar öğreticiye sokulmuyor.

**Görevler** (`QuestService`) — 30dk / 3sa / günlük, her vadede 2 görev.
İlerleme *taban farkından* hesaplanıyor: görev verilirken sayacın o anki
değeri kaydediliyor. Bu yüzden görev sayaçları yalnızca ARTMALI.

**İksirler** (`PotionService`) — günlük vadenin tamamını bitiren bir iksir
kazanıyor. Envantere giriyor, anında uygulanmıyor. **Hepsi süreli,
kalıcı hiçbir şey yok** — bunlar Robux pass'lerinin karşılığı, süresiz
bir tanesi bile pass satışını öldürür. Bir test bu kuralı koruyor.

**Unvan kuşanma** — oyuncu açtığı unvanlardan istediğini takabiliyor.
Elle seçim yaptıysa sonradan daha yükseği açılsa üstüne yazılmıyor.

**Rozetler, şans çarkı, hırsız yakalama** — daha önceki turdan, çalışıyor.

## Yeni remote'lar

`Net.luau`'da artık açık bir yön haritası var. İstemciden sunucuya
**dinlenen** remote'lar sadece bunlar:

| Remote | Ne yapıyor |
|---|---|
| `TutorialSkip` | Öğreticiyi kapatır (kalan ödüller yanar) |
| `TitleEquip` | Açılmış bir unvanı takar |
| `PotionUse` | Envanterdeki bir iksiri içer |

Üçü de **bir şey vermiyor** — saldırı yüzeyi bilerek dar tutuluyor.
İstemciden sunucuya yeni bir remote eklersen `CLIENT_TO_SERVER`
tablosuna da yaz, yoksa güvenlik testi yakalar.

Sunucudan istemciye: `Notify`, `StealAlert`, `Tutorial`, `Titles`,
`Quests`, `Potions`.

## İki kural (README'de bağlayıcı)

**1. Şerit.** `src/client/*` senin, `src/server/*` karşı tarafın,
`src/shared/Config.luau` ortak ama denge sayıları onda. Bu kural bir kez
çiğnendi ve HUD çalışması silindi.

**2. Studio sync: ÖNCE ÇEK, SONRA BAS.** Dosyaları Studio'ya basmadan
önce Studio'dakini dosyaya çek ve `git diff` ile bak. Beklemediğin bir
fark varsa karşı taraf çalışmış demektir — basma, önce konuş. (Bu kural
bugün bir kez daha doğrulandı: karşı taraf sırayı ters yapıp kendi
düzenlemelerini sildi.)

Köprü: `python tools/sync_server.py`, `127.0.0.1:8788`. Ayrıntısı
README'de.

## Testler

```lua
require(game.ServerScriptService.Server.Tests).Run(player)
```

`0` dönerse temiz. Yeni özellik eklersen testini de ekle. Periyodik
tarama yapan bir servis eklersen `SetPaused` de ekle ve `Run`'da
duraklat — yoksa tarama test ortasında ödül dağıtıp nakit sayan
testleri bozuyor.

## Batur'dan bekleyenler (ikimizi de bekletiyor)

- Sunucu boyutu hâlâ 60, 8 olacaktı
- 10 Robux ürünü (4 gamepass + 6 developer product) ID'leri — hepsi
  `id = 0`, yani şu an satın alma kapalı
- 10 rozet ID'si — aynı şekilde kapalı
