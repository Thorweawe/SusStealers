--!strict
-- Tüm oyun dengesi burada. Yeni karakter / mutasyon eklemek için sadece bu dosya.

local Config = {}

-- ─── Dünya ──────────────────────────────────────────────────────────────────
Config.PlotCount = 8
Config.PodiumsPerPlot = 8
Config.PlotSize = Vector3.new(60, 2, 44)
Config.PlotSpacing = 76
Config.PodiumSpacing = 6.5

-- ─── Ekonomi ────────────────────────────────────────────────────────────────
Config.StartingCash = 250
Config.IncomeInterval = 1

-- ─── Konveyör ───────────────────────────────────────────────────────────────
Config.ConveyorInterval = 10   -- kaç saniyede bir yeni karakter gelir
Config.ConveyorLifetime = 22   -- alınmazsa kaç saniye sonra kaybolur
Config.ConveyorSpeed = 6

-- ─── Çalma ──────────────────────────────────────────────────────────────────
Config.StealHoldTime = 4.0     -- prompt kaç saniye basılı tutulur
Config.StealCooldown = 18      -- bir çalmadan sonra oyuncunun bekleme süresi
Config.CarryWalkSpeed = 11     -- karakter taşırken hız
Config.NormalWalkSpeed = 16
Config.SafeSeconds = 8         -- yeni yerleştirilen karakter kaç sn çalınamaz

-- Çalınan karakter, çalındığı yerden üsse taşınırken en az bu oranda
-- yürüme süresi geçmiş olmalı. Karakterin konumu istemcinin elinde
-- olduğu için ışınlanan biri yürüyüşü tamamen atlayabiliyordu; çalmanın
-- bütün riski o yürüyüşte. 1.0 = tam yürüme süresi (çok sıkı, eğim ve
-- kestirme yüzünden meşru oyuncu takılır), 0 = kontrol kapalı.
Config.CarryTravelTolerance = 0.7

-- ─── Kilit (savunma) ────────────────────────────────────────────────────────
Config.LockDuration = 25
Config.LockCooldown = 80

-- ─── Rebirth ve katlar ──────────────────────────────────────────────────────
-- Tavana ulaşan oyuncunun yapacak bir şeyi kalmıyordu. Rebirth her şeyi
-- sıfırlıyor ama karşılığında kalıcı gelir çarpanı ve yeni bir kat veriyor.
Config.MaxFloors = 3           -- 1. kat açık gelir, her rebirth bir kat açar
Config.FloorHeight = 18        -- katlar arası yükseklik (stud)
-- 8 kaide Amogus Prime ile 1. kat tavanı ~3.36M/sn. Rebirth'ün o tavanda
-- birkaç dakikalık oyun kadar tutması gerekiyor; 25M yedi saniyelik
-- kazançtı, hiçbir şey ifade etmiyordu.
Config.RebirthBaseCost = 1000000000
Config.RebirthCostGrowth = 8   -- her seviyede maliyet bu kat artar
Config.RebirthIncomeBonus = 0.5 -- seviye başına kalıcı gelir artışı (+%50)

-- ─── Çevrimdışı gelir ───────────────────────────────────────────────────────
-- Oyuncu çıkınca kazanç tamamen duruyordu, geri gelmek için sebep azdı.
-- Tam oran vermiyoruz ki oynamak hâlâ daha kârlı olsun.
Config.OfflineIncomeRate = 0.25
Config.OfflineIncomeCapHours = 4

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
-- weight: konveyörde çıkma ağırlığı (büyük = sık)
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

Config.Units = {
	-- Common
	{ id = "RedCrew",     name = "Red Crewmate",       rarity = "Common",    price =    100, income =     3, weight = 1000, color = Color3.fromRGB(197,  17,  17) },
	{ id = "BlueCrew",    name = "Blue Crewmate",      rarity = "Common",    price =    180, income =     6, weight =  900, color = Color3.fromRGB( 19,  46, 210) },
	{ id = "YellowCrew",  name = "Yellow Crewmate",    rarity = "Common",    price =    320, income =    11, weight =  800, color = Color3.fromRGB(241, 224,  90) },

	-- Uncommon
	{ id = "Engineer",    name = "Engineer",           rarity = "Uncommon",  price =    750, income =    28, weight =  500, color = Color3.fromRGB( 56, 254, 220) },
	{ id = "Scientist",   name = "Scientist",          rarity = "Uncommon",  price =   1600, income =    62, weight =  420, color = Color3.fromRGB( 80, 240, 100) },
	{ id = "Guardian",    name = "Guardian Angel",     rarity = "Uncommon",  price =   3400, income =   135, weight =  340, color = Color3.fromRGB(235, 235, 255) },

	-- Rare
	{ id = "Shapeshift",  name = "Shapeshifter",       rarity = "Rare",      price =   7500, income =   310, weight =  200, color = Color3.fromRGB(107,  47, 187) },
	{ id = "VentCrawler", name = "Vent Crawler",       rarity = "Rare",      price =  16000, income =   680, weight =  160, color = Color3.fromRGB( 62,  71,  78) },
	{ id = "MedbayScan",  name = "Medbay Scanner",     rarity = "Rare",      price =  34000, income =  1450, weight =  120, color = Color3.fromRGB( 90, 200, 255) },

	-- Epic
	{ id = "Impostor",    name = "Impostor",           rarity = "Epic",      price =  72000, income =  3100, weight =   70, color = Color3.fromRGB(140,  10,  10) },
	{ id = "Reactor",     name = "Reactor Meltdown",   rarity = "Epic",      price = 155000, income =  6800, weight =   50, color = Color3.fromRGB(255, 120,  20) },
	{ id = "Emergency",   name = "Emergency Meeting",  rarity = "Epic",      price = 330000, income = 14500, weight =   36, color = Color3.fromRGB(255,  60,  60) },

	-- Legendary
	{ id = "Ejected",     name = "Ejected Into Space", rarity = "Legendary", price = 700000, income = 31000, weight =   18, color = Color3.fromRGB( 25,  25,  60) },
	{ id = "TheSkeld",    name = "The Skeld",          rarity = "Legendary", price =1500000, income = 67000, weight =   12, color = Color3.fromRGB(120, 130, 145) },

	-- Mythic
	{ id = "DoubleImp",   name = "Double Impostor",    rarity = "Mythic",    price =3200000, income =145000, weight =    5, color = Color3.fromRGB(190,   0,  55) },

	-- Secret
	{ id = "AmogusPrime", name = "Amogus Prime",       rarity = "Secret",    price =9000000, income =420000, weight =    1, color = Color3.fromRGB( 12,  12,  18) },
} :: { UnitDef }

-- ─── Mutasyonlar ────────────────────────────────────────────────────────────
-- Konveyörde çıkan her karaktere sırayla bakılır, ilk tutan uygulanır.
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

-- Karakter satılınca alış fiyatının bu kadarı geri gelir. 1.0'a yaklaştıkça
-- oyuncu bedava deneme hakkı kazanır: alır, beğenmezse tam iade alır.
-- Düşürdükçe kaide dolduğunda karar vermek zorlaşır.
Config.SellRefundFactor = 0.5

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
	Karakterin satış fiyatı. Konveyör bunu kullanır; çalınan bir karakter
	sahibine iade edilemediğinde para iadesi de buradan hesaplanır.
	Tek kaynak olsun diye iki yerde ayrı ayrı hesaplanmıyor.
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

--[[ Karakteri satınca eline geçen para. ]]
function Config.GetSellPrice(unitId: string, mutationId: string?): number
	return math.floor(Config.GetPrice(unitId, mutationId) * Config.SellRefundFactor)
end

--[[
	Karakteri çalmak için promptun kaç saniye basılı tutulacağı.
	Değerle birlikte artar: ucuz karakter çabuk gider, pahalı karakter
	hırsızı uzun süre açıkta bırakır. Ölçek logaritmik, çünkü fiyatlar
	100 ile 9.000.000 arasında; doğrusal olsaydı ilk beş karakter hariç
	hepsi tavan değere yapışırdı.

	100 -> 2 sn, 9.000.000 -> 8 sn.
]]
function Config.GetStealHoldTime(unitId: string, mutationId: string?): number
	local price = Config.GetPrice(unitId, mutationId)
	if price <= 0 then
		return Config.StealHoldTime
	end

	local t = math.log(price / 100) / math.log(90000)
	return math.clamp(2 + t * 6, 2, 8)
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
function Config.GetUnlockedFloors(rebirths: number): number
	return math.clamp(1 + rebirths, 1, Config.MaxFloors)
end

--[[ Açık katlarla birlikte toplam kaç kaide kullanılabilir. ]]
function Config.GetUnlockedPodiumCount(rebirths: number): number
	return Config.GetUnlockedFloors(rebirths) * Config.PodiumsPerPlot
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

--[[ Konveyör için ağırlıklı rastgele karakter seçer. ]]
function Config.RollUnit(rng: Random): UnitDef
	local total = 0
	for _, unit in Config.Units do
		total += unit.weight
	end

	local roll = rng:NextNumber(0, total)
	for _, unit in Config.Units do
		roll -= unit.weight
		if roll <= 0 then
			return unit
		end
	end

	return Config.Units[1]
end

--[[ Mutasyon çeker, çıkmazsa nil döner. ]]
function Config.RollMutation(rng: Random): MutationDef?
	for _, mutation in Config.Mutations do
		if rng:NextNumber() < mutation.chance then
			return mutation
		end
	end
	return nil
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

return Config
