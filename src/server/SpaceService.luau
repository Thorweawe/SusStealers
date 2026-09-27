--!strict
--[[
	Uzay soygunu: karakterlerin kaynağı (konveyörün yerine).

	Kafeteryanın karşısındaki kuzey duvarın ortası açık; kapının dışında
	Launch Bay güvertesi, ötesinde uzay. Güverteden çıkan oyuncu uçuyor
	(istemci, SpaceFX). Uzayda tek sırada, bir sağda bir solda altı gezegen;
	her birinin tepesinde bir canavar ve önünde kayıp mürettebatlar.

	  Çalma     — mürettebata basılı tut → sırtında; o gezegenin canavarı
	              kükreyip kovalıyor (hızı Config.SpaceMonsters[i].need)
	  Teslim    — güverteye ya da gemiye varınca karakter üssün boş kaidesine
	  Yakalanma — canavar oyuncuyu eliyle kavrıyor ve gemiye fırlatıyor
	              (istemci çiziyor, sunucu sonunda yerini garantiliyor);
	              karakter gezegendeki yerine dönüyor

	Canavarlar sunucuda yalnızca görünmez bir kök parça: konum, yön ve
	durum ("idle" | "wake" | "chase" | "grab" | "throw" | "return")
	nitelikle gidiyor, modeli ve animasyonu istemci kuruyor (MonsterModel).
	Ağda canavar başına tek parça.

	Uzay hızı oyuncunun "SpaceSpeed" niteliğinde (CapsuleService yazıyor).

	Oyuncu nitelikleri:
	  InSpace       — uçuş bölgesinde (sunucu konumdan hesaplıyor)
	  SpaceCarry    — canavardan çalınan karakteri taşıyor
	  SpaceGrabbed  — canavarın elinde (id), fırlatılana kadar
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SpaceField = require(Shared.SpaceField)
local UnitModel = require(Shared.UnitModel)

local AnnounceService = require(script.Parent.AnnounceService)
local BadgeService = require(script.Parent.BadgeService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MonetizationService = require(script.Parent.MonetizationService)
local PlotService = require(script.Parent.PlotService)
local PromptGuard = require(script.Parent.PromptGuard)
local UpgradeService = require(script.Parent.UpgradeService)
local MovementService = require(script.Parent.MovementService)

local SpaceService = {}

SpaceService.NotifyKind = "steal"

type Spot = {
	planet: number,
	index: number,
	position: Vector3,   -- ayak hizası
	unitId: string?,
	mutationId: string?,
	model: Model?,
	emptySince: number?,
	held: boolean,       -- biri taşıyor: yenisi gelmesin, düşerse aynısı dönsün
	anchor: BasePart?,   -- görünmez yer işareti: istemci boşken geri sayımı buna yazıyor
}

type Monster = {
	def: Config.SpaceMonsterDef,
	planet: number,
	root: BasePart,
	home: CFrame,
	position: Vector3,
	facing: Vector3,
	state: string,
	stateAt: number,
	chaseAt: number,
	target: Player?,
	lungeUntil: number,     -- ani atak bu ana kadar sürüyor
	nextLunge: number,      -- bir sonraki atak en erken
	stunUntil: number,      -- sersemletildi (kalkan iksiri): bu ana kadar yerinde
}

type Carry = {
	unitId: string,
	mutationId: string?,
	planet: number,
	spot: number,
	model: Model,
	grabbedAt: number,
	from: Vector3,
}

local rng = Random.new()
local notifyRemote: RemoteEvent? = nil
local fxRemote: RemoteEvent? = nil

local spots: { { Spot } } = {}
local monsters: { Monster } = {}
local carrying: { [Player]: Carry } = {}
local immuneUntil: { [Player]: number } = {}
local grabbedBy: { [Player]: Monster } = {}
-- Canavar kalkanı yeniden ne zaman hazır (os.clock)
local shieldReadyAt: { [Player]: number } = {}
-- Lucky Scanner zarı (mürettebat balonlarının zarından ayrı)
local luckRng = Random.new()

-- Aşağıda tanımlı; daha önceki fonksiyonlar (catch) da kullanıyor
local keepOffPlanets: (p: Vector3) -> (Vector3, boolean)

--[[ Stealth Suit: hedef oyuncunun canavar uyanma süresi çarpanı (hedef yoksa 1). ]]
local function stealthOf(player: Player?): number
	if not player then
		return 1
	end
	local wakeMul = Config.GetStealth(UpgradeService.GetLevel(player, "StealthSuit"))
	return wakeMul
end
-- Testler döngüyü durduruyor (canavar test oyuncusunu yakalamasın)
local paused = false
-- Bir sonraki ortak mürettebat rotasyonu (sunucu saati)
local rotateAt = math.huge

--[[
	Olayların uzaya etkisi (EventService):
	  wakeMul   — kükreme süresi çarpanı (Lights Sabotage: canavar geç fark ediyor)
	  chaseMul  — kovalama hızı çarpanı (Lights Sabotage: yarı kör, yavaş)
	  mutated   — Mutation Storm: gezegenlerdeki her mürettebat mutasyonlu
]]
local eventMods = { wakeMul = 1, chaseMul = 1, mutated = false }

-- Gemi çıkışı nadir karakterleri herkese duyurulsun (eski konveyör kuralı)
local ANNOUNCE_RARITIES = { Mythic = true, Secret = true }

local function notify(player: Player, text: string, isError: boolean, kind: string?)
	if notifyRemote and player.Parent then
		notifyRemote:FireClient(player, text, isError, kind or SpaceService.NotifyKind)
	end
end

local function fx(player: Player, ...: any)
	if fxRemote and player.Parent then
		fxRemote:FireClient(player, ...)
	end
end

local function fxAll(...: any)
	if fxRemote then
		fxRemote:FireAllClients(...)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

--[[ Uçuş hızı: kapsül hızı + pet bonusu (istemcideki SpaceFX ile aynı hesap). ]]
local function speedOf(player: Player): number
	local v = player:GetAttribute("SpaceSpeed")
	local pet = player:GetAttribute("PetSpeedBonus")
	return Config.GetFlightSpeed(if typeof(v) == "number" then v else Config.Space.BaseSpeed,
		if typeof(pet) == "number" then pet else 0)
end

-- ─── Yapı yardımcıları ──────────────────────────────────────────────────────

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

--[[ Ekseni `normal` olan disk/silindir. ]]
local function cyl(parent: Instance, name: string, center: Vector3, normal: Vector3, length: number, diameter: number, color: Color3, props: { [string]: any }?): BasePart
	local n = normal.Unit
	local up = if math.abs(n.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local cf = CFrame.lookAt(center, center + n, up) * CFrame.Angles(0, math.rad(90), 0)
	local p = part(parent, name, Vector3.new(length, diameter, diameter), cf, color, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

--[[ Basık kubbe: ekseni `normal`, kalınlığı `thick`, çapı `diameter` (küre mesh'li). ]]
local function ellipsoid(parent: Instance, name: string, center: Vector3, normal: Vector3, thick: number, diameter: number, color: Color3): BasePart
	local n = normal.Unit
	local up = if math.abs(n.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	local cf = CFrame.lookAt(center, center + n, up) * CFrame.Angles(0, math.rad(90), 0)
	local p = part(parent, name, Vector3.new(thick, diameter, diameter), cf, color, { CanCollide = false, CanQuery = false, CastShadow = false })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

--[[ Kalın yazılı tabela (FredokaOne + kontur). ]]
local function sign(parent: BasePart, face: Enum.NormalId, lines: { { text: string, color: Color3, size: number } }, pixelsPerStud: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud or 40
	gui.LightInfluence = 0
	gui.Parent = parent
	local list = Instance.new("UIListLayout")
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = gui
	for i, line in lines do
		local t = Instance.new("TextLabel")
		t.LayoutOrder = i
		t.Size = UDim2.new(1, 0, 0, line.size * 1.25)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.FredokaOne
		t.TextSize = line.size
		t.TextColor3 = line.color
		t.Text = line.text
		t.TextWrapped = true
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(16, 18, 34)
		s.Thickness = math.max(2, line.size / 10)
		s.Parent = t
		t.Parent = gui
	end
end

local METAL = Color3.fromRGB(176, 186, 200)
local METAL_DARK = Color3.fromRGB(70, 78, 94)
local HULL = Color3.fromRGB(128, 138, 152)
local HAZARD = Color3.fromRGB(255, 200, 40)
local CYAN = Color3.fromRGB(90, 210, 255)
local WHITE = Color3.new(1, 1, 1)

-- ─── Launch Bay (güverte) ───────────────────────────────────────────────────

local function buildDeck(zone: Model)
	local s = Config.Space
	local deck = Instance.new("Folder")
	deck.Name = "LaunchBay"
	deck.Parent = zone
	local z1 = SpaceField.WallOuterZ()
	local z0 = SpaceField.DeckEdgeZ()
	local cz = (z0 + z1) / 2
	local W = s.DeckHalfWidth * 2
	local D = z1 - z0
	local top = s.DeckTop
	local X = s.GateX

	-- Zemin: iki kademe (üstte açık gri güverte, altta gövde rengi karın)
	part(deck, "Deck", Vector3.new(W, 1, D), CFrame.new(X, top - 0.5, cz), METAL, { Material = Enum.Material.DiamondPlate })
	part(deck, "DeckBelly", Vector3.new(W - 6, 7, D - 4), CFrame.new(X, top - 4.5, cz + 1), HULL)
	part(deck, "DeckKeel", Vector3.new(W - 30, 4, D - 20), CFrame.new(X, top - 9, cz + 4), METAL_DARK)
	-- Karo çizgileri
	for k = 1, 7 do
		local x = X - W / 2 + k * (W / 8)
		part(deck, "Seam", Vector3.new(0.2, 0.06, D - 2), CFrame.new(x, top + 0.03, cz), METAL_DARK, { CanCollide = false })
	end
	-- Dış kenar: sarı-siyah şerit + parlak çizgi
	for k = 0, 15 do
		local x = X - W / 2 + (k + 0.5) * (W / 16)
		part(deck, "Hazard", Vector3.new(W / 16, 0.08, 3), CFrame.new(x, top + 0.04, z0 + 1.6), if k % 2 == 0 then HAZARD else Color3.fromRGB(30, 30, 36), { CanCollide = false })
	end
	part(deck, "EdgeGlow", Vector3.new(W, 0.3, 0.4), CFrame.new(X, top + 0.15, z0 + 0.2), CYAN, { Material = Enum.Material.Neon, CanCollide = false })
	-- Kalkış pedi: ortada parlak halka ve dışarı bakan oklar
	cyl(deck, "LaunchPad", Vector3.new(X, top + 0.05, cz - 4), Vector3.yAxis, 0.1, 22, Color3.fromRGB(40, 60, 90), { CanCollide = false })
	cyl(deck, "LaunchRing", Vector3.new(X, top + 0.08, cz - 4), Vector3.yAxis, 0.1, 20, CYAN, { Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false })
	cyl(deck, "LaunchCore", Vector3.new(X, top + 0.11, cz - 4), Vector3.yAxis, 0.1, 17, Color3.fromRGB(40, 60, 90), { CanCollide = false })
	for k = 0, 2 do
		local az = cz - 18 - k * 6
		local arrow = Instance.new("WedgePart")
		arrow.Name = "Arrow"
		arrow.Size = Vector3.new(6, 0.12, 3)
		arrow.CFrame = CFrame.new(X, top + 0.08, az) * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.Angles(0, 0, 0)
		arrow.Anchored = true
		arrow.CanCollide = false
		arrow.Material = Enum.Material.Neon
		arrow.Color = HAZARD
		arrow.Transparency = 0.1 + k * 0.2
		arrow.Parent = deck
		arrow:SetAttribute("PulsePeriod", 1.2)
	end

	-- Yan duvarlar: alçak metal korkuluk + cam
	for _, side in { -1, 1 } do
		local x = X + side * (W / 2 - 0.6)
		part(deck, "SideWall", Vector3.new(1.2, 5, D), CFrame.new(x, top + 2.5, cz), HULL)
		part(deck, "SideCap", Vector3.new(1.6, 0.5, D), CFrame.new(x, top + 5.2, cz), METAL)
		part(deck, "SideGlass", Vector3.new(0.3, 10, D - 2), CFrame.new(x, top + 10.4, cz), Color3.fromRGB(150, 220, 255),
			{ Material = Enum.Material.Glass, Transparency = 0.7, CastShadow = false })
		for z = z0 + 4, z1 - 4, 12 do
			part(deck, "Post", Vector3.new(1, 11, 1), CFrame.new(x, top + 10.7, z), METAL_DARK)
			local lamp = part(deck, "Lamp", Vector3.new(1.3, 1.3, 1.3), CFrame.new(x, top + 16.4, z), Color3.fromRGB(255, 90, 80),
				{ Material = Enum.Material.Neon, Shape = Enum.PartType.Ball })
			lamp:SetAttribute("PulsePeriod", 1.8)
		end
	end

	-- Dış kemer: iki ayak + üst kiriş, arasında kuvvet alanı perdesi
	local archH = 30
	for _, side in { -1, 1 } do
		local x = X + side * (W / 2 - 2)
		part(deck, "ArchLeg", Vector3.new(4, archH, 4), CFrame.new(x, top + archH / 2, z0 + 2), METAL)
		part(deck, "ArchStripe", Vector3.new(4.2, 2, 4.2), CFrame.new(x, top + 8, z0 + 2), HAZARD)
		part(deck, "ArchStripe", Vector3.new(4.2, 2, 4.2), CFrame.new(x, top + 20, z0 + 2), HAZARD)
	end
	local beam = part(deck, "ArchBeam", Vector3.new(W, 5, 4), CFrame.new(X, top + archH + 2.5, z0 + 2), METAL)
	part(deck, "ArchGlow", Vector3.new(W - 6, 0.5, 0.5), CFrame.new(X, top + archH - 0.3, z0 + 0.4), CYAN, { Material = Enum.Material.Neon, CanCollide = false })
	local field = part(deck, "ForceField", Vector3.new(W - 8, archH, 0.3), CFrame.new(X, top + archH / 2, z0 + 2), Color3.fromRGB(110, 200, 255),
		{ Material = Enum.Material.ForceField, Transparency = 0.55, CanCollide = false, CanQuery = false, CastShadow = false })
	local _ = field
	-- Tabela: içeriden LAUNCH BAY, dışarıdan SAFE ZONE
	-- Yazı tabelaya sığıyor: eskiden 6 px/stud'da 120 punto "LAUN" diye kesiliyordu
	local board = part(deck, "ArchSign", Vector3.new(40, 4.6, 0.4), CFrame.new(X, top + archH + 2.5, z0 + 4.25), Color3.fromRGB(20, 26, 46))
	sign(board, Enum.NormalId.Back, { { text = "LAUNCH BAY", color = Color3.fromRGB(130, 225, 255), size = 72 } }, 20)
	local outBoard = part(deck, "SafeSign", Vector3.new(40, 4.6, 0.4), CFrame.new(X, top + archH + 2.5, z0 - 0.25), Color3.fromRGB(20, 46, 30))
	sign(outBoard, Enum.NormalId.Front, { { text = "SAFE ZONE", color = Color3.fromRGB(120, 255, 140), size = 72 } }, 20)
	local beamLight = Instance.new("SurfaceLight")
	beamLight.Face = Enum.NormalId.Bottom
	beamLight.Range = 32
	beamLight.Brightness = 1.4
	beamLight.Color = Color3.fromRGB(200, 230, 255)
	beamLight.Parent = beam

	-- Bilgi panosu: kapının yanında, içeri bakıyor
	local info = part(deck, "InfoBoard", Vector3.new(0.4, 12, 22), CFrame.new(X - W / 2 + 1.6, top + 9, z1 - 16), Color3.fromRGB(20, 26, 46))
	sign(info, Enum.NormalId.Right, {
		{ text = "SPACE HEIST", color = Color3.fromRGB(130, 225, 255), size = 64 },
		{ text = "1. Fly to a planet", color = WHITE, size = 34 },
		{ text = "2. Hold on a crewmate to steal it", color = WHITE, size = 34 },
		{ text = "3. Fly back here before the monster catches you!", color = Color3.fromRGB(255, 140, 170), size = 34 },
		{ text = "Buy a jetpack here to fly out faster!", color = Color3.fromRGB(255, 220, 110), size = 30 },
	}, 18)
end

-- ─── Gezegenler ─────────────────────────────────────────────────────────────

local function surfacePoint(center: Vector3, radius: number, dir: Vector3): Vector3
	return center + dir.Unit * radius
end

local function buildPlanet(folder: Instance, index: number, def: Config.SpaceMonsterDef)
	local model = Instance.new("Model")
	model.Name = "Planet" .. index
	model:SetAttribute("MonsterId", def.id)
	model.Parent = folder
	local detail = Random.new(index * 97)
	local center = SpaceField.PlanetCenter(def)
	local r = def.radius
	local plateauR = SpaceField.PlateauRadius(def)

	local sphere = part(model, "Planet", Vector3.one * r * 2, CFrame.new(center), def.planetColor, { Shape = Enum.PartType.Ball })
	-- Plato: kürenin üstünde düz tepeli bir mesa (kenarı küreye gömülü), üstünde parlak halka
	local depth = SpaceField.PlateauDepth(def)
	cyl(model, "Plateau", def.position - Vector3.new(0, depth / 2, 0), Vector3.yAxis, depth, plateauR * 2 + 1.5, def.planetColor2)
	cyl(model, "PlateauRim", def.position - Vector3.new(0, 0.4, 0), Vector3.yAxis, 0.6, plateauR * 2 + 2.2, def.glow,
		{ Material = Enum.Material.Neon, CanCollide = false })
	-- (PlateauTop kalktı: üst yüzü platoyla aynı düzlemdeydi, tepe titriyordu)

	-- Kraterler ve lekeler (üst yarıküre, platonun dışında)
	for k = 1, 22 do
		local a = detail:NextNumber(0, math.pi * 2)
		local y = detail:NextNumber(-0.85, 0.72)
		local flat = math.sqrt(1 - y * y)
		local dir = Vector3.new(math.cos(a) * flat, y, math.sin(a) * flat)
		local size = detail:NextNumber(0.12, 0.3) * r
		--[[
			2026-09-28: kraterler düz diskti; diskin yüzü kürenin çokgen
			yüzeyiyle aynı düzlemde kalıp titriyordu (gezegenlerde "pervane"
			gibi dilimli lekeler). Artık yüzeyden belirgin taşan basık kubbe
			(küre mesh'li elipsoit): yüzeyi eğik kesiyor, çakışma yok.
		]]
		local thick = size * 0.22
		if k % 3 == 0 then
			ellipsoid(model, "CraterRim", surfacePoint(center, r - thick * 0.15, dir), dir, thick * 0.9, size * 1.25,
				def.planetColor:Lerp(WHITE, 0.15))
		end
		ellipsoid(model, "Crater", surfacePoint(center, r - thick * 0.05, dir), dir, thick, size, def.planetColor2)
	end
	-- Parlayan kristaller platonun kenarında
	for k = 1, 10 do
		local a = (k / 10) * math.pi * 2 + detail:NextNumber(-0.2, 0.2)
		local rr = plateauR - detail:NextNumber(0.5, 2.5)
		local h = detail:NextNumber(3, 7) * (0.8 + def.scale * 0.2)
		local base = Vector3.new(def.position.X + math.cos(a) * rr, def.position.Y - 0.5, def.position.Z + math.sin(a) * rr)
		local crystal = part(model, "Crystal", Vector3.new(1.6, h, 1.6), CFrame.new(base + Vector3.new(0, h / 2, 0))
			* CFrame.Angles(detail:NextNumber(-0.35, 0.35), a, detail:NextNumber(-0.35, 0.35)), def.glow,
			{ Material = Enum.Material.Neon, Transparency = 0.15, CanCollide = false, CastShadow = false })
		if k % 4 == 0 then
			local l = Instance.new("PointLight")
			l.Color = def.glow
			l.Range = 20
			l.Brightness = 1.2
			l.Parent = crystal
		end
	end
	-- Halkalı gezegenler (2 ve 6): eğik neon halka
	if index == 2 or index == 6 then
		local tilt = CFrame.new(center) * CFrame.Angles(math.rad(12), 0, math.rad(if index == 2 then 18 else -14))
		local segments = 40
		local ringR = r * 1.55
		for k = 1, segments do
			local a0 = (k - 1) / segments * math.pi * 2
			local a1 = k / segments * math.pi * 2
			local p0 = (tilt * CFrame.new(math.cos(a0) * ringR, 0, math.sin(a0) * ringR)).Position
			local p1 = (tilt * CFrame.new(math.cos(a1) * ringR, 0, math.sin(a1) * ringR)).Position
			local mid = (p0 + p1) / 2
			part(model, "Ring", Vector3.new((p1 - p0).Magnitude + 0.4, 0.4, r * 0.28), CFrame.lookAt(mid, p1, tilt.UpVector) * CFrame.Angles(0, math.rad(90), 0),
				def.glow, { Material = Enum.Material.Neon, Transparency = 0.45, CanCollide = false, CanQuery = false, CastShadow = false })
		end
	end
	-- Atmosfer parıltısı: biraz büyük yarı saydam küre
	-- Parıltı küresi biraz aşağıda: tepesi platonun üstüne taşmasın
	part(model, "Atmosphere", Vector3.one * r * 2.12, CFrame.new(center - Vector3.new(0, r * 0.08, 0)), def.glow,
		{ Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField, Transparency = 0.6, CanCollide = false, CanQuery = false, CastShadow = false })

	model.PrimaryPart = sphere :: BasePart
	return model
end

-- ─── Mürettebat yerleri ─────────────────────────────────────────────────────

local onGrab: (player: Player, spot: Spot) -> ()

local function clearSpot(spot: Spot)
	spot.unitId = nil
	spot.mutationId = nil
	if spot.model then
		spot.model:Destroy()
		spot.model = nil
	end
end

local function placeSpot(spot: Spot, unitId: string, mutationId: string?, folder: Instance)
	clearSpot(spot)
	local def = Config.SpaceMonsters[spot.planet]
	local facing = SpaceField.Facing(def)
	local model = UnitModel.Build(unitId, mutationId)
	model.Name = "LostCrew"
	model:PivotTo(CFrame.lookAt(spot.position, spot.position + facing))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	local label = UnitModel.BuildLabel(unitId, mutationId)
	label.Parent = model.PrimaryPart
	local unit = Config.GetUnit(unitId)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HeistPrompt"
	prompt.ActionText = "Steal"
	prompt.ObjectText = if unit then unit.name else unitId
	prompt.HoldDuration = Config.Space.GrabHold
	prompt.MaxActivationDistance = Config.Space.GrabDistance
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	PromptGuard.Connect(prompt, function(player)
		onGrab(player, spot)
	end, function(player)
		-- Fast Steal / Fast Hands ve Quick Hands kısaltıyor (istemci PromptFilter'da aynı hesap)
		return Config.GetPersonalGrabHold(Config.Space.GrabHold,
			MonetizationService.GetStealHoldMultiplier(player), UpgradeService.GetLevel(player, "QuickHands"))
	end)
	model:SetAttribute("Planet", spot.planet)
	model:SetAttribute("Spot", spot.index)
	-- İstemcinin nadirlik aurası (CrewAura) için
	model:SetAttribute("UnitId", unitId)
	model:SetAttribute("MutationId", mutationId)
	model.Parent = folder
	spot.model = model
	spot.unitId = unitId
	spot.mutationId = mutationId
	spot.emptySince = nil
	if spot.anchor then
		spot.anchor:SetAttribute("RespawnAt", nil)
	end
end

local crewFolder: Folder? = nil

local function rollSpot(spot: Spot)
	local def = Config.SpaceMonsters[spot.planet]
	local unit = Config.RollSpaceUnit(rng, def)
	local mutation = Config.RollMutation(rng)
	if eventMods.mutated then
		while not mutation do
			mutation = Config.RollMutation(rng)
		end
	end
	placeSpot(spot, unit.id, if mutation then mutation.id else nil, crewFolder :: Folder)
end

-- ─── Taşıma ─────────────────────────────────────────────────────────────────

local function attachToBack(player: Player, unitId: string, mutationId: string?): Model?
	local character = player.Character
	local root = rootOf(player)
	if not (character and root) then
		return nil
	end
	local model = UnitModel.Build(unitId, mutationId)
	-- "CarriedUnit" DEĞİL: o adı gemideki çalma sistemi (alarm, iz, rehber) izliyor
	model.Name = "SpaceCarry"
	model:PivotTo(root.CFrame * CFrame.new(0, 2.2, 1.6) * CFrame.Angles(0, math.rad(180), 0))
	local primary = model.PrimaryPart :: BasePart
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.Massless = true
			if d ~= primary then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = d
				weld.Parent = d
			end
		end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = primary
	weld.Parent = primary
	model.Parent = character
	return model
end

--[[ Taşınanı bırakır: karakter gezegendeki yerine döner. ]]
local function drop(player: Player)
	local carry = carrying[player]
	if not carry then
		return
	end
	carrying[player] = nil
	if carry.model.Parent then
		carry.model:Destroy()
	end
	player:SetAttribute("SpaceCarry", nil)
	MovementService.RefreshSpeed(player)
	local spot = spots[carry.planet] and spots[carry.planet][carry.spot]
	if spot then
		spot.held = false
		if not spot.unitId and crewFolder then
			placeSpot(spot, carry.unitId, carry.mutationId, crewFolder)
		end
	end
end

local function unitName(unitId: string, mutationId: string?): string
	local def = Config.GetUnit(unitId)
	local mutation = Config.GetMutation(mutationId)
	local name = if def then def.name else unitId
	return if mutation then mutation.name .. " " .. name else name
end

function onGrab(player: Player, spot: Spot)
	if not spot.unitId or spot.held then
		return
	end
	if carrying[player] then
		notify(player, "You're already carrying one - fly back to the Launch Bay!", true)
		return
	end
	if grabbedBy[player] or os.clock() < (immuneUntil[player] or 0) then
		return
	end
	local plot = PlotService.GetPlotOf(player)
	if not plot then
		notify(player, "You need a base first", true)
		return
	end
	if not PlotService.FindEmptyPodium(plot) then
		notify(player, "No free podium - sell or rebirth to make room", true)
		return
	end
	local unitId, mutationId = spot.unitId :: string, spot.mutationId
	--[[
		Lucky Scanner: mutasyonsuz mürettebat şansla mutasyonlu çıkıyor.
		Hangi mutasyon olacağı mutasyonların kendi nadirliğiyle (chance).
	]]
	local lucky = false
	if not mutationId and luckRng:NextNumber() < Config.GetLuckyChance(UpgradeService.GetLevel(player, "LuckyScanner")) then
		local total = 0
		for _, m in Config.Mutations do
			total += m.chance
		end
		local roll = luckRng:NextNumber() * total
		for _, m in Config.Mutations do
			roll -= m.chance
			if roll <= 0 then
				mutationId = m.id
				lucky = true
				break
			end
		end
	end
	local model = attachToBack(player, unitId, mutationId)
	if not model then
		return
	end
	clearSpot(spot)
	spot.held = true
	carrying[player] = {
		unitId = unitId,
		mutationId = mutationId,
		planet = spot.planet,
		spot = spot.index,
		model = model,
		grabbedAt = os.clock(),
		from = spot.position,
	}
	player:SetAttribute("SpaceCarry", true)
	MovementService.RefreshSpeed(player)
	DataService.Discover(player, unitId)

	local monster = monsters[spot.planet]
	if lucky then
		notify(player, string.format("LUCKY SCANNER! It's a %s!", unitName(unitId, mutationId)), false, "spin")
	end
	notify(player, string.format("Stole %s! Fly back to the Launch Bay!", unitName(unitId, mutationId)), false, "steal")
	if monster then
		if monster.state == "idle" or monster.state == "return" then
			monster.state = "wake"
			monster.stateAt = os.clock()
			monster.target = player
		end
		fxAll("roar", monster.def.id, player.UserId)
	end
end

--[[
	Kaideye koyar. Nadirse duyurur. Teslim ve bedava karakter (çark,
	Robux ürünü) aynı yoldan geçiyor.
]]
local function placeOnPodium(player: Player, unitId: string, mutationId: string?, origin: string): boolean
	local plot = PlotService.GetPlotOf(player)
	local podium = plot and PlotService.FindEmptyPodium(plot)
	if not podium then
		return false
	end
	if not PlotService.PlaceUnit(podium, unitId, mutationId) then
		return false
	end
	DataService.Discover(player, unitId)
	local def = Config.GetUnit(unitId)
	if def and def.rarity == "Secret" then
		BadgeService.Award(player, "SecretFind")
	end
	if def and ANNOUNCE_RARITIES[def.rarity] then
		local rarity = Config.Rarities[def.rarity]
		AnnounceService.Summon(string.format("%s %s %s!", player.DisplayName, origin,
			AnnounceService.Paint(unitName(unitId, mutationId), rarity.color)))
	end
	return true
end

local function deliver(player: Player, root: BasePart)
	local carry = carrying[player]
	if not carry then
		return
	end
	--[[
		Hile payı: bu yolu oyuncunun uzay hızıyla (toleranslı) en az şu kadar
		sürede gelmiş olmalı. Hız hilesiyle ışınlanan karakterini geri verir.
	]]
	local distance = (carry.from - root.Position).Magnitude
	local jet = Config.GetJetBoost(UpgradeService.GetLevel(player, "JetBoost"))
	-- Jet Boost payda; halkalar 2026-09-28'de kalktı ama çarpanı ek pay olarak duruyor.
	-- Jetpack bonusu taşırken yok (Config.GetJetpackBoost), payda gerekmiyor.
	local boost = (if jet then jet.mul else 1) * Config.SpaceBonus.RingBoostMul
	local minTime = distance / (speedOf(player) * Config.Space.DeliverSpeedTolerance * boost) - 1
	if os.clock() - carry.grabbedAt < minTime then
		drop(player)
		notify(player, "Too fast! The crewmate slipped back to its planet", true)
		return
	end

	carrying[player] = nil
	if carry.model.Parent then
		carry.model:Destroy()
	end
	player:SetAttribute("SpaceCarry", nil)
	MovementService.RefreshSpeed(player)
	local spot = spots[carry.planet] and spots[carry.planet][carry.spot]
	if spot then
		spot.held = false
		spot.emptySince = os.clock()
		if spot.anchor then
			spot.anchor:SetAttribute("RespawnAt", workspace:GetServerTimeNow() + Config.Space.CrewRespawn)
		end
	end

	if not placeOnPodium(player, carry.unitId, carry.mutationId, "stole") then
		-- Bu arada kaide dolduysa karakter kaybolmasın: yerine dönsün
		if spot and not spot.unitId and crewFolder then
			placeSpot(spot, carry.unitId, carry.mutationId, crewFolder)
		end
		notify(player, "No free podium! The crewmate floated back to its planet", true)
		return
	end
	DataService.Bump(player, "salvaged")
	-- Skor tablosundaki "Stolen" ve MOST STOLEN panosu (eskiden oyuncudan çalma sayıyordu)
	EconomyService.AddStealCount(player)
	if carry.mutationId then
		DataService.Bump(player, "mutatedSteals")
	end
	if carry.planet == #Config.SpaceMonsters then
		DataService.Bump(player, "bossSteals")
	end
	local best = DataService.Get(player)
	if best and carry.planet > best.bestPlanet then
		best.bestPlanet = carry.planet
	end
	BadgeService.Award(player, "FirstSteal")
	local profile = DataService.Get(player)
	if profile and profile.salvaged >= 100 then
		BadgeService.Award(player, "StreakMaster")
	end
	local name = unitName(carry.unitId, carry.mutationId)
	notify(player, string.format("%s is on your podium!", name), false, "deposit")
	fx(player, "delivered", name)
end

-- ─── Yakalama ve fırlatma ───────────────────────────────────────────────────

local function landing(): CFrame
	local p = Config.Space.Landing
	return CFrame.lookAt(p, p + Vector3.new(0, 0, 1))
end

local function catch(monster: Monster, player: Player)
	--[[
		Canavar kalkanı (Strong Lock pass'i / Reinforced Lock iksiri): hazırsa
		oyuncu kurtuluyor — canavar sersemleyip geri itiliyor, karakter
		sırtta kalıyor. Sonra ShieldCooldown sn yeniden dolmuyor.
	]]
	local now0 = os.clock()
	if MonetizationService.HasShield(player) and now0 >= (shieldReadyAt[player] or 0) then
		shieldReadyAt[player] = now0 + Config.ShieldCooldown
		player:SetAttribute("ShieldReadyAt", workspace:GetServerTimeNow() + Config.ShieldCooldown)
		monster.stunUntil = now0 + Config.ShieldStun
		local root = rootOf(player)
		if root then
			local away = monster.position - root.Position
			away = Vector3.new(away.X, 0, away.Z)
			if away.Magnitude > 0.1 then
				monster.position = (keepOffPlanets(monster.position + away.Unit * Config.ShieldKnock))
			end
		end
		fx(player, "shield", monster.def.id)
		notify(player, "MONSTER SHIELD! You broke free - fly!", false, "catch")
		return
	end
	local carry = carrying[player]
	local name = if carry then unitName(carry.unitId, carry.mutationId) else "it"
	drop(player)
	local s = Config.Space
	local now = os.clock()
	grabbedBy[player] = monster
	DataService.Bump(player, "thrown")
	BadgeService.Award(player, "Victim")
	immuneUntil[player] = now + s.GrabTime + s.ThrowTime + s.ThrowImmunity
	player:SetAttribute("SpaceGrabbed", monster.def.id)
	monster.state = "grab"
	monster.stateAt = now
	monster.target = player
	fx(player, "grab", monster.def.id, s.GrabTime, s.ThrowTime)
	notify(player, string.format("%s caught you! %s went back to its planet", monster.def.name, name), true)

	-- Sunucu yedeği: istemci fırlatmayı çizemezse yine de gemiye insin
	task.delay(s.GrabTime + s.ThrowTime + 0.8, function()
		if grabbedBy[player] ~= monster then
			return
		end
		grabbedBy[player] = nil
		player:SetAttribute("SpaceGrabbed", nil)
		local root = rootOf(player)
		if root and not SpaceField.InSafe(root.Position) and player.Character then
			player.Character:PivotTo(landing())
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end)
end

-- ─── Canavarlar ─────────────────────────────────────────────────────────────

local function buildMonsterRoot(folder: Instance, index: number, def: Config.SpaceMonsterDef): Monster
	local home = SpaceField.MonsterHome(def)
	local holder = Instance.new("Model")
	holder.Name = "Monster" .. index
	local root = part(holder, "Root", Vector3.new(2, 2, 2), home, def.glow,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	holder.PrimaryPart = root
	holder:SetAttribute("MonsterId", def.id)
	holder:SetAttribute("Planet", index)
	holder:SetAttribute("State", "idle")
	holder:SetAttribute("Target", 0)
	holder.Parent = folder
	return {
		def = def,
		planet = index,
		root = root,
		home = home,
		position = home.Position,
		facing = home.LookVector,
		state = "idle",
		stateAt = 0,
		chaseAt = 0,
		target = nil,
		lungeUntil = 0,
		nextLunge = 0,
		stunUntil = 0,
	}
end

local function setState(m: Monster, state: string)
	if m.state ~= state then
		m.state = state
		m.stateAt = os.clock()
	end
end

-- Canavarın gövde merkezi kökten bu kadar yukarıda (yakalama mesafesi buradan)
local function bodyHeight(def: Config.SpaceMonsterDef): number
	return 7 * def.scale
end

local function nearestCarrier(m: Monster): (Player?, BasePart?)
	local best: Player? = nil
	local bestRoot: BasePart? = nil
	local bestD = math.huge
	for player, carry in carrying do
		if carry.planet == m.planet then
			local root = rootOf(player)
			if root then
				local d = (root.Position - m.position).Magnitude
				if d < bestD then
					best, bestRoot, bestD = player, root, d
				end
			end
		end
	end
	return best, bestRoot
end

--[[ Canavar güvenli bölgeye giremiyor: güvertenin önünde duruyor. ]]
local function clampOutside(m: Monster, p: Vector3): Vector3
	local margin = 6 + m.def.scale * 6
	local limitZ = SpaceField.WallOuterZ() - margin
	local lo, hi = SpaceField.DeckBox()
	if p.X > lo.X - margin and p.X < hi.X + margin and p.Y < hi.Y + margin then
		limitZ = lo.Z - margin
	end
	if p.Z > limitZ then
		p = Vector3.new(p.X, p.Y, limitZ)
	end
	return p
end

--[[
	Canavar gezegenlerin İÇİNE girmiyor. ESKİ HATA: kovalama hedefi
	oyuncunun gövde yüksekliği kadar altıydı; plato hizasında kaçan
	oyuncunun peşinden canavar platoya / küreye gömülüyor, "çıkmaya
	çalışırken" takılıp geç çıkıyordu. Plato (mesa) içindeyse tepesine,
	kürenin içindeyse yüzeyine itiliyor. İtildiyse true.
]]
function keepOffPlanets(p: Vector3): (Vector3, boolean)
	local pushed = false
	for _, def in Config.SpaceMonsters do
		local top = def.position.Y
		local flat = Vector3.new(p.X - def.position.X, 0, p.Z - def.position.Z)
		if flat.Magnitude < SpaceField.PlateauRadius(def) + 1.5 and p.Y < top and p.Y > top - SpaceField.PlateauDepth(def) - 2 then
			p = Vector3.new(p.X, top, p.Z)
			pushed = true
		end
		local center = SpaceField.PlanetCenter(def)
		local off = p - center
		-- Plato tepesi merkezden radius + 0.3 uzakta: ev noktası itilmesin
		local minR = def.radius + 0.25
		if off.Magnitude < minR then
			p = center + (if off.Magnitude > 0.01 then off.Unit else Vector3.yAxis) * minR
			pushed = true
		end
	end
	return p, pushed
end

--[[ Gezegenin kenarından dışarı (yatay): itilip yerinde sayan canavar buradan kayıyor. ]]
local function outwardFrom(p: Vector3): Vector3
	local best: Config.SpaceMonsterDef? = nil
	local bestD = math.huge
	for _, def in Config.SpaceMonsters do
		local d = (p - SpaceField.PlanetCenter(def)).Magnitude - def.radius
		if d < bestD then
			best, bestD = def, d
		end
	end
	if not best then
		return Vector3.yAxis
	end
	local flat = Vector3.new(p.X - best.position.X, 0, p.Z - best.position.Z)
	return if flat.Magnitude > 0.1 then flat.Unit else SpaceField.Facing(best)
end

--[[
	Yakalama noktası: canavarın ayağından tepesine dikey bir gövde; oyuncuya
	en yakın noktası. Canavar artık platonun altına inemediği için tek bir
	gövde merkezi, plato hizasındaki oyuncuya erişemiyordu.
]]
local function reachPoint(m: Monster, target: Vector3): Vector3
	local feet = m.position
	local y = math.clamp(target.Y, feet.Y + 1, feet.Y + bodyHeight(m.def) * 1.3)
	return Vector3.new(feet.X, y, feet.Z)
end

--[[ Canavarı hedefe doğru bir adım yürütür (gezegenlere girmeden). Hedefe kalan farkı döner. ]]
local function moveMonster(m: Monster, moveTo: Vector3, speed: number, dt: number): Vector3
	local delta = moveTo - m.position
	if delta.Magnitude > 0.05 then
		local step = math.min(delta.Magnitude, speed * dt)
		local from = m.position
		local nextPos, pushed = keepOffPlanets(from + delta.Unit * step)
		-- Gezegene yaslanıp yerinde sayıyorsa kenarından kayarak çıksın
		if pushed and (nextPos - from).Magnitude < step * 0.4 then
			nextPos = keepOffPlanets(from + (outwardFrom(from) * 0.8 + delta.Unit * 0.2).Unit * step)
		end
		m.position = clampOutside(m, nextPos)
	end
	return delta
end

local function stepMonsters(dt: number)
	local s = Config.Space
	local now = os.clock()
	for _, m in monsters do
		local need = m.def.need
		local moveTo: Vector3? = nil
		local speed = need * s.ReturnSpeedMul
		local look: Vector3? = nil
		--[[
			Ekipmanla sersemletilen canavar (Stun Gun, Slap Glove, Emergency
			Button) yerinde duruyor, kimseyi yakalamıyor; sersemlik bitince
			kovalamaya YENİDEN YAVAŞ başlıyor (rampa baştan) — oyuncuya
			gerçek bir kaçış penceresi.
		]]
		local stunned = now < m.stunUntil and m.state ~= "grab" and m.state ~= "throw"
		if stunned then
			if m.state == "chase" then
				m.chaseAt = now
			end
		elseif m.state == "wake" then
			local other, root = nearestCarrier(m)
			if root then
				look = root.Position - m.position
			end
			if not other then
				-- Kükrerken taşıyan teslim etti / bıraktı: eve dön
				m.target = nil
				setState(m, "return")
			elseif now - m.stateAt >= (m.def.wake or s.WakeDelay) * eventMods.wakeMul * stealthOf(m.target) then
				setState(m, "chase")
				m.chaseAt = now
			end
		elseif m.state == "chase" then
			local target = m.target
			local root = if target and carrying[target] and carrying[target].planet == m.planet then rootOf(target) else nil
			if not root then
				local other, otherRoot = nearestCarrier(m)
				m.target = other
				root = otherRoot
			end
			if not (m.target and root) then
				m.target = nil
				setState(m, "return")
			else
				local ramp = math.clamp((now - m.chaseAt) / s.ChaseRamp, 0, 1)
				speed = need * (s.ChaseStartMul + (1 - s.ChaseStartMul) * ramp)
				moveTo = root.Position - Vector3.new(0, bodyHeight(m.def), 0)
				look = root.Position - m.position
				local _, reachMul = Config.GetStealth(UpgradeService.GetLevel(m.target :: Player, "StealthSuit"))
				local reach = SpaceField.CatchRadius(m.def) * reachMul
				local body = reachPoint(m, root.Position)
				-- Ani atak (ileri canavarlar): yakına gelince kısa süre need × lunge
				local lunge = m.def.lunge or 1
				if lunge > 1 and now >= m.nextLunge and (body - root.Position).Magnitude <= s.LungeRange then
					m.lungeUntil = now + s.LungeTime
					m.nextLunge = now + s.LungeCooldown
					fx(m.target :: Player, "lunge", m.def.id)
				end
				if now < m.lungeUntil then
					speed = need * lunge
				end
				speed *= eventMods.chaseMul
				if (body - root.Position).Magnitude <= reach and not SpaceField.InSafe(root.Position) then
					catch(m, m.target :: Player)
				end
			end
		elseif m.state == "grab" then
			if now - m.stateAt >= s.GrabTime then
				setState(m, "throw")
			end
		elseif m.state == "throw" then
			if now - m.stateAt >= 0.6 then
				m.target = nil
				setState(m, "return")
			end
		elseif m.state == "return" then
			moveTo = m.home.Position
			local d = (m.home.Position - m.position).Magnitude
			if d < 1 then
				m.position = m.home.Position
				setState(m, "idle")
			end
			-- Dönerken biri yine çalarsa kovalamaya geri dön
			local other = nearestCarrier(m)
			if other then
				m.target = other
				setState(m, "wake")
			end
		elseif m.state == "idle" then
			-- En yakın oyuncuyu gözüyle izliyor
			local best: Vector3? = nil
			local bestD = 70
			for _, player in Players:GetPlayers() do
				local root = rootOf(player)
				if root then
					local d = (root.Position - m.position).Magnitude
					if d < bestD then
						best, bestD = root.Position, d
					end
				end
			end
			look = if best then best - m.position else m.home.LookVector
			local other = nearestCarrier(m)
			if other then
				m.target = other
				setState(m, "wake")
			end
		end

		if moveTo then
			local delta = moveMonster(m, moveTo, speed, dt)
			if not look and delta.Magnitude > 0.5 then
				look = delta
			end
		end
		if look then
			local flat = Vector3.new(look.X, 0, look.Z)
			if flat.Magnitude > 0.1 then
				m.facing = m.facing:Lerp(flat.Unit, math.min(1, dt * (if m.state == "idle" then 2 else 6))).Unit
			end
		end

		local cf = CFrame.lookAt(m.position, m.position + m.facing)
		if (m.root.CFrame.Position - cf.Position).Magnitude > 0.01 or m.root.CFrame.LookVector:Dot(cf.LookVector) < 0.9999 then
			m.root.CFrame = cf
		end
		local holder = m.root.Parent :: Instance
		local stunAttr = if stunned then true else nil
		if holder:GetAttribute("Stunned") ~= stunAttr then
			holder:SetAttribute("Stunned", stunAttr)
		end
		if holder:GetAttribute("State") ~= m.state then
			holder:SetAttribute("State", m.state)
		end
		local targetId = if m.target then m.target.UserId else 0
		if holder:GetAttribute("Target") ~= targetId then
			holder:SetAttribute("Target", targetId)
		end
	end
end

-- ─── Oyuncular ──────────────────────────────────────────────────────────────

local lastPlayerStep = 0

local function stepPlayers()
	local now = os.clock()
	if now - lastPlayerStep < 0.1 then
		return
	end
	lastPlayerStep = now
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if not root then
			continue
		end
		local pos = root.Position
		local inSpace = SpaceField.InSpace(pos)
		if (player:GetAttribute("InSpace") == true) ~= inSpace then
			player:SetAttribute("InSpace", if inSpace then true else nil)
			-- Bobin hızı uzayda sayılmıyor (MovementService bakıyor)
			MovementService.RefreshSpeed(player)
		end
		if carrying[player] and not grabbedBy[player] and SpaceField.InSafe(pos) then
			deliver(player, root)
		end
		-- Uçuş sınırının çok dışına düşen / fırlayan: güverteye
		local lo, hi = Config.Space.BoundsMin, Config.Space.BoundsMax
		if pos.Z < hi.Z and (pos.X < lo.X - 60 or pos.X > hi.X + 60 or pos.Y < lo.Y - 60 or pos.Y > hi.Y + 60 or pos.Z < lo.Z - 60) then
			drop(player)
			if player.Character then
				local deck = SpaceField.DeckCenter() + Vector3.new(0, 3.5, 0)
				player.Character:PivotTo(CFrame.lookAt(deck, deck + Vector3.new(0, 0, -1)))
				root.AssemblyLinearVelocity = Vector3.zero
			end
			notify(player, "Lost in space! Back to the Launch Bay", true)
		end
	end

	for _, list in spots do
		for _, spot in list do
			if not spot.unitId and not spot.held and spot.emptySince and now - spot.emptySince >= Config.Space.CrewRespawn then
				rollSpot(spot)
			end
		end
	end

	--[[
		Ortak rotasyon: CrewRotate sn'de bir bütün gezegenlerdeki mürettebat
		birlikte değişiyor (taşınanlar hariç). Zaman sunucu saati: istemci
		workspace.CrewRotateAt'ten herkese aynı geri sayımı çiziyor.
	]]
	local serverNow = workspace:GetServerTimeNow()
	if serverNow >= rotateAt then
		SpaceService.RotateCrew()
	end
end

-- ─── Dışa açık ──────────────────────────────────────────────────────────────

--[[ Bütün gezegenlerdeki mürettebatı birlikte yeniler (taşınanlar hariç). ]]
function SpaceService.RotateCrew()
	for _, list in spots do
		for _, spot in list do
			if not spot.held and crewFolder then
				rollSpot(spot)
			end
		end
	end
	rotateAt = workspace:GetServerTimeNow() + Config.Space.CrewRotate
	workspace:SetAttribute("CrewRotateAt", rotateAt)
end

--[[
	"Return to Station": uzaydaki oyuncuyu güverteye ışınlar. Taşırken
	olmaz (kaçmanın kısayolu olurdu), fırlatılırken olmaz. Kaide doluyken
	uzakta kalan oyuncu için (2026-09-28 isteği). Remote "SpaceReturn".
]]
local lastReturn: { [Player]: number } = {}
function SpaceService.ReturnToStation(player: Player): boolean
	local root = rootOf(player)
	if not root or not player:GetAttribute("InSpace") then
		return false
	end
	if carrying[player] then
		notify(player, "Bring the crewmate home first!", true)
		return false
	end
	if grabbedBy[player] then
		return false
	end
	local now = os.clock()
	if now - (lastReturn[player] or -math.huge) < 3 then
		return false
	end
	lastReturn[player] = now
	local deck = SpaceField.DeckCenter() + Vector3.new(0, 3.5, 8)
	if player.Character then
		player.Character:PivotTo(CFrame.lookAt(deck, deck + Vector3.new(0, 0, -1)))
		root.AssemblyLinearVelocity = Vector3.zero
	end
	return true
end

function SpaceService.IsCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

--[[
	Bedava karakter (çark, "Guaranteed Mutation" ürünü): oyuncunun hızının
	yettiği en iyi canavarın havuzundan, doğrudan kaideye. Boş kaide yoksa
	nil — çağıran ödülü harcamasın (ürün makbuzu sonra yeniden denenir).
]]
--[[ Oyuncunun hızının yettiği en iyi canavar, isteğe bağlı bir üst kademe. ]]
function SpaceService.PoolFor(player: Player, bonusTier: number?): Config.SpaceMonsterDef
	local best = Config.BestSpaceMonster(speedOf(player))
	local index = table.find(Config.SpaceMonsters, best) or 1
	return Config.SpaceMonsters[math.min(#Config.SpaceMonsters, index + (bonusTier or 0))]
end

function SpaceService.GrantUnit(player: Player, forceMutation: boolean, bonusTier: number?): (string?, string?)
	local def = SpaceService.PoolFor(player, bonusTier)
	local unit = Config.RollSpaceUnit(rng, def)
	local mutation = Config.RollMutation(rng)
	if forceMutation then
		while not mutation do
			mutation = Config.RollMutation(rng)
		end
	end
	local mutationId = if mutation then mutation.id else nil
	if not placeOnPodium(player, unit.id, mutationId, "got") then
		return nil, nil
	end
	return unitName(unit.id, mutationId), unit.id
end

--[[ Olayların uzaya etkisi (bkz. eventMods). Verilmeyen alan varsayılana döner. ]]
function SpaceService.SetEventMods(mods: { wakeMul: number?, chaseMul: number?, mutated: boolean? })
	local wasMutated = eventMods.mutated
	eventMods.wakeMul = mods.wakeMul or 1
	eventMods.chaseMul = mods.chaseMul or 1
	eventMods.mutated = mods.mutated == true
	-- Mutation Storm başlayınca gezegenlerdeki (taşınmayan) herkes yeniden çekiliyor
	if eventMods.mutated and not wasMutated and crewFolder then
		for _, list in spots do
			for _, spot in list do
				if spot.unitId and not spot.held then
					rollSpot(spot)
				end
			end
		end
	end
end

--[[
	Uzayda rastgele bir nokta: güverte ile bir gezegen arasındaki yolda,
	yanlara saçılmış, gezegenlerin içinde değil (Reactor Meltdown çekirdekleri).
]]
function SpaceService.RandomSpacePoint(random: Random?): Vector3?
	local r = random or rng
	local start = SpaceField.DeckCenter() + Vector3.new(0, 10, -20)
	for _ = 1, 30 do
		local def = Config.SpaceMonsters[r:NextInteger(1, #Config.SpaceMonsters)]
		local p = start:Lerp(def.position + Vector3.new(0, 12, 0), r:NextNumber(0.25, 0.85))
			+ Vector3.new(r:NextNumber(-45, 45), r:NextNumber(-12, 22), r:NextNumber(-20, 20))
		p = SpaceField.ClampToBounds(p)
		local clear = SpaceField.InSpace(p)
		for _, other in Config.SpaceMonsters do
			if (p - SpaceField.PlanetCenter(other)).Magnitude < other.radius + 8 then
				clear = false
			end
		end
		if clear then
			return p
		end
	end
	return nil
end

-- ─── Testler için ───────────────────────────────────────────────────────────

function SpaceService._Grab(player: Player, planet: number, index: number)
	local list = spots[planet]
	local spot = list and list[index]
	if spot then
		onGrab(player, spot)
	end
end

--[[ keepTime: yol süresi kontrolünü de dene (hile testi). ]]
function SpaceService._Deliver(player: Player, keepTime: boolean?)
	local root = rootOf(player)
	if root then
		local carry = carrying[player]
		if carry and not keepTime then
			carry.grabbedAt = -math.huge
		end
		deliver(player, root)
	end
end

function SpaceService.SetPaused(value: boolean)
	paused = value
end

function SpaceService._Drop(player: Player)
	drop(player)
end

function SpaceService._Catch(player: Player, planet: number)
	local m = monsters[planet]
	if m then
		catch(m, player)
	end
end

function SpaceService._Spot(planet: number, index: number): (string?, string?)
	local list = spots[planet]
	local spot = list and list[index]
	if not spot then
		return nil, nil
	end
	return spot.unitId, spot.mutationId
end

function SpaceService._Monster(planet: number): (string?, Player?)
	local m = monsters[planet]
	if not m then
		return nil, nil
	end
	return m.state, m.target
end

function SpaceService._Step(dt: number)
	stepMonsters(dt)
end

function SpaceService._KeepOffPlanets(p: Vector3): (Vector3, boolean)
	return keepOffPlanets(p)
end

function SpaceService._StepToward(planet: number, target: Vector3, dt: number)
	local m = monsters[planet]
	if m then
		moveMonster(m, target, m.def.need, dt)
	end
end

function SpaceService._MonsterPosition(planet: number): Vector3
	local m = monsters[planet]
	return if m then m.position else Vector3.zero
end

function SpaceService._ResetMonster(planet: number)
	local m = monsters[planet]
	if m then
		m.position = m.home.Position
		m.facing = m.home.LookVector
		m.target = nil
		m.stunUntil = 0
		setState(m, "idle")
	end
end

function SpaceService._ClearImmunity(player: Player)
	immuneUntil[player] = nil
	grabbedBy[player] = nil
	player:SetAttribute("SpaceGrabbed", nil)
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

function SpaceService.Start()
	notifyRemote = Net.Get("Notify")
	fxRemote = Net.Get("SpaceFX")

	-- Eski sürümün kafeterya hava kilidi (Batur, 2026-09-27) artık yok
	local oldAirlock = workspace:FindFirstChild("SpaceAirlock")
	if oldAirlock then
		oldAirlock:Destroy()
	end
	local old = workspace:FindFirstChild("SpaceZone")
	if old then
		old:Destroy()
	end

	local zone = Instance.new("Model")
	zone.Name = "SpaceZone"
	zone.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	buildDeck(zone)

	local planetFolder = Instance.new("Folder")
	planetFolder.Name = "Planets"
	planetFolder.Parent = zone
	local monsterFolder = Instance.new("Folder")
	monsterFolder.Name = "Monsters"
	monsterFolder.Parent = zone
	local crew = Instance.new("Folder")
	crew.Name = "Crew"
	crew.Parent = zone
	crewFolder = crew

	table.clear(spots)
	table.clear(monsters)
	for i, def in Config.SpaceMonsters do
		buildPlanet(planetFolder, i, def)
		monsters[i] = buildMonsterRoot(monsterFolder, i, def)
		local list: { Spot } = {}
		for k, pos in SpaceField.CrewSpots(def) do
			local spot: Spot = { planet = i, index = k, position = pos, held = false }
			-- Görünmez yer işareti (eskiden parlak halka vardı: "uzaydaki çemberler")
			local anchor = part(crew, "CrewSpot", Vector3.one, CFrame.new(pos + Vector3.new(0, 3, 0)), WHITE,
				{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
			anchor:SetAttribute("Planet", i)
			spot.anchor = anchor
			list[k] = spot
		end
		spots[i] = list
	end
	zone.Parent = workspace
	SpaceService.RotateCrew()

	--[[
		Konveyör kalktı; onun ürünleri artık doğrudan kaideye karakter veriyor.
		Boş kaide yoksa false: MonetizationService makbuzu sonra yeniden dener.
	]]
	MonetizationService.RegisterGranter("conveyor", function(player)
		return SpaceService.GrantUnit(player, false) ~= nil
	end)
	MonetizationService.RegisterGranter("lucky", function(player)
		return SpaceService.GrantUnit(player, true) ~= nil
	end)

	RunService.Heartbeat:Connect(function(dt)
		if paused then
			return
		end
		stepMonsters(dt)
		stepPlayers()
	end)

	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			drop(player)
			grabbedBy[player] = nil
			player:SetAttribute("InSpace", nil)
			player:SetAttribute("SpaceCarry", nil)
			player:SetAttribute("SpaceGrabbed", nil)
			MovementService.RefreshSpeed(player)
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Net.Get("SpaceReturn").OnServerEvent:Connect(function(player)
		SpaceService.ReturnToStation(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		drop(player)
		lastReturn[player] = nil
		immuneUntil[player] = nil
		grabbedBy[player] = nil
		shieldReadyAt[player] = nil
		for _, m in monsters do
			if m.target == player then
				m.target = nil
			end
		end
	end)
end

return SpaceService
