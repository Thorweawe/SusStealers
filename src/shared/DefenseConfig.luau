--!strict
--[[
	GEZEGEN SAVUNMASI (2026-10-01, Batur): pilot panelinden bir gezegene
	iniliyor, kaidedeki crewmate'ler gemi önündeki alana konuyor, gelen
	dalgalara karşı savunuyor. Plan: PLAN-GEZEGEN-SAVUNMA.md.

	Bütün sayılar burada; simülasyon DefenseSim'de, sunucu DefenseService'te.
	Koordinatlar gezegen dünyasının YEREL düzleminde: Vector2(x, z).
	Gemi rampası (Field.gate) z ≈ 26'da, düşman kapısı (Field.entrance)
	alanın öbür ucunda. Dünya konumu PlanetWorldService'te.

	Denge ilkesi (Batur): "daha çok kazandıran daha güçlü ama oyunu bitiren
	için bölümler aşırı basit olmasın, ileri seviyeler hafif farklı olsun".
	Crewmate'in gücü gelirinin LOGARİTMASIYLA artıyor (GetPower); asıl güç
	altınla alınan rol yükseltmelerinden ve yerleşimden.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local DefenseConfig = {}

--[[
	ANAHTAR (2026-10-01, Batur: "bu modu şimdilik devre dışı bırakıcaz,
	buton gerçek modda çalışmasın, tamam dediğimde açarsın").
	false iken canlı sunucuda PILOT istemi yok, remote her şeyi reddediyor,
	istemci hiçbir şey kurmuyor. Studio'da test için her zaman açık.
]]
DefenseConfig.Live = false

function DefenseConfig.IsEnabled(): boolean
	return DefenseConfig.Live or RunService:IsStudio()
end

-- ─── Genel ──────────────────────────────────────────────────────────────────

DefenseConfig.TickRate = 10              -- simülasyon adımı (Hz)
DefenseConfig.WavesPerSector = 5         -- bir bölüm (yıldız + altın + kontrol noktası)
DefenseConfig.ReviveMinutes = 15         -- hastane: crewmate'in bu kadar dakikalık kazancı
DefenseConfig.MaxEnemies = 70            -- aynı anda sahada (güvenlik sınırı)
DefenseConfig.UnitSpacing = 4.5          -- iki crewmate arası en az mesafe (modeller büyüdü)
DefenseConfig.PathClearance = 0          -- yolun üstüne de konabilir (bloklamak için)

--[[
	Savaş alanı (yerel düzlem). Gemi z < 0 tarafında, burnu +z'ye bakıyor;
	rampa ucu `gate`. Düşmanlar `entrance`'tan çıkıp gate'e yürüyor.
	Crewmate'ler dikdörtgenin içine konabiliyor.
]]
DefenseConfig.Field = {
	gate = Vector2.new(0, 26),
	entrance = Vector2.new(0, 214),
	halfWidth = 64,
	zMin = 34,
	zMax = 200,
}

--[[
	Gezegen dünyaları haritanın çok uzağında (uzay z < -68, istasyon ve
	lobi x < 3400): her gezegenin kendi yüzeyi, ilk inişte kuruluyor
	(PlanetWorldService). Yerel düzlemde gemi z ≈ -18'de, burnu +z'ye bakıyor.
]]
DefenseConfig.WorldBase = Vector3.new(9000, 20, 2400)
DefenseConfig.WorldGap = 1500

function DefenseConfig.WorldOrigin(planet: number): Vector3
	return DefenseConfig.WorldBase + Vector3.new((planet - 1) * DefenseConfig.WorldGap, 0, 0)
end

function DefenseConfig.ToWorld(planet: number, p: Vector2, y: number?): Vector3
	return DefenseConfig.WorldOrigin(planet) + Vector3.new(p.X, y or 0, p.Y)
end

--[[ Dünya noktası hangi gezegen dünyasında (yoksa nil). ]]
function DefenseConfig.WorldAt(p: Vector3): number?
	local rel = p - DefenseConfig.WorldBase
	if math.abs(rel.Z) > 600 or rel.Y < -200 or rel.Y > 600 then
		return nil
	end
	local index = math.floor(rel.X / DefenseConfig.WorldGap + 0.5) + 1
	if index < 1 or index > 64 then
		return nil
	end
	local local_ = rel.X - (index - 1) * DefenseConfig.WorldGap
	return if math.abs(local_) <= 600 then index else nil
end

-- Yüzeydeki yerler (yerel düzlem)
--[[
	2026-10-01 (Batur: "şimdilik bir tane harita, pilota E basınca direkt
	buraya gelsin, ilk gezegene yoğunlaşalım"): tek gezegen. Diğer
	gezegenlerin kodu duruyor ama pilot doğrudan buraya indiriyor.
]]
DefenseConfig.OnlyPlanet = 1

--[[
	ARENALAR (Batur: "8 kişi için farklı yer olsa, farklı yerlere
	ışınlansalar"): gezegenin her oyuncu için ayrı bir kopyası. Pilot boştaki
	ilk arenaya indiriyor; herkes kendi gemisi, dükkânları ve alanıyla yalnız.
	Dünya konumu arenaya göre (WorldOrigin(arena)); renk ve zorluk gezegenden.
	Kopyalar ilk kullanımda kuruluyor (PlanetWorldService).
]]
DefenseConfig.MaxArenas = 10

--[[
	IŞIN KILICI (Batur: "ışın kılıcını gear olarak alıp kendi crewmate'lerimize
	yardım etme"): gezegende Armory'den altınla. Oyuncu alanda yürüyüp
	sallıyor; önündeki yay içindeki düşmanlara vuruyor. Hasar dalganın can
	çarpanıyla ölçekli (her dalgada aynı oranda işe yarasın), seviyeyle artıyor.
	Düşmanlar oyuncuya saldırmıyor.
]]
DefenseConfig.Saber = {
	price = 150,                    -- ilk alış (seviye 1)
	upgradeCosts = { 90, 140, 200, 280 },   -- seviye 2..5
	damage = 34,                    -- × dalga can çarpanı
	perLevel = 0.3,
	radius = 8,
	cooldown = 0.45,
}

function DefenseConfig.SaberDamage(level: number, hpMul: number): number
	return DefenseConfig.Saber.damage * (1 + DefenseConfig.Saber.perLevel * math.max(0, level - 1)) * hpMul
end

-- Gemi büyük (gövde ~130 stud, burnu z ≈ 6'da); dükkânlar yanlarda küçük gemiler
DefenseConfig.Layout = {
	shipZ = -60,
	spawn = Vector2.new(-38, 10),
	-- Konsollar savunma çizgisinden biraz geride (Batur: "alana çok yakın")
	command = Vector2.new(20, 12),
	takeoff = Vector2.new(-20, 12),
	-- Dükkân gemicikleri alana dönük, yay biçiminde (Batur: "sıra halinde değil, biraz eğimli")
	hospital = Vector2.new(-80, 14),
	armory = Vector2.new(80, 14),
	shop = Vector2.new(-98, -32),
	market = Vector2.new(98, -32),
	shopsFace = 120,      -- dükkânların baktığı nokta (alanın ortası, z)
	groundRadius = 420,
}

-- ─── Roller ─────────────────────────────────────────────────────────────────

export type RoleDef = {
	id: string,
	name: string,
	icon: string,
	color: Color3,
	desc: string,
	hp: number,
	dmg: number,          -- vuruş başına (medic'te zayıf saldırı)
	range: number,        -- saldırı menzili
	cooldown: number,     -- iki vuruş arası (sn)
	engage: number,       -- geçen düşman bu mesafeye girince durup bununla dövüşüyor
	block: number,        -- aynı anda tutabildiği yakın dövüşçü düşman (fazlası yanından geçiyor)
	heal: number?,        -- iyileştirme (vuruş başına), yalnızca Medic
	healRange: number?,
	target: string,       -- "first" (kapıya en yakın) | "strongest" (en çok can)
	splash: number?,      -- hedefin çevresine yayılan hasar yarıçapı
}

DefenseConfig.Roles = {
	Brawler = {
		id = "Brawler", name = "Brawler", icon = "👊", color = Color3.fromRGB(255, 120, 70),
		desc = "Stops enemies in their tracks and punches them.",
		hp = 180, dmg = 13, range = 4.5, cooldown = 0.8, engage = 5, block = 2, target = "first",
	},
	Guard = {
		id = "Guard", name = "Guard", icon = "🛡️", color = Color3.fromRGB(90, 160, 255),
		desc = "Tons of health. Pulls nearby enemies onto itself.",
		hp = 340, dmg = 6, range = 4.5, cooldown = 1.0, engage = 8, block = 3, target = "first",
	},
	Shooter = {
		id = "Shooter", name = "Shooter", icon = "🎯", color = Color3.fromRGB(255, 220, 80),
		desc = "Shoots from far away. Keep it behind the front line.",
		hp = 70, dmg = 9, range = 17, cooldown = 0.85, engage = 2.5, block = 1, target = "first",
	},
	Assassin = {
		id = "Assassin", name = "Assassin", icon = "🗡️", color = Color3.fromRGB(190, 90, 255),
		desc = "Fragile, but one stab melts the strongest enemy in reach.",
		hp = 65, dmg = 38, range = 8, cooldown = 1.5, engage = 2.5, block = 1, target = "strongest",
	},
	Medic = {
		id = "Medic", name = "Medic", icon = "✚", color = Color3.fromRGB(110, 240, 140),
		desc = "Heals the most hurt crewmate nearby.",
		hp = 85, dmg = 4, range = 9, cooldown = 1.0, engage = 2.5, block = 1, target = "first",
		heal = 11, healRange = 13,
	},
} :: { [string]: RoleDef }

DefenseConfig.RoleOrder = { "Brawler", "Guard", "Shooter", "Assassin", "Medic" }

--[[
	Her crewmate'in rolü. Her nadirlik kademesinde dört karakter var; her
	kademede farklı roller düşsün diye elle dağıtıldı (adına göre).
	Listede olmayan (yeni eklenen) karakter adının özetinden bir rol alıyor.
]]
DefenseConfig.UnitRoles = {
	-- Common
	RedCrew = "Brawler", BlueCrew = "Shooter", YellowCrew = "Medic", LimeCrew = "Assassin",
	-- Uncommon
	Engineer = "Shooter", Scientist = "Medic", Janitor = "Brawler", Guardian = "Guard",
	-- Rare
	Shapeshift = "Brawler", VentCrawler = "Assassin", MedbayScan = "Medic", Sheriff = "Shooter",
	-- Epic
	Impostor = "Assassin", Reactor = "Shooter", O2Sabotage = "Medic", Emergency = "Guard",
	-- Legendary
	Ejected = "Assassin", Polus = "Guard", TheSkeld = "Shooter", Airship = "Brawler",
	-- Mythic
	DoubleImp = "Assassin", TripleImp = "Brawler", Jester = "Shooter",
	-- Secret
	AmogusPrime = "Guard", TheCrewmate = "Medic",
	-- Celestial
	Frostbite = "Shooter", SnowQueen = "Medic", GlacierGuard = "Guard",
	GemMiner = "Brawler", Prism = "Shooter", DiamondCrew = "Guard",
	Sunborn = "Shooter", FlameKnight = "Brawler", PhoenixRider = "Assassin",
	GravityBender = "Shooter", Singularity = "Assassin", NebulaWizard = "Medic",
	TitanHeart = "Guard", GalaxyGuardian = "Brawler", StarEmperor = "Shooter",
} :: { [string]: string }

function DefenseConfig.GetRole(unitId: string): RoleDef
	local id = DefenseConfig.UnitRoles[unitId]
	if not id then
		local sum = 0
		for i = 1, #unitId do
			sum += string.byte(unitId, i)
		end
		id = DefenseConfig.RoleOrder[sum % #DefenseConfig.RoleOrder + 1]
	end
	return DefenseConfig.Roles[id]
end

--[[
	Güç çarpanı: saniyelik gelirin (mutasyonla) logaritması. Kazandıran
	biraz daha güçlü, fark küçük:
	  Red Crewmate (2/sn) ≈ 1.02 · Sheriff ≈ 1.19 · The Crewmate ≈ 1.38
	  Star Emperor ≈ 1.70 · Impostor mutasyonu +0.07
]]
DefenseConfig.PowerPerDecade = 0.05

function DefenseConfig.GetPower(unitId: string, mutationId: string?): number
	local def = Config.GetUnit(unitId)
	if not def then
		return 1
	end
	local mutation = Config.GetMutation(mutationId)
	local income = def.income * (if mutation then mutation.incomeMul else 1)
	return 1 + DefenseConfig.PowerPerDecade * math.log10(math.max(1, income))
end

-- ─── Düşmanlar ──────────────────────────────────────────────────────────────

export type EnemyDef = {
	id: string,
	name: string,
	hp: number,
	speed: number,       -- stud/sn
	dmg: number,
	range: number,       -- 3 = yakın dövüş; büyükse uzaktan
	cooldown: number,
	leak: number,        -- gemiye varınca gövdeden düşen
	size: number,        -- model ölçeği
	cost: number,        -- dalga bütçesinde kapladığı yer
	from: number,        -- bu dalgadan itibaren çıkıyor
	cleave: number?,     -- vuruş hedefin çevresine de yayılıyor (yarıçap)
	boss: boolean?,
}

DefenseConfig.Enemies = {
	Grub    = { id = "Grub",    name = "Goo Slug",    hp = 42,  speed = 6,   dmg = 5,  range = 3,  cooldown = 1.0, leak = 1,  size = 1.0, cost = 1,   from = 1 },
	Skitter = { id = "Skitter", name = "Gloop Mite", hp = 22,  speed = 11,  dmg = 4,  range = 3,  cooldown = 0.7, leak = 1,  size = 0.75, cost = 0.7, from = 2 },
	Spitter = { id = "Spitter", name = "Spore Spitter", hp = 34,  speed = 5,   dmg = 7,  range = 13, cooldown = 1.3, leak = 1,  size = 0.95, cost = 1.4, from = 3 },
	Brute   = { id = "Brute",   name = "Ooze Golem",   hp = 170, speed = 3.8, dmg = 16, range = 3.4, cooldown = 1.4, leak = 3, size = 1.6, cost = 3,   from = 4 },
	Boss    = { id = "Boss",    name = "Glorp",    hp = 520, speed = 3.2, dmg = 26, range = 4,  cooldown = 1.6, leak = 8, size = 2.6, cost = 0,   from = 5, cleave = 4.5, boss = true },
} :: { [string]: EnemyDef }

DefenseConfig.EnemyOrder = { "Grub", "Skitter", "Spitter", "Brute" }

--[[
	Zorluk. Gezegen tabanı doğrusal (üst gezegen = daha derinden başlamak
	gibi), dalga üstel. Hasar candan yavaş büyüyor: düşman "süngerleşiyor"
	ama crewmate'leri tek vuruşta silmiyor.
]]
DefenseConfig.PlanetStep = 0.3
DefenseConfig.WaveHpGrowth = 1.09
DefenseConfig.WaveDmgGrowth = 1.05

function DefenseConfig.PlanetBase(planet: number): number
	return 1 + DefenseConfig.PlanetStep * math.max(0, planet - 1)
end

function DefenseConfig.WaveScale(planet: number, wave: number): (number, number)
	local base = DefenseConfig.PlanetBase(planet)
	local w = math.max(0, wave - 1)
	return base * DefenseConfig.WaveHpGrowth ^ w, math.sqrt(base) * DefenseConfig.WaveDmgGrowth ^ w
end

-- ─── Dalga üretimi ──────────────────────────────────────────────────────────

--[[
	"Gelen yer belli olacak ama geliş biçimleri her seferinde farklı":
	kapı sabit, yol ve diziliş her dalgada değişiyor. Yollar kapıdan
	rampaya giden kırık çizgiler; dalga başlamadan önce oyuncuya gösteriliyor.
]]
DefenseConfig.Patterns = {
	{ id = "straight", name = "HEAD-ON" },
	{ id = "left", name = "LEFT FLANK" },
	{ id = "right", name = "RIGHT FLANK" },
	{ id = "zigzag", name = "ZIGZAG" },
	{ id = "split", name = "SPLIT" },
	{ id = "pincer", name = "PINCER" },
	{ id = "swarm", name = "SWARM" },
}

export type Spawn = { t: number, kind: string, path: number, lane: number }
export type WavePlan = {
	pattern: string,
	name: string,
	paths: { { Vector2 } },
	spawns: { Spawn },
	boss: boolean,
}

local function curve(rng: Random, xs: { number }): { Vector2 }
	local f = DefenseConfig.Field
	local points = { f.entrance }
	local n = #xs
	for i, x in xs do
		local z = f.entrance.Y - (f.entrance.Y - f.gate.Y) * i / (n + 1)
		local jx = x + rng:NextNumber(-6, 6)
		local jz = z + rng:NextNumber(-8, 8)
		table.insert(points, Vector2.new(math.clamp(jx, -f.halfWidth + 4, f.halfWidth - 4), jz))
	end
	table.insert(points, f.gate)
	return points
end

local function pathFor(rng: Random, pattern: string, side: number?): { Vector2 }
	local s = side or (if rng:NextNumber() < 0.5 then -1 else 1)
	if pattern == "left" or pattern == "right" then
		local d = if pattern == "left" then -1 else 1
		return curve(rng, { d * 40, d * 52, d * 30 })
	elseif pattern == "zigzag" then
		return curve(rng, { s * 42, -s * 40, s * 34, -s * 14 })
	elseif pattern == "split" then
		return curve(rng, { s * 48, s * 46, s * 20 })
	elseif pattern == "pincer" then
		return curve(rng, { s * 54, s * 50, s * 8 })
	else
		return curve(rng, { rng:NextNumber(-14, 14), rng:NextNumber(-16, 16) })
	end
end

--[[
	Dalga planı. `last` bir önceki dalganın deseni (aynısı arka arkaya
	gelmesin). Deterministik: aynı tohum aynı dalgayı veriyor.
]]
function DefenseConfig.BuildWave(planet: number, wave: number, seed: number, last: string?): WavePlan
	local rng = Random.new(seed + wave * 7919 + planet * 104729)
	local boss = wave % DefenseConfig.WavesPerSector == 0

	-- Desen: ilk iki dalga düz gelsin (öğrenme); sonra rastgele, tekrar yok
	local pattern: string
	if wave <= 1 then
		pattern = "straight"
	else
		local pool = {}
		for _, p in DefenseConfig.Patterns do
			if p.id ~= last and not (p.id == "swarm" and wave < 3) and not (p.id == "split" and wave < 3)
				and not (p.id == "pincer" and wave < 4) then
				table.insert(pool, p.id)
			end
		end
		pattern = pool[rng:NextInteger(1, #pool)]
	end
	local name = pattern
	for _, p in DefenseConfig.Patterns do
		if p.id == pattern then
			name = p.name
		end
	end

	local paths: { { Vector2 } } = {}
	if pattern == "split" or pattern == "pincer" then
		paths[1] = pathFor(rng, pattern, -1)
		paths[2] = pathFor(rng, pattern, 1)
	else
		paths[1] = pathFor(rng, pattern)
	end

	-- Bütçe → düşman listesi
	local budget = 3 + 1.4 * wave
	local kinds: { string } = {}
	if pattern == "swarm" then
		-- Sürü: çoğu hızlı ve zayıf, bütçe biraz büyük
		budget *= 1.25
		while budget > 0 do
			local kind = if rng:NextNumber() < 0.8 then "Skitter" else "Grub"
			table.insert(kinds, kind)
			budget -= DefenseConfig.Enemies[kind].cost
		end
	else
		while budget > 0 do
			local pool = {}
			for _, id in DefenseConfig.EnemyOrder do
				local def = DefenseConfig.Enemies[id]
				if wave >= def.from then
					-- Grub her zaman en sık; diğerleri dalga ilerledikçe sıklaşıyor
					local weight = if id == "Grub" then 5 else math.min(4, 1 + (wave - def.from) * 0.35)
					table.insert(pool, { id = id, weight = weight })
				end
			end
			local total = 0
			for _, e in pool do
				total += e.weight
			end
			local roll = rng:NextNumber() * total
			local pick = pool[1].id
			for _, e in pool do
				roll -= e.weight
				if roll <= 0 then
					pick = e.id
					break
				end
			end
			table.insert(kinds, pick)
			budget -= DefenseConfig.Enemies[pick].cost
		end
	end
	-- Yavaşlar önde, hızlılar arkada gelince kümelenip bir anda vuruyorlar;
	-- desenine göre biraz karıştır
	if pattern ~= "swarm" then
		for i = #kinds, 2, -1 do
			local j = rng:NextInteger(1, i)
			kinds[i], kinds[j] = kinds[j], kinds[i]
		end
	end
	if boss then
		-- Boss ortalarda geliyor, önünde ve arkasında eskort
		table.insert(kinds, math.max(1, math.floor(#kinds * 0.6)), "Boss")
	end

	-- Zamanlama: akış ya da gruplar
	local spawns: { Spawn } = {}
	local grouped = pattern == "zigzag" or pattern == "pincer" or rng:NextNumber() < 0.35
	local t = 1.5
	for i, kind in kinds do
		local path = if #paths > 1 then (i % 2) + 1 else 1
		table.insert(spawns, { t = t, kind = kind, path = path, lane = rng:NextNumber(-2.2, 2.2) })
		if pattern == "swarm" then
			t += 0.35
		elseif grouped and i % 4 == 0 then
			t += 4.5
		elseif grouped then
			t += 0.45
		else
			t += math.max(0.55, 1.25 - wave * 0.02)
		end
	end

	return { pattern = pattern, name = name, paths = paths, spawns = spawns, boss = boss }
end

-- ─── Yıldız ve altın ────────────────────────────────────────────────────────

--[[
	"Binlerce kazanılmamalı, 3 yıldız mantığı": altın yalnızca YENİ yıldız
	için. Bir bölümde 1★ alıp sonra 3★ yapan farkı alıyor; aynı bölümü
	tekrar oynamak altın kasmaya yaramıyor.
]]
DefenseConfig.StarGold = { 30, 60, 100 }
DefenseConfig.PlanetGoldStep = 0.1

function DefenseConfig.StarsForLosses(losses: number): number
	if losses <= 0 then
		return 3
	elseif losses <= 2 then
		return 2
	end
	return 1
end

function DefenseConfig.GoldForStars(planet: number, stars: number): number
	if stars <= 0 then
		return 0
	end
	local base = DefenseConfig.StarGold[math.clamp(stars, 1, 3)]
	return math.floor(base * (1 + DefenseConfig.PlanetGoldStep * math.max(0, planet - 1)) + 0.5)
end

--[[ Yıldızı `had`'den `got`'a çıkaran oyuncunun aldığı altın. ]]
function DefenseConfig.GoldForImprovement(planet: number, had: number, got: number): number
	if got <= had then
		return 0
	end
	return DefenseConfig.GoldForStars(planet, got) - DefenseConfig.GoldForStars(planet, had)
end

-- ─── Gezegenler ─────────────────────────────────────────────────────────────

--[[
	Savunma gezegenleri uzaydakilerle aynı (Config.SpaceMonsters sırası).
	Açılma: rebirth kilidi uzaydakiyle aynı + bir önceki gezegende en az
	UnlockSectors bölüm bitmiş olmalı.
]]
DefenseConfig.UnlockSectors = 2

function DefenseConfig.PlanetCount(): number
	return #Config.SpaceMonsters
end

-- ─── Dükkânlar (altın) ──────────────────────────────────────────────────────

--[[
	Armory: rol başına seviye. Her seviye o roldeki crewmate'lerin canını
	ve hasarını (medic'te iyileştirmeyi) RoleLevelBonus kadar artırıyor.
]]
DefenseConfig.RoleMaxLevel = 10
DefenseConfig.RoleLevelBonus = 0.1

function DefenseConfig.RoleUpgradeCost(level: number): number?
	if level >= DefenseConfig.RoleMaxLevel then
		return nil
	end
	return 40 + 25 * level
end

-- Command Shop: sahaya konabilecek crewmate sayısı ve gemi gövdesi
DefenseConfig.BaseSlots = 4
DefenseConfig.SlotCosts = { 80, 160, 280, 450, 700 }   -- 5 → 9
DefenseConfig.BaseHull = 25
DefenseConfig.HullPerLevel = 6
DefenseConfig.HullCosts = { 60, 120, 200, 320, 480 }

function DefenseConfig.GetSlots(level: number): number
	return DefenseConfig.BaseSlots + math.clamp(level, 0, #DefenseConfig.SlotCosts)
end

function DefenseConfig.GetHull(level: number): number
	return DefenseConfig.BaseHull + DefenseConfig.HullPerLevel * math.clamp(level, 0, #DefenseConfig.HullCosts)
end

-- Market: savaşta tek kullanımlık destekler (dalga başına her birinden bir)
export type SupportDef = { id: string, name: string, icon: string, desc: string, price: number }
DefenseConfig.Supports = {
	{ id = "Strike", name = "Orbital Strike", icon = "☄️", desc = "Blasts every enemy around a spot.", price = 20 },
	{ id = "MedDrop", name = "Med Drop", icon = "💉", desc = "Heals your whole crew by half.", price = 15 },
	{ id = "Freeze", name = "Stasis Field", icon = "❄️", desc = "Freezes all enemies for 4 seconds.", price = 25 },
} :: { SupportDef }
DefenseConfig.SupportStack = 5
DefenseConfig.StrikeRadius = 10
DefenseConfig.StrikeDamage = 260         -- × dalganın can çarpanı
DefenseConfig.FreezeSeconds = 4

function DefenseConfig.GetSupport(id: string): SupportDef?
	for _, s in DefenseConfig.Supports do
		if s.id == id then
			return s
		end
	end
	return nil
end

return DefenseConfig
