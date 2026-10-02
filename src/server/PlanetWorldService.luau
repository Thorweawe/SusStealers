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

-- ─── Elips gövde ────────────────────────────────────────────────────────────

--[[
	Roblox'un Ball şekli HER ZAMAN küre (en küçük kenar): eski gemilerde
	uzun gövdeler topa dönüşüyordu, "gemiler kötü" görünmesinin sebebi.
	Gerçek elips için blok + SpecialMesh(Sphere). Çarpışma kutu olduğundan
	gövdelerde kapalı; altına daha küçük, görünmez çarpışma kutuları.
]]
local function ellipsoid(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, props: Props?): Part
	local p = part(parent, name, size, cf, color, props)
	p.CanCollide = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function blocker(parent: Instance, cf: CFrame, size: Vector3)
	part(parent, "Collision", size, cf, WHITE, { Transparency = 1, CanQuery = false, CastShadow = false })
end

--[[
	3D ağlar (2026-10-02, Yusuf): ReplicatedStorage.DefenseMeshes (ChatGPT
	konsepti → TRELLIS → tools/normalize_meshes.lua; taban y=0, ortası
	x=z=0). Şablon varsa gemi/dükkân/dekor onunla giydiriliyor; yoksa
	aşağıdaki parça modeller aynen. Ağlar çarpışmasız: çarpışma yine
	görünmez "Collision" kutularında.
]]
local function meshTemplate(name: string): Model?
	local meshes = ReplicatedStorage:FindFirstChild("DefenseMeshes")
	local t = meshes and meshes:FindFirstChild(name)
	return if t and t:IsA("Model") then t else nil
end

-- Şablonun MeshPart'larını cf çerçevesine, k ölçeğinde kopyalar
local function skin(parent: Instance, template: Model, cf: CFrame, k: number?)
	local scale = k or 1
	for _, src in template:GetDescendants() do
		if not src:IsA("MeshPart") then
			continue
		end
		local p = src:Clone()
		for _, c in p:GetChildren() do
			if not (c:IsA("SurfaceAppearance") or c:IsA("Decal") or c:IsA("Texture")) then
				c:Destroy()
			end
		end
		p.Name = template.Name
		p.Size = src.Size * scale
		p.CFrame = cf * (src.CFrame.Rotation + src.CFrame.Position * scale)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Parent = parent
	end
end

-- Görünmez ışık kaynağı (dokulu ağın "parlayan" yerleri gerçekten ışık saçsın)
local function glowAt(parent: Instance, at: Vector3, color: Color3, range: number, brightness: number)
	local a = part(parent, "GlowLight", Vector3.one * 0.2, CFrame.new(at), color,
		{ Transparency = 1, CanCollide = false, CanQuery = false })
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = a
end

local function wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Anchored = true
	w.Material = Enum.Material.SmoothPlastic
	if props then
		for k, v in props do
			(w :: any)[k] = v
		end
	end
	w.Parent = parent
	return w
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
		-- Savaş alanı: "Grass" uzun ot süsü çıkarıyor (boyu koddan kısılamıyor:
		-- Terrain.GrassLength betiklere kapalı). Otsuz Sand, çimen renginde.
		T:SetMaterialColor(Enum.Material.Sand, patch:Lerp(Color3.fromRGB(255, 255, 255), 0.05))
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
	T:FillBlock(at(0, -2, (F.zMin + F.zMax) / 2 + 8), Vector3.new(F.halfWidth * 2 + 12, 4, fieldD), Enum.Material.Sand)
	-- Gemilerin indiği yer: yanık toprak
	T:FillBlock(at(0, -2, L.shipZ + 4), Vector3.new(200, 4, 160), Enum.Material.Ground)

	-- Kraterler (alan ve üs dışında): oyuk + taş kenar
	for _ = 1, 26 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(130, L.groundRadius - 90)
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		local inField = math.abs(x) < F.halfWidth + 24 and z > F.zMin - 20 and z < F.zMax + 60
		local nearBase = math.abs(x) < 140 and z < 45 and z > -160
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
		local nearBase = math.abs(x) < 140 and z < 45 and z > -150
		return not inField and not nearBase and (x * x + z * z) < (L.groundRadius - 60) ^ 2
	end

	local mushroom = meshTemplate("DecorMushroom")
	local crystal = meshTemplate("DecorCrystal")
	local rocks = meshTemplate("DecorRocks")

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
		if mushroom then
			-- Şablon 12 boyunda; ağaçlar 1.2–2.6 kat
			local k = h / 12 * 2
			skin(f, mushroom, CFrame.new(p) * CFrame.Angles(0, angle * 3, 0), k)
			if rng:NextNumber() < 0.35 then
				glowAt(f, p + Vector3.new(0, 12 * k * 0.6, 0), light_, 22, 1.2)
			end
			continue
		end
		cyl(f, "Stem", alongY(CFrame.new(p + Vector3.new(0, h / 2, 0))), h, h * 0.16, Color3.fromRGB(230, 225, 205))
		local capW = h * rng:NextNumber(0.7, 1.0)
		ellipsoid(f, "Cap", CFrame.new(p + Vector3.new(0, h, 0)), Vector3.new(capW, capW * 0.45, capW), light_:Lerp(WHITE, 0.15),
			{ Material = Enum.Material.SmoothPlastic })
		for k = 1, 4 do
			local a = k / 4 * math.pi * 2 + rng:NextNumber(0, 1)
			ball(f, "Spot", CFrame.new(p + Vector3.new(math.cos(a) * capW * 0.28, h + capW * 0.16, math.sin(a) * capW * 0.28)),
				Vector3.one * capW * 0.14, WHITE, glow(WHITE, { CanCollide = false }))
		end
		local glowPart = ellipsoid(f, "CapGlow", CFrame.new(p + Vector3.new(0, h - capW * 0.12, 0)), Vector3.new(capW * 0.8, capW * 0.2, capW * 0.8),
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
		if crystal then
			local k = rng:NextNumber(0.8, 1.6)
			skin(f, crystal, CFrame.new(p) * CFrame.Angles(0, angle * 5, 0), k)
			glowAt(f, p + Vector3.new(0, 4 * k, 0), light_, 14, 0.8)
			continue
		end
		--[[
			Kristal (Batur: "parlayan şeyler var, ne olduğu belli değil"):
			eskiden düz neon bloklardı, ışıltıyla beyaz kutulara dönüyordu.
			Şimdi renkli cam gövde + sivri uç; içte sönük parlayan çekirdek.
		]]
		local tint = light_:Lerp(Color3.fromRGB(120, 170, 255), 0.45)
		for _ = 1, rng:NextInteger(3, 6) do
			local h = rng:NextNumber(3, 9)
			local w = h * 0.3
			local cf = CFrame.new(p + Vector3.new(rng:NextNumber(-2, 2), h * 0.4, rng:NextNumber(-2, 2)))
				* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4))
			part(f, "CrystalShard", Vector3.new(w, h, w), cf, tint,
				{ Material = Enum.Material.Glass, Transparency = 0.3, Reflectance = 0.3 })
			local tipH = w * 1.3
			wedge(f, "CrystalTip", Vector3.new(w, tipH, w / 2), cf * CFrame.new(0, (h + tipH) / 2, -w / 4), tint,
				{ Material = Enum.Material.Glass, Transparency = 0.3, Reflectance = 0.3 })
			wedge(f, "CrystalTip", Vector3.new(w, tipH, w / 2), cf * CFrame.new(0, (h + tipH) / 2, w / 4) * CFrame.Angles(0, math.pi, 0), tint,
				{ Material = Enum.Material.Glass, Transparency = 0.3, Reflectance = 0.3 })
			part(f, "Crystal", Vector3.new(w * 0.35, h * 0.75, w * 0.35), cf, tint:Lerp(WHITE, 0.2),
				glow(tint:Lerp(WHITE, 0.2), { Transparency = 0.45, CanCollide = false }))
		end
	end

	-- Balçıklı kaya kümeleri (yalnız 3D ağ varsa; parça hâli terrain tepeleri)
	if rocks then
		for _ = 1, 30 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local radius = rng:NextNumber(80, L.groundRadius - 60)
			local x, z = math.cos(angle) * radius, math.sin(angle) * radius
			if free(x, z) then
				skin(f, rocks, CFrame.new(origin + Vector3.new(x, -0.4, z)) * CFrame.Angles(0, angle * 7, 0),
					rng:NextNumber(0.7, 1.8))
			end
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

-- 3D ana gemi: ağ geldiğinde Studio'da bakılarak ayarlandı
local SHIP_MESH_YAW = 0
local SHIP_MESH_OFFSET = Vector3.new(0, 0, 0)
local SHIP_KEEP = { Collision = true, Ramp = true, RampTread = true, RampRail = true, RailPost = true, Door = true }

local function buildShip(model: Model, origin: Vector3)
	local L = DefenseConfig.Layout
	local F = DefenseConfig.Field
	local ship = Instance.new("Model")
	ship.Name = "LandedShip"
	ship.Parent = model
	local c = origin + Vector3.new(0, 0, L.shipZ)
	local Y = 22           -- gövde ekseni
	local W, H, LEN = 30, 26, 118

	local function rel(x: number, y: number, z: number): CFrame
		return CFrame.new(c + Vector3.new(x, y, z))
	end
	-- Elips gövdenin z'deki yarı genişliği (pencere, tabela yerleşimi)
	local function halfWidth(z: number, y: number): number
		local k = 1 - (z / (LEN / 2)) ^ 2 - (y / (H / 2)) ^ 2
		return (W / 2) * math.sqrt(math.max(0, k))
	end

	-- Gövde katmanları
	ellipsoid(ship, "Fuselage", rel(0, Y, 0), Vector3.new(W, H, LEN), HULL)
	ellipsoid(ship, "Belly", rel(0, Y - 9, -2), Vector3.new(W - 4, 12, LEN - 16), HULL2)
	ellipsoid(ship, "Stripe", rel(0, Y - 2.5, 0), Vector3.new(W + 0.5, 2.6, LEN + 0.5), TRIM)
	ellipsoid(ship, "StripeThin", rel(0, Y + 1.2, 0), Vector3.new(W + 0.3, 0.8, LEN + 0.3), TRIM)
	ellipsoid(ship, "Deck", rel(0, Y + 9, -10), Vector3.new(22, 14, 78), HULL)
	-- Kokpit camı (üst önde) ve çerçevesi
	ellipsoid(ship, "CockpitRim", rel(0, Y + 7.6, 38), Vector3.new(20, 11, 30), DARK)
	ellipsoid(ship, "Cockpit", rel(0, Y + 8.2, 39), Vector3.new(18.6, 10, 28.6), GLASS,
		{ Material = Enum.Material.Glass, Transparency = 0.15, Reflectance = 0.25 })
	blocker(ship, rel(0, Y, 0), Vector3.new(W - 6, H - 6, LEN - 14))
	blocker(ship, rel(0, Y - 9, -2), Vector3.new(W - 10, 8, LEN - 28))

	-- Pencere sırası (gövdenin kavisine oturuyor)
	for side = -1, 1, 2 do
		for z = -40, 32, 8 do
			local hw = halfWidth(z, 3)
			if hw > 4 then
				local at = rel(side * (hw - 0.3), Y + 3, z) * CFrame.Angles(0, if side > 0 then 0 else math.rad(180), 0)
				cyl(ship, "WindowRim", at, 0.8, 3.6, DARK)
				cyl(ship, "Window", at * CFrame.new(0.25, 0, 0), 0.6, 2.8, Color3.fromRGB(255, 236, 170),
					glow(Color3.fromRGB(255, 236, 170), { CanCollide = false }))
			end
		end
		-- Adı
		local hw = halfWidth(-14, 9)
		local p = (rel(side * (hw + 0.3), Y + 9, -14)).Position
		signBoard(ship, "ShipName", CFrame.lookAt(p, p + Vector3.new(side, 0, 0)), Vector2.new(24, 3.6), "S.S. CREWMATE", TRIM)
	end

	-- Kanatlar: yuvarlak hatlı, geriye süpürülmüş; uçlarda kapsül ve ışık
	for side = -1, 1, 2 do
		local wing = rel(side * 27, Y - 5, -18) * CFrame.Angles(0, math.rad(side * 22), math.rad(side * -6))
		ellipsoid(ship, "Wing", wing, Vector3.new(40, 3, 26), HULL2)
		ellipsoid(ship, "WingEdge", wing * CFrame.new(0, 0.4, -9), Vector3.new(36, 2.4, 6), TRIM)
		local tip = rel(side * 46, Y - 4, -26)
		ellipsoid(ship, "WingPod", tip, Vector3.new(6, 6, 24), TRIM)
		cyl(ship, "WingPodGlow", alongZ(tip * CFrame.new(0, 0, -12.2)), 0.4, 3.6, FLAME, glow(FLAME))
		ball(ship, "WingLight", tip * CFrame.new(0, 0, 12.4), Vector3.one * 1.6,
			if side < 0 then Color3.fromRGB(255, 70, 70) else Color3.fromRGB(70, 255, 120),
			glow(if side < 0 then Color3.fromRGB(255, 70, 70) else Color3.fromRGB(70, 255, 120)))
	end
	-- Kuyruk kanadı ve yatay kanatçıklar
	local fin = rel(0, Y + 20, -44) * CFrame.Angles(math.rad(-24), 0, 0)
	ellipsoid(ship, "Fin", fin, Vector3.new(2.4, 24, 22), HULL)
	ellipsoid(ship, "FinStripe", fin * CFrame.new(0, 7, 0), Vector3.new(2.6, 6, 16), TRIM)
	for side = -1, 1, 2 do
		ellipsoid(ship, "TailWing", rel(side * 10, Y + 8, -48) * CFrame.Angles(0, math.rad(side * 15), math.rad(side * 10)),
			Vector3.new(18, 2, 11), HULL2)
	end
	-- Motorlar (arka)
	local engines = { { 0, Y + 3, 15 }, { -12, Y - 5, 10 }, { 12, Y - 5, 10 } }
	for _, e in engines do
		local ex, ey, ed = e[1], e[2], e[3]
		local back = rel(ex, ey, -LEN / 2 + 2)
		cyl(ship, "Engine", alongZ(back), 16, ed, METAL)
		cyl(ship, "EngineRing", alongZ(back * CFrame.new(0, 0, -4)), 1.2, ed + 1, TRIM)
		cyl(ship, "Nozzle", alongZ(back * CFrame.new(0, 0, -8.5)), 3, ed + 2, DARK)
		local g = cyl(ship, "EngineGlow", alongZ(back * CFrame.new(0, 0, -10.1)), 0.6, ed - 1.5, FLAME, glow(FLAME))
		cyl(ship, "EngineCore", alongZ(back * CFrame.new(0, 0, -10.3)), 0.6, ed * 0.45, Color3.fromRGB(140, 220, 255),
			glow(Color3.fromRGB(140, 220, 255)))
		light(g, FLAME, 26, 2)
	end
	-- Anten, radar çanağı
	cyl(ship, "Antenna", alongY(rel(5, Y + 21, -16)), 9, 0.6, METAL)
	ball(ship, "AntennaTip", rel(5, Y + 26, -16), Vector3.one * 1.2, TRIM, glow(TRIM))
	cyl(ship, "DishPole", alongY(rel(-6, Y + 18, -26)), 4, 1, METAL)
	ellipsoid(ship, "Dish", rel(-6, Y + 21, -26) * CFrame.Angles(math.rad(-35), 0, 0), Vector3.new(9, 2.4, 9), HULL2)
	-- İniş ayakları
	for _, z in { -38, -6, 26 } do
		for side = -1, 1, 2 do
			local foot = c + Vector3.new(side * 14, 0, z)
			local top = c + Vector3.new(side * 9, Y - 10, z)
			local mid = (foot + top) / 2
			part(ship, "Leg", Vector3.new(1.8, (top - foot).Magnitude, 1.8), CFrame.lookAt(mid, top) * CFrame.Angles(math.rad(90), 0, 0), METAL)
			cyl(ship, "Foot", alongY(CFrame.new(foot + Vector3.new(0, 0.5, 0))), 1, 6, DARK)
		end
	end

	-- Rampa: burnun altındaki kapıdan savunma çizgisine
	local top = c + Vector3.new(0, 12, 40)
	local bottom = origin + Vector3.new(F.gate.X, 0.3, F.gate.Y)
	local len = (top - bottom).Magnitude
	local rampCf = CFrame.lookAt((top + bottom) / 2, bottom)
	part(ship, "Ramp", Vector3.new(12, 0.8, len), rampCf, PANEL)
	for k = -3, 3 do
		part(ship, "RampTread", Vector3.new(11, 0.2, 0.6), rampCf * CFrame.new(0, 0.5, k * len / 7), DARK)
	end
	for side = -1, 1, 2 do
		part(ship, "RampRail", Vector3.new(0.5, 0.5, len), rampCf * CFrame.new(side * 5.8, 2.4, 0), TRIM, glow(TRIM))
		for k = -2, 2, 2 do
			part(ship, "RailPost", Vector3.new(0.4, 2.4, 0.4), rampCf * CFrame.new(side * 5.8, 1.2, k * len / 5), METAL)
		end
	end
	local door = part(ship, "Door", Vector3.new(11, 0.4, 9), CFrame.new(top + Vector3.new(0, 0.6, -3)), Color3.fromRGB(255, 240, 200),
		glow(Color3.fromRGB(255, 240, 200), { CanCollide = false }))
	light(door, Color3.fromRGB(255, 230, 180), 30, 2)

	-- 3D ağ: gövde/kanat/motor/ayak parçaları yerine; rampa, kapı ve
	-- çarpışma kutuları (yürünen yerler) kalıyor
	local mesh = meshTemplate("Mothership")
	if mesh then
		for _, d in ship:GetChildren() do
			if d:IsA("BasePart") and not SHIP_KEEP[d.Name] then
				d:Destroy()
			end
		end
		skin(ship, mesh, CFrame.new(c + SHIP_MESH_OFFSET) * CFrame.Angles(0, math.rad(SHIP_MESH_YAW), 0))
		for side = -1, 1, 2 do
			glowAt(ship, c + Vector3.new(side * 16, Y, -60), FLAME, 26, 2)
		end
	end
end

-- ─── Dükkân gemicikleri ─────────────────────────────────────────────────────

type Stall = { kind: string, title: string, name: string, color: Color3, action: string, npc: string }

local STALLS: { [string]: Stall } = {
	hospital = { kind = "hospital", title = "✚ HOSPITAL", name = "HOSPITAL", color = Color3.fromRGB(255, 80, 90), action = "Visit", npc = "MedbayScan" },
	armory = { kind = "armory", title = "⚔ ARMORY", name = "ARMORY", color = Color3.fromRGB(255, 160, 50), action = "Upgrade", npc = "Sheriff" },
	shop = { kind = "shop", title = "🚀 COMMAND", name = "COMMAND SHOP", color = Color3.fromRGB(80, 160, 255), action = "Shop", npc = "Engineer" },
	market = { kind = "market", title = "☄ MARKET", name = "MARKET", color = Color3.fromRGB(180, 100, 255), action = "Buy", npc = "Jester" },
}

--[[
	Küçük gemi. Yerel çerçeve: -Z = savaş alanına doğru (kapak, tezgâh,
	tabela o yüzde), gövde X ekseninde uzanıyor (burun +X). Dükkânlar alana
	bakıyor ve yay biçiminde dizili (DefenseConfig.Layout).
]]
local STALL_MESH: { [string]: string } = {
	hospital = "ShipHospital", armory = "ShipArmory", shop = "ShipShop", market = "ShipMarket",
}
local STALL_MESH_YAW = 0
local STALL_KEEP = { Deck = true, Counter = true, CounterTop = true, Sign = true }

local function miniShip(model: Model, arena: number, origin: Vector3, at: Vector2, info: Stall)
	local p = origin + Vector3.new(at.X, 0, at.Y)
	local facing = origin + Vector3.new(0, 0, DefenseConfig.Layout.shopsFace)
	local frame = CFrame.lookAt(p, Vector3.new(facing.X, p.Y, facing.Z))
	local f = Instance.new("Model")
	f.Name = "Stall_" .. info.kind
	f.Parent = model
	local color = info.color
	local Y = 8
	local function rel(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end

	-- Gövde
	ellipsoid(f, "Body", rel(0, Y, 0), Vector3.new(28, 12, 13), HULL)
	ellipsoid(f, "Belly", rel(-1, Y - 3.2, 0), Vector3.new(24, 6, 11), HULL2)
	ellipsoid(f, "Band", rel(0, Y - 0.6, 0), Vector3.new(28.4, 2.4, 13.4), color)
	ellipsoid(f, "Cockpit", rel(9, Y + 3.2, 0), Vector3.new(10, 6, 8.4), GLASS,
		{ Material = Enum.Material.Glass, Transparency = 0.15, Reflectance = 0.2 })
	ellipsoid(f, "Roof", rel(-3, Y + 4.8, 0), Vector3.new(14, 4, 8), HULL)
	-- Çarpışma: elips gövdeler kutu çarpıştığı için kapalı; altlarında
	-- gövdeyi saran görünmez kutular (Batur: "içinden geçebildiğimiz bloklar")
	blocker(f, rel(0, Y, 0), Vector3.new(26, 10.5, 11.6))
	blocker(f, rel(-1, Y - 3.2, 0), Vector3.new(21, 4, 9.5))
	blocker(f, rel(9, Y + 3.2, 0), Vector3.new(8, 4.5, 7))
	blocker(f, rel(-3, Y + 4.8, 0), Vector3.new(12, 3, 7))
	-- Kuyruk, kanatlar, motorlar
	ellipsoid(f, "Fin", rel(-11, Y + 6, 0) * CFrame.Angles(0, 0, math.rad(18)), Vector3.new(7, 9, 1.6), color)
	for s = -1, 1, 2 do
		ellipsoid(f, "Wing", rel(-4, Y - 2.5, s * 8) * CFrame.Angles(math.rad(s * 8), 0, 0), Vector3.new(11, 1.4, 8), HULL2)
		blocker(f, rel(-4, Y - 2.5, s * 8) * CFrame.Angles(math.rad(s * 8), 0, 0), Vector3.new(9, 1.2, 6.5))
		local eng = rel(-14.5, Y - 1, s * 3)
		cyl(f, "Engine", eng, 5, 4, METAL)
		cyl(f, "EngineGlow", eng * CFrame.new(-2.6, 0, 0), 0.4, 3, FLAME, glow(FLAME))
		for _, x in { -8, 8 } do
			local foot = (rel(x, 0, s * 4)).Position
			part(f, "Leg", Vector3.new(0.9, Y - 4, 0.9), CFrame.new(foot + Vector3.new(0, (Y - 4) / 2, 0)), METAL)
			cyl(f, "Foot", alongY(CFrame.new(foot + Vector3.new(0, 0.3, 0))), 0.6, 3, DARK)
		end
	end
	-- Kapak (alana dönük yüz) ve ışığı
	part(f, "HatchFrame", Vector3.new(11.6, 7.6, 0.6), rel(0, Y, -6.2), DARK)
	part(f, "HatchLight", Vector3.new(10.6, 6.6, 0.4), rel(0, Y, -6.4), Color3.fromRGB(255, 240, 210),
		glow(Color3.fromRGB(255, 240, 210), { CanCollide = false }))
	-- Platform, tezgâh, tente
	part(f, "Deck", Vector3.new(15, 0.8, 11), rel(0, 0.4, -11.5), PANEL)
	part(f, "Counter", Vector3.new(13, 3.6, 2.4), rel(0, 2.6, -16), WHITE)
	local counterTop = part(f, "CounterTop", Vector3.new(13.6, 0.5, 3), rel(0, 4.6, -16), color, glow(color))
	for k = -2, 2 do
		part(f, "Awning", Vector3.new(2.8, 0.4, 11), rel(k * 2.8, 11.4, -11.5) * CFrame.Angles(math.rad(14), 0, 0),
			if k % 2 == 0 then color else WHITE)
	end
	-- Tabela: çatının üstünde, alana dönük
	signBoard(f, "Sign", rel(0, 17.5, -2), Vector2.new(15, 3.6), info.title, color)
	cyl(f, "SignPole", alongY(rel(-5, 14.5, -2)), 3, 0.4, METAL)
	cyl(f, "SignPole", alongY(rel(5, 14.5, -2)), 3, 0.4, METAL)

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
		npc:PivotTo(rel(0, 0.8, -12))
		-- Ayakları güverteye otursun (modelin pivotu ayakta değil: toprağa gömülüyordu)
		local box, size = npc:GetBoundingBox()
		local bottom = box.Position.Y - size.Y / 2
		npc:PivotTo(npc:GetPivot() + Vector3.new(0, (p.Y + 0.8) - bottom, 0))
		npc.Parent = f
	end
	addPrompt(counterTop, arena, info.kind, info.action, info.name, 0.2)

	-- Ne olduğu uzaktan belli olsun
	if info.kind == "hospital" then
		for _, z in { -6.3, 6.3 } do
			local crossAt = rel(-6, Y + 1, z)
			part(f, "CrossV", Vector3.new(1.4, 4.6, 0.3), crossAt, color, glow(color, { CanCollide = false }))
			part(f, "CrossH", Vector3.new(4.6, 1.4, 0.3), crossAt, color, glow(color, { CanCollide = false }))
		end
		part(f, "Bed", Vector3.new(6, 1.2, 3.4), rel(-10, 1.4, -11), WHITE)
	elseif info.kind == "armory" then
		for k = -2, 2 do
			part(f, "Blade", Vector3.new(0.3, 4, 0.5), rel(k * 2.2, 7.2, -16) * CFrame.Angles(0, 0, math.rad(10)),
				Color3.fromRGB(210, 220, 235), { Material = Enum.Material.Metal })
		end
	elseif info.kind == "market" then
		for k = 0, 2 do
			part(f, "Crate", Vector3.new(3, 3, 3), rel(-10 + k * 0.4, 1.9 + k * 3, -11) * CFrame.Angles(0, k * 0.4, 0),
				Color3.fromRGB(170, 120, 70), { Material = Enum.Material.WoodPlanks })
		end
	else
		part(f, "Screen", Vector3.new(8, 4, 0.4), rel(-6, Y + 1, -6.6), color, glow(color, { CanCollide = false }))
	end
	-- Sönük ve beyaza yakın: renkli güçlü ışık gemiyi ve zemini pembeye boyuyordu
	light(counterTop, color:Lerp(WHITE, 0.6), 12, 0.6)

	-- 3D ağ: gövde ve süsler yerine; güverte, tezgâh (istem), tabela ve
	-- tezgâhtar kalıyor. Ağın vitrini -Z'de (alana dönük).
	local mesh = meshTemplate(STALL_MESH[info.kind])
	if mesh then
		for _, d in f:GetChildren() do
			if d:IsA("BasePart") and not STALL_KEEP[d.Name] then
				d:Destroy()
			end
		end
		skin(f, mesh, rel(0, 0, 0) * CFrame.Angles(0, math.rad(STALL_MESH_YAW), 0))
		local ext = mesh:GetExtentsSize()
		blocker(f, rel(0, ext.Y * 0.4, 0), Vector3.new(ext.X * 0.85, ext.Y * 0.75, ext.Z * 0.75))
		local sign = f:FindFirstChild("Sign")
		if sign and sign:IsA("BasePart") then
			sign.CFrame = rel(0, ext.Y + 2.5, -2)
		end
	end
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
	-- Tabela konsolun üstünde, küçük ve emojisiz (büyüğü ve ⚔ "bozuk" görünüyordu)
	signBoard(f, "Label", CFrame.lookAt(p + Vector3.new(0, 10, 0), p + Vector3.new(0, 10, -10)), Vector2.new(7, 1.6), object, color)
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
	-- Terrain yüzeyinin gerçek yüksekliği (voksel yuvarlaması; bkz. DefenseConfig.GroundLift)
	local lift = DefenseConfig.GroundLift
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(origin + Vector3.new(0, 40, 110), Vector3.new(0, -80, 0), params)
	if hit then
		lift = math.clamp(hit.Position.Y - origin.Y, -1, 4)
	end
	buildDecor(model, origin, def, rng)
	buildShip(model, origin)

	local L = DefenseConfig.Layout
	console(model, arena, origin, L.command, "command", "Defend", "DEFEND", Color3.fromRGB(90, 230, 140))
	console(model, arena, origin, L.takeoff, "takeoff", "Take off", "TAKE OFF", Color3.fromRGB(120, 200, 255))
	miniShip(model, arena, origin, L.hospital, STALLS.hospital)
	miniShip(model, arena, origin, L.armory, STALLS.armory)
	miniShip(model, arena, origin, L.shop, STALLS.shop)
	miniShip(model, arena, origin, L.market, STALLS.market)

	local spawn = part(model, "Spawn", Vector3.new(6, 0.2, 6),
		CFrame.new(origin + Vector3.new(L.spawn.X, 0.1, L.spawn.Y)), Color3.fromRGB(120, 200, 255),
		{ Transparency = 1, CanCollide = false, CanQuery = false })
	spawn:SetAttribute("DefenseSpawn", true)

	model.PrimaryPart = spawn
	-- Her şey kökte kuruldu; terrain yüzeyine oturt (gemiler, dükkânlar,
	-- tezgâhtarlar 2 stud gömülüydü)
	model:TranslateBy(Vector3.new(0, lift, 0))
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
	local p = DefenseConfig.ToWorld(arena, L.spawn, 4 + DefenseConfig.GroundLift)
	return CFrame.lookAt(p, DefenseConfig.ToWorld(arena, Vector2.new(0, 60), 4 + DefenseConfig.GroundLift))
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
