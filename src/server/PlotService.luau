--!strict
-- Üsleri koddan kurar, oyunculara dağıtır, kaide (podium) durumunu tutar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local UnitModel = require(Shared.UnitModel)

local DataService = require(script.Parent.DataService)
local MonetizationService = require(script.Parent.MonetizationService)
local BadgeService = require(script.Parent.BadgeService)

local PlotService = {}

local plotsFolder: Folder
local plots: { Model } = {}
local ownerByPlot: { [Model]: Player? } = {}
local plotByOwner: { [Player]: Model } = {}

-- Start() tekrar çağrılabilsin diye: eski bağlantılar burada tutulur,
-- yeniden kurarken kesilir. Yoksa PlayerAdded iki kez tetiklenir.
local connections: { RBXScriptConnection } = {}

-- Oyuncu çıkarken üssü boşaltılıyor. O sırada profile yazarsak kayıtlı
-- karakterleri kaydedilmeden hemen önce sileriz. Bu bayrak onu engelliyor.
local releasing: { [Player]: boolean } = {}

-- Üs bekleyen oyuncular, giriş sırasına göre
local waiting: { Player } = {}

local notifyRemote: RemoteEvent

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError)
	end
end

-- ─── Kurulum ────────────────────────────────────────────────────────────────

local function newAnchoredPart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

--[[
	═══ ÜS YERLEŞİMİ ════════════════════════════════════════════════════════

	Bütün üs tek bir koordinat sözleşmesine göre kuruluyor. Buradaki sayılar
	hem zemini hem üst katları hem de kaideleri bağlar; tek yerde durmaları
	bilinçli, yoksa biri değişince diğeri kayıyor.

	x ekseni (üs genişliği 72, yani ±36):
	    -36 .. -25   merdiven kuyusu (STAIR_W = 11)
	    -25 .. +36   güverte
	    kaideler ortada, ±11.25 ve ±3.75
	    bonus kaideler ±18.75
	    yükseltme kulübesi +27 civarı

	z ekseni (üs derinliği 52, yani ±26):
	    -25   tabela
	    -18   doğuş pedi
	     -9   ön kaide sırası
	      0   bonus kaide sırası
	     +9   arka kaide sırası
	    +21   konveyör

	KAİDE DAĞILIMI — "5'e 3 olmuş, 4'e 4 olmalı" şikâyetinin sebebi:
	eskiden 10 kaide sırayla ikiye bölünüyordu (1-5 ön, 6-10 arka) ve bonus
	olanlar 9-10'du. Yani ön sırada 5 kullanılabilir, arka sırada 3 kalıyordu.
	Artık 8 temel kaide 4+4 ortada, 2 bonus kaide de yanlarda ayrı duruyor.
	Bonus alınmasa bile temel diziliş simetrik.
]]
local LAYOUT = {
	STAIR_W = 11,
	ROW_Z = 9,           -- ön/arka kaide sırasının merkezden uzaklığı
	BONUS_X = 2.5,       -- bonus kaidenin kaç "PodiumSpacing" kadar yanda olduğu
	DECK_INSET = 6,      -- güvertenin ön/arka kenarının üs kenarından içeride kalması
}

--[[
	Bir kaidenin üs merkezine göre konumu. Hem zemin hem üst katlar bunu
	kullanıyor, böylece katlar birbirinin tam üstüne oturuyor.

	index 1..PodiumsPerPlot  → temel kaideler, 4+4 ortada
	index sonrası            → bonus kaideler, yanlarda simetrik
]]
local function podiumOffset(index: number): Vector3
	local base = Config.PodiumsPerPlot
	local spacing = Config.PodiumSpacing

	if index <= base then
		local perRow = math.ceil(base / 2)
		local front = index <= perRow
		local column = if front then index - 1 else index - perRow - 1
		return Vector3.new(
			(column - (perRow - 1) / 2) * spacing,
			0,
			if front then -LAYOUT.ROW_Z else LAYOUT.ROW_Z
		)
	end

	-- Bonus: merkezin iki yanında, sıraların arasındaki boş şeritte
	local n = index - base
	local side = if n % 2 == 1 then -1 else 1
	local rank = math.floor((n - 1) / 2)
	return Vector3.new(side * (LAYOUT.BONUS_X + rank) * spacing, 0, 0)
end

--[[
	═══ ÜST KAT ═════════════════════════════════════════════════════════════

	İki merdiven vardı, teke indi — ikisi birden hem gereksizdi hem de
	güvertenin iki ucunu da yiyordu. Tek merdiven SOL uçta; sağ uç tamamen
	güverte olarak kalıyor.

	Önceki sürümün üç somut hatası vardı, üçü de burada düzeltildi:

	  1. Merdivenin ÖNÜNDE duvar vardı. "StairWall" kuyunun girişine
	     konuyordu ve basamaklara ulaşılamıyordu. Artık duvarlar merdivenin
	     YANLARINDA, giriş açık.
	  2. Sahanlık ana güverteyle üst üste biniyordu ("bloklar iç içe
	     girmiş"). Artık güverte merdiven şeridinin bittiği yerden başlıyor,
	     ikisi hiç kesişmiyor.
	  3. Korkuluk basamakların dışına taşıyordu ("demir çıkıntısı"). Korkuluk
	     artık basamak dizisiyle aynı uzunlukta ve aynı merkezde.
]]
local function buildUpperFloor(parent: Instance, origin: Vector3, deckTop: number)
	local halfX = Config.PlotSize.X / 2
	local halfZ = Config.PlotSize.Z / 2
	local rise = Config.FloorHeight

	local stairW = LAYOUT.STAIR_W
	local deckZ = Config.PlotSize.Z - LAYOUT.DECK_INSET * 2

	-- Merdiven şeridi solda: x ∈ [-halfX, -halfX + stairW]
	local stairX = -halfX + stairW / 2
	-- Güverte onun sağında başlıyor, üssün sağ kenarına kadar
	local deckX0 = -halfX + stairW
	local deckW = halfX - deckX0
	local deckCX = deckX0 + deckW / 2

	local DECK_COLOR = Color3.fromRGB(64, 76, 82)
	local TRIM_COLOR = Color3.fromRGB(126, 140, 144)
	local RAIL_COLOR = Color3.fromRGB(168, 181, 184)

	local function slab(name: string, size: Vector3, offset: Vector3, color: Color3): Part
		local p = newAnchoredPart(name, size, CFrame.new(origin + offset), color, parent)
		p.Material = Enum.Material.Metal
		return p
	end

	-- ── Ana güverte ────────────────────────────────────────────────────────
	slab("Deck", Vector3.new(deckW, 1, deckZ), Vector3.new(deckCX, deckTop - 0.5, 0), DECK_COLOR)

	-- Kenar süpürgeliği: levhanın kalınlığı okunsun
	for _, sz in { -1, 1 } do
		slab("DeckEdge", Vector3.new(deckW, 1.4, 0.8),
			Vector3.new(deckCX, deckTop - 0.7, sz * deckZ / 2), TRIM_COLOR)
	end
	slab("DeckEdge", Vector3.new(0.8, 1.4, deckZ),
		Vector3.new(halfX - 0.4, deckTop - 0.7, 0), TRIM_COLOR)

	--[[
		── Merdiven ───────────────────────────────────────────────────────
		Basamak sayısı yükseklikten türetiliyor; FloorHeight değişirse
		merdiven kendiliğinden uyuyor. Basamak yüksekliği 1.4 civarında
		tutuluyor çünkü Roblox karakteri zıplamadan ancak 2 studa çıkıyor.

		Merdiven z ekseninde tırmanıyor: arkadan (+z) öne (-z) doğru. Üst
		ucunda sahanlık var, sahanlık güverteye yandan bağlanıyor.
	]]
	local STEPS = math.max(6, math.ceil(rise / 1.4))
	local stepRise = rise / STEPS
	local stepRun = 2.4
	local stairLen = STEPS * stepRun

	-- Basamak dizisinin z aralığı: [zTop, zTop + stairLen]
	local zTop = -deckZ / 2 + 2

	for i = 1, STEPS do
		local p = newAnchoredPart(
			"Step",
			Vector3.new(stairW - 1.2, stepRise, stepRun),
			CFrame.new(origin + Vector3.new(
				stairX,
				deckTop - rise + (i - 0.5) * stepRise,
				zTop + stairLen - (i - 0.5) * stepRun
			)),
			if i % 2 == 0 then DECK_COLOR else TRIM_COLOR,
			parent
		)
		p.Material = Enum.Material.Metal
		p.CanCollide = true
	end

	-- Üst sahanlık: basamakların bittiği yerden güvertenin ön kenarına
	local landingLen = zTop + deckZ / 2
	slab("Landing", Vector3.new(stairW, 1, landingLen),
		Vector3.new(stairX, deckTop - 0.5, zTop - landingLen / 2), DECK_COLOR)

	--[[
		SADECE DIŞ duvar. İç tarafta (güverteye bakan yüz) duvar OLMAMALI.

		İlk sürümde iki yana da duvar konuyordu ve bu kimsenin merdiveni
		kullanamamasına yol açıyordu: iç duvar sahanlığı güverteden ayırıyor,
		oyuncu merdivenin tepesine çıkıp orada kapalı kalıyordu. Üstelik 3.
		kata çıkmak için oyuncunun 2. katın güvertesinden merdiven kuyusuna
		YANDAN girmesi gerekiyor — iç duvar o girişi de kapatıyordu.

		Kuyunun güverteye bakan yüzü açık; düşme riski yok çünkü orada zaten
		bir üst basamak var.
	]]
	slab("StairSide", Vector3.new(0.8, rise, stairLen + landingLen),
		Vector3.new(
			stairX - (stairW / 2 - 0.4),
			deckTop - rise / 2,
			zTop + stairLen / 2 - landingLen / 2
		),
		TRIM_COLOR)

	--[[
		Korkuluk: basamak dizisiyle AYNI uzunlukta ve aynı merkezde. Önceki
		sürümde uzunluk bağımsız hesaplanıyordu ve uçları basamakların
		dışına taşıyordu — ekranda havada duran demir çubuk olarak
		görünüyordu.
	]]
	local slope = math.atan2(rise, stairLen)
	local railLen = math.sqrt(rise * rise + stairLen * stairLen)
	for _, rs in { -1, 1 } do
		local rail = newAnchoredPart(
			"StairRail",
			Vector3.new(0.4, 0.4, railLen),
			CFrame.new(origin + Vector3.new(
				stairX + rs * (stairW / 2 - 1),
				deckTop - rise / 2 + 3.4,
				zTop + stairLen / 2
			)) * CFrame.Angles(slope, 0, 0),
			RAIL_COLOR,
			parent
		)
		rail.Material = Enum.Material.Metal
		rail.CanCollide = false
	end

	--[[
		── Güverte korkuluğu ──────────────────────────────────────────────
		Sadece DIŞ kenarlara: sağ uç ve ön/arka kenarların uçları. Kaidelerin
		önü açık kalıyor, yoksa karakterler korkuluğun arkasında kalıyor.
	]]
	local function railing(cx: number, cz: number, length: number, along: string)
		local size = if along == "x"
			then Vector3.new(length, 0.35, 0.35)
			else Vector3.new(0.35, 0.35, length)

		slab("Rail", size, Vector3.new(cx, deckTop + 3.2, cz), RAIL_COLOR).CanCollide = false

		local posts = math.max(2, math.floor(length / 8))
		for i = 0, posts do
			local t = i / posts
			slab("RailPost", Vector3.new(0.35, 3.2, 0.35), Vector3.new(
				if along == "x" then cx - length / 2 + length * t else cx,
				deckTop + 1.6,
				if along == "z" then cz - length / 2 + length * t else cz
			), RAIL_COLOR).CanCollide = false
		end
	end

	railing(halfX - 0.5, 0, deckZ, "z")
	for _, sz in { -1, 1 } do
		railing(halfX - 10, sz * (deckZ / 2 - 0.5), 18, "x")
	end

	--[[
		── Kolonlar ───────────────────────────────────────────────────────
		Güverteyi alt kata bağlıyorlar. Yapısal olarak gereksiz (her şey
		anchored) ama görsel olarak şart: kolonsuz üst kat havada asılı
		duruyor. Kaidelerin arasına denk gelmesinler diye köşelere yakın.
	]]
	for _, sx in { 0.06, 0.94 } do
		for _, sz in { -1, 1 } do
			slab("Column", Vector3.new(2, rise, 2), Vector3.new(
				deckX0 + deckW * sx,
				deckTop - rise / 2 - 1,
				sz * (deckZ / 2 - 1.5)
			), TRIM_COLOR)
		end
	end

	-- Güvertenin altına gömme aydınlatma: alt kat karanlıkta kalmasın
	for _, t in { 0.3, 0.7 } do
		local lamp = newAnchoredPart(
			"DeckLamp",
			Vector3.new(deckW * 0.36, 0.3, 3),
			CFrame.new(origin + Vector3.new(deckX0 + deckW * t, deckTop - 1.2, 0)),
			Color3.fromRGB(255, 244, 222),
			parent
		)
		lamp.Material = Enum.Material.Neon
		lamp.CanCollide = false

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 244, 222)
		light.Range = 26
		light.Brightness = 0.7
		light.Parent = lamp
	end
end

--[[
	═══ YÜKSELTME KULÜBESİ ══════════════════════════════════════════════════

	İlk sürüm fazla kalabalıktı: tezgâh, arka pano, iki direk, çatı, eğik
	tente, tabela, lamba — ve üstüne UpgradeService'in dört fiziksel panosu.
	Tezgâh 15 stud, panolar 26 stud yer istiyordu; birbirine ve direklere
	giriyorlardı. Eğik tente de karşıdan bakınca havada duran turuncu bir
	levha gibi görünüyordu.

	Sadeleştirildi. Kalanlar:
	    tezgâh          — satıcının arkasına geçtiği yüzey
	    arka pano       — kulübeyi bir "dükkân" yapan düz yüzey
	    çift yüzlü tabela — iki taraftan da UPGRADES yazıyor
	    tavan + lamba   — tezgâhı aydınlatan gömme armatür
	    satıcı          — uzun, eşsiz görünümlü görevli
	    tetik alanı     — üstüne basınca arayüz açılan görünmez daire

	Yükseltme listesi artık fiziksel değil: oyuncu tetik alanına girince
	istemcideki UpgradePanel açılıyor.
]]
local function buildUpgradeBooth(parent: Instance, origin: Vector3)
	local halfX = Config.PlotSize.X / 2
	local halfZ = Config.PlotSize.Z / 2
	local topY = Config.PlotSize.Y / 2

	--[[
		Sağ kenarda, ön ve arka arasında. Çakışma kontrolü:
		    doğuş pedi   x ±4,   z -23..-15
		    kaideler     x ±11.2 (sıralar), ±18.8 (bonus)
		    konveyör     z +21
		    merdiven     x -36..-25
		Kulübe x 22..34, z -10..-2 → hiçbiriyle kesişmiyor.
	]]
	local bx = halfX - 8
	local bz = -6

	local booth = Instance.new("Model")
	booth.Name = "UpgradeBooth"
	booth.Parent = parent

	local SHELL = Color3.fromRGB(96, 108, 114)
	local TRIM = Color3.fromRGB(168, 181, 184)
	local ACCENT = Color3.fromRGB(206, 172, 72)
	local DARK = Color3.fromRGB(27, 34, 39)

	local root = Vector3.new(bx, topY, bz)

	local function part(name: string, size: Vector3, offset: Vector3, color: Color3, collide: boolean?): Part
		local p = newAnchoredPart(name, size, CFrame.new(origin + root + offset), color, booth)
		p.Material = Enum.Material.Metal
		p.CanCollide = collide ~= false
		return p
	end

	-- Tezgâh: oyuncunun karşısında, -z tarafında
	part("Counter", Vector3.new(12, 4, 2.6), Vector3.new(0, 2, -2.6), SHELL)
	part("CounterTop", Vector3.new(13, 0.6, 4), Vector3.new(0, 4.3, -2.8), TRIM)
	part("CounterStripe", Vector3.new(12.2, 0.5, 0.3), Vector3.new(0, 3.1, -3.95), ACCENT, false)

	-- Arka pano ve yan duvarlar: dükkân hissi
	part("BoothBack", Vector3.new(13, 10, 1), Vector3.new(0, 5, 2.2), SHELL)
	for _, s in { -1, 1 } do
		part("BoothSide", Vector3.new(1, 10, 5.4), Vector3.new(s * 6, 5, -0.3), SHELL)
	end

	-- Tavan: düz, taşkın yok. Eğik tente kaldırıldı.
	part("BoothRoof", Vector3.new(14.4, 0.8, 7.4), Vector3.new(0, 10.4, -0.4), TRIM)

	--[[
		Tabela ÇİFT YÜZLÜ. Üssün iki yanından da gelinebiliyor; tek yüzlü
		tabela arkadan bakınca boş bir levha oluyordu.
	]]
	local sign = part("BoothSign", Vector3.new(12, 2.8, 0.5), Vector3.new(0, 12.2, -0.4), DARK, false)

	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local surface = Instance.new("SurfaceGui")
		surface.Name = "Label" .. face.Name
		surface.Face = face
		surface.CanvasSize = Vector2.new(240, 56)
		surface.LightInfluence = 0
		surface.Parent = sign

		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBold
		text.TextScaled = true
		text.TextColor3 = ACCENT
		text.Text = "UPGRADES"
		text.Parent = surface
	end

	-- Tavana gömme lamba
	local lamp = part("BoothLamp", Vector3.new(10, 0.3, 2), Vector3.new(0, 9.9, -1.4), Color3.fromRGB(255, 244, 222), false)
	lamp.Material = Enum.Material.Neon
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 244, 222)
	light.Range = 22
	light.Brightness = 0.8
	light.Parent = lamp

	--[[
		═══ TETİK ALANI ═════════════════════════════════════════════════════

		Tezgâhın önünde görünmez bir daire. Oyuncu üstüne basınca istemci
		yükseltme arayüzünü açıyor, çıkınca kapatıyor.

		ProximityPrompt yerine alan kullanılmasının sebebi: prompt tek bir
		yükseltme için "basılı tut" istiyor ve dört yükseltme dört prompt
		demek. Alan tek seferde bütün listeyi açıyor ve oyuncunun hiçbir
		tuşa basması gerekmiyor — dükkâna girer gibi.

		CanCollide kapalı (içinden geçilebilir), CanQuery açık: istemci
		oyuncunun mesafesini buna göre ölçüyor.
	]]
	local zone = newAnchoredPart(
		"UpgradeZone",
		Vector3.new(16, 0.4, 16),
		CFrame.new(origin + root + Vector3.new(0, 0.2, -9)),
		ACCENT,
		booth
	)
	zone.Shape = Enum.PartType.Cylinder
	zone.CFrame = CFrame.new(origin + root + Vector3.new(0, 0.2, -9)) * CFrame.Angles(0, 0, math.rad(90))
	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanTouch = false

	-- Zeminde alanın nerede olduğunu gösteren soluk halka
	part("ZoneRing", Vector3.new(16, 0.14, 16), Vector3.new(0, 0.07, -9), ACCENT, false).Transparency = 0.72
	part("ZoneRingInner", Vector3.new(12.4, 0.16, 12.4), Vector3.new(0, 0.08, -9), DARK, false).Transparency = 0.5

	--[[
		═══ SATICI ══════════════════════════════════════════════════════════

		Uzatıldı: gövde ölçüleri 1.35 kat ve tezgâhın üstünden görünsün diye
		yükseltildi. Önceki hâlinde tezgâhın arkasında kalıyor, sadece
		kafasının üstü görünüyordu.

		Kasten EŞSİZ: rengi hiçbir mürettebat tulumunda yok (soluk mor-gri),
		vizörü sarı (hepsininki mavi), kulaklığı da hiçbir nadirlik
		kademesinde yok. Bakınca "bu satılık bir karakter değil, görevli"
		anlaşılıyor.
	]]
	local SKIN = Color3.fromRGB(122, 112, 148)
	local VISOR = Color3.fromRGB(240, 226, 150)
	local S = 1.35                       -- ölçek
	local FEET = 0.6                     -- tezgâhın arkasında bir basamak

	local vroot = Vector3.new(bx, topY + FEET, bz + 0.4)

	local function vendor(name: string, size: Vector3, offset: Vector3, color: Color3, shape: Enum.PartType?): Part
		local p = newAnchoredPart(name, size * S, CFrame.new(origin + vroot + offset * S), color, booth)
		p.Material = Enum.Material.SmoothPlastic
		p.CanCollide = false
		if shape then
			p.Shape = shape
		end
		return p
	end

	-- Satıcının üstünde durduğu basamak: tezgâhın üstünden görünsün
	part("VendorStep", Vector3.new(6, FEET, 3), Vector3.new(0, FEET / 2, 0.4), SHELL)

	-- Gövde silindir; ekseni X olduğu için Z etrafında 90° çevriliyor
	local body = vendor("VendorBody", Vector3.new(2.2, 2.6, 2.2), Vector3.new(0, 1.9, 0), SKIN, Enum.PartType.Cylinder)
	body.CFrame = CFrame.new(origin + vroot + Vector3.new(0, 1.9 * S, 0)) * CFrame.Angles(0, 0, math.rad(90))

	vendor("VendorHead", Vector3.new(2.2, 2.2, 2.2), Vector3.new(0, 3.2, 0), SKIN, Enum.PartType.Ball)
	vendor("VendorVisor", Vector3.new(1.5, 0.95, 0.6), Vector3.new(0, 3.25, -0.95), VISOR)
	vendor("VendorPack", Vector3.new(0.9, 2.1, 1), Vector3.new(0, 2.1, 1.35), SKIN)
	for _, s in { -1, 1 } do
		vendor("VendorLeg", Vector3.new(0.8, 1.4, 1.1), Vector3.new(s * 0.6, 0.7, 0), SKIN)
		vendor("VendorPhone", Vector3.new(0.5, 1, 1), Vector3.new(s * 1.2, 3.3, 0), TRIM)
	end
	-- Kulaklık köprüsü: iki kulaklığı birleştiren bant
	vendor("VendorBridge", Vector3.new(2.5, 0.35, 0.9), Vector3.new(0, 4.3, 0), TRIM)
	vendor("VendorCap", Vector3.new(1.9, 0.55, 1.9), Vector3.new(0, 4.62, 0), ACCENT)
	vendor("VendorCapTip", Vector3.new(1.5, 0.22, 1.1), Vector3.new(0, 4.4, -1.1), ACCENT)
end

local function buildPlot(index: number): Model
	local plot = Instance.new("Model")
	plot.Name = string.format("Plot%d", index)

	-- Izgara yerleşimi: soldan sağa PlotColumns tane, sonra alt satır.
	-- Tek sıra isteniyorsa Config.PlotColumns = Config.PlotCount yapılır.
	local columns = Config.PlotColumns or Config.PlotCount
	local column = (index - 1) % columns
	local row = math.floor((index - 1) / columns)

	local origin = Vector3.new(
		column * Config.PlotSpacing,
		0,
		row * (Config.PlotRowSpacing or 0)
	)

	-- Zemin
	local base = newAnchoredPart("Base", Config.PlotSize, CFrame.new(origin), Color3.fromRGB(58, 64, 76), plot)
	base.Material = Enum.Material.Concrete
	plot.PrimaryPart = base

	-- Kaideler: her katta iki sıra. 1. kat zeminde ve açık gelir,
	-- üst katlar rebirth ile açılır. Slot numaraları katlar boyunca
	-- kesintisiz devam ediyor ki kayıttaki slot -> kaide eşlemesi bozulmasın.
	local podiums = Instance.new("Folder")
	podiums.Name = "Podiums"
	podiums.Parent = plot

	local floors = Instance.new("Folder")
	floors.Name = "Floors"
	floors.Parent = plot

	local groundY = Config.PlotSize.Y / 2   -- 1. katın yürüme yüzeyi

	for floor = 1, Config.MaxFloors do
		local deckTop = groundY + (floor - 1) * Config.FloorHeight

		local floorModel = Instance.new("Model")
		floorModel.Name = string.format("Floor%d", floor)
		floorModel.Parent = floors

		if floor > 1 then
			buildUpperFloor(floorModel, origin, deckTop)
		end

		--[[
			Kaide konumu artık podiumOffset'ten geliyor: temel 8 tanesi 4+4
			ortada, bonus olanlar yanlarda. Eskiden sıra sırayla ikiye
			bölünüyordu ve bonuslar arka sıranın sonuna düşüyordu; oyuncu
			ön sırada 5, arka sırada 3 kullanılabilir kaide görüyordu.
		]]
		for index = 1, Config.PodiumsPerFloorTotal do
			local offset = podiumOffset(index) + Vector3.new(0, deckTop + 0.5, 0)

			local podium = newAnchoredPart(
				"Podium",
				Vector3.new(4, 1, 4),
				CFrame.new(origin + offset),
				Color3.fromRGB(90, 98, 112),
				podiums
			)
			podium:SetAttribute("SlotIndex", (floor - 1) * Config.PodiumsPerFloorTotal + index)
			podium:SetAttribute("Floor", floor)
			podium:SetAttribute("Bonus", index > Config.PodiumsPerPlot)
			podium:SetAttribute("UnitId", "")
			podium:SetAttribute("MutationId", "")
			podium:SetAttribute("PlacedAt", 0)
		end
	end

	buildUpgradeBooth(plot, origin)

	-- Konveyör (görsel şerit)
	local conveyor = newAnchoredPart(
		"Conveyor",
		Vector3.new(Config.PlotSize.X - 8, 1, 5),
		CFrame.new(origin + Vector3.new(0, Config.PlotSize.Y / 2 + 0.5, Config.PlotSize.Z / 2 - 5)),
		Color3.fromRGB(38, 42, 52),
		plot
	)
	conveyor.Material = Enum.Material.DiamondPlate

	local items = Instance.new("Folder")
	items.Name = "Items"
	items.Parent = plot

	-- Sahip tabelası
	local sign = newAnchoredPart(
		"Sign",
		Vector3.new(6, 0.4, 0.4),
		CFrame.new(origin + Vector3.new(0, 8, -Config.PlotSize.Z / 2 + 1)),
		Color3.fromRGB(30, 34, 42),
		plot
	)

	--[[
		AlwaysOnTop kapali: acikken tabela 2B HUD'un uzerine ciziliyordu.
		Kendi ussune yaklasan oyuncunun ekraninin yarisini "48YUSUF" kapliyor,
		siralama tablosunun ustune biniyordu. Boyut da kucultuldu; 12x3 olcek
		uzaktan devasa duruyordu.
	]]
	local gui = Instance.new("BillboardGui")
	gui.Name = "OwnerLabel"
	gui.Size = UDim2.fromScale(7, 1.8)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 170
	gui.Parent = sign

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(235, 240, 255)
	label.TextStrokeTransparency = 0.3
	label.Text = "EMPTY BASE"
	label.Parent = gui

	-- Doğuş pedi: oyuncu ortada değil, kendi üssünde başlasın
	local spawnPad = newAnchoredPart(
		"SpawnPad",
		Vector3.new(8, 0.4, 8),
		CFrame.new(origin + Vector3.new(0, Config.PlotSize.Y / 2 + 0.3, -Config.PlotSize.Z / 2 + 7)),
		Color3.fromRGB(70, 200, 255),
		plot
	)
	spawnPad.Material = Enum.Material.Neon
	spawnPad.Transparency = 0.45

	plot:SetAttribute("Locked", false)
	plot:SetAttribute("LockUsedAt", 0)
	plot:SetAttribute("UnlockedFloors", 1)

	--[[
		Satırlar birbirine baksın. Üs varsayılan olarak -Z yönüne bakıyor
		(tabela orada). Iki satırlı düzende üst satır bu haliyle koridorun
		tersine bakıyor, o yüzden 180° çevriliyor. Sonuç: iki sıra üs
		aradaki koridora bakar, oyuncu ortada durup ikisini birden görür.

		180° eksen hizasını bozmuyor, bu yüzden isInsidePlot gibi dünya
		eksenine bakan kontroller çalışmaya devam ediyor. Başka bir açı
		seçilirse oralar da düzeltilmeli.
	]]
	local rowCount = math.ceil(Config.PlotCount / columns)
	if rowCount > 1 and row % 2 == 0 then
		plot:PivotTo(CFrame.new(origin) * CFrame.Angles(0, math.pi, 0))
	end

	plot.Parent = plotsFolder

	--[[
		Kilitli katları HEMEN kapat. Eskiden bu sadece üs bir oyuncuya
		verilince çalışıyordu; sahipsiz üste 2. ve 3. kat tamamen katı ve
		görünür duruyordu, hatta kilitli olmasına rağmen merdiveninden
		çıkılabiliyordu.
	]]
	PlotService.SetUnlockedFloors(plot, 1)
	return plot
end

-- ─── Kaide işlemleri ────────────────────────────────────────────────────────

function PlotService.GetPodiums(plot: Model): { Part }
	local result: { Part } = {}
	local folder = plot:FindFirstChild("Podiums")
	if not folder then
		return result
	end

	for _, child in folder:GetChildren() do
		if child:IsA("Part") then
			table.insert(result, child)
		end
	end

	table.sort(result, function(a, b)
		return (a:GetAttribute("SlotIndex") :: number) < (b:GetAttribute("SlotIndex") :: number)
	end)
	return result
end

function PlotService.IsOccupied(podium: Part): boolean
	return (podium:GetAttribute("UnitId") :: string) ~= ""
end

--[[
	Kaide kullanılabilir mi. İki koşul var: katı açık olacak (rebirth) ve
	bonus kaideyse sahibinin gamepass'i olacak.
]]
function PlotService.IsPodiumUnlocked(podium: Part): boolean
	local plot = PlotService.GetPlotFromDescendant(podium)
	if not plot then
		return false
	end

	local floor = (podium:GetAttribute("Floor") :: number?) or 1
	local unlocked = (plot:GetAttribute("UnlockedFloors") :: number?) or 1
	if floor > unlocked then
		return false
	end

	if podium:GetAttribute("Bonus") then
		local owner = ownerByPlot[plot]
		if not owner or MonetizationService.GetExtraPodiumsPerFloor(owner) <= 0 then
			return false
		end
	end

	return true
end

--[[ Yalnızca açık katlardaki kaideler. ]]
function PlotService.GetUnlockedPodiums(plot: Model): { Part }
	local unlocked = (plot:GetAttribute("UnlockedFloors") :: number?) or 1
	local result: { Part } = {}

	for _, podium in PlotService.GetPodiums(plot) do
		local floor = (podium:GetAttribute("Floor") :: number?) or 1
		if floor <= unlocked and PlotService.IsPodiumUnlocked(podium) then
			table.insert(result, podium)
		end
	end
	return result
end

function PlotService.FindEmptyPodium(plot: Model): Part?
	for _, podium in PlotService.GetUnlockedPodiums(plot) do
		if not PlotService.IsOccupied(podium) then
			return podium
		end
	end
	return nil
end

--[[
	Açık kat sayısını değiştirir ve kapalı katları hayalete çevirir:
	görünür ama üstüne çıkılamaz, kaidesi kullanılamaz. Tamamen
	gizlemek yerine böyle bırakıyoruz ki oyuncu ne kazanacağını görsün.
]]
function PlotService.SetUnlockedFloors(plot: Model, count: number)
	local unlocked = math.clamp(count, 1, Config.MaxFloors)
	plot:SetAttribute("UnlockedFloors", unlocked)

	--[[
		Kilitli kat TAMAMEN yok sayılmalı: görünmez, çarpışmasız, gölgesiz
		ve ışıksız.

		Eski hâli %75 saydam + çarpışma kapalıydı ve iki şikâyete yol
		açıyordu. Birincisi görsel: satın alınmamış katın merdiveni ve
		kaideleri havada asılı hayalet bloklar olarak duruyordu. İkincisi
		daha kötü: bazı parçalar (güverte altı lamba, korkuluk) çarpışması
		açık kalıyor ve oyuncuyu GÖRÜNMEZ biçimde engelliyordu.

		Artık tek geçişte hepsi kapanıyor. Korkuluk gibi zaten çarpışmasız
		olması gereken parçalar için `BaseCollide` niteliği var: kat açılınca
		o parça kendi varsayılanına dönüyor, körü körüne true olmuyor.
	]]
	local function setFloorParts(root: Instance, open: boolean)
		for _, part in root:GetDescendants() do
			if not part:IsA("BasePart") then
				continue
			end

			if part:GetAttribute("BaseCollide") == nil then
				part:SetAttribute("BaseCollide", part.CanCollide)
			end

			part.CanCollide = open and part:GetAttribute("BaseCollide") == true
			part.Transparency = if open then 0 else 1
			part.CastShadow = open

			local light = part:FindFirstChildOfClass("PointLight")
			if light then
				light.Enabled = open
			end
		end
	end

	local floors = plot:FindFirstChild("Floors")
	if floors then
		for _, floorModel in floors:GetChildren() do
			local index = tonumber(string.match(floorModel.Name, "%d+")) or 1
			setFloorParts(floorModel, index <= unlocked)
		end
	end

	--[[
		Kaideler Floors'un altında değil, ayrı bir klasörde. Kat kilitliyse
		o kata ait kaideler de tamamen gizleniyor.

		Bonus (gamepass) kaideler farklı: katları açıksa görünür kalıyorlar
		ama yarı saydam ve çarpışmasız — "burada bir yer var ama senin
		değil" mesajı. Onları da gizlersek satın alınacak bir şey olduğu
		hiç belli olmaz.
	]]
	for _, podium in PlotService.GetPodiums(plot) do
		local floor = podium:GetAttribute("Floor")
		local floorOpen = typeof(floor) ~= "number" or floor <= unlocked
		local open = PlotService.IsPodiumUnlocked(podium)

		if not floorOpen then
			podium.Transparency = 1
			podium.CanCollide = false
			podium.CastShadow = false
		else
			podium.Transparency = if open then 0 else 0.6
			podium.CanCollide = open
			podium.CastShadow = true
		end
	end
end

--[[
	Üssün güncel kaide içeriğini sahibinin profiline yazar.
	Profil DataService'in kaydettiği tablo olduğu için ayrıca kaydetmek
	gerekmiyor; bir sonraki autosave veya çıkış kaydı bunu diske alır.
]]
local function syncProfile(podium: Part)
	local plot = PlotService.GetPlotFromDescendant(podium)
	local owner = plot and ownerByPlot[plot]
	if not (plot and owner) or releasing[owner] then
		return
	end

	local profile = DataService.Get(owner)
	if not profile then
		return
	end

	local units = {}
	for _, other in PlotService.GetPodiums(plot) do
		local unitId = other:GetAttribute("UnitId") :: string
		if unitId ~= "" then
			local mutationId = other:GetAttribute("MutationId") :: string
			table.insert(units, {
				slot = other:GetAttribute("SlotIndex") :: number,
				unitId = unitId,
				mutationId = if mutationId == "" then nil else mutationId,
			})
		end
	end

	profile.units = units
end

--[[ Kaideye karakter yerleştirir. Doluysa false döner. ]]
function PlotService.PlaceUnit(podium: Part, unitId: string, mutationId: string?): boolean
	if PlotService.IsOccupied(podium) then
		return false
	end

	-- Kayıt geri yüklenirken kapalı kata denk gelebilir; sessizce atla
	if not PlotService.IsPodiumUnlocked(podium) then
		return false
	end

	local model = UnitModel.Build(unitId, mutationId)
	model.Name = "Unit"
	model:PivotTo(podium.CFrame * CFrame.new(0, podium.Size.Y / 2, 0))

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	local label = UnitModel.BuildLabel(unitId, mutationId)
	label.Parent = model.PrimaryPart

	model.Parent = podium

	podium:SetAttribute("UnitId", unitId)
	podium:SetAttribute("MutationId", mutationId or "")
	podium:SetAttribute("PlacedAt", os.clock())

	syncProfile(podium)

	--[[
		Rozetler. Yerleştirme burada tek noktadan geçtiği için kontrol de
		burada: satın alma, çalma ve çark ödülü aynı yoldan geliyor.
	]]
	local plot = PlotService.GetPlotFromDescendant(podium)
	local owner = plot and ownerByPlot[plot]
	if owner then
		local def = Config.GetUnit(unitId)
		if def and def.rarity == "Secret" then
			BadgeService.Award(owner, "SecretFind")
		end

		local unlocked = PlotService.GetUnlockedPodiums(plot)
		local occupied = 0
		for _, other in unlocked do
			if PlotService.IsOccupied(other) then
				occupied += 1
			end
		end
		if occupied == #unlocked and #unlocked > 0 then
			BadgeService.Award(owner, "FullHouse")
		end
	end

	return true
end

--[[ Kaideyi boşaltır ve üstündeki karakterin kimliğini döner. ]]
function PlotService.ClearUnit(podium: Part): (string?, string?)
	if not PlotService.IsOccupied(podium) then
		return nil, nil
	end

	local unitId = podium:GetAttribute("UnitId") :: string
	local mutationId = podium:GetAttribute("MutationId") :: string

	local model = podium:FindFirstChild("Unit")
	if model then
		model:Destroy()
	end

	podium:SetAttribute("UnitId", "")
	podium:SetAttribute("MutationId", "")
	podium:SetAttribute("PlacedAt", 0)

	syncProfile(podium)
	return unitId, (if mutationId == "" then nil else mutationId)
end

-- ─── Sahiplik ───────────────────────────────────────────────────────────────

function PlotService.GetPlotOf(player: Player): Model?
	return plotByOwner[player]
end

function PlotService.GetOwner(plot: Model): Player?
	return ownerByPlot[plot]
end

--[[ Herhangi bir parçadan üstteki plot'u bulur. ]]
function PlotService.GetPlotFromDescendant(instance: Instance): Model?
	local current: Instance? = instance
	while current and current ~= plotsFolder do
		if current:IsA("Model") and current.Parent == plotsFolder then
			return current
		end
		current = current.Parent
	end
	return nil
end

function PlotService.GetAllPlots(): { Model }
	return plots
end

local function setSignText(plot: Model, text: string)
	local sign = plot:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("OwnerLabel")
	local label = gui and gui:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

--[[ Oyuncuyu kendi üssünün doğuş pedine taşır. Üssü yoksa hiçbir şey yapmaz. ]]
function PlotService.TeleportToPlot(player: Player)
	local plot = plotByOwner[player]
	if not plot then
		return
	end

	local pad = plot:FindFirstChild("SpawnPad")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (pad and pad:IsA("BasePart") and root and root:IsA("BasePart")) then
		return
	end

	character:PivotTo(pad.CFrame * CFrame.new(0, 4, 0))
end

--[[ Kayıtlı karakterleri oyuncunun kaidelerine geri koyar. ]]
local function restoreUnits(player: Player)
	local plot = plotByOwner[player]
	local profile = DataService.Get(player)
	if not (plot and profile) then
		return
	end

	-- PlaceUnit profile geri yazıyor; kopyayı gezmezsek listeyi altımızdan çeker
	local stored = table.clone(profile.units)
	local podiums = PlotService.GetPodiums(plot)

	for _, entry in stored do
		local podium = podiums[entry.slot]
		if podium and not PlotService.IsOccupied(podium) then
			PlotService.PlaceUnit(podium, entry.unitId, entry.mutationId)
		end
	end
end

local function grantPlot(player: Player, plot: Model)
	ownerByPlot[plot] = player
	plotByOwner[player] = plot
	setSignText(plot, string.upper(player.DisplayName))

	--[[
		İstemci kendi üssünü bundan buluyor.

		Eskiden tabeladaki yazıyı oyuncunun adıyla karşılaştırıyordu ve
		rebirth rozeti eklenince ("ATCIKM  [R1]") eşleşme bozuldu: rebirth
		atan herkeste üs paneli "no base" diyordu, kilit göstergesi ve
		taşıma oku da çalışmıyordu. Nitelik replike olduğu için remote
		gerekmiyor ve tabelanın yazısı serbest kalıyor.
	]]
	player:SetAttribute("Plot", plot.Name)

	PlotService.TeleportToPlot(player)

	-- Profil hâlâ yükleniyor olabilir
	task.spawn(function()
		local profile = DataService.WaitForProfile(player)
		if not profile then
			return
		end

		-- Katları karakterleri geri koymadan ÖNCE aç: kayıtlı karakter
		-- üst kattaysa kapalı kata konamaz ve sessizce kaybolurdu.
		PlotService.SetUnlockedFloors(plot, Config.GetUnlockedFloors(profile.floorsBought))
		PlotService.RefreshSign(plot)
		restoreUnits(player)
	end)
end

--[[
	Boş üs varsa verir, yoksa sıraya alır. Üssü olmayan oyuncu hiçbir şey
	yapamıyor — satın alamıyor, çalamıyor, kazanç üretemiyor. Eskiden bu
	durumda sadece sunucuya uyarı basılıyordu ve oyuncu ne olduğunu
	anlamadan boş bir ekrana bakıyordu.
]]
--[[ Tabelaya sahibin adını ve rebirth seviyesini yazar. ]]
function PlotService.RefreshSign(plot: Model)
	local owner = ownerByPlot[plot]
	if not owner then
		setSignText(plot, "EMPTY BASE")
		return
	end

	local profile = DataService.Get(owner)
	local rebirths = if profile then profile.rebirths else 0

	if rebirths > 0 then
		setSignText(plot, string.format("%s  [R%d]", string.upper(owner.DisplayName), rebirths))
	else
		setSignText(plot, string.upper(owner.DisplayName))
	end
end

local function assignPlot(player: Player)
	for _, plot in plots do
		if ownerByPlot[plot] == nil then
			grantPlot(player, plot)
			return
		end
	end

	if not table.find(waiting, player) then
		table.insert(waiting, player)
	end

	local position = table.find(waiting, player) or #waiting
	notify(player, string.format("All bases taken - you are #%d in line", position), true)
end

--[[ Boşalan üssü sıradaki oyuncuya verir. ]]
local function grantToNextInLine(plot: Model)
	while #waiting > 0 do
		local next = table.remove(waiting, 1)
		if next and next.Parent then
			grantPlot(next, plot)
			notify(next, "A base opened up - it is yours", false)
			return
		end
	end
end

local function releasePlot(player: Player)
	local plot = plotByOwner[player]
	if not plot then
		return
	end

	-- Kaideleri boşaltırken profile dokunma: kayıt henüz alınmamış olabilir
	releasing[player] = true

	for _, podium in PlotService.GetPodiums(plot) do
		PlotService.ClearUnit(podium)
	end

	releasing[player] = nil

	local items = plot:FindFirstChild("Items")
	if items then
		items:ClearAllChildren()
	end

	plot:SetAttribute("Locked", false)
	PlotService.SetUnlockedFloors(plot, 1)
	setSignText(plot, "EMPTY BASE")

	ownerByPlot[plot] = nil
	plotByOwner[player] = nil
	player:SetAttribute("Plot", nil)

	grantToNextInLine(plot)
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

function PlotService.Start()
	-- Tekrar çağrılabilir olmalı: eski dünya siliniyorsa ona ait durum da
	-- silinmeli. Aksi halde plots listesinde yok edilmiş modeller kalır ve
	-- oyuncular artık var olmayan üslere atanır.
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(plots)
	table.clear(ownerByPlot)
	table.clear(plotByOwner)
	table.clear(waiting)

	notifyRemote = Net.Get("Notify")

	local existing = workspace:FindFirstChild("Plots")
	if existing then
		existing:Destroy()
	end

	plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = workspace

	for index = 1, Config.PlotCount do
		table.insert(plots, buildPlot(index))
	end

	-- Üs ver + her doğuşta o üsse taşı
	local function onPlayerAdded(player: Player)
		assignPlot(player)

		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart")
			task.wait(0.1) -- karakter tam oturmadan ışınlarsak geri kayıyor
			PlotService.TeleportToPlot(player)
		end)

		if player.Character then
			PlotService.TeleportToPlot(player)
		end
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		local index = table.find(waiting, player)
		if index then
			table.remove(waiting, index)
		end
		releasePlot(player)
	end))
end

return PlotService
