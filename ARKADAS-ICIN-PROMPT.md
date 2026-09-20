# Arkadaşın Claude'una atılacak prompt

Aşağıdaki metni olduğu gibi kopyalayıp arkadaşın kendi Claude Code oturumuna yapıştırsın.

---

Merhaba. Bir arkadaşımla birlikte bir Roblox oyunu yapıyoruz ve onun Claude'u projeyi kurdu. Sen de aynı projede çalışacaksın. Durum şu:

## Oyun

**Sus Stealers** — Among Us temalı, "Steal a Brainrot" tarzı bir Roblox oyunu.

Döngü: Konveyörden karakter satın al → kendi üssündeki kaideye koy → karakter saniyede para bassın → rakibin üssüne gir, kaidesinden karakterini söküp sırtında taşı → kendi kaidene bırak. Savunma için üssünü geçici olarak kilitleyebiliyorsun.

## Kod

Kod arkadaşımın bilgisayarında `SusStealers` klasöründe. Sana repo linkini ayrıca verecek — klonla ve `README.md`'yi oku, modül haritası orada.

Mimari özeti:

| Dosya | Sorumluluğu |
|---|---|
| `src/shared/Config.luau` | Tüm denge sayıları, 16 karakter, 5 mutasyon, para formatı |
| `src/shared/Net.luau` | RemoteEvent yaratma/erişim |
| `src/shared/UnitModel.luau` | Among Us karakterini koddan üretir (hazır asset yok) |
| `src/server/init.server.luau` | Açılış, servis sırası |
| `src/server/PlotService.luau` | Üsleri kurar, oyunculara dağıtır, kaide durumu |
| `src/server/EconomyService.luau` | Nakit, leaderstats, saniyelik gelir |
| `src/server/ConveyorService.luau` | Konveyör üretimi, kaydırma, satın alma |
| `src/server/StealService.luau` | Çalma, taşıma, bırakma, kilit savunması |
| `src/client/init.client.luau` | HUD, bildirim şeridi |

Bağımlılık yönü: `client → shared ← server`. Shared modülleri hiçbir servise bağımlı değil, bu yönü bozma. Sunucu servisleri birbirini `script.Parent.<Servis>` ile çağırıyor.

Denge değiştirmek istersen **sadece `Config.luau`**'ya dokun, sayılar hep orada tutuluyor.

## Kurulumum

Roblox Studio MCP sunucusunu kurmam lazım ki sen Studio'ya doğrudan kod basabilesin. Şunu indirip bir kez çalıştıracağım (Studio plugin'ini kendi kuruyor):

```
https://github.com/Roblox/studio-rust-mcp-server/releases/download/v0.2.365/rbx-studio-mcp.exe
```

Sonra Studio'yu ve Claude'u yeniden başlatacağım. Kurulum tamamlanınca sana haber veririm, `get_studio_mode` ile bağlantıyı doğrularsın.

Not: Bu repo Nisan 2026'da arşivlendi ama binary çalışıyor. Roblox'un yerine koyduğu gömülü MCP sunucusu henüz her hesaba açılmadı — bizde çıkmadı.

## Birlikte çalışma kuralları

Arkadaşımla şöyle çalışıyoruz: **biri yazarken diğeri test ediyor.** Aynı anda ikimiz kod yazmıyoruz, o yüzden dosya çakışması derdi yok. Ama şu iki şeye dikkat et:

**1. Team Create'te script'ler taslakta durur.** Sen script oluşturduktan/değiştirdikten sonra bana söyle, `View → Drafts → Commit All` yapayım. Commit edilmeyen değişiklik karşı tarafa gitmez — yoksa onlar eski kodu test edip düzeltilmiş bug'ları bize bildirir.

**2. `PlotService.Start()` haritayı siliyor.** İçinde `workspace.Plots` varsa yok edip sıfırdan kuruyor. Karşı taraf test ederken bunu çalıştırma — önce haber ver. Elle yapılan dekor/harita işleri `Plots` klasörünün **dışında**, ayrı bir klasörde dursun ki silinmesin.

**3. Dünyayı tek kişi kursun.** İkimiz aynı anda kurulum kodu çalıştırırsak her nesne çift oluşur.

## Nasıl çalışmanı istiyorum

- Studio'ya kod basarken MCP'nin `run_code` aracını kullan
- Test için `start_stop_play`, hata bakmak için `get_console_output`
- Değişikliği hem Studio'ya bas **hem de** repodaki dosyaya yaz — iki taraf senkron kalsın, yoksa diğer Claude eski kodu okur
- Bir şeyi değiştirmeden önce `README.md`'ye bak, mimari orada

Başlamadan önce repoyu klonlayıp README'yi oku, sonra ne üzerinde çalışacağımızı konuşalım.
