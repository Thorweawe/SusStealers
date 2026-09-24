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
