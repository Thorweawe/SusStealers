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
| `src/server/PromptGuard.luau` | Sunucu | Prompt tetiklemelerinin doğrulanması |
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
prompt güvenliği · kayıt · unvanlar · öğretici.

Testler oyuncunun profilini geçici olarak değiştiriyor ama `Run` sonunda
başlangıç hali geri yükleniyor.

**Periyodik tarama yapan bir servis eklersen `SetPaused` de ekle ve
`Run`'da duraklat.** `TitleService` ve `TutorialService` saniyede bir
profili tarayıp koşul sağlanmışsa ödül veriyor. Testler profili doğrudan
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
geliyor, yani öğretici tek başına çalışıyor. Bağlamak için:

```lua
local TutorialUI = require(script.TutorialUI)
local tutorial = TutorialUI.Create(screen)
```

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
