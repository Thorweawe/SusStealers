--!strict
--[[
	Gezegen savunmasının 3B çizimi (DefenseClient çağırıyor). Savaş sunucuda
	dönüyor (DefenseService + DefenseSim); buraya yalnızca bu oyuncunun
	olayları geliyor ve her şey İSTEMCİDE kuruluyor: başka oyuncular senin
	düşmanlarını görmüyor, sen de onlarınkini.

	  Crewmate'ler  — UnitModel, sahadaki yerinde; üstünde rol simgesi ve can
	  Düşmanlar     — EnemyModel, gezegenin renginde; anlık görüntüler
	                  arasında yumuşak geçiş (SEND aralığı)
	  Yol önizlemesi — dalga başlamadan düşmanın geleceği yol (oklar)
	  Efektler      — atış, bıçak, yumruk, iyileştirme, ölüm, sızıntı, destekler
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DefenseConfig = require(Shared.DefenseConfig)
local DefenseSim = require(Shared.DefenseSim)
local EnemyModel = require(Shared.EnemyModel)
local MonsterModel = require(Shared.MonsterModel)
local UnitModel = require(Shared.UnitModel)

local SoundFX = require(script.Parent.SoundFX)

local DefenseFX = {}

-- Crewmate'lerin sahadaki boyu (stud) ve düşmanların büyütme çarpanı
local UNIT_HEIGHT = 7.5
local ENEMY_SCALE = 1.8
local SNAP_GAP = 0.2          -- sunucunun anlık görüntü aralığı (DefenseService SEND_EVERY)
local WHITE = Color3.new(1, 1, 1)

type EnemyView = {
	model: Model,
	kind: string,
	from: Vector3,
	to: Vector3,
	t0: number,
	facing: Vector3,
	hp: number,
	foe: number,
	bar: Frame?,
	barGui: BillboardGui?,
	lunge: number,
	dead: boolean,
	-- Boss: gezegenin canavarı (Yusuf'un 3B modeli, MonsterModel) iskeletiyle
	rig: MonsterModel.Rig?,
	height: number,
	born: number,
	body: BasePart?,           -- jöle gibi esneyen gövde
	mesh: SpecialMesh?,
	meshSize: Vector3?,        -- 3D ağ gövde (EnemyModel/DefenseMeshes): Size ile esniyor
	bodyColor: Color3,
	flash: number,             -- vurulunca beyaz parlama 1 → 0
	squash: number,            -- vurulunca jöle gibi ezilme 1 → 0
	knock: Vector3,            -- geri tepme (sönümleniyor)
	glow: Highlight?,          -- Boss'ta beyaz parlama (gövde ağı yok)
}

type UnitView = {
	uid: number,
	unitId: string,
	role: string,
	model: Model,
	base: CFrame,
	bar: Frame,
	gui: BillboardGui,
	lunge: number,
	lungeDir: Vector3,
	fallen: boolean,
	born: number,              -- elden düşme animasyonu
	prompt: ProximityPrompt,   -- hazırlıkta "Pick up"
	weapon: Model?,            -- rol silahı
	-- Sunucudan gelen konum (crewmate'ler artık yürüyor): ara değerleme
	area: Model,               -- karakolun çevresindeki hareket alanı halkası
	from: Vector3,
	to: Vector3,
	t0: number,
	hand: CFrame,              -- silahın modele göre yeri
	swing: number,             -- vuruş animasyonu 1 → 0
	height: number,
	hurt: number,              -- can azalınca kırmızı parlama + geriye eğilme 1 → 0
	hpFrac: number,            -- son bilinen can oranı (azsa kırmızı nabız)
	knock: Vector3,            -- darbeyle geri tepme
	hurtGlow: Highlight,
}

local folder: Folder? = nil
local planet = 1
-- Dünya konumu arenaya göre (her oyuncunun kendi gezegen kopyası)
local arena = 1
local palette = { body = WHITE, dark = WHITE, glow = WHITE }
local enemies: { [number]: EnemyView } = {}
local units: { [number]: UnitView } = {}
local pathParts: { BasePart } = {}
local marker: BasePart? = nil
local rangeRing: BasePart? = nil
local selectRing: BasePart? = nil
local lastSound: { [string]: number } = {}
local prepMode = false
local pickupHandler: ((number) -> ())? = nil
local DROP_HEIGHT = 5
local DROP_TIME = 0.38

local function root(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "DefenseView"
	nf.Parent = workspace
	folder = nf
	return nf
end

--[[
	Zemin: alanın Terrain yüzeyi arenanın kökünden ~2 stud yukarıda (voksel
	yuvarlaması). Her şey bu kadar gömülüyordu (alan halkaları hiç
	görünmüyordu, crewmate'lerin ayağı kumun içindeydi). Bir kez ölçülüp
	saklanıyor; arazi henüz akmadıysa tahmini değer.
]]
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { workspace.Terrain }
local groundLift: number? = nil

local function lift(): number
	local cached = groundLift
	if cached then
		return cached
	end
	local origin = DefenseConfig.ToWorld(arena, Vector2.new(0, 110), 0)
	local hit = workspace:Raycast(origin + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), groundParams)
	if hit then
		local h = math.clamp(hit.Position.Y - origin.Y, -1, 4)
		groundLift = h
		return h
	end
	return DefenseConfig.GroundLift
end

local function world(p: Vector2, y: number?): Vector3
	return DefenseConfig.ToWorld(arena, p, (y or 0) + lift())
end

-- ─── Darbe hissi: kıvılcım / jöle sıçraması, sarsıntı ────────────────────────

--[[
	Paylaşılan parçacık yayıcıları (her vuruşta yeni parça açılmıyor):
	bağlantı noktası vuruş yerine taşınıp Emit. Ayrı yayıcılar, çünkü
	yayıcının rengi değişince havadaki parçacıklar da renk değiştiriyor.
]]
local burstHost: Attachment? = nil
local emitters: { [string]: ParticleEmitter } = {}

local function emitter(name: string, setup: (ParticleEmitter) -> ()): ParticleEmitter
	local host = burstHost
	if not host or not host.Parent then
		local a = Instance.new("Attachment")
		a.Name = "DefenseBursts"
		a.Parent = workspace.Terrain
		burstHost = a
		host = a
		table.clear(emitters)
	end
	local e = emitters[name]
	if e and e.Parent then
		return e
	end
	local ne = Instance.new("ParticleEmitter")
	ne.Name = name
	ne.Rate = 0
	setup(ne)
	ne.Parent = host
	emitters[name] = ne
	return ne
end

local function burst(name: string, at: Vector3, count: number)
	local e = emitters[name]
	local host = burstHost
	if not (e and host and host.Parent) then
		return
	end
	host.WorldPosition = at
	e:Emit(count)
end

local function setupBursts(glow: Color3)
	for _, e in emitters do
		e:Destroy()
	end
	table.clear(emitters)
	-- Beyaz-sarı kıvılcım (her isabet)
	emitter("Spark", function(e)
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 255, 230), Color3.fromRGB(255, 210, 90))
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.18, 0.32)
		e.Speed = NumberRange.new(14, 24)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Drag = 7
	end)
	-- Gezegen renginde jöle damlaları (yaratık vurulunca / patlayınca)
	emitter("Goo", function(e)
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(glow:Lerp(WHITE, 0.15), glow:Lerp(Color3.new(0, 0, 0), 0.25))
		e.LightEmission = 0.35
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.2) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.45, 0.7)
		e.Speed = NumberRange.new(10, 20)
		e.SpreadAngle = Vector2.new(70, 70)
		e.EmissionDirection = Enum.NormalId.Top
		e.Acceleration = Vector3.new(0, -70, 0)
		e.RotSpeed = NumberRange.new(-120, 120)
	end)
	-- Kırmızı kıvılcım (crewmate'e darbe)
	emitter("Hurt", function(e)
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 120, 110), Color3.fromRGB(220, 30, 40))
		e.LightEmission = 0.8
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.0), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.22, 0.38)
		e.Speed = NumberRange.new(10, 18)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Drag = 6
	end)
end

-- Kamera sarsıntısı: büyük darbelerde (Boss, gemiye sızma, kılıç isabeti)
local shake = 0
local function addShake(amount: number)
	shake = math.min(1.2, shake + amount)
end

local function sound(key: string, gap: number, fn: () -> ())
	local now = os.clock()
	if now - (lastSound[key] or 0) < gap then
		return
	end
	lastSound[key] = now
	fn()
end

local function fxPart(name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	if shape then
		p.Shape = shape
	end
	p.Parent = root()
	return p
end

local function fadeAway(p: BasePart, seconds: number, grow: Vector3?)
	local goal: { [string]: any } = { Transparency = 1 }
	if grow then
		goal.Size = grow
	end
	TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	task.delay(seconds, function()
		p:Destroy()
	end)
end

local OUTLINE = Color3.fromRGB(22, 20, 34)

local function hpBar(adornee: BasePart, offset: number, width: number, color: Color3): (BillboardGui, Frame)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(width, 10)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offset, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 400
	gui.Adornee = adornee
	gui.Parent = adornee
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	back.BorderSizePixel = 0
	back.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Color = OUTLINE
	stroke.Thickness = 2
	stroke.Parent = back
	-- İz: kaybedilen can bir an açık renkte kalıp eriyor (canın gittiği görünsün)
	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.Size = UDim2.fromScale(1, 1)
	chip.BackgroundColor3 = Color3.fromRGB(255, 236, 190)
	chip.BorderSizePixel = 0
	chip.ZIndex = 1
	chip.Parent = back
	local c3 = Instance.new("UICorner")
	c3.CornerRadius = UDim.new(1, 0)
	c3.Parent = chip
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.ZIndex = 2
	fill:SetAttribute("BaseColor", color)
	fill.Parent = back
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(1, 0)
	c2.Parent = fill
	return gui, fill
end

--[[
	Çubuğu güncelle: azalınca dolgu beyaz parlayıp rengine dönüyor, açık
	renkli iz biraz bekleyip eriyerek yetişiyor; artınca iz hemen eşitleniyor.
]]
local function setBar(fill: Frame, frac: number, color: Color3?)
	frac = math.clamp(frac, 0, 1)
	if color then
		fill:SetAttribute("BaseColor", color)
	end
	local base = fill:GetAttribute("BaseColor")
	local baseColor = if typeof(base) == "Color3" then base else WHITE
	local old = fill.Size.X.Scale
	if math.abs(old - frac) < 0.001 then
		if color then
			fill.BackgroundColor3 = baseColor
		end
		return
	end
	fill.Size = UDim2.fromScale(frac, 1)
	local chip = fill.Parent and fill.Parent:FindFirstChild("Chip") :: Frame?
	if frac < old then
		fill.BackgroundColor3 = WHITE
		TweenService:Create(fill, TweenInfo.new(0.2), { BackgroundColor3 = baseColor }):Play()
		if chip then
			TweenService:Create(chip, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.3),
				{ Size = UDim2.fromScale(frac, 1) }):Play()
		end
	else
		fill.BackgroundColor3 = baseColor
		if chip then
			chip.Size = UDim2.fromScale(frac, 1)
		end
	end
end

-- Crewmate can rengi: yeşil → sarı → kırmızı
local function unitHpColor(frac: number): Color3
	if frac > 0.5 then
		return Color3.fromRGB(90, 230, 110)
	elseif frac > 0.25 then
		return Color3.fromRGB(255, 205, 60)
	end
	return Color3.fromRGB(255, 70, 70)
end

-- ─── Ekran: gemi hasarında kırmızı kenar, Boss can çubuğu ────────────────────

local fxGui: ScreenGui? = nil
local edges: { Frame } = {}
local bossBar: Frame? = nil
local bossFill: Frame? = nil
local bossName: TextLabel? = nil
local bossEid: number? = nil

local function screenGui(): ScreenGui?
	local g = fxGui
	if g and g.Parent then
		return g
	end
	local pg = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return nil
	end
	local ng = Instance.new("ScreenGui")
	ng.Name = "DefenseFXGui"
	ng.IgnoreGuiInset = true
	ng.ResetOnSpawn = false
	ng.DisplayOrder = 4
	ng.Parent = pg
	fxGui = ng
	table.clear(edges)
	-- Kenarlar: dışta kırmızı, içe doğru saydam
	local specs = {
		{ UDim2.new(1, 0, 0.22, 0), UDim2.fromScale(0, 0), 90 },
		{ UDim2.new(1, 0, 0.22, 0), UDim2.fromScale(0, 0.78), -90 },
		{ UDim2.new(0.16, 0, 1, 0), UDim2.fromScale(0, 0), 0 },
		{ UDim2.new(0.16, 0, 1, 0), UDim2.fromScale(0.84, 0), 180 },
	}
	for _, s in specs do
		local f = Instance.new("Frame")
		f.Size = s[1]
		f.Position = s[2]
		f.BackgroundColor3 = Color3.fromRGB(255, 30, 40)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Parent = ng
		local grad = Instance.new("UIGradient")
		grad.Rotation = s[3]
		grad.Transparency = NumberSequence.new(0, 1)
		grad.Parent = f
		table.insert(edges, f)
	end
	-- Boss can çubuğu (üstte ortada, yalnızca Boss sahadayken)
	local bar = Instance.new("Frame")
	bar.Name = "BossBar"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 96)
	bar.Size = UDim2.fromOffset(420, 46)
	bar.BackgroundTransparency = 1
	bar.Visible = false
	bar.Parent = ng
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(1, 0, 0, 22)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.FredokaOne
	name.TextSize = 22
	name.TextColor3 = Color3.fromRGB(255, 120, 120)
	name.AutoLocalize = false
	name.Text = "BOSS"
	name.Parent = bar
	local ns = Instance.new("UIStroke")
	ns.Color = OUTLINE
	ns.Thickness = 2.5
	ns.Parent = name
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(0, 24)
	back.Size = UDim2.new(1, 0, 0, 18)
	back.BackgroundColor3 = Color3.fromRGB(30, 22, 34)
	back.BorderSizePixel = 0
	back.Parent = bar
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(1, 0)
	bc.Parent = back
	local bs = Instance.new("UIStroke")
	bs.Color = OUTLINE
	bs.Thickness = 3
	bs.Parent = back
	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.Size = UDim2.fromScale(1, 1)
	chip.BackgroundColor3 = Color3.fromRGB(255, 236, 190)
	chip.BorderSizePixel = 0
	chip.ZIndex = 1
	chip.Parent = back
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(1, 0)
	cc.Parent = chip
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 70, 90)
	fill.BorderSizePixel = 0
	fill.ZIndex = 2
	fill:SetAttribute("BaseColor", Color3.fromRGB(255, 70, 90))
	fill.Parent = back
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = fill
	local fg = Instance.new("UIGradient")
	fg.Rotation = 90
	fg.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200))
	fg.Parent = fill
	bossBar = bar
	bossFill = fill
	bossName = name
	return ng
end

local function hullFlash(strength: number)
	if not screenGui() then
		return
	end
	for _, f in edges do
		f.BackgroundTransparency = math.clamp(1 - strength, 0, 1)
		TweenService:Create(f, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	end
end

local function showBoss(eid: number?, name: string?)
	if not screenGui() then
		return
	end
	local bar = bossBar :: Frame
	bossEid = eid
	if eid then
		(bossName :: TextLabel).Text = "⚠ " .. string.upper(name or "BOSS")
		local fill = bossFill :: Frame
		fill.Size = UDim2.fromScale(1, 1)
		local chip = fill.Parent and fill.Parent:FindFirstChild("Chip") :: Frame?
		if chip then
			chip.Size = UDim2.fromScale(1, 1)
		end
		bar.Visible = true
		bar.Position = UDim2.new(0.5, 0, 0, 60)
		TweenService:Create(bar, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0, 96) }):Play()
	else
		bar.Visible = false
	end
end

-- ─── Gezegen ────────────────────────────────────────────────────────────────

function DefenseFX.SetArena(index: number)
	arena = index
	groundLift = nil
end

function DefenseFX.SetPlanet(index: number)
	planet = index
	local def = Config.SpaceMonsters[index]
	if def then
		palette = {
			body = def.planetColor:Lerp(def.glow, 0.25),
			dark = def.planetColor2:Lerp(Color3.new(0, 0, 0), 0.35),
			glow = def.glow,
		}
	end
	setupBursts(palette.glow)
end

-- ─── Crewmate'ler ───────────────────────────────────────────────────────────

--[[
	Rol silahları (2026-10-01, Batur: "savaşırken belli olsun hangi silahı
	kullanıyorlar, nasıl can basıyorlar, animasyonlar gelişsin"). Silah
	crewmate modelinin içinde ayrı bir Model; her karede elin yerine
	(sağ yan, göğüs hizası) + vuruş animasyonu (swing 1→0) ile konuyor.
	Parçalar "Muzzle" adlı uçtan mermi / iyileştirme çıkıyor.
]]
local function weaponPart(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, neon: boolean?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = if neon then Enum.Material.Neon else Enum.Material.Metal
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

local METAL_DARK = Color3.fromRGB(60, 64, 76)

--[[
	3D silahlar (2026-10-02, Yusuf): ReplicatedStorage.DefenseMeshes.Wpn*
	(ChatGPT → TRELLIS → tools/normalize_meshes.lua) silahın kendi
	uzayında (s = 1, tutuş noktası orijinde) duruyor. Varsa parça silah
	gizlenip ağ biniyor; Grip ve Muzzle (mermi/iyileştirme çıkış noktası)
	görünmez olarak yerinde. Kalkancının copu parça kalıyor.
]]
local WEAPON_MESH: { [string]: { name: string, at: { CFrame } } } = {
	Shooter = { name = "WpnBlaster", at = { CFrame.new(0, 0, -1.05) } },
	Brawler = { name = "WpnSword", at = { CFrame.new() } },
	Guard = { name = "WpnShield", at = { CFrame.new(-1.1, 0, -0.9) } },
	Assassin = { name = "WpnDagger", at = { CFrame.new(0, 0, -0.6), CFrame.new(-2, 0, -0.6) } },
	Medic = { name = "WpnStaff", at = { CFrame.new() } },
}

local function skinWeapon(w: Model, role: string, s: number)
	local spec = WEAPON_MESH[role] or WEAPON_MESH.Medic
	local meshes = ReplicatedStorage:FindFirstChild("DefenseMeshes")
	local template = meshes and meshes:FindFirstChild(spec.name)
	if not (template and template:IsA("Model")) then
		return
	end
	for _, d in w:GetChildren() do
		if d:IsA("BasePart") and d.Name ~= "Baton" then
			d.Transparency = 1
		end
	end
	for _, at in spec.at do
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
			p.Name = "WeaponMesh"
			p.Size = src.Size * s
			p.CFrame = CFrame.new(at.Position * s) * at.Rotation * (src.CFrame.Rotation + src.CFrame.Position * s)
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Parent = w
		end
	end
end

local function buildWeapon(role: string, color: Color3, s: number): Model
	local w = Instance.new("Model")
	w.Name = "Weapon"
	local grip = weaponPart(w, "Grip", Vector3.one * 0.2 * s, CFrame.new(), color)
	grip.Transparency = 1
	w.PrimaryPart = grip
	if role == "Shooter" then
		-- Blaster: gövde, namlu, enerji hücresi, namlu ucu (Muzzle)
		weaponPart(w, "Body", Vector3.new(0.5, 0.7, 1.6) * s, CFrame.new(0, 0.1 * s, -0.3 * s), METAL_DARK)
		weaponPart(w, "Barrel", Vector3.new(1.6 * s, 0.32 * s, 0.32 * s), CFrame.new(0, 0.25 * s, -1.6 * s) * CFrame.Angles(0, math.rad(90), 0), METAL_DARK, false, Enum.PartType.Cylinder)
		weaponPart(w, "Cell", Vector3.new(0.3, 0.3, 0.8) * s, CFrame.new(0, 0.55 * s, -0.3 * s), color, true)
		weaponPart(w, "Handle", Vector3.new(0.3, 0.7, 0.35) * s, CFrame.new(0, -0.35 * s, 0.1 * s) * CFrame.Angles(math.rad(-15), 0, 0), METAL_DARK)
		local m = weaponPart(w, "Muzzle", Vector3.one * 0.36 * s, CFrame.new(0, 0.25 * s, -2.45 * s), color, true, Enum.PartType.Ball)
		m.Transparency = 0.2
	elseif role == "Brawler" then
		-- Enerji kılıcı: yukarı tutuluyor, vururken öne iniyor
		weaponPart(w, "Hilt", Vector3.new(0.3, 0.9, 0.3) * s, CFrame.new(0, 0, 0), METAL_DARK)
		weaponPart(w, "Guard", Vector3.new(0.9, 0.18, 0.3) * s, CFrame.new(0, 0.5 * s, 0), METAL_DARK)
		weaponPart(w, "Blade", Vector3.new(0.18, 3.2, 0.36) * s, CFrame.new(0, 2.15 * s, 0), color, true)
		weaponPart(w, "Muzzle", Vector3.one * 0.1, CFrame.new(0, 3.6 * s, 0), color, true).Transparency = 1
	elseif role == "Guard" then
		-- Büyük kalkan (önde) ve kısa cop
		weaponPart(w, "Shield", Vector3.new(2.2, 2.8, 0.35) * s, CFrame.new(-1.1 * s, 0.2 * s, -0.9 * s), Color3.fromRGB(200, 210, 225))
		weaponPart(w, "ShieldRim", Vector3.new(2.4, 3, 0.25) * s, CFrame.new(-1.1 * s, 0.2 * s, -0.75 * s), color, true)
		weaponPart(w, "ShieldBoss", Vector3.one * 0.8 * s, CFrame.new(-1.1 * s, 0.2 * s, -1.15 * s), color, true, Enum.PartType.Ball)
		weaponPart(w, "Baton", Vector3.new(0.25, 1.8, 0.25) * s, CFrame.new(0, 0.6 * s, 0), METAL_DARK)
		weaponPart(w, "Muzzle", Vector3.one * 0.1, CFrame.new(-1.1 * s, 0.2 * s, -1.4 * s), color, true).Transparency = 1
	elseif role == "Assassin" then
		-- Çift hançer (iki yanda)
		for _, x in { 0, -2.0 } do
			weaponPart(w, "Hilt", Vector3.new(0.22, 0.22, 0.6) * s, CFrame.new(x * s, 0, 0), METAL_DARK)
			weaponPart(w, "Dagger", Vector3.new(0.12, 0.3, 1.4) * s, CFrame.new(x * s, 0, -0.95 * s), color, true)
		end
		weaponPart(w, "Muzzle", Vector3.one * 0.1, CFrame.new(-1 * s, 0, -1.6 * s), color, true).Transparency = 1
	else
		-- Medic: asa, tepesinde yeşil haçlı küre
		weaponPart(w, "Staff", Vector3.new(0.22, 4, 0.22) * s, CFrame.new(0, 1 * s, 0), Color3.fromRGB(230, 230, 240))
		local orb = weaponPart(w, "Muzzle", Vector3.one * 0.9 * s, CFrame.new(0, 3.2 * s, 0), color, true, Enum.PartType.Ball)
		orb.Transparency = 0.15
		weaponPart(w, "CrossV", Vector3.new(0.12, 0.7, 0.2) * s, CFrame.new(0, 3.2 * s, -0.42 * s), WHITE, true)
		weaponPart(w, "CrossH", Vector3.new(0.7, 0.12, 0.2) * s, CFrame.new(0, 3.2 * s, -0.42 * s), WHITE, true)
	end
	skinWeapon(w, role, s)
	return w
end

-- Vuruş animasyonu: swing 1 (vurdu) → 0. Elin çerçevesine göre.
local function weaponPose(role: string, swing: number, t: number): CFrame
	local k = math.sin(math.clamp(swing, 0, 1) * math.pi)
	if role == "Shooter" then
		return CFrame.new(0, 0, 0.6 * k) * CFrame.Angles(math.rad(12 * k), 0, 0)
	elseif role == "Brawler" then
		return CFrame.Angles(-math.rad(105 * k), 0, math.rad(-20 * k))
	elseif role == "Guard" then
		return CFrame.new(0, 0, -0.9 * k)
	elseif role == "Assassin" then
		return CFrame.new(0, 0.2 * k, -1.2 * k) * CFrame.Angles(-math.rad(50 * k), 0, 0)
	end
	-- Medic: asa kalkıyor, boştayken hafif sallanıyor
	return CFrame.new(0, 0.7 * k, 0) * CFrame.Angles(0, 0, math.rad(math.sin(t * 2) * 4))
end


local function anchorAll(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
		end
	end
end

--[[
	Hareket alanı (Batur: "ne kadar alan içinde iş yaptıkları belli değil, bir
	alan olsun altlarında, çok göz almayan ama belli olan"): karakolun
	çevresinde rol renginde ince halka + çok silik disk, leash yarıçapında.
]]
local AREA_SEGMENTS = 28

local function buildArea(roleId: string, color: Color3): Model
	local role = DefenseConfig.Roles[roleId]
	local r = if role then role.leash else 8
	local m = Instance.new("Model")
	m.Name = "Area"
	local disc = fxPart("AreaDisc", Vector3.new(0.06, r * 2, r * 2), CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder)
	disc.Transparency = 0.9
	disc.Material = Enum.Material.SmoothPlastic
	disc.Parent = m
	for k = 0, AREA_SEGMENTS - 1 do
		local a0 = k / AREA_SEGMENTS * math.pi * 2
		local a1 = (k + 1) / AREA_SEGMENTS * math.pi * 2
		local p0 = Vector3.new(math.cos(a0) * r, 0.12, math.sin(a0) * r)
		local p1 = Vector3.new(math.cos(a1) * r, 0.12, math.sin(a1) * r)
		local seg = fxPart("AreaRing", Vector3.new(0.4, 0.08, (p1 - p0).Magnitude + 0.05), CFrame.lookAt((p0 + p1) / 2, p1), color:Lerp(WHITE, 0.2))
		seg.Transparency = 0.35
		seg.Parent = m
	end
	m.PrimaryPart = disc
	return m
end

local function buildUnit(info: any): UnitView?
	local ok, model = pcall(UnitModel.Build, info.unitId, info.mutationId)
	if not (ok and model) then
		return nil
	end
	model.Name = "Crew_" .. tostring(info.uid)
	anchorAll(model)
	-- Boy ölçülüp UNIT_HEIGHT'a büyütülüyor (karakterlerin boyu farklı)
	local rawHeight = model:GetExtentsSize().Y
	if rawHeight > 0.1 then
		pcall(function()
			model:ScaleTo(model:GetScale() * UNIT_HEIGHT / rawHeight)
		end)
	end
	local height = model:GetExtentsSize().Y
	local width = model:GetExtentsSize().X
	local role = DefenseConfig.Roles[info.role] or DefenseConfig.GetRole(info.unitId)
	local pos = world(Vector2.new(info.x, info.z))
	local base = CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1))
	model:PivotTo(base)
	-- Silah: sağ yanda, göğüs hizasında
	local s = height / 5
	local weapon = buildWeapon(role.id, role.color, s)
	local hand = CFrame.new(width * 0.5 + 0.2 * s, height * 0.42, -0.4 * s)
	weapon:PivotTo(base * hand)
	weapon.Parent = model
	local area = buildArea(role.id, role.color)
	area:PivotTo(CFrame.new(pos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)))
	area.Parent = root()
	model:SetAttribute("DefenseUid", info.uid)
	model.Parent = root()
	-- Can azalınca kırmızı parlama
	local hurtGlow = Instance.new("Highlight")
	hurtGlow.Name = "HurtGlow"
	hurtGlow.FillColor = Color3.fromRGB(255, 50, 50)
	hurtGlow.OutlineColor = Color3.fromRGB(255, 220, 220)
	hurtGlow.FillTransparency = 1
	hurtGlow.OutlineTransparency = 1
	hurtGlow.DepthMode = Enum.HighlightDepthMode.Occluded
	hurtGlow.Enabled = false
	hurtGlow.Adornee = model
	hurtGlow.Parent = model

	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart") :: BasePart
	local gui, fill = hpBar(anchor, height + 1.2, 64, Color3.fromRGB(90, 230, 110))
	-- Rol simgesi
	local icon = Instance.new("TextLabel")
	icon.AnchorPoint = Vector2.new(0.5, 1)
	icon.Position = UDim2.new(0.5, 0, 0, -1)
	icon.Size = UDim2.fromOffset(24, 22)
	icon.BackgroundColor3 = role.color
	icon.Text = role.icon
	icon.TextScaled = true
	icon.Font = Enum.Font.GothamBlack
	icon.TextColor3 = WHITE
	icon.AutoLocalize = false
	icon.Parent = gui
	gui.Size = UDim2.fromOffset(64, 10)
	gui.ClipsDescendants = false
	local ic = Instance.new("UICorner")
	ic.CornerRadius = UDim.new(1, 0)
	ic.Parent = icon

	-- Hazırlıkta yanına gelince geri al (istemcide; sunucu mesafeyi doğruluyor)
	local def = Config.GetUnit(info.unitId)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick up"
	prompt.ObjectText = if def then def.name else ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = prepMode
	prompt.Parent = anchor
	prompt.Triggered:Connect(function()
		if pickupHandler then
			pickupHandler(info.uid)
		end
	end)

	return {
		uid = info.uid,
		unitId = info.unitId,
		role = role.id,
		model = model,
		base = base,
		bar = fill,
		gui = gui,
		lunge = 0,
		lungeDir = Vector3.zero,
		fallen = false,
		born = os.clock(),
		prompt = prompt,
		weapon = weapon,
		hand = hand,
		swing = 0,
		height = height,
		hurt = 0,
		hpFrac = 1,
		knock = Vector3.zero,
		hurtGlow = hurtGlow,
		area = area,
		from = pos,
		to = pos,
		t0 = os.clock(),
	}
end

--[[ Sahadaki crewmate'leri koşu durumuyla eşitler (yeni kur, taşı, kaldır). ]]
function DefenseFX.SyncUnits(list: { any })
	local seen: { [number]: boolean } = {}
	for _, info in list do
		seen[info.uid] = true
		local view = units[info.uid]
		if not view then
			local built = buildUnit(info)
			if built then
				units[info.uid] = built
				-- Kondu: küçük bir zıplama
				-- Elden düşüyor; yere değince toz halkası
				local at = world(Vector2.new(info.x, info.z), 0.2)
				task.delay(DROP_TIME, function()
					local p = fxPart("Drop", Vector3.new(0.3, 5, 5), CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)),
						Color3.fromRGB(120, 220, 255), Enum.PartType.Cylinder)
					p.Transparency = 0.3
					fadeAway(p, 0.5, Vector3.new(0.3, 9, 9))
				end)
			end
		else
			local pos = world(Vector2.new(info.x, info.z))
			view.base = CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1))
			view.area:PivotTo(CFrame.new(pos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90)))
			-- Hazırlıkta karakoluna yürüyerek dönüyor
			local now = os.clock()
			local a = math.clamp((now - view.t0) / SNAP_GAP, 0, 1)
			view.from = view.from:Lerp(view.to, a)
			view.to = pos
			view.t0 = now
		end
	end
	for uid, view in units do
		if not seen[uid] and not view.fallen then
			view.model:Destroy()
			view.area:Destroy()
			units[uid] = nil
		end
	end
end

function DefenseFX.ResetUnitHealth()
	for _, view in units do
		view.hpFrac = 1
		setBar(view.bar, 1, unitHpColor(1))
	end
end

--[[ Ekrandaki bir noktaya en yakın crewmate (yerel düzlemde, yarıçap içinde). ]]
function DefenseFX.UnitNear(p: Vector2, radius: number): number?
	local best, bestD = nil, radius
	for uid, view in units do
		if not view.fallen then
			local rel = view.base.Position - DefenseConfig.WorldOrigin(arena)
			local d = (Vector2.new(rel.X, rel.Z) - p).Magnitude
			if d < bestD then
				best, bestD = uid, d
			end
		end
	end
	return best
end

-- ─── Düşmanlar ──────────────────────────────────────────────────────────────

--[[
	2026-10-01 (Batur: "ilk gezegenin canavarlarına bakalım"): bütün
	düşmanlar gezegenin canavarının (Glorp) farklı boydaki yavruları;
	Yusuf'un 3B ağ şablonu (ReplicatedStorage.MonsterMeshes) varsa onunla.
	Tür boyla ayırt ediliyor; ölçek ilk kurulumda bir kez ölçülüyor.
]]
local KIND_HEIGHT: { [string]: number } = {
	Skitter = 6, Grub = 9.5, Spitter = 10, Brute = 15, Boss = 20,
}
local unitHeight: { [string]: number } = {}

local function monsterModel(id: string, kind: string): (Model, MonsterModel.Rig?, number)
	local target = KIND_HEIGHT[kind] or 4
	local h1 = unitHeight[id]
	if not h1 then
		local ok, probe = pcall(MonsterModel.Build, id, 1)
		h1 = 0
		if ok and probe then
			h1 = probe:GetExtentsSize().Y
			probe:Destroy()
		end
		unitHeight[id] = h1
	end
	local scale = if (h1 :: number) > 0.5 then target / (h1 :: number) else 0.3
	local ok, model = pcall(MonsterModel.Build, id, scale)
	if not (ok and model) then
		return EnemyModel.Build(kind, palette.body, palette.dark, palette.glow), nil, target
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	local rigOk, rig = pcall(MonsterModel.Rig, model)
	return model, if rigOk then rig else nil, target
end

local function spawnEnemy(eid: number, kind: string, pathIndex: number, lane: number, paths: { { Vector2 } }?)
	if enemies[eid] then
		return
	end
	local model: Model
	local rig: MonsterModel.Rig? = nil
	local height = KIND_HEIGHT[kind] or 4
	local monster = Config.SpaceMonsters[planet]
	if kind == "Boss" and monster then
		-- Boss gezegenin canavarı (Glorp; Yusuf'un 3B şablonu varsa onunla)
		model, rig, height = monsterModel(monster.id, kind)
	else
		-- Diğerleri gezegenin yaratıkları (EnemyModel), büyütülmüş
		model = EnemyModel.Build(kind, palette.body, palette.dark, palette.glow)
		pcall(function()
			model:ScaleTo(ENEMY_SCALE)
		end)
		height = model:GetExtentsSize().Y
	end
	local body = model:FindFirstChild("Body") :: BasePart?
	local mesh = body and body:FindFirstChildOfClass("SpecialMesh")
	local start = DefenseConfig.Field.entrance
	if paths and paths[pathIndex] then
		start = paths[pathIndex][1]
	end
	local pos = world(start + Vector2.new(lane, 0))
	model:PivotTo(CFrame.lookAt(pos, pos - Vector3.new(0, 0, 1)))
	model.Parent = root()
	local view: EnemyView = {
		model = model,
		kind = kind,
		from = pos,
		to = pos,
		t0 = os.clock(),
		facing = Vector3.new(0, 0, -1),
		hp = 1,
		foe = 0,
		bar = nil,
		barGui = nil,
		lunge = 0,
		dead = false,
		rig = rig,
		height = height,
		born = os.clock(),
		body = body,
		mesh = mesh,
		meshSize = if not mesh and body and body:IsA("MeshPart") then body.Size else nil,
		bodyColor = if body then body.Color else WHITE,
		flash = 0,
		squash = 0,
		knock = Vector3.zero,
		glow = nil,
	}
	if not mesh then
		-- Gövde ağı olmayan (Boss): vurulunca Highlight ile beyaz parlama
		local hl = Instance.new("Highlight")
		hl.Name = "HitGlow"
		hl.FillColor = WHITE
		hl.OutlineTransparency = 1
		hl.FillTransparency = 1
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Enabled = false
		hl.Adornee = model
		hl.Parent = model
		view.glow = hl
	end
	enemies[eid] = view
	if kind == "Boss" then
		-- Boss geliyor: sarsıntı, gürleme, üstte büyük can çubuğu
		SoundFX.GearSound("GearBlast", pos)
		SoundFX.WorldSound("CrashBoom", pos, 0.7, 0.55, 1.4)
		addShake(0.9)
		local def = DefenseConfig.Enemies.Boss
		showBoss(eid, if monster then monster.name else def.name)
	end
	-- Kapıdan çıkış parıltısı
	local flash = fxPart("Emerge", Vector3.one * 3, CFrame.new(pos + Vector3.new(0, 1.5, 0)), palette.glow, Enum.PartType.Ball)
	flash.Transparency = 0.3
	fadeAway(flash, 0.4, Vector3.one * 7)
end

local function killEnemy(eid: number)
	local view = enemies[eid]
	if not view or view.dead then
		return
	end
	view.dead = true
	enemies[eid] = nil
	local at = view.model:GetPivot().Position
	local big = view.kind == "Boss" or view.kind == "Brute"
	local puff = fxPart("Puff", Vector3.one * 2, CFrame.new(at + Vector3.new(0, view.height * 0.4, 0)), palette.glow, Enum.PartType.Ball)
	puff.Transparency = 0.2
	fadeAway(puff, 0.35, Vector3.one * (if view.kind == "Boss" then 16 elseif big then 10 else 7))
	-- Jöle patlaması: damlalar + yerde leke
	burst("Goo", at + Vector3.new(0, view.height * 0.4, 0), if big then 26 else 14)
	local splat = fxPart("Splat", Vector3.new(0.12, 2, 2), CFrame.new(at + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		palette.glow:Lerp(Color3.new(0, 0, 0), 0.3), Enum.PartType.Cylinder)
	splat.Material = Enum.Material.SmoothPlastic
	splat.Transparency = 0.25
	local spread = if big then 9 else 5
	TweenService:Create(splat, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.12, spread, spread) }):Play()
	task.delay(1.2, function()
		fadeAway(splat, 0.8)
	end)
	if big then
		addShake(if view.kind == "Boss" then 0.9 else 0.3)
	end
	-- Jöle patlıyor: yayvanlaşıp sönüyor
	local mesh = view.mesh
	if mesh then
		TweenService:Create(mesh, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Scale = Vector3.new(1.6, 0.25, 1.6) }):Play()
	elseif view.meshSize and view.body then
		TweenService:Create(view.body, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = view.meshSize * Vector3.new(1.5, 0.3, 1.5) }):Play()
	end
	if bossEid == eid then
		showBoss(nil, nil)
	end
	sound("poof", 0.08, function()
		SoundFX.WorldSound("GearPoof", at, 0.6, if big then 0.75 else 1.25, 0.7)
	end)
	for _, d in view.model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			TweenService:Create(d, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		end
	end
	task.delay(0.3, function()
		view.model:Destroy()
	end)
end

local function enemyBar(view: EnemyView, hp: number)
	view.hp = hp
	if hp < 0.999 and not view.bar then
		local anchor = view.model.PrimaryPart :: BasePart
		local h = view.height + 1
		local gui, fill = hpBar(anchor, h, if view.kind == "Boss" then 130 elseif view.kind == "Brute" then 76 else 56, Color3.fromRGB(255, 80, 80))
		view.bar = fill
		view.barGui = gui
	end
	local bar = view.bar
	if bar then
		setBar(bar, hp)
	end
	if view.kind == "Boss" and bossFill and bossEid then
		setBar(bossFill :: Frame, hp)
	end
end

-- ─── Efektler ───────────────────────────────────────────────────────────────

local function chest(model: Model): Vector3
	return model:GetPivot().Position + Vector3.new(0, 2.2, 0)
end

local function beam(from: Vector3, to: Vector3, color: Color3, width: number, seconds: number)
	local d = (to - from).Magnitude
	if d < 0.1 then
		return
	end
	local p = fxPart("Beam", Vector3.new(width, width, d), CFrame.lookAt((from + to) / 2, to), color)
	p.Transparency = 0.1
	fadeAway(p, seconds)
end

local function bolt(from: Vector3, to: Vector3, color: Color3)
	local p = fxPart("Bolt", Vector3.one * 0.6, CFrame.new(from), color, Enum.PartType.Ball)
	local t = TweenService:Create(p, TweenInfo.new(0.14, Enum.EasingStyle.Linear), { CFrame = CFrame.new(to) })
	t:Play()
	t.Completed:Connect(function()
		p:Destroy()
	end)
end

local function floatText(at: Vector3, text: string, color: Color3)
	local p = fxPart("FloatText", Vector3.one * 0.2, CFrame.new(at), color)
	p.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(60, 24)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.2
	l.AutoLocalize = false
	l.Text = text
	l.Parent = gui
	TweenService:Create(p, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(at + Vector3.new(0, 3, 0)) }):Play()
	TweenService:Create(l, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.85, function()
		p:Destroy()
	end)
end

--[[
	Hasar sayısı: büyük başlayıp küçülüyor, yükselip sönüyor. `big` için
	daha büyük.
]]
local function damageText(at: Vector3, amount: number, color: Color3, big: boolean?)
	local p = fxPart("DamageText", Vector3.one * 0.2, CFrame.new(at), color)
	p.Transparency = 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(if big then 86 else 64, if big then 38 else 28)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 220
	gui.Parent = p
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0
	l.TextStrokeColor3 = Color3.fromRGB(30, 20, 30)
	l.AutoLocalize = false
	l.Text = tostring(amount)
	l.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 1.7
	scale.Parent = l
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	local drift = Vector3.new((math.random() - 0.5) * 2.5, 3.5, (math.random() - 0.5) * 2.5)
	TweenService:Create(p, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(at + drift) }):Play()
	task.delay(0.35, function()
		TweenService:Create(l, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	task.delay(0.75, function()
		p:Destroy()
	end)
end

--[[
	Yaratık vuruldu (Batur: "hasar alma animasyonları olsun, hiç vuruş hissi
	yok"): beyaz parlama, jöle gibi ezilme, vurulduğu yönden geri tepme,
	kıvılcım + jöle damlası, hasar sayısı ve vıcık ses.
]]
local function hitEnemy(e: EnemyView, from: Vector3?, amount: number?, power: number, color: Color3?, crit: boolean?)
	if e.dead then
		return
	end
	e.flash = 1
	e.squash = 1
	local pivot = e.model:GetPivot().Position
	if from then
		local away = (pivot - from) * Vector3.new(1, 0, 1)
		if away.Magnitude > 0.1 then
			local resist = if e.kind == "Boss" then 0.2 elseif e.kind == "Brute" then 0.45 else 1
			e.knock += away.Unit * power * resist
			if e.knock.Magnitude > 3 then
				e.knock = e.knock.Unit * 3
			end
		end
	end
	local at = pivot + Vector3.new(0, e.height * 0.5, 0)
	burst("Spark", at, if crit then 10 else 6)
	burst("Goo", at, if crit then 7 else 4)
	if amount and amount > 0 then
		damageText(at + Vector3.new(0, e.height * 0.4 + 1, 0), amount, color or WHITE, crit)
	end
	sound("ehit", 0.07, function()
		SoundFX.WorldSound("GearSlap", at, 0.45, if e.kind == "Boss" or e.kind == "Brute" then 0.8 else 1.35, 0.4)
	end)
end

--[[
	Crewmate'in canı azaldı (Batur: "bizim crewmate'lere de ekle"): kırmızı
	parlama, darbenin geldiği yönden geri tepme + geriye eğilme, kırmızı
	kıvılcım, hasar sayısı ve darbe sesi; Boss / Golem vurursa kamera sarsılıyor.
]]
local function hurtUnit(u: UnitView, from: Vector3?, amount: number, heavy: boolean)
	u.hurt = 1
	if from then
		local away = (u.base.Position - from) * Vector3.new(1, 0, 1)
		if away.Magnitude > 0.1 then
			u.knock += away.Unit * (if heavy then 2.2 else 1.1)
			if u.knock.Magnitude > 3 then
				u.knock = u.knock.Unit * 3
			end
		end
	end
	local at = chest(u.model) + Vector3.new(0, u.height * 0.15, 0)
	burst("Hurt", at, if heavy then 14 else 7)
	damageText(at + Vector3.new(0, u.height * 0.45, 0), amount, Color3.fromRGB(255, 80, 80), heavy)
	if heavy then
		addShake(0.45)
	end
	sound("uhurt", 0.1, function()
		SoundFX.WorldSound("GearSlap", at, if heavy then 0.8 else 0.55, if heavy then 0.7 else 0.95, 0.5)
		if heavy then
			SoundFX.WorldSound("CrashBoom", at, 0.35, 1.2, 0.6)
		end
	end)
end

local function onUnitAttack(uid: number, eid: number, amount: number?)
	local u = units[uid]
	local e = enemies[eid]
	if not (u and e) or u.fallen then
		return
	end
	local muzzle = u.weapon and u.weapon:FindFirstChild("Muzzle") :: BasePart?
	local from = if muzzle then muzzle.Position else chest(u.model)
	local to = e.model:GetPivot().Position + Vector3.new(0, e.height * 0.45, 0)
	local dir = (to - from) * Vector3.new(1, 0, 1)
	if dir.Magnitude > 0.1 then
		u.lungeDir = dir.Unit
	end
	u.swing = 1
	local role = DefenseConfig.Roles[u.role]
	local origin = u.base.Position
	if u.role == "Shooter" or u.role == "Medic" then
		-- Mermi varınca isabet
		task.delay(0.14, function()
			if enemies[eid] == e then
				hitEnemy(e, origin, amount, 0.5, WHITE)
			end
		end)
	else
		local power = if u.role == "Assassin" then 1.0 elseif u.role == "Guard" then 1.6 else 1.3
		hitEnemy(e, origin, amount, power, if u.role == "Assassin" then Color3.fromRGB(255, 170, 60) else WHITE, u.role == "Assassin")
	end
	if u.role == "Shooter" then
		-- Namlu alevi + parlak mermi
		local flare = fxPart("MuzzleFlash", Vector3.one * 0.9, CFrame.new(from), role.color, Enum.PartType.Ball)
		flare.Transparency = 0.1
		fadeAway(flare, 0.12, Vector3.one * 1.8)
		bolt(from, to, role.color)
		sound("shot", 0.09, function()
			SoundFX.Laser()
		end)
	elseif u.role == "Assassin" then
		u.lunge = 1
		beam(from, to, role.color, 0.3, 0.18)
		sound("stab", 0.1, function()
			SoundFX.GearSound("GearSwing", from)
		end)
	elseif u.role == "Medic" then
		bolt(from, to, role.color)
	else
		u.lunge = 1
		-- Kılıç / kalkan izi
		beam(from, to, role.color, 0.2, 0.12)
		sound("punch", 0.12, function()
			SoundFX.GearSound(if u.role == "Brawler" then "GearSwing" else "GearSlap", to)
		end)
	end
end

local function onUnitHit(uid: number, eid: number, amount: number)
	local u = units[uid]
	local e = enemies[eid]
	if e and u then
		e.lunge = 1
		local def = DefenseConfig.Enemies[e.kind]
		if def and def.range > 7 then
			-- Tükürük
			bolt(e.model:GetPivot().Position + Vector3.new(0, 2, 0), chest(u.model), palette.glow)
		end
	end
	if u and not u.fallen then
		local heavy = e ~= nil and (e.kind == "Boss" or e.kind == "Brute")
		local from = if e then e.model:GetPivot().Position else nil
		local def = e and DefenseConfig.Enemies[e.kind]
		if def and def.range > 7 then
			-- Tükürük uçarken bekle
			task.delay(0.14, function()
				if units[uid] == u and not u.fallen then
					hurtUnit(u, from, amount, heavy)
				end
			end)
		else
			hurtUnit(u, from, amount, heavy)
		end
	end
end

local function onHeal(uid: number, target: number, amount: number)
	local u = units[uid]
	local t = units[target]
	if not (u and t) then
		return
	end
	u.swing = 1
	local green = Color3.fromRGB(110, 255, 150)
	local muzzle = u.weapon and u.weapon:FindFirstChild("Muzzle") :: BasePart?
	local from = if muzzle then muzzle.Position else chest(u.model)
	beam(from, chest(t.model), green, 0.3, 0.35)
	-- Hastanın ayağında büyüyen yeşil halka ve yükselen ışıltılar
	local feet = t.base.Position + Vector3.new(0, 0.3, 0)
	local ringPart = fxPart("HealRing", Vector3.new(0.2, 3, 3), CFrame.new(feet) * CFrame.Angles(0, 0, math.rad(90)), green, Enum.PartType.Cylinder)
	ringPart.Transparency = 0.25
	fadeAway(ringPart, 0.5, Vector3.new(0.2, 7, 7))
	local host = fxPart("HealSparks", Vector3.one * 0.2, CFrame.new(feet + Vector3.new(0, 1, 0)), green)
	host.Transparency = 1
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(green)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.6, 0.9)
	e.Speed = NumberRange.new(3, 6)
	e.SpreadAngle = Vector2.new(25, 25)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rate = 0
	e.Parent = host
	e:Emit(14)
	task.delay(1, function()
		host:Destroy()
	end)
	floatText(chest(t.model) + Vector3.new(0, 2.5, 0), "+" .. tostring(amount), green)
end

local function onUnitFall(uid: number)
	local u = units[uid]
	if not u or u.fallen then
		return
	end
	u.fallen = true
	setBar(u.bar, 0)
	local base = u.base
	-- Devrilme: modeli pivotundan yana yatır
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.45 and u.model.Parent do
			local a = math.clamp((os.clock() - t0) / 0.45, 0, 1)
			u.model:PivotTo(base * CFrame.Angles(0, 0, math.rad(-85 * a)))
			task.wait()
		end
	end)
	floatText(chest(u.model) + Vector3.new(0, 2, 0), "✚ HOSPITAL", Color3.fromRGB(255, 110, 110))
	burst("Hurt", chest(u.model), 22)
	u.hurt = 1
	u.hurtGlow.Enabled = true
	u.hurtGlow.FillTransparency = 0.35
	addShake(0.35)
	sound("fall", 0.2, function()
		SoundFX.WorldSound("CrashMetal", chest(u.model), 0.5, 0.85, 0.7)
		SoundFX.GearSound("GearBlast", chest(u.model))
	end)
	task.delay(1.6, function()
		if units[uid] == u then
			units[uid] = nil
		end
		u.model:Destroy()
		u.area:Destroy()
	end)
end

local function onLeak()
	local gate = world(DefenseConfig.Field.gate, 2)
	local p = fxPart("Leak", Vector3.one * 4, CFrame.new(gate), Color3.fromRGB(255, 60, 60), Enum.PartType.Ball)
	p.Transparency = 0.2
	fadeAway(p, 0.5, Vector3.one * 16)
	addShake(0.6)
	hullFlash(0.75)
	sound("leak", 0.25, function()
		SoundFX.ShipCrash()
	end)
end

local function onStrike(x: number, z: number)
	local at = world(Vector2.new(x, z))
	-- Gökten inen ışın + patlama halkası
	local column = fxPart("StrikeBeam", Vector3.new(3, 120, 3), CFrame.new(at + Vector3.new(0, 60, 0)), Color3.fromRGB(255, 200, 80))
	column.Transparency = 0.2
	fadeAway(column, 0.5, Vector3.new(0.5, 120, 0.5))
	local ring = fxPart("StrikeRing", Vector3.new(0.4, 4, 4), CFrame.new(at + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(255, 160, 60), Enum.PartType.Cylinder)
	local r = DefenseConfig.StrikeRadius * 2
	fadeAway(ring, 0.6, Vector3.new(0.4, r, r))
	addShake(0.7)
	SoundFX.GearSound("GearBlast", at)
end

local function onFreeze(seconds: number)
	for _, e in enemies do
		if e.meshSize or e.rig then
			-- Dokulu 3D ağda Color görünmüyor: buz mavisi Highlight
			local ice = Instance.new("Highlight")
			ice.Name = "Frozen"
			ice.FillColor = Color3.fromRGB(150, 215, 255)
			ice.FillTransparency = 0.45
			ice.OutlineColor = Color3.fromRGB(220, 245, 255)
			ice.OutlineTransparency = 0.2
			ice.DepthMode = Enum.HighlightDepthMode.Occluded
			ice.Adornee = e.model
			ice.Parent = e.model
			task.delay(seconds, function()
				ice:Destroy()
			end)
		end
		for _, d in e.model:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "Body" then
				local original = d.Color
				d.Color = Color3.fromRGB(160, 220, 255)
				task.delay(seconds, function()
					if d.Parent then
						d.Color = original
					end
				end)
			end
		end
	end
	SoundFX.GearSound("GearZap", world(Vector2.new(0, 110), 2))
end

--[[ Oyuncunun ışın tabancası: elindeki tabancanın ucundan düşmana lazer. ]]
local function onPlayerShot(x: number, z: number, eid: number, amount: number?)
	local character = Players.LocalPlayer.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	local muzzle = tool and tool:FindFirstChild("Muzzle") :: BasePart?
	local from = if muzzle then muzzle.Position else world(Vector2.new(x, z), 3)
	local e = enemies[eid]
	local color = if muzzle then muzzle.Color else Color3.fromRGB(120, 220, 255)
	if e then
		hitEnemy(e, from, amount, 0.8, Color3.fromRGB(255, 230, 90))
		local to = e.model:GetPivot().Position + Vector3.new(0, e.height * 0.45, 0)
		beam(from, to, color, 0.35, 0.12)
		local hit = fxPart("RayHit", Vector3.one * 1.2, CFrame.new(to), color, Enum.PartType.Ball)
		hit.Transparency = 0.2
		fadeAway(hit, 0.2, Vector3.one * 3)
	end
	local flare = fxPart("RayFlare", Vector3.one * 0.8, CFrame.new(from), color, Enum.PartType.Ball)
	flare.Transparency = 0.1
	fadeAway(flare, 0.1, Vector3.one * 1.6)
	sound("raygun", 0.06, function()
		if e then
			local to = e.model:GetPivot().Position
			SoundFX.WorldSound("RayHit", to, 0.5, 1.15, 0.45)
		end
	end)
end

--[[ Oyuncunun ışın kılıcı vuruşu: yay biçiminde parlama. ]]
local function onSlash(x: number, z: number, hits: number, amount: number?)
	local at = world(Vector2.new(x, z), 2.5)
	if hits > 0 then
		-- Kılıç isabeti: çevredeki yaratıklar savruluyor, kamera hafif sarsılıyor
		local feet = world(Vector2.new(x, z))
		for _, e in enemies do
			local d = (e.to - feet) * Vector3.new(1, 0, 1)
			if d.Magnitude <= DefenseConfig.Saber.radius + 1.5 then
				hitEnemy(e, feet, amount, 2.2, Color3.fromRGB(150, 230, 255))
			end
		end
		addShake(0.25)
	end
	local ring = fxPart("SlashRing", Vector3.new(0.3, 4, 4), CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(140, 220, 255), Enum.PartType.Cylinder)
	ring.Transparency = 0.3
	local r = DefenseConfig.Saber.radius * 2
	fadeAway(ring, 0.25, Vector3.new(0.3, r, r))
	if hits > 0 then
		sound("saberhit", 0.08, function()
			SoundFX.WorldSound("SaberHit", at, 0.6, 1.0, 0.5)
			SoundFX.WorldSound("GearSlap", at, 0.35, 0.8, 0.35)
		end)
	end
end

local function onMedDrop()
	for _, u in units do
		if not u.fallen then
			floatText(chest(u.model) + Vector3.new(0, 2, 0), "+50%", Color3.fromRGB(110, 255, 150))
		end
	end
	SoundFX.Success()
end

--[[
	Sunucudan gelen anlık görüntü (DefenseService.snapshot): düşman
	konumları/canları, crewmate canları ve o arada olan olaylar.
]]
function DefenseFX.Tick(snap: any, paths: { { Vector2 } }?)
	-- Önce olaylar: yeni doğanlar konum güncellemesinden önce kurulsun
	for _, ev in snap.ev or {} do
		local kind = ev[1]
		if kind == "spawn" then
			spawnEnemy(ev[2], ev[3], ev[4], ev[5], paths)
		elseif kind == "edie" then
			killEnemy(ev[2])
		elseif kind == "uatk" then
			onUnitAttack(ev[2], ev[3], ev[4])
		elseif kind == "uhit" then
			onUnitHit(ev[2], ev[3], ev[4])
		elseif kind == "heal" then
			onHeal(ev[2], ev[3], ev[4])
		elseif kind == "ufall" then
			onUnitFall(ev[2])
		elseif kind == "leak" then
			local view = enemies[ev[2]]
			if view then
				view.dead = true
				enemies[ev[2]] = nil
				view.model:Destroy()
			end
			if bossEid == ev[2] then
				showBoss(nil, nil)
			end
			onLeak()
		elseif kind == "strike" then
			onStrike(ev[2], ev[3])
		elseif kind == "freeze" then
			onFreeze(ev[2])
		elseif kind == "meddrop" then
			onMedDrop()
		elseif kind == "slash" then
			onSlash(ev[2], ev[3], ev[4], ev[5])
		elseif kind == "pshot" then
			onPlayerShot(ev[2], ev[3], ev[4], ev[5])
		end
	end

	local now = os.clock()
	local present: { [number]: boolean } = {}
	for _, e in snap.e or {} do
		local eid = e[1]
		present[eid] = true
		local view = enemies[eid]
		if view then
			local pos = world(Vector2.new(e[2], e[3]))
			local current = view.model:GetPivot().Position
			view.from = Vector3.new(current.X, pos.Y, current.Z)
			view.to = pos
			view.t0 = now
			view.foe = e[5]
			enemyBar(view, e[4])
		end
	end
	-- Görüntüde olmayan (ölen / sızan, olayı kaçmış) düşmanları temizle
	for eid, view in enemies do
		if not present[eid] then
			killEnemy(eid)
		end
	end
	for _, u in snap.u or {} do
		local view = units[u[1]]
		if view and not view.fallen then
			view.hpFrac = math.clamp(u[2], 0, 1)
			setBar(view.bar, view.hpFrac, unitHpColor(view.hpFrac))
			if u[3] and u[4] then
				local a = math.clamp((now - view.t0) / SNAP_GAP, 0, 1)
				view.from = view.from:Lerp(view.to, a)
				view.to = world(Vector2.new(u[3], u[4]))
				view.t0 = now
			end
		end
	end
end

-- ─── Yol önizlemesi ve imleçler ─────────────────────────────────────────────

function DefenseFX.ShowPaths(paths: { { Vector2 } }?, faint: boolean?)
	for _, p in pathParts do
		p:Destroy()
	end
	table.clear(pathParts)
	if not paths then
		return
	end
	local color = Color3.fromRGB(255, 170, 60)
	for _, points in paths do
		local lens = DefenseSim.Cumulative(points)
		local total = lens[#lens]
		local d = 3
		local k = 0
		while d < total - 2 do
			local p, dir = DefenseSim.PointAt(points, lens, d)
			local at = world(p, 0.25)
			k += 1
			local part: Part
			if k % 5 == 0 then
				-- Ok: yönü gösteren ince üçgen yerine iki çubuk
				part = fxPart("PathArrow", Vector3.new(0.3, 0.3, 2.6), CFrame.lookAt(at, at + Vector3.new(dir.X, 0, dir.Y)), color)
				for _, s in { -1, 1 } do
					local wing = fxPart("PathArrow", Vector3.new(0.3, 0.3, 1.6),
						CFrame.lookAt(at, at + Vector3.new(dir.X, 0, dir.Y)) * CFrame.new(s * 0.5, 0, -0.6) * CFrame.Angles(0, math.rad(s * 35), 0), color)
					wing.Transparency = if faint then 0.75 else 0.15
					table.insert(pathParts, wing)
				end
			else
				part = fxPart("PathDot", Vector3.new(0.12, 0.7, 0.7), CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder)
			end
			part.Transparency = if faint then 0.75 else 0.15
			table.insert(pathParts, part)
			d += 3
		end
	end
end

local function ring(name: string, color: Color3): Part
	local p = fxPart(name, Vector3.new(0.15, 4, 4), CFrame.new(), color, Enum.PartType.Cylinder)
	p.Transparency = 0.55
	return p
end

--[[ Yerleştirme imleci: geçerliyse yeşil, değilse kırmızı. nil = gizle. ]]
function DefenseFX.Marker(p: Vector2?, ok: boolean, range: number?)
	if not p then
		if marker then
			marker:Destroy()
			marker = nil
		end
		if rangeRing then
			rangeRing:Destroy()
			rangeRing = nil
		end
		return
	end
	local m = marker or ring("PlaceMarker", WHITE)
	marker = m
	m.Color = if ok then Color3.fromRGB(90, 255, 120) else Color3.fromRGB(255, 80, 80)
	m.Size = Vector3.new(0.15, DefenseConfig.UnitSpacing * 2, DefenseConfig.UnitSpacing * 2)
	m.CFrame = CFrame.new(world(p, 0.2)) * CFrame.Angles(0, 0, math.rad(90))
	if range and range > 0 then
		local r = rangeRing or ring("RangeRing", Color3.fromRGB(255, 255, 255))
		rangeRing = r
		r.Transparency = 0.85
		r.Size = Vector3.new(0.1, range * 2, range * 2)
		r.CFrame = CFrame.new(world(p, 0.15)) * CFrame.Angles(0, 0, math.rad(90))
	elseif rangeRing then
		rangeRing:Destroy()
		rangeRing = nil
	end
end

--[[ Seçili crewmate'in altında halka ve menzili. ]]
function DefenseFX.Select(uid: number?)
	if selectRing then
		selectRing:Destroy()
		selectRing = nil
	end
	local view = uid and units[uid]
	if not view then
		return
	end
	local role = DefenseConfig.Roles[view.role]
	local r = ring("SelectRing", role.color)
	r.Transparency = 0.6
	local range = math.max(role.range, role.healRange or 0)
	r.Size = Vector3.new(0.1, range * 2, range * 2)
	r.CFrame = CFrame.new(view.base.Position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	selectRing = r
end

--[[ Her şeyi kaldırır (koşu bitti / gezegenden ayrıldı). ]]
--[[ Hazırlık mı (yerdekiler geri alınabilir), savaş mı. ]]
function DefenseFX.SetPrep(flag: boolean)
	prepMode = flag
	for _, view in units do
		view.prompt.Enabled = flag and not view.fallen
	end
end

function DefenseFX.OnPickup(handler: (number) -> ())
	pickupHandler = handler
end

function DefenseFX.Clear()
	for _, view in enemies do
		view.model:Destroy()
	end
	table.clear(enemies)
	if bossEid then
		showBoss(nil, nil)
	end
	for _, view in units do
		view.model:Destroy()
		view.area:Destroy()
	end
	table.clear(units)
	DefenseFX.ShowPaths(nil)
	DefenseFX.Marker(nil, false)
	DefenseFX.Select(nil)
end

function DefenseFX.ClearEnemies()
	for _, view in enemies do
		view.model:Destroy()
	end
	table.clear(enemies)
	if bossEid then
		showBoss(nil, nil)
	end
end

-- ─── Kare kare ──────────────────────────────────────────────────────────────

function DefenseFX.Start()
	-- Sarsıntı kameranın kendi güncellemesinden SONRA, sönümlenerek
	RunService:BindToRenderStep("DefenseShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		if shake <= 0.001 then
			return
		end
		local camera = workspace.CurrentCamera
		local s = shake * shake
		camera.CFrame = camera.CFrame * CFrame.new((math.random() - 0.5) * 0.7 * s, (math.random() - 0.5) * 0.7 * s, 0)
			* CFrame.Angles(0, 0, (math.random() - 0.5) * 0.02 * s)
		shake = math.max(0, shake - dt * 2.8)
	end)
	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		for _, view in enemies do
			local a = math.clamp((now - view.t0) / SNAP_GAP, 0, 1)
			local pos = view.from:Lerp(view.to, a)
			local move = view.to - view.from
			if move.Magnitude > 0.05 then
				view.facing = view.facing:Lerp(move.Unit, math.min(1, dt * 10))
			end
			local foe = if view.foe ~= 0 then units[view.foe] else nil
			local face = view.facing
			if foe and not foe.fallen then
				local toFoe = (foe.base.Position - pos) * Vector3.new(1, 0, 1)
				if toFoe.Magnitude > 0.1 then
					face = toFoe.Unit
				end
			end
			-- Yürürken zıplama, vururken öne atılma
			local walking = move.Magnitude > 0.05
			local bob = if walking then math.abs(math.sin(now * 9 + view.t0)) * 0.35 else 0
			-- Jöle: gövde esneyip sıkışıyor (yürürken daha çok)
			local mesh = view.mesh
			view.squash = math.max(0, view.squash - dt * 5)
			if mesh then
				local w = math.sin(now * (if walking then 9 else 4) + view.t0) * (if walking then 0.09 else 0.05)
				-- Vurulunca ezilip geri zıplıyor (yaylı)
				local s = view.squash
				local q = math.sin(s * math.pi * 1.5) * s * 0.28
				mesh.Scale = Vector3.new(1 + w + q, 1 - w - q, 1 + w + q)
			elseif view.meshSize and view.body then
				-- 3D ağ: aynı esneme Size ile; ayaklar yerden kalkmasın diye
				-- gövde ezildiği kadar aşağı (aşağıda "sink")
				local w = math.sin(now * (if walking then 9 else 4) + view.t0) * (if walking then 0.07 else 0.04)
				local s = view.squash
				local q = math.sin(s * math.pi * 1.5) * s * 0.22
				view.body.Size = view.meshSize * Vector3.new(1 + w + q, 1 - w - q, 1 + w + q)
			end
			local sink = if view.meshSize and view.body then (view.meshSize.Y - view.body.Size.Y) / 2 else 0
			if view.flash > 0 then
				view.flash = math.max(0, view.flash - dt * 6)
				if view.body then
					view.body.Color = view.bodyColor:Lerp(Color3.new(1, 1, 1), view.flash * 0.9)
				end
				local glow = view.glow
				if glow then
					glow.Enabled = view.flash > 0.02
					glow.FillTransparency = 1 - 0.75 * view.flash
				end
			end
			view.knock *= math.exp(-dt * 8)
			view.lunge = math.max(0, view.lunge - dt * 5)
			local lunge = face * (math.sin(view.lunge * math.pi) * 0.9)
			local at = pos + Vector3.new(0, bob - sink, 0) + lunge + view.knock
			if face.Magnitude > 0.01 then
				local cf = CFrame.lookAt(at, at + Vector3.new(face.X, 0, face.Z))
				local rig = view.rig
				if rig then
					-- Çıkarken kükrüyor, vururken kavrıyor
					local age = now - view.born
					local roar = if age < 1.6 then math.sin(math.clamp(age / 1.6, 0, 1) * math.pi) else 0
					local ok = pcall(function()
						local rp = pos + view.knock
						rig:Pose(CFrame.lookAt(rp, rp + Vector3.new(face.X, 0, face.Z)), now,
							{ sway = 1.2, rate = 1.4, grab = math.sin(view.lunge * math.pi), roar = roar })
					end)
					if not ok then
						view.rig = nil
					end
				else
					view.model:PivotTo(cf)
				end
			end
		end
		for _, view in units do
			if not view.fallen then
				view.lunge = math.max(0, view.lunge - dt * 6)
				local fall = math.clamp((now - view.born) / DROP_TIME, 0, 1)
				local walk = view.to - view.from
				local moving = walk.Magnitude > 0.15
				local lerpA = math.clamp((now - view.t0) / SNAP_GAP, 0, 1)
				local stand = view.from:Lerp(view.to, lerpA)
				local step = if moving then math.abs(math.sin(now * 10 + view.uid)) * 0.45 else 0
				local offset = view.lungeDir * (math.sin(view.lunge * math.pi) * 0.8)
					+ Vector3.new(0, DROP_HEIGHT * (1 - fall) * (1 - fall) + step, 0)
				local base = CFrame.new(stand) * view.base.Rotation
				local look = if moving then (walk * Vector3.new(1, 0, 1)).Unit
					elseif view.lungeDir.Magnitude > 0.01 then view.lungeDir else base.LookVector
				-- Darbe: geri tepme, geriye eğilme, kırmızı parlama
				view.knock *= math.exp(-dt * 9)
				view.hurt = math.max(0, view.hurt - dt * 3.5)
				local h = view.hurt
				-- Canı azsa kırmızı nabız (yardım lazım, belli olsun)
				local low = if view.hpFrac < 0.3 then 0.25 + 0.2 * math.sin(now * 9) else 0
				local g = math.max(h, low)
				view.hurtGlow.Enabled = g > 0.02
				view.hurtGlow.FillTransparency = 1 - 0.6 * g
				view.hurtGlow.OutlineTransparency = 1 - 0.7 * g
				-- Boşta hafif nefes
				local p = base.Position + offset + view.knock + Vector3.new(0, math.sin(now * 2.2 + view.uid) * 0.06, 0)
				local cf = CFrame.lookAt(p, p + Vector3.new(look.X, 0, look.Z))
					* CFrame.Angles(math.rad(-16 * math.sin(h * math.pi)), 0, math.rad(6 * math.sin(h * math.pi * 2)))
				view.model:PivotTo(cf)
				local weapon = view.weapon
				if weapon and weapon.Parent then
					view.swing = math.max(0, view.swing - dt * 4)
					weapon:PivotTo(cf * view.hand * weaponPose(view.role, view.swing, now + view.uid))
				end
			end
		end
	end)
end

return DefenseFX
