--!strict
--[[
	Petleri sahiplerinin peşinden İSTEMCİDE yürütür — bütün oyuncuların
	petlerini, her karede.

	═══ NEDEN İSTEMCİDE ════════════════════════════════════════════════════

	Eskiden sunucu her Heartbeat'te petleri PivotTo ile taşıyordu. Anchored
	parçanın konumu istemciye ağdan saniyede ~20 kez ve gecikmeyle
	geliyordu: pet kesik kesik ilerliyor, sahibinin arkasında "laglı"
	kalıyordu. Karakterler akıcı çünkü Roblox onların konumunu istemcide
	aradeğerliyor; petler için böyle bir şey yok.

	Artık sunucu peti yalnızca kuruyor ve kimin olduğunu nitelikle
	söylüyor (OwnerId, Slot, SlotCount — PetService.Respawn). Her istemci
	sahibin karakterini izleyip peti kendi karesinde, kare hızından
	bağımsız yumuşatmayla (1 - e^-kt) konumluyor. Sunucu petleri hiç
	taşımadığı için yerel konumla çakışan bir güncelleme de gelmiyor.

	═══ HAREKET ════════════════════════════════════════════════════════════

	  Yürüyenler (blob, yengeç, robot): yerde; sahibi yürürken zıplayarak
	    geliyor (zıplamanın tepesinde öne eğik), dururken hafifçe nefes
	    alıyor.
	  Uçanlar (küre, kristal): yerden bir boy yukarıda süzülüyor, yürürken
	    hafif dalgalanıyor.
	  Hepsi gittiği yöne dönüyor, dururken sahibinin baktığı yöne.
	  Altlarında yuvarlak bir gölge: petin yere "bastığını" gösteren şey;
	    zıplarken küçülüp soluyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PetModel = require(Shared.PetModel)

local PetFollow = {}

local FOLLOW_RATE = 9        -- konum yumuşatması (büyük = sıkı takip)
local TURN_RATE = 8          -- dönüş yumuşatması
local SNAP_DISTANCE = 70     -- bundan uzaksa ışınla (doğuş, vent, ışınlanma)
local FLY_HEIGHT = 1.3       -- uçan petin tabanı yerden ne kadar yukarıda
local HOP_HEIGHT = 0.85      -- yürüyen petin zıplama yüksekliği (düz boyda)
local HOP_RATE = 11          -- zıplama hızı (rad/sn), sahibin hızıyla ölçekleniyor

type State = {
	model: Model,
	pos: Vector3,       -- tabanın (ayakların) yumuşatılmış konumu
	yaw: number,
	phase: number,      -- zıplama / dalga fazı
	flying: boolean,
	shadow: BasePart?,
	seed: number,
}

local states: { [Model]: State } = {}

local function flyingForm(model: Model): boolean
	local tag = model:FindFirstChild("PetId")
	local form = if tag and tag:IsA("StringValue") then PetModel.FormOf(tag.Value) else "blob"
	return form == "orb" or form == "shard"
end

local function numberAttr(model: Model, name: string, default: number): number
	local v = model:GetAttribute(name)
	return if typeof(v) == "number" then v else default
end

local shadowFolder: Folder? = nil

local function makeShadow(model: Model): BasePart
	if not shadowFolder then
		local f = Instance.new("Folder")
		f.Name = "PetShadows"
		f.Parent = workspace
		shadowFolder = f
	end
	local radius = numberAttr(model, "Radius", 1.2)
	local p = Instance.new("Part")
	p.Name = "PetShadow"
	p.Shape = Enum.PartType.Cylinder
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = Color3.new(0, 0, 0)
	p.Transparency = 0.62
	p.Size = Vector3.new(0.05, radius * 1.5, radius * 1.5)
	p.Parent = shadowFolder
	return p
end

local function track(model: Model)
	if states[model] or not model:IsA("Model") then
		return
	end
	local pivot = model:GetPivot()
	states[model] = {
		model = model,
		pos = pivot.Position - Vector3.new(0, numberAttr(model, "Lift", 1), 0),
		yaw = 0,
		phase = math.random() * math.pi * 2,
		flying = flyingForm(model),
		shadow = makeShadow(model),
		seed = math.random() * 10,
	}
end

local function untrack(model: Instance)
	local s = states[model :: Model]
	if s then
		if s.shadow then
			s.shadow:Destroy()
		end
		states[model :: Model] = nil
	end
end

-- Sahibin ayak hizası ve yere göre hızı
local function ownerInfo(userId: number): (CFrame?, number, number)
	local owner = Players:GetPlayerByUserId(userId)
	local character = owner and owner.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		return nil, 0, 0
	end
	local feetY = root.Position.Y - humanoid.HipHeight - root.Size.Y / 2
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	return root.CFrame, feetY, speed
end

local function step(dt: number)
	if dt <= 0 then
		return
	end
	local follow = 1 - math.exp(-FOLLOW_RATE * dt)
	local turn = 1 - math.exp(-TURN_RATE * dt)

	-- Sahibe göre grupla: aralık en geniş petin yarıçapına göre açılıyor
	local widest: { [number]: number } = {}
	for model, _ in states do
		local owner = numberAttr(model, "OwnerId", 0)
		widest[owner] = math.max(widest[owner] or 0, numberAttr(model, "Radius", 1.5))
	end

	for model, s in states do
		if not model.Parent then
			continue
		end
		local ownerId = numberAttr(model, "OwnerId", 0)
		local rootCf, feetY, speed = ownerInfo(ownerId)
		if not rootCf then
			-- Sahibi yok ya da öldü: pet olduğu yerde bekliyor, gölgesi de
			continue
		end

		local slot = numberAttr(model, "Slot", 1)
		local count = math.max(1, numberAttr(model, "SlotCount", 1))
		local radius = numberAttr(model, "Radius", 1.5)
		local lift = numberAttr(model, "Lift", 1)
		local scale = math.max(1, radius / 1.2)

		-- Yay: tek pet tam arkada, üç pet -1/0/+1 sütunlarda; kenardakiler biraz geride
		local spread = if count > 1 then (slot - 1) / (count - 1) - 0.5 else 0
		local gap = math.max(5.5, (widest[ownerId] or radius) * 2.5 + 1)
		local offset = Vector3.new(spread * gap, 0, 3 + radius + math.abs(spread) * 1.4)
		local flatLook = Vector3.new(rootCf.LookVector.X, 0, rootCf.LookVector.Z)
		if flatLook.Magnitude < 1e-3 then
			flatLook = Vector3.new(0, 0, -1)
		end
		local base = CFrame.lookAt(Vector3.new(rootCf.Position.X, feetY, rootCf.Position.Z),
			Vector3.new(rootCf.Position.X, feetY, rootCf.Position.Z) + flatLook.Unit)
		local target = (base * CFrame.new(offset)).Position

		-- Uzaksa ışınla; değilse yatayda yumuşat, dikeyde (merdiven) biraz daha sıkı
		local delta = target - s.pos
		if delta.Magnitude > SNAP_DISTANCE then
			s.pos = target
		else
			local horizontal = Vector3.new(s.pos.X, 0, s.pos.Z):Lerp(Vector3.new(target.X, 0, target.Z), follow)
			local y = s.pos.Y + (target.Y - s.pos.Y) * math.min(1, follow * 1.6)
			s.pos = Vector3.new(horizontal.X, y, horizontal.Z)
		end

		-- Yön: hareket ediyorsa gittiği yöne, duruyorsa sahibinin baktığı yöne
		local moving = speed > 1.5 or Vector3.new(delta.X, 0, delta.Z).Magnitude > 1.2
		local wantYaw: number
		local dir = Vector3.new(delta.X, 0, delta.Z)
		if moving and dir.Magnitude > 0.2 then
			wantYaw = math.atan2(-dir.X, -dir.Z)
		else
			wantYaw = math.atan2(-flatLook.X, -flatLook.Z)
		end
		local diff = (wantYaw - s.yaw + math.pi) % (math.pi * 2) - math.pi
		s.yaw += diff * turn

		-- Zıplama / süzülme
		local rate = HOP_RATE * math.clamp(speed / 16, 0.6, 1.6)
		local height: number
		local pitch, roll = 0, 0
		local shadowK = 1
		if s.flying then
			s.phase += dt * (if moving then 4.2 else 2.2)
			height = FLY_HEIGHT * scale + math.sin(s.phase + s.seed) * (if moving then 0.28 else 0.18) * scale
			pitch = if moving then math.rad(-10) else 0
			roll = math.sin(s.phase * 0.5 + s.seed) * math.rad(5)
			shadowK = 0.8
		elseif moving then
			s.phase += dt * rate
			local hop = math.abs(math.sin(s.phase))
			height = hop * HOP_HEIGHT * scale
			-- Havadayken öne eğik, inerken yana hafif sallanma
			pitch = math.rad(-12) * hop
			roll = math.sin(s.phase) * math.rad(6)
			shadowK = 1 - hop * 0.45
		else
			-- Dururken nefes: çok küçük iniş çıkış
			s.phase += dt * 2.4
			height = (math.sin(s.phase + s.seed) * 0.5 + 0.5) * 0.12 * scale
			roll = 0
			shadowK = 1
		end

		local pivot = CFrame.new(s.pos + Vector3.new(0, lift + height, 0))
			* CFrame.Angles(0, s.yaw, 0)
			* CFrame.Angles(pitch, 0, roll)
		model:PivotTo(pivot)

		local shadow = s.shadow
		if shadow then
			local d = radius * 1.5 * shadowK
			shadow.Size = Vector3.new(0.05, d, d)
			shadow.CFrame = CFrame.new(s.pos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
			shadow.Transparency = 0.62 + (1 - shadowK) * 0.3
		end
	end
end

function PetFollow.Start()
	task.spawn(function()
		local folder = workspace:WaitForChild("Pets", math.huge)
		for _, model in folder:GetChildren() do
			if model:IsA("Model") then
				track(model)
			end
		end
		folder.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				-- Nitelikler ve PetId aynı karede gelmeyebilir: bir kare bekle
				task.defer(track, child)
			end
		end)
		folder.ChildRemoved:Connect(untrack)
	end)
	RunService:BindToRenderStep("PetFollow", Enum.RenderPriority.Camera.Value - 1, step)
end

return PetFollow
