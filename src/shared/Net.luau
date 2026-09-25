--!strict
-- Remote'ları tek yerden yaratır/verir. Sunucu yaratır, istemci bekler.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

-- Sadece gerçekten kullanılanlar. Boş duran bir RemoteEvent, ileride
-- doğrulamasız bir handler bağlanmasını davet ediyor.
--
-- Yön önemli: server -> client olanlar güvenli, istemci onları tetikleyemez.
-- İstemciden sunucuya dinlenen tek remote TutorialSkip ve o da hiçbir şey
-- vermiyor — sadece oyuncunun kendi öğreticisini kapatıyor, kalan ödülleri
-- yakarak. Yani istismarı oyuncunun kendi zararına.
local EVENTS = {
	"Notify",       -- server -> client (text, isError)
	"StealAlert",   -- server -> client (thiefName, unitName)
	"Tutorial",     -- server -> client (payload, target)
	"Titles",       -- server -> client (açık unvanlar, takılı olan)
	"Quests",       -- server -> client (vade -> görev listesi)
	"Potions",      -- server -> client (envanter + aktif takviye)
	"Pets",         -- server -> client (sahip olunanlar + takılı sıra)
	"PetHatched",   -- server -> client (keys: {string}, source: "egg" | "fuse", fromKey: string? — egg: yumurta kimliği, fuse: birleşen anahtar)
	"Summons",      -- server -> client (text: string) — Summons sohbet kanalı
	"Rewards",      -- server -> client (günlük seri + oynama süresi durumu)
	"TutorialSkip", -- client -> server (argümansız)
	"TitleEquip",   -- client -> server (titleId: string)
	"PotionUse",    -- client -> server (potionId: string)
	"QuestClaim",   -- client -> server (tierId: string, questId: string)
	"UpgradeBuy",   -- client -> server (upgradeId: string)
	"FloorBuy",     -- client -> server (argumansiz)
	"RebirthBuy",   -- client -> server (argumansiz)
	"PetHatch",     -- client -> server (eggId: string)
	"PetEquip",     -- client -> server (key: string, equip: boolean)
	"PetFuse",      -- client -> server (key: string)
	"RewardClaim",  -- client -> server (kind: "daily"|"playtime"|"index", arg)
	"GearBuy",      -- client -> server (gearId: string)
	"Sprint",       -- client -> server (active: boolean)
	"AsteroidsDone", -- client -> server (argumansiz) — Weapons görevi bitti
	"TaskDone",     -- client -> server (taskId: string) — ek oda görevi bitti
	"CosmeticAction", -- client -> server (action: "buy"|"equip"|"unequip", id: string)
	"SabotageAction", -- client -> server (action: "buy"|"use", id: string, targetUserId: number?)
	"SettingsSave", -- client -> server (settings: { music: number, sfx: number, shake: boolean })
}

--[[
	İstemciden sunucuya DİNLENEN remote'lar. Buraya bir isim eklemek yeni
	bir saldırı yüzeyi açmak demek: istemci onu istediği argümanla,
	istediği sıklıkta tetikleyebiliyor.

	Kural: buradaki her remote sunucuda doğrulanıyor ve sınırlanıyor.
	Hiçbiri oyuncuya bedava bir şey VEREMİYOR — biri öğreticiyi kapatıyor
	(kalan ödülleri yakarak), biri zaten açılmış bir unvanı takıyor, biri
	envanterdeki bir iksiri harcıyor, biri de oyuncunun KENDİ parasını
	kendi üssünde harcıyor.

	UpgradeBuy yeni bir yüzey açmıyor: aynı işlem zaten tezgâhtaki
	ProximityPrompt ile yapılabiliyordu ve doğrulama aynı yerde
	(UpgradeService.TryUpgrade) — üs sahibi mi, seviye tavanda mı, parası
	yetiyor mu. Prompt yerine arayüz geçti, kontrol aynı kaldı.
]]
local CLIENT_TO_SERVER = {
	TutorialSkip = true,
	TitleEquip = true,
	PotionUse = true,
	--[[
		QuestClaim bedava bir şey vermiyor: yalnızca SUNUCUNUN tamamlanmış
		saydığı bir görevin ödülünü teslim ediyor. Koşulu istemci değil
		QuestService.Check belirliyor; burası sadece "aldım" diyor.
	]]
	QuestClaim = true,
	UpgradeBuy = true,
	FloorBuy = true,
	RebirthBuy = true,
	--[[
		PetHatch oyuncunun KENDİ parasını harcıyor: fiyatı ve çekilişi
		sunucu yapıyor (PetService.TryHatch), istemci yalnızca hangi
		yumurta olduğunu söylüyor ve o kimlik Config'de aranıyor.
		Tanınmayan kimlik reddediliyor.

		PetEquip hiçbir şey vermiyor, zaten SAHİP OLUNAN bir peti takıp
		çıkarıyor. Sahiplik profilden doğrulanıyor ve slot sayısı
		sunucuda sınırlanıyor.

		PetFuse üç kopyayı YAKIP bir tane veriyor: adet sunucuda sayılıyor,
		sonuç sunucuda çekiliyor. İstemci yalnızca hangi anahtar olduğunu
		söylüyor; üç kopyası yoksa istek reddediliyor.
	]]
	PetHatch = true,
	PetEquip = true,
	PetFuse = true,
	--[[
		RewardClaim bedava bir şey VERMİYOR: hak sunucudaki sayaçlardan
		hesaplanıyor (gün numarası, oynanan saniye, keşif listesi) ve
		toplanan ödül profile işaretleniyor. İstemci yalnızca "şunu
		topluyorum" diyor; hakkı yoksa reddediliyor (RewardService).

		GearBuy oyuncunun KENDİ parasını harcıyor; fiyat ve sahiplik
		sunucuda (GearService.TryBuy).
	]]
	RewardClaim = true,
	GearBuy = true,
	--[[
		Sprint yalnızca bir bayrak; hızı sunucu belirliyor ve TAŞIRKEN
		reddediyor. Roblox'ta oyuncu zaten kendi WalkSpeed'ini istemciden
		değiştirebiliyor, yani bu remote yeni bir kaçak açmıyor — tersine,
		koşmayı sunucunun bildiği ve sınırladığı bir şey haline getiriyor.
	]]
	Sprint = true,
	--[[
		AsteroidsDone küçük bir ödül veriyor ve sonucu istemci söylüyor —
		bu yüzden bütün sınırlar sunucuda (MinigameService.TryComplete):
		  - oyun SUNUCUDA başlamış olmalı: konsoldaki prompt tetiklenince
		    başlangıç zamanı sunucuda yazılıyor, istemci başlatamıyor
		  - en kısa süre (20 asteroit 8 sn'den hızlı vurulamaz)
		  - başlangıçtan en fazla 4 dk geçmiş olmalı
		  - iki ödül arası bekleme süresi (90 sn)
		  - oyuncu konsolun yakınında olmalı
		Ödül gelirle ölçekli ve küçük (45 sn'lik gelir); sahte istek en
		fazla bekleme süresi başına bir kez işe yarar, o da oyunu oynamakla
		aynı kazanç.
	]]
	AsteroidsDone = true,
	--[[
		TaskDone, AsteroidsDone'ın aynısı ama ek odalardaki görevler için
		(TaskService.TryComplete): başlangıç sunucuda (konsol promptu), en
		kısa süre, en uzun süre, görev başına bekleme ve konsola yakınlık
		sunucuda. Kimlik Config.Tasks'ta aranıyor; tanınmayan reddediliyor.
		Ödül küçük (60 sn'lik gelir, 10 dk'da bir) — sahte istek, görevi
		oynamaktan fazlasını kazandıramıyor.
	]]
	TaskDone = true,
	--[[
		CosmeticAction bedava bir şey VERMİYOR: "buy" oyuncunun KENDİ parasını
		harcıyor (fiyat Config'te, sunucuda okunuyor), "equip" yalnızca sahip
		olunan bir kozmetiği takıyor, "unequip" çıkarıyor. Kozmetik güç
		vermiyor; kimlik Config'te aranıyor, tanınmayan reddediliyor
		(CosmeticService). Üç iş tek remote'ta: yüzeyi büyütmemek için.
	]]
	CosmeticAction = true,
	--[[
		SabotageAction bedava bir şey VERMİYOR: "buy" oyuncunun KENDİ parasını
		harcıyor (fiyat gelire göre, sunucuda; yığın sınırı sunucuda), "use"
		envanterdeki bir eşyayı harcıyor. Hedefe verdiği zarar sunucuda
		sınırlanıyor: kendine olmaz, boş üsse olmaz, aynı üsse 90 sn'de bir,
		oyuncu başına 45 sn'de bir, etki en fazla 45 sn (SabotageService).
	]]
	SabotageAction = true,
	--[[
		SettingsService hiçbir şey VERMİYOR, yalnızca oyuncunun KENDİ
		tercihlerini profile yazıyor: ses/sarsıntı ve yumurtadan çıkınca
		silinecek pet kademeleri (autoDelete — yalnızca kendi gelecekteki
		petlerini etkiliyor, mutasyonlular hiç silinmiyor). Değerler sunucuda
		sınırlanıyor (0..1, boolean, tanınan kademe), bilinmeyen alan yok
		sayılıyor, sıklık sınırlı.
	]]
	SettingsSave = true,
}

local Net = {}

local folder: Folder
if IS_SERVER then
	folder = ReplicatedStorage:FindFirstChild("Net") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Net"
		folder.Parent = ReplicatedStorage
	end

	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Net") :: Folder
end

--[[ Bu remote istemciden sunucuya mı dinleniyor. Testler buna bakıyor. ]]
function Net.IsClientToServer(name: string): boolean
	return CLIENT_TO_SERVER[name] == true
end

--[[ İstemciden sunucuya dinlenen remote adları. ]]
function Net.GetClientToServer(): { string }
	local names = {}
	for name in CLIENT_TO_SERVER do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

--[[ İsimle remote verir. İstemcide hazır olana kadar bekler. ]]
function Net.Get(name: string): RemoteEvent
	if IS_SERVER then
		local remote = folder:FindFirstChild(name)
		assert(remote, string.format("Net: no remote named '%s'", name))
		return remote :: RemoteEvent
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

return Net
