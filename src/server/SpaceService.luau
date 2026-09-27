--!strict
--[[
	Uzay yürüyüşü: kafeteryadaki hava kilidinden geminin dışına çıkılıyor,
	asteroit yağan kaya yolundan Void Beast yuvasına gidiliyor, balonlarda
	süzülen kayıp mürettebatlardan biri kapılıyor ve canavarlar kovalarken
	rıhtıma kaçılıyor. Rıhtıma varan karakter üssün boş kaidesine gidiyor.

	NEDEN: sunucuda kimse yokken çalma döngüsü tamamen kayboluyordu. Bu
	yol tek başına da oynanıyor; oyuncular varken ikinci bir kaynak.

	Parçalar:
	  Hava kilidi (gemi)  — workspace.SpaceAirlock: kafeteryanın kuzeydoğu
	                        köşe duvarında yuvarlak kapak + zemin pedi + prompt
	  Uzay alanı          — workspace.SpaceZone (kalıcı model): rıhtım, yol,
	                        yuva, balonlar, canavarlar. Çalışma anında kuruluyor.
	  Asteroitler         — DETERMİNİSTİK (shared/SpaceField): ağda konum
	                        gitmiyor, istemci çiziyor ve çarpmayı kendi
	                        ekranında görüp bildiriyor ("SpaceHit"), sunucu aynı
	                        formülle doğruluyor. Hile ile çarpmayı bildirmemek
	                        yalnızca oyunu kolaylaştırıyor, hiçbir şey vermiyor.
	  Canavarlar          — sunucuda: uyku → (kapınca) kükreme → kovalama →
	                        yakalarsa karakteri yuvaya geri alıyor → dönüş.

	Hız: StealService.applyWalkSpeed "InSpace"/"SpaceCarry" niteliklerine
	bakıp Config.Space hızlarını veriyor (tek yerde, koşma da orada).
	Yerçekimi istemcide (karakter fiziği oyuncunun makinesinde).

	Oyuncu nitelikleri:
	  InSpace     — uzay alanında
	  SpaceCarry  — kayıp mürettebat taşıyor (istemci arayüzü ve hız için)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SpaceField = require(Shared.SpaceField)
local UnitModel = require(Shared.UnitModel)

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local PromptGuard = require(script.Parent.PromptGuard)
local StealService = require(script.Parent.StealService)

local SpaceService = {}

SpaceService.NotifyKind = "steal"

type Spot = {
	index: number,
	position: Vector3,
	bubble: BasePart,
	prompt: ProximityPrompt,
	unitId: string?,
	mutationId: string?,
	model: Model?,
	emptySince: number?,
}

type Carry = {
	unitId: string,
	mutationId: string?,
	spot: number,
	model: Model,
}

type Monster = {
	model: Model,
	root: BasePart,
	parts: { BasePart },
	offsets: { CFrame },
	wiggle: { number },     -- parça başına dokunaç salınımı (0 = sabit)
	label: TextLabel,
	home: Vector3,
	position: Vector3,
	facing: Vector3,
	state: string,          -- "sleep" | "wake" | "chase" | "return"
	target: Player?,
	speed: number,
	wakeAt: number,
	lastSwipe: { [Player]: number },
}

local rng = Random.new()
local notifyRemote: RemoteEvent? = nil
local fxRemote: RemoteEvent? = nil

local zone: Model? = nil
local airlockPad: BasePart? = nil
local spots: { Spot } = {}
local monsters: { Monster } = {}
local carrying: { [Player]: Carry } = {}
local lastHit: { [Player]: number } = {}
local savedJump: { [Player]: number } = {}

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

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
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

local function ball(parent: Instance, name: string, diameter: number, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = part(parent, name, Vector3.one * diameter, cf, color, props)
	p.Shape = Enum.PartType.Ball
	return p
end

--[[ Uçan kalın yazı (FredokaOne + kontur); sunucuda CardKit yok. ]]
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
		s.Color = Color3.fromRGB(22, 20, 34)
		s.Thickness = math.max(2, line.size / 10)
		s.Parent = t
		t.Parent = gui
	end
end

local ROCK = Color3.fromRGB(84, 76, 98)
local ROCK_DARK = Color3.fromRGB(58, 52, 70)
local EDGE = Color3.fromRGB(90, 200, 255)
local HAZARD = Color3.fromRGB(255, 200, 40)
local METAL = Color3.fromRGB(150, 160, 176)

-- ─── Hava kilidi (gemide) ───────────────────────────────────────────────────

--[[
	Kafeteryanın kuzeydoğu pah duvarı (lobby.luau sekizgeni). İç yüzün
	hemen önüne yuvarlak kapak; önünde sarı-siyah ped ve prompt. Köprüden
	kafeteryaya giren oyuncu ilk bakışta görüyor.
]]
local function buildAirlock(): BasePart?
	local old = workspace:FindFirstChild("SpaceAirlock")
	if old then
		old:Destroy()
	end

	local cafX1, cafZ0, chamfer = 290, 242, 40
	local a = Vector3.new(cafX1 - chamfer, 0, cafZ0)
	local b = Vector3.new(cafX1, 0, cafZ0 + chamfer)
	local mid = (a + b) / 2
	local inward = Vector3.new(-1, 0, 1).Unit
	local wallFace = mid + inward * 1.4

	-- Zemin yüksekliği: kafeterya zeminine ışın
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { Players:GetPlayers() }
	local floorY = 0.5
	local hit = workspace:Raycast(wallFace + inward * 8 + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), params)
	if hit then
		floorY = hit.Position.Y
	end

	local model = Instance.new("Model")
	model.Name = "SpaceAirlock"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	local doorCenter = Vector3.new(wallFace.X, floorY + 8.5, wallFace.Z)
	local facing = CFrame.lookAt(doorCenter, doorCenter + inward)
	-- Disk: silindirin ekseni X; bakış yönüne çevir
	local disk = facing * CFrame.Angles(0, math.rad(90), 0)
	part(model, "HatchRing", Vector3.new(0.8, 17, 17), disk * CFrame.new(-0.1, 0, 0), HAZARD, { Shape = Enum.PartType.Cylinder })
	part(model, "HatchStripe", Vector3.new(0.9, 15.6, 15.6), disk * CFrame.new(0.05, 0, 0), Color3.fromRGB(28, 28, 34), { Shape = Enum.PartType.Cylinder })
	local hatch = part(model, "Hatch", Vector3.new(1, 13.6, 13.6), disk * CFrame.new(0.3, 0, 0), METAL, { Shape = Enum.PartType.Cylinder, Material = Enum.Material.DiamondPlate })
	part(model, "HatchWindow", Vector3.new(1.1, 6, 6), disk * CFrame.new(0.4, 1.5, 0), Color3.fromRGB(40, 120, 255), { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon })
	for i = 0, 7 do
		local ang = math.rad(i * 45)
		part(model, "HatchBolt", Vector3.new(1.3, 1, 1), disk * CFrame.new(0.45, math.cos(ang) * 5.6, math.sin(ang) * 5.6), Color3.fromRGB(60, 64, 72), { Shape = Enum.PartType.Cylinder })
	end
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(80, 170, 255)
	light.Range = 18
	light.Brightness = 1.6
	light.Parent = hatch

	-- Kapağın üstünde tabela
	local board = part(model, "AirlockSign", Vector3.new(16, 3.4, 0.4), facing * CFrame.new(0, 10.2, -0.2), Color3.fromRGB(24, 26, 40))
	sign(board, Enum.NormalId.Front, {
		{ text = "SPACE WALK", color = Color3.fromRGB(120, 220, 255), size = 68 },
	}, 12)
	-- Front yüzü -Z: lookAt'ın ileri yönü odaya bakıyor

	-- Zeminde ped: prompt burada
	local padCf = CFrame.lookAt(Vector3.new(doorCenter.X, floorY + 0.15, doorCenter.Z) + inward * 5, Vector3.new(doorCenter.X, floorY + 0.15, doorCenter.Z) + inward * 10)
	local pad = part(model, "AirlockPad", Vector3.new(12, 0.3, 8), padCf, Color3.fromRGB(34, 34, 40))
	part(model, "AirlockPadStripe", Vector3.new(11, 0.32, 1), padCf * CFrame.new(0, 0, 3.2), HAZARD, { Material = Enum.Material.Neon })
	part(model, "AirlockPadStripe", Vector3.new(11, 0.32, 1), padCf * CFrame.new(0, 0, -3.2), HAZARD, { Material = Enum.Material.Neon })

	model.PrimaryPart = hatch
	model.Parent = workspace
	return pad
end

-- ─── Uzay alanı ─────────────────────────────────────────────────────────────

local function buildMonster(parent: Instance, home: Vector3, index: number): Monster
	local model = Instance.new("Model")
	model.Name = "VoidBeast" .. index
	local origin = CFrame.new(home)
	local body = Color3.fromRGB(58, 26, 84)
	local skin = Color3.fromRGB(92, 40, 128)
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local wiggle: { number } = {}

	local function add(p: BasePart, offset: CFrame, w: number?)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		table.insert(parts, p)
		table.insert(offsets, offset)
		table.insert(wiggle, w or 0)
	end

	local root = ball(model, "Body", 16, origin, body)
	add(root, CFrame.new())
	add(ball(model, "Belly", 12, origin, Color3.fromRGB(170, 70, 255), { Material = Enum.Material.Neon, Transparency = 0.35 }), CFrame.new(0, -2.5, -3.2))
	-- Üç göz (ileri = -Z)
	for i, x in { -3.6, 0, 3.6 } do
		local y = if i == 2 then 4 else 2.6
		add(ball(model, "Eye", 3.4, origin, Color3.fromRGB(255, 236, 60), { Material = Enum.Material.Neon }), CFrame.new(x, y, -6.6))
		add(ball(model, "Pupil", 1.5, origin, Color3.fromRGB(20, 10, 20)), CFrame.new(x, y, -8.2))
	end
	-- Ağız ve dişler
	add(part(model, "Mouth", Vector3.new(9, 2.6, 2), origin, Color3.fromRGB(24, 6, 18)), CFrame.new(0, -2.2, -7))
	for i = -3, 3 do
		local tooth = Instance.new("WedgePart")
		tooth.Name = "Tooth"
		tooth.Size = Vector3.new(0.9, 1.4, 0.8)
		tooth.Color = Color3.fromRGB(245, 240, 230)
		tooth.Anchored = true
		tooth.Material = Enum.Material.SmoothPlastic
		tooth.Parent = model
		add(tooth, CFrame.new(i * 1.2, -1.3, -7.9) * CFrame.Angles(math.rad(180), 0, 0))
	end
	-- Sırt dikenleri
	for i = -2, 2 do
		local spike = Instance.new("WedgePart")
		spike.Name = "Spike"
		spike.Size = Vector3.new(1.2, 3.6, 3)
		spike.Color = skin
		spike.Anchored = true
		spike.Parent = model
		add(spike, CFrame.new(i * 2.4, 7.4 - math.abs(i) * 0.6, 1 + math.abs(i) * 0.4) * CFrame.Angles(math.rad(-20), 0, 0))
	end
	-- Dokunaçlar: altta halka, uçları parlak
	for i = 1, 6 do
		local ang = math.rad(i * 60)
		local base = CFrame.new(math.cos(ang) * 4.5, -6.5, math.sin(ang) * 4.5) * CFrame.Angles(0, -ang, 0)
		add(part(model, "Tentacle", Vector3.new(1.6, 8, 1.6), origin, skin), base * CFrame.new(0, -3, 0), 1)
		add(ball(model, "TentacleTip", 2, origin, Color3.fromRGB(255, 80, 200), { Material = Enum.Material.Neon }), base * CFrame.new(0, -7.2, 0), 1)
	end

	-- İsim etiketi
	local gui = Instance.new("BillboardGui")
	gui.Name = "BeastLabel"
	gui.Size = UDim2.fromOffset(200, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 12, 0)
	gui.MaxDistance = 220
	gui.LightInfluence = 0
	gui.Parent = root
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 26
	label.TextColor3 = Color3.fromRGB(200, 150, 255)
	label.Text = "VOID BEAST  zzz"
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(22, 10, 30)
	stroke.Parent = label

	model.PrimaryPart = root
	model.Parent = parent

	return {
		model = model,
		root = root,
		parts = parts,
		offsets = offsets,
		wiggle = wiggle,
		label = label,
		home = home,
		position = home,
		facing = Vector3.new(0, 0, 1),
		state = "sleep",
		target = nil,
		speed = Config.Space.MonsterSpeed,
		wakeAt = 0,
		lastSwipe = {},
	}
end

local function rollSpot(spot: Spot)
	local def = Config.RollUnit(rng, Config.Space.RollLevel)
	local mutation = Config.RollMutation(rng)
	spot.unitId = def.id
	spot.mutationId = if mutation then mutation.id else nil
	spot.emptySince = nil

	if spot.model then
		spot.model:Destroy()
	end
	local model = UnitModel.Build(def.id, spot.mutationId)
	model.Name = "StrandedCrew"
	model:PivotTo(CFrame.new(spot.position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, math.rad(180), 0))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	local label = UnitModel.BuildLabel(def.id, spot.mutationId)
	label.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
	label.Parent = model.PrimaryPart
	model.Parent = spot.bubble.Parent
	spot.model = model

	spot.bubble.Transparency = 0.15
	spot.prompt.ObjectText = def.name
	spot.prompt.Enabled = true
end

local function clearSpot(spot: Spot)
	spot.unitId = nil
	spot.mutationId = nil
	spot.emptySince = os.clock()
	if spot.model then
		spot.model:Destroy()
		spot.model = nil
	end
	spot.bubble.Transparency = 0.85
	spot.prompt.Enabled = false
end

--[[ Taşınan karakteri balonuna geri koyar (düşürme / yakalanma). ]]
local function restoreSpot(index: number, unitId: string, mutationId: string?)
	local spot = spots[index]
	if not spot then
		return
	end
	if spot.unitId then
		return -- bu arada yenisi gelmiş; eskisi uzayda kayboldu
	end
	clearSpot(spot)
	spot.emptySince = nil
	-- rollSpot yerine aynı karakter
	local model = UnitModel.Build(unitId, mutationId)
	model.Name = "StrandedCrew"
	model:PivotTo(CFrame.new(spot.position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, math.rad(180), 0))
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	local label = UnitModel.BuildLabel(unitId, mutationId)
	label.StudsOffsetWorldSpace = Vector3.new(0, 9, 0)
	label.Parent = model.PrimaryPart
	model.Parent = spot.bubble.Parent
	spot.model = model
	spot.unitId = unitId
	spot.mutationId = mutationId
	spot.bubble.Transparency = 0.15
	local def = Config.GetUnit(unitId)
	spot.prompt.ObjectText = if def then def.name else unitId
	spot.prompt.Enabled = true
end

local onGrab: (player: Player, spot: Spot) -> ()
local enterSpace: (player: Player) -> ()
local exitSpace: (player: Player) -> ()

local function buildZone(): Model
	local old = workspace:FindFirstChild("SpaceZone")
	if old then
		old:Destroy()
	end
	local s = Config.Space
	local O = s.Origin
	local model = Instance.new("Model")
	model.Name = "SpaceZone"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	local deco = Instance.new("Folder")
	deco.Name = "Deco"
	deco.Parent = model
	local detail = Random.new(1150)

	-- ─── Rıhtım ─────────────────────────────────────────────────────────
	local dock = part(model, "Dock", Vector3.new(s.DockHalf.X * 2, 2, s.DockHalf.Y * 2), CFrame.new(O + Vector3.new(0, -1, 0)), METAL,
		{ Material = Enum.Material.DiamondPlate })
	for _, x in { -1, 1 } do
		part(deco, "DockEdge", Vector3.new(1, 0.4, s.DockHalf.Y * 2), CFrame.new(O + Vector3.new(x * (s.DockHalf.X - 0.5), 0.2, 0)), HAZARD, { Material = Enum.Material.Neon })
		for z = -s.DockHalf.Y + 3, s.DockHalf.Y - 3, 8 do
			part(deco, "RailPost", Vector3.new(0.6, 4, 0.6), CFrame.new(O + Vector3.new(x * (s.DockHalf.X - 0.6), 2, z)), METAL)
		end
		part(deco, "Rail", Vector3.new(0.5, 0.5, s.DockHalf.Y * 2 - 4), CFrame.new(O + Vector3.new(x * (s.DockHalf.X - 0.6), 4, 0)), METAL)
	end
	part(deco, "DockMouth", Vector3.new(s.DockHalf.X * 2, 0.4, 1.2), CFrame.new(O + Vector3.new(0, 0.2, -s.DockHalf.Y + 0.6)), HAZARD, { Material = Enum.Material.Neon })

	-- Arkada gemiye dönüş kapısı
	local backZ = s.DockHalf.Y - 2
	part(deco, "GateL", Vector3.new(2, 16, 2), CFrame.new(O + Vector3.new(-9, 8, backZ)), METAL)
	part(deco, "GateR", Vector3.new(2, 16, 2), CFrame.new(O + Vector3.new(9, 8, backZ)), METAL)
	part(deco, "GateTop", Vector3.new(20, 2.4, 2), CFrame.new(O + Vector3.new(0, 16.4, backZ)), METAL)
	local portal = part(deco, "GatePortal", Vector3.new(16, 14.6, 0.4), CFrame.new(O + Vector3.new(0, 7.6, backZ + 0.4)), Color3.fromRGB(60, 150, 255),
		{ Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false })
	local console = part(model, "ReturnConsole", Vector3.new(4, 3.6, 2.4), CFrame.new(O + Vector3.new(0, 1.8, backZ - 5)), Color3.fromRGB(40, 44, 58))
	part(deco, "ConsoleScreen", Vector3.new(3.4, 1.6, 0.2), CFrame.new(O + Vector3.new(0, 3.2, backZ - 6.25)) * CFrame.Angles(math.rad(-25), 0, 0),
		Color3.fromRGB(80, 200, 255), { Material = Enum.Material.Neon })
	local returnPrompt = Instance.new("ProximityPrompt")
	returnPrompt.Name = "ReturnPrompt"
	returnPrompt.ActionText = "Back to Ship"
	returnPrompt.ObjectText = "Airlock"
	returnPrompt.HoldDuration = 0.3
	returnPrompt.MaxActivationDistance = 10
	returnPrompt.RequiresLineOfSight = false
	returnPrompt.Parent = console
	PromptGuard.Connect(returnPrompt, function(player)
		exitSpace(player)
	end)
	local portalLight = Instance.new("PointLight")
	portalLight.Color = Color3.fromRGB(80, 170, 255)
	portalLight.Range = 24
	portalLight.Brightness = 2
	portalLight.Parent = portal

	-- Rıhtımdaki bilgi tabelası (yola bakan oyuncunun solunda)
	local board = part(deco, "InfoBoard", Vector3.new(0.4, 9, 16), CFrame.new(O + Vector3.new(-s.DockHalf.X + 1.5, 6.5, 4)), Color3.fromRGB(24, 26, 40))
	sign(board, Enum.NormalId.Right, {
		{ text = "SPACE WALK", color = Color3.fromRGB(120, 220, 255), size = 64 },
		{ text = "1. Dodge the asteroids", color = Color3.new(1, 1, 1), size = 34 },
		{ text = "2. Grab a lost crewmate", color = Color3.new(1, 1, 1), size = 34 },
		{ text = "3. Outrun the Void Beasts!", color = Color3.fromRGB(255, 120, 200), size = 34 },
	}, 20)

	-- ─── Yol ────────────────────────────────────────────────────────────
	local W = s.PathHalfWidth
	for i, seg in s.Segments do
		local len = seg.z0 - seg.z1
		local cz = (seg.z0 + seg.z1) / 2
		local slab = part(model, "Path" .. i, Vector3.new(W * 2, 3, len), CFrame.new(O + Vector3.new(0, -1.5, cz)), ROCK,
			{ Material = Enum.Material.Rock })
		slab:SetAttribute("SpacePath", true)
		part(deco, "PathBelly", Vector3.new(W * 2 - 6, 6, len - 6), CFrame.new(O + Vector3.new(0, -5, cz)), ROCK_DARK, { Material = Enum.Material.Rock })
		-- Kenar ışıkları: karanlıkta yolun sınırı okunsun
		for _, x in { -1, 1 } do
			part(deco, "PathEdge", Vector3.new(0.6, 0.3, len - 1), CFrame.new(O + Vector3.new(x * (W - 0.5), 0.15, cz)), EDGE, { Material = Enum.Material.Neon })
		end
		-- Yanlarda süs kayalar
		for _ = 1, 4 do
			local size = detail:NextNumber(3, 7)
			local x = (if detail:NextNumber() < 0.5 then -1 else 1) * detail:NextNumber(W - 2, W + 3)
			local z = detail:NextNumber(seg.z1 + 4, seg.z0 - 4)
			part(deco, "Boulder", Vector3.new(size, size * 0.7, size * 1.1), CFrame.new(O + Vector3.new(x, size * 0.25, z))
				* CFrame.Angles(detail:NextNumber(0, 1), detail:NextNumber(0, 6), detail:NextNumber(0, 1)), ROCK_DARK, { Material = Enum.Material.Rock })
		end
	end

	-- Asteroit şeritlerinin yol üstündeki uyarı çizgisi istemcide (SpaceFX); burada yok.

	-- ─── Yuva ───────────────────────────────────────────────────────────
	local nest = SpaceField.NestCenter()
	local nestSlab = part(model, "Nest", Vector3.new(4, s.NestRadius * 2, s.NestRadius * 2), CFrame.new(nest + Vector3.new(0, -2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(66, 40, 84), { Material = Enum.Material.Rock, Shape = Enum.PartType.Cylinder })
	nestSlab:SetAttribute("SpacePath", true)
	part(deco, "NestBelly", Vector3.new(14, s.NestRadius * 2 - 16, s.NestRadius * 2 - 16), CFrame.new(nest + Vector3.new(0, -10, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		ROCK_DARK, { Material = Enum.Material.Rock, Shape = Enum.PartType.Cylinder })
	-- Kenar halkası: zeminin biraz altında, yalnızca dış kuşağı görünüyor
	part(deco, "NestRim", Vector3.new(0.5, s.NestRadius * 2 + 2, s.NestRadius * 2 + 2), CFrame.new(nest + Vector3.new(0, -0.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(190, 80, 255), { Material = Enum.Material.Neon, Shape = Enum.PartType.Cylinder, CanCollide = false })
	-- Kristaller ve yapışkan birikintiler
	for i = 1, 14 do
		local a = math.rad(i * (360 / 14) + detail:NextNumber(-8, 8))
		local r = s.NestRadius - detail:NextNumber(3, 8)
		local h = detail:NextNumber(5, 12)
		local crystal = part(deco, "Crystal", Vector3.new(2.4, h, 2.4), CFrame.new(nest + Vector3.new(math.sin(a) * r, h / 2 - 0.5, math.cos(a) * r))
			* CFrame.Angles(detail:NextNumber(-0.3, 0.3), a, detail:NextNumber(-0.3, 0.3)),
			Color3.fromRGB(180, 90, 255), { Material = Enum.Material.Neon, Transparency = 0.1 })
		if i % 3 == 0 then
			local l = Instance.new("PointLight")
			l.Color = Color3.fromRGB(190, 110, 255)
			l.Range = 22
			l.Brightness = 1.4
			l.Parent = crystal
		end
	end
	for _ = 1, 6 do
		local a = detail:NextNumber(0, math.pi * 2)
		local r = detail:NextNumber(8, s.NestRadius - 14)
		part(deco, "Goo", Vector3.new(0.3, detail:NextNumber(5, 9), detail:NextNumber(5, 9)), CFrame.new(nest + Vector3.new(math.sin(a) * r, 0.1, math.cos(a) * r))
			* CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(120, 255, 120), { Material = Enum.Material.Neon, Transparency = 0.3, Shape = Enum.PartType.Cylinder, CanCollide = false })
	end
	local nestSign = part(deco, "NestSign", Vector3.new(14, 4, 0.4), CFrame.new(nest + Vector3.new(0, 14, s.NestRadius - 6)) * CFrame.Angles(0, math.rad(180), 0), Color3.fromRGB(40, 16, 50))
	sign(nestSign, Enum.NormalId.Back, { { text = "VOID BEAST NEST", color = Color3.fromRGB(255, 120, 200), size = 60 } }, 14)

	-- ─── Balonlar ───────────────────────────────────────────────────────
	local spotFolder = Instance.new("Folder")
	spotFolder.Name = "Spots"
	spotFolder.Parent = model
	table.clear(spots)
	for i, pos in SpaceField.SpotPositions() do
		local holder = Instance.new("Model")
		holder.Name = "Spot" .. i
		holder.Parent = spotFolder
		local bubble = ball(holder, "Bubble", 9, CFrame.new(pos), Color3.fromRGB(140, 220, 255),
			{ Material = Enum.Material.ForceField, CanCollide = false, CastShadow = false })
		part(holder, "Beam", Vector3.new(0.4, pos.Y - nest.Y, 0.4), CFrame.new(Vector3.new(pos.X, (pos.Y + nest.Y) / 2 - 2, pos.Z)),
			Color3.fromRGB(140, 220, 255), { Material = Enum.Material.Neon, Transparency = 0.5, CanCollide = false })
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "RescuePrompt"
		prompt.ActionText = "Grab"
		prompt.ObjectText = ""
		prompt.HoldDuration = Config.Space.GrabHold
		prompt.MaxActivationDistance = 11
		prompt.RequiresLineOfSight = false
		prompt.Parent = bubble
		local spot: Spot = { index = i, position = pos, bubble = bubble, prompt = prompt }
		spots[i] = spot
		PromptGuard.Connect(prompt, function(player)
			onGrab(player, spot)
		end)
		rollSpot(spot)
	end

	-- ─── Canavarlar ─────────────────────────────────────────────────────
	local monsterFolder = Instance.new("Folder")
	monsterFolder.Name = "Monsters"
	monsterFolder.Parent = model
	for _, m in monsters do
		m.model:Destroy()
	end
	table.clear(monsters)
	for i, home in SpaceField.MonsterHomes() do
		table.insert(monsters, buildMonster(monsterFolder, home, i))
	end

	-- Uzakta süzülen dev kayalar (manzara)
	for _ = 1, 26 do
		local size = detail:NextNumber(8, 26)
		local p = O + Vector3.new(detail:NextNumber(-260, 260), detail:NextNumber(-120, 90), detail:NextNumber(-520, 120))
		if math.abs(p.X - O.X) < 60 and p.Y > O.Y - 40 then
			p += Vector3.new(if p.X > O.X then 80 else -80, 0, 0)
		end
		part(deco, "FarRock", Vector3.new(size, size * detail:NextNumber(0.6, 1), size * detail:NextNumber(0.7, 1.3)), CFrame.new(p)
			* CFrame.Angles(detail:NextNumber(0, 6), detail:NextNumber(0, 6), detail:NextNumber(0, 6)), ROCK_DARK,
			{ Material = Enum.Material.Rock, CanCollide = false, CastShadow = false })
	end

	model.PrimaryPart = dock
	model.Parent = workspace
	return model
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
	model:PivotTo(root.CFrame * CFrame.new(0, 3.5, 0.4))
	local primary = model.PrimaryPart :: BasePart
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
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

local function monstersForget(player: Player)
	for _, m in monsters do
		if m.target == player then
			m.target = nil
			if m.state == "chase" or m.state == "wake" then
				m.state = "return"
			end
		end
	end
end

--[[ Taşınanı düşürür: karakter balonuna döner. ]]
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
	restoreSpot(carry.spot, carry.unitId, carry.mutationId)
	monstersForget(player)
	StealService.RefreshSpeed(player)
end

--[[ Uzaydaki oyuncuyu savurur (istemci uyguluyor). ]]
local function knock(player: Player, from: Vector3, strength: number, stun: number)
	lastHit[player] = os.clock()
	fx(player, "knock", from, strength, stun)
end

function onGrab(player: Player, spot: Spot)
	if not player:GetAttribute("InSpace") then
		return
	end
	if carrying[player] then
		notify(player, "You're already carrying one - run to the airlock!", true)
		return
	end
	if not spot.unitId then
		return
	end
	local plot = PlotService.GetPlotOf(player)
	if not plot then
		notify(player, "You need a base first", true)
		return
	end
	if not PlotService.FindEmptyPodium(plot) then
		notify(player, "No free podium - make room first", true)
		return
	end
	local unitId, mutationId = spot.unitId :: string, spot.mutationId
	local model = attachToBack(player, unitId, mutationId)
	if not model then
		return
	end
	clearSpot(spot)
	-- Taşınırken balon yenilenmiyor: düşürülürse aynı karakter geri dönüyor
	spot.emptySince = nil
	carrying[player] = { unitId = unitId, mutationId = mutationId, spot = spot.index, model = model }
	player:SetAttribute("SpaceCarry", true)
	StealService.RefreshSpeed(player)

	local def = Config.GetUnit(unitId)
	notify(player, string.format("Grabbed %s! RUN to the airlock!", if def then def.name else unitId), false, "steal")

	-- Yuvadaki canavarlar uyanıyor: kısa kükreme, sonra kovalama
	local now = os.clock()
	local root = rootOf(player)
	for _, m in monsters do
		if m.state == "sleep" or m.state == "return" then
			m.state = "wake"
			m.target = player
			m.wakeAt = now + Config.Space.MonsterWakeDelay
			m.speed = Config.Space.MonsterSpeed
		end
	end
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("InSpace") then
			fx(other, "roar", SpaceField.NestCenter(), if root then root.Position else SpaceField.NestCenter())
		end
	end
end

local function deliver(player: Player)
	local carry = carrying[player]
	if not carry then
		return
	end
	local plot = PlotService.GetPlotOf(player)
	local podium = plot and PlotService.FindEmptyPodium(plot)
	if not podium then
		notify(player, "No free podium! It floated back to the nest", true)
		drop(player)
		return
	end
	carrying[player] = nil
	if carry.model.Parent then
		carry.model:Destroy()
	end
	player:SetAttribute("SpaceCarry", nil)
	PlotService.PlaceUnit(podium, carry.unitId, carry.mutationId)
	-- Balon artık yeni bir kayıp mürettebat bekliyor
	local spot = spots[carry.spot]
	if spot and not spot.unitId then
		spot.emptySince = os.clock()
	end
	monstersForget(player)
	StealService.RefreshSpeed(player)

	local profile = DataService.Get(player)
	if profile then
		profile.salvaged = (profile.salvaged or 0) + 1
	end
	local def = Config.GetUnit(carry.unitId)
	local name = if def then def.name else carry.unitId
	notify(player, string.format("Rescued %s! It's on your podium", name), false, "deposit")
	fx(player, "delivered", name)
end

-- ─── Giriş / çıkış ──────────────────────────────────────────────────────────

function enterSpace(player: Player)
	if player:GetAttribute("InSpace") then
		return
	end
	if StealService.IsCarrying(player) then
		notify(player, "Bring your loot home first!", true)
		return
	end
	local character = player.Character
	local humanoid = humanoidOf(player)
	if not (character and humanoid and humanoid.Health > 0) then
		return
	end
	local spawn = SpaceField.DockSpawn()
	pcall(function()
		player:RequestStreamAroundAsync(spawn.Position, 3)
	end)
	savedJump[player] = humanoid.JumpHeight
	humanoid.JumpHeight = Config.Space.JumpHeight
	player:SetAttribute("InSpace", true)
	character:PivotTo(spawn)
	StealService.RefreshSpeed(player)
	fx(player, "enter")
end

function exitSpace(player: Player)
	if not player:GetAttribute("InSpace") then
		return
	end
	drop(player)
	player:SetAttribute("InSpace", nil)
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.JumpHeight = savedJump[player] or 7.2
	end
	savedJump[player] = nil
	local character = player.Character
	if character and airlockPad then
		local look = airlockPad.CFrame.LookVector
		local p = airlockPad.Position + look * 4 + Vector3.new(0, 3.5, 0)
		character:PivotTo(CFrame.lookAt(p, p + look))
	end
	StealService.RefreshSpeed(player)
	fx(player, "exit")
end

-- ─── Döngü ──────────────────────────────────────────────────────────────────

local function nearestCarrier(from: Vector3): (Player?, BasePart?)
	local best: Player? = nil
	local bestRoot: BasePart? = nil
	local bestDist = math.huge
	for player in carrying do
		local root = rootOf(player)
		if root then
			local d = (root.Position - from).Magnitude
			if d < bestDist then
				best, bestRoot, bestDist = player, root, d
			end
		end
	end
	return best, bestRoot
end

local clock = 0

local function stepMonsters(dt: number)
	clock += dt
	local s = Config.Space
	local now = os.clock()
	local dockEdgeZ = s.Origin.Z - s.DockHalf.Y - 8

	for index, m in monsters do
		local goal = m.home
		local speed = s.MonsterReturnSpeed

		if m.state == "wake" then
			goal = m.position
			if now >= m.wakeAt then
				m.state = "chase"
			end
		end

		if m.state == "chase" then
			local target = m.target
			local root = target and carrying[target] and rootOf(target)
			if not (target and root) then
				-- Hedef düştü/teslim etti: başka taşıyan varsa ona, yoksa eve
				local other, otherRoot = nearestCarrier(m.position)
				if other and otherRoot then
					m.target = other
					root = otherRoot
				else
					m.state = "return"
					m.target = nil
				end
			end
			if m.state == "chase" and root then
				-- Kalabalık olmasın: her canavar hedefin biraz yanına
				local side = (index - (#monsters + 1) / 2) * 5
				goal = root.Position + Vector3.new(side, 5, 0)
				m.speed = math.min(s.MonsterMaxSpeed, m.speed + s.MonsterAccel * dt)
				speed = m.speed
				local target2 = m.target :: Player
				-- Yakaladı mı
				if (m.position - root.Position).Magnitude <= s.MonsterCatchRadius + 5 and not SpaceField.InDock(root.Position) then
					local def = carrying[target2] and Config.GetUnit(carrying[target2].unitId)
					drop(target2)
					knock(target2, m.position, s.MonsterKnock, s.MonsterStun)
					notify(target2, string.format("The Void Beast snatched %s back!", if def then def.name else "it"), true)
					m.state = "return"
					m.target = nil
				end
			end
		end

		if m.state == "return" and (m.position - m.home).Magnitude < 2 then
			m.state = "sleep"
			m.speed = s.MonsterSpeed
		end

		-- Hareket
		local delta = goal - m.position
		if m.state ~= "sleep" and m.state ~= "wake" and delta.Magnitude > 0.05 then
			local step = math.min(delta.Magnitude, speed * dt)
			local nextPos = m.position + delta.Unit * step
			-- Rıhtıma giremez
			if nextPos.Z > dockEdgeZ then
				nextPos = Vector3.new(nextPos.X, nextPos.Y, dockEdgeZ)
			end
			m.position = nextPos
			local flat = Vector3.new(delta.X, 0, delta.Z)
			if flat.Magnitude > 0.1 then
				m.facing = m.facing:Lerp(flat.Unit, math.min(1, dt * 6))
			end
		end

		-- Uyurken yakındaki boş elli oyuncuyu savuruyor; yüzünü en yakına dönüyor
		if m.state == "sleep" then
			local nearest: Vector3? = nil
			local nearestD = 60
			for _, player in Players:GetPlayers() do
				local root = player:GetAttribute("InSpace") and rootOf(player)
				if root then
					local d = (root.Position - m.position).Magnitude
					if d < nearestD then
						nearest, nearestD = root.Position, d
					end
					local flatD = Vector3.new(root.Position.X - m.position.X, 0, root.Position.Z - m.position.Z).Magnitude
					if flatD <= s.MonsterSwipeRadius and not carrying[player] and now - (m.lastSwipe[player] or 0) >= s.MonsterSwipeCooldown then
						m.lastSwipe[player] = now
						knock(player, m.position, s.AsteroidKnock, s.AsteroidStun)
					end
				end
			end
			if nearest then
				local flat = Vector3.new(nearest.X - m.position.X, 0, nearest.Z - m.position.Z)
				if flat.Magnitude > 0.1 then
					m.facing = m.facing:Lerp(flat.Unit, math.min(1, dt * 2))
				end
			end
		end

		-- Çizim: gövde salınımı, uyanınca titreme, dokunaç dalgası
		local bob = math.sin(clock * 1.6 + index) * (if m.state == "sleep" then 1.2 else 0.6)
		local shake = if m.state == "wake" then Vector3.new(math.sin(clock * 50) * 0.5, 0, math.cos(clock * 43) * 0.5) else Vector3.zero
		local base = CFrame.lookAt(m.position, m.position + m.facing) + Vector3.new(0, bob, 0) + shake
		local cframes = table.create(#m.parts)
		for i, offset in m.offsets do
			if m.wiggle[i] ~= 0 then
				local sway = math.sin(clock * (if m.state == "chase" then 9 else 3) + i * 0.7) * 0.35
				cframes[i] = base * offset * CFrame.Angles(sway, 0, sway * 0.5)
			else
				cframes[i] = base * offset
			end
		end
		workspace:BulkMoveTo(m.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

		local text = if m.state == "chase" or m.state == "wake" then "VOID BEAST!" else "VOID BEAST  zzz"
		if m.label.Text ~= text then
			m.label.Text = text
			-- İstemci (SpaceFX) tehlike kenarını buna göre yakıyor
			m.model:SetAttribute("Chasing", if m.state == "chase" or m.state == "wake" then true else nil)
			m.label.TextColor3 = if m.state == "sleep" or m.state == "return" then Color3.fromRGB(200, 150, 255) else Color3.fromRGB(255, 70, 90)
		end
	end
end

local function stepPlayers()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		if not player:GetAttribute("InSpace") then
			continue
		end
		local root = rootOf(player)
		if not root then
			continue
		end
		-- Başka yoldan gemiye dönmüş (ışınlanma vb.): durumu temizle
		if (root.Position - Config.Space.Origin).Magnitude > 900 then
			drop(player)
			player:SetAttribute("InSpace", nil)
			local humanoid = humanoidOf(player)
			if humanoid then
				humanoid.JumpHeight = savedJump[player] or 7.2
			end
			savedJump[player] = nil
			StealService.RefreshSpeed(player)
			fx(player, "exit")
			continue
		end
		if SpaceField.Fell(root.Position) then
			local had = carrying[player] ~= nil
			drop(player)
			local character = player.Character
			if character then
				character:PivotTo(SpaceField.DockSpawn())
				root.AssemblyLinearVelocity = Vector3.zero
			end
			notify(player, if had then "Lost in space! The crewmate floated back to the nest" else "Lost in space! Back to the dock", true)
			continue
		end
		if carrying[player] and SpaceField.InDock(root.Position) then
			deliver(player)
		end
	end

	-- Boş balonlar dolsun
	for _, spot in spots do
		if not spot.unitId and spot.emptySince and now - spot.emptySince >= Config.Space.SpotRespawn then
			rollSpot(spot)
		end
	end
end

-- ─── Çarpma bildirimi ───────────────────────────────────────────────────────

local function onHit(player: Player, laneIndex: any, t: any)
	if typeof(laneIndex) ~= "number" or typeof(t) ~= "number" or laneIndex ~= laneIndex or t ~= t then
		return
	end
	if not player:GetAttribute("InSpace") then
		return
	end
	local now = os.clock()
	if now - (lastHit[player] or 0) < Config.Space.HitImmunity * 0.8 then
		return
	end
	local serverNow = workspace:GetServerTimeNow()
	if t < serverNow - 1.5 or t > serverNow + 0.5 then
		return
	end
	local root = rootOf(player)
	if not root then
		return
	end
	if not SpaceField.CameNear(math.floor(laneIndex), t - 0.4, t + 0.2, root.Position, Config.Space.HitTolerance) then
		return
	end
	lastHit[player] = now
	if carrying[player] then
		drop(player)
		notify(player, "Asteroid hit! You dropped the crewmate", true)
	end
end

-- ─── Testler için ───────────────────────────────────────────────────────────

function SpaceService._Enter(player: Player)
	enterSpace(player)
end

function SpaceService._Exit(player: Player)
	exitSpace(player)
end

function SpaceService._Grab(player: Player, index: number)
	local spot = spots[index]
	if spot then
		onGrab(player, spot)
	end
end

function SpaceService._Deliver(player: Player)
	deliver(player)
end

function SpaceService._Drop(player: Player)
	drop(player)
end

function SpaceService._Spot(index: number): (string?, string?)
	local spot = spots[index]
	if not spot then
		return nil, nil
	end
	return spot.unitId, spot.mutationId
end

function SpaceService._Monsters(): { { state: string, target: Player? } }
	local list = {}
	for _, m in monsters do
		table.insert(list, { state = m.state, target = m.target })
	end
	return list
end

function SpaceService.IsCarrying(player: Player): boolean
	return carrying[player] ~= nil
end

function SpaceService.GetAirlock(): BasePart?
	return airlockPad
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

function SpaceService.Start()
	notifyRemote = Net.Get("Notify")
	fxRemote = Net.Get("SpaceFX")

	zone = buildZone()
	airlockPad = buildAirlock()
	if airlockPad then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "AirlockPrompt"
		prompt.ActionText = "Space Walk"
		prompt.ObjectText = "Airlock"
		prompt.HoldDuration = 0.4
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.Parent = airlockPad
		PromptGuard.Connect(prompt, function(player)
			enterSpace(player)
		end)
	end

	Net.Get("SpaceHit").OnServerEvent:Connect(onHit)

	RunService.Heartbeat:Connect(function(dt)
		if #monsters > 0 then
			stepMonsters(dt)
		end
		stepPlayers()
	end)

	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			-- Yeniden doğan uzayda değil; taşıdığı balonuna döner
			drop(player)
			player:SetAttribute("InSpace", nil)
			player:SetAttribute("SpaceCarry", nil)
			savedJump[player] = nil
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		drop(player)
		lastHit[player] = nil
		savedJump[player] = nil
		for _, m in monsters do
			m.lastSwipe[player] = nil
		end
	end)
end

return SpaceService
