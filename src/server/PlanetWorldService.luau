--!strict
--[[
	Gezegen savunmasının yüzeyi (2026-10-01, Batur).

	İkinci sürüm ("map çok kötü olmuş; gemi daha büyük ve detaylı, upgrade
	shop gibi yerler küçük gemicikler olsun; şimdilik tek harita"):
	  - Zemin, tepeler, kraterler ve düşman mağarası TERRAIN (istasyon
	    Terrain kullanmıyor, malzeme renkleri gezegenin paleti)
	  - Ortada büyük, detaylı inik gemi; burnunun altından rampa savunma
	    çizgisine iniyor
	  - Dört dükkân, yanlarda inmiş küçük gemiler: yan kapakları ana gemiye
	    açık, önünde tezgâh, tabela ve tezgâhtar crewmate
	  - Savaş alanı geminin önünde; düşmanlar alanın ucundaki kayalığın
	    mağarasından çıkıyor

	Yerel düzlem DefenseConfig.Layout / Field. Savaşın kendisi burada YOK:
	her oyuncunun dalgası kendi istemcisinde çiziliyor (DefenseFX).

	İstemler DefenseService'e: OnPrompt(kind), kind = "command" | "takeoff" |
	"hospital" | "armory" | "shop" | "market".
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DefenseConfig = require(Shared.DefenseConfig)
local UnitModel = require(Shared.UnitModel)

local PromptGuard = require(script.Parent.PromptGuard)

local PlanetWorldService = {}

-- arena -> dünya (DefenseConfig.MaxArenas kopya, ilk kullanımda)
local worlds: { [number]: Model } = {}
local folder: Folder? = nil
local promptHandler: ((Player, number, string) -> ())? = nil
local paletteSet = false

local WHITE = Color3.fromRGB(240, 244, 248)
local HULL = Color3.fromRGB(232, 236, 242)
local HULL2 = Color3.fromRGB(196, 204, 216)
local PANEL = Color3.fromRGB(150, 158, 172)
local TRIM = Color3.fromRGB(214, 48, 52)
local GLASS = Color3.fromRGB(110, 200, 255)
local METAL = Color3.fromRGB(96, 104, 118)
local DARK = Color3.fromRGB(34, 38, 48)
local FLAME = Color3.fromRGB(255, 150, 60)

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

local function glow(color: Color3, extra: Props?): Props
	local t: Props = { Material = Enum.Material.Neon, Color = color, CastShadow = false }
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end

-- Silindir boyu X ekseninde: `along` yönüne çevrilmiş CFrame
local function alongZ(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, math.rad(90), 0)
end
local function alongY(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, 0, math.rad(90))
end

local function cyl(parent: Instance, name: string, cf: CFrame, length: number, diameter: number, color: Color3, props: Props?): Part
	local p = part(parent, name, Vector3.new(length, diameter, diameter), cf, color, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, props: Props?): Part
	local p = part(parent, name, size, cf, color, props)
	p.Shape = Enum.PartType.Ball
	return p
end

local function signBoard(parent: Instance, name: string, cf: CFrame, size: Vector2, text: string, color: Color3)
	local board = part(parent, name, Vector3.new(size.X, size.Y, 0.5), cf, DARK)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.CanvasSize = Vector2.new(size.X * 40, size.Y * 40)
		gui.LightInfluence = 0
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = color
		label.TextStrokeTransparency = 0.3
		label.AutoLocalize = false
		label.Text = text
		label.Parent = gui
	end
	part(parent, name .. "Frame", Vector3.new(size.X + 0.8, size.Y + 0.8, 0.3), cf, color, glow(color, { CanCollide = false }))
end

local function light(parent: BasePart, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
end

local function addPrompt(parent: BasePart, arena: number, kind: string, action: string, object: string, hold: number?)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DefensePrompt"
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = hold or 0.2
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("DefenseKind", kind)
	prompt.Parent = parent
	PromptGuard.Connect(prompt, function(player)
		if promptHandler then
			promptHandler(player, arena, kind)
		end
	end)
end

-- ─── Zemin (Terrain) ────────────────────────────────────────────────────────

local function buildTerrain(origin: Vector3, def: Config.SpaceMonsterDef, rng: Random)
	local T = workspace.Terrain
	local L = DefenseConfig.Layout
	local F = DefenseConfig.Field
	local base, patch = def.planetColor2, def.planetColor
	-- Malzeme renkleri gezegenin paleti (Terrain'i başka yer kullanmıyor;
	-- renkler genel, tek gezegen olduğu için bir kez)
	if not paletteSet then
		paletteSet = true
		T:SetMaterialColor(Enum.Material.LeafyGrass, base)
		T:SetMaterialColor(Enum.Material.Grass, patch)
		T:SetMaterialColor(Enum.Material.Ground, base:Lerp(Color3.fromRGB(90, 80, 60), 0.45))
		T:SetMaterialColor(Enum.Material.Rock, base:Lerp(DARK, 0.55))
		T:SetMaterialColor(Enum.Material.Mud, base:Lerp(DARK, 0.4))
	end

	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(origin + Vector3.new(x, y, z))
	end

	-- Ana disk: üst yüzey origin.Y
	T:FillCylinder(at(0, -10, 0), 20, L.groundRadius, Enum.Material.LeafyGrass)
	-- Savaş alanı açık renkli çimen
	local fieldD = F.zMax - F.zMin + 34
	T:FillBlock(at(0, -2, (F.zMin + F.zMax) / 2 + 8), Vector3.new(F.halfWidth * 2 + 12, 4, fieldD), Enum.Material.Grass)
	-- Gemilerin indiği yer: yanık toprak
	T:FillBlock(at(0, -2, L.shipZ + 4), Vector3.new(200, 4, 160), Enum.Material.Ground)

	-- Kraterler (alan ve üs dışında): oyuk + taş kenar
	for _ = 1, 26 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(130, L.groundRadius - 90)
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		local inField = math.abs(x) < F.halfWidth + 24 and z > F.zMin - 20 and z < F.zMax + 60
		local nearBase = math.abs(x) < 120 and z < 30 and z > -160
		if inField or nearBase then
			continue
		end
		local r = rng:NextNumber(8, 18)
		T:FillCylinder(at(x, -1, z), 4, r, Enum.Material.Air)
		T:FillCylinder(at(x, -4, z), 2, r * 0.9, Enum.Material.Mud)
		for k = 0, 9 do
			local a = k / 10 * math.pi * 2
			T:FillBall(Vector3.new(origin.X + x + math.cos(a) * r, origin.Y - 1, origin.Z + z + math.sin(a) * r), 3.5, Enum.Material.Ground)
		end
	end

	-- Çevredeki yeşil tepeler
	for i = 1, 30 do
		local angle = (i / 30) * math.pi * 2 + rng:NextNumber(-0.06, 0.06)
		local radius = L.groundRadius - rng:NextNumber(20, 70)
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		-- Alanın arkası kayalık (aşağıda); oraya tepe koyma
		if z > 180 and math.abs(x) < 220 then
			continue
		end
		local r = rng:NextNumber(40, 80)
		T:FillBall(Vector3.new(origin.X + x, origin.Y - r * 0.45, origin.Z + z), r, Enum.Material.LeafyGrass)
		if rng:NextNumber() < 0.5 then
			T:FillBall(Vector3.new(origin.X + x + rng:NextNumber(-20, 20), origin.Y + r * 0.2, origin.Z + z), r * 0.45, Enum.Material.Rock)
		end
	end

	-- Alanın sonundaki kayalık ve ortasında mağara (düşman kapısı)
	local cliffZ = F.entrance.Y + 44
	for x = -230, 230, 22 do
		local h = 40 + math.abs(math.sin(x * 0.05)) * 30 + rng:NextNumber(0, 16)
		T:FillBall(Vector3.new(origin.X + x, origin.Y + h * 0.3, origin.Z + cliffZ + rng:NextNumber(-8, 12)), h * 0.75, Enum.Material.Rock)
	end
	-- Mağara ağzı: kayalığın önünü oy
	T:FillBall(Vector3.new(origin.X + F.entrance.X, origin.Y + 8, origin.Z + F.entrance.Y + 22), 22, Enum.Material.Air)
	T:FillBlock(at(F.entrance.X, -2, F.entrance.Y + 14), Vector3.new(40, 4, 40), Enum.Material.Mud)
end

local function buildDecor(model: Model, origin: Vector3, def: Config.SpaceMonsterDef, rng: Random)
	local L = DefenseConfig.Layout
	local F = DefenseConfig.Field
	local f = Instance.new("Folder")
	f.Name = "Decor"
	f.Parent = model
	local light_ = def.glow

	local function free(x: number, z: number): boolean
		local inField = math.abs(x) < F.halfWidth + 14 and z > F.zMin - 12 and z < F.zMax + 40
		local nearBase = math.abs(x) < 118 and z < 30 and z > -150
		return not inField and not nearBase and (x * x + z * z) < (L.groundRadius - 60) ^ 2
	end

	-- Parlayan mantar ağaçları
	for _ = 1, 46 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(90, L.groundRadius - 70)
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		if not free(x, z) then
			continue
		end
		local h = rng:NextNumber(6, 16)
		local p = origin + Vector3.new(x, 0, z)
		cyl(f, "Stem", alongY(CFrame.new(p + Vector3.new(0, h / 2, 0))), h, h * 0.16, Color3.fromRGB(230, 225, 205))
		local capW = h * rng:NextNumber(0.7, 1.0)
		ball(f, "Cap", CFrame.new(p + Vector3.new(0, h, 0)), Vector3.new(capW, capW * 0.45, capW), light_:Lerp(WHITE, 0.15),
			{ Material = Enum.Material.SmoothPlastic })
		for k = 1, 4 do
			local a = k / 4 * math.pi * 2 + rng:NextNumber(0, 1)
			ball(f, "Spot", CFrame.new(p + Vector3.new(math.cos(a) * capW * 0.28, h + capW * 0.16, math.sin(a) * capW * 0.28)),
				Vector3.one * capW * 0.14, WHITE, glow(WHITE, { CanCollide = false }))
		end
		local glowPart = ball(f, "CapGlow", CFrame.new(p + Vector3.new(0, h - capW * 0.12, 0)), Vector3.new(capW * 0.8, capW * 0.2, capW * 0.8),
			light_, glow(light_, { CanCollide = false }))
		if rng:NextNumber() < 0.3 then
			light(glowPart, light_, 18, 1)
		end
	end

	-- Kristal kümeleri
	for _ = 1, 26 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(100, L.groundRadius - 70)
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		if not free(x, z) then
			continue
		end
		local p = origin + Vector3.new(x, 0, z)
		for k = 1, rng:NextInteger(3, 6) do
			local h = rng:NextNumber(3, 9)
			part(f, "Crystal", Vector3.new(h * 0.3, h, h * 0.3),
				CFrame.new(p + Vector3.new(rng:NextNumber(-2, 2), h * 0.4, rng:NextNumber(-2, 2)))
					* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)),
				light_:Lerp(Color3.fromRGB(140, 200, 255), 0.4), glow(light_:Lerp(Color3.fromRGB(140, 200, 255), 0.4), { Transparency = 0.15 }))
		end
	end

	-- Alan sınırı: lambalı dikmeler ve rampanın önünde savunma çizgisi
	for side = -1, 1, 2 do
		for z = F.zMin, F.zMax + 10, 20 do
			local post = origin + Vector3.new(side * (F.halfWidth + 6), 0, z)
			cyl(f, "FieldPost", alongY(CFrame.new(post + Vector3.new(0, 1.6, 0))), 3.2, 0.9, METAL)
			ball(f, "FieldLamp", CFrame.new(post + Vector3.new(0, 3.5, 0)), Vector3.one * 1.1, light_, glow(light_))
		end
	end
	part(f, "GateLine", Vector3.new(F.halfWidth * 2, 0.15, 1), CFrame.new(origin + Vector3.new(0, 0.12, F.zMin - 4)),
		Color3.fromRGB(255, 220, 80), glow(Color3.fromRGB(255, 220, 80), { CanCollide = false }))

	-- Mağaranın içindeki geçit
	local gate = origin + Vector3.new(F.entrance.X, 0, F.entrance.Y + 18)
	local portal = cyl(f, "Portal", CFrame.new(gate + Vector3.new(0, 11, 0)) * CFrame.Angles(0, math.rad(90), 0), 1, 22, light_,
		glow(light_, { Transparency = 0.35, CanCollide = false }))
	light(portal, light_, 50, 3)
	cyl(f, "PortalRing", CFrame.new(gate + Vector3.new(0, 11, 0.6)) * CFrame.Angles(0, math.rad(90), 0), 1.2, 25, DARK)
end

-- ─── Ana gemi ───────────────────────────────────────────────────────────────

local function buildShip(model: Model, origin: Vector3)
	local L = DefenseConfig.Layout
	local F = DefenseConfig.Field
	local ship = Instance.new("Model")
	ship.Name = "LandedShip"
	ship.Parent = model
	local c = origin + Vector3.new(0, 0, L.shipZ)
	local Y = 22          -- gövde ekseninin yüksekliği
	local D = 30          -- gövde çapı
	local LEN = 104

	local function rel(x: number, y: number, z: number): CFrame
		return CFrame.new(c + Vector3.new(x, y, z))
	end

	-- Gövde: uzun silindir, burun ve kuyruk küreleri
	cyl(ship, "Fuselage", alongZ(rel(0, Y, 0)), LEN, D, HULL)
	ball(ship, "Nose", rel(0, Y, LEN / 2), Vector3.new(D, D, 40), HULL)
	ball(ship, "Tail", rel(0, Y, -LEN / 2), Vector3.new(D, D, 22), HULL2)
	-- Sırt kamburu
	cyl(ship, "Dorsal", alongZ(rel(0, Y + 9, -6)), 70, 20, HULL)
	ball(ship, "DorsalFront", rel(0, Y + 9, 29), Vector3.new(20, 20, 18), HULL)
	-- Alt karın (kargo)
	part(ship, "Belly", Vector3.new(22, 5, 88), rel(0, Y - 13.5, -4), PANEL)
	-- Kokpit camı ve çerçevesi
	ball(ship, "Cockpit", rel(0, Y + 8, LEN / 2 + 4), Vector3.new(22, 13, 22), GLASS,
		{ Material = Enum.Material.Glass, Transparency = 0.2, Reflectance = 0.2 })
	ball(ship, "CockpitRim", rel(0, Y + 7.4, LEN / 2 + 3.4), Vector3.new(23.4, 12.4, 22.6), DARK)
	-- Panel çizgileri (gövdeyi saran halkalar)
	for z = -40, 40, 16 do
		cyl(ship, "PanelRing", alongZ(rel(0, Y, z)), 0.8, D + 0.5, PANEL)
	end
	-- Yan kırmızı şerit ve pencere sırası
	for side = -1, 1, 2 do
		part(ship, "Stripe", Vector3.new(0.6, 3, LEN - 4), rel(side * (D / 2 - 0.1), Y - 3, 0), TRIM)
		part(ship, "StripeThin", Vector3.new(0.6, 0.8, LEN - 4), rel(side * (D / 2 - 0.1), Y - 0.6, 0), TRIM)
		for z = -36, 36, 9 do
			cyl(ship, "WindowRim", rel(side * (D / 2 - 0.6), Y + 4, z), 1.2, 4.2, DARK)
			cyl(ship, "Window", rel(side * (D / 2 - 0.3), Y + 4, z), 1.2, 3.2, Color3.fromRGB(255, 236, 170),
				glow(Color3.fromRGB(255, 236, 170)))
		end
		-- Adı
		signBoard(ship, "ShipName", CFrame.lookAt((rel(side * (D / 2 + 0.4), Y + 10.5, -18)).Position,
			(rel(side * 40, Y + 10.5, -18)).Position), Vector2.new(30, 4), "S.S. CREWMATE", TRIM)
	end
	-- Kanatlar: geriye süpürülmüş, uçlarında kırmızı motor kapsülü ve ışık
	for side = -1, 1, 2 do
		local wing = rel(side * 30, Y - 6, -14) * CFrame.Angles(0, math.rad(side * 18), math.rad(side * -5))
		part(ship, "Wing", Vector3.new(36, 2.6, 30), wing, HULL2)
		part(ship, "WingEdge", Vector3.new(36, 1, 1.4), wing * CFrame.new(0, 0, -15.4), TRIM)
		local tip = rel(side * 49, Y - 6, -20)
		cyl(ship, "WingPod", alongZ(tip), 24, 6, TRIM)
		ball(ship, "WingPodNose", tip * CFrame.new(0, 0, 12), Vector3.new(6, 6, 6), TRIM)
		ball(ship, "WingLight", tip * CFrame.new(0, 0, 14.6), Vector3.one * 1.6,
			if side < 0 then Color3.fromRGB(255, 70, 70) else Color3.fromRGB(70, 255, 120),
			glow(if side < 0 then Color3.fromRGB(255, 70, 70) else Color3.fromRGB(70, 255, 120)))
	end
	-- Kuyruk kanadı
	local fin = rel(0, Y + 24, -40) * CFrame.Angles(math.rad(-20), 0, 0)
	part(ship, "Fin", Vector3.new(2.2, 22, 18), fin, HULL)
	part(ship, "FinTip", Vector3.new(2.4, 4, 18.4), fin * CFrame.new(0, 10, 0), TRIM)
	for side = -1, 1, 2 do
		part(ship, "TailWing", Vector3.new(16, 1.6, 10), rel(side * 9, Y + 12, -46) * CFrame.Angles(0, 0, math.rad(side * 12)), HULL2)
	end
	-- Motorlar
	local engines = { { 0, Y + 2, 16 }, { -13, Y - 6, 11 }, { 13, Y - 6, 11 } }
	for _, e in engines do
		local ex, ey, ed = e[1], e[2], e[3]
		local back = rel(ex, ey, -LEN / 2 - 6)
		cyl(ship, "Engine", alongZ(back), 16, ed, METAL)
		cyl(ship, "Nozzle", alongZ(back * CFrame.new(0, 0, -8.5)), 3, ed + 2, DARK)
		local g = cyl(ship, "EngineGlow", alongZ(back * CFrame.new(0, 0, -10.1)), 0.6, ed - 1.5, FLAME, glow(FLAME))
		cyl(ship, "EngineCore", alongZ(back * CFrame.new(0, 0, -10.3)), 0.6, ed * 0.45, Color3.fromRGB(140, 220, 255),
			glow(Color3.fromRGB(140, 220, 255)))
		light(g, FLAME, 26, 2)
	end
	-- Anten, radar çanağı, uyarı ışığı
	cyl(ship, "Antenna", alongY(rel(6, Y + 26, -14)), 10, 0.6, METAL)
	ball(ship, "AntennaTip", rel(6, Y + 31.4, -14), Vector3.one * 1.2, TRIM, glow(TRIM))
	cyl(ship, "DishPole", alongY(rel(-7, Y + 22, -22)), 5, 1, METAL)
	ball(ship, "Dish", rel(-7, Y + 25, -22) * CFrame.Angles(math.rad(-35), 0, 0), Vector3.new(9, 2.5, 9), HULL2)
	-- İniş ayakları
	for _, z in { -36, -4, 28 } do
		for side = -1, 1, 2 do
			local foot = c + Vector3.new(side * 13, 0, z)
			local top = c + Vector3.new(side * 9, Y - 13, z)
			local mid = (foot + top) / 2
			part(ship, "Leg", Vector3.new(1.8, (top - foot).Magnitude, 1.8), CFrame.lookAt(mid, top) * CFrame.Angles(math.rad(90), 0, 0), METAL)
			part(ship, "Piston", Vector3.new(1.1, (top - foot).Magnitude * 0.7, 1.1),
				CFrame.lookAt(mid + Vector3.new(0, 0, 1.6), top + Vector3.new(0, 0, 1.6)) * CFrame.Angles(math.rad(90), 0, 0), PANEL)
			cyl(ship, "Foot", alongY(CFrame.new(foot + Vector3.new(0, 0.5, 0))), 1, 6, DARK)
		end
	end

	-- Rampa: burnun altındaki kapıdan savunma çizgisine
	local doorZ = LEN / 2 - 2
	local top = c + Vector3.new(0, Y - 14, doorZ)
	local bottom = origin + Vector3.new(F.gate.X, 0.3, F.gate.Y)
	local len = (top - bottom).Magnitude
	local rampCf = CFrame.lookAt((top + bottom) / 2, bottom)
	part(ship, "Ramp", Vector3.new(12, 0.8, len), rampCf, PANEL)
	for k = -2, 2 do
		part(ship, "RampTread", Vector3.new(11, 0.2, 0.6), rampCf * CFrame.new(0, 0.5, k * len / 5), DARK)
	end
	for side = -1, 1, 2 do
		part(ship, "RampRail", Vector3.new(0.5, 0.5, len), rampCf * CFrame.new(side * 5.8, 2.4, 0), TRIM, glow(TRIM))
		for k = -2, 2, 2 do
			part(ship, "RailPost", Vector3.new(0.4, 2.4, 0.4), rampCf * CFrame.new(side * 5.8, 1.2, k * len / 5), METAL)
		end
	end
	local door = part(ship, "Door", Vector3.new(11, 0.4, 8), CFrame.new(top + Vector3.new(0, 0.2, -2)), Color3.fromRGB(255, 240, 200),
		glow(Color3.fromRGB(255, 240, 200), { CanCollide = false }))
	light(door, Color3.fromRGB(255, 230, 180), 30, 2)
end

-- ─── Dükkân gemicikleri ─────────────────────────────────────────────────────

type Stall = { kind: string, title: string, name: string, color: Color3, action: string, npc: string }

local STALLS: { [string]: Stall } = {
	hospital = { kind = "hospital", title = "✚ HOSPITAL", name = "HOSPITAL", color = Color3.fromRGB(255, 80, 90), action = "Visit", npc = "MedbayScan" },
	armory = { kind = "armory", title = "⚔ ARMORY", name = "ARMORY", color = Color3.fromRGB(255, 160, 50), action = "Upgrade", npc = "Sheriff" },
	shop = { kind = "shop", title = "🚀 COMMAND", name = "COMMAND SHOP", color = Color3.fromRGB(80, 160, 255), action = "Shop", npc = "Engineer" },
	market = { kind = "market", title = "☄ MARKET", name = "MARKET", color = Color3.fromRGB(180, 100, 255), action = "Buy", npc = "Jester" },
}

local function miniShip(model: Model, arena: number, origin: Vector3, at: Vector2, info: Stall)
	local p = origin + Vector3.new(at.X, 0, at.Y)
	-- Gövde z boyunca (ana gemiye paralel); yan kapak ana gemiye (x = 0) bakıyor
	local side = if at.X > 0 then -1 else 1
	local f = Instance.new("Model")
	f.Name = "Stall_" .. info.kind
	f.Parent = model
	local Y, D, LEN = 8, 12, 26
	local color = info.color
	local function rel(x: number, y: number, z: number): CFrame
		return CFrame.new(p + Vector3.new(x, y, z))
	end

	cyl(f, "Body", alongZ(rel(0, Y, 0)), LEN, D, HULL)
	ball(f, "Nose", rel(0, Y, LEN / 2), Vector3.new(D, D, 14), HULL)
	ball(f, "Tail", rel(0, Y, -LEN / 2), Vector3.new(D, D, 8), HULL2)
	ball(f, "Cockpit", rel(0, Y + 3, LEN / 2 + 1.5), Vector3.new(8, 5, 9), GLASS,
		{ Material = Enum.Material.Glass, Transparency = 0.2 })
	-- Renk bandı ve kuyruk
	cyl(f, "Band", alongZ(rel(0, Y, 4)), 5, D + 0.3, color)
	cyl(f, "Band2", alongZ(rel(0, Y, -6)), 2, D + 0.3, color)
	part(f, "Fin", Vector3.new(1.2, 8, 7), rel(0, Y + 8, -10) * CFrame.Angles(math.rad(-18), 0, 0), color)
	for s = -1, 1, 2 do
		part(f, "Wing", Vector3.new(9, 1.2, 8), rel(s * 9, Y - 2, -6) * CFrame.Angles(0, 0, math.rad(s * -8)), HULL2)
		local eng = rel(s * 3.6, Y - 1, -LEN / 2 - 3)
		cyl(f, "Engine", alongZ(eng), 6, 4, METAL)
		cyl(f, "EngineGlow", alongZ(eng * CFrame.new(0, 0, -3.1)), 0.4, 3, FLAME, glow(FLAME))
		for _, z in { -8, 8 } do
			local foot = p + Vector3.new(s * 4.5, 0, z)
			part(f, "Leg", Vector3.new(1, Y - 4, 1), CFrame.new(foot + Vector3.new(0, (Y - 4) / 2, 0)), METAL)
			cyl(f, "Foot", alongY(CFrame.new(foot + Vector3.new(0, 0.3, 0))), 0.6, 3, DARK)
		end
	end
	-- Yan kapak: dışa açılmış rampa-tezgâh
	local hatchX = side * (D / 2 + 0.2)
	part(f, "HatchFrame", Vector3.new(0.6, 7.4, 11.4), rel(hatchX, Y, 0), DARK)
	part(f, "HatchLight", Vector3.new(0.4, 6.4, 10.4), rel(hatchX + side * 0.15, Y, 0), Color3.fromRGB(255, 240, 210),
		glow(Color3.fromRGB(255, 240, 210), { CanCollide = false }))
	-- Platform: kapaktan yere inen kısa rampa ve önünde tezgâh
	local deckX = side * (D / 2 + 6)
	part(f, "Deck", Vector3.new(12, 0.8, 14), rel(deckX, 0.4, 0), PANEL)
	local counterX = side * (D / 2 + 10.5)
	part(f, "Counter", Vector3.new(2.4, 3.6, 12), rel(counterX, 2.6, 0), WHITE)
	local top = part(f, "CounterTop", Vector3.new(3, 0.5, 12.6), rel(counterX, 4.6, 0), color, glow(color))
	-- Tente (gövdeden dışa)
	for k = -2, 2 do
		part(f, "Awning", Vector3.new(11, 0.4, 2.6),
			rel(side * (D / 2 + 5.4), 10.6, k * 2.6) * CFrame.Angles(0, 0, math.rad(side * -12)),
			if k % 2 == 0 then color else WHITE)
	end
	-- Tabela: tentenin üstünde, ana gemiye dönük
	local signPos = p + Vector3.new(side * (D / 2 + 4), 15, 0)
	signBoard(f, "Sign", CFrame.lookAt(signPos, signPos + Vector3.new(side, 0, 0)), Vector2.new(13, 3.4), info.title, color)

	-- Tezgâhtar
	local ok, npc = pcall(UnitModel.Build, info.npc, nil)
	if ok and npc then
		npc.Name = "Keeper"
		for _, d in npc:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		local stand = p + Vector3.new(side * (D / 2 + 6.5), 0.8, 0)
		npc:PivotTo(CFrame.lookAt(stand, stand + Vector3.new(side, 0, 0)))
		npc.Parent = f
	end
	addPrompt(top, arena, info.kind, info.action, info.name, 0.2)

	-- Ne olduğu uzaktan belli olsun
	if info.kind == "hospital" then
		for _, s in { -1, 1 } do
			local crossAt = rel(s * (D / 2 + 0.1), Y + 1, -6)
			part(f, "CrossV", Vector3.new(0.4, 5, 1.6), crossAt, color, glow(color))
			part(f, "CrossH", Vector3.new(0.4, 1.6, 5), crossAt, color, glow(color))
		end
		part(f, "Bed", Vector3.new(4, 1.2, 7), rel(side * (D / 2 + 4), 1.4, -9.5), WHITE)
	elseif info.kind == "armory" then
		for k = -2, 2 do
			part(f, "Blade", Vector3.new(0.3, 4, 0.5), rel(counterX, 7.2, k * 2.2) * CFrame.Angles(0, 0, math.rad(10)),
				Color3.fromRGB(210, 220, 235), { Material = Enum.Material.Metal })
		end
	elseif info.kind == "market" then
		for k = -1, 1 do
			part(f, "Crate", Vector3.new(3, 3, 3), rel(side * (D / 2 + 4), 2.3, -10 + k * 0.2) * CFrame.new(0, 0, k * 3.4),
				Color3.fromRGB(170, 120, 70), { Material = Enum.Material.WoodPlanks })
		end
	else
		part(f, "Screen", Vector3.new(0.4, 4, 8), rel(side * (D / 2 + 0.5), Y + 1, -8), color, glow(color))
	end
	light(top, color, 20, 1.5)
end

-- ─── Konsollar ──────────────────────────────────────────────────────────────

local function console(model: Model, arena: number, origin: Vector3, at: Vector2, kind: string, action: string,
	object: string, color: Color3)
	local p = origin + Vector3.new(at.X, 0, at.Y)
	local f = Instance.new("Model")
	f.Name = "Console_" .. kind
	f.Parent = model
	part(f, "Base", Vector3.new(5, 3.4, 4), CFrame.new(p + Vector3.new(0, 1.7, 0)), METAL)
	local screen = part(f, "Screen", Vector3.new(5.4, 0.4, 4.2),
		CFrame.new(p + Vector3.new(0, 3.7, 0)) * CFrame.Angles(math.rad(-25), 0, 0), color, glow(color))
	cyl(f, "Pole", alongY(CFrame.new(p + Vector3.new(0, 6, 0))), 4.6, 0.4, METAL)
	ball(f, "Beacon", CFrame.new(p + Vector3.new(0, 8.6, 0)), Vector3.one * 1.4, color, glow(color))
	light(screen, color, 16, 2)
	signBoard(f, "Label", CFrame.lookAt(p + Vector3.new(0, 11, 0), p + Vector3.new(0, 11, -10)), Vector2.new(9, 2), object, color)
	addPrompt(screen, arena, kind, action, object, 0.25)
end

-- ─── Kurulum ────────────────────────────────────────────────────────────────

local function build(planet: number, arena: number): Model?
	local def = Config.SpaceMonsters[planet]
	if not def then
		return nil
	end
	local origin = DefenseConfig.WorldOrigin(arena)
	local model = Instance.new("Model")
	model.Name = "Arena_" .. arena
	model:SetAttribute("Planet", planet)
	model:SetAttribute("Arena", arena)
	-- Her arena aynı görünsün (aynı tohum)
	local rng = Random.new(planet * 7717)

	buildTerrain(origin, def, rng)
	buildDecor(model, origin, def, rng)
	buildShip(model, origin)

	local L = DefenseConfig.Layout
	console(model, arena, origin, L.command, "command", "Defend", "⚔ DEFEND", Color3.fromRGB(90, 230, 140))
	console(model, arena, origin, L.takeoff, "takeoff", "Take off", "🚀 TAKE OFF", Color3.fromRGB(120, 200, 255))
	miniShip(model, arena, origin, L.hospital, STALLS.hospital)
	miniShip(model, arena, origin, L.armory, STALLS.armory)
	miniShip(model, arena, origin, L.shop, STALLS.shop)
	miniShip(model, arena, origin, L.market, STALLS.market)

	local spawn = part(model, "Spawn", Vector3.new(6, 0.2, 6),
		CFrame.new(origin + Vector3.new(L.spawn.X, 0.1, L.spawn.Y)), Color3.fromRGB(120, 200, 255),
		{ Transparency = 1, CanCollide = false, CanQuery = false })
	spawn:SetAttribute("DefenseSpawn", true)

	model.PrimaryPart = spawn
	model.Parent = folder
	return model
end

--[[ Arenanın dünyası (yoksa şimdi kuruluyor). ]]
function PlanetWorldService.Get(planet: number, arena: number): Model?
	local existing = worlds[arena]
	if existing and existing.Parent then
		return existing
	end
	local model = build(planet, arena)
	if model then
		worlds[arena] = model
	end
	return model
end

--[[ Varış noktası (dünya CFrame'i), gemiye ve alana dönük. ]]
function PlanetWorldService.SpawnCFrame(arena: number): CFrame
	local L = DefenseConfig.Layout
	local p = DefenseConfig.ToWorld(arena, L.spawn, 4)
	return CFrame.lookAt(p, DefenseConfig.ToWorld(arena, Vector2.new(0, 60), 4))
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
