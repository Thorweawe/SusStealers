# Sus Stealers

Among Us temalı "Steal a Brainrot" tarzı Roblox oyunu.

**Döngü:** Konveyörden karakter al → kaideye koy → saniyelik para bassın → rakibin üssüne girip karakterini çal → kendi kaidene bırak.

---

## Modül haritası

| Dosya | Nerede çalışır | Sorumluluğu |
|---|---|---|
| `src/shared/Config.luau` | Her yerde | Tüm denge sayıları, karakterler, mutasyonlar, formüller |
| `src/shared/Net.luau` | Her yerde | RemoteEvent yaratma/erişim |
| `src/shared/UnitModel.luau` | Her yerde | Among Us karakterini koddan üretir + isim etiketi |
| `src/server/init.server.luau` | Sunucu | Açılış, servis sırası |
| `src/server/DataService.luau` | Sunucu | Kalıcı kayıt, oturum kilidi, çevrimdışı gelir |
| `src/server/PlotService.luau` | Sunucu | Üsleri kurar, dağıtır, kaide ve kat durumu |
| `src/server/EconomyService.luau` | Sunucu | Nakit, leaderstats, saniyelik gelir |
| `src/server/ConveyorService.luau` | Sunucu | Konveyör üretimi, kaydırma, satın alma |
| `src/server/StealService.luau` | Sunucu | Çalma, taşıma, bırakma, kilit, seri bonusu |
| `src/server/SellService.luau` | Sunucu | Karakter satma |
| `src/server/RebirthService.luau` | Sunucu | Rebirth, kat açma |
| `src/server/UpgradeService.luau` | Sunucu | Oyun içi parayla üs yükseltmeleri |
| `src/server/MonetizationService.luau` | Sunucu | Gamepass, developer product, makbuz işleme |
| `src/server/BadgeService.luau` | Sunucu | Roblox rozetleri |
| `src/server/TitleService.luau` | Sunucu | Unvanlar, koşullar, ödüller |
| `src/server/SpinService.luau` | Sunucu | Şans çarkı, günlük hak |
| `src/server/TutorialService.luau` | Sunucu | Öğretici adımları, koşullar, ödüller |
| `src/server/QuestService.luau` | Sunucu | 30dk/3sa/günlük görevler, ilerleme, ödüller |
| `src/server/PotionService.luau` | Sunucu | İksir envanteri, içme, süreli takviyeler |
| `src/server/FloorService.luau` | Sunucu | Üst katların parayla satın alınması |
| `src/server/PromptGuard.luau` | Sunucu | Prompt tetiklemelerinin doğrulanması |
| `src/server/FriendService.luau` | Sunucu | Aynı sunucudaki arkadaş başına küçük gelir bonusu |
| `src/client/DeviceLayout.luau` | İstemci | Telefon/tablet/konsol: arayüz ölçeği, dokunmatik yerleşim, gamepad seçimi |
| `src/client/*` | İstemci | HUD, efekt, ses, mini harita, dekor |
| `tests/ServerTests.luau` | Sunucu (elle) | Regresyon testleri |

**Bağımlılık yönü:** `client → shared ← server`. Sunucu servisleri birbirini `script.Parent.<Servis>` ile çağırır. Shared modülleri hiçbir servise bağımlı değildir — bu yönü bozma.

---

## İki kişi çalışırken

İkimizin de Claude'u aynı Team Create place'ine bağlanıyor. Çakışmamak için:

### 1. Dosya sahipliği — BU KURAL BAĞLAYICI

```
Batur   : src/server/*       (plot, ekonomi, konveyör, çalma)
Diğeri  : src/client/*       (HUD, efektler, ses, kamera)
Ortak   : src/shared/*       -> dokunmadan önce haber ver
```

**Kendi şeridin dışına, karşı tarafa haber vermeden yazma.** Görev ne
olursa olsun. "Oyunu İngilizce yap" gibi her dosyaya dokunan işler
şeridi geçersiz kılmaz — böyle bir iş çıkarsa önce haber ver, ya da
sadece kendi şeridindeki dosyaları çevir.

> Bu kural bir kez gevşetildi ("ikimiz aynı anda yazmıyoruz zaten") ve
> hemen ardından HUD iki kez üst üste ezildi. Gevşetmeyin.

**Tek istisna: karşı taraf çalışmıyorken.** Kullanıcın karşı tarafın o an
çalışmadığını söylerse onun şeridine de yazabilirsin. Şartları:

1. Başlamadan `git pull` ve Studio'dakini dosyaya çekip `git diff` — fark
   varsa dur.
2. İş bitince **`DEVIR.md`'nin en üstüne kayıt ekle**: ne değişti, hangi
   dosyalar, karşı tarafın bilmesi gereken ne var. Sonra commit + push.

### Her oturumun başında: `DEVIR.md`

`git pull`'dan sonra `DEVIR.md`'yi oku. Son baktığından beri eklenen
kayıtlar karşı tarafın senin şeridinde yaptığı işler ve sana notlarıdır.
Kendi şeridinde yaptığın ama karşı tarafı ilgilendiren işleri de (yeni
remote, Config alanı, bağlanması gereken modül) oraya yaz.

### Dil kuralı
Oyuncunun gördüğü her metin **İngilizce** (karakter isimleri, promptlar,
bildirimler, leaderstats, HUD). Kod içi yorumlar **Türkçe**.

### 2. `PlotService.Start()` dünyayı sıfırlar
`Start()` içinde `workspace.Plots` varsa **siliniyor ve yeniden kuruluyor**. Team Create'te karşı taraf haritada elle bir şey yaptıysa o da gider.

Kural: **sunucu script'ini yeniden çalıştırmadan önce diğerine haber ver.** Elle yapılan dekor/harita işleri `workspace.Plots` dışında, ayrı bir klasörde dursun.

### 3. Drafts Mode — bu projede KAPALI
Team Create'te Drafts Mode açıksa script değişiklikleri taslakta bekler ve
commit edilmeden karşı tarafa gitmez. **Bu place'de kapalı.** Script
değişiklikleri anında replike oluyor — commit etmeye gerek yok, `View`
menüsünde `Drafts` girdisi de yok.

Pratikte anlamı: karşı taraf sen yazarken senin script'ini görüyor.
Koruma katmanı yok, dolayısıyla şerit kuralı ve "önce çek sonra bas"
kuralı tek güvenceniz.

### 4. Kim yeniden kuruyor
Aynı anda iki kişi `run_code` ile aynı şeyi kurmaya çalışırsa ikinci seferinde çift nesne oluşur. Dünyayı kuran komutu **tek kişi** çalıştırsın.

---

## Sync — dosya ↔ Studio

Rojo kurmaya gerek yok. Proje kökünde köprüyü başlat:

```bash
python tools/sync_server.py
```

`http://127.0.0.1:8788/` üzerinden çalışır: `GET` dosyayı Studio'ya verir,
`POST` Studio'daki kaynağı dosyaya geri yazar.

### ÖNCE ÇEK, SONRA BAS

> Tek yönlü sync bu projede bir kez veri kaybettirdi. Dosya → Studio
> yönünde 9 dosyayı birden basmak, karşı tarafın Team Create'te yaptığı
> işi sessizce siler.

Kural: **Studio'ya basmadan önce Studio'dakini dosyaya çek ve git ile
karşılaştır.** Beklemediğin bir fark varsa karşı taraf çalışmış demektir —
basma, önce konuş.

`POST` yönü (Studio → dosya), README sonundaki örneğin aynısıdır; sadece
`GetAsync` yerine `PostAsync` kullanır ve `inst.Source`'u gövde olarak yollar.

### Dosya → Studio

Sadece **kendi şeridindeki** dosyaları listeye koy. Aşağıdaki liste
hepsini içerir; kullanmadan önce kendine ait olmayanları sil:

```lua
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local SPS = game:GetService("StarterPlayer").StarterPlayerScripts

local shared, server, client = RS.Shared, SSS.Server, SPS.Client
local BASE = "http://127.0.0.1:8788/"

local mapping = {
	{ "src/client/CarryGuide.luau",             client.CarryGuide },
	{ "src/client/DecorFX.luau",                client.DecorFX },
	{ "src/client/FloorStyle.luau",             client.FloorStyle },
	{ "src/client/Index.luau",                  client.Index },
	{ "src/client/Leaderboard.luau",            client.Leaderboard },
	{ "src/client/Lobby.luau",                  client.Lobby },
	{ "src/client/Minimap.luau",                client.Minimap },
	{ "src/client/OwnerColors.luau",            client.OwnerColors },
	{ "src/client/PromptFilter.luau",           client.PromptFilter },
	{ "src/client/RarityFX.luau",               client.RarityFX },
	{ "src/client/ScreenFX.luau",               client.ScreenFX },
	{ "src/client/SoundFX.luau",                client.SoundFX },
	{ "src/client/ThiefTrail.luau",             client.ThiefTrail },
	{ "src/client/TutorialUI.luau",             client.TutorialUI },
	{ "src/client/QuestPanel.luau",             client.QuestPanel },
	{ "src/client/Menus.luau",                  client.Menus },
	{ "src/client/HudToggle.luau",              client.HudToggle },
	{ "src/client/UpgradePanel.luau",           client.UpgradePanel },
	{ "src/client/init.client.luau",            client },
	{ "src/server/ConveyorService.luau",        server.ConveyorService },
	{ "src/server/DataService.luau",            server.DataService },
	{ "src/server/EconomyService.luau",         server.EconomyService },
	{ "src/server/MonetizationService.luau",    server.MonetizationService },
	{ "src/server/PlotService.luau",            server.PlotService },
	{ "src/server/PromptGuard.luau",            server.PromptGuard },
	{ "src/server/RebirthService.luau",         server.RebirthService },
	{ "src/server/SellService.luau",            server.SellService },
	{ "src/server/StealService.luau",           server.StealService },
	{ "src/server/TutorialService.luau",        server.TutorialService },
	{ "src/server/QuestService.luau",           server.QuestService },
	{ "src/server/PotionService.luau",          server.PotionService },
	{ "src/server/FloorService.luau",           server.FloorService },
	{ "src/server/UpgradeService.luau",         server.UpgradeService },
	{ "src/server/init.server.luau",            server },
	{ "src/shared/Config.luau",                 shared.Config },
	{ "src/shared/Net.luau",                    shared.Net },
	{ "src/shared/UnitModel.luau",              shared.UnitModel },
}

for _, entry in mapping do
	local ok, result = pcall(function()
		return HttpService:GetAsync(BASE .. entry[1], true)
	end)
	if ok then
		entry[2].Source = result
		print("OK", entry[1], #result)
	else
		print("HATA", entry[1], result)
	end
end
```

`HttpService.HttpEnabled` kapalı olsa bile çalışıyor — plugin bağlamında `GetAsync` izinli.

**Yapı ilk kez kuruluyorsa** (place boşsa) önce kapları yarat: `ReplicatedStorage.Shared` (Folder), `ServerScriptService.Server` (Script), `StarterPlayerScripts.Client` (LocalScript), ve Shared altına `Config`/`Net`/`UnitModel`, Server altına `PlotService`/`EconomyService`/`ConveyorService`/`StealService` ModuleScript'leri.

## Kayıt (DataStore)

`src/server/DataService.luau` nakit, kaidedeki karakterler, çalma
sayısı, rebirth seviyesi, yükseltmeler ve satın alma makbuzlarını kalıcı
tutar.

**Studio'da çalışması için açılması gerekiyor:**
`File` → `Experience Settings` → `Security` → **Enable Studio Access to API Services**

Kapalıyken oyun çalışmaya devam eder ama hiçbir şey kaydedilmez; Output'ta
uyarı görürsün. Bu bilinçli — test ederken oyunu kilitlemesin diye.

**Tasarım:** DataService veriyi yorumlamaz. Diğer servisler kendi alanlarını
profil tablosunda doğrudan günceller (`EconomyService` → `profile.cash`,
`PlotService` → `profile.units`). DataService yalnızca yükler, kaydeder ve
oturum kilidini yönetir. Bu yüzden kayıt anında servisler arası çağrı yok.

**Oturum kilidi:** Çalınabilir eşya olan bir oyunda iki sunucunun aynı
profili yazması kopyalamaya yol açar. Profil `UpdateAsync` ile kilitleniyor;
kilit başka bir sunucudaysa oyuncu içeri alınmıyor, tekrar girmesi isteniyor.

**Sürüm:** Store adı `PlayerData_v2`. Profil şeması bozucu şekilde
değişirse numarayı artır — eski kayıtlar yanlış yorumlanmasın. v1'den v2'ye
kat başına kaide 8 -> 10 olduğu için geçildi, slot numaralandırması değişti.

## Regresyon testleri

`tests/ServerTests.luau` — 56 test, 300+ kontrol, ~2.3 saniye.

**Neden var:** bir kez basılı tutma doğrulaması yüzünden çalma ve satma
tamamen kırıldı ve ancak elle oynanarak fark edildi. İki kişi aynı sunucu
dosyalarına yazarken bu tekrar olacak.

**Her sunucu değişikliğinden sonra koş.** Önce dosyayı Studio'ya
`ServerScriptService.Server.Tests` olarak senkronize et, sonra MCP'nin
`run_script_in_play_mode` aracını `mode = "start_play"` ile kullan:

```lua
local Players = game:GetService("Players")

local player
for _ = 1, 60 do
	player = Players:GetPlayers()[1]
	if player and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then break end
	task.wait(0.5)
end
task.wait(4)

require(game.ServerScriptService.Server.Tests).Run(player)
```

`Run` başarısız kontrol sayısını döner; 0 ise temiz.

**Kapsam:** Config bütünlüğü · üs ve kaide yapısı · ekonomi · satın alma
ve satma · çalma kuralları · yükseltmeler · rebirth · para kazanma ·
prompt güvenliği · kayıt · unvanlar · öğretici · görevler · iksirler ·
üst kat satın alma.

Testler oyuncunun profilini geçici olarak değiştiriyor ama `Run` sonunda
başlangıç hali geri yükleniyor.

**Periyodik tarama yapan bir servis eklersen `SetPaused` de ekle ve
`Run`'da duraklat.** `TitleService`, `TutorialService` ve `QuestService`
saniyede bir profili tarayıp koşul sağlanmışsa ödül veriyor. Testler profili doğrudan
kurcaladığı için tarama araya girerse kazanılmamış ödül dağıtılıyor ve
nakit sayan testler tutmuyor — rebirth testi tam olarak böyle kaldı. `init.server` bu modülü require etmiyor,
yayına çıkan kodda hiçbir etkisi yok.

**Yeni özellik eklerken testini de ekle.** Dosyanın altındaki `case(...)`
kalıbı yeterli; testler sırayla koşuyor ve her biri ortamı kendi
kuruyor.

## Test etmek

Oyuncu gerektiren testler için MCP'nin `run_script_in_play_mode` aracını `mode = "start_play"` ile kullan — sunucu datamodel'inde çalışır, sonunda otomatik durur. Oyuncusuz birim testleri için `mode = "run_server"` yeterli.

Normal `run_code` **edit datamodel'inde** çalışır; `workspace.Plots` orada yoktur, çünkü üsleri sunucu çalışma anında kuruyor.

---

## Öğretici

Yeni oyuncu altı adımdan geçiyor: karakter al → ikinci kaideyi doldur →
birinden çal → üssünü kilitle → yükseltme al → çarkı çevir. Adımlar
`Config.Tutorial`'da veri; koşullar `TutorialService`'te.

Kurallar:

- **İlerleme sunucuda.** Profilde tek sayı: tamamlanan adım. İstemci
  yalnızca çiziyor, ilerlemeyi değiştiremiyor.
- **Adımlar var olan duruma bakıyor.** Hiçbir servis `TutorialService`'i
  çağırmıyor; bağımlılık tek yönlü, öğretici kaldırılsa oyun aynen çalışır.
- **Eski kayıtlar öğreticiye girmiyor.** Oynadığına dair iz varsa
  (`stolen`, `rebirths`, kaidede karakter, yükseltme, çark) öğretici ödül
  dağıtmadan bitmiş sayılıyor.
- **Atlamak ödül vermiyor.** `TutorialSkip` remote'u istemciden sunucuya
  dinlenen tek remote; kalan ödülleri yakmaktan başka etkisi yok.

Yeni adım eklemek `Config.Tutorial`'a bir satır ve gerekiyorsa
`TutorialService.checkValue` içine bir sayaç. `hint` alanının karşılığı
dünyada bulunamazsa hedef gösterilmiyor — testler bunu kontrol ediyor.

**Arayüz:** `src/client/TutorialUI.luau` hazır ama `init.client.luau`'ya
bağlı değil (istemci şeridi). Bağlanana kadar adımlar bildirim olarak
geliyor, yani öğretici tek başına çalışıyor.

Panel üç şey gösteriyor: yazılı adım, hedefin üstünde duran dünya oku ve
hedef görüş alanının dışındaysa ekranda dönen pusula oku + mesafe. Sadece
yazı yeterli değildi — oyuncu "konveyör" kelimesini okuyup hangi parçanın
konveyör olduğunu bilmiyor.

---

## Görevler

Üç vade: **30 dakika**, **3 saat**, **günlük**. Her vadede 2 görev, pencere
dolunca yeniden çekiliyor. `Config.Quests` havuzu, `Config.QuestTiers`
vadeler, koşullar `QuestService`'te.

- **İlerleme tabandan hesaplanıyor.** Görev verilirken sayacın o anki
  değeri kaydediliyor; ilerleme bugünkü değerle farkı. Bu yüzden görev
  sayaçlarının hepsi yalnızca ARTMALI — azalan bir sayaç tamamlanmış
  görevi tamamlanmamışa çevirir.
- **Hedefler çekim anında donuyor.** Canlı hesaplansaydı oyuncu
  zenginleştikçe hedef büyür, görev hiç bitmezdi.
- **Ödüller ödeme anındaki gelire göre.** Çekimde hesaplansaydı üç saatte
  büyüyen oyuncu üç saat önceki gelirine göre ödüllenirdi.
- **`fromTier` ve `maxGoal` var.** Yeni oyuncu 30 dakikada rebirth
  atamıyor; başkasının çalmasını bekleyen "hırsız yakala" görevinin
  tavanı düşük.

Yeni görev eklemek `Config.Quests`'e bir satır ve gerekiyorsa
`QuestService.statValue` içine artan bir sayaç.

---

## İksirler

Günlük vadenin **tamamını** bitiren bir iksir kazanıyor. Envantere
giriyor, anında uygulanmıyor — oyuncu ne zaman işine geliyorsa o zaman
içiyor.

**Hepsi süreli, kalıcı hiçbir şey verilmiyor.** Bunlar Robux pass'lerinin
karşılığı; süresiz bir tanesi bile pass satışını öldürür. Süreli olanı
tersine çalışıyor: on dakika iki kat kazanan oyuncu pass'in ne işe
yaradığını öğreniyor. Bir test bunu kontrol ediyor.

Pass'i olan oyuncuya iksir **üstüne binmiyor** — `MonetizationService`
ikisinin büyüğünü alıyor, yoksa parasını veren oyuncu bedava ödülle daha
da öne geçerdi.

Etki `MonetizationService`'te, pass'lerle aynı yerden okunuyor; böylece
"pass mi iksir mi" ayrımını her servis ayrı ayrı yapmıyor.

---

## Üst katlar

Kat artık rebirth ödülü **değil**. Rebirth katın kilidini açıyor, kat
oyun içi parayla satın alınıyor.

| Kat | Gereken rebirth | Fiyat |
|---|---|---|
| 1 | — | bedava |
| 2 | 1 | $5 milyar |
| 3 | 2 | $150 milyar |

Neden böyle: rebirth zaten kalıcı gelir çarpanı veriyordu, kat da bedava
gelince rebirth tek başına her şeydi ve biriken paranın rebirth dışında
harcanacak büyük bir yeri yoktu. Şimdi "5 milyarı 2. kata mı yatırayım
yoksa 8 milyarlık rebirth'e mi saklayayım" gerçek bir karar.

- **Satın alınan kat kalıcı.** Rebirth onu geri almıyor; parasını ödedi.
- **Sıralı.** 3. kat, 2. kat alınmadan satın alınamıyor — yoksa arada
  erişilemez bir kat kalırdı.
- **Eski kayıtlar katlarını kaybetmiyor.** `floorsBought` alanı sonradan
  eklendi; onsuz kaydedilmiş profile eski kuralın verdiği kadarı
  (`rebirths` kadar kat) hediye ediliyor.

Satın alma pedi rampanın dibinde ve yeri **rampadan türetiliyor**, elle
koordinat girilmiyor. Pedin kaydırma yönü üssün merkezinden hesaplanıyor:
alt sıradaki dört üs 180° dönük olduğu için sabit bir yön hiçbir zaman
ikisinde birden doğru olmuyor.

Fiyat değiştirmek `Config.FloorUnlocks`'ta bir satır. Bir test fiyatın,
o katı açan rebirth'lere harcanan toplamdan büyük kalmasını koruyor.

---

## Unvan kuşanma

Oyuncu açtığı unvanlardan istediğini takabiliyor. Elle seçim yaptıysa
(`titleManual`) sonradan daha yüksek bir unvan açılsa bile üstüne
yazılmıyor. Seçim yapmayan oyuncu en yükseğini otomatik takıyor — menüyü
hiç açmayan da ilerlemesini sohbette görsün diye.

Boş kimlik göndermek otomatiğe dönüyor.

---

## İstemci panelleri

Hepsi `Create(screen)` kalıbında, `init.client.luau`'ya bağlanmayı
bekliyor (istemci şeridi):

```lua
local TutorialUI = require(script.TutorialUI)
local QuestPanel = require(script.QuestPanel)
local Menus      = require(script.Menus)
local HudToggle  = require(script.HudToggle)

local tutorial = TutorialUI.Create(screen)
local quests   = QuestPanel.Create(screen)
local menus    = Menus.Create(screen)
local hud      = HudToggle.Create(screen)  -- EN SONA: diğerlerini bulması gerekiyor
```

| Modül | Yer | İş |
|---|---|---|
| `TutorialUI` | Sol alt + dünya oku | Öğretici adımı ve hedef |
| `QuestPanel` | Sol, nakit satırının altı | Üç vadeli görev listesi, katlanabilir |
| `Menus` | Sağ, üs panelinin altı | Unvan seçimi ve iksir envanteri (sekmeli) |
| `HudToggle` | Sağ üst | Kalabalık yapanları gizle (`H` tuşu) |

`HudToggle` arayüz öğelerini **adıyla** buluyor, kimsenin koduna
dokunmuyor. Listesinde olmayan bir panel gizlenmiyor; yeni panel eklerken
adını `CLUTTER` listesine yaz.

---

## Harita (The Skeld)

Harita tamamen koddan kuruluyor: `tools/build_decor.luau` yükleyici,
bölümler `tools/map/*.luau` (station, bays, rooms, landmarks, exterior,
lobby, wings, finish). Ortak ölçüler, palet ve Skeld duvarı/kapısı
`tools/map/kit.luau` içinde. Oda renkleri ve adları `Config.BayRooms`
(PlotService üs zeminini de aynı renge boyuyor).

Sync sunucusu açıkken Studio'da (run_code):

```lua
-- _G.MAP_ONLY = { "lobby" }   -- yalnızca bir bölümü yeniden kurmak için
local src = game:GetService("HttpService"):GetAsync("http://127.0.0.1:8788/tools/build_decor.luau")
loadstring(src)()
_G.MAP_ONLY = nil
```

Kurulumun sonunda `tools/map/check.luau` ölçerek denetim yapıyor: aynı
düzlemde çakışan yüzler (titreme) ve üslerin oyun alanına giren katı
parçalar. Rapor `cakisan yuz: 0 | oyun alani ihlali: 0` olmalı.

Kodun adıyla aradığı parçalar (değiştirirken koru): `Hatchery.Egg1..4 /
PodRing / PodScreen / FuseCore`, `GearShop.GearCounter / GearPlinth1..3`,
`Wheel` (Model) `.WheelHub`, `TeleportPad.PadColumn`, `Boards.BoardScreenN.Display`,
`Lobby.LobbyDeck`, `Plots.PlotN.PodiumPad / FrameX / FrameZ / PillarBand / HatchHood`,
`Doorways.DoorGlowN`, `BayMarkers.BayPadN`.

---

## Denge ayarları

Hepsi `src/shared/Config.luau` içinde, tek yerde:

- `ConveyorInterval` — kaç saniyede bir yeni karakter (varsayılan 10)
- `PodiumsPerPlot` — üs başına kaide sayısı (varsayılan 8)
- `StealHoldTime` / `StealCooldown` — çalma zorluğu
- `SafeSeconds` — yeni konan karakterin dokunulmazlık süresi
- `LockDuration` / `LockCooldown` — savunma dengesi
- `Config.Units` — karakter listesi (fiyat, gelir, çıkma ağırlığı)
- `Config.Mutations` — mutasyon şansları ve gelir çarpanları
