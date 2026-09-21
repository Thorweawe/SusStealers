# Sus Stealers

Among Us temalı "Steal a Brainrot" tarzı Roblox oyunu.

**Döngü:** Konveyörden karakter al → kaideye koy → saniyelik para bassın → rakibin üssüne girip karakterini çal → kendi kaidene bırak.

---

## Modül haritası

| Dosya | Nerede çalışır | Sorumluluğu |
|---|---|---|
| `src/shared/Config.luau` | Her yerde | Tüm denge sayıları, 16 karakter, 5 mutasyon, para formatı |
| `src/shared/Net.luau` | Her yerde | RemoteEvent yaratma/erişim |
| `src/shared/UnitModel.luau` | Her yerde | Among Us karakterini koddan üretir + isim etiketi |
| `src/server/init.server.luau` | Sunucu | Açılış, servis sırası |
| `src/server/PlotService.luau` | Sunucu | Üsleri kurar, oyunculara dağıtır, kaide durumu |
| `src/server/EconomyService.luau` | Sunucu | Nakit, leaderstats, saniyelik gelir |
| `src/server/ConveyorService.luau` | Sunucu | Konveyör üretimi, kaydırma, satın alma |
| `src/server/StealService.luau` | Sunucu | Çalma, taşıma, bırakma, kilit savunması |
| `src/client/init.client.luau` | İstemci | HUD, bildirim şeridi |

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
	{ "src/shared/Config.luau",          shared.Config },
	{ "src/shared/Net.luau",             shared.Net },
	{ "src/shared/UnitModel.luau",       shared.UnitModel },
	{ "src/server/init.server.luau",     server },
	{ "src/server/PlotService.luau",     server.PlotService },
	{ "src/server/EconomyService.luau",  server.EconomyService },
	{ "src/server/ConveyorService.luau", server.ConveyorService },
	{ "src/server/StealService.luau",    server.StealService },
	{ "src/client/init.client.luau",     client },
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

`src/server/DataService.luau` nakit, kaidedeki karakterler ve çalma
sayısını kalıcı tutar.

**Studio'da çalışması için açılması gerekiyor:**
`Game Settings` → `Security` → **Enable Studio Access to API Services**

Kapalıyken oyun çalışmaya devam eder ama hiçbir şey kaydedilmez; Output'ta
uyarı görürsün. Bu bilinçli — test ederken oyunu kilitlemesin diye.

**Tasarım:** DataService veriyi yorumlamaz. Diğer servisler kendi alanlarını
profil tablosunda doğrudan günceller (`EconomyService` → `profile.cash`,
`PlotService` → `profile.units`). DataService yalnızca yükler, kaydeder ve
oturum kilidini yönetir. Bu yüzden kayıt anında servisler arası çağrı yok.

**Oturum kilidi:** Çalınabilir eşya olan bir oyunda iki sunucunun aynı
profili yazması kopyalamaya yol açar. Profil `UpdateAsync` ile kilitleniyor;
kilit başka bir sunucudaysa oyuncu içeri alınmıyor, tekrar girmesi isteniyor.

**Sürüm:** Store adı `PlayerData_v1`. Profil şeması bozucu şekilde
değişirse adı `_v2` yap — eski kayıtlar bozulmasın.

## Test etmek

Oyuncu gerektiren testler için MCP'nin `run_script_in_play_mode` aracını `mode = "start_play"` ile kullan — sunucu datamodel'inde çalışır, sonunda otomatik durur. Oyuncusuz birim testleri için `mode = "run_server"` yeterli.

Normal `run_code` **edit datamodel'inde** çalışır; `workspace.Plots` orada yoktur, çünkü üsleri sunucu çalışma anında kuruyor.

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
