--!strict
--[[
	Gezegen savunmasının yüzeyleri (2026-10-01, Batur: "zemini ilk amongusu
	aldığımız dünyaya benzeyecek, gemi inmiş gibi, yanında shopçu, gearcı,
	marketçiler, geminin ilerisinde asıl yer").

	Her gezegenin dünyası İLK İNİŞTE kuruluyor (DefenseConfig.WorldOrigin,
	haritanın çok uzağında) ve sunucu kapanana kadar duruyor. Renkler
	uzaydaki gezegenin paleti (Config.SpaceMonsters): zemin planetColor2,
	alan planetColor, parlayan bitkiler glow.

	Yerel düzlem (DefenseConfig.Layout): gemi z ≈ -18'de, burnu +z'ye;
	rampa ucu Field.gate; savaş alanı önünde (z 34..200), düşman kapısı
	alanın öbür ucunda. Savaşın kendisi burada YOK: her oyuncunun dalgası
	kendi istemcisinde çiziliyor (DefenseService → DefenseFX).

	İstemler (ProximityPrompt) DefenseService'e gidiyor: OnPrompt(kind).
	kind: "command" | "takeoff" | "hospital" | "armory" | "shop" | "market"
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DefenseConfig = require(Shared.DefenseConfig)
local UnitModel = require(Shared.UnitModel)

local PromptGuard = require(script.Parent.PromptGuard)

local PlanetWorldService = {}

local worlds: { [number]: Model } = {}
local folder: Folder? = nil
local promptHandler: ((Player, number, string) -> ())? = nil

local WHITE = Color3.fromRGB(240, 244, 248)
local HULL = Color3.fromRGB(226, 232, 240)
local HULL_DARK = Color3.fromRGB(150, 160, 176)
local TRIM = Color3.fromRGB(214, 52, 52)
local GLASS = Color3.fromRGB(120, 200, 255)
local METAL = Color3.fromRGB(96, 104, 118)
local DARK = Color3.fromRGB(34, 38, 48)

-- ─── Parça yardımcıları ─────────────────────────────────────────────────────

type Props = { [string]: any }

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function glow(color: Color3): Props
	return { Material = Enum.Material.Neon, Color = color, CastShadow = false }
end

-- Dikey silindir (Roblox silindiri X ekseninde uzanıyor)
local function vcyl(parent: Instance, name: string, at: Vector3, height: number, diameter: number, color: Color3, props: Props?): Part
	local p = part(parent, name, Vector3.new(height, diameter, diameter),
		CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)), color, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, at: CFrame, size: Vector3, color: Color3, props: Props?): Part
	local p = part(parent, name, size, at, color, props)
	p.Shape = Enum.PartType.Ball
	return p
end

local function sign(parent: Instance, name: string, cf: CFrame, size: Vector2, text: string, color: Color3)
	local board = part(parent, name, Vector3.new(size.X, size.Y, 0.4), cf, DARK)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = Vector2.new(size.X * 50, size.Y * 50)
	gui.LightInfluence = 0
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.AutoLocalize = false
	label.Text = text
	label.Parent = gui
	local frame = part(parent, name .. "Frame", Vector3.new(size.X + 0.6, size.Y + 0.6, 0.3),
		cf * CFrame.new(0, 0, 0.25), color, glow(color))
	frame.CanCollide = false
end

local function addPrompt(parent: BasePart, planet: number, kind: string, action: string, object: string, hold: number?)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DefensePrompt"
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = hold or 0.25
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("DefenseKind", kind)
	prompt.Parent = parent
	PromptGuard.Connect(prompt, function(player)
		if promptHandler then
			promptHandler(player, planet, kind)
		end
	end)
end

-- ─── Zemin ──────────────────────────────────────────────────────────────────

local function buildGround(model: Model, origin: Vector3, def: Config.SpaceMonsterDef, rng: Random)
	local L = DefenseConfig.Layout
	local F = DefenseConfig.Field
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = model
	local base, patch, light = def.planetColor2, def.planetColor, def.glow

	-- Ana disk
	local disk = vcyl(ground, "Surface", origin - Vector3.new(0, 5, 0), 10, L.groundRadius * 2, base,
		{ Material = Enum.Material.Grass })
	disk:SetAttribute("DefenseGround", true)

	-- Savaş alanı: hafif açık renkli yama ve kenar işaretleri
	local fieldW, fieldD = F.halfWidth * 2 + 8, F.zMax - F.zMin + 30
	local fieldCenter = origin + Vector3.new(0, 0.05, (F.zMin + F.zMax) / 2 + 6)
	local field = part(ground, "Field", Vector3.new(fieldW, 0.1, fieldD), CFrame.new(fieldCenter),
		patch:Lerp(WHITE, 0.08), { Material = Enum.Material.Grass, CanCollide = false })
	field:SetAttribute("DefenseGround", true)
	for side = -1, 1, 2 do
		for z = F.zMin, F.zMax + 10, 18 do
			local post = origin + Vector3.new(side * (F.halfWidth + 5), 0, z)
			vcyl(ground, "FieldPost", post + Vector3.new(0, 1.2, 0), 2.4, 0.8, METAL)
			ball(ground, "FieldLamp", CFrame.new(post + Vector3.new(0, 2.7, 0)), Vector3.one * 0.9, light, glow(light))
		end
	end
	-- Rampanın önündeki savunma çizgisi
	part(ground, "GateLine", Vector3.new(F.halfWidth * 2, 0.12, 0.8),
		CFrame.new(origin + Vector3.new(0, 0.1, F.zMin - 4)), light, glow(light))

	-- Kraterler (ilk gezegendeki gibi: kenarı açık, içi koyu)
	local function crater(at: Vector3, size: number)
		vcyl(ground, "CraterRim", at + Vector3.new(0, 0.15, 0), 0.6, size, patch:Lerp(WHITE, 0.12),
			{ CanCollide = false })
		vcyl(ground, "Crater", at + Vector3.new(0, 0.3, 0), 0.5, size * 0.78, base:Lerp(DARK, 0.25),
			{ CanCollide = false })
	end
	for _ = 1, 34 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(60, L.groundRadius - 50)
		local at = origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local rel = at - origin
		-- Gemi ve dükkânların üstüne düşmesin
		if math.abs(rel.X) < 70 and rel.Z < 30 and rel.Z > -70 then
			continue
		end
		crater(at, rng:NextNumber(8, 22))
	end

	-- Parlayan bitkiler ve kayalar (alanın dışında)
	for _ = 1, 70 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(80, L.groundRadius - 30)
		local at = origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local rel = at - origin
		local inField = math.abs(rel.X) < F.halfWidth + 10 and rel.Z > F.zMin - 10 and rel.Z < F.zMax + 30
		local nearBase = math.abs(rel.X) < 75 and rel.Z < 30 and rel.Z > -75
		if inField or nearBase then
			continue
		end
		if rng:NextNumber() < 0.55 then
			local h = rng:NextNumber(2, 5)
			vcyl(ground, "Stalk", at + Vector3.new(0, h / 2, 0), h, 0.5, patch:Lerp(DARK, 0.3))
			ball(ground, "GlowBulb", CFrame.new(at + Vector3.new(0, h + 0.4, 0)), Vector3.one * rng:NextNumber(1, 1.8),
				light, glow(light))
		else
			local s = rng:NextNumber(3, 9)
			ball(ground, "Rock", CFrame.new(at + Vector3.new(0, s * 0.2, 0)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
				Vector3.new(s * 1.3, s * 0.7, s), base:Lerp(DARK, 0.35), { Material = Enum.Material.Slate })
		end
	end

	-- Ufuktaki dağlar
	for i = 1, 26 do
		local angle = (i / 26) * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local radius = L.groundRadius - rng:NextNumber(0, 20)
		local at = origin + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		local h = rng:NextNumber(40, 110)
		local w = rng:NextNumber(60, 120)
		ball(ground, "Mountain", CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			Vector3.new(w, h * 2, w * 0.8), base:Lerp(DARK, rng:NextNumber(0.25, 0.5)), { Material = Enum.Material.Slate })
	end

	-- Düşman kapısı: kayalık bir yarık ve içinde parlayan geçit
	local gate = origin + Vector3.new(F.entrance.X, 0, F.entrance.Y + 10)
	vcyl(ground, "PitRim", gate + Vector3.new(0, 0.3, 0), 0.8, 34, base:Lerp(DARK, 0.4), { CanCollide = false })
	vcyl(ground, "Pit", gate + Vector3.new(0, 0.5, 0), 0.6, 26, Color3.fromRGB(16, 10, 24), { CanCollide = false })
	-- Silindir X ekseninde: Y'de 90° çevirince yüzü alana (z) bakan bir halka
	local portal = part(ground, "Portal", Vector3.new(1, 26, 26),
		CFrame.new(gate + Vector3.new(0, 13, 6)) * CFrame.Angles(0, math.rad(90), 0), light, glow(light))
	portal.Shape = Enum.PartType.Cylinder
	portal.Transparency = 0.45
	for k = -3, 3 do
		local a = math.rad(k * 26)
		local at = gate + Vector3.new(math.sin(a) * 19, 0, 8 + math.cos(a) * 6)
		local s = rng:NextNumber(10, 16)
		ball(ground, "GateRock", CFrame.new(at + Vector3.new(0, s * 0.5, 0)), Vector3.new(s, s * 1.8, s),
			base:Lerp(DARK, 0.45), { Material = Enum.Material.Slate })
	end
	local beacon = Instance.new("PointLight")
	beacon.Color = light
	beacon.Range = 40
	beacon.Brightness = 3
	beacon.Parent = portal
end

-- ─── İnik gemi ──────────────────────────────────────────────────────────────

local function buildShip(model: Model, origin: Vector3)
	local L = DefenseConfig.Layout
	local F = DefenseConfig.Field
	local ship = Instance.new("Model")
	ship.Name = "LandedShip"
	ship.Parent = model
	local c = origin + Vector3.new(0, 0, L.shipZ)
	local bodyY = 9

	-- Gövde: uzun yuvarlak kapsül
	part(ship, "Hull", Vector3.new(26, 12, 46), CFrame.new(c + Vector3.new(0, bodyY, 0)), HULL)
	ball(ship, "Nose", CFrame.new(c + Vector3.new(0, bodyY, 23)), Vector3.new(26, 12, 22), HULL)
	ball(ship, "Tail", CFrame.new(c + Vector3.new(0, bodyY, -23)), Vector3.new(26, 12, 14), HULL_DARK)
	part(ship, "Belly", Vector3.new(22, 2, 44), CFrame.new(c + Vector3.new(0, bodyY - 6.6, 0)), HULL_DARK)
	part(ship, "Stripe", Vector3.new(26.3, 1.4, 46.2), CFrame.new(c + Vector3.new(0, bodyY + 1, 0)), TRIM)
	-- Kokpit camı
	ball(ship, "Cockpit", CFrame.new(c + Vector3.new(0, bodyY + 3.5, 22)), Vector3.new(16, 8, 14), GLASS,
		{ Material = Enum.Material.Glass, Transparency = 0.25, Reflectance = 0.15 })
	-- Kanatlar
	for side = -1, 1, 2 do
		part(ship, "Wing", Vector3.new(16, 1.4, 20),
			CFrame.new(c + Vector3.new(side * 19, bodyY - 1, -4)) * CFrame.Angles(0, 0, math.rad(side * -8)), HULL)
		part(ship, "WingTip", Vector3.new(1.2, 5, 8), CFrame.new(c + Vector3.new(side * 27, bodyY + 1, -8)), TRIM)
		-- Motorlar
		local engine = c + Vector3.new(side * 8, bodyY - 1, -29)
		local e = part(ship, "Engine", Vector3.new(10, 7, 7), CFrame.new(engine) * CFrame.Angles(0, math.rad(90), 0), METAL)
		e.Shape = Enum.PartType.Cylinder
		local g = part(ship, "EngineGlow", Vector3.new(0.6, 5, 5), CFrame.new(engine - Vector3.new(0, 0, 5.1)) * CFrame.Angles(0, math.rad(90), 0),
			Color3.fromRGB(255, 150, 60), glow(Color3.fromRGB(255, 150, 60)))
		g.Shape = Enum.PartType.Cylinder
		-- İniş ayakları
		for _, z in { -14, 12 } do
			local foot = c + Vector3.new(side * 10, 0, z)
			part(ship, "Leg", Vector3.new(1.2, bodyY - 2, 1.2), CFrame.new(foot + Vector3.new(0, (bodyY - 2) / 2, 0)) * CFrame.Angles(0, 0, math.rad(side * 10)), METAL)
			vcyl(ship, "Foot", foot + Vector3.new(side * 0.6, 0.3, 0), 0.6, 3.4, DARK)
		end
	end
	-- Tepe anteni ve ışığı
	vcyl(ship, "Antenna", c + Vector3.new(0, bodyY + 9, -10), 6, 0.4, METAL)
	ball(ship, "AntennaTip", CFrame.new(c + Vector3.new(0, bodyY + 12.2, -10)), Vector3.one * 0.9, TRIM, glow(TRIM))

	-- Rampa: burnun altından savunma çizgisine iniyor
	local top = Vector3.new(0, 3.2, L.shipZ + 22)
	local bottom = Vector3.new(F.gate.X, 0.2, F.gate.Y)
	local mid = (top + bottom) / 2
	local len = (top - bottom).Magnitude
	local rampCf = CFrame.lookAt(origin + mid, origin + bottom)
	part(ship, "Ramp", Vector3.new(10, 0.6, len), rampCf, HULL_DARK)
	for side = -1, 1, 2 do
		part(ship, "RampRail", Vector3.new(0.4, 0.4, len), rampCf * CFrame.new(side * 4.8, 2, 0), TRIM, glow(TRIM))
	end
	-- Rampanın altında kapı ışığı
	part(ship, "Door", Vector3.new(9, 6, 0.4), CFrame.new(origin + Vector3.new(0, 4.4, L.shipZ + 21.5)),
		Color3.fromRGB(255, 240, 200), glow(Color3.fromRGB(255, 240, 200)))
end

-- ─── Konsollar ve dükkânlar ─────────────────────────────────────────────────

local function console(model: Model, planet: number, origin: Vector3, at: Vector2, kind: string, action: string,
	object: string, color: Color3)
	local p = origin + Vector3.new(at.X, 0, at.Y)
	local f = Instance.new("Model")
	f.Name = "Console_" .. kind
	f.Parent = model
	part(f, "Base", Vector3.new(4, 3.2, 3), CFrame.new(p + Vector3.new(0, 1.6, 0)), METAL)
	local screen = part(f, "Screen", Vector3.new(4.4, 0.4, 3.2),
		CFrame.new(p + Vector3.new(0, 3.5, 0)) * CFrame.Angles(math.rad(-25), 0, 0), color, glow(color))
	ball(f, "Beacon", CFrame.new(p + Vector3.new(0, 6.5, 0)), Vector3.one * 1.1, color, glow(color))
	vcyl(f, "Pole", p + Vector3.new(0, 5, 0), 3, 0.3, METAL)
	addPrompt(screen, planet, kind, action, object, 0.3)
end

type Stall = { kind: string, title: string, name: string, color: Color3, action: string, npc: string }

local STALLS: { [string]: Stall } = {
	hospital = { kind = "hospital", title = "✚ HOSPITAL", name = "HOSPITAL", color = Color3.fromRGB(255, 90, 90), action = "Visit", npc = "MedbayScan" },
	armory = { kind = "armory", title = "⚔ ARMORY", name = "ARMORY", color = Color3.fromRGB(255, 170, 60), action = "Upgrade", npc = "Sheriff" },
	shop = { kind = "shop", title = "🚀 COMMAND SHOP", name = "COMMAND SHOP", color = Color3.fromRGB(90, 170, 255), action = "Shop", npc = "Engineer" },
	market = { kind = "market", title = "☄ MARKET", name = "MARKET", color = Color3.fromRGB(190, 110, 255), action = "Buy", npc = "Jester" },
}

local function stall(model: Model, planet: number, origin: Vector3, at: Vector2, info: Stall)
	local p = origin + Vector3.new(at.X, 0, at.Y)
	-- Tezgâh gemiye (x = 0) bakıyor
	local face = CFrame.lookAt(p, Vector3.new(origin.X, p.Y, p.Z))
	local f = Instance.new("Model")
	f.Name = "Stall_" .. info.kind
	f.Parent = model

	part(f, "Floor", Vector3.new(16, 0.6, 14), face * CFrame.new(0, 0.3, 0), HULL_DARK)
	part(f, "Counter", Vector3.new(12, 3.4, 2.4), face * CFrame.new(0, 2.3, -3.5), WHITE)
	local top = part(f, "CounterTop", Vector3.new(12.6, 0.4, 3), face * CFrame.new(0, 4.1, -3.5), info.color)
	for _, x in { -7, 7 } do
		for _, z in { -6, 5.5 } do
			vcyl(f, "Post", (face * CFrame.new(x, 5, z)).Position, 10, 0.6, METAL)
		end
	end
	-- Çatı: iki renkli tente
	for k = -3, 3 do
		part(f, "Awning", Vector3.new(2.2, 0.5, 15),
			face * CFrame.new(k * 2.2, 10.4, -0.2) * CFrame.Angles(math.rad(8), 0, 0),
			if k % 2 == 0 then info.color else WHITE)
	end
	sign(f, "Sign", face * CFrame.new(0, 12.6, -6.6) * CFrame.Angles(0, math.rad(180), 0), Vector2.new(11, 2.4),
		info.title, info.color)

	-- Tezgâhtar: oyundaki bir crewmate
	local ok, npc = pcall(UnitModel.Build, info.npc, nil)
	if ok and npc then
		npc.Name = "Keeper"
		for _, d in npc:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		npc:PivotTo(face * CFrame.new(0, 0.6, 0.5) * CFrame.Angles(0, math.rad(180), 0))
		npc.Parent = f
	end

	addPrompt(top, planet, info.kind, info.action, info.name, 0.2)

	-- Hastanede yatak ve kırmızı haç, cephanede silah rafı: ne olduğu uzaktan belli olsun
	if info.kind == "hospital" then
		for k = -1, 1, 2 do
			part(f, "Bed", Vector3.new(3, 1.2, 6), face * CFrame.new(k * 5, 1.2, 3.5), WHITE)
			part(f, "Pillow", Vector3.new(2.4, 0.6, 1.4), face * CFrame.new(k * 5, 2, 5.6), Color3.fromRGB(200, 230, 255))
		end
		part(f, "CrossV", Vector3.new(1.2, 4, 0.4), face * CFrame.new(0, 7, 6.6), info.color, glow(info.color))
		part(f, "CrossH", Vector3.new(4, 1.2, 0.4), face * CFrame.new(0, 7, 6.6), info.color, glow(info.color))
	elseif info.kind == "armory" then
		part(f, "Rack", Vector3.new(10, 6, 0.6), face * CFrame.new(0, 3.6, 6.4), METAL)
		for k = -2, 2 do
			part(f, "Blade", Vector3.new(0.4, 4, 0.3), face * CFrame.new(k * 2, 4, 6), Color3.fromRGB(210, 220, 235),
				{ Material = Enum.Material.Metal })
		end
	elseif info.kind == "market" then
		for k = -1, 1 do
			part(f, "Crate", Vector3.new(3, 3, 3), face * CFrame.new(k * 3.6, 1.8, 5),
				Color3.fromRGB(170, 120, 70), { Material = Enum.Material.WoodPlanks })
		end
	else
		part(f, "Screen", Vector3.new(9, 4.5, 0.4), face * CFrame.new(0, 6, 6.4), info.color, glow(info.color))
	end
end

-- ─── Kurulum ────────────────────────────────────────────────────────────────

local function build(planet: number): Model?
	local def = Config.SpaceMonsters[planet]
	if not def then
		return nil
	end
	local origin = DefenseConfig.WorldOrigin(planet)
	local model = Instance.new("Model")
	model.Name = "World_" .. planet
	model:SetAttribute("Planet", planet)
	local rng = Random.new(planet * 7717)

	buildGround(model, origin, def, rng)
	buildShip(model, origin)

	local L = DefenseConfig.Layout
	console(model, planet, origin, L.command, "command", "Command", "DEFENSE", Color3.fromRGB(90, 230, 140))
	console(model, planet, origin, L.takeoff, "takeoff", "Take off", "SHIP", Color3.fromRGB(120, 200, 255))
	stall(model, planet, origin, L.hospital, STALLS.hospital)
	stall(model, planet, origin, L.armory, STALLS.armory)
	stall(model, planet, origin, L.shop, STALLS.shop)
	stall(model, planet, origin, L.market, STALLS.market)

	-- Varış noktası
	local spawn = part(model, "Spawn", Vector3.new(6, 0.2, 6),
		CFrame.new(origin + Vector3.new(L.spawn.X, 0.1, L.spawn.Y)), Color3.fromRGB(120, 200, 255),
		{ Transparency = 1, CanCollide = false, CanQuery = false })
	spawn:SetAttribute("DefenseSpawn", true)

	model.PrimaryPart = spawn
	model.Parent = folder
	return model
end

--[[ Gezegenin dünyası (yoksa şimdi kuruluyor). ]]
function PlanetWorldService.Get(planet: number): Model?
	local existing = worlds[planet]
	if existing and existing.Parent then
		return existing
	end
	local model = build(planet)
	if model then
		worlds[planet] = model
	end
	return model
end

--[[ Varış noktası (dünya CFrame'i, ayak hizasının biraz üstü). ]]
function PlanetWorldService.SpawnCFrame(planet: number): CFrame
	local L = DefenseConfig.Layout
	local p = DefenseConfig.ToWorld(planet, L.spawn, 3.5)
	return CFrame.lookAt(p, p + Vector3.new(0, 0, 1))
end

function PlanetWorldService.OnPrompt(handler: (Player, number, string) -> ())
	promptHandler = handler
end

function PlanetWorldService.Start()
	local existing = workspace:FindFirstChild("PlanetWorlds")
	if existing then
		existing:Destroy()
	end
	table.clear(worlds)
	local f = Instance.new("Folder")
	f.Name = "PlanetWorlds"
	f.Parent = workspace
	folder = f
end

return PlanetWorldService
