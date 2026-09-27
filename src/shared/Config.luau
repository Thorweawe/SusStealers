--!strict
-- Tüm oyun dengesi burada. Yeni karakter / mutasyon eklemek için sadece bu dosya.

local Config = {}

-- ─── Dünya ──────────────────────────────────────────────────────────────────
Config.PlotCount = 8
Config.PodiumsPerPlot = 8

--[[
	Üs ölçüsü 60x44'ten 72x52'ye büyüdü. Sebep: üssün üstünde artık
	kaidelerin yanı sıra merdiven, yükseltme kulübesi ve bonus kaideler de
	var; eski ölçüde her şey birbirinin dibindeydi. Kaideler arası boşluk da
	6.5'ten 7.5'e çıktı — komşu karakterlerin şapkaları birbirine giriyordu.
]]
Config.PlotSize = Vector3.new(72, 2, 52)
Config.PodiumSpacing = 7.5
--[[
	Ön/arka kaide sırasının üs merkezine uzaklığı.

	Burada duruyor çünkü İKİ yer birden kullanıyor: PlotService gerçek
	kaideleri, build_decor da altlarındaki pedleri buna göre koyuyor.
	Ayrı ayrı yazılıydı (9 ve 8) ve bir stud kayıyorlardı — pedler
	kaidelerin altından taşıyordu.
]]
Config.PodiumRowZ = 9

--[[
	Üsler ızgara halinde diziliyor: soldan sağa PlotColumns tane, sonra alt
	satıra geçiliyor. Tek sıra istersen PlotColumns'u PlotCount'a eşitle.

	Tek sıra (8x1) harita 644x108 stud'luk bir şerit yapıyordu; 25:1 oranında
	her şey yassı görünüyor, duvar ve pencere gibi detaylar kayboluyordu.
	4x2 ızgarada harita derinleşiyor ve istasyon gibi duruyor.

	Boşluklar üs ölçüsünden büyük olmalı, yoksa üsler bitişik görünür:
	PlotSpacing - PlotSize.X = yanal boşluk, PlotRowSpacing - PlotSize.Z = dikey.
]]
Config.PlotColumns = 4
--[[
	2026-09-27: üslerin olduğu alan genişledi (120/116 → 136/128). Odalar
	(kit.luau ROOM_HX 42 → 50) de büyüdü, koridor yine 36. Launch Bay
	kapısı (Config.Space.GateX) buradan türetiliyor. Değiştirince haritayı
	yeniden kur (README "Harita").
]]
Config.PlotSpacing = 136       -- yanal boşluk 64 stud (üs 72 geniş)
Config.PlotRowSpacing = 128    -- dikey boşluk 76 stud (üs 52 derin)

--[[
	Üs odaları: harita The Skeld, her üs bir Skeld odası. Sıra üs numarasına
	göre (1-4 arka satır, 5-8 ön satır). Skeld'de motorlar solda üst üste
	durduğu için 1 ve 5 motor odaları; aralarındaki koridor ucunda Reaktör.

	İki yer kullanıyor: harita kurucusu (tools/map) oda zeminini, tabelayı
	ve eşyaları buna göre kuruyor; PlotService üssün zeminini aynı renge
	boyuyor. Renk burada tek yerde, yoksa üs ile oda ayrı tonda kalıyordu.
]]
export type BayRoom = {
	id: string,        -- eşya seti (aynı id aynı eşyalar)
	name: string,      -- tabelada yazan ad
	tile: Color3,      -- zemin karosu
	tile2: Color3,     -- dama deseninin ikinci tonu
	grout: Color3,     -- karo arası oluk
	accent: Color3,    -- odanın vurgu rengi (şerit, ekran)
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Config.BayRooms = {
	{ id = "Engine", name = "UPPER ENGINE", tile = rgb(170, 154, 138), tile2 = rgb(156, 141, 126), grout = rgb(108, 96, 86), accent = rgb(240, 136, 52) },
	{ id = "Security", name = "SECURITY", tile = rgb(116, 176, 140), tile2 = rgb(104, 162, 128), grout = rgb(66, 110, 84), accent = rgb(90, 230, 150) },
	{ id = "Comms", name = "COMMUNICATIONS", tile = rgb(132, 154, 190), tile2 = rgb(120, 142, 178), grout = rgb(78, 96, 126), accent = rgb(120, 206, 255) },
	{ id = "O2", name = "O2", tile = rgb(116, 184, 174), tile2 = rgb(104, 170, 160), grout = rgb(66, 118, 110), accent = rgb(120, 244, 204) },
	{ id = "Engine", name = "LOWER ENGINE", tile = rgb(170, 154, 138), tile2 = rgb(156, 141, 126), grout = rgb(108, 96, 86), accent = rgb(240, 136, 52) },
	{ id = "Electrical", name = "ELECTRICAL", tile = rgb(184, 170, 116), tile2 = rgb(168, 154, 102), grout = rgb(116, 104, 64), accent = rgb(255, 214, 60) },
	{ id = "Admin", name = "ADMIN", tile = rgb(180, 118, 126), tile2 = rgb(164, 104, 112), grout = rgb(110, 64, 72), accent = rgb(110, 240, 150) },
	{ id = "Shields", name = "SHIELDS", tile = rgb(220, 200, 156), tile2 = rgb(204, 184, 142), grout = rgb(146, 126, 94), accent = rgb(255, 216, 80) },
} :: { BayRoom }

function Config.GetBayRoom(index: number): BayRoom
	return Config.BayRooms[(index - 1) % #Config.BayRooms + 1]
end

--[[
	Weapons odasındaki "Clear Asteroids" görevi (Among Us'taki görevin
	aynısı): topçu konsoluna gel, ekrandan geçen asteroitleri vur.

	Ödül gelirle ölçekleniyor ki her aşamada anlamlı kalsın ama çalmanın
	yerini tutmasın: 3 dakikalık gelir, en az $1000. Ödül 20 dakikada bir
	alınabiliyor (arada oyun oynanabiliyor, ödülsüz); en kısa süre de oyunu
	gerçekten oynamayı gerektiriyor (20 asteroit 8 saniyeden hızlı
	vurulamıyor — daha hızlı gelen istek sahte sayılıyor).
]]
Config.AsteroidTask = {
	goal = 20,            -- vurulacak asteroit
	minSeconds = 8,       -- bundan hızlı bitirilemez (sahte istek)
	maxSeconds = 240,     -- konsoldan başlanan oyun bu kadar geçerli
	cooldown = 1200,      -- iki ödül arası (20 dk)
	rewardSeconds = 180,  -- ödül = saniyelik gelir × bu
	minReward = 1000,
	range = 45,           -- bitirirken konsola en fazla bu kadar uzak
}

--[[
	Ek odalardaki (Storage, Laboratory) Among Us görevleri. Asteroit göreviyle
	aynı kurallar: konsoldan başlanıyor (sunucu saati tutuyor), en kısa süre
	var (oynamadan bitirilemez), bekleme süresi var, konsolun yakınında
	olmak gerekiyor. Ödül küçük: görevler oyunun özü değil, arada bir sapma.

	minSeconds — bundan hızlı bitirilemez (sahte istek)
	maxSeconds — konsoldan başlanan görev bu kadar geçerli
	cooldown   — aynı görevin iki ödülü arası
	rewardSeconds — ödül = saniyelik gelir × bu (en az minReward)
]]
export type TaskDef = {
	id: string,
	name: string,
	room: string,
	minSeconds: number,
	maxSeconds: number,
	cooldown: number,
	rewardSeconds: number,
	minReward: number,
	range: number,
}

Config.Tasks = {
	{ id = "Fuel",   name = "Fuel Engines", room = "Storage",    minSeconds = 3, maxSeconds = 180, cooldown = 600, rewardSeconds = 60, minReward = 500, range = 16 },
	{ id = "Wiring", name = "Fix Wiring",   room = "Storage",    minSeconds = 2, maxSeconds = 180, cooldown = 600, rewardSeconds = 60, minReward = 500, range = 16 },
	{ id = "Card",   name = "Swipe Card",   room = "Laboratory", minSeconds = 1, maxSeconds = 180, cooldown = 600, rewardSeconds = 60, minReward = 500, range = 16 },
} :: { TaskDef }

function Config.GetTask(id: string): TaskDef?
	for _, def in Config.Tasks do
		if def.id == id then
			return def
		end
	end
	return nil
end

--[[
	Oyuncu ayarları (başlangıç ekranındaki SETTINGS). Profilde saklanıyor,
	sunucu oyuncuya "Setting<Ad>" niteliği olarak yazıyor, istemci okuyor.
	Ses seviyeleri 0..1 çarpan: grubun kendi taban seviyesiyle çarpılıyor.
]]
Config.DefaultSettings = {
	music = 1,
	sfx = 1,
	shake = true,
	pets = true,     -- başka oyuncuların petleri görünsün
	myPets = true,   -- kendi petlerin görünsün (kapalıyken bonus sürüyor, yalnızca görünmüyor)
	lowGfx = false,  -- düşük grafik: gölge, parçacık ve ışık efektleri kapalı
}

-- ─── Ekonomi ────────────────────────────────────────────────────────────────
Config.StartingCash = 250
Config.IncomeInterval = 1

--[[
	Konveyör 2026-09-27'de kaldırıldı: karakterler artık uzaydaki
	canavarlardan çalınıyor (Config.Space, SpaceService). Üssün arkasındaki
	bant yerine uzay hızını geliştiren kapsül duruyor (Config.Capsule).
]]

-- ─── Yürüme (gemide) ───────────────────────────────────────────────────────
--[[
	2026-09-28: oyuncudan çalma kalktı (kaideden çalma, taşıma, "Stop
	Thief", kilit, çalma serisi, sabotajlar). Karakterler yalnızca uzaydaki
	canavarlardan çalınıyor (Config.Space). Gemide kalan tek şey yürüme hızı.
]]
Config.NormalWalkSpeed = 16
-- Shift ile koşma (mobilde RUN düğmesi)
Config.SprintWalkSpeed = 24

-- ─── Şans çarkı ─────────────────────────────────────────────────────────────
--[[
	Günde bir bedava çevirme, fazlası Robux ile. Ödüller sabit tutar değil,
	oyuncunun kendi gelirinin katı: sabit olsaydı geç oyunda anlamsızlaşır,
	erken oyunda dengeyi bozardı. Taban değerler yeni oyuncu için.

	Her dilimde bir şey çıkıyor, boş dilim yok.
]]
Config.SpinCooldownHours = 24
Config.SpinDuration = 5            -- çark kaç saniyede yavaşlayıp ödülde duruyor

export type SpinReward = {
	id: string,
	name: string,
	weight: number,
	kind: string,            -- cash | spawn | mutation | unit
	incomeSeconds: number?,  -- cash: kaç saniyelik gelir
	minimum: number?,        -- cash: taban tutar
}

Config.SpinRewards = {
	{ id = "SmallCash",  name = "Cash",              weight = 40, kind = "cash",     incomeSeconds =  40, minimum =   1000 },
	{ id = "MedCash",    name = "Big Cash",          weight = 25, kind = "cash",     incomeSeconds = 150, minimum =   8000 },
	-- spawn/mutation/unit: karakter doğrudan kaideye (SpaceService.GrantUnit)
	{ id = "Spawn",      name = "Free Crewmate",     weight = 15, kind = "spawn" },
	{ id = "Mutation",   name = "Mutated Crewmate",  weight = 12, kind = "mutation" },
	{ id = "HugeCash",   name = "Huge Cash",         weight =  6, kind = "cash",     incomeSeconds = 420, minimum =  60000 },
	-- Jackpot: bir üst canavarın havuzundan
	{ id = "FreeUnit",   name = "Jackpot Crewmate",  weight =  2, kind = "unit" },
} :: { SpinReward }

--[[
	Çarkın 12 dilimi, saat yönünün tersine (tools/map/lobby.luau SLICES ile
	aynı sayı). Yalnızca görünüş: ödülü yukarıdaki ağırlıklar seçiyor, çark
	o ödülün dilimlerinden birinde duruyor (shared/WheelSpin). Her ödül en
	az bir dilimde olmalı — yoksa çark onu gösteremez (test var).
]]
Config.SpinWheelSlices = {
	"SmallCash", "Spawn", "MedCash", "Mutation", "SmallCash", "HugeCash",
	"MedCash", "Spawn", "SmallCash", "Mutation", "MedCash", "FreeUnit",
}

--[[ Dilimlerin rengi ve yazısı: salondaki çark (SpinService) ve pencere (SpinPanel). ]]
Config.SpinSliceLook = {
	SmallCash = { color = Color3.fromRGB(88, 200, 74), text = "CASH", icon = "💵" },
	MedCash = { color = Color3.fromRGB(40, 150, 230), text = "BIG CASH", icon = "💰" },
	HugeCash = { color = Color3.fromRGB(255, 190, 30), text = "HUGE CASH", icon = "💎" },
	Spawn = { color = Color3.fromRGB(245, 120, 30), text = "CREWMATE", icon = "👾" },
	Mutation = { color = Color3.fromRGB(160, 80, 235), text = "MUTATED", icon = "✨" },
	FreeUnit = { color = Color3.fromRGB(230, 45, 70), text = "JACKPOT", icon = "🏆" },
} :: { [string]: { color: Color3, text: string, icon: string } }

--[[ Çarkta ağırlıklı ödül seçer. ]]
function Config.RollSpinReward(rng: Random): SpinReward
	local total = 0
	for _, reward in Config.SpinRewards do
		total += reward.weight
	end

	local roll = rng:NextNumber(0, total)
	for _, reward in Config.SpinRewards do
		roll -= reward.weight
		if roll <= 0 then
			return reward
		end
	end
	return Config.SpinRewards[1]
end

--[[ Nakit ödülünün tutarı. Gelir düşükse taban değer geçerli. ]]
function Config.GetSpinCash(reward: SpinReward, incomePerSecond: number): number
	local scaled = incomePerSecond * (reward.incomeSeconds or 0)
	return math.floor(math.max(reward.minimum or 0, scaled))
end

-- ─── Unvanlar ───────────────────────────────────────────────────────────────
--[[
	Sohbette adının yanında görünen unvan. Rozetlerden farkı: rozet Roblox
	tarafında kalıcı bir nişan, unvan oyun içi bir gösterge ve açılınca
	para ödülü veriyor.

	Koşullar profildeki sayaçlara bakıyor, yani her unvan için ayrı kod
	yazmak gerekmiyor — yeni unvan eklemek bu tabloya bir satır.

	Ödüller gelirle ölçekli: sabit tutar olsaydı geç oyunda açılan unvanlar
	anlamsız kalırdı. Taban değer yeni oyuncu için.

	order: aynı anda birden fazla unvan açıksa en yükseği takılıyor.
]]

export type TitleDef = {
	id: string,
	name: string,
	stat: string,          -- profildeki sayaç (TitleService.statValue)
	threshold: number,
	rarity: string,        -- Config.Rarities anahtarı: renk ve prestij
	order: number,         -- otomatik takılan en yüksek order
	incomeSeconds: number, -- ödül: kaç saniyelik gelir
	minimum: number,       -- ödül tabanı
	hint: string,          -- menüde "nasıl kazanılır"
}

--[[
	2026-09-28 YENİDEN: "kazanması çok kolay, insanlar heves etsin".
	Eski unvanların çoğu oyuncudan çalmaya bağlıydı ve birkaç çalmada
	açılıyordu. Artık:
	  - NADİRLİK KADEMESİ: Common → Secret. Sohbette ve BAŞIN ÜSTÜNDE
	    (herkes görüyor) nadirlik renginde; Mythic/Secret parlıyor.
	  - ZORLAŞAN HEDEFLER: ilk unvan 10 soygun, en üstü 10.000.
	  - FARKLI YOLLAR: soygun, uzay hızı, antrenman, canavar sersemletme,
	    mutasyon avı, koleksiyon, rebirth, son canavar.
	  - ÖDÜL: nadirlikle büyüyen gelir (saniyelik gelir × incomeSeconds).
	Kayıtta kalan eski unvanlar (Sus, Impostor...) Config'te olmadığı için
	yükleme sırasında düşüyor; Crewmate/Captain/Engineer/Amogus Prime kalıyor.
]]
Config.Titles = {
	{ id = "Crewmate",      name = "Crewmate",           rarity = "Common",    stat = "salvaged",      threshold = 0,     order = 1,  incomeSeconds = 0,    minimum = 0,        hint = "Everyone starts here" },
	{ id = "SpaceRookie",   name = "Space Rookie",       rarity = "Common",    stat = "salvaged",      threshold = 10,    order = 2,  incomeSeconds = 60,  minimum = 2500,     hint = "Steal 10 crewmates from space monsters" },
	{ id = "SpaceThief",    name = "Space Thief",        rarity = "Uncommon",  stat = "salvaged",      threshold = 50,    order = 3,  incomeSeconds = 150,  minimum = 15000,    hint = "Steal 50 crewmates from space monsters" },
	{ id = "Rocketeer",     name = "Rocketeer",          rarity = "Uncommon",  stat = "spaceSpeed",    threshold = 44,    order = 4,  incomeSeconds = 150,  minimum = 15000,    hint = "Reach 44 space speed" },
	{ id = "Yeeted",        name = "Yeeted",             rarity = "Uncommon",  stat = "thrown",        threshold = 40,    order = 5,  incomeSeconds = 150,  minimum = 15000,    hint = "Get thrown back by monsters 40 times" },
	{ id = "HeistPro",      name = "Heist Pro",          rarity = "Rare",      stat = "salvaged",      threshold = 200,   order = 6,  incomeSeconds = 450,  minimum = 75000,   hint = "Steal 200 crewmates from space monsters" },
	-- "stunned" 2026-09-28'den beri gear'la vurulan oyuncular (GearService); kimlik kayıtlar için aynı
	{ id = "MonsterTamer",  name = "Space Bully",        rarity = "Rare",      stat = "stunned",       threshold = 100,   order = 7,  incomeSeconds = 450,  minimum = 75000,   hint = "Hit other players 100 times with gear" },
	{ id = "IronWill",      name = "Iron Will",          rarity = "Rare",      stat = "trainings",     threshold = 150,   order = 8,  incomeSeconds = 450,  minimum = 75000,   hint = "Win the capsule mini game 150 times" },
	{ id = "Captain",       name = "Captain",            rarity = "Rare",      stat = "rebirths",      threshold = 1,     order = 9,  incomeSeconds = 600, minimum = 150000,   hint = "Rebirth once" },
	{ id = "WarpRunner",    name = "Warp Runner",        rarity = "Epic",      stat = "spaceSpeed",    threshold = 90,    order = 10, incomeSeconds = 900, minimum = 500000,  hint = "Reach 90 space speed" },
	{ id = "VoidRaider",    name = "Void Raider",        rarity = "Epic",      stat = "salvaged",      threshold = 750,   order = 11, incomeSeconds = 900, minimum = 500000,  hint = "Steal 750 crewmates from space monsters" },
	{ id = "MutantHunter",  name = "Mutant Hunter",      rarity = "Epic",      stat = "mutatedSteals", threshold = 75,    order = 12, incomeSeconds = 900, minimum = 500000,  hint = "Steal 75 mutated crewmates" },
	{ id = "Engineer",      name = "Engineer",           rarity = "Epic",      stat = "maxedUpgrades", threshold = 5,     order = 13, incomeSeconds = 900, minimum = 500000,  hint = "Max out 5 upgrades" },
	{ id = "Lightspeed",    name = "Lightspeed",         rarity = "Legendary", stat = "spaceSpeed",    threshold = 120,   order = 14, incomeSeconds = 1800, minimum = 2500000,  hint = "Reach 120 space speed" },
	{ id = "GalaxyBandit",  name = "Galaxy Bandit",      rarity = "Legendary", stat = "salvaged",      threshold = 2500,  order = 15, incomeSeconds = 1800, minimum = 2500000,  hint = "Steal 2,500 crewmates from space monsters" },
	{ id = "Collector",     name = "Collector",          rarity = "Legendary", stat = "discovered",    threshold = 25,    order = 16, incomeSeconds = 1800, minimum = 2500000,  hint = "Discover all 25 crewmates in the Index" },
	{ id = "Admiral",       name = "Admiral",            rarity = "Legendary", stat = "rebirths",      threshold = 5,     order = 17, incomeSeconds = 1800, minimum = 2500000,  hint = "Rebirth 5 times" },
	{ id = "LeviathanRobber", name = "Leviathan Robber", rarity = "Mythic",    stat = "bossSteals",    threshold = 50,    order = 18, incomeSeconds = 3600, minimum = 12500000, hint = "Steal 50 crewmates from the Void Leviathan" },
	{ id = "AmogusPrime",   name = "Amogus Prime",       rarity = "Mythic",    stat = "secrets",       threshold = 1,     order = 19, incomeSeconds = 3600, minimum = 12500000, hint = "Own a Secret crewmate" },
	{ id = "MonstersNightmare", name = "Monsters' Nightmare", rarity = "Secret", stat = "salvaged",   threshold = 10000, order = 20, incomeSeconds = 7200, minimum = 50000000, hint = "Steal 10,000 crewmates from space monsters" },
} :: { TitleDef }

--[[
	Unvanın yazı rengi (sohbet, baş üstü, menü). Nadirlik renklerinden;
	Secret'ın nadirlik rengi neredeyse siyah, yazıda açık altın.
]]
local TITLE_COLORS: { [string]: Color3 } = {
	Common = Color3.fromRGB(205, 210, 220),
	Uncommon = Color3.fromRGB(110, 235, 140),
	Rare = Color3.fromRGB(90, 175, 255),
	Epic = Color3.fromRGB(195, 125, 255),
	Legendary = Color3.fromRGB(255, 185, 50),
	Mythic = Color3.fromRGB(255, 85, 150),
	Secret = Color3.fromRGB(255, 240, 160),
}

function Config.GetTitleColor(rarity: string): Color3
	return TITLE_COLORS[rarity] or TITLE_COLORS.Common
end

local titlesById: { [string]: TitleDef } = {}
for _, def in Config.Titles do
	titlesById[def.id] = def
end

function Config.GetTitle(id: string): TitleDef?
	return titlesById[id]
end

--[[ Unvan ödülünün tutarı. Gelir düşükse taban değer geçerli. ]]
function Config.GetTitleReward(def: TitleDef, incomePerSecond: number): number
	return math.floor(math.max(def.minimum, incomePerSecond * def.incomeSeconds))
end

-- ─── Görevler ───────────────────────────────────────────────────────────────
--[[
	Üç vadeli görevler: 30 dakika, 3 saat, günlük.

	Neden var: gelir üretmek pasif bir döngü. Oyuncuya "şimdi ne yapayım"
	sorusunun cevabını veren bir şey yoksa oyun açık bırakılan bir sekmeye
	dönüşüyor. Görevler o boşluğu dolduruyor ve oyuncuyu çalmaya,
	yükseltmeye, çark çevirmeye itiyor.

	Vade penceresi dolunca görevler yeniden çekiliyor. Tamamlananlar
	pencere dolana kadar tamamlanmış duruyor — "hepsini bitirdim" hissi
	olmadan hemen yenisi gelirse hiç bitmeyen bir liste oluyor.

	İlerleme mutlak sayaçların farkından hesaplanıyor: görev verilirken
	sayacın o anki değeri taban alınıyor. Bu yüzden her sayaç yalnızca
	artmalı; azalan bir sayaç ilerlemeyi geri götürür.
]]

export type QuestTier = {
	id: string,
	name: string,
	seconds: number,       -- pencere uzunluğu
	slots: number,         -- aynı anda kaç görev
	goalMul: number,       -- hedefler kısa vadeye göre bu kat
	rewardSeconds: number, -- ödül: kaç saniyelik gelir
	rewardMinimum: number, -- ödül tabanı
}

--[[
	goalMul zamanla orantılı değil bilerek: 30 dakikadan 3 saate geçerken
	süre 6 katına çıkıyor ama kimse 3 saat kesintisiz oynamıyor. 4 kat,
	iki oturumda bitirilebilir bir hedef bırakıyor.
]]
Config.QuestTiers = {
	-- 2026-09-28 dengesi: günlük görev 1 SAATLİK gelir veriyordu (bir oyuncu 62M aldı).
	-- Ödüller artık birkaç dakikalık gelir: görev hedefe yönlendiriyor, para basmıyor.
	{ id = "short",  name = "30 Minutes", seconds =  1800, slots = 2, goalMul =  1, rewardSeconds =   45, rewardMinimum =   2000 },
	{ id = "medium", name = "3 Hours",    seconds = 10800, slots = 2, goalMul =  4, rewardSeconds =  180, rewardMinimum =  12000 },
	{ id = "daily",  name = "Daily",      seconds = 86400, slots = 2, goalMul = 12, rewardSeconds =  480, rewardMinimum =  50000 },
} :: { QuestTier }

export type QuestDef = {
	id: string,
	text: string,           -- string.format kalıbı; %s hedefin yazılı hali
	stat: string,           -- QuestService'in tanıdığı sayaç
	base: number,           -- kısa vade hedefi
	maxGoal: number,        -- uzun vadede bile bunu aşmıyor
	fromTier: number,       -- bu sıradan önceki vadelerde çıkmıyor
	incomeSeconds: number?, -- hedef nakitse: kaç saniyelik gelir
	minimum: number?,       -- nakit hedefi tabanı
}

--[[
	maxGoal neden var: "hırsız yakala" görevi günlük vadede 12 katına
	çıksaydı, oyuncunun kontrolü dışında bir şey isterdi — birinin gelip
	ondan çalmasını beklemek. Başkasına bağlı görevlerin tavanı düşük.

	fromTier neden var: yeni oyuncu 30 dakikada yükseltme alamıyor, rebirth
	hiç atamıyor. O görevler kısa vadede çıkarsa görev paneli baştan
	imkânsız görünüyor.
]]
Config.Quests = {
	{ id = "Heist",   stat = "salvaged", base = 3, maxGoal = 30, fromTier = 1, text = "Steal %s crewmates from space monsters" },
	{ id = "Train",   stat = "trainings", base = 3, maxGoal = 30, fromTier = 1, text = "Win the capsule mini game %s times" },
	{ id = "Sell",    stat = "sold",     base = 3, maxGoal = 25, fromTier = 1, text = "Sell %s crewmates" },
	{ id = "Earn",    stat = "earned",   base = 0, maxGoal = 0,  fromTier = 1, text = "Earn $%s", incomeSeconds = 300, minimum = 20000 },
	{ id = "Stun",    stat = "stunned",  base = 2, maxGoal = 20, fromTier = 2, text = "Hit other players %s times with gear" },
	{ id = "Mutated", stat = "mutatedSteals", base = 1, maxGoal = 5, fromTier = 2, text = "Steal %s mutated crewmates" },
	{ id = "Upgrade", stat = "upgrades", base = 1, maxGoal =  4, fromTier = 2, text = "Buy %s base upgrades" },
	{ id = "Spin",    stat = "spins",    base = 1, maxGoal =  1, fromTier = 3, text = "Spin the wheel %s time" },
	{ id = "Rebirth", stat = "rebirths", base = 1, maxGoal =  1, fromTier = 3, text = "Rebirth %s time" },
} :: { QuestDef }

--[[
	İksirler — süreli takviyeler.

	Görev ödülü olarak envantere giriyor, ANINDA uygulanmıyor. Sebep:
	çalışırken kazanılan bir takviye boşa gidiyor. Envanterde durursa
	oyuncu ne zaman işine geliyorsa o zaman içiyor.

	Hepsi SÜRELİ. Kalıcı hiçbir şey verilmiyor: kalıcı pass'i bedava
	dağıtmak satışı öldürür, süreli olanı tersine çalışır — on dakika iki
	kat kazanan oyuncu pass'in ne işe yaradığını öğrenmiş oluyor.

	kind, MonetizationService'in tanıdığı takviye türü. Aynı türden iki
	iksir üst üste binmiyor, süreleri ekleniyor.
]]

export type PotionDef = {
	id: string,
	name: string,
	description: string,
	kind: string,
	seconds: number,
	weight: number,
	multiplier: number?,
}

--[[
	3x gelir pass'in (2x) üstünde ama yalnızca beş dakika ve en nadiri;
	kalıcı 2x ile yarışmıyor, sadece ödülü heyecanlı kılıyor.
]]
Config.Potions = {
	{ id = "Income2x",   name = "Double Income", kind = "income", seconds = 600, multiplier = 2, weight = 35,
	  description = "2x cash from every podium" },
	{ id = "FastSteal",  name = "Fast Hands",    kind = "steal",  seconds = 900, weight = 25,
	  description = "Grab crewmates in space 20% faster" },
	-- Kimlik eski (kayıtlar ve Robux ürünü bağlı); 2026-09-28'den beri canavar kalkanı
	{ id = "StrongLock", name = "Monster Shield", kind = "lock", seconds = 900, weight = 25,
	  description = "Break free once when a monster catches you" },
	{ id = "Income3x",   name = "Triple Income", kind = "income", seconds = 300, multiplier = 3, weight = 15,
	  description = "3x cash from every podium" },
} :: { PotionDef }

-- Aynı iksirden envanterde en fazla bu kadar durabiliyor. Sınırsız olsaydı
-- oyuncu aylarca biriktirip tek seferde dökerdi.
Config.PotionStackLimit = 5

local potionsById: { [string]: PotionDef } = {}
for _, def in Config.Potions do
	potionsById[def.id] = def
end

function Config.GetPotion(id: string): PotionDef?
	return potionsById[id]
end

function Config.RollPotion(rng: Random): PotionDef
	local total = 0
	for _, def in Config.Potions do
		total += def.weight
	end

	local roll = rng:NextNumber() * total
	for _, def in Config.Potions do
		roll -= def.weight
		if roll <= 0 then
			return def
		end
	end

	return Config.Potions[1]
end

--[[ Süreyi okunur yazar. Panel ve bildirimler bunu kullanıyor. ]]
function Config.FormatDuration(seconds: number): string
	local total = math.max(0, math.floor(seconds))
	if total >= 3600 then
		return string.format("%dh %dm", total // 3600, (total % 3600) // 60)
	end
	return string.format("%d:%02d", total // 60, total % 60)
end

local questsById: { [string]: QuestDef } = {}
for _, def in Config.Quests do
	questsById[def.id] = def
end

function Config.GetQuest(id: string): QuestDef?
	return questsById[id]
end

function Config.GetQuestTier(id: string): QuestTier?
	for _, tier in Config.QuestTiers do
		if tier.id == id then
			return tier
		end
	end
	return nil
end

--[[ Vadenin sırası (1'den başlar). Bilinmiyorsa 0. ]]
function Config.GetQuestTierIndex(id: string): number
	for index, tier in Config.QuestTiers do
		if tier.id == id then
			return index
		end
	end
	return 0
end

--[[
	Görevin o vadedeki hedefi. Nakit hedefleri gelirle ölçekleniyor, çünkü
	sabit bir tutar geç oyunda bir saniyede doluyor, erken oyunda hiç
	dolmuyor.
]]
function Config.GetQuestGoal(def: QuestDef, tier: QuestTier, incomePerSecond: number): number
	if def.incomeSeconds then
		local scaled = incomePerSecond * def.incomeSeconds * tier.goalMul
		return math.floor(math.max((def.minimum or 0) * tier.goalMul, scaled))
	end

	return math.floor(math.min(def.maxGoal, math.max(1, def.base * tier.goalMul)))
end

--[[ Görev metnindeki hedefin okunur hali. Nakit hedefleri kısaltılıyor. ]]
function Config.FormatQuestGoal(def: QuestDef, goal: number): string
	if def.incomeSeconds then
		return Config.FormatCash(goal)
	end
	return tostring(goal)
end

--[[ Vade ödülü. Unvan ödülleriyle aynı mantık: gelirle ölçekli, tabanlı. ]]
function Config.GetQuestReward(tier: QuestTier, incomePerSecond: number): number
	return math.floor(math.max(tier.rewardMinimum, incomePerSecond * tier.rewardSeconds))
end

--[[
	Bir vade için görev seçer. Aynı görev iki kez çıkmıyor; uygun görev
	sayısı slot sayısından azsa daha az görev dönüyor (boş satır, aynı
	görevin iki kez görünmesinden iyi).
]]
function Config.RollQuests(rng: Random, tier: QuestTier): { QuestDef }
	local tierIndex = Config.GetQuestTierIndex(tier.id)

	local pool = {}
	for _, def in Config.Quests do
		if def.fromTier <= tierIndex then
			table.insert(pool, def)
		end
	end

	local picked = {}
	for _ = 1, math.min(tier.slots, #pool) do
		local index = rng:NextInteger(1, #pool)
		table.insert(picked, pool[index])
		table.remove(pool, index)
	end

	return picked
end

-- ─── Öğretici ───────────────────────────────────────────────────────────────
--[[
	Yeni oyuncunun ilk oturumunda izlediği sıralı adımlar.

	Neden var: oyunun döngüsü (uzaydaki canavardan çal -> kaideye koy -> gelir
	üret -> kapsülde hızlan -> başkasından çal -> üssünü kilitle) hiçbir
	yerde anlatılmıyor. Bu türde
	oyuncu ilk iki dakikada döngüyü çözemezse çıkıyor.

	Adımlar sıralı: biri bitmeden sonraki gösterilmiyor. Koşul kontrolü
	TutorialService'te; burada yalnızca veri duruyor çünkü Config istemciden
	de okunuyor ve sunucu durumuna erişemiyor.

	check:  TutorialService'in tanıdığı sayaç adı
	goal:   o sayacın ulaşması gereken değer (ilerleme çubuğu bundan çıkıyor)
	hint:   istemcinin hedef göstereceği nesnenin adı
	reward: adım bitince verilen nakit

	Ödüller sabit: öğretici tanımı gereği oyunun en başında geçiyor, gelirle
	ölçeklemek burada hep tabana düşerdi. Toplamı en ucuz yükseltmenin ilk
	seviyesinden biraz fazla — öğreticiyi bitiren oyuncu oyunun ikinci
	katmanına dokunabiliyor ama dengeyi bozmuyor.
]]

export type TutorialStep = {
	id: string,
	title: string,
	text: string,
	hint: string,
	check: string,
	goal: number,
	reward: number,
}

Config.Tutorial = {
	--[[
		2026-09-28 YENİDEN: oyuncudan çalma kalktı ("rakipten çal", "kilitle"
		adımları gitti). Akış oyunun asıl döngüsünü sırayla öğretiyor:
		  soygun → ikinci soygun → kapsül → mini oyun → çark → JETPACK →
		  yükseltme → daha güçlü canavar (hızın ne işe yaradığı) → pet →
		  gear → görev.
		Ödüller bir sonraki adımın masrafını karşılıyor (test "her adım
		karşılanabiliyor"): Scout Jet 15 bin, Supply Egg 50 bin, Slap Glove
		250 bin. Jetpack adımının ödülü fiyatını geri veriyor ve Gear
		adımına pay bırakıyor (yükseltmeler pahalandı).
	]]
	{
		id = "Heist", title = "Your first heist", hint = "SpaceGate",
		text = "Go through the Launch Bay gate, fly to Glorp's planet and grab a crewmate. Fly back to the SAFE deck before Glorp catches you!",
		check = "units", goal = 1, reward = 500,
	},
	{
		id = "Fill", title = "Bring home another", hint = "SpaceGate",
		text = "Every crewmate on your podiums prints cash each second. Steal a second one!",
		check = "units", goal = 2, reward = 1500,
	},
	{
		id = "Train", title = "Train your space speed", hint = "Capsule",
		text = "Step into the Space Capsule behind your base. It raises your Space Speed so you can outrun bigger monsters.",
		check = "spaceSpeed", goal = 18, reward = 3000,
	},
	{
		id = "CapsuleGame", title = "Win the capsule game", hint = "Capsule",
		text = "Inside the capsule, steer the rocket with WASD (or the joystick) and dodge the rocks until the bar fills.",
		check = "trainings", goal = 1, reward = 5000,
	},
	{
		id = "Spin", title = "Take your free spin", hint = "Wheel",
		text = "The lucky wheel in the Cafeteria gives one free spin every day. Go claim today's!",
		check = "spins", goal = 1, reward = 20000,
	},
	{
		id = "Jetpack", title = "Buy a jetpack", hint = "JetpackStand",
		text = "The JETPACKS stand on the Launch Bay deck sells faster jetpacks. Buy the Scout Jet: you fly out to the planets faster!",
		check = "jetpacks", goal = 1, reward = 40000,
	},
	{
		id = "Upgrade", title = "Buy an upgrade", hint = "Upgrades",
		text = "Your upgrade booth sells Jet Boost, Quick Hands and more. Upgrades cost cash, not Robux.",
		check = "upgrades", goal = 1, reward = 25000,
	},
	{
		id = "Tougher", title = "Rob a tougher monster", hint = "Planet2",
		text = "Chomper guards better crewmates but needs 28 Space Speed. Train up, then steal from Chomper!",
		check = "bestPlanet", goal = 2, reward = 30000,
	},
	{
		id = "Hatch", title = "Hatch a pet", hint = "Hatchery",
		text = "Eggs in the Hatchery hold pets that boost your cash and flight speed.",
		check = "pets", goal = 1, reward = 220000,
	},
	{
		id = "Gear", title = "Get a gear", hint = "GearShop",
		text = "Gear from the Weapons room slaps, zaps and blasts other players, even while flying. Buy one and try it!",
		check = "gear", goal = 1, reward = 50000,
	},
	{
		id = "Task", title = "Do a ship task", hint = "Task",
		text = "Task consoles in the side rooms pay cash. Finish one to complete your training!",
		check = "tasks", goal = 1, reward = 20000,
	},
} :: { TutorialStep }

-- Bitirince verilen ek ödül. Adım ödüllerinden büyük ki son adım yarıda
-- bırakılmasın.
--[[
	Ödüller yükseltme fiyatlarıyla birlikte yükseltildi. Öğreticinin 5.
	adımı "bir yükseltme al" diyor; en ucuz yükseltme 100 bine çıkınca
	eski toplam (65 bin) o adımı imkânsız kılıyordu.
]]
Config.TutorialFinishBonus = 50000

function Config.GetTutorialStep(index: number): TutorialStep?
	return Config.Tutorial[index]
end

--[[ Öğreticinin toplam nakit değeri. Denge testleri buna bakıyor. ]]
function Config.GetTutorialTotalReward(): number
	local total = Config.TutorialFinishBonus
	for _, step in Config.Tutorial do
		total += step.reward
	end
	return total
end

-- ─── Bildirim sesleri ───────────────────────────────────────────────────────
--[[
	Bildirim tınıları.

	İLK DENEMEM YETERSİZDİ: hepsi aynı 0.39 saniyelik örnekten yalnızca
	perde değiştirilerek türetiliyordu. 1.18 ile 0.92 arasındaki fark o
	kadar kısa bir seste ayırt edilemiyor — kullanıcı haklı olarak "satın
	alma, satma ve yükseltme hâlâ aynı" dedi.

	ŞİMDİ FARKLI ÖRNEKLERDEN türetiliyor. Elimizde beş ses var ve üçü uzun,
	yani içlerinden farklı anlar kesilebiliyor:

	  Success (0.39 sn)  kısa parlak blip
	  Deny    (0.73 sn)  kısa boğuk red
	  Machine (1.93 sn)  mekanik uğultu  -> kesilince "tık/güm"
	  Alarm   (33 sn)    gergin siren    -> kesilince "bip"
	  Ambient (32 sn)    geniş süzülme   -> kesilince "yükseliş"

	Tımbre farkı perdeden çok daha güçlü bir işaret: mekanik bir "güm" ile
	parlak bir "ping" aynı perdede bile karıştırılmıyor. Perde ve vuruş
	sayısı üstüne binen ikincil işaretler.

	source  hangi örnek (yoksa Success)
	startAt örneğin neresinden başlasın (uzun örnekleri kesmek için)
	length  kaç saniye çalsın (yoksa sonuna kadar)
]]

export type NotifyCue = {
	source: string?,
	startAt: number?,
	length: number?,
	pitch: number,
	volume: number,
	repeats: number?,
	gap: number?,
}

Config.NotifyCues = {
	--[[
		Para işlemleri. ÜÇÜ DE FARKLI KAYNAKTAN: perde farkı kısa seslerde
		ayırt edilmiyordu, timbre farkı ediliyor. Kullanıcının "satın alma,
		satma ve yükseltme hâlâ aynı" şikâyeti tam olarak buydu.
	]]
	buy      = { source = "UiA", startAt = 1.20, length = 0.28, pitch = 1.15, volume = 0.45 },
	sell     = { source = "UiB", startAt = 2.40, length = 0.30, pitch = 0.85, volume = 0.45 },
	upgrade  = { source = "UiC", startAt = 3.60, length = 0.26, pitch = 1.00, volume = 0.50, repeats = 2, gap = 0.13 },

	-- Çalma döngüsü: uyarı ailesinden, kısa ve gergin
	steal    = { source = "Alarm", startAt = 2.00, length = 0.22, pitch = 1.25, volume = 0.45 },
	deposit  = { source = "UiD", startAt = 1.50, length = 0.28, pitch = 0.80, volume = 0.50, repeats = 2, gap = 0.12 },
	lock     = { source = "Throb", startAt = 4.00, length = 0.55, pitch = 0.75, volume = 0.50 },
	catch    = { source = "Alarm", startAt = 1.00, length = 0.18, pitch = 1.10, volume = 0.55, repeats = 3, gap = 0.10 },

	-- Büyük ve kalıcı alımlar: ağır, çok vuruşlu
	floor    = { source = "Throb", startAt = 2.00, length = 0.65, pitch = 0.60, volume = 0.60, repeats = 2, gap = 0.22 },
	rebirth  = { source = "Throb", startAt = 8.00, length = 1.60, pitch = 0.55, volume = 0.65 },
	purchase = { source = "UiC", startAt = 5.00, length = 0.26, pitch = 1.05, volume = 0.55, repeats = 3, gap = 0.11 },

	-- Kutlamalar: yükselen dizi, farklı tonlardan
	badge    = { source = "UiD", startAt = 4.00, length = 0.24, pitch = 1.20, volume = 0.55, repeats = 3, gap = 0.09 },
	title    = { source = "UiA", startAt = 6.00, length = 0.26, pitch = 1.05, volume = 0.50, repeats = 3, gap = 0.12 },
	quest    = { source = "UiB", startAt = 5.50, length = 0.26, pitch = 0.95, volume = 0.45, repeats = 2, gap = 0.12 },
	spin     = { source = "UiC", startAt = 8.00, length = 0.24, pitch = 1.30, volume = 0.45, repeats = 2, gap = 0.07 },
	potion   = { source = "UiD", startAt = 7.00, length = 0.22, pitch = 1.45, volume = 0.40 },
	-- Yumurta açılışı: yükselen üç vuruş, "çatladı" hissi için hızlı
	pet      = { source = "UiA", startAt = 3.00, length = 0.20, pitch = 1.35, volume = 0.50, repeats = 3, gap = 0.08 },
	-- Günlük/oynama/indeks ödülü: hediye kutusu açılışı, parlak ve kısa
	reward   = { source = "UiD", startAt = 2.50, length = 0.22, pitch = 1.25, volume = 0.50, repeats = 2, gap = 0.10 },
	-- Ekipman satın alma: metalik tek vuruş
	gear     = { source = "UiB", startAt = 3.50, length = 0.26, pitch = 0.95, volume = 0.50 },
	-- Sunucu olayı başladı/yaklaşıyor: alarm ailesinden, ağır iki vuruş
	event    = { source = "Alarm", startAt = 5.00, length = 0.30, pitch = 0.85, volume = 0.45, repeats = 2, gap = 0.22 },
	-- Kozmetik satın alma: parlak, üç hızlı vuruş (ödülden farklı kaynak)
	cosmetic = { source = "UiC", startAt = 10.0, length = 0.20, pitch = 1.40, volume = 0.45, repeats = 3, gap = 0.07 },
	-- Arkadaş sunucuya girdi: sıcak, iki vuruşlu karşılama
	friend   = { source = "UiA", startAt = 7.50, length = 0.24, pitch = 1.10, volume = 0.45, repeats = 2, gap = 0.14 },
	-- Sabotaj: alarm ailesinden, alçak ve kısa üç vuruş (olaydan farklı)
	sabotage = { source = "Alarm", startAt = 3.00, length = 0.16, pitch = 0.70, volume = 0.45, repeats = 3, gap = 0.09 },
	-- Gezen impostor: alarm ailesinden ama tiz ve uzun iki vuruş
	rogue    = { source = "Alarm", startAt = 6.00, length = 0.34, pitch = 1.45, volume = 0.45, repeats = 2, gap = 0.18 },

	-- Bilgilendirme: en sessizler, araya girmemeli
	tutorial = { source = "UiA", startAt = 9.00, length = 0.24, pitch = 1.00, volume = 0.32 },
	welcome  = { source = "UiB", startAt = 8.00, length = 0.30, pitch = 1.00, volume = 0.38, repeats = 2, gap = 0.15 },
	plot     = { source = "UiC", startAt = 11.0, length = 0.24, pitch = 0.90, volume = 0.32 },
	income   = { source = "UiB", startAt = 12.0, length = 0.20, pitch = 0.95, volume = 0.25 },
} :: { [string]: NotifyCue }

--[[ Bu türün tanımlı bir sesi var mı. Testler buna bakıyor. ]]
function Config.HasNotifyCue(kind: string): boolean
	return Config.NotifyCues[kind] ~= nil
end

-- ─── Rozetler ───────────────────────────────────────────────────────────────
-- ID'ler Creator Dashboard > Badges altında oluşturulunca buraya yazılacak.
-- id = 0 olan rozet verilmiyor; oyun onu yokmuş gibi çalışıyor.

export type BadgeDef = {
	id: number,
	name: string,
}

Config.Badges = {
	FirstSteal   = { id = 1465909777545910, name = "First Heist" },
	FirstRebirth = { id = 179427778492757, name = "Reborn" },
	Millionaire  = { id = 417888352205442, name = "Millionaire" },
	Billionaire  = { id = 3789475162138106, name = "Billionaire" },
	ThiefCatcher = { id = 1045910647960350, name = "Caught Red-Handed" },
	-- 2026-09-28: kimlik 0 (Roblox'ta henüz yok); canavar ilk kez fırlatınca
	Victim       = { id = 4265089406351174, name = "Yeeted" },
	FullHouse    = { id = 0, name = "Full House" },
	SecretFind   = { id = 0, name = "Secret Collector" },
	-- 2026-09-28: kimlik 0; 100 uzay soygununda
	StreakMaster = { id = 4304894818520792, name = "Heist Master" },
	FirstSpin    = { id = 0, name = "Lucky Spinner" },
} :: { [string]: BadgeDef }

-- Rozet eşikleri
Config.BadgeMillionaire = 1000000
Config.BadgeBillionaire = 1000000000

-- ─── Rebirth ve katlar ──────────────────────────────────────────────────────
-- Tavana ulaşan oyuncunun yapacak bir şeyi kalmıyordu. Rebirth her şeyi
-- sıfırlıyor ama karşılığında kalıcı gelir çarpanı ve yeni bir kat veriyor.
Config.MaxFloors = 3           -- 1. kat açık gelir, üstü satın alınıyor
Config.FloorHeight = 18        -- katlar arası yükseklik (stud)
-- 8 kaide Amogus Prime ile 1. kat tavanı ~3.36M/sn. Rebirth'ün o tavanda
-- birkaç dakikalık oyun kadar tutması gerekiyor; 25M yedi saniyelik
-- kazançtı, hiçbir şey ifade etmiyordu.
Config.RebirthBaseCost = 1000000000
Config.RebirthCostGrowth = 8   -- her seviyede maliyet bu kat artar
Config.RebirthIncomeBonus = 0.5 -- seviye başına kalıcı gelir artışı (+%50)

--[[
	Üst katlar: rebirth AÇIYOR, para SATIN ALIYOR.

	Eskiden kat doğrudan rebirth ödülüydü. Sorun şuydu: rebirth zaten
	kalıcı gelir çarpanı veriyor, kat da bedava gelince rebirth tek
	başına her şeydi ve biriken paranın rebirth dışında harcanacak büyük
	bir yeri yoktu.

	Şimdi ikisi ayrı: rebirth katın KİLİDİNİ açıyor, kat parayla
	alınıyor. Böylece rebirth'ten sonra oyuncunun önünde somut ve pahalı
	bir hedef duruyor, ve para biriktirmek rebirth ile yarışıyor —
	5 milyarı 2. kata mı yatırayım yoksa 8 milyarlık rebirth'e mi
	saklayayım sorusu gerçek bir karar.

	Fiyatlar rebirth maliyetlerine göre: 2. kat (5 mlr) ilk rebirth'ün
	(1 mlr) beş katı, 3. kat (150 mlr) ilk iki rebirth'ün toplamının
	(9 mlr) çok üstünde — bilerek, oyunun son büyük alımı olsun diye.

	Satın alınan kat KALICI: rebirth onu geri almıyor. Parasını ödedi.
]]

export type FloorUnlock = {
	floor: number,
	rebirths: number,  -- bu kadar rebirth olmadan satın alınamıyor
	cost: number,      -- oyun içi nakit
}

Config.FloorUnlocks = {
	{ floor = 2, rebirths = 1, cost =   5000000000 },
	{ floor = 3, rebirths = 2, cost = 150000000000 },
} :: { FloorUnlock }

function Config.GetFloorUnlock(floor: number): FloorUnlock?
	for _, def in Config.FloorUnlocks do
		if def.floor == floor then
			return def
		end
	end
	return nil
end

--[[
	Satın alınabilecek bir sonraki kat. Hepsi alınmışsa nil.

	Sıralı: 3. kat 2. kat alınmadan satın alınamıyor. Aksi halde oyuncu
	ortadaki katı atlayıp üsttekini alır ve arada boşluk kalırdı.
]]
function Config.GetNextFloor(floorsBought: number): FloorUnlock?
	return Config.GetFloorUnlock(floorsBought + 2)
end

-- ─── Çevrimdışı gelir ───────────────────────────────────────────────────────
-- Oyuncu çıkınca kazanç tamamen duruyordu, geri gelmek için sebep azdı.
-- Ama çevrimdışı oyuncudan çalınamıyor da: çıkmak zaten güvenli, bir de
-- cömert kazanç verirsek çıkmak oynamaktan kârlı hale gelir.
--
-- Bu ayarlarla 3 saat çevrimdışı ≈ 9 dakika aktif oyun. Hoş geldin
-- hediyesi kadar, strateji olacak kadar değil.
Config.OfflineIncomeRate = 0.05
Config.OfflineIncomeCapHours = 3

-- ─── Sunucu olayları ────────────────────────────────────────────────────────
--[[
	Saatli olaylar (EventService). Zamanlar UTC saatine hizalı: bütün
	sunucularda aynı anda başlıyor, oyuncu "Emergency Meeting her saat
	başı :15'te" diye öğrenebiliyor ve o saatte oyuna giriyor.

	every   — kaç saniyede bir
	offset  — periyodun içindeki başlangıç (0 = saat başı)
	duration— kaç saniye sürüyor

	Dakikalar birbirine denk gelmeyecek şekilde dağıtıldı: :15 toplantı,
	:30 reaktör (3 saatte bir), :45 ışıklar.

	RASTGELE OLAYLAR (random = true): Impostor sürpriz olmalı — oyuncu ne
	zaman geleceğini bilirse kilidini önceden basar ve olayın gerilimi
	kalmaz. Her saat `perHour` kez, sabit olayların pencerelerine (uyarı
	dahil) ve birbirlerine denk gelmeyen rastgele anlarda başlıyor; her
	sunucu kendi zarını atıyor, çizelgede görünmüyor, önceden uyarı yok.
]]
export type EventDef = {
	id: string,
	name: string,
	every: number,
	offset: number,
	duration: number,
	random: boolean?,
	perHour: number?,
}

Config.Events = {
	{ id = "Meeting",   name = "Emergency Meeting", every = 3600,     offset = 15 * 60, duration = 120 },
	{ id = "LightsOut", name = "Lights Sabotage",   every = 3600,     offset = 45 * 60, duration = 90 },
	{ id = "Meltdown",  name = "Reactor Meltdown",  every = 3 * 3600, offset = 30 * 60, duration = 60 },
	-- Uzay soygunu olayı: iki saatte bir, gezegenlerdeki her mürettebat mutasyonlu
	{ id = "Storm",     name = "Mutation Storm",    every = 2 * 3600, offset = 5 * 60,  duration = 120 },
	-- 2026-09-28: sürpriz (rastgele), saatte bir; kalkan Impostor Hunt'ın yerine
	{ id = "Comet",     name = "Golden Comet",      every = 3600, offset = 0, duration = 75, random = true, perHour = 1 },
} :: { EventDef }

-- Rastgele olayın sabit olaylardan ve kendi kopyalarından en az uzaklığı
Config.RandomEventGap = 90
Config.RandomEventSpacing = 15 * 60

-- Başlamadan kaç saniye önce haber verilsin
Config.EventWarning = 30

-- Emergency Meeting: herkese gelir çarpanı
Config.MeetingIncomeMul = 2
-- Lights Sabotage: uzaydaki canavarlar yarı kör: geç uyanıyor, yavaş kovalıyor
Config.LightsOutWakeMul = 2.5
Config.LightsOutChaseMul = 0.85

--[[
	Reactor Meltdown: reaktör enerji çekirdeklerini UZAYA savuruyor (güverte
	ile gezegenler arasına, SpaceService.RandomSpacePoint), ilk dokunan
	alıyor; uzay yoksa istasyonun rastgele noktalarına. Rastgele çünkü üsler farklı yerlerde; sabit
	nokta bazı üslere hep yakın olurdu.
	Ödül gelirle ölçekli (yeni oyuncu için de anlamlı, zengin için de):
	nakit ya da düşük ihtimalle bir karakter.
]]
Config.MeltdownCores = 6
Config.MeltdownRewardSeconds = 40   -- nakit ödül = saniyelik gelir × bu (2026-09-28: 90'dan)
Config.MeltdownMinCash = 5000
Config.MeltdownUnitChance = 0.15
Config.MeltdownUnitMinutes = 10     -- karakter ödülü: ~10 dk'lık gelirle alınabilecek en iyisi

function Config.GetNextEventStart(def: EventDef, now: number): number
	local into = (now - def.offset) % def.every
	if into == 0 then
		return now
	end
	return now - into + def.every
end

--[[
	Sabit olayların [from, to) aralığına düşen pencereleri: uyarıdan bitişe.
	Rastgele olay bunlara denk gelmemeli.
]]
function Config.GetFixedEventWindows(from: number, to: number): { { number } }
	local windows = {}
	for _, def in Config.Events do
		if def.random then
			continue
		end
		local t = Config.GetNextEventStart(def, from - def.duration - Config.EventWarning)
		while t < to + Config.EventWarning do
			table.insert(windows, { t - Config.EventWarning, t + def.duration })
			t += def.every
		end
	end
	return windows
end

--[[
	Rastgele olayın bir saatteki başlangıçları (unix saniye, sıralı).
	`hourStart` saatin başı. Adaylar 30 sn aralıklı; sabit pencerelere
	Config.RandomEventGap'ten yakın olanlar ve birbirine RandomEventSpacing'ten
	yakın olanlar eleniyor. Aday kalmazsa daha az döner.
]]
function Config.PlanRandomEvent(def: EventDef, hourStart: number, rng: Random): { number }
	local gap = Config.RandomEventGap
	local windows = Config.GetFixedEventWindows(hourStart - 3600, hourStart + 7200)
	local candidates = {}
	local t = hourStart + gap
	while t + def.duration + gap <= hourStart + 3600 do
		local free = true
		for _, w in windows do
			if t - gap < w[2] and w[1] < t + def.duration + gap then
				free = false
				break
			end
		end
		if free then
			table.insert(candidates, t)
		end
		t += 30
	end
	local picked: { number } = {}
	for _ = 1, def.perHour or 1 do
		local pool = {}
		for _, c in candidates do
			local ok = true
			for _, p in picked do
				if math.abs(c - p) < Config.RandomEventSpacing then
					ok = false
					break
				end
			end
			if ok then
				table.insert(pool, c)
			end
		end
		if #pool == 0 then
			break
		end
		table.insert(picked, pool[rng:NextInteger(1, #pool)])
	end
	table.sort(picked)
	return picked
end

function Config.GetEvent(id: string): EventDef?
	for _, def in Config.Events do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- ─── Vent ───────────────────────────────────────────────────────────────────
-- Taşırken kullanılamıyor (VentService). Bekleme, iki kapak arasında gidip
-- gelip kovalayanı sonsuza kadar atlatmayı engelliyor.
Config.VentCooldown = 8
Config.VentHoldTime = 0.35

-- ─── Arkadaş bonusu ─────────────────────────────────────────────────────────
--[[
	Aynı sunucudaki her Roblox arkadaşı için küçük bir gelir bonusu.
	Amaç oyuncunun arkadaşını çağırması; dengeyi bozmaması için küçük ve
	tavanlı: üç arkadaşta +%15, sonrası artmıyor. Karşılaştırma: tek bir
	rebirth +%50, gelir pass'i x2.

	Karşılıklı: iki arkadaş aynı sunucudaysa İKİSİ de bonus alıyor, yani
	davet eden de gelen de kazanıyor.
]]
Config.FriendBonusPerFriend = 0.05
Config.FriendBonusMax = 0.15

--[[ Sunucudaki arkadaş sayısına göre gelir bonusu (0.10 = +%10). ]]
function Config.GetFriendBonus(friendCount: number): number
	return math.min(Config.FriendBonusMax, math.max(0, friendCount) * Config.FriendBonusPerFriend)
end

-- ─── Para kazanma ───────────────────────────────────────────────────────────
-- ID'ler Creator Dashboard > Monetization altında ürün oluşturulunca buraya
-- yazılacak. id = 0 olan ürün devre dışıdır: satın alma kontrolü yapılmaz,
-- oyun da onu yokmuş gibi çalışır. Böylece ID'ler gelmeden test edilebiliyor.

export type GamePassDef = {
	id: number,
	name: string,
}

Config.GamePasses = {
	DoubleIncome = { id = 1997912710, name = "2x Income" },
	ExtraPodiums = { id = 1999070658, name = "+2 Podiums Per Floor" },
	-- 2026-09-28: Roblox'ta "Fast Grab" ve "Monster Shield" olarak yeniden adlandırıldı
	FastSteal    = { id = 1998410695, name = "Fast Grab" },
	StrongLock   = { id = 1998878635, name = "Monster Shield" },
	-- Yumurtayı tek seferde üç kez açar (üç kat fiyat, tek bekleme)
	TripleHatch  = { id = 1999526736, name = "Triple Hatch" },
} :: { [string]: GamePassDef }

--[[
	Oyunun Roblox grubu. OTOMATİK YUMURTA AÇMA gruba katılanlara açık:
	oyuncu grubu büyütüyor, grup da güncelleme bildirimleriyle oyuncuyu
	geri getiriyor.

	0 = grup yok: otomatik açma kapalı. Studio'da test için grup şartı
	aranmıyor (PetService).

	"Steal a Crewmate Official": roblox.com/communities/814468451
]]
Config.GroupId = 814468451

--[[
	Sunucu kapasitesi (Creator Dashboard > Places > Server Size ile AYNI
	olmalı). Başlık ekranı "x / 8" yazarken bunu kullanıyor: Studio testinde
	Players.MaxPlayers Studio'nun varsayılanını (60) veriyordu.
]]
Config.ServerSize = 8

-- Oyunun geliştiricileri (Roblox UserId)
Config.Developers = {
	[10382876527] = true, -- ATCIKM (Batur)
	[235261243] = true,   -- 48yusuf (Yusuf)
} :: { [number]: boolean }

--[[
	Sıralamalarda (lobi panoları, TOP CREW kürsüsü) GÖRÜNMEYEN hesaplar:
	geliştiriciler. Test ederken biriken parayla listenin başına
	oturuyorlardı. Kayıtları yazılmaya devam ediyor, yalnızca gösterilmiyor.
]]
Config.LeaderboardHidden = Config.Developers

--[[
	Geliştiricilerin sohbetteki unvanı. Config.Titles'ta DEĞİL: orada olsa
	herkesin unvan menüsünde kilitli bir "DEVELOPER" görünürdü. TitleService
	geliştiricinin "Title" niteliğine bunu yazıyor (seçtiği unvanın yerine).
]]
Config.DeveloperTitle = "DEVELOPER"

--[[
	Yumurta açılışının süresi (saniye). Bir yumurta açılırken ikincisi
	açılamıyor — sunucu bu süreyi bekletiyor, istemcideki animasyon da bu
	süreye göre ayarlı (HatchFX). Eskiden art arda basınca animasyonlar
	kuyruğa giriyor ve sonuçlar kaçıyordu.
]]
-- 3.5'ten 4.5'e: sallanma gerilimi ve açılış sesi sığsın (oyuncu isteği)
Config.HatchDuration = 4.5
Config.TripleHatchCount = 3

-- Gamepass etkileri. Tek yerde dursun ki denge değiştirmek kolay olsun.
Config.PassDoubleIncomeMultiplier = 2
Config.PassExtraPodiumsPerFloor = 2

-- Kat başına fiziksel kaide sayısı: normal + bonus. Bonus kaideler her
-- zaman inşa ediliyor ama pass olmadan kullanılamıyor. Slot numaraları
-- bu sabite göre ilerliyor; sonradan değiştirmek kayıtlı slot -> kaide
-- eşlemesini bozar, o yüzden değişirse DataService sürümü de artmalı.
Config.PodiumsPerFloorTotal = Config.PodiumsPerPlot + Config.PassExtraPodiumsPerFloor
--[[
	Hızlı kapma (Fast Steal pass'i, Fast Hands iksiri): uzaydaki mürettebatı
	kapma süresi bu oranla çarpılıyor. Pass kalıcı ve Robux'la alınıyor, o
	yüzden belirgin güçlü (%40); iksir süreli bir tadımlık (%20). İkisi üst
	üste binmiyor, iyisi geçiyor. Quick Hands yükseltmesiyle çarpılıyor.
]]
Config.PassFastStealMultiplier = 0.6
Config.PotionFastStealMultiplier = 0.8
-- Hiçbir çarpan birleşimi kapmayı bundan kısa yapamaz
Config.MinGrabHold = 0.25

--[[
	Oyuncuya özel kapma süresi: taban × pass/iksir çarpanı × Quick Hands.
	Sunucu (PromptGuard) ve istemci (PromptFilter) AYNI fonksiyonu
	kullanıyor; farklı hesaplasalar basış reddedilirdi.
]]
function Config.GetPersonalGrabHold(base: number, passMul: number, quickHandsLevel: number): number
	return math.max(Config.MinGrabHold, base * passMul * Config.GetGrabHoldMul(quickHandsLevel))
end

--[[
	Canavar kalkanı (Strong Lock pass'i ve Reinforced Lock iksiri —
	2026-09-28'de kilit kalkınca yeniden amaçlandı; Roblox panelindeki
	adları "Monster Shield" yapılmalı). Canavar yakaladığında kalkan hazırsa
	oyuncu kurtuluyor: canavar sersemleyip geri itiliyor, karakter sırtta
	kalıyor. Sonra ShieldCooldown sn yeniden dolmuyor.
]]
Config.ShieldCooldown = 60
Config.ShieldStun = 2.5
Config.ShieldKnock = 30

Config.Products = {
	-- Roblox'taki adları: Small / Medium / Huge Cash Pack
	--[[
		2026-09-28: "sonraki oyun için çok az veriyor, kimse Robux'la almaz".
		Miktar artık oyuncunun anlık gelirine ve bakiyesine göre
		(Config.GetCashPackAmount): amount taban, seconds kaç saniyelik gelir,
		cashFrac bakiyenin ne kadarı. Hangisi büyükse o. Adlar Roblox'taki
		ürün adları; mağaza kartı gerçek miktarı gösteriyor.

		Robux fiyatları 25 / 99 / 299. Büyük paket Robux başına daha
		kârlı olmalı ("küçük paket daha ucuza geliyordu"): Robux başına
		değer küçüğe göre Orta ~×1.35, Büyük ~×1.65 (üç terimin her birinde).
	]]
	Cash100K       = { id = 3714873855, name = "Small Cash Pack",  kind = "cash", amount =   100000, seconds =   900, cashFrac = 0.1 },
	Cash1M         = { id = 3714873899, name = "Medium Cash Pack", kind = "cash", amount =  1000000, seconds =  4800, cashFrac = 0.55 },
	Cash10M        = { id = 3714873959, name = "Huge Cash Pack",   kind = "cash", amount = 10000000, seconds = 18000, cashFrac = 2 },
	-- Instant Spawn (3714873580, kind "conveyor") mağazadan kaldırıldı. Konveyör de
	-- kalktı; "conveyor" ödülü artık SpaceService'te (kaideye bir karakter).
	LuckyRoll      = { id = 3714873797, name = "Guaranteed Mutation", kind = "lucky" },
	InstantRebirth = { id = 3714874005, name = "Instant Rebirth", kind = "rebirth" },
	ExtraSpin      = { id = 3714873337, name = "Extra Spin",      kind = "spin" },
	--[[
		Mağazadaki iksirler (Robux). Kimlikler Creator Dashboard'da ürün
		açılınca yazılacak; 0 iken mağazada "SOON". Ürün ikonları:
		store_icons/product_potion_*.png.
	]]
	PotionIncome2x   = { id = 3714932156, name = "Double Income Potion",   kind = "potion", potion = "Income2x" },
	PotionIncome3x   = { id = 3714932218, name = "Triple Income Potion",   kind = "potion", potion = "Income3x" },
	PotionFastSteal  = { id = 3714932280, name = "Fast Hands Potion",      kind = "potion", potion = "FastSteal" },
	PotionStrongLock = { id = 3714932378, name = "Monster Shield Potion",  kind = "potion", potion = "StrongLock" },
} :: { [string]: ProductDef }

--[[
	Nakit paketinin bu oyuncuya vereceği miktar: taban, `seconds` saniyelik
	gelir ya da bakiyenin `cashFrac` katı — hangisi büyükse. İki anlamlı
	basamağa yuvarlanıyor (kartta okunaklı dursun). Sunucu satın alma anında
	aynı hesabı yapıyor; kart da oyuncunun Cash/Income niteliklerinden.
]]
function Config.GetCashPackAmount(product: any, incomePerSecond: number, cash: number): number
	local base = product.amount or 0
	local byIncome = math.max(0, incomePerSecond) * (product.seconds or 0)
	local byCash = math.max(0, cash) * (product.cashFrac or 0)
	local amount = math.max(base, byIncome, byCash)
	if amount >= 100 then
		local digits = math.floor(math.log10(amount)) - 1
		local unit = 10 ^ digits
		amount = math.floor(amount / unit + 0.5) * unit
	end
	return math.floor(amount)
end

-- Profilde saklanan makbuz kimliği sayısı. Aynı satın almanın iki kez
-- işlenmesini engellemek için tutuluyor; sınırsız büyümesin diye kırpılıyor.
Config.ReceiptHistoryLimit = 50

-- ─── Üs yükseltmeleri (oyun içi parayla) ────────────────────────────────────
-- Nakdin karakter almak dışında harcanacak yeri olsun diye. Robux ürünlerinin
-- aksine bunlar herkese açık: yeterince oynayan herkes alabiliyor.

export type UpgradeDef = {
	id: string,
	name: string,
	category: string,      -- "training" | "heist" | "base" (arayüz grupları)
	blurb: string,         -- tek satır açıklama
	baseMaxLevel: number,  -- 1. katta ulaşılabilen tavan
	baseCost: number,
	costGrowth: number,
}

--[[
	2026-09-28 YENİDEN: oyuncudan çalma kalkınca Unit Guard, Carry Speed ve
	Lock Power anlamsız kaldı (harcanan para DataService'te iade:
	Config.RetiredUpgrades). Yükseltmeler artık oyunun asıl döngüsüne göre:

	  ANTRENMAN  Space Capsule    — kapsülde hız kazancı
	             Training Console — kapsül mini oyununu kolaylaştırıyor
	                                (kapsülün öbür yanındaki ayrı istasyon)
	  SOYGUN     Quick Hands      — mürettebatı daha hızlı kapma
	             Jet Boost        — uzayda atılma (Q / düğme); seviye 1 açıyor
	             Stealth Suit     — canavar geç uyanıyor, yakalama menzili kısa
	             Lucky Scanner    — çalınan mürettebat mutasyonlu olabiliyor
	  ÜS         Crew Morale      — kaidelerin geliri

	Kurallar (eskisi gibi): tavan kat sayısıyla ikiye katlanıyor (1. kat
	taban, 2. kat ×2, 3. kat ×4); etkiler bir tavana yaklaşıyor (azalan
	getiri), yani ileride tavan artsa da oyun kırılmıyor. Rebirth
	yükseltmeleri SIFIRLIYOR (RebirthService).
]]
Config.Upgrades = {
	-- 2026-09-28: "kapsül çok ucuz, çok hızlı maxlanıyor" — hepsi ~3-8 kat pahalı, büyüme dik
	{ id = "SpaceCapsule",    name = "Space Capsule",    category = "training", baseMaxLevel = 6, baseCost = 25000,  costGrowth = 3.0,
	  blurb = "Train your space speed faster in the capsule" },
	{ id = "TrainingConsole", name = "Training Console", category = "training", baseMaxLevel = 5, baseCost = 90000,  costGrowth = 2.9,
	  blurb = "Makes the capsule mini game easier" },
	{ id = "QuickHands",      name = "Quick Hands",      category = "heist",    baseMaxLevel = 5, baseCost = 200000, costGrowth = 2.9,
	  blurb = "Grab lost crewmates faster" },
	{ id = "JetBoost",        name = "Jet Boost",        category = "heist",    baseMaxLevel = 5, baseCost = 500000, costGrowth = 3.0,
	  blurb = "Dash in space (Q). More power, less cooldown" },
	{ id = "StealthSuit",     name = "Stealth Suit",     category = "heist",    baseMaxLevel = 5, baseCost = 1500000, costGrowth = 3.0,
	  blurb = "Monsters wake up later and reach less far" },
	{ id = "LuckyScanner",    name = "Lucky Scanner",    category = "heist",    baseMaxLevel = 5, baseCost = 4000000, costGrowth = 3.1,
	  blurb = "Stolen crewmates may turn mutated" },
	{ id = "CrewMorale",      name = "Crew Morale",      category = "base",     baseMaxLevel = 6, baseCost = 800000, costGrowth = 2.9,
	  blurb = "More cash from every podium" },
} :: { UpgradeDef }

--[[
	2026-09-28: "upgrade sayıları çok daha fazla olmalı, hemen makslanıyor".
	Her yükseltmenin seviyesi UpgradeLevelScale katına çıktı; etkiler
	seviye / UpgradeLevelScale ile hesaplanıyor (tavanda güç aynı), maliyet
	büyümesi kökü alınıp tabanı küçüldü (tavana kadar toplam harcama benzer,
	adımlar küçük). Eski kayıtların seviyesi bu katla çarpılıyor
	(DataService, profile.upgradeScale).
]]
Config.UpgradeLevelScale = 4
for _, def in Config.Upgrades do
	local k = Config.UpgradeLevelScale
	local g = def.costGrowth
	local g2 = g ^ (1 / k)
	def.baseMaxLevel = def.baseMaxLevel * k
	def.baseCost = def.baseCost * (g2 - 1) / (g - 1)
	def.costGrowth = g2
end

--[[ Etki fonksiyonlarının kullandığı "eski ölçekli" seviye (kesirli). ]]
local function upgradeStep(level: number): number
	return math.max(0, level) / Config.UpgradeLevelScale
end

--[[
	Kalkan yükseltmeler: kayıtta bulunursa (DataService sanitize) o seviyelere
	harcanmış para iade ediliyor ve kayıttan siliniyor; bir kez oluyor.
]]
Config.RetiredUpgrades = {
	UnitGuard  = { baseCost = 240000, costGrowth = 2.0 },
	CarrySpeed = { baseCost = 400000, costGrowth = 2.0 },
	LockPower  = { baseCost = 600000, costGrowth = 2.0 },
} :: { [string]: { baseCost: number, costGrowth: number } }

--[[ Kalkan bir yükseltmenin `level` seviyesine kadar harcanan toplam. ]]
function Config.GetRetiredUpgradeRefund(id: string, level: number): number
	local def = Config.RetiredUpgrades[id]
	if not def or level <= 0 then
		return 0
	end
	local total = 0
	for i = 0, math.floor(level) - 1 do
		total += math.floor(def.baseCost * def.costGrowth ^ i)
	end
	return total
end

--[[
	Açık kat sayısına göre tavan. Her kat tavanı ikiye katlıyor.
	floors 1 -> baseMaxLevel, 2 -> x2, 3 -> x4.
]]
function Config.GetUpgradeMaxLevel(def: UpgradeDef, floors: number): number
	local unlocked = math.clamp(floors, 1, Config.MaxFloors)
	return def.baseMaxLevel * 2 ^ (unlocked - 1)
end

--[[ Oyunda ulaşılabilecek en yüksek tavan. Kayıt kırpması buna bakıyor. ]]
function Config.GetUpgradeCeiling(def: UpgradeDef): number
	return Config.GetUpgradeMaxLevel(def, Config.MaxFloors)
end

local upgradesById: { [string]: UpgradeDef } = {}
for _, def in Config.Upgrades do
	upgradesById[def.id] = def
end

function Config.GetUpgrade(id: string): UpgradeDef?
	return upgradesById[id]
end

--[[
	Bir sonraki seviyenin maliyeti. Seviye o katın tavanındaysa nil döner.

	floors verilmezse en yüksek tavan varsayılıyor; sadece fiyat soran
	(tavanı ayrıca kontrol eden) çağrılar için.
]]
function Config.GetUpgradeCost(id: string, currentLevel: number, floors: number?): number?
	local def = upgradesById[id]
	if not def then
		return nil
	end

	local max = if floors then Config.GetUpgradeMaxLevel(def, floors) else Config.GetUpgradeCeiling(def)
	if currentLevel >= max then
		return nil
	end

	-- İki anlamlı basamak: 1234 -> 1200 (fiyatlar okunaklı)
	local cost = def.baseCost * def.costGrowth ^ currentLevel
	if cost >= 100 then
		local unit = 10 ^ (math.floor(math.log10(cost)) - 1)
		cost = math.floor(cost / unit + 0.5) * unit
	end
	return math.floor(cost)
end

-- ─── Yükseltme etkileri (tek yerde: sunucu ve arayüz aynısını kullanıyor) ───

-- 0'dan 1'e yaklaşan azalan getiri: seviye arttıkça her seviye biraz daha az ekliyor
local function saturate(level: number, rate: number): number
	return 1 - rate ^ math.max(0, level)
end

--[[ Quick Hands: kapma süresi çarpanı (1 → ~0.4). ]]
function Config.GetGrabHoldMul(level: number): number
	return 0.4 + 0.6 * (1 - saturate(upgradeStep(level), 0.86))
end

--[[
	Training Console: kapsül mini oyununun kolaylığı (0..1). İstemci
	(CapsuleFX) buna göre yeşil alanı büyütüyor, çubuğu hızlı dolduruyor,
	yavaş boşaltıyor, roketi sakinleştiriyor.
]]
function Config.GetTrainingAssist(level: number): number
	return saturate(upgradeStep(level), 0.84)
end

export type JetBoost = { mul: number, duration: number, cooldown: number }

--[[ Jet Boost: seviye 0'da yok; 1'den itibaren atılma çarpanı, süresi, beklemesi. ]]
function Config.GetJetBoost(level: number): JetBoost?
	if level <= 0 then
		return nil
	end
	local k = saturate(upgradeStep(level - 1), 0.85)
	return {
		mul = 1.6 + 0.5 * k,
		duration = 0.9 + 0.7 * k,
		cooldown = 12 - 6 * k,
	}
end

--[[ Stealth Suit: canavarın uyanma süresi çarpanı ve yakalama menzili çarpanı. ]]
function Config.GetStealth(level: number): (number, number)
	local k = saturate(upgradeStep(level), 0.86)
	return 1 + 1.3 * k, 1 - 0.3 * k
end

--[[ Lucky Scanner: çalınan mutasyonsuz mürettebatın mutasyon kazanma şansı. ]]
function Config.GetLuckyChance(level: number): number
	return 0.3 * saturate(upgradeStep(level), 0.88)
end

--[[ Crew Morale: gelir çarpanı (1 → ~1.6). ]]
function Config.GetMoraleMultiplier(level: number): number
	return 1 + 0.6 * saturate(upgradeStep(level), 0.9)
end

-- ─── Nadirlikler ────────────────────────────────────────────────────────────
export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic" | "Secret"

Config.Rarities = {
	Common    = { order = 1, color = Color3.fromRGB(170, 176, 186) },
	Uncommon  = { order = 2, color = Color3.fromRGB( 80, 200, 120) },
	Rare      = { order = 3, color = Color3.fromRGB( 70, 145, 255) },
	Epic      = { order = 4, color = Color3.fromRGB(170,  95, 255) },
	Legendary = { order = 5, color = Color3.fromRGB(255, 175,  45) },
	Mythic    = { order = 6, color = Color3.fromRGB(255,  70, 110) },
	Secret    = { order = 7, color = Color3.fromRGB( 30,  30,  40) },
}

-- ─── Karakterler ────────────────────────────────────────────────────────────
-- weight: aynı nadirlikteki karakterler arasında çıkma ağırlığı (büyük = sık;
--         nadirliği canavarın odds'u seçiyor, Config.RollSpaceUnit)
-- income: saniyede kazandırdığı para
export type UnitDef = {
	id: string,
	name: string,
	rarity: Rarity,
	price: number,
	income: number,
	weight: number,
	color: Color3,
}

--[[
	═══ DENGE ═══════════════════════════════════════════════════════════════

	Ölçü birimi AMORTİ SÜRESİ: price / income. Karakterin kendi parasını kaç
	saniyede geri ödediği. Oyunun bütün hızı bu tek sayıda.

	ESKİ DURUM: her karakter kendini 21-33 saniyede ödüyordu, üstelik
	nadirlik arttıkça süre KISALIYORDU (Amogus Prime 21.4s, Red Crewmate
	33s). Sonuç: sekiz kaidesi dolu bir oyuncu saniyede yatırdığı paranın
	~%35'ini geri alıyor, yani sermayesi yarım dakikada katlanıyordu. Birkaç
	dakikada milyarlara çıkılmasının sebebi buydu — test sırasında 4.65B
	görüldü.

	YENİ DURUM: amorti süresi nadirlikle UZUYOR.

	    Common  55s → Uncommon 75s → Rare 100s → Epic 135s
	                → Legendary 175s → Mythic 230s → Secret 320s

	Neden artan? Çünkü yüksek nadirlik zaten kendi başına ödül. Kısa amorti
	verirsek pahalı karakter hem daha güçlü hem daha verimli olur ve ucuz
	kaidelerin hiçbir anlamı kalmaz. Uzayan amorti, pahalı karakteri bir
	YATIRIM yapıyor: toplam kazanç çok daha yüksek ama geri dönüş sabır
	istiyor. Bu arada çalma da anlam kazanıyor — rakibin Mythic'i hâlâ
	kendini ödemeden onu çalmak gerçek bir darbe.

	Fiyat merdiveni ~2.1x adımlarla ilerliyor. Her kademede dört karakter
	var (Mythic üç, Secret iki) — eskiden bazı kademelerde tek karakter
	vardı ve konveyörde hep aynı şey çıkıyordu.

	Sayılar elle yazıldı, formülle üretilmedi: yuvarlak fiyatlar oyuncuya
	daha okunaklı geliyor ve tek tek elden geçirilebiliyor.
]]
Config.Units = {
	-- Common — amorti ~55s
	{ id = "RedCrew",     name = "Red Crewmate",       rarity = "Common",    price =        100, income =           2, weight = 1000, color = Color3.fromRGB(197,  17,  17) },
	{ id = "BlueCrew",    name = "Blue Crewmate",      rarity = "Common",    price =        220, income =           4, weight =  920, color = Color3.fromRGB( 19,  46, 210) },
	{ id = "YellowCrew",  name = "Yellow Crewmate",    rarity = "Common",    price =        480, income =           9, weight =  840, color = Color3.fromRGB(241, 224,  90) },
	{ id = "LimeCrew",    name = "Lime Crewmate",      rarity = "Common",    price =       1000, income =          18, weight =  760, color = Color3.fromRGB( 80, 240,  57) },

	-- Uncommon — amorti ~75s
	{ id = "Engineer",    name = "Engineer",           rarity = "Uncommon",  price =       2200, income =          29, weight =  520, color = Color3.fromRGB( 56, 254, 220) },
	{ id = "Scientist",   name = "Scientist",          rarity = "Uncommon",  price =       4800, income =          64, weight =  450, color = Color3.fromRGB( 80, 240, 100) },
	{ id = "Janitor",     name = "Janitor",            rarity = "Uncommon",  price =      10500, income =         140, weight =  390, color = Color3.fromRGB(113,  73,  30) },
	{ id = "Guardian",    name = "Guardian Angel",     rarity = "Uncommon",  price =      23000, income =         307, weight =  330, color = Color3.fromRGB(235, 235, 255) },

	-- Rare — amorti ~100s
	{ id = "Shapeshift",  name = "Shapeshifter",       rarity = "Rare",      price =      50000, income =         500, weight =  195, color = Color3.fromRGB(107,  47, 187) },
	{ id = "VentCrawler", name = "Vent Crawler",       rarity = "Rare",      price =     110000, income =        1100, weight =  165, color = Color3.fromRGB( 62,  71,  78) },
	{ id = "MedbayScan",  name = "Medbay Scanner",     rarity = "Rare",      price =     240000, income =        2400, weight =  140, color = Color3.fromRGB( 90, 200, 255) },
	{ id = "Sheriff",     name = "Sheriff",            rarity = "Rare",      price =     520000, income =        5200, weight =  115, color = Color3.fromRGB(218, 165,  32) },

	-- Epic — amorti ~135s
	{ id = "Impostor",    name = "Impostor",           rarity = "Epic",      price =    1150000, income =        8500, weight =   72, color = Color3.fromRGB(140,  10,  10) },
	{ id = "Reactor",     name = "Reactor Meltdown",   rarity = "Epic",      price =    2500000, income =       18500, weight =   58, color = Color3.fromRGB(255, 120,  20) },
	{ id = "O2Sabotage",  name = "O2 Sabotage",        rarity = "Epic",      price =    5400000, income =       40000, weight =   46, color = Color3.fromRGB(120, 220, 255) },
	{ id = "Emergency",   name = "Emergency Meeting",  rarity = "Epic",      price =   11500000, income =       85000, weight =   36, color = Color3.fromRGB(255,  60,  60) },

	-- Legendary — amorti ~175s
	{ id = "Ejected",     name = "Ejected Into Space", rarity = "Legendary", price =   25000000, income =      143000, weight =   20, color = Color3.fromRGB( 25,  25,  60) },
	{ id = "Polus",       name = "Frost Outpost",      rarity = "Legendary", price =   54000000, income =      309000, weight =   16, color = Color3.fromRGB(190, 210, 225) },
	{ id = "TheSkeld",    name = "The Starship",       rarity = "Legendary", price =  115000000, income =      657000, weight =   12, color = Color3.fromRGB(120, 130, 145) },
	{ id = "Airship",     name = "The Airship",        rarity = "Legendary", price =  250000000, income =     1430000, weight =    9, color = Color3.fromRGB(150, 118,  70) },

	-- Mythic — amorti ~230s
	{ id = "DoubleImp",   name = "Double Impostor",    rarity = "Mythic",    price =  540000000, income =     2350000, weight =    5, color = Color3.fromRGB(190,   0,  55) },
	{ id = "TripleImp",   name = "Triple Impostor",    rarity = "Mythic",    price = 1200000000, income =     5220000, weight =    3, color = Color3.fromRGB(120,   0,  35) },
	{ id = "Jester",      name = "The Jester",         rarity = "Mythic",    price = 2600000000, income =    11300000, weight =    2, color = Color3.fromRGB(238,  84, 187) },

	-- Secret — amorti ~320s
	{ id = "AmogusPrime", name = "Amogus Prime",       rarity = "Secret",    price = 5800000000, income =    18100000, weight =    1, color = Color3.fromRGB( 12,  12,  18) },
	{ id = "TheCrewmate", name = "The Crewmate",       rarity = "Secret",    price =13000000000, income =    40600000, weight =    1, color = Color3.fromRGB(215, 224, 240) },
} :: { UnitDef }

--[[
	═══ 2026-09-27 DENGESİ: PARA ÇOK HIZLI ═════════════════════════════════

	Yayından sonra "para çok hızlı kazanılıyor, fiyatlar artmalı, daha az
	vermeliler". Yukarıdaki tablo elle yazılmış merdiven olarak kalıyor;
	burada iki düğmeyle ölçekleniyor ve okunaklı sayıya yuvarlanıyor
	(iki anlamlı basamak; 100'ün altında tam sayı).

	  UnitPriceScale  — bütün fiyatlar (1.5x)
	  UnitIncomeScale — nadirliğe göre gelir (yüksek nadirlik daha çok düşüyor)

	Amorti süresi (fiyat / gelir) yaklaşık:
	    Common 55s → ~100s   Uncommon 75s → ~160s   Rare 100s → ~240s
	    Epic 135s → ~350s    Legendary 175s → ~480s
	    Mythic 230s → ~620s  Secret 320s → ~890s
	Common hızlı kalıyor ki yeni oyuncunun ilk dakikaları sıkıcı olmasın.
]]
Config.UnitPriceScale = 1.5
Config.UnitIncomeScale = {
	Common = 0.75, Uncommon = 0.7, Rare = 0.62, Epic = 0.58,
	Legendary = 0.55, Mythic = 0.55, Secret = 0.55,
} :: { [string]: number }

local function niceNumber(x: number): number
	if x < 100 then
		return math.max(1, math.floor(x + 0.5))
	end
	local step = 10 ^ (math.floor(math.log10(x)) - 1)
	return math.floor(x / step + 0.5) * step
end

for _, unit in Config.Units do
	unit.price = niceNumber(unit.price * Config.UnitPriceScale)
	unit.income = niceNumber(unit.income * (Config.UnitIncomeScale[unit.rarity] or 1))
end

-- ─── Mutasyonlar ────────────────────────────────────────────────────────────
-- Uzayda (ve bedava ödüllerde) çıkan her karaktere sırayla bakılır, ilk tutan uygulanır.
export type MutationDef = {
	id: string,
	name: string,
	chance: number,
	incomeMul: number,
	tint: Color3?,
}

-- Toplam mutasyon şansı ~%13. Tek tek çarpılıyor, o yüzden
-- bir tanesini yükseltmek toplamı beklediğinden çok artırır.
Config.Mutations = {
	{ id = "Impostor", name = "IMPOSTOR", chance = 0.004, incomeMul = 30, tint = Color3.fromRGB(190,  15,  40) },
	{ id = "Golden",   name = "Golden",   chance = 0.012, incomeMul = 15, tint = Color3.fromRGB(255, 200,  60) },
	{ id = "Ejected",  name = "Ejected",  chance = 0.025, incomeMul =  8, tint = Color3.fromRGB( 40,  40,  90) },
	{ id = "Vented",   name = "Vented",   chance = 0.050, incomeMul =  4, tint = Color3.fromRGB( 90, 110, 120) },
	{ id = "Sus",      name = "Sus",      chance = 0.050, incomeMul =  2, tint = Color3.fromRGB(255, 120, 180) },
} :: { MutationDef }

-- Mutasyonlu karakterin fiyat çarpanı = incomeMul * bu sayı.
-- Gelir çarpanı ise incomeMul'ün tamamı. Yani 0.6'da mutasyonlu karakter
-- kendini normalden %40 daha hızlı amorti eder — şans vuruşu her zaman
-- kârlı. 1.0 yaparsan mutasyon sadece "daha büyük ama aynı verimde"
-- bir karakter olur.
Config.MutationPriceFactor = 0.6

--[[
	Satınca karakter değerinin (price) bu kadarı gelir.

	2026-09-27: 0.5 → 0.25. Konveyörde karakter parayla alınıyordu, satış
	zararına bir iadeydi. Artık canavarlardan BEDAVA çalınıyor; yarı değer
	"çal-sat" döngüsünü gelirden hızlı bir para musluğuna çeviriyordu. Şimdi
	satış kaide açmak içindir: tutmak her zaman daha kârlı (Common ~20 sn,
	Secret ~4 dk'lık geliri eder).
]]
Config.SellRefundFactor = 0.25
--[[
	2026-09-28: satış karakterin GELİRİNE bağlandı (değerine değil). Karakterler
	bedava çalındığı için değer (price) üzerinden satış nadirlikle aşırı
	büyüyordu. Satış = SellIncomeSeconds saniyelik gelir (mutasyon dahil):
	kaide açmak için mantıklı, çal-sat döngüsü tutmaktan hep kârsız.
]]
Config.SellIncomeSeconds = 45

-- ─── Yardımcılar ────────────────────────────────────────────────────────────

local unitsById: { [string]: UnitDef } = {}
for _, unit in Config.Units do
	unitsById[unit.id] = unit
end

function Config.GetUnit(id: string): UnitDef?
	return unitsById[id]
end

function Config.GetMutation(id: string?): MutationDef?
	if id == nil then
		return nil
	end
	for _, mutation in Config.Mutations do
		if mutation.id == id then
			return mutation
		end
	end
	return nil
end

--[[
	Karakterin değeri (eskiden konveyördeki fiyatı). Satış bunun
	SellRefundFactor'ü; çalınan karakter sahibine iade edilemediğinde para
	iadesi ve çalma süresi de buradan. Tek kaynak.
]]
function Config.GetPrice(unitId: string, mutationId: string?): number
	local def = unitsById[unitId]
	if not def then
		return 0
	end

	local mutation = Config.GetMutation(mutationId)
	local multiplier = if mutation then mutation.incomeMul * Config.MutationPriceFactor else 1
	return math.floor(def.price * multiplier)
end

--[[
	En düşük karakter değeri. (Konveyör döneminde "kilitlenme koruması"
	buna bakıyordu; karakterler artık bedava, koruma kalktı.)
]]
local cheapestPrice: number? = nil
function Config.GetCheapestUnitPrice(): number
	if not cheapestPrice then
		local lowest = math.huge
		for _, unit in Config.Units do
			if unit.price < lowest then
				lowest = unit.price
			end
		end
		cheapestPrice = lowest
	end
	return cheapestPrice :: number
end

--[[ Karakteri satınca eline geçen para. ]]
function Config.GetSellPrice(unitId: string, mutationId: string?): number
	local def = Config.GetUnit(unitId)
	if not def then
		return 0
	end
	local mutation = Config.GetMutation(mutationId)
	local income = def.income * (if mutation then mutation.incomeMul else 1)
	return math.max(1, math.floor(income * Config.SellIncomeSeconds))
end

--[[ Bir sonraki rebirth'ün maliyeti. Seviye 0 -> ilk rebirth'ün fiyatı. ]]
function Config.GetRebirthCost(rebirths: number): number
	return math.floor(Config.RebirthBaseCost * Config.RebirthCostGrowth ^ rebirths)
end

--[[ Rebirth sayısının getirdiği kalıcı gelir çarpanı. 0 -> 1.0 ]]
function Config.GetIncomeMultiplier(rebirths: number): number
	return 1 + rebirths * Config.RebirthIncomeBonus
end

--[[ Kaç kat açık. İlk kat bedava, her rebirth bir kat daha açar. ]]
--[[
	Açık kat sayısı.

	1. kat herkeste açık. Üstü satın alındığı kadar — rebirth koşulu
	satın alma anında aranıyor, sonradan geri alınmıyor.
]]
function Config.GetUnlockedFloors(floorsBought: number): number
	return math.clamp(1 + floorsBought, 1, Config.MaxFloors)
end

--[[ Açık katlarla birlikte toplam kaç kaide kullanılabilir. ]]
function Config.GetUnlockedPodiumCount(floorsBought: number): number
	return Config.GetUnlockedFloors(floorsBought) * Config.PodiumsPerPlot
end

--[[
	Oyuncu yokken biriken kazanç. Tam oran verilmiyor ve tavanı var;
	yoksa uzun süre girmemek oynamaktan kârlı hale gelir.
]]
function Config.GetOfflineEarnings(incomePerSecond: number, secondsAway: number): number
	if incomePerSecond <= 0 or secondsAway <= 0 then
		return 0
	end

	local capped = math.min(secondsAway, Config.OfflineIncomeCapHours * 3600)
	return math.floor(incomePerSecond * capped * Config.OfflineIncomeRate)
end

--[[
	Konveyörün seviyeye bağlı nadirlik kilidi (RarityUnlock, RollUnit,
	RollAffordableUnit) 2026-09-27'de kalktı: nadirliği artık canavarın
	havuzu seçiyor (Config.SpaceMonsters[i].odds, Config.RollSpaceUnit).
]]

--[[ Mutasyon çeker, çıkmazsa nil döner. ]]
function Config.RollMutation(rng: Random): MutationDef?
	for _, mutation in Config.Mutations do
		if rng:NextNumber() < mutation.chance then
			return mutation
		end
	end
	return nil
end

-- ─── Petler ─────────────────────────────────────────────────────────────────
--[[
	═══ NE İŞE YARIYORLAR ══════════════════════════════════════════════════

	Pet, oyuncunun peşinden gelen küçük bir yoldaş ve iki şeye dokunuyor:
	GELİR yüzdesi ve TAŞIMA HIZI. İkisi de oyunun iki ana fiiline karşılık
	geliyor — kaide doldurmak ve çalmak.

	Neden bu iki stat? Çünkü oyuncunun zaten umursadığı sayılar bunlar ve
	ikisi de HUD'da görünüyor. Üçüncü bir stat eklemek (şans, kilit süresi)
	peti "bir sürü küçük yüzde" haline getirirdi; bakışta ne yaptığı
	anlaşılmazdı.

	═══ NEDEN YUMURTA ══════════════════════════════════════════════════════

	Peti doğrudan satmak, parası olanın istediğini alması demek — nadirlik
	kademesi anlamsızlaşır. Yumurta ise PARAYLA ALINIYOR ama içinden ne
	çıkacağı şansa bağlı: para sadece daha iyi bir havuza giriş bileti.

	Her yumurtanın KENDİ pet takımı var ve her yumurta Common'dan
	başlıyor. Bu kasten: pahalı yumurtanın kötü sonucu da olsun ki açmak
	heyecanlı kalsın — ama o kötü sonuç bile alt yumurtanın aynı
	kademesinden güçlü (aşağıda, PET_TIER x EGG_TIER).

	═══ DENGE ══════════════════════════════════════════════════════════════

	Üç pet takılabiliyor ve bonuslar TOPLANIYOR. Üç Void Secret +%600
	gelir demek — çok gibi duruyor ama Secret yalnızca son iki yumurtadan
	ve binde 3-5 ağırlıkla çıkıyor; oraya gelen oyuncu zaten oyunun sonunda.

	Gelir çarpanı rebirth ve gamepass ile ÇARPILIYOR (EconomyService),
	toplanmıyor. Yani pet her kademede aynı oranda işe yarıyor.
]]
export type PetDef = {
	id: string,
	name: string,
	rarity: Rarity,
	egg: string,           -- çıktığı TEK yumurta (Config.Eggs kimliği)
	incomeBonus: number,   -- gelire eklenen oran (0.25 = +%25)
	speedBonus: number,    -- taşıma hızına eklenen stud/s
	color: Color3,
}

--[[
	═══ PET GÜCÜ = KADEME x YUMURTA ═════════════════════════════════════════

	Her pet TEK bir yumurtadan çıkıyor ve her yumurtanın kendi pet takımı
	var (kademe başına bir pet). Eskiden petler yumurtadan bağımsızdı ve
	bonus yalnızca kademeye bağlıydı: 9 milyarlık Void yumurtasının
	Common'ı 50 binlik Supply yumurtasının Common'ıyla birebir aynı gücü
	veriyordu. Artık:

	    bonus = kademe tabanı (PET_TIER) x yumurta çarpanı (EGG_TIER)

	Kademe tabanı yumurta içinde sıralamayı, yumurta çarpanı yumurtalar
	arasındaki farkı veriyor. Sonuç (gelir, düz boy):

	              Common Uncommon Rare  Epic  Legendary Mythic Secret
	    Supply      2%     4%     7%    12%     20%       -      -
	    Skeld       3%     6%    11%    19%     32%      51%     -
	    Polus       5%    10%    18%    30%     50%      80%   125%
	    Void        8%    16%    28%    48%     80%     128%   200%

	Pahalı yumurtanın en kötü sonucu da ucuzunkinden iyi (Void Common %8 >
	Supply Common %2), ama bir alt yumurtanın iyi sonucu hâlâ değerli
	(Supply Epic %12 > Void Common %8): alt yumurtayı açmak boşa gitmiyor.

	Denge değiştirmek isteyen iki küçük tabloya bakıyor.
]]
local PET_TIER = {
	Common    = { income = 0.02, speed = 0.05 },
	Uncommon  = { income = 0.04, speed = 0.09 },
	Rare      = { income = 0.07, speed = 0.15 },
	Epic      = { income = 0.12, speed = 0.24 },
	Legendary = { income = 0.20, speed = 0.36 },
	Mythic    = { income = 0.32, speed = 0.50 },
	Secret    = { income = 0.50, speed = 0.70 },
}

local EGG_TIER = {
	SupplyEgg = { income = 1.0, speed = 1.0 },
	SkeldEgg  = { income = 1.6, speed = 1.25 },
	PolusEgg  = { income = 2.5, speed = 1.55 },
	VoidEgg   = { income = 4.0, speed = 1.9 },
}

--[[
	═══ PET TİPİ (şu an kullanılmıyor) ═══════════════════════════════════

	pet(..., style) ile aynı kademedeki petlere farklı stat verilebilir:
	kazandıran (gelir önde) / koşucu (hız önde) / dengeli. 2026-09-26'da
	56 pete çıkılıp geri 25'e dönüldü; şimdi her kademede tek pet ve hepsi
	dengeli. Yeni pet eklenirse buradan farklılaştır — aralıklar dar ki
	en kötü Rare bile en iyi Uncommon'dan fazla gelir versin.
]]
local PET_STYLE = {
	balanced = { income = 1.0, speed = 1.0 },
	earner   = { income = 1.15, speed = 0.8 },   -- kazandıran: gelir önde
	runner   = { income = 0.85, speed = 1.25 },  -- koşucu: taşıma hızı önde
}

local function pet(id: string, name: string, rarity: Rarity, egg: string, color: Color3, style: string?): PetDef
	local base = PET_TIER[rarity]
	local eggTier = EGG_TIER[egg]
	local st = PET_STYLE[style or "balanced"]
	local tier = { income = base.income * st.income, speed = base.speed * st.speed }
	-- Binde bire yuvarla: kayan nokta artığı arayüzde "+%3" yerine "+%2.99..." olmasın
	local function round(x: number): number
		return math.floor(x * 1000 + 0.5) / 1000
	end
	return {
		id = id,
		name = name,
		rarity = rarity,
		egg = egg,
		incomeBonus = round(tier.income * eggTier.income),
		speedBonus = round(tier.speed * eggTier.speed),
		color = color,
	}
end

--[[
	Petler, yumurtalara göre. Hepsi Skeld'in / Among Us evreninin kendi
	eşyalarından: bir görev konsolu, bir yedek kask, havalandırmadan çıkan
	bir şey. Among Us'tan HAZIR VARLIK kopyalanmıyor — alınan şey mekânın
	dili.

	Kimlikler eski kayıtlarla aynı: petlerin yumurtası ve kademesi değişti,
	oyuncunun envanteri olduğu gibi okunuyor (yalnızca bonus yeni tablodan).
]]
Config.Pets = {
	-- Supply Egg: erzak dolabından çıkanlar
	pet("Bolt",       "Loose Bolt",       "Common",    "SupplyEgg", Color3.fromRGB(176, 184, 196)),
	pet("VentRat",    "Vent Rat",         "Uncommon",  "SupplyEgg", Color3.fromRGB(113,  73,  30)),
	pet("Hamster",    "Cargo Hamster",    "Rare",      "SupplyEgg", Color3.fromRGB(226, 186, 120)),
	pet("SparePod",   "Spare Helmet",     "Epic",      "SupplyEgg", Color3.fromRGB(150, 222, 236)),
	pet("FuelCan",    "Fuel Canister",    "Legendary", "SupplyEgg", Color3.fromRGB(255, 196,  40)),

	-- Skeld Egg: geminin mürettebatı ve makineleri
	pet("MiniCrew",   "Mini Crew",        "Common",    "SkeldEgg",  Color3.fromRGB(197,  17,  17)),
	pet("BrainSlug",  "Brain Slug",       "Uncommon",  "SkeldEgg",  Color3.fromRGB(238, 132, 195)),
	pet("TaskBot",    "Task Bot",         "Rare",      "SkeldEgg",  Color3.fromRGB( 56, 254, 220)),
	pet("MedDrone",   "Medbay Drone",     "Epic",      "SkeldEgg",  Color3.fromRGB( 90, 200, 255)),
	pet("SecurityCam","Security Cam",     "Legendary", "SkeldEgg",  Color3.fromRGB(120, 220, 255)),
	pet("PrimeShield","Prime Shield",     "Mythic",    "SkeldEgg",  Color3.fromRGB( 70, 150, 255)),

	-- Polus Egg: buzul üssü ve reaktör
	pet("SnowPal",    "Snow Pal",         "Common",    "PolusEgg",  Color3.fromRGB(190, 210, 225)),
	pet("VentCrab",   "Vent Crab",        "Uncommon",  "PolusEgg",  Color3.fromRGB( 62,  71,  78)),
	pet("CoreShard",  "Reactor Shard",    "Rare",      "PolusEgg",  Color3.fromRGB(255, 120,  20)),
	pet("EscapePod",  "Escape Pod",       "Epic",      "PolusEgg",  Color3.fromRGB(215, 224, 240)),
	pet("SusShadow",  "Sus Shadow",       "Legendary", "PolusEgg",  Color3.fromRGB(107,  47, 187)),
	pet("MeetingBell","Emergency Bell",   "Mythic",    "PolusEgg",  Color3.fromRGB(255,  70, 110)),
	pet("TheEgg",     "The Egg",          "Secret",    "PolusEgg",  Color3.fromRGB(238, 230, 214)),

	-- Void Egg: geminin dışı, boşluk
	pet("VoidMite",   "Void Mite",        "Common",    "VoidEgg",   Color3.fromRGB( 96,  64, 150)),
	pet("StarJelly",  "Star Jelly",       "Uncommon",  "VoidEgg",   Color3.fromRGB(255, 140, 220)),
	pet("CometPup",   "Comet Pup",        "Rare",      "VoidEgg",   Color3.fromRGB(110, 230, 255)),
	pet("GhostCrew",  "Ejected Ghost",    "Epic",      "VoidEgg",   Color3.fromRGB(170, 190, 255)),
	pet("MiniImp",    "Mini Impostor",    "Legendary", "VoidEgg",   Color3.fromRGB(190,   0,  55)),
	pet("NebulaEye",  "Nebula Eye",       "Mythic",    "VoidEgg",   Color3.fromRGB(200,  90, 255)),
	pet("VoidShard",  "Void Shard",       "Secret",    "VoidEgg",   Color3.fromRGB( 18,  18,  26)),
} :: { PetDef }

-- Aynı anda takılabilecek pet sayısı. Üç: sıralı bir seçim yapacak kadar
-- az, "hangisi daha iyi" sorusunu anlamlı kılacak kadar çok.
Config.PetEquipSlots = 3

--[[
	Envanter tavanı. Sınırsız olsaydı kayıt dosyası büyür ve arayüz
	kullanılmaz hale gelirdi. Aynı petten birden fazla tutuluyor (adet),
	yani tavan ÇEŞİT sayısı değil, kayıt satırı sayısı.
]]
Config.PetStackLimit = 99

--[[
	═══ PET MUTASYONLARI ═══════════════════════════════════════════════════

	Karakter mutasyonlarından AYRI bir tablo. Onlarınki gelir çarpanı
	x2..x30; pete x30 verseydik tek bir Cosmic Secret +%3750 gelir demekti
	ve oyun biterdi. Burada çarpan petin BONUSUNA uygulanıyor ve en fazla
	x3.

	Şans yumurta açarken bir kez atılıyor; birleştirmede mutasyon
	KORUNUYOR (üç Golden -> bir Golden). Böylece mutasyonlu kopya
	toplamanın da bir anlamı oluyor.
]]
export type PetMutationDef = {
	id: string,
	name: string,
	chance: number,
	multiplier: number,
	tint: Color3,
}

Config.PetMutations = {
	-- Sıra önemli: en nadir önce denenir, tutan uygulanır
	{ id = "Cosmic",  name = "Cosmic",  chance = 0.005, multiplier = 3.0, tint = Color3.fromRGB(150,  90, 255) },
	{ id = "Crystal", name = "Crystal", chance = 0.020, multiplier = 2.0, tint = Color3.fromRGB(120, 230, 255) },
	{ id = "Golden",  name = "Golden",  chance = 0.050, multiplier = 1.5, tint = Color3.fromRGB(255, 200,  60) },
} :: { PetMutationDef }

function Config.GetPetMutation(id: string?): PetMutationDef?
	if not id or id == "" then
		return nil
	end
	for _, def in Config.PetMutations do
		if def.id == id then
			return def
		end
	end
	return nil
end

function Config.RollPetMutation(rng: Random): PetMutationDef?
	for _, def in Config.PetMutations do
		if rng:NextNumber() < def.chance then
			return def
		end
	end
	return nil
end

--[[
	═══ BOYUT KADEMELERİ (BİRLEŞTİRME) ═════════════════════════════════════

	Birleştirme petin NADİRLİĞİNİ değil BOYUTUNU büyütüyor: aynı petten
	üç tane -> o petin BIG hâli; üç BIG -> HUGE; üç HUGE -> TITAN. Tür ve
	mutasyon aynı kalıyor, sahadaki model de gözle görülür şekilde büyüyor.

	Eskiden üç kopya bir üst kademeden RASTGELE bir pete dönüşüyordu; en
	sevdiğin peti birleştirince elinde başka bir pet kalıyordu ve Secret
	hiç birleştirilemiyordu.

	Çarpan petin bonusuna uygulanıyor (mutasyonla ÇARPILARAK):

	    Big x2.5 (3 kopya) · Huge x5 (9) · Titan x10 (27)

	Üç kopyanın ham toplamı x3; Big x2.5 ondan biraz AZ ama tek slota
	sığıyor — slot üç tane, yani birleştirme slot verimliliği. Titan için
	aynı petten 27 tane gerekiyor: oyunun sonundaki hedef bu.
]]
export type PetSizeDef = {
	id: string,
	name: string,
	multiplier: number,
	scale: number,       -- sahadaki model ölçeği (PetModel)
}

Config.PetSizes = {
	{ id = "Big",   name = "Big",   multiplier = 2.5, scale = 1.5 },
	{ id = "Huge",  name = "Huge",  multiplier = 5,   scale = 2.2 },
	{ id = "Titan", name = "Titan", multiplier = 10,  scale = 3.2 },
} :: { PetSizeDef }

function Config.GetPetSize(id: string?): PetSizeDef?
	if not id or id == "" then
		return nil
	end
	for _, def in Config.PetSizes do
		if def.id == id then
			return def
		end
	end
	return nil
end

--[[ Bir sonraki boyut. Normal -> Big -> Huge -> Titan -> nil. ]]
function Config.GetNextPetSize(current: PetSizeDef?): PetSizeDef?
	if not current then
		return Config.PetSizes[1]
	end
	local index = table.find(Config.PetSizes, current)
	return if index then Config.PetSizes[index + 1] else nil
end

--[[
	═══ ENVANTER ANAHTARI ══════════════════════════════════════════════════

	Envanter "anahtar -> adet" tablosu. Aynı petin Golden'ı, Huge'ı ve
	düzü AYRI satır olmalı, ama tabloyu iç içe yapmak kayıt biçimini ve
	bütün okuyucuları değiştirirdi.

	Anahtar: pet kimliği, ardından sırayla isteğe bağlı mutasyon ve boyut.

	    "MiniCrew"   "MiniCrew:Golden"   "MiniCrew:Huge"   "MiniCrew:Golden:Huge"

	Mutasyon ve boyut kimlikleri birbirinden farklı olduğu için hangisinin
	hangisi olduğu adından anlaşılıyor. Düz pet eski biçimle birebir aynı,
	yani mevcut kayıtlar olduğu gibi okunuyor.
]]
function Config.PetKey(petId: string, mutationId: string?, sizeId: string?): string
	local key = petId
	if mutationId and mutationId ~= "" then
		key ..= ":" .. mutationId
	end
	if sizeId and sizeId ~= "" then
		key ..= ":" .. sizeId
	end
	return key
end

--[[
	Anahtarı çözer: (pet, mutasyon?, boyut?). Pet, mutasyon ya da boyut
	tanınmıyorsa pet nil döner — çağıran o satırı atlamalı (Config'ten
	kalkmış bir şey kayıtta kalmış olabilir). Tanınmayanı sessizce atmak
	oyuncunun elinden bir şey almak olurdu.
]]
function Config.ParsePetKey(key: string): (PetDef?, PetMutationDef?, PetSizeDef?)
	local parts = string.split(key, ":")
	-- Config.GetPet aşağıda tanımlı; çağrı anında çözülüyor
	local def = Config.GetPet(parts[1])
	if not def or #parts > 3 then
		return nil, nil, nil
	end

	local mutation: PetMutationDef? = nil
	local size: PetSizeDef? = nil
	for i = 2, #parts do
		local part = parts[i]
		local m = Config.GetPetMutation(part)
		local s = Config.GetPetSize(part)
		if m and not mutation and not size then
			mutation = m
		elseif s and not size then
			size = s
		else
			return nil, nil, nil
		end
	end
	return def, mutation, size
end

--[[ "Golden Huge Mini Crew" gibi okunur ad. ]]
function Config.PetDisplayName(key: string): string
	local def, mutation, size = Config.ParsePetKey(key)
	if not def then
		return key
	end
	local name = def.name
	if size then
		name = size.name .. " " .. name
	end
	if mutation then
		name = mutation.name .. " " .. name
	end
	return name
end

-- Aynı anahtardan kaç kopya bir üst boyuta birleşiyor
Config.PetFuseCount = 3
--[[
	Verilen kademeden eşit şansla bir pet. Yumurta çekilişinin ikinci
	aşaması; `eggId` verilirse yalnızca o yumurtanın petleri.
]]
function Config.RollPetOfRarity(rng: Random, rarity: string, eggId: string?): PetDef?
	local pool = {}
	for _, def in Config.Pets do
		if def.rarity == rarity and (eggId == nil or def.egg == eggId) then
			table.insert(pool, def)
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[rng:NextInteger(1, #pool)]
end

export type EggDef = {
	id: string,
	name: string,
	price: number,
	weights: { [string]: number },  -- nadirlik -> ağırlık
	tint: Color3,                   -- yumurtanın ışık/yazı rengi (kuluçka ve arayüz)
}

--[[
	Yumurtalar. Fiyatları o kademedeki karakterlerin fiyatına yakın:
	yumurta, kaideye bir karakter daha koymakla yarışmalı.

	Her yumurta Common'dan başlıyor ve pahalandıkça üst kademe ekliyor:
	Supply'da tek bir Legendary (binde 6), Skeld'de tek bir Mythic (binde
	4) — ucuz yumurtanın da "belki çıkar" diye açılan bir ödülü olsun;
	Polus ve Void'de Mythic ve Secret de var. Kademe oranları bütün yumurtalarda aynı
	merdiven (Common en sık, Secret binde birkaç); fark petlerin gücünde
	(EGG_TIER) ve yeni kademelerde.

	`tint` eskiden havuzun en iyi kademesinden hesaplanıyordu; artık iki
	yumurtada Secret var ve ikisi aynı renge düşerdi, o yüzden elle.
]]
Config.Eggs = {
	{ id = "SupplyEgg", name = "Supply Egg", price =         50000,
		weights = { Common = 59.4, Uncommon = 28, Rare = 10, Epic = 2, Legendary = 0.6 },
		tint = Color3.fromRGB(170, 95, 255) },
	{ id = "SkeldEgg",  name = "Station Egg", price =       2500000,
		weights = { Common = 45.6, Uncommon = 30, Rare = 15, Epic = 7, Legendary = 2, Mythic = 0.4 },
		tint = Color3.fromRGB(255, 175, 45) },
	{ id = "PolusEgg",  name = "Frost Egg",  price =     150000000,
		weights = { Common = 42, Uncommon = 28, Rare = 16, Epic = 8.5, Legendary = 4, Mythic = 1.2, Secret = 0.3 },
		tint = Color3.fromRGB(255, 70, 110) },
	{ id = "VoidEgg",   name = "Void Egg",   price =    9000000000,
		weights = { Common = 38, Uncommon = 27, Rare = 17, Epic = 10, Legendary = 5.5, Mythic = 2, Secret = 0.5 },
		tint = Color3.fromRGB(30, 30, 40) },
} :: { EggDef }

--[[ Bir yumurtanın petleri, kademe sırasıyla (Common önce). ]]
function Config.GetEggPets(eggId: string): { PetDef }
	local out = {}
	for _, def in Config.Pets do
		if def.egg == eggId then
			table.insert(out, def)
		end
	end
	-- Kademe, aynı kademede gelir, sonra kimlik: sıra her açılışta aynı kalsın
	table.sort(out, function(a, b)
		local ra, rb = Config.Rarities[a.rarity].order, Config.Rarities[b.rarity].order
		if ra ~= rb then
			return ra < rb
		end
		if a.incomeBonus ~= b.incomeBonus then
			return a.incomeBonus < b.incomeBonus
		end
		return a.id < b.id
	end)
	return out
end

--[[
	Bir petin o yumurtadan çıkma şansı (yüzde). Önce kademe çekiliyor,
	sonra kademedeki petlerden biri eşit şansla — yani kademe şansı o
	kademedeki pet sayısına bölünüyor. Arayüz (yumurta paneli, indeks)
	buradan okuyor.
]]
function Config.GetPetChance(eggId: string, petId: string): number
	local egg = Config.GetEgg(eggId)
	local def = Config.GetPet(petId)
	if not (egg and def) or def.egg ~= eggId then
		return 0
	end
	local total = 0
	for _, w in egg.weights do
		total += w
	end
	local same = 0
	for _, other in Config.Pets do
		if other.egg == eggId and other.rarity == def.rarity then
			same += 1
		end
	end
	return (egg.weights[def.rarity] or 0) / math.max(total, 1e-6) * 100 / math.max(same, 1)
end

local petsById: { [string]: PetDef } = {}
for _, def in Config.Pets do
	petsById[def.id] = def
end

function Config.GetPet(id: string): PetDef?
	return petsById[id]
end

function Config.GetEgg(id: string): EggDef?
	for _, def in Config.Eggs do
		if def.id == id then
			return def
		end
	end
	return nil
end

--[[
	Yumurtadan bir pet çeker.

	İki aşamalı: önce KADEME seçiliyor (yumurtanın ağırlıklarıyla), sonra
	o kademedeki petlerden biri eşit şansla. Tek aşamalı olsaydı kademede
	üç pet olması o kademeyi üç kat sık yapardı — yani yeni bir pet eklemek
	dengeyi sessizce bozardı.
]]
function Config.RollPet(rng: Random, eggId: string): PetDef?
	local egg = Config.GetEgg(eggId)
	if not egg then
		return nil
	end

	local total = 0
	for _, weight in egg.weights do
		total += weight
	end
	if total <= 0 then
		return nil
	end

	local roll = rng:NextNumber(0, total)
	local chosen: string? = nil
	for rarity, weight in egg.weights do
		roll -= weight
		if roll <= 0 then
			chosen = rarity
			break
		end
	end
	if not chosen then
		return nil
	end

	return Config.RollPetOfRarity(rng, chosen, eggId)
end

--[[
	Tek bir envanter anahtarının bonusu: petin kademe bonusu x mutasyon x boyut.
]]
function Config.GetPetKeyBonus(key: string): (number, number)
	local def, mutation, size = Config.ParsePetKey(key)
	if not def then
		return 0, 0
	end
	local mul = (if mutation then mutation.multiplier else 1) * (if size then size.multiplier else 1)
	return def.incomeBonus * mul, def.speedBonus * mul
end

--[[
	Takılı petlerin toplam bonusu. Liste envanter ANAHTARLARI tutuyor
	("MiniCrew" ya da "MiniCrew:Golden").

	Bilinmeyen anahtarlar sessizce atlanıyor: bir pet Config'den
	kaldırılırsa eski kayıtlar oyunu kırmasın.
]]
function Config.GetPetBonus(equipped: { string }): (number, number)
	local income, speed = 0, 0
	for index, key in equipped do
		if index > Config.PetEquipSlots then
			break
		end
		local i, s = Config.GetPetKeyBonus(key)
		income += i
		speed += s
	end
	return income, speed
end

-- ─── Ekipman (lobideki Gear Shop) ───────────────────────────────────────────
--[[
	Oyun içi parayla bir kez alınan, kalıcı aletler. Her doğuşta sırt
	çantasına geliyor.

	2026-09-28 (Yusuf): aletler canavarlara İŞLEMİYOR; OYUNCULARA (ve
	gemide gezen impostora) işliyor. Uzayda da kullanılıyor, oyuncular
	birbirini hafifçe sabote edebiliyor: uzayda sersemlik/savrulma ×0.6 ve
	vurulan dönerek sürükleniyor (istasyonda yere savruluyor). Taşınan
	mürettebat düşmüyor. Vurulan GearHitImmunity sn tekrar vurulamıyor
	(GearService).

	Speed Coil yalnızca gemide (uzayda uçuş hızı kapsülden geliyor).
]]
export type GearDef = {
	id: string,
	name: string,
	price: number,
	blurb: string,
	kind: string,          -- "slap" | "speed" | "stun" | "blast"
	walkSpeed: number?,    -- speed: elde tutarken yürüme hızı
	sprintSpeed: number?,  -- speed: elde tutup Shift'e basınca
	cooldown: number?,     -- iki kullanım arası saniye
	range: number?,        -- menzil / etki yarıçapı (stud)
	stun: number?,         -- vurulan oyuncunun sersem kaldığı saniye (uzayda ×0.6)
	knock: number?,        -- vurulan oyuncunun savrulma hızı (uzayda ×0.6)
}

Config.Gear = {
	{ id = "SlapGlove",       name = "Slap Glove",       price =      250000, kind = "slap",
		cooldown = 8, range = 16, stun = 1.5, knock = 18,
		blurb = "Slap the player in front of you: knocked back and dazed. Works in space too!" },
	{ id = "SpeedCoil",       name = "Speed Coil",       price =     1500000, kind = "speed",
		walkSpeed = 32, sprintSpeed = 40,
		blurb = "Run way faster on the ship while holding it." },
	{ id = "StunGun",         name = "Stun Gun",         price =    12000000, kind = "stun",
		cooldown = 20, range = 45, stun = 3,
		blurb = "Zap a player from afar: frozen for 3s. In space they spin out!" },
	{ id = "EmergencyButton", name = "Emergency Button", price =   300000000, kind = "blast",
		cooldown = 40, range = 28, stun = 2.5, knock = 30,
		blurb = "Slam it: every player around you is blasted away and dazed." },
} :: { GearDef }

--[[
	Kaldırılan aletler -> iade. Kayıtta bulunursa (DataService sanitize)
	aletin fiyatı paraya ekleniyor ve kayıttan siliniyor; bir kez oluyor.
]]
-- Vurulan oyuncu bu kadar saniye tekrar vurulamıyor (sersemleme kilidi olmasın)
Config.GearHitImmunity = 3

Config.RetiredGear = {
	GravityCoil = 800000,
	-- 2026-09-27: "çok güçlü" — görünmezlik hem gemide hem uzayda fazla kaçırıyordu
	GhostSerum = 75000000,
} :: { [string]: number }

function Config.GetGear(id: string): GearDef?
	for _, def in Config.Gear do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- ─── Kozmetikler ────────────────────────────────────────────────────────────
--[[
	Oyuncunun kendi karakterine şapka ve koşarken arkasında kalan iz.
	Oyun içi parayla alınıyor ve KALICI (rebirth'te gitmiyor).

	Neden: geç oyunda milyarları harcayacak yer azdı; kozmetik oynanışı
	değiştirmeyen bir para çukuru — güç vermiyor, gösteriş veriyor. Fiyat
	merdiveni erken oyundan (10K) geç oyuna (10B) uzanıyor ki her aşamada
	alınacak bir şey olsun.

	Görünüşleri src/shared/CosmeticModel.luau'da (hazır varlık yok).
]]
export type CosmeticDef = {
	id: string,
	name: string,
	kind: string,       -- "hat" | "trail"
	price: number,
	rarity: Rarity,
	color: Color3,
	colors: { Color3 }?, -- iz renk geçişi (yoksa tek renk)
}

Config.Cosmetics = {
	-- Şapkalar
	{ id = "Sprout",      name = "Sprout",        kind = "hat", price = 10_000,        rarity = "Common",    color = Color3.fromRGB(90, 200, 90) },
	{ id = "PartyHat",    name = "Party Hat",     kind = "hat", price = 50_000,        rarity = "Common",    color = Color3.fromRGB(60, 140, 240) },
	{ id = "ToiletPaper", name = "Toilet Paper",  kind = "hat", price = 150_000,       rarity = "Uncommon",  color = Color3.fromRGB(242, 244, 248) },
	{ id = "Antenna",     name = "Antenna",       kind = "hat", price = 500_000,       rarity = "Uncommon",  color = Color3.fromRGB(210, 40, 50) },
	{ id = "FriedEgg",    name = "Fried Egg",     kind = "hat", price = 2_000_000,     rarity = "Rare",      color = Color3.fromRGB(250, 200, 60) },
	{ id = "ChefHat",     name = "Chef Hat",      kind = "hat", price = 8_000_000,     rarity = "Rare",      color = Color3.fromRGB(242, 244, 248) },
	{ id = "TrafficCone", name = "Traffic Cone",  kind = "hat", price = 30_000_000,    rarity = "Epic",      color = Color3.fromRGB(245, 120, 30) },
	{ id = "Horns",       name = "Impostor Horns", kind = "hat", price = 150_000_000,  rarity = "Legendary", color = Color3.fromRGB(200, 20, 30) },
	{ id = "Crown",       name = "Crown",         kind = "hat", price = 1_000_000_000, rarity = "Mythic",    color = Color3.fromRGB(250, 200, 60) },
	{ id = "Halo",        name = "Halo",          kind = "hat", price = 5_000_000_000, rarity = "Secret",    color = Color3.fromRGB(255, 230, 120) },
	-- İzler
	{ id = "Stardust",    name = "Stardust Trail", kind = "trail", price = 1_000_000,     rarity = "Uncommon", color = Color3.fromRGB(235, 240, 255) },
	{ id = "Toxic",       name = "Toxic Trail",    kind = "trail", price = 25_000_000,    rarity = "Epic",     color = Color3.fromRGB(110, 240, 140) },
	{ id = "Crimson",     name = "Impostor Trail", kind = "trail", price = 500_000_000,   rarity = "Legendary", color = Color3.fromRGB(220, 30, 40),
	  colors = { Color3.fromRGB(255, 70, 70), Color3.fromRGB(120, 0, 20) } },
	{ id = "Rainbow",     name = "Rainbow Trail",  kind = "trail", price = 10_000_000_000, rarity = "Secret",  color = Color3.fromRGB(255, 120, 200),
	  colors = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 200, 60), Color3.fromRGB(90, 220, 110), Color3.fromRGB(70, 150, 255), Color3.fromRGB(190, 90, 255) } },
} :: { CosmeticDef }

function Config.GetCosmetic(id: string): CosmeticDef?
	for _, def in Config.Cosmetics do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- ─── Gezen impostor (NPC) ───────────────────────────────────────────────────
--[[
	Arada bir bir vent'ten NPC impostor çıkıyor, rastgele bir üsse yürüyüp
	bir kaideyi "hackliyor", karakteri kapıp başka bir vent'e kaçıyor.
	YALNIZCA o üssün sahibi durdurabiliyor (hold E):
	  durdurursa — gelirine göre ödül (RogueRewardSeconds, en az RogueRewardMin)
	  kaçarsa    — karakter kaidede kalıyor ama RogueOfflineSeconds boyunca
	               para üretmiyor (soluk görünüyor, üstünde geri sayım)

	Kalabalık olmayan sunucuda da oyunda hareket olsun diye. Kilit işe
	yaramıyor (kilit oyunculara karşı); tek savunma sahibinin kendisi.
	Hızı normal yürüyüşten yavaş: sahibi yetişebilsin.
]]
-- 2026-09-28: "sürekli çalmasın" — 5-9 dk'dan 15-25 dk'ya
Config.RogueIntervalMin = 900      -- iki impostor arası (sn), rastgele
Config.RogueIntervalMax = 1500
Config.RogueFirstDelay = { 300, 600 } -- sunucu açıldıktan sonra ilki
Config.RogueApproachSpeed = 11
Config.RogueFleeSpeed = 13         -- NormalWalkSpeed'den yavaş olmalı
Config.RogueHackSeconds = 8
Config.RogueApproachTimeout = 120  -- yolda takılırsa vazgeçer
Config.RogueFleeTimeout = 60       -- kaçarken takılırsa kaçmış sayılır
-- Kaçış vent'i kaideden en az bu kadar uzak: en yakın vent 5 sn'lik
-- yoldaydı, sahibinin yetişme şansı yoktu. 150 stud ≈ 12 sn kovalamaca.
Config.RogueEscapeMinDistance = 150
Config.RogueOfflineSeconds = 300   -- kaçınca karakterin gelirsiz kaldığı süre
Config.RogueRewardSeconds = 60
Config.RogueRewardMin = 5_000
Config.RogueCatchHold = 1
Config.RogueCatchRange = 12

function Config.GetRogueReward(incomePerSecond: number): number
	return math.max(Config.RogueRewardMin, math.floor(incomePerSecond * Config.RogueRewardSeconds))
end

-- ─── Ödüller: günlük seri, oynama süresi, indeks ────────────────────────────
--[[
	═══ NEDEN ═══════════════════════════════════════════════════════════════

	İkisi de oyuncuyu GERİ getiren şeyler, oyunu değiştirenler değil:
	  - Günlük seri: her gün girip toplayan oyuncunun ödülü büyüyor, bir
	    gün kaçırınca seri başa dönüyor. "Yarın da gireyim" sebebi.
	  - Oynama süresi hediyeleri: oturumun 5., 10., 20. ... dakikasında
	    birer kutu. "Biraz daha kalayım" sebebi. Gün değişince sıfırlanıyor
	    (oturum değil) — çıkıp girerek aynı kutuyu tekrar almak olmasın.

	Nakit ödüller oyuncunun GELİRİNE göre (kaç saniyelik gelir) ve bir
	tabanı var: 1B kazanan oyuncuya $5K vermek anlamsız, yeni oyuncuya
	saatlik gelir vermek de dengeyi bozar.

	Ödül türleri:
	  cash   — `seconds` saniyelik gelir, en az `minimum`
	  potion — rastgele bir iksir (envantere), `count` kadar
	  egg    — bedava bir yumurta açılışı (`egg`), animasyonuyla
]]
export type RewardDef = {
	kind: string,
	seconds: number?,
	minimum: number?,
	count: number?,
	egg: string?,
	minutes: number?,   -- yalnızca oynama süresi hediyelerinde
}

Config.DailyRewards = {
	{ kind = "cash",   seconds = 40,  minimum = 4000 },
	{ kind = "potion", count = 1 },
	{ kind = "cash",   seconds = 150, minimum = 15000 },
	{ kind = "egg",    egg = "SupplyEgg" },
	{ kind = "cash",   seconds = 400, minimum = 60000 },
	{ kind = "potion", count = 2 },
	-- Yedinci gün büyük: seriyi tamamlamanın hedefi bu
	{ kind = "egg",    egg = "SkeldEgg" },
} :: { RewardDef }

--[[
	Kodlar (mağazanın CODES bölümü). Oyuncu kodu yazıyor, sunucu burada
	arıyor; büyük/küçük harf ve baştaki/sondaki boşluk önemsiz. Her kod
	oyuncu başına BİR kez (profile.codes). Ödüller günlük ödüllerle aynı
	türde (RewardDef): nakit gelire göre ölçekli, iksir, bedava yumurta.

	Yeni kod: listeye ekle (büyük harf). Kaldırmak için satırı sil ya da
	`expires` (os.time) ver; süresi geçen kod "expired" diyor.
]]
export type CodeDef = {
	code: string,
	rewards: { RewardDef },
	expires: number?,
}

Config.Codes = {
	{ code = "RELEASE",  rewards = { { kind = "cash", seconds = 300, minimum = 25000 }, { kind = "potion", count = 1 } } },
	{ code = "CREWMATE", rewards = { { kind = "cash", seconds = 600, minimum = 50000 } } },
	{ code = "SUS",      rewards = { { kind = "egg", egg = "SupplyEgg" } } },
} :: { CodeDef }

--[[ Kodu normalleştirip tanımını verir (yoksa nil). ]]
function Config.GetCode(text: string): CodeDef?
	local key = string.upper((string.gsub(text, "^%s*(.-)%s*$", "%1")))
	for _, def in Config.Codes do
		if def.code == key then
			return def
		end
	end
	return nil
end

Config.PlaytimeRewards = {
	{ minutes = 5,  kind = "cash",   seconds = 30,  minimum = 1500 },
	{ minutes = 10, kind = "potion", count = 1 },
	{ minutes = 20, kind = "cash",   seconds = 120, minimum = 8000 },
	{ minutes = 30, kind = "egg",    egg = "SupplyEgg" },
	{ minutes = 45, kind = "cash",   seconds = 300, minimum = 30000 },
	{ minutes = 60, kind = "egg",    egg = "SkeldEgg" },
} :: { RewardDef }

--[[
	İndeks ödülü: bir nadirliğin BÜTÜN karakterleri keşfedilince toplanan
	kalıcı gelir bonusu. Toplam +%42; tamamlanmış bir indeks bir gamepass
	kadar değerli değil ama her satır ayrı bir hedef.
	Rebirth'te sıfırlanmıyor — keşif de sıfırlanmıyor.
]]
Config.IndexRewards = {
	Common = 0.02, Uncommon = 0.03, Rare = 0.04, Epic = 0.05,
	Legendary = 0.07, Mythic = 0.09, Secret = 0.12,
} :: { [string]: number }

--[[ Nakit ödülünün tutarı: gelirin `seconds` katı, en az `minimum`. ]]
function Config.GetRewardCash(reward: RewardDef, incomePerSecond: number): number
	return math.max(reward.minimum or 0, math.floor(incomePerSecond * (reward.seconds or 0)))
end

--[[ UTC gün numarası. Günlük seri ve oynama süresi bununla sıfırlanıyor. ]]
function Config.DayIndex(now: number): number
	return math.floor(now / 86400)
end

--[[ 1234567 -> "1.23M" ]]
function Config.FormatCash(amount: number): string
	local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi" }
	local index = 1
	local value = amount

	while value >= 1000 and index < #suffixes do
		value /= 1000
		index += 1
	end

	if index == 1 then
		return string.format("%d", value)
	end
	return string.format("%.2f%s", value, suffixes[index])
end

-- ─── Uzay soygunu ───────────────────────────────────────────────────────────
--[[
	Karakterlerin kaynağı: uzaydaki canavarlar ("Steal an Egg" fikri, bizim
	temada). Kafeteryanın karşısındaki kuzey duvarın ortası açık; arkasında
	Launch Bay güvertesi, ötesinde uzay. Güverteden atlayan oyuncu uçuyor.

	  Gezegenler  — tek sırada, bir sağda bir solda; her birinin tepesinde
	                bir canavar ve önünde CrewPerPlanet kayıp mürettebat
	  Çalma       — mürettebata GrabHold sn basılı tut → sırtına alıyorsun,
	                canavar kükreyip kovalıyor. Güverteye (ya da gemiye)
	                varınca karakter üssün boş kaidesine gidiyor
	  Yakalanma   — canavar oyuncuyu eliyle kavrıyor ve gemiye fırlatıyor;
	                karakter canavarın önüne geri dönüyor
	  Uzay hızı   — uçuş hızı (stud/sn), profilde kalıcı. Kapsülde durarak
	                artıyor (Config.Capsule). Her canavar need hızında
	                kovalıyor: hızın ondan düşükse kaçamazsın

	Kademe = nadirlik havuzu. İlk canavar taban hıza göre ayarlı: oyuna yeni
	giren herkes ilk karakterini oradan alıyor.

	Geometri SpaceField'da (sunucu + istemci aynı hesap). Konumlar dünya
	koordinatı: istasyon x -78..438, z -68..184; kuzey duvar z = -68.
]]
export type SpaceMonsterDef = {
	id: string,
	name: string,           -- oyuncunun gördüğü ad
	planet: string,         -- gezegenin adı
	need: number,           -- önerilen uzay hızı = canavarın tavan kovalama hızı
	position: Vector3,      -- gezegenin tepesindeki düzlüğün (plato) merkezi, üst yüz
	radius: number,         -- gezegen yarıçapı
	scale: number,          -- canavar modelinin ölçeği (MonsterModel)
	wake: number,           -- kükreme süresi: bu kadar sn sonra kovalamaya başlıyor
	lunge: number,          -- yakına gelince ani atak hız çarpanı (1 = atak yok)
	odds: { [string]: number },   -- nadirlik -> ağırlık
	planetColor: Color3,
	planetColor2: Color3,
	glow: Color3,
}

Config.SpaceMonsters = {
	{
		id = "Glorp", name = "Glorp", planet = "Gloopus", need = 16,
		position = Vector3.new(40, 2, -330), radius = 44, scale = 1, wake = 1.0, lunge = 1,
		odds = { Common = 88, Uncommon = 12 },
		planetColor = Color3.fromRGB(96, 178, 88), planetColor2 = Color3.fromRGB(62, 128, 70), glow = Color3.fromRGB(150, 255, 90),
	},
	{
		id = "Chomper", name = "Chomper", planet = "Candorra", need = 28,
		position = Vector3.new(320, 16, -640), radius = 48, scale = 1.15, wake = 0.9, lunge = 1,
		odds = { Common = 30, Uncommon = 55, Rare = 15 },
		planetColor = Color3.fromRGB(214, 96, 170), planetColor2 = Color3.fromRGB(150, 58, 130), glow = Color3.fromRGB(255, 120, 200),
	},
	{
		id = "Kraken", name = "Nebula Kraken", planet = "Abyssia", need = 44,
		position = Vector3.new(20, -6, -1000), radius = 52, scale = 1.3, wake = 0.7, lunge = 1.15,
		odds = { Uncommon = 30, Rare = 50, Epic = 20 },
		planetColor = Color3.fromRGB(46, 96, 184), planetColor2 = Color3.fromRGB(30, 60, 132), glow = Color3.fromRGB(80, 230, 255),
	},
	{
		id = "SandMaw", name = "Sand Maw", planet = "Duneveil", need = 64,
		position = Vector3.new(340, 22, -1420), radius = 56, scale = 1.45, wake = 0.6, lunge = 1.2,
		odds = { Rare = 30, Epic = 50, Legendary = 18, Mythic = 2 },
		planetColor = Color3.fromRGB(214, 146, 84), planetColor2 = Color3.fromRGB(170, 104, 58), glow = Color3.fromRGB(90, 200, 255),
	},
	{
		id = "RiftStalker", name = "Rift Stalker", planet = "Cinderhold", need = 90,
		position = Vector3.new(0, 4, -1900), radius = 58, scale = 1.6, wake = 0.5, lunge = 1.25,
		odds = { Epic = 30, Legendary = 50, Mythic = 18, Secret = 2 },
		planetColor = Color3.fromRGB(64, 58, 66), planetColor2 = Color3.fromRGB(40, 36, 44), glow = Color3.fromRGB(255, 90, 40),
	},
	{
		id = "VoidLeviathan", name = "Void Leviathan", planet = "Umbra Prime", need = 120,
		position = Vector3.new(360, 30, -2450), radius = 64, scale = 1.8, wake = 0.4, lunge = 1.3,
		odds = { Legendary = 45, Mythic = 43, Secret = 12 },
		planetColor = Color3.fromRGB(38, 26, 64), planetColor2 = Color3.fromRGB(22, 14, 40), glow = Color3.fromRGB(200, 80, 255),
	},
} :: { SpaceMonsterDef }

Config.Space = {
	BaseSpeed = 16,             -- yeni oyuncunun uzay hızı (ilk canavarın need'i)
	MaxSpeed = 1000,            -- kayıt kırpması

	-- Launch Bay: kuzey duvarın dışında, orta koridorun ucunda
	-- Orta koridorun ucu: üs ızgarasının ortası (PlotSpacing'den)
	GateX = (Config.PlotColumns - 1) * Config.PlotSpacing / 2,
	GateWidth = 36,
	GateHeight = 24,
	WallZ = -68,                -- kuzey duvarın merkez çizgisi
	WallThickness = 2.4,
	DeckHalfWidth = 64,
	DeckDepth = 62,             -- duvarın dış yüzünden dışarı
	DeckTop = 0.27,             -- istasyonun karo üstüyle aynı
	SafeHeight = 44,

	-- Uçulabilen alan (dışına çıkan içeri itiliyor)
	BoundsMin = Vector3.new(-220, -200, -2650),
	BoundsMax = Vector3.new(580, 280, -68),

	-- Fırlatılan oyuncunun indiği yer: gemide, kapının içinde
	Landing = Vector3.new((Config.PlotColumns - 1) * Config.PlotSpacing / 2, 3.5, -40),

	CrewPerPlanet = 5,
	CrewRing = 13,              -- mürettebat yayının yarıçapı
	--[[
		Mürettebat rotasyonu (2026-09-28): bütün gezegenlerdeki mürettebat
		HEP BİRLİKTE her CrewRotate sn'de değişiyor (sunucuda, herkes aynısını
		görüyor; üstünde geri sayım). Çalınan yerin yenisi CrewRespawn sn sonra
		geliyor, sonra ortak rotasyona katılıyor.
	]]
	CrewRotate = 300,
	CrewRespawn = 60,
	GrabHold = 1.0,
	GrabDistance = 12,

	--[[
		Canavar. Kükreme süresi (wake) ve ani atak (lunge) canavar başına
		(Config.SpaceMonsters): ilk ikisi yeni oyuncuya affedici, sonrakiler
		daha çabuk uyanıyor ve yakına gelince LungeTime sn boyunca need ×
		lunge hızla atılıyor. need hızında kaçan biri atakta yakalanabilir;
		ileri gezegenlerde biraz fazla hız ya da iyi manevra gerekiyor.
	]]
	WakeDelay = 0.9,            -- (varsayılan; canavarın wake'i öncelikli)
	LungeRange = 28,
	LungeTime = 0.8,
	LungeCooldown = 4,          -- (3.5'ten; biraz daha kolay)
	ChaseStartMul = 0.8,        -- kovalamaya need × bu hızla başlıyor...
	ChaseRamp = 2.5,            -- ...bu kadar sn'de need'e çıkıyor
	CatchRadius = 6.5,          -- + ölçek × 2 (7'den; biraz daha kolay)
	ReturnSpeedMul = 1.4,
	GrabTime = 1.3,             -- elinde tutup sallıyor
	ThrowTime = 1.9,            -- gemiye uçuş süresi
	ThrowImmunity = 2.5,        -- indikten sonra tekrar çalamama süresi

	-- Hile payı: teslimde "bu yolu bu hızla en az şu kadar sürede gelmiş olmalı"
	DeliverSpeedTolerance = 1.7,

	-- Uçuş (istemci)
	FlyAccel = 6,               -- hedef hıza yaklaşma katsayısı (sn⁻¹)
}

--[[
	Yol üstü ödüller ve engeller (SpaceBonusService, SpaceFX). 2026-09-28:
	"gezegenlere giden yol çok boş". Ödüller gelire göre (yeni oyuncu için
	taban), yani her aşamada anlamlı ama kapsülün ve soygunun yerini tutmuyor.
]]
Config.SpaceBonus = {
	RingSpacing = 70,           -- iki hız halkası arası (stud)
	RingRadius = 9,
	RingBoostMul = 1.45,        -- halkadan geçince uçuş hızı çarpanı...
	RingBoostTime = 1.8,        -- ...bu kadar sn
	-- 2026-09-28: yıldız tozu ve hız halkaları KALKTI (para basıyordu, halkalar
	-- kalabalık yapıyordu; hızı artık jetpack veriyor). Sandık azaldı ve seyrek.
	StardustClusterSpacing = 95,
	StardustPerCluster = 6,
	StardustRadius = 6,         -- toplama mesafesi
	StardustRespawn = 30,
	StardustIncomeSeconds = 1.5, -- ödül = saniyelik gelir × bu (en az StardustMin)
	StardustMin = 40,
	CrateRadius = 8,
	CrateRespawn = 300,
	CrateIncomeSeconds = 6,
	CrateMin = 400,
	CratePotionChance = 0.06,
	-- Golden Comet olayı: uzaydan geçen altın kuyruklu yıldız, ilk dokunan kazanır
	CometSpeed = 38,
	CometRadius = 10,
	CometIncomeSeconds = 60,
	CometMin = 15000,
}

-- ─── Jetpack'ler ────────────────────────────────────────────────────────────
--[[
	Launch Bay'deki JETPACK standından alınıyor (JetpackService). Kuşanılan
	jetpack GİDERKEN uçuş hızını çarpıyor (boost); bir mürettebat kapınca
	kendi hızınla dönüyorsun — canavarla yarış yine kapsül hızına bağlı.
	Uzak gezegenlere gitmek jetpack'le kısalıyor ("çok uzun sürüyor").

	  price  — oyun içi para (0 = herkeste var)
	  pass   — Robux gamepass kimliği (varsa price yerine; 0 iken "SOON")
	Görünüş (SpaceFX): tank sayısı, renkler, kanat/halka, alev rengi.
]]
export type JetpackDef = {
	id: string,
	name: string,
	boost: number,
	price: number,
	pass: number?,
	robux: number?,        -- mağazada gösterilecek fiyat (pass fiyatı Roblox'ta ayarlanıyor)
	tanks: number,
	tank: Color3,
	trim: Color3,
	flame: Color3,
	flame2: Color3,
	wings: boolean?,
	ring: boolean?,
}

Config.Jetpacks = {
	{ id = "Starter", name = "Starter Pack", boost = 1.0,  price = 0,
	  tanks = 1, tank = Color3.fromRGB(170, 178, 192), trim = Color3.fromRGB(90, 98, 112), flame = Color3.fromRGB(255, 180, 80), flame2 = Color3.fromRGB(255, 90, 40) },
	{ id = "Scout",   name = "Scout Jet",    boost = 1.25, price = 15000,
	  tanks = 2, tank = Color3.fromRGB(226, 70, 70), trim = Color3.fromRGB(220, 224, 232), flame = Color3.fromRGB(255, 200, 90), flame2 = Color3.fromRGB(255, 80, 40) },
	{ id = "Comet",   name = "Comet Jet",    boost = 1.5,  price = 750000,
	  tanks = 2, tank = Color3.fromRGB(60, 140, 240), trim = Color3.fromRGB(230, 236, 246), flame = Color3.fromRGB(140, 220, 255), flame2 = Color3.fromRGB(60, 120, 255), wings = true },
	{ id = "Plasma",  name = "Plasma Jet",   boost = 1.75, price = 0, pass = 1999683184, robux = 99,
	  tanks = 2, tank = Color3.fromRGB(70, 230, 120), trim = Color3.fromRGB(30, 40, 50), flame = Color3.fromRGB(160, 255, 150), flame2 = Color3.fromRGB(40, 220, 90), wings = true },
	{ id = "Nova",    name = "Nova Jet",     boost = 1.85, price = 40000000,
	  tanks = 2, tank = Color3.fromRGB(255, 190, 50), trim = Color3.fromRGB(250, 246, 230), flame = Color3.fromRGB(255, 240, 150), flame2 = Color3.fromRGB(255, 150, 40), wings = true },
	{ id = "Pulsar",  name = "Pulsar Jet",   boost = 2.2,  price = 2500000000,
	  tanks = 2, tank = Color3.fromRGB(180, 90, 255), trim = Color3.fromRGB(40, 30, 60), flame = Color3.fromRGB(230, 170, 255), flame2 = Color3.fromRGB(160, 70, 255), wings = true, ring = true },
	{ id = "Quasar",  name = "Quasar Jet",   boost = 2.55, price = 150000000000,
	  tanks = 2, tank = Color3.fromRGB(30, 30, 44), trim = Color3.fromRGB(255, 70, 110), flame = Color3.fromRGB(255, 150, 190), flame2 = Color3.fromRGB(255, 50, 110), wings = true, ring = true },
	{ id = "Galaxy",  name = "Galaxy Jet",   boost = 2.9,  price = 0, pass = 1999461068, robux = 499,
	  tanks = 2, tank = Color3.fromRGB(50, 30, 110), trim = Color3.fromRGB(120, 230, 255), flame = Color3.fromRGB(255, 255, 255), flame2 = Color3.fromRGB(120, 200, 255), wings = true, ring = true },
} :: { JetpackDef }

function Config.GetJetpack(id: string?): JetpackDef?
	if not id then
		return nil
	end
	for _, def in Config.Jetpacks do
		if def.id == id then
			return def
		end
	end
	return nil
end

--[[ Giderken uçuş çarpanı: taşırken 1 (kendi hızın), değilse jetpack'in boost'u. ]]
function Config.GetJetpackBoost(id: string?, carrying: boolean): number
	if carrying then
		return 1
	end
	local def = Config.GetJetpack(id)
	return if def then def.boost else 1
end

function Config.GetSpaceMonster(id: string): SpaceMonsterDef?
	for _, def in Config.SpaceMonsters do
		if def.id == id then
			return def
		end
	end
	return nil
end

local RARITY_LADDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

--[[
	Canavarın havuzundan karakter çeker: önce nadirlik (odds ağırlığıyla),
	sonra o nadirlikteki karakterler kendi weight'leriyle.
]]
function Config.RollSpaceUnit(rng: Random, def: SpaceMonsterDef): UnitDef
	local total = 0
	for _, w in def.odds do
		total += w
	end
	local roll = rng:NextNumber(0, total)
	local rarity = "Common"
	for _, name in RARITY_LADDER do
		local w = def.odds[name]
		if w then
			rarity = name
			roll -= w
			if roll <= 0 then
				break
			end
		end
	end
	local pool = 0
	for _, unit in Config.Units do
		if unit.rarity == rarity then
			pool += unit.weight
		end
	end
	local pick = rng:NextNumber(0, pool)
	for _, unit in Config.Units do
		if unit.rarity == rarity then
			pick -= unit.weight
			if pick <= 0 then
				return unit
			end
		end
	end
	return Config.Units[1]
end

--[[ Oyuncunun hızının yettiği en yüksek canavar (hiçbiri değilse ilki). ]]
function Config.BestSpaceMonster(speed: number): SpaceMonsterDef
	local best = Config.SpaceMonsters[1]
	for _, def in Config.SpaceMonsters do
		if speed >= def.need then
			best = def
		end
	end
	return best
end

-- ─── Uzay kapsülü ───────────────────────────────────────────────────────────
--[[
	Her üssün arkasında (konveyörün eski yerinde) bir kapsül. İçinde duran
	sahibinin uzay hızı artıyor ("uzay yürüyüşü simülasyonu"). Kapsül
	seviyesi = SpaceCapsule yükseltmesi (Config.Upgrades).

	    kazanç/sn = Rate × Growth^seviye × (Ref / (hız + Ref − BaseSpeed))^Pow

	İkinci çarpan azalan getiri: hız büyüdükçe aynı kapsül yavaşlıyor, üst
	canavarlar yükseltme ister. Rebirth kapsülü sıfırlıyor (bütün
	yükseltmeler gibi), kazanılmış hızı değil.
]]
Config.Capsule = {
	--[[
		2026-09-28 dengesi: "oyun çok hızlı ya da çok yavaş bitmesin". Mini
		oyun zorlaştı (Training Console kolaylaştırıyor), eğri biraz hızlandı.
		Kaba süreler (kapsül seviyesi 0/3/6/9/12 hıza göre, ortalama mini oyun
		×1.3 — oynamayan için parantezde):
		  28 ~2.5 dk, 44 ~10 dk, 64 ~32 dk, 90 ~1.4 sa, 120 ~3.2 sa (~4.1 sa)
		Eskiden 120'ye ~4.6-6.5 sa. sv9+ için 2. kat (rebirth + kat parası)
		gerekiyor; gerçek süre soygun ve para beklemesiyle biraz daha uzun.
	]]
	--[[ 2026-09-28 (Yusuf): "kapsül çok çok hızlı" — yeniden yavaşladı.
	     Mini oyunsuz: 28 ~4 dk, 44 ~14 dk, 64 ~42 dk, 90 ~2 sa, 120 ~4 sa
	     (kapsül sv 0/3/6/9/12; sv9+ 2. kat ister). Mini oyunla ~%30 kısa. ]]
	Rate = 0.14,
	Growth = 1.14,
	Ref = 20,
	Pow = 3.4,
	Tick = 0.5,                 -- sunucunun ölçtüğü aralık
	--[[
		Mini oyun (Stardew balık tutma gibi): roketi hareketli yeşil alanda
		tut, çubuk dolunca CatchBonusSeconds saniyelik kazanç bir anda gelir.
		Sunucu sınırı: iki bonus arası en az CatchCooldown sn, kapsüle
		girdikten en az CatchWarmup sn sonra. Hile en fazla ~2.2x verir;
		iyi oynayan zaten oraya yaklaşıyor.
	]]
	--[[
		2026-09-28: "mini oyun geliştirilsin, çok hızlı kazanılıyorsa ayar
		çek". Tur ~12 sn (Training Console ~9.5), eskiden ~8.5; sunucu iki
		bonus arasını CatchCooldown ile sınırlıyor. Çarpmadan biten tur
		("PERFECT") PerfectCatchMul kat. İyi oynayan pasif kazancın ~1.6-1.8
		katını alıyor (eskiden ~1.9-2.2).
	]]
	CatchBonusSeconds = 7,
	CatchCooldown = 9,
	CatchWarmup = 3,
	PerfectCatchMul = 1.3,
}

--[[
	Uçuş hızı = kapsülde kazanılan uzay hızı + petlerin hız bonusu.
	2026-09-28: petlerin hız bonusu eskiden gemide TAŞIMA hızına ekleniyordu;
	taşıma kalkınca uzaydaki uçuşa geçti. Canavara erişim eşiği (need) yine
	kapsül hızına bakıyor; pet yalnızca kaçarken fark yaratıyor.
]]
Config.PetFlightMul = 1

function Config.GetFlightSpeed(spaceSpeed: number, petBonus: number?): number
	return spaceSpeed + math.max(0, petBonus or 0) * Config.PetFlightMul
end

function Config.GetCapsuleGain(level: number, speed: number): number
	local c = Config.Capsule
	local falloff = (c.Ref / (math.max(speed, Config.Space.BaseSpeed) + c.Ref - Config.Space.BaseSpeed)) ^ c.Pow
	return c.Rate * c.Growth ^ upgradeStep(level) * falloff
end

return Config
