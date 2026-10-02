--!strict
--[[
	Mutasyon animasyonları (2026-10-02, Yusuf: "mutasyonlar, trait'ler için
	de efektler animasyonlar olsun, her mutasyon için") — tamamen istemcide.

	Yayıcılar modelin içinde (UnitModel MUT_FX); burası CANLI kısım:
	  Impostor  — kızıl ışık bozuk lamba gibi titriyor, ara ara kıvılcım patlaması
	  Golden    — etrafında dönen üç altın küre, ışık parıldıyor
	  Ejected   — yavaş dönen iki yıldız, uzay boşluğu nefesi
	  Vented    — birkaç saniyede bir havalandırmadan duman püskürmesi
	  Sus       — başında "!" fırlıyor, pembe ışık nabzı
	  Starborn  — izli kayan yıldız yörüngede
	  Haunted   — izli hayalet yörüngede, yeşil ışık titriyor
	  pet Crystal / Cosmic — camgöbeği kırık / mor küre yörüngede
	  pet boyu (trait) Titan+ — ayak altında genişleyip sönen halka

	Mürettebat modeli "MutationId" (UnitModel), pet "MutationId" + "PetSize"
	(PetModel) değeri taşıyor. Kameradan uzaktakiler güncellenmiyor.
]]

local RunService = game:GetService("RunService")

local MutationFX = {}

local FAR = 160

type Orbiter = { part: BasePart, radius: number, height: number, speed: number, phase: number, bob: number }
type Tracked = {
	model: Model,
	orbit: { Orbiter },
	light: PointLight?,
	baseBright: number,
	flicker: string?, -- "glitch" | "pulse" | "shimmer" | "ghost"
	bursts: { { emitter: ParticleEmitter, every: number, count: number, next: number } },
	ring: BasePart?,
	ringEvery: number,
	ringSize: number,
	radius: number,
	halfY: number,
	parts: { BasePart },
}

local tracked: { [Model]: Tracked } = {}
local folder: Folder? = nil

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Instance.new("Folder")
	f.Name = "MutationFXClient"
	f.Parent = workspace
	folder = f
	return f
end

local function ball(size: number, color: Color3, transparency: number?): Part
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = getFolder()
	return p
end

local function addTrail(p: BasePart, c1: Color3, c2: Color3, life: number)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, p.Size.Y * 0.4, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -p.Size.Y * 0.4, 0)
	a1.Parent = p
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Color = ColorSequence.new(c1, c2)
	t.Transparency = NumberSequence.new(0.2, 1)
	t.Lifetime = life
	t.LightEmission = 1
	t.FaceCamera = true
	t.Parent = p
end

local function findEmitter(model: Model, name: string): ParticleEmitter?
	local e = model:FindFirstChild(name, true)
	return if e and e:IsA("ParticleEmitter") then e else nil
end

local function track(model: Model, mutation: string, size: string)
	if tracked[model] then
		return
	end
	local _, ext = model:GetBoundingBox()
	local r = math.max(ext.X, ext.Z) / 2 + 0.6
	local t: Tracked = {
		model = model,
		orbit = {},
		light = nil,
		baseBright = 1,
		flicker = nil,
		bursts = {},
		ring = nil,
		ringEvery = 0,
		ringSize = 0,
		radius = r,
		halfY = ext.Y / 2,
		parts = {},
	}
	local s = math.clamp(ext.Y / 4, 0.6, 4) -- küçük pet ile dev crewmate aynı oranda
	local function orbiter(p: BasePart, radius: number, height: number, speed: number, phase: number, bob: number)
		table.insert(t.orbit, { part = p, radius = radius, height = height, speed = speed, phase = phase, bob = bob })
		table.insert(t.parts, p)
	end
	local function light(color: Color3, bright: number, flicker: string)
		local host = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if not host then
			return
		end
		local l = Instance.new("PointLight")
		l.Name = "MutationFXLight"
		l.Color = color
		l.Brightness = bright
		l.Range = 8 * s
		l.Parent = host
		t.light = l
		t.baseBright = bright
		t.flicker = flicker
	end
	local function burst(name: string, every: number, count: number)
		local e = findEmitter(model, name)
		if e then
			table.insert(t.bursts, { emitter = e, every = every, count = count, next = os.clock() + math.random() * every })
		end
	end

	if mutation == "Impostor" then
		light(Color3.fromRGB(255, 40, 40), 1.6, "glitch")
		burst("MutGlitch", 2.5, 14)
	elseif mutation == "Golden" then
		light(Color3.fromRGB(255, 210, 90), 1.2, "shimmer")
		for i = 1, 3 do
			orbiter(ball(0.35 * s, Color3.fromRGB(255, 205, 70)), r, ext.Y * 0.55, 1.4, i * 2.094, 0.25 * s)
		end
	elseif mutation == "Ejected" then
		for i = 1, 2 do
			local p = ball(0.25 * s, Color3.fromRGB(200, 210, 255))
			addTrail(p, Color3.fromRGB(200, 210, 255), Color3.fromRGB(60, 60, 160), 0.5)
			orbiter(p, r * 1.1, ext.Y * (0.3 + i * 0.25), 0.6, i * 3.14, 0.4 * s)
		end
	elseif mutation == "Vented" then
		burst("MutVentDust", 3.5, 16)
		burst("MutSteam", 3.5, 6)
	elseif mutation == "Sus" then
		light(Color3.fromRGB(255, 120, 190), 1, "pulse")
		burst("MutSus", 4, 1)
	elseif mutation == "Starborn" then
		local p = ball(0.3 * s, Color3.fromRGB(230, 245, 255))
		addTrail(p, Color3.fromRGB(230, 245, 255), Color3.fromRGB(120, 190, 255), 0.6)
		orbiter(p, r * 1.15, ext.Y * 0.7, 2.2, 0, 0.6 * s)
		light(Color3.fromRGB(150, 215, 255), 1, "shimmer")
	elseif mutation == "Haunted" then
		local p = ball(0.7 * s, Color3.fromRGB(200, 255, 225), 0.45)
		addTrail(p, Color3.fromRGB(200, 255, 225), Color3.fromRGB(90, 200, 150), 0.8)
		orbiter(p, r * 1.2, ext.Y * 0.6, 0.9, 0, 0.8 * s)
		light(Color3.fromRGB(150, 255, 200), 1.2, "ghost")
	elseif mutation == "Crystal" then
		for i = 1, 3 do
			local p = Instance.new("Part")
			p.Size = Vector3.new(0.18, 0.5, 0.18) * s
			p.Color = Color3.fromRGB(150, 235, 255)
			p.Material = Enum.Material.Glass
			p.Transparency = 0.2
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Parent = getFolder()
			orbiter(p, r, ext.Y * 0.5, 1, i * 2.094, 0.2 * s)
		end
	elseif mutation == "Cosmic" then
		local p = ball(0.35 * s, Color3.fromRGB(170, 110, 255))
		addTrail(p, Color3.fromRGB(200, 150, 255), Color3.fromRGB(90, 40, 200), 0.6)
		orbiter(p, r * 1.1, ext.Y * 0.6, 1.8, 0, 0.3 * s)
	end

	-- Boy trait'i: büyük petin ayak altında yayılan halka
	if size == "Titan" or size == "Colossal" or size == "Galactic" then
		local ring = Instance.new("Part")
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Color = if size == "Galactic" then Color3.fromRGB(150, 110, 255)
			elseif size == "Colossal" then Color3.fromRGB(255, 120, 80)
			else Color3.fromRGB(255, 210, 90)
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Parent = getFolder()
		t.ring = ring
		t.ringEvery = if size == "Galactic" then 1.4 elseif size == "Colossal" then 1.8 else 2.2
		t.ringSize = r * 2.4
		table.insert(t.parts, ring)
	end

	if #t.orbit == 0 and not t.light and #t.bursts == 0 and not t.ring then
		return
	end
	tracked[model] = t
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			for _, p in t.parts do
				p:Destroy()
			end
			if t.light then
				t.light:Destroy()
			end
			tracked[model] = nil
		end
	end)
end

local function consider(v: Instance)
	if not (v:IsA("StringValue") and (v.Name == "MutationId" or v.Name == "PetSize")) then
		return
	end
	task.defer(function()
		local model = v.Parent
		if not (model and model:IsA("Model") and model:IsDescendantOf(workspace)) then
			return
		end
		local m = model:FindFirstChild("MutationId")
		local z = model:FindFirstChild("PetSize")
		local mutation = if m and m:IsA("StringValue") then m.Value else ""
		local size = if z and z:IsA("StringValue") then z.Value else ""
		if mutation ~= "" or size ~= "" then
			track(model, mutation, size)
		end
	end)
end

function MutationFX.Start()
	for _, d in workspace:GetDescendants() do
		consider(d)
	end
	workspace.DescendantAdded:Connect(consider)

	local camera = workspace.CurrentCamera
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local camPos = (workspace.CurrentCamera or camera).CFrame.Position
		for model, t in tracked do
			local pivot = model:GetPivot()
			local base = pivot.Position - Vector3.new(0, t.halfY, 0)
			local near = (pivot.Position - camPos).Magnitude < FAR
			for _, p in t.parts do
				p.LocalTransparencyModifier = if near then 0 else 1
			end
			if not near then
				continue
			end
			for _, o in t.orbit do
				local a = o.phase + now * o.speed
				local pos = base + Vector3.new(math.cos(a) * o.radius, o.height + math.sin(now * 2 + o.phase) * o.bob, math.sin(a) * o.radius)
				o.part.CFrame = CFrame.new(pos) * CFrame.Angles(0, -a, now)
			end
			local l = t.light
			if l then
				if t.flicker == "glitch" then
					-- bozuk lamba: çoğu an yanık, ara ara kesik
					l.Brightness = if math.noise(now * 6, t.radius) > 0.35 then 0 else t.baseBright
				elseif t.flicker == "pulse" then
					l.Brightness = t.baseBright * (0.6 + 0.4 * math.sin(now * 4))
				elseif t.flicker == "ghost" then
					l.Brightness = t.baseBright * (0.5 + 0.5 * math.abs(math.noise(now * 1.5, t.radius)) * 2)
				else
					l.Brightness = t.baseBright * (0.85 + 0.15 * math.sin(now * 2.5))
				end
			end
			for _, b in t.bursts do
				if now >= b.next then
					b.next = now + b.every * (0.7 + math.random() * 0.6)
					b.emitter:Emit(b.count)
				end
			end
			local ring = t.ring
			if ring then
				local k = (now % t.ringEvery) / t.ringEvery
				local d = t.ringSize * (0.4 + 0.6 * k)
				ring.Size = Vector3.new(0.08, d, d)
				ring.CFrame = CFrame.new(base + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
				ring.Transparency = 0.3 + 0.7 * k
			end
		end
	end)
end

return MutationFX
