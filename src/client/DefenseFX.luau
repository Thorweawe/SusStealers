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
local UNIT_HEIGHT = 5.6
local ENEMY_SCALE = 1.3
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
	bodyColor: Color3,
	flash: number,             -- vurulunca beyaz parlama 1 → 0
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
	hand: CFrame,              -- silahın modele göre yeri
	swing: number,             -- vuruş animasyonu 1 → 0
	height: number,
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

local function world(p: Vector2, y: number?): Vector3
	return DefenseConfig.ToWorld(arena, p, y)
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

local function hpBar(adornee: BasePart, offset: number, width: number, color: Color3): (BillboardGui, Frame)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(width, 7)
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
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(1, 0)
	c2.Parent = fill
	return gui, fill
end

-- ─── Gezegen ────────────────────────────────────────────────────────────────

function DefenseFX.SetArena(index: number)
	arena = index
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
	model:SetAttribute("DefenseUid", info.uid)
	model.Parent = root()

	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart") :: BasePart
	local gui, fill = hpBar(anchor, height + 1.2, 60, Color3.fromRGB(90, 230, 110))
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
	gui.Size = UDim2.fromOffset(60, 8)
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
			if not view.fallen then
				view.model:PivotTo(view.base)
			end
		end
	end
	for uid, view in units do
		if not seen[uid] and not view.fallen then
			view.model:Destroy()
			units[uid] = nil
		end
	end
end

function DefenseFX.ResetUnitHealth()
	for _, view in units do
		view.bar.Size = UDim2.fromScale(1, 1)
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
	Skitter = 4.6, Grub = 7, Spitter = 7.2, Brute = 11, Boss = 15,
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
		bodyColor = if body then body.Color else WHITE,
		flash = 0,
	}
	enemies[eid] = view
	if kind == "Boss" then
		SoundFX.GearSound("GearBlast", pos)
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
	local puff = fxPart("Puff", Vector3.one * 2, CFrame.new(at + Vector3.new(0, 1.5, 0)), palette.glow, Enum.PartType.Ball)
	puff.Transparency = 0.2
	fadeAway(puff, 0.35, Vector3.one * (if view.kind == "Boss" then 14 else 6))
	sound("poof", 0.12, function()
		SoundFX.GearSound("GearPoof", at)
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
		local gui, fill = hpBar(anchor, h, if view.kind == "Boss" then 100 else 44, Color3.fromRGB(255, 80, 80))
		view.bar = fill
		view.barGui = gui
	end
	if view.bar then
		view.bar.Size = UDim2.fromScale(math.clamp(hp, 0, 1), 1)
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

local function onUnitAttack(uid: number, eid: number)
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
	e.flash = 1
	local role = DefenseConfig.Roles[u.role]
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
		if def and def.range > 4.5 then
			-- Tükürük
			bolt(e.model:GetPivot().Position + Vector3.new(0, 2, 0), chest(u.model), palette.glow)
		end
	end
	if u and not u.fallen then
		floatText(chest(u.model) + Vector3.new(0, 2.5, 0), "-" .. tostring(amount), Color3.fromRGB(255, 90, 90))
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
	u.bar.Size = UDim2.fromScale(0, 1)
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
	sound("fall", 0.2, function()
		SoundFX.GearSound("GearBlast", chest(u.model))
	end)
	task.delay(1.6, function()
		if units[uid] == u then
			units[uid] = nil
		end
		u.model:Destroy()
	end)
end

local function onLeak()
	local gate = world(DefenseConfig.Field.gate, 2)
	local p = fxPart("Leak", Vector3.one * 4, CFrame.new(gate), Color3.fromRGB(255, 60, 60), Enum.PartType.Ball)
	p.Transparency = 0.2
	fadeAway(p, 0.5, Vector3.one * 16)
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
	SoundFX.GearSound("GearBlast", at)
end

local function onFreeze(seconds: number)
	for _, e in enemies do
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

--[[ Oyuncunun ışın kılıcı vuruşu: yay biçiminde parlama. ]]
local function onSlash(x: number, z: number, hits: number)
	local at = world(Vector2.new(x, z), 2.5)
	local ring = fxPart("SlashRing", Vector3.new(0.3, 4, 4), CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(140, 220, 255), Enum.PartType.Cylinder)
	ring.Transparency = 0.3
	local r = DefenseConfig.Saber.radius * 2
	fadeAway(ring, 0.25, Vector3.new(0.3, r, r))
	if hits > 0 then
		sound("saberhit", 0.08, function()
			SoundFX.GearSound("GearZap", at)
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
			onUnitAttack(ev[2], ev[3])
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
			onLeak()
		elseif kind == "strike" then
			onStrike(ev[2], ev[3])
		elseif kind == "freeze" then
			onFreeze(ev[2])
		elseif kind == "meddrop" then
			onMedDrop()
		elseif kind == "slash" then
			onSlash(ev[2], ev[3], ev[4])
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
			view.bar.Size = UDim2.fromScale(math.clamp(u[2], 0, 1), 1)
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
	for _, view in units do
		view.model:Destroy()
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
end

-- ─── Kare kare ──────────────────────────────────────────────────────────────

function DefenseFX.Start()
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
			if mesh then
				local w = math.sin(now * (if walking then 9 else 4) + view.t0) * (if walking then 0.09 else 0.05)
				mesh.Scale = Vector3.new(1 + w, 1 - w, 1 + w)
			end
			if view.flash > 0 and view.body then
				view.flash = math.max(0, view.flash - dt * 6)
				view.body.Color = view.bodyColor:Lerp(Color3.new(1, 1, 1), view.flash * 0.8)
			end
			view.lunge = math.max(0, view.lunge - dt * 5)
			local lunge = face * (math.sin(view.lunge * math.pi) * 0.9)
			local at = pos + Vector3.new(0, bob, 0) + lunge
			if face.Magnitude > 0.01 then
				local cf = CFrame.lookAt(at, at + Vector3.new(face.X, 0, face.Z))
				local rig = view.rig
				if rig then
					-- Çıkarken kükrüyor, vururken kavrıyor
					local age = now - view.born
					local roar = if age < 1.6 then math.sin(math.clamp(age / 1.6, 0, 1) * math.pi) else 0
					local ok = pcall(function()
						rig:Pose(CFrame.lookAt(pos, pos + Vector3.new(face.X, 0, face.Z)), now,
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
				local offset = view.lungeDir * (math.sin(view.lunge * math.pi) * 0.8)
					+ Vector3.new(0, DROP_HEIGHT * (1 - fall) * (1 - fall), 0)
				local base = view.base
				local look = if view.lungeDir.Magnitude > 0.01 then view.lungeDir else base.LookVector
				-- Boşta hafif nefes
				local p = base.Position + offset + Vector3.new(0, math.sin(now * 2.2 + view.uid) * 0.06, 0)
				local cf = CFrame.lookAt(p, p + Vector3.new(look.X, 0, look.Z))
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
