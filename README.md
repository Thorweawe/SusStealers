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

### 1. Dosya sahipliği
Bir dosyayı aynı anda iki kişi düzenlemez. Kim neyi aldıysa yazsın:

```
Batur  : src/server/*        (plot, ekonomi, konveyör, çalma)
Arkadaş: src/client/*        (HUD, efektler, ses, kamera)
Ortak  : src/shared/Config   -> değişiklik önce konuşulur
```

`Config.luau` ortak kullanılan tek dosya. Yeni karakter/mutasyon eklemek isteyen önce haber versin.

### 2. `PlotService.Start()` dünyayı sıfırlar
`Start()` içinde `workspace.Plots` varsa **siliniyor ve yeniden kuruluyor**. Team Create'te karşı taraf haritada elle bir şey yaptıysa o da gider.

Kural: **sunucu script'ini yeniden çalıştırmadan önce diğerine haber ver.** Elle yapılan dekor/harita işleri `workspace.Plots` dışında, ayrı bir klasörde dursun.

### 3. Draft commit
Team Create'te script değişiklikleri taslak olarak durur. Her iş bitiminde:
`View → Drafts → Commit`
Commit edilmeyen script karşı tarafa gitmez.

### 4. Kim yeniden kuruyor
Aynı anda iki kişi `run_code` ile aynı şeyi kurmaya çalışırsa ikinci seferinde çift nesne oluşur. Dünyayı kuran komutu **tek kişi** çalıştırsın.

---

## Rojo ile çalışmak (opsiyonel)

Team Create kullanıyorsanız Rojo'ya gerek yok — kod doğrudan MCP ile place'e basılır. Yine de dosyadan senkron isterseniz:

```bash
rojo serve default.project.json
```

Studio'da Rojo plugin'inden `Connect`.

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
