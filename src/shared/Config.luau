--!strict
-- Tüm oyun dengesi burada. Yeni karakter / mutasyon eklemek için sadece bu dosya.

local Config = {}

-- ─── Dünya ──────────────────────────────────────────────────────────────────
Config.PlotCount = 6
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
Config.StealHoldTime = 3.0     -- prompt kaç saniye basılı tutulur
Config.StealCooldown = 18      -- bir çalmadan sonra oyuncunun bekleme süresi
Config.CarryWalkSpeed = 11     -- karakter taşırken hız
Config.NormalWalkSpeed = 16
Config.SafeSeconds = 8         -- yeni yerleştirilen karakter kaç sn çalınamaz

-- ─── Kilit (savunma) ────────────────────────────────────────────────────────
Config.LockDuration = 25
Config.LockCooldown = 80

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
	{ id = "RedCrew",     name = "Kırmızı Mürettebat", rarity = "Common",    price =    100, income =     3, weight = 1000, color = Color3.fromRGB(197,  17,  17) },
	{ id = "BlueCrew",    name = "Mavi Mürettebat",    rarity = "Common",    price =    180, income =     6, weight =  900, color = Color3.fromRGB( 19,  46, 210) },
	{ id = "YellowCrew",  name = "Sarı Mürettebat",    rarity = "Common",    price =    320, income =    11, weight =  800, color = Color3.fromRGB(241, 224,  90) },

	-- Uncommon
	{ id = "Engineer",    name = "Tamirci",            rarity = "Uncommon",  price =    750, income =    28, weight =  500, color = Color3.fromRGB( 56, 254, 220) },
	{ id = "Scientist",   name = "Bilim İnsanı",       rarity = "Uncommon",  price =   1600, income =    62, weight =  420, color = Color3.fromRGB( 80, 240, 100) },
	{ id = "Guardian",    name = "Koruyucu Melek",     rarity = "Uncommon",  price =   3400, income =   135, weight =  340, color = Color3.fromRGB(235, 235, 255) },

	-- Rare
	{ id = "Shapeshift",  name = "Şekil Değiştiren",   rarity = "Rare",      price =   7500, income =   310, weight =  200, color = Color3.fromRGB(107,  47, 187) },
	{ id = "VentCrawler", name = "Kanal Sürüngeni",    rarity = "Rare",      price =  16000, income =   680, weight =  160, color = Color3.fromRGB( 62,  71,  78) },
	{ id = "MedbayScan",  name = "Revir Tarayıcı",     rarity = "Rare",      price =  34000, income =  1450, weight =  120, color = Color3.fromRGB( 90, 200, 255) },

	-- Epic
	{ id = "Impostor",    name = "Hain",               rarity = "Epic",      price =  72000, income =  3100, weight =   70, color = Color3.fromRGB(140,  10,  10) },
	{ id = "Reactor",     name = "Reaktör Erimesi",    rarity = "Epic",      price = 155000, income =  6800, weight =   50, color = Color3.fromRGB(255, 120,  20) },
	{ id = "Emergency",   name = "Acil Toplantı",      rarity = "Epic",      price = 330000, income = 14500, weight =   36, color = Color3.fromRGB(255,  60,  60) },

	-- Legendary
	{ id = "Ejected",     name = "Uzaya Fırlatıldı",   rarity = "Legendary", price = 700000, income = 31000, weight =   18, color = Color3.fromRGB( 25,  25,  60) },
	{ id = "TheSkeld",    name = "The Skeld",          rarity = "Legendary", price =1500000, income = 67000, weight =   12, color = Color3.fromRGB(120, 130, 145) },

	-- Mythic
	{ id = "DoubleImp",   name = "Çifte Hain",         rarity = "Mythic",    price =3200000, income =145000, weight =    5, color = Color3.fromRGB(190,   0,  55) },

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

Config.Mutations = {
	{ id = "Impostor", name = "HAIN",    chance = 0.004, incomeMul = 30, tint = Color3.fromRGB(190,  15,  40) },
	{ id = "Golden",   name = "Altın",   chance = 0.012, incomeMul = 15, tint = Color3.fromRGB(255, 200,  60) },
	{ id = "Ejected",  name = "Fırlatıldı", chance = 0.030, incomeMul = 8, tint = Color3.fromRGB( 40,  40,  90) },
	{ id = "Vented",   name = "Kanalcı", chance = 0.070, incomeMul = 4,  tint = Color3.fromRGB( 90, 110, 120) },
	{ id = "Sus",      name = "Şüpheli", chance = 0.150, incomeMul = 2,  tint = Color3.fromRGB(255, 120, 180) },
} :: { MutationDef }

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
