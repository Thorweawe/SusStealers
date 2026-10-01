--!strict
--[[
	Gezegenlerdeki mürettebatın nadirlik aurası — tamamen istemcide.

	2026-09-28 (Yusuf): "among us'ların efektlerini daha profesyonel yap,
	parçacık yayılsın, yumurtalardaki gibi güzel olsun". Sunucu yalnızca
	modeli koyuyor (SpaceService, "LostCrew" + UnitId/MutationId
	nitelikleri); süsü her istemci kendisi kuruyor, ağda bir şey taşınmıyor.

	Kademe arttıkça katman ekleniyor (zıtlık: sıradan olan sade kalsın):

	  herkes      — ayak altında nadirlik renginde parlayan halka + yumuşak disk
	  Uncommon+   — yukarı süzülen ışıltılar (sayı kademeyle artıyor)
	  Rare+       — çevresinde dönen ışık küreleri + nokta ışık
	  Legendary+  — gökyüzüne ışık sütunu + ara ara yıldız patlaması
	  mutasyonlu  — mutasyon renginde ikinci ışıltı katmanı
	  etkinlik    — etkinlik mutasyonu (STARBORN): başının üstünden yağan
	                yıldızlar, uzaktan "bu özel" desin

	Kameradan uzaktakilerin dönen parçaları güncellenmiyor (performans).

	2026-10-01 (Batur: "bu kısımdaki amonguslar çok parlıyor gezegenden
	dolayı", Glacira): açık renkli gezegende (buz, güneş) neon halka/disk/
	sütun ve ışık bloom'la birleşip crewmate'i beyaza boğuyordu. Aura artık
	gezegenin parlaklığına göre kısılıyor (dimOf): Glacira'da tam, koyu
	gezegenlerde hiç.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local CrewAura = {}

export type Handle = { Destroy: () -> () }

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-- Secret'ın Config rengi neredeyse siyah; aurada mor-beyaz görünsün
local function toneOf(rarity: string): Color3
	if rarity == "Secret" then
		return Color3.fromRGB(200, 160, 255)
	end
	local info = Config.Rarities[rarity]
	return if info then info.color else Color3.new(1, 1, 1)
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, transparency: number, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = transparency
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function sparkles(parent: Instance, color: Color3, rate: number, size: number, spread: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "AuraSparkles"
	e.Texture = SPARKLE
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(1.2, 2.2)
	e.Rate = rate
	e.Speed = NumberRange.new(1.5, 3)
	e.SpreadAngle = Vector2.new(spread, spread)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, 0.6, 0)
	e.RotSpeed = NumberRange.new(-90, 90)
	e.Parent = parent
	return e
end

type Aura = {
	model: Model,
	folder: Folder,
	base: CFrame,
	orbs: { Part },
	ring: { Part },
	spin: number,
	burst: ParticleEmitter?,
	nextBurst: number,
	dim: number,
}

--[[ Crewmate'in durduğu gezegen ne kadar açık renkli: 0 (koyu) .. 1 (buz beyazı). ]]
local function dimOf(model: Model): number
	local index = model:GetAttribute("Planet")
	local def = if typeof(index) == "number" then Config.SpaceMonsters[index] else nil
	if not def then
		return 0
	end
	local c = def.planetColor
	local lum = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	return math.clamp((lum - 0.45) / 0.35, 0, 1)
end

-- Saydamlığı parlak gezegende 1'e doğru çeker
local function fade(transparency: number, dim: number): number
	return transparency + (1 - transparency) * 0.6 * dim
end

function CrewAura.Start(): Handle
	local auras: { [Model]: Aura } = {}
	local conns: { RBXScriptConnection } = {}

	local function build(model: Model)
		if auras[model] or model.Name ~= "LostCrew" then
			return
		end
		local unitId = model:GetAttribute("UnitId")
		local def = if typeof(unitId) == "string" then Config.GetUnit(unitId) else nil
		if not def then
			return
		end
		local info = Config.Rarities[def.rarity]
		local order = if info then info.order else 1
		local tone = toneOf(def.rarity)
		local mutationId = model:GetAttribute("MutationId")
		local mutation = if typeof(mutationId) == "string" then Config.GetMutation(mutationId) else nil
		local dim = dimOf(model)

		-- Ayak = sınır kutusunun altı (etiket/prompt parçası yok, yalnızca gövde)
		local pivot = model:GetPivot()
		local cf, size = model:GetBoundingBox()
		local feet = Vector3.new(pivot.Position.X, cf.Position.Y - size.Y / 2 + 0.06, pivot.Position.Z)
		local base = CFrame.new(feet)
		local radius = math.max(2.2, math.max(size.X, size.Z) * 0.75)

		local folder = Instance.new("Folder")
		folder.Name = "CrewAura"
		folder.Parent = model

		--[[
			Ayak altı: yumuşak disk (Uncommon+) + parlak halka.
			2026-10-01 ("amongusların altında sürekli dönen şeyler"): disk ayak
			hizasındaydı ve gezegenin KAVİSLİ yüzeyine yarı gömülüyordu; yüzeyle
			çakışan kısımları titreşip kamera dönünce dönen beyaz kıymıklar gibi
			görünüyordu (en çok Common'ın soluk beyaz diskinde). Common'da disk
			yok, diğerlerinde biraz yukarıda.
		]]
		if order >= 2 then
			part(folder, "AuraDisc", Vector3.new(0.08, radius * 2, radius * 2), base * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90)), tone, fade(0.75, dim), Enum.PartType.Cylinder)
		end
		-- Halka: kısa parçalardan daire (içi boş)
		local ring: { Part } = {}
		if order >= 2 then
			local segments = 24
			local r = radius * 1.12
			for k = 0, segments - 1 do
				local a0 = k / segments * math.pi * 2
				local a1 = (k + 1) / segments * math.pi * 2
				local p0 = base.Position + Vector3.new(math.cos(a0) * r, 0.32, math.sin(a0) * r)
				local p1 = base.Position + Vector3.new(math.cos(a1) * r, 0.32, math.sin(a1) * r)
				table.insert(ring, part(folder, "AuraRing", Vector3.new(0.22, 0.12, (p1 - p0).Magnitude + 0.05),
					CFrame.lookAt((p0 + p1) / 2, p1), tone, 0.3))
			end
		end

		-- Işıltılar
		local emitterHost = part(folder, "AuraEmitter", Vector3.new(radius * 1.6, 0.1, radius * 1.6), base * CFrame.new(0, 0.2, 0), tone, 1)
		--[[ 2026-09-28: "her şey aynı derecede parlak" — efektler seyreltildi:
		     Common/Uncommon yalnızca disk ve halka; ışıltı Rare'den, küreler
		     Epic'ten, ışık sütunu Mythic'ten. Nadir olan gerçekten öne çıksın. ]]
		if order >= 3 then
			local e = sparkles(emitterHost, tone, (1 + order) * (1 - 0.5 * dim), 0.35 + order * 0.05, 12)
			e.LightEmission = 1 - 0.7 * dim
		end
		if mutation then
			local mc = mutation.tint or Color3.fromRGB(255, 255, 200)
			sparkles(emitterHost, mc, 4, 0.5, 30)
			if mutation.id == Config.LimitedEvent.mutation then
				local sky = part(folder, "EventRain", Vector3.new(radius * 1.6, 0.1, radius * 1.6),
					base * CFrame.new(0, size.Y + 3, 0), mc, 1)
				local rain = sparkles(sky, Config.LimitedEvent.color, 7, 0.55, 10)
				rain.Name = "EventRain"
				rain.EmissionDirection = Enum.NormalId.Bottom
				rain.Acceleration = Vector3.new(0, -4, 0)
				rain.Speed = NumberRange.new(2, 4)
				rain.Lifetime = NumberRange.new(0.9, 1.4)
			end
		end

		-- Dönen küreler ve ışık
		local orbs: { Part } = {}
		if order >= 4 then
			local count = if order >= 6 then 4 else 2
			for _ = 1, count do
				local orb = part(folder, "AuraOrb", Vector3.one * (0.45 + order * 0.04), base, tone, fade(0, dim), Enum.PartType.Ball)
				local trail = Instance.new("Trail")
				local a0 = Instance.new("Attachment")
				a0.Position = Vector3.new(0, 0.18, 0)
				a0.Parent = orb
				local a1 = Instance.new("Attachment")
				a1.Position = Vector3.new(0, -0.18, 0)
				a1.Parent = orb
				trail.Attachment0 = a0
				trail.Attachment1 = a1
				trail.Color = ColorSequence.new(tone)
				trail.LightEmission = 1 - 0.7 * dim
				trail.Lifetime = 0.35
				trail.Transparency = NumberSequence.new(0.3, 1)
				trail.FaceCamera = true
				trail.Parent = orb
				table.insert(orbs, orb)
			end
			local light = Instance.new("PointLight")
			light.Color = tone
			light.Range = 8 + order * 2
			light.Brightness = 1.2 * (1 - 0.75 * dim)
			light.Parent = emitterHost
		end

		-- Işık sütunu ve yıldız patlaması
		local burst: ParticleEmitter? = nil
		if order >= 6 then
			local height = 26 + (order - 5) * 10
			part(folder, "AuraBeam", Vector3.new(height, radius * 0.9, radius * 0.9), base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), tone, fade(0.86, dim), Enum.PartType.Cylinder)
			local e = sparkles(emitterHost, tone, 0, 0.9, 180)
			e.LightEmission = 1 - 0.7 * dim
			e.Speed = NumberRange.new(6, 10)
			e.Lifetime = NumberRange.new(0.6, 1)
			e.Drag = 3
			burst = e
		end

		auras[model] = {
			model = model,
			folder = folder,
			base = base,
			orbs = orbs,
			ring = ring,
			spin = math.random() * 10,
			burst = burst,
			nextBurst = os.clock() + math.random() * 3,
			dim = dim,
		}
	end

	local function watch(folder: Instance)
		for _, child in folder:GetChildren() do
			if child:IsA("Model") then
				task.defer(build, child)
			end
		end
		table.insert(conns, folder.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				-- Nitelikler modelle aynı pakette geliyor ama parçalar bir kare sonra olabilir
				task.delay(0.1, build, child)
			end
		end))
		table.insert(conns, folder.ChildRemoved:Connect(function(child)
			if child:IsA("Model") then
				auras[child] = nil
			end
		end))
	end

	task.spawn(function()
		local zone = workspace:WaitForChild("SpaceZone", 60)
		local crew = zone and zone:WaitForChild("Crew", 60)
		if crew then
			watch(crew)
		end
	end)

	local clock = 0
	table.insert(conns, RunService.RenderStepped:Connect(function(dt)
		clock += dt
		local camera = workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		local now = os.clock()
		for model, aura in auras do
			if not model.Parent then
				auras[model] = nil
				continue
			end
			if (aura.base.Position - camPos).Magnitude > 220 then
				continue
			end
			local t = clock + aura.spin
			for i, orb in aura.orbs do
				local a = t * 1.6 + (i - 1) / #aura.orbs * math.pi * 2
				local r = 2.4
				orb.CFrame = aura.base * CFrame.new(math.cos(a) * r, 2 + math.sin(t * 2 + i) * 0.8, math.sin(a) * r)
			end
			if #aura.ring > 0 then
				local tr = fade(0.2 + 0.3 * (0.5 + 0.5 * math.sin(t * 3)), aura.dim)
				for _, seg in aura.ring do
					seg.Transparency = tr
				end
			end
			if aura.burst and now >= aura.nextBurst then
				aura.nextBurst = now + 2.5 + math.random() * 2
				aura.burst:Emit(14)
			end
		end
	end))

	return {
		Destroy = function()
			for _, c in conns do
				c:Disconnect()
			end
			for _, aura in auras do
				aura.folder:Destroy()
			end
			table.clear(auras)
		end,
	}
end

return CrewAura
