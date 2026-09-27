--!strict
--[[
	Gezegenlere giden yolun içi (2026-09-28: "yol çok boş, oyuncu daha
	hevesli olsun"). Geometri shared/SpaceField'da (Routes, Rings,
	StardustSpots, CrateSpots, RockClusters), sayılar Config.SpaceBonus'ta.

	  Hız halkaları   — içinden geçince kısa hız patlaması. Yalnızca görsel
	                    burada; geçişi ve patlamayı istemci (SpaceFX) ölçüyor,
	                    uçuş zaten istemcide.
	  Yıldız tozu     — rota boyunca kümeler; dokunana küçük para. 30 sn
	                    sonra yeniden beliriyor.
	  Tedarik sandığı — her rotada bir tane: büyük para, şansla bir iksir.
	  Asteroit kuşağı — rotanın yanlarında katı kayalar: kestirme yapan
	                    çarpıp yavaşlıyor.
	  Gezegen panosu  — Launch Bay'de: her canavarın adı, gereken hız ve
	                    verdiği en nadir mürettebat.
	  Golden Comet    — olay (EventService "Comet"): uzaydan geçen altın
	                    kuyruklu yıldız; ilk dokunan mutasyonlu bir mürettebat
	                    ve büyük para kazanıyor.

	Toplama SUNUCUDA: oyuncunun konumu replike, sunucu mesafeye bakıyor.
	İstemciden yeni bir remote dinlenmiyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SpaceField = require(Shared.SpaceField)

local EconomyService = require(script.Parent.EconomyService)
local PotionService = require(script.Parent.PotionService)
local SpaceService = require(script.Parent.SpaceService)

local SpaceBonusService = {}

SpaceBonusService.NotifyKind = "reward"

type Pickup = { part: BasePart, position: Vector3, readyAt: number, kind: string }

local notifyRemote: RemoteEvent? = nil
local fxRemote: RemoteEvent? = nil
local root: Model? = nil
local pickups: { Pickup } = {}
local rng = Random.new()
local paused = false

type Comet = { part: BasePart, from: Vector3, to: Vector3, startedAt: number, duration: number, done: boolean }
local comet: Comet? = nil

local function notify(player: Player, text: string, isError: boolean, kind: string?)
	if notifyRemote and player.Parent then
		notifyRemote:FireClient(player, text, isError, kind or SpaceBonusService.NotifyKind)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local r = character and character:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

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

--[[ Gelire göre ödül: saniyelik gelir × saniye, en az taban. ]]
local function rewardFor(player: Player, seconds: number, minimum: number): number
	return math.floor(math.max(minimum, EconomyService.GetIncome(player) * seconds))
end

-- ─── Kurulum ────────────────────────────────────────────────────────────────

local RING = Color3.fromRGB(90, 230, 255)
local DUST = Color3.fromRGB(255, 236, 140)
local GOLD = Color3.fromRGB(255, 196, 40)
local ROCK = Color3.fromRGB(86, 80, 96)

local function buildRing(folder: Instance, ring: SpaceField.Ring, index: number)
	local model = Instance.new("Model")
	model.Name = "Ring" .. index
	local segments = 10
	local r = ring.radius
	for k = 0, segments - 1 do
		local a = (k + 0.5) / segments * math.pi * 2
		local p = ring.cf * CFrame.new(math.cos(a) * r, math.sin(a) * r, 0)
		local length = 2 * r * math.sin(math.pi / segments) + 0.4
		part(model, "RingSeg", Vector3.new(length, 0.9, 0.9), CFrame.lookAt(p.Position, p.Position + ring.cf.LookVector)
			* CFrame.Angles(0, 0, a + math.pi / 2), RING,
			{ Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	end
	-- İçi hafif parlıyor (uzaktan halka okunsun)
	part(model, "RingGlow", Vector3.new(0.2, r * 2 - 1, r * 2 - 1), ring.cf * CFrame.Angles(0, math.rad(90), 0), RING,
		{ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Transparency = 0.88,
			CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	model:SetAttribute("SpaceRing", index)
	model.Parent = folder
end

local function buildCrate(folder: Instance, position: Vector3, index: number): BasePart
	local model = Instance.new("Model")
	model.Name = "Crate" .. index
	local body = part(model, "CrateBody", Vector3.new(4.4, 3.4, 3.4), CFrame.new(position) * CFrame.Angles(0.2, index, 0.1),
		Color3.fromRGB(70, 74, 92), { Material = Enum.Material.DiamondPlate, CanCollide = false })
	for _, y in { -1.2, 1.2 } do
		part(model, "CrateBand", Vector3.new(4.6, 0.35, 3.6), body.CFrame * CFrame.new(0, y, 0), GOLD,
			{ Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
	end
	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = 14
	light.Brightness = 1.6
	light.Parent = body
	local gui = Instance.new("BillboardGui")
	gui.Name = "CrateLabel"
	gui.Size = UDim2.fromOffset(170, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 20
	label.TextColor3 = GOLD
	label.Text = "SUPPLY CRATE"
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(30, 20, 10)
	stroke.Parent = label
	gui.Parent = body
	model.PrimaryPart = body
	model.Parent = folder
	return body
end

local function buildRocks(folder: Instance, cluster: SpaceField.RockCluster)
	local r = Random.new(cluster.seed)
	-- 9 → 5 kaya: "biraz dolu görünsün ama kalabalık olmasın"
	for k = 1, 5 do
		local size = r:NextNumber(4, 13)
		local p = cluster.center + Vector3.new(r:NextNumber(-1, 1), r:NextNumber(-0.6, 0.6), r:NextNumber(-1, 1)) * cluster.radius
		part(folder, "Asteroid", Vector3.new(size, size * r:NextNumber(0.6, 1), size * r:NextNumber(0.7, 1.2)),
			CFrame.new(p) * CFrame.Angles(r:NextNumber(0, 6), r:NextNumber(0, 6), r:NextNumber(0, 6)), ROCK:Lerp(Color3.fromRGB(120, 100, 90), r:NextNumber()),
			{ Material = Enum.Material.Rock, CastShadow = false })
		if k % 3 == 0 then
			-- Kayanın içinden sızan sıcak ışık: karanlıkta kuşak okunuyor
			local glow = part(folder, "AsteroidGlow", Vector3.one * size * 0.35, CFrame.new(p), Color3.fromRGB(255, 120, 60),
				{ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CastShadow = false })
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 130, 70)
			light.Range = size * 1.6
			light.Brightness = 1
			light.Parent = glow
		end
	end
end

--[[ Launch Bay'deki gezegen panosu: her canavarın adı, gereken hız, en nadir ödülü. ]]
local function buildBoard(folder: Instance)
	local s = Config.Space
	local center = SpaceField.DeckCenter()
	-- Güvertenin SAĞ yanında (solda bilgi panosu ve jetpack standı var; üst üste biniyordu)
	local p = Vector3.new(s.GateX + s.DeckHalfWidth - 10, s.DeckTop + 9, center.Z + 6)
	local board = part(folder, "PlanetBoard", Vector3.new(18, 13, 0.6), CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z + 30)),
		Color3.fromRGB(18, 22, 40), { Material = Enum.Material.SmoothPlastic })
	part(folder, "PlanetBoardFrame", Vector3.new(19, 14, 0.4), board.CFrame * CFrame.new(0, 0, 0.25), Color3.fromRGB(80, 200, 255),
		{ Material = Enum.Material.Neon, CanCollide = false })
	part(folder, "PlanetBoardLeg", Vector3.new(1, p.Y - s.DeckTop - 6.5, 1), CFrame.new(p.X, (s.DeckTop + p.Y - 6.5) / 2, p.Z), Color3.fromRGB(60, 66, 80))
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlanetList"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0
	gui.Parent = board
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 4)
	list.Parent = gui
	local function line(text: string, size: number, color: Color3, order: number)
		local t = Instance.new("TextLabel")
		t.LayoutOrder = order
		t.Size = UDim2.new(1, -20, 0, size * 1.25)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.FredokaOne
		t.TextSize = size
		t.TextColor3 = color
		t.Text = text
		t.RichText = true
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(10, 12, 24)
		stroke.Parent = t
		t.Parent = gui
	end
	line("SPACE HEIST TARGETS", 44, Color3.fromRGB(120, 220, 255), 0)
	local ladder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
	for i, def in Config.SpaceMonsters do
		local best = "Common"
		for _, name in ladder do
			if def.odds[name] then
				best = name
			end
		end
		local color = Config.GetTitleColor(best)
		line(string.format('%d. %s  <font color="#FFE13C">%d SPEED</font>  <font color="#%s">up to %s</font>',
			i, string.upper(def.name), def.need, color:ToHex(), best), 30, Color3.new(1, 1, 1), i)
	end
	line("Train in your capsule to reach the far planets!", 24, Color3.fromRGB(170, 255, 170), 99)
end

local function build()
	local old = workspace:FindFirstChild("SpaceBonus")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "SpaceBonus"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	--[[
		2026-09-28 (Yusuf): hız halkaları ("uzaydaki mavi çemberler") ve para
		veren yıldız tozu ("küçük daireler") KALKTI. Hızı artık jetpack veriyor
		(JetpackService), bedava para enflasyon yapıyordu. buildRing ve
		SpaceField.Rings/StardustSpots duruyor ama kullanılmıyor.
	]]
	table.clear(pickups)
	local _ = { buildRing, DUST }

	local crates = Instance.new("Folder")
	crates.Name = "Crates"
	crates.Parent = model
	for i, p in SpaceField.CrateSpots() do
		local body = buildCrate(crates, p, i)
		table.insert(pickups, { part = body, position = p, readyAt = 0, kind = "crate" })
	end

	local rocks = Instance.new("Folder")
	rocks.Name = "AsteroidBelts"
	rocks.Parent = model
	for _, cluster in SpaceField.RockClusters() do
		buildRocks(rocks, cluster)
	end

	buildBoard(model)
	model.Parent = workspace
	root = model
end

-- ─── Toplama ────────────────────────────────────────────────────────────────

local function setVisible(pickup: Pickup, on: boolean)
	local model = if pickup.kind == "crate" then pickup.part.Parent else nil
	local parts: { Instance } = if model then model:GetDescendants() else { pickup.part }
	for _, d in parts do
		if d:IsA("BasePart") then
			d.Transparency = if on then (if d.Name == "RingGlow" then 0.88 else 0) else 1
		elseif d:IsA("BillboardGui") or d:IsA("PointLight") then
			(d :: any).Enabled = on
		end
	end
end

local function collect(player: Player, pickup: Pickup, now: number)
	local b = Config.SpaceBonus
	if pickup.kind == "stardust" then
		pickup.readyAt = now + b.StardustRespawn
		setVisible(pickup, false)
		local amount = rewardFor(player, b.StardustIncomeSeconds, b.StardustMin)
		EconomyService.AddCash(player, amount)
		if fxRemote then
			fxRemote:FireClient(player, "bonus", "stardust", amount, pickup.position)
		end
	else
		pickup.readyAt = now + b.CrateRespawn
		setVisible(pickup, false)
		local amount = rewardFor(player, b.CrateIncomeSeconds, b.CrateMin)
		EconomyService.AddCash(player, amount)
		local potionText = ""
		if rng:NextNumber() < b.CratePotionChance then
			local def = Config.RollPotion(rng)
			if PotionService.Grant(player, def.id, 1) then
				potionText = " + " .. def.name .. " potion"
			end
		end
		notify(player, string.format("SUPPLY CRATE! +$%s%s", Config.FormatCash(amount), potionText), false)
		if fxRemote then
			fxRemote:FireClient(player, "bonus", "crate", amount, pickup.position)
		end
	end
end

local function stepPickups()
	local now = os.clock()
	local b = Config.SpaceBonus
	for _, pickup in pickups do
		if pickup.readyAt > 0 and now >= pickup.readyAt then
			pickup.readyAt = 0
			setVisible(pickup, true)
		end
	end
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("InSpace") ~= true or player:GetAttribute("SpaceGrabbed") then
			continue
		end
		local r = rootOf(player)
		if not r then
			continue
		end
		local pos = r.Position
		for _, pickup in pickups do
			if pickup.readyAt == 0 then
				local reach = if pickup.kind == "crate" then b.CrateRadius else b.StardustRadius
				if (pickup.position - pos).Magnitude <= reach then
					collect(player, pickup, now)
				end
			end
		end
	end
end

-- ─── Golden Comet ───────────────────────────────────────────────────────────

--[[
	Kuyruklu yıldızı başlatır: uzayın bir ucundan öbürüne, rotaların üstünden
	geçen bir yayla. İlk dokunan kazanır; kimse yakalamazsa süre dolunca biter.
	Olay sistemi (EventService) çağırıyor; dönen fonksiyon temizlik.
]]
function SpaceBonusService.StartComet(): () -> ()
	SpaceBonusService.StopComet()
	local s = Config.Space
	local b = Config.SpaceBonus
	local last = Config.SpaceMonsters[#Config.SpaceMonsters]
	local from = Vector3.new(s.BoundsMin.X + 40, 60, SpaceField.DeckEdgeZ() - 160)
	local to = Vector3.new(s.BoundsMax.X - 40, 30, last.position.Z + 300)
	local duration = (to - from).Magnitude / b.CometSpeed
	local core = part(workspace, "GoldenComet", Vector3.one * 5, CFrame.new(from), Color3.fromRGB(255, 220, 90),
		{ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 2, 0)
	a0.Parent = core
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -2, 0)
	a1.Parent = core
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 1.6
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 120, 30))
	trail.Transparency = NumberSequence.new(0, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Parent = core
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 90)
	light.Range = 40
	light.Brightness = 3
	light.Parent = core
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 6, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 26
	label.TextColor3 = Color3.fromRGB(255, 225, 90)
	label.Text = "★ GOLDEN COMET ★"
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(60, 30, 0)
	stroke.Parent = label
	gui.Parent = core
	comet = { part = core, from = from, to = to, startedAt = os.clock(), duration = duration, done = false }
	return function()
		SpaceBonusService.StopComet()
	end
end

function SpaceBonusService.StopComet()
	local c = comet
	comet = nil
	if c and c.part.Parent then
		c.part:Destroy()
	end
end

function SpaceBonusService.GetComet(): BasePart?
	return if comet then comet.part else nil
end

local function stepComet()
	local c = comet
	if not c or c.done then
		return
	end
	local u = (os.clock() - c.startedAt) / c.duration
	if u >= 1 then
		SpaceBonusService.StopComet()
		return
	end
	local pos = c.from:Lerp(c.to, u) + Vector3.new(0, math.sin(u * math.pi) * 60, 0)
	c.part.CFrame = CFrame.new(pos)
	for _, player in Players:GetPlayers() do
		local r = rootOf(player)
		if r and player:GetAttribute("InSpace") == true and (r.Position - pos).Magnitude <= Config.SpaceBonus.CometRadius then
			c.done = true
			local b = Config.SpaceBonus
			local amount = rewardFor(player, b.CometIncomeSeconds, b.CometMin)
			EconomyService.AddCash(player, amount)
			local unitId, mutationId = SpaceService.GrantUnit(player, true, 1)
			local extra = ""
			if unitId then
				local def = Config.GetUnit(unitId)
				local mutation = Config.GetMutation(mutationId)
				extra = string.format(" + a %s%s", if mutation then mutation.name .. " " else "", if def then def.name else unitId)
			end
			notify(player, string.format("YOU CAUGHT THE GOLDEN COMET! +$%s%s", Config.FormatCash(amount), extra), false, "spin")
			for _, other in Players:GetPlayers() do
				if other ~= player then
					notify(other, string.format("%s caught the Golden Comet!", player.DisplayName), false, "event")
				end
			end
			if fxRemote then
				fxRemote:FireClient(player, "bonus", "comet", amount, pos)
			end
			SpaceBonusService.StopComet()
			return
		end
	end
end

-- ─── Testler için ───────────────────────────────────────────────────────────

function SpaceBonusService._Pickups(): { Pickup }
	return pickups
end

function SpaceBonusService._Collect(player: Player, index: number): boolean
	local pickup = pickups[index]
	if not pickup or pickup.readyAt > 0 then
		return false
	end
	collect(player, pickup, os.clock())
	return true
end

function SpaceBonusService._Respawn()
	for _, pickup in pickups do
		pickup.readyAt = 0
		setVisible(pickup, true)
	end
end

function SpaceBonusService.SetPaused(value: boolean)
	paused = value
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

function SpaceBonusService.Start()
	notifyRemote = Net.Get("Notify")
	fxRemote = Net.Get("SpaceFX")
	build()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		stepComet()
		acc += dt
		if acc < 0.1 or paused then
			return
		end
		acc = 0
		stepPickups()
	end)
end

return SpaceBonusService
