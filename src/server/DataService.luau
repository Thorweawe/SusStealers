--!strict
-- Oyuncu verisinin kalıcılığı: nakit, kaidedeki karakterler, çalma sayısı.
--
-- Tasarım: bu modül veriyi yorumlamaz. Diğer servisler kendilerine ait
-- alanları profil tablosunda doğrudan günceller (EconomyService profile.cash,
-- PlotService profile.units). DataService yalnızca yükler, kaydeder ve
-- oturum kilidini yönetir. Böylece kayıt anında başka servise çağrı yok,
-- bağımlılık tek yönlü kalıyor.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local DataService = {}

-- v2: kat başına kaide sayısı 8 -> 10 oldu (bonus slotlar), slot
-- numaralandırması değişti. v1 kayıtları yanlış kaideye düşerdi.
local STORE_NAME = "PlayerData_v2"
local AUTOSAVE_INTERVAL = 120
local LOCK_TIMEOUT = 180      -- kilit bu kadar saniye tazelenmezse ölü sayılır
local LOAD_RETRIES = 4

export type StoredUnit = {
	slot: number,
	unitId: string,
	mutationId: string?,
}

export type Profile = {
	version: number,
	cash: number,
	stolen: number,
	rebirths: number,
	units: { StoredUnit },
	-- Çevrimdışı gelir hesabı için: son görülme ve o andaki kazanç hızı
	lastSeen: number,
	incomePerSecond: number,
	-- İşlenmiş satın alma kimlikleri; aynı makbuzun iki kez ödüllenmesini
	-- engelliyor. Config.ReceiptHistoryLimit kadar tutuluyor.
	receipts: { string },
	-- Üs yükseltmeleri: id -> seviye
	upgrades: { [string]: number },
	-- Son bedava çark çevirme anı (os.time)
	lastSpinAt: number,
	-- Unvanlar: açılanların kümesi ve takılı olanın id'si
	titles: { [string]: boolean },
	activeTitle: string,
	-- Unvan koşullarının baktığı sayaçlar
	robbed: number,
	caught: number,
	maxStreak: number,
	-- Öğreticide tamamlanan adım sayısı. #Config.Tutorial ise bitmiş,
	-- -1 ise oyuncu atlamış. Sayı olarak tutuluyor çünkü adımlar sıralı.
	tutorialStep: number,
	-- Oyuncu unvanı kendi eliyle seçtiyse true. O andan sonra yeni unvan
	-- açılsa bile üstüne yazmıyoruz; seçim oyuncunun.
	titleManual: boolean,
	-- Görev sayaçları. Hepsi yalnızca ARTIYOR: görev ilerlemesi, görev
	-- verilirken alınan tabanla bugünkü değerin farkından hesaplanıyor.
	-- Azalan bir sayaç ilerlemeyi geri götürür.
	bought: number,
	sold: number,
	spins: number,
	earned: number,
	-- Vade -> o vadedeki görevler ve pencerenin bitiş anı (os.time)
	quests: { [string]: QuestSlot },
	-- İksir envanteri: iksir kimliği -> adet
	potions: { [string]: number },
	-- Satın alınmış üst kat sayısı (1. kat bedava, sayıya dahil değil)
	floorsBought: number,
	--[[
		Pet envanteri: anahtar -> adet. Anahtar "MiniCrew" ya da
		"MiniCrew:Golden" (Config.PetKey) — mutasyonlu kopya ayrı satır.

		Adet tutuluyor çünkü yumurtadan aynı pet tekrar çıkabiliyor ve
		kopyayı sessizce yakmak "yumurta boşa gitti" hissi veriyordu.
		İleride birleştirme (fuse) gelirse kopyalar zaten burada duruyor.
	]]
	pets: { [string]: number },
	--[[
		Takılı petler, SIRALI. Sıra önemli: sahada hangi petin nereye
		dizileceğini o belirliyor ve oyuncu sıralamayı kendi kuruyor.
		Uzunluğu Config.PetEquipSlots ile sınırlı.
	]]
	equippedPets: { string },
	--[[
		İndekste KEŞFEDİLMİŞ karakterler: kimlik -> true. Konveyörde
		görülen ya da bir kaideye konan her karakter giriyor, hiç çıkmıyor.

		Eskiden "görüldü" bilgisi istemcide oturum boyunca tutuluyordu ve
		her girişte sıfırlanıyordu; indeks bir koleksiyon değil, o anki
		kaidelerin listesiydi.
	]]
	discovered: { [string]: boolean },
	-- Günlük seri: art arda kaç gün toplandı ve en son hangi gün (UTC gün no)
	dailyStreak: number,
	lastDailyDay: number,
	-- Oynama süresi hediyeleri: hangi günün sayacı, o gün kaç saniye
	-- oynandı ve hangi hediyeler (sıra no) toplandı
	playtimeDay: number,
	playtimeSeconds: number,
	playtimeClaimed: { [string]: boolean },
	-- İndeks ödülleri: toplanan nadirlik satırları
	indexClaimed: { [string]: boolean },
	-- Satın alınmış ekipman (Gear Shop): kimlik -> true. Kalıcı; rebirth'te
	-- sıfırlanmıyor, bir kez alınan alet hep geliyor.
	gear: { [string]: boolean },
	-- Kozmetikler: sahip olunanlar (kimlik -> true) ve takılı şapka / iz.
	-- Boş dize = takılı değil. Kalıcı; rebirth'te sıfırlanmıyor.
	cosmetics: { [string]: boolean },
	hat: string,
	trail: string,
	-- Sabotaj eşyaları: kimlik -> adet (en fazla Config.SabotageMaxStack).
	-- Tek kullanımlık; rebirth'te sıfırlanmıyor (parayla alındı).
	sabotages: { [string]: number },
	-- Son sabotaj kullanımı (unix saati); bekleme çıkıp girince sıfırlanmasın
	lastSabotageAt: number,
	-- Başlangıç ekranındaki ayarlar (SettingsService); oyuna güç vermiyor.
	-- autoDelete: yumurtadan çıkınca envantere girmeden silinecek kademeler
	settings: { music: number, sfx: number, shake: boolean, autoDelete: { [string]: boolean } },
	-- Pet indeksi: bir kez bile elde edilmiş (ya da otomatik silinmiş) pet kimlikleri
	petsFound: { [string]: boolean },
}

export type QuestEntry = {
	id: string,
	goal: number,
	baseline: number,
	done: boolean,
	-- Ödül TESLİM ALINDI mı. done koşulun sağlandığını, claimed oyuncunun
	-- ödülü kendi eliyle aldığını söylüyor; ikisi ayrı çünkü arada
	-- oyuncunun düğmeye basması var.
	claimed: boolean,
}

export type QuestSlot = {
	expiresAt: number,
	entries: { QuestEntry },
}

type Lock = { owner: string, at: number }
type Record = { profile: Profile, lock: Lock? }

local store: DataStore? = nil
local storeAvailable = false

-- Studio'da her oturum ayrı sayılsın diye JobId bos ise kendimiz uretiyoruz
local SESSION_ID = if game.JobId ~= "" then game.JobId else "studio-" .. tostring(os.time())

local profiles: { [Player]: Profile } = {}
local loading: { [Player]: boolean } = {}
local offlineEarnings: { [Player]: { amount: number, seconds: number } } = {}

-- Aynı anahtara çok sık yazmak DataStore kuyruğunu dolduruyor
local SAVE_MIN_INTERVAL = 7
local lastSaveAt: { [Player]: number } = {}
local pendingSave: { [Player]: boolean } = {}

-- ─── Varsayılan ─────────────────────────────────────────────────────────────

local function newProfile(): Profile
	return {
		version = 1,
		cash = Config.StartingCash,
		stolen = 0,
		rebirths = 0,
		units = {},
		lastSeen = 0,
		incomePerSecond = 0,
		receipts = {},
		upgrades = {},
		lastSpinAt = 0,
		titles = {},
		activeTitle = "",
		robbed = 0,
		caught = 0,
		maxStreak = 0,
		tutorialStep = 0,
		titleManual = false,
		bought = 0,
		sold = 0,
		spins = 0,
		earned = 0,
		quests = {},
		potions = {},
		floorsBought = 0,
		pets = {},
		equippedPets = {},
		discovered = {},
		dailyStreak = 0,
		lastDailyDay = 0,
		playtimeDay = 0,
		playtimeSeconds = 0,
		playtimeClaimed = {},
		indexClaimed = {},
		gear = {},
		cosmetics = {},
		hat = "",
		trail = "",
		sabotages = {},
		lastSabotageAt = 0,
		settings = {
			music = Config.DefaultSettings.music,
			sfx = Config.DefaultSettings.sfx,
			shake = Config.DefaultSettings.shake,
			autoDelete = {},
		},
		petsFound = {},
	}
end

--[[
	Diskten gelen tabloyu güvenli hale getirir. Eski sürüm, eksik alan veya
	bozuk veri gelirse oyuncuyu patlatmak yerine varsayılana düşer.
]]
local function sanitize(raw: any): Profile
	if typeof(raw) ~= "table" then
		return newProfile()
	end

	local profile = newProfile()

	if typeof(raw.cash) == "number" and raw.cash == raw.cash and raw.cash >= 0 then
		profile.cash = math.floor(raw.cash)
	end

	if typeof(raw.stolen) == "number" and raw.stolen >= 0 then
		profile.stolen = math.floor(raw.stolen)
	end

	if typeof(raw.rebirths) == "number" and raw.rebirths >= 0 then
		profile.rebirths = math.floor(raw.rebirths)
	end

	if typeof(raw.lastSeen) == "number" and raw.lastSeen > 0 then
		profile.lastSeen = math.floor(raw.lastSeen)
	end

	if typeof(raw.incomePerSecond) == "number" and raw.incomePerSecond >= 0 then
		profile.incomePerSecond = raw.incomePerSecond
	end

	if typeof(raw.receipts) == "table" then
		for _, id in raw.receipts do
			if typeof(id) == "string" then
				table.insert(profile.receipts, id)
			end
		end
	end

	if typeof(raw.lastSpinAt) == "number" and raw.lastSpinAt > 0 then
		profile.lastSpinAt = math.floor(raw.lastSpinAt)
	end

	for _, field in { "robbed", "caught", "maxStreak", "bought", "sold", "spins", "earned" } do
		local value = (raw :: any)[field]
		if typeof(value) == "number" and value >= 0 then
			(profile :: any)[field] = math.floor(value)
		end
	end

	if typeof(raw.titles) == "table" then
		for id, unlocked in raw.titles do
			-- Config'ten kalkmış bir unvan kayıtta durabilir
			if typeof(id) == "string" and unlocked == true and Config.GetTitle(id) then
				profile.titles[id] = true
			end
		end
	end

	if typeof(raw.activeTitle) == "string" and Config.GetTitle(raw.activeTitle) then
		profile.activeTitle = raw.activeTitle
	end

	-- -1 (atlandı) ile adım sayısı arasında kalmalı. Config'ten adım
	-- silinirse eski kayıt aralık dışı kalır; kırpmak öğreticiyi bitmiş
	-- saymaktan daha doğru, çünkü kalan adımlar hâlâ öğretilmeli.
	if typeof(raw.tutorialStep) == "number" and raw.tutorialStep == raw.tutorialStep then
		profile.tutorialStep = math.clamp(math.floor(raw.tutorialStep), -1, #Config.Tutorial)
	end

	profile.titleManual = raw.titleManual == true

	--[[
		Katlar eskiden doğrudan rebirth ödülüydü; şimdi parayla alınıyor.

		Eski kayıtta floorsBought alanı yok ve 0 geliyor. Onu olduğu gibi
		kabul etmek, rebirth atmış oyuncunun katlarını elinden almak
		olurdu — üstelik üstünde karakteri varken. Eski kuralın verdiği
		kadarını hediye ediyoruz.
	]]
	if typeof(raw.floorsBought) == "number" and raw.floorsBought >= 0 then
		profile.floorsBought = math.clamp(math.floor(raw.floorsBought), 0, Config.MaxFloors - 1)
	else
		profile.floorsBought = math.clamp(profile.rebirths, 0, Config.MaxFloors - 1)
	end

	if typeof(raw.potions) == "table" then
		for id, count in raw.potions do
			-- Config'ten kalkmış iksir kayıtta durabilir
			if typeof(id) == "string" and Config.GetPotion(id)
				and typeof(count) == "number" and count > 0
			then
				profile.potions[id] = math.clamp(math.floor(count), 0, Config.PotionStackLimit)
			end
		end
	end

	--[[
		Petler. İksirle aynı kalıp: Config'ten kalkmış pet kayıtta durabilir,
		tanınmayan atlanıyor.

		Takılı liste AYRICA süzülüyor ve sahip olunmayan pet atılıyor — kayıt
		elle kurcalanmış olsa bile bonus, sahip olunmayan bir petten gelemez.
	]]
	if typeof(raw.pets) == "table" then
		for key, count in raw.pets do
			-- Anahtar "pet" ya da "pet:mutasyon" (Config.PetKey); ikisi de
			-- tanınmalı, yoksa satır atılıyor
			if typeof(key) == "string" and (Config.ParsePetKey(key)) ~= nil
				and typeof(count) == "number" and count > 0
			then
				profile.pets[key] = math.clamp(math.floor(count), 0, Config.PetStackLimit)
			end
		end
	end

	if typeof(raw.equippedPets) == "table" then
		-- Aynı pet birden fazla takılı olabilir: elde olan kopya kadar
		local used: { [string]: number } = {}
		for _, id in raw.equippedPets do
			if #profile.equippedPets >= Config.PetEquipSlots then
				break
			end
			if typeof(id) == "string" and (used[id] or 0) < (profile.pets[id] or 0) then
				used[id] = (used[id] or 0) + 1
				table.insert(profile.equippedPets, id)
			end
		end
	end

	--[[
		Görevler: Config'ten kalkmış görev ya da vade kayıtta durabilir.
		Tanınmayanı atıyoruz; QuestService boş vadeyi yeniden çekiyor, yani
		oyuncu görevsiz kalmıyor.
	]]
	if typeof(raw.quests) == "table" then
		for tierId, slot in raw.quests do
			if typeof(tierId) ~= "string"
				or not Config.GetQuestTier(tierId)
				or typeof(slot) ~= "table"
				or typeof(slot.expiresAt) ~= "number"
				or typeof(slot.entries) ~= "table"
			then
				continue
			end

			local entries: { QuestEntry } = {}
			for _, entry in slot.entries do
				if typeof(entry) == "table"
					and typeof(entry.id) == "string"
					and Config.GetQuest(entry.id)
					and typeof(entry.goal) == "number"
					and typeof(entry.baseline) == "number"
				then
					table.insert(entries, {
						id = entry.id,
						goal = math.max(1, math.floor(entry.goal)),
						baseline = math.max(0, math.floor(entry.baseline)),
						done = entry.done == true,
						--[[
							Alan sonradan eklendi. Eski kayıtta done=true olan
							görevin ödülü ZATEN VERİLMİŞTİ (o zaman otomatikti),
							yani alınmış saymalıyız — yoksa oyuncu aynı ödülü
							bir kez daha toplardı.
						]]
						claimed = if entry.claimed ~= nil
							then entry.claimed == true
							else entry.done == true,
					})
				end
			end

			if #entries > 0 then
				profile.quests[tierId] = {
					expiresAt = math.floor(slot.expiresAt),
					entries = entries,
				}
			end
		end
	end

	if typeof(raw.upgrades) == "table" then
		for id, level in raw.upgrades do
			local def = typeof(id) == "string" and Config.GetUpgrade(id)
			if def and typeof(level) == "number" and level > 0 then
				-- Tavan kat sayısına bağlı; kayıtta oyunun mutlak tavanına
				-- kırpıyoruz, kat kontrolü satın alma anında yapılıyor
				profile.upgrades[id] = math.clamp(
					math.floor(level), 0, Config.GetUpgradeCeiling(def))
			end
		end
	end

	if typeof(raw.units) == "table" then
		for _, entry in raw.units do
			if typeof(entry) == "table"
				and typeof(entry.slot) == "number"
				and typeof(entry.unitId) == "string"
				-- Config'ten silinmiş bir karakter kayıtta kalmış olabilir
				and Config.GetUnit(entry.unitId) ~= nil
			then
				local mutationId: string? = nil
				if typeof(entry.mutationId) == "string" and Config.GetMutation(entry.mutationId) then
					mutationId = entry.mutationId
				end

				table.insert(profile.units, {
					slot = math.floor(entry.slot),
					unitId = entry.unitId,
					mutationId = mutationId,
				})
			end
		end
	end

	--[[
		Keşif listesi. Alan sonradan eklendi; eski kayıtta yok. O yüzden
		kaidelerde duran karakterler de keşfedilmiş sayılıyor — oyuncunun
		elindeki bir karakterin indekste "???" görünmesi saçma olurdu.
	]]
	if typeof(raw.discovered) == "table" then
		for id, flag in raw.discovered do
			if typeof(id) == "string" and flag == true and Config.GetUnit(id) then
				profile.discovered[id] = true
			end
		end
	end
	for _, stored in profile.units do
		profile.discovered[stored.unitId] = true
	end

	--[[ Ödül sayaçları. Sayılar negatif ya da bozuksa sıfırdan başlıyor:
	     en kötü ihtimalle oyuncu bir seriyi kaybeder, fazladan ödül almaz. ]]
	local function count(value: any): number
		return if typeof(value) == "number" and value == value and value >= 0 then math.floor(value) else 0
	end
	profile.dailyStreak = count(raw.dailyStreak)
	profile.lastDailyDay = count(raw.lastDailyDay)
	profile.playtimeDay = count(raw.playtimeDay)
	profile.playtimeSeconds = count(raw.playtimeSeconds)

	if typeof(raw.playtimeClaimed) == "table" then
		for index, flag in raw.playtimeClaimed do
			local n = tonumber(index)
			if n and Config.PlaytimeRewards[n] and flag == true then
				profile.playtimeClaimed[tostring(n)] = true
			end
		end
	end
	if typeof(raw.indexClaimed) == "table" then
		for rarity, flag in raw.indexClaimed do
			if typeof(rarity) == "string" and Config.IndexRewards[rarity] and flag == true then
				profile.indexClaimed[rarity] = true
			end
		end
	end
	if typeof(raw.gear) == "table" then
		for id, flag in raw.gear do
			if typeof(id) == "string" and Config.GetGear(id) and flag == true then
				profile.gear[id] = true
			end
		end
	end
	--[[
		Kozmetikler. Takılı olan AYRICA süzülüyor: sahip olunmayan ya da
		Config'ten kalkmış bir şey takılı kalmasın, türü de doğru olmalı.
	]]
	if typeof(raw.cosmetics) == "table" then
		for id, flag in raw.cosmetics do
			if typeof(id) == "string" and Config.GetCosmetic(id) and flag == true then
				profile.cosmetics[id] = true
			end
		end
	end
	for _, slot in { "hat", "trail" } do
		local id = (raw :: any)[slot]
		local def = if typeof(id) == "string" then Config.GetCosmetic(id) else nil
		if def and def.kind == slot and profile.cosmetics[id] then
			(profile :: any)[slot] = id
		end
	end

	if typeof(raw.sabotages) == "table" then
		for id, count in raw.sabotages do
			if typeof(id) == "string" and Config.GetSabotage(id)
				and typeof(count) == "number" and count > 0
			then
				profile.sabotages[id] = math.clamp(math.floor(count), 0, Config.SabotageMaxStack)
			end
		end
	end
	if typeof(raw.lastSabotageAt) == "number" then
		profile.lastSabotageAt = raw.lastSabotageAt
	end

	if typeof(raw.settings) == "table" then
		local s = raw.settings
		for _, key in { "music", "sfx" } do
			local v = s[key]
			if typeof(v) == "number" and v == v then
				(profile.settings :: any)[key] = math.clamp(v, 0, 1)
			end
		end
		if typeof(s.shake) == "boolean" then
			profile.settings.shake = s.shake
		end
		if typeof(s.autoDelete) == "table" then
			for rarity, on in s.autoDelete do
				if typeof(rarity) == "string" and Config.Rarities[rarity] and on == true then
					profile.settings.autoDelete[rarity] = true
				end
			end
		end
	end

	if typeof(raw.petsFound) == "table" then
		for id, on in raw.petsFound do
			if typeof(id) == "string" and on == true and Config.GetPet(id) then
				profile.petsFound[id] = true
			end
		end
	end

	return profile
end

-- ─── Kilit ──────────────────────────────────────────────────────────────────

local function lockIsForeign(lock: Lock?): boolean
	if not lock then
		return false
	end
	if lock.owner == SESSION_ID then
		return false
	end
	return (os.time() - lock.at) < LOCK_TIMEOUT
end

-- ─── Yükleme ────────────────────────────────────────────────────────────────

local function keyFor(player: Player): string
	return "player_" .. tostring(player.UserId)
end

--[[
	Profili yükler ve oturum kilidini alır. Başka bir sunucu kilidi
	tutuyorsa birkaç kez dener. Çalınabilir eşya olan bir oyunda iki
	sunucunun aynı profili yazması kopyalamaya yol açar, o yüzden
	kilit alınamazsa nil döner.
]]
local function loadProfile(player: Player): Profile?
	if not storeAvailable then
		return newProfile()
	end

	local key = keyFor(player)

	for attempt = 1, LOAD_RETRIES do
		local ok, result = pcall(function()
			return (store :: DataStore):UpdateAsync(key, function(old: Record?): Record?
				local record: Record = old or { profile = newProfile() }

				if lockIsForeign(record.lock) then
					return nil -- iptal: kilit baskasinda
				end

				record.profile = sanitize(record.profile)
				record.lock = { owner = SESSION_ID, at = os.time() }
				return record
			end)
		end)

		if ok and result then
			return sanitize((result :: Record).profile)
		end

		if not ok then
			warn(string.format("[Data] %s yuklenemedi (deneme %d): %s", player.Name, attempt, tostring(result)))
		end

		if attempt < LOAD_RETRIES then
			task.wait(2 * attempt)
		end
	end

	return nil
end

-- ─── Kaydetme ───────────────────────────────────────────────────────────────

--[[ Profili diske yazar. releaseLock true ise oturum kilidini de bırakır. ]]
local function saveProfile(player: Player, releaseLock: boolean): boolean
	local profile = profiles[player]
	if not profile or not storeAvailable then
		return false
	end

	-- Yazarken profil değişebilir; anlık kopya al
	profile.lastSeen = os.time()

	--[[
		═══ ALANLARI TEK TEK YAZMIYORUZ ═══════════════════════════════════

		Burası bir alan listesiydi ve liste GERİDE KALMIŞTI: tutorialStep,
		titleManual, bought/sold/spins/earned, quests, potions ve
		floorsBought snapshot'a hiç girmiyordu. Yani diske yazılmıyorlardı
		— oyuncu her oturumda öğreticiye sıfırdan başlıyor, iksirlerini ve
		görev ilerlemesini kaybediyordu. floorsBought'un kaybı
		görünmüyordu çünkü sanitize onu rebirth sayısından tahmin ediyor.

		Artık profilin TAMAMI kopyalanıyor. Yeni bir alan eklemek için
		burayı güncellemek gerekmiyor; unutulması mümkün olan adım ortadan
		kalktı.

		Tablolar ayrıca kopyalanıyor: table.clone sığ, yani iç tabloları
		paylaşırdık ve UpdateAsync beklerken oyuncu bir iksir içse diske
		yazılan veri değişirdi.
	]]
	local snapshot: Profile = table.clone(profile)
	snapshot.units = table.clone(profile.units)
	snapshot.receipts = table.clone(profile.receipts)
	snapshot.upgrades = table.clone(profile.upgrades)
	snapshot.titles = table.clone(profile.titles)
	snapshot.potions = table.clone(profile.potions)
	snapshot.discovered = table.clone(profile.discovered)
	snapshot.playtimeClaimed = table.clone(profile.playtimeClaimed)
	snapshot.indexClaimed = table.clone(profile.indexClaimed)
	snapshot.gear = table.clone(profile.gear)
	snapshot.cosmetics = table.clone(profile.cosmetics)
	snapshot.sabotages = table.clone(profile.sabotages)
	snapshot.settings = table.clone(profile.settings)
	snapshot.settings.autoDelete = table.clone(profile.settings.autoDelete)
	snapshot.petsFound = table.clone(profile.petsFound)
	snapshot.pets = table.clone(profile.pets)
	snapshot.equippedPets = table.clone(profile.equippedPets)

	-- Görevler iki kat derin: vade -> entries -> görev
	local quests: { [string]: QuestSlot } = {}
	for tierId, slot in profile.quests do
		local entries: { QuestEntry } = {}
		for _, entry in slot.entries do
			table.insert(entries, table.clone(entry))
		end
		quests[tierId] = { expiresAt = slot.expiresAt, entries = entries }
	end
	snapshot.quests = quests

	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(keyFor(player), function(old: Record?): Record?
			local record: Record = old or {} :: any

			if lockIsForeign(record.lock) then
				return nil -- baskasinin oturumunun ustune yazma
			end

			record.profile = snapshot
			record.lock = if releaseLock then nil else { owner = SESSION_ID, at = os.time() }
			return record
		end)
	end)

	if not ok then
		warn(string.format("[Data] %s kaydedilemedi: %s", player.Name, tostring(err)))
	end
	return ok
end

-- ─── Dışa açık API ──────────────────────────────────────────────────────────

function DataService.Get(player: Player): Profile?
	return profiles[player]
end

--[[ Profil yüklenene kadar bekler. Yükleme başarısızsa nil döner. ]]
function DataService.WaitForProfile(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 20)

	while os.clock() < deadline do
		if profiles[player] then
			return profiles[player]
		end
		if not loading[player] and player.Parent == nil then
			return nil
		end
		task.wait(0.1)
	end

	return profiles[player]
end

--[[
	Profildeki sayısal bir sayacı artırır.

	Servislerin her biri "profili al, alan var mı bak, artır" kalıbını
	tekrarlıyordu. Sayaç görev ilerlemesinin tabanı olduğu için yanlış
	yazılan bir alan adı sessizce hiçbir şey yapardı; burada assert var.
]]
function DataService.Bump(player: Player, field: string, amount: number?)
	local profile = profiles[player]
	if not profile then
		return
	end

	local any = profile :: any
	local current = any[field]
	assert(typeof(current) == "number", "DataService.Bump: sayısal olmayan alan " .. field)

	any[field] = current + (amount or 1)
end

function DataService.Save(player: Player): boolean
	return saveProfile(player, false)
end

--[[
	Kaydı ister ama arka arkaya gelen istekleri birleştirir.

	Roblox anahtar başına yaklaşık 6 saniyede bir yazmaya izin veriyor;
	daha sık yazmak kuyruğa giriyor ve kuyruk dolunca istekler düşüyor.
	Unvan açılması gibi olaylar kümelenebildiği için (girişte birden
	fazla unvan birden açılabiliyor) her biri ayrı yazma isteyemez.

	Son yazmadan bu yana yeterli süre geçtiyse hemen yazar, geçmediyse
	tek bir gecikmeli yazma planlar. Veri kaybolmuyor, sadece saniyeler
	içinde diske iniyor.
]]
function DataService.RequestSave(player: Player)
	local now = os.clock()
	local last = lastSaveAt[player] or 0

	if now - last >= SAVE_MIN_INTERVAL then
		lastSaveAt[player] = now
		saveProfile(player, false)
		return
	end

	if pendingSave[player] then
		return
	end
	pendingSave[player] = true

	task.delay(SAVE_MIN_INTERVAL - (now - last), function()
		pendingSave[player] = nil
		if profiles[player] then
			lastSaveAt[player] = os.clock()
			saveProfile(player, false)
		end
	end)
end

--[[ DataStore kullanılabiliyor mu. Studio'da API Services kapalıysa false. ]]
function DataService.IsAvailable(): boolean
	return storeAvailable
end

-- ─── Yaşam döngüsü ──────────────────────────────────────────────────────────

local function onPlayerAdded(player: Player)
	loading[player] = true

	local profile = loadProfile(player)

	if player.Parent == nil then
		loading[player] = nil
		return
	end

	if not profile then
		loading[player] = nil
		player:Kick("Your data is still saving from another server. Please rejoin in a minute.")
		return
	end

	-- Çevrimdışı kazanç: profil kullanıma açılmadan ÖNCE eklenmeli ki
	-- EconomyService nakdi okuduğunda birikmiş tutar zaten içinde olsun.
	local away = if profile.lastSeen > 0 then os.time() - profile.lastSeen else 0
	local earned = Config.GetOfflineEarnings(profile.incomePerSecond, away)
	if earned > 0 then
		profile.cash += earned
		offlineEarnings[player] = { amount = earned, seconds = away }
	end

	profiles[player] = profile
	loading[player] = nil

	DataService.PublishDiscovered(player)
end

--[[
	Keşif listesini istemciye nitelik olarak yayınlar: virgülle ayrılmış
	kimlikler. Ayrı bir remote yerine nitelik, çünkü yirmi beş kısa
	kimlik küçük bir metin ve nitelik zaten replike oluyor.
]]
function DataService.PublishDiscovered(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local ids = {}
	for id in profile.discovered do
		table.insert(ids, id)
	end
	table.sort(ids)
	player:SetAttribute("Discovered", table.concat(ids, ","))
end

--[[
	Karakteri oyuncunun indeksine ekler. Zaten varsa bir şey yapmıyor,
	yani sık çağrılması ucuz (konveyör her üretimde çağırıyor).
]]
function DataService.Discover(player: Player, unitId: string)
	local profile = profiles[player]
	if not profile or profile.discovered[unitId] or not Config.GetUnit(unitId) then
		return
	end
	profile.discovered[unitId] = true
	DataService.PublishDiscovered(player)
end

--[[ Bu oturumda çevrimdışı kazanç verildiyse tutarı döner, sonra unutur. ]]
function DataService.ConsumeOfflineEarnings(player: Player): (number, number)
	local entry = offlineEarnings[player]
	if not entry then
		return 0, 0
	end
	offlineEarnings[player] = nil
	return entry.amount, entry.seconds
end

local function onPlayerRemoving(player: Player)
	saveProfile(player, true)
	profiles[player] = nil
	loading[player] = nil
	offlineEarnings[player] = nil
	lastSaveAt[player] = nil
	pendingSave[player] = nil
end

function DataService.Start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)

	if ok and result then
		store = result
		-- GetDataStore, API Services kapaliyken de basarili olabiliyor;
		-- gercek erisimi kucuk bir okumayla dogruluyoruz.
		local reachable = pcall(function()
			(result :: DataStore):GetAsync("__probe")
		end)
		storeAvailable = reachable
	end

	if not storeAvailable then
		warn("[Data] DataStore kapali - veriler bu oturumda kaydedilmeyecek. "
			.. "Studio'da: Game Settings > Security > Enable Studio Access to API Services")
	end

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Periyodik kayıt: çökme durumunda kaybı sınırlar, kilidi de tazeler
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_INTERVAL)
			for _, player in Players:GetPlayers() do
				if profiles[player] then
					saveProfile(player, false)
				end
			end
		end
	end)

	-- Sunucu kapanırken herkesi kaydet. Roblox burada 30 saniye tanıyor.
	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end

		local pending = 0
		for _, player in Players:GetPlayers() do
			if profiles[player] then
				pending += 1
				task.spawn(function()
					saveProfile(player, true)
					pending -= 1
				end)
			end
		end

		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
