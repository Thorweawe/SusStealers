--!strict
--[[
	Jetpack modeli (Config.Jetpacks). Launch Bay standındaki vitrin (sunucu,
	JetpackService) ve uzaydaki oyuncuların sırtı (istemci, SpaceFX) aynı
	modeli kullanıyor.

	Yerleşim: `origin` sırtın ortası, ileri -Z (karakterin baktığı yön);
	paket +Z tarafında (arkada). Parçalar çarpışmasız ve kütlesiz.

	  Sırt plakası + kemer tokası, bir ya da iki tank (kubbeli), tankta
	  parlak şerit, altta memeler. İleri modellerde kanatçıklar ve arkada
	  neon halka. Memelerin ucunda "Flame1"/"Flame2" Attachment'ları:
	  alevi istemci ekliyor (FlameFX), vitrinde sönük parıltı.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local JetpackModel = {}

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = model
	return p
end

-- Dik silindir (ekseni modelin Y'si)
local function vcyl(model: Model, name: string, height: number, diameter: number, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = part(model, name, Vector3.new(height, diameter, diameter), cf * CFrame.Angles(0, 0, math.rad(90)), color, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(model: Model, name: string, d: number, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = part(model, name, Vector3.one * d, cf, color, props)
	p.Shape = Enum.PartType.Ball
	return p
end

--[[
	Jetpack'i kurar. `origin` sırtın ortası (UpperTorso'nun arka yüzü
	civarı), `scale` karakter boyuna göre (R15 ~1).
]]
function JetpackModel.Build(def: Config.JetpackDef, origin: CFrame, scale: number?): Model
	local S = scale or 1
	local model = Instance.new("Model")
	model.Name = "Jetpack_" .. def.id
	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x * S, y * S, z * S)
	end

	-- Sırt plakası ve kemer tokası
	local plate = part(model, "Pack", Vector3.new(1.7, 2.1, 0.45) * S, at(0, 0.05, 0.35), def.trim)
	part(model, "PlateEdge", Vector3.new(1.84, 2.24, 0.3) * S, at(0, 0.05, 0.28), def.trim:Lerp(Color3.new(0, 0, 0), 0.35))
	part(model, "Buckle", Vector3.new(0.5, 0.36, 0.2) * S, at(0, -0.72, 0.62), Color3.fromRGB(255, 214, 80), { Material = Enum.Material.Metal })
	-- Omuz askıları (gövdenin önüne dolanmadan, üstten)
	for _, x in { -0.55, 0.55 } do
		part(model, "Strap", Vector3.new(0.28, 0.14, 1.1) * S, at(x, 1.02, -0.05), def.trim:Lerp(Color3.new(0, 0, 0), 0.5))
	end

	-- Tanklar
	-- Üç tank: geç oyun jetpackleri (Supernova, Cosmic)
	local xs = if def.tanks >= 3 then { -0.66, 0, 0.66 } elseif def.tanks >= 2 then { -0.5, 0.5 } else { 0 }
	local tankD = if def.tanks >= 3 then 0.62 elseif def.tanks >= 2 then 0.78 else 1.1
	local nozzles = {}
	for i, x in xs do
		local cz = 0.95
		vcyl(model, "Tank", 1.9, tankD, at(x, 0.15, cz) , def.tank, { Material = Enum.Material.SmoothPlastic })
		ball(model, "TankCap", tankD, at(x, 1.1, cz), def.tank)
		ball(model, "TankShine", tankD * 0.28, at(x - tankD * 0.18, 0.8, cz + tankD * 0.4), Color3.new(1, 1, 1),
			{ Material = Enum.Material.Neon, Transparency = 0.35 })
		-- Parlak şerit
		vcyl(model, "TankStripe", 0.22, tankD + 0.06, at(x, 0.45, cz), def.flame, { Material = Enum.Material.Neon })
		vcyl(model, "TankBand", 0.14, tankD + 0.05, at(x, -0.45, cz), def.trim)
		-- Meme: koyu gövde + içte parlak halka
		vcyl(model, "Nozzle", 0.45, tankD * 0.82, at(x, -1.02, cz), Color3.fromRGB(58, 62, 74), { Material = Enum.Material.Metal })
		vcyl(model, "NozzleBell", 0.25, tankD * 0.95, at(x, -1.32, cz), Color3.fromRGB(44, 46, 56), { Material = Enum.Material.Metal })
		vcyl(model, "NozzleGlow", 0.08, tankD * 0.62, at(x, -1.46, cz), def.flame, { Material = Enum.Material.Neon })
		local host = part(model, "FlameHost" .. i, Vector3.one * 0.2 * S, at(x, -1.5, cz), def.flame, { Transparency = 1 })
		local a = Instance.new("Attachment")
		a.Name = "Flame" .. i
		a.Parent = host
		table.insert(nozzles, host)
	end

	-- Kanatçıklar: yanlara ve biraz aşağı açılan kısa kanat
	if def.wings then
		for _, side in { -1, 1 } do
			local w = Instance.new("WedgePart")
			w.Name = "Wing"
			w.Size = Vector3.new(0.14, 0.9, 1.25) * S
			w.CFrame = at(side * 1.05, -0.35, 0.9) * CFrame.Angles(0, 0, math.rad(side * -18)) * CFrame.Angles(math.rad(180), 0, 0)
			w.Color = def.trim
			w.Material = Enum.Material.SmoothPlastic
			w.Anchored = true
			w.CanCollide = false
			w.CanQuery = false
			w.CanTouch = false
			w.Massless = true
			w.CastShadow = false
			w.Parent = model
			part(model, "WingTip", Vector3.new(0.18, 0.16, 0.5) * S, at(side * 1.27, -0.78, 1.25), def.flame, { Material = Enum.Material.Neon })
		end
	end

	-- Arkada neon halka (en iyi modeller)
	if def.ring then
		local segments = 14
		local r = 1.05
		for k = 0, segments - 1 do
			local a0 = k / segments * math.pi * 2
			local a1 = (k + 1) / segments * math.pi * 2
			local p0 = at(math.cos(a0) * r, 0.2 + math.sin(a0) * r, 1.45).Position
			local p1 = at(math.cos(a1) * r, 0.2 + math.sin(a1) * r, 1.45).Position
			local mid = (p0 + p1) / 2
			part(model, "Halo", Vector3.new((p1 - p0).Magnitude + 0.04, 0.12 * S, 0.12 * S),
				CFrame.lookAt(mid, p1) * CFrame.Angles(0, math.rad(90), 0), def.flame, { Material = Enum.Material.Neon })
		end
	end

	-- Yıldız çekirdeği (geç oyun): halkanın ortasında parlayan küre ve ışık
	if def.star then
		local core = ball(model, "StarCore", 0.7, at(0, 0.2, 1.45), def.flame, { Material = Enum.Material.Neon })
		ball(model, "StarShell", 1.0, at(0, 0.2, 1.45), def.flame2, { Material = Enum.Material.Neon, Transparency = 0.6 })
		local light = Instance.new("PointLight")
		light.Color = def.flame
		light.Range = 10
		light.Brightness = 1.5
		light.Parent = core
	end

	--[[
		3D ağ (2026-10-02): ReplicatedStorage.JetpackMeshes.<id> varsa (ChatGPT
		konsepti → TRELLIS → tools/normalize_meshes.lua, ortası x/z = 0, alt =
		meme ağzı) parçalar GİZLENİP ağ takılıyor. Parçalar silinmiyor: alev
		noktaları (FlameHost), Pack (StyleFX efektleri) ve ışıklar yerinde kalsın.
		Ağ sırttan MESH_Z kadar geride (parça sürümünün tank hizası).
	]]
	local meshes = ReplicatedStorage:FindFirstChild("JetpackMeshes")
	local template = meshes and meshes:FindFirstChild(def.id)
	if template and template:IsA("Model") then
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") then
				p.Transparency = 1
			end
		end
		local MESH_Z = 0.8
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
			p.Name = "Mesh" .. src.Name
			p.Size = src.Size * S
			p.CFrame = at(src.Position.X, src.Position.Y, src.Position.Z + MESH_Z) * src.CFrame.Rotation
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.CastShadow = false
			p.Parent = model
		end
	end

	model.PrimaryPart = plate
	return model
end

--[[
	Memelere alev ekler (istemci ve vitrin). `strength` 0..1: 0 sönük
	parıltı, 1 tam itki. Dönen fonksiyon gücü değiştirir.

	`flame` (Config.JetFlames) verilirse alev o kozmetiğin görünüşünde:
	renkler, beyaz/koyu çekirdek, duman rengi, ışıltı, kıvılcım, boy ve
	memelerden uzanan iz (Trail). Gökkuşağı alevi her güncellemede rengini
	kaydırıyor. Verilmezse jetpack'in kendi alev renkleri (Classic).
]]
local EMBER = "rbxasset://textures/particles/fire_sparks_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

function JetpackModel.AddFlames(model: Model, def: Config.JetpackDef, flame: Config.JetFlameDef?): (number) -> ()
	local c1 = if flame then flame.flame else def.flame
	local c2 = if flame then flame.flame2 else def.flame2
	local coreColor = (flame and flame.core) or Color3.new(1, 1, 1)
	local smokeColor = (flame and flame.smoke) or Color3.fromRGB(200, 205, 220)
	local size = (flame and flame.size) or 1
	local rainbow = flame ~= nil and flame.rainbow == true

	type Set = { flame: ParticleEmitter, core: ParticleEmitter, smoke: ParticleEmitter, extra: { ParticleEmitter }, trail: Trail? }
	local emitters: { Set } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Attachment") and d.Name:match("^Flame%d") then
			local fire = Instance.new("ParticleEmitter")
			fire.Name = "Flame"
			fire.Texture = "rbxasset://textures/particles/fire_main.dds"
			fire.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, c1),
				ColorSequenceKeypoint.new(0.5, c2),
				ColorSequenceKeypoint.new(1, c2:Lerp(Color3.new(0, 0, 0), 0.5)),
			})
			fire.LightEmission = 1
			fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55 * size), NumberSequenceKeypoint.new(1, 0.05) })
			fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
			fire.Lifetime = NumberRange.new(0.18 * size, 0.3 * size)
			fire.Speed = NumberRange.new(9, 13)
			fire.EmissionDirection = Enum.NormalId.Bottom
			fire.SpreadAngle = Vector2.new(6, 6)
			fire.Rate = 0
			fire.Parent = d
			local core = Instance.new("ParticleEmitter")
			core.Name = "Core"
			core.Texture = SPARKLE
			core.Color = ColorSequence.new(coreColor, c1)
			core.LightEmission = if coreColor.R + coreColor.G + coreColor.B < 0.5 then 0 else 1
			core.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35 * size), NumberSequenceKeypoint.new(1, 0) })
			core.Transparency = NumberSequence.new(0, 1)
			core.Lifetime = NumberRange.new(0.1, 0.16)
			core.Speed = NumberRange.new(7, 9)
			core.EmissionDirection = Enum.NormalId.Bottom
			core.Rate = 0
			core.Parent = d
			local smoke = Instance.new("ParticleEmitter")
			smoke.Name = "Smoke"
			smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
			smoke.Color = ColorSequence.new(smokeColor)
			smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1.4 * size) })
			smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(1, 1) })
			smoke.Lifetime = NumberRange.new(0.5, 0.9)
			smoke.Speed = NumberRange.new(2, 4)
			smoke.EmissionDirection = Enum.NormalId.Bottom
			smoke.Rate = 0
			smoke.Parent = d

			local extra: { ParticleEmitter } = {}
			-- Işıltı: aleve karışan küçük yıldızlar
			if flame and flame.sparkle then
				local e = Instance.new("ParticleEmitter")
				e.Name = "Sparkle"
				e.Texture = SPARKLE
				e.Color = ColorSequence.new(flame.sparkle)
				e.LightEmission = 1
				e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.3), NumberSequenceKeypoint.new(1, 0) })
				e.Lifetime = NumberRange.new(0.5, 0.9)
				e.Speed = NumberRange.new(3, 6)
				e.SpreadAngle = Vector2.new(30, 30)
				e.EmissionDirection = Enum.NormalId.Bottom
				e.RotSpeed = NumberRange.new(-200, 200)
				e.Drag = 2
				e.Rate = 0
				e.Parent = d
				table.insert(extra, e)
			end
			-- Kıvılcım: yerçekimiyle düşen sıcak parçalar
			if flame and flame.embers then
				local e = Instance.new("ParticleEmitter")
				e.Name = "Embers"
				e.Texture = EMBER
				e.Color = ColorSequence.new(c1, c2)
				e.LightEmission = 1
				e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
				e.Lifetime = NumberRange.new(0.6, 1.1)
				e.Speed = NumberRange.new(4, 9)
				e.SpreadAngle = Vector2.new(35, 35)
				e.Acceleration = Vector3.new(0, -12, 0)
				e.EmissionDirection = Enum.NormalId.Bottom
				e.Rate = 0
				e.Parent = d
				table.insert(extra, e)
			end
			-- İz: memeden geriye uzanan ışık şeridi (uçarken görünür)
			local trail: Trail? = nil
			if flame and flame.trail then
				local host = d.Parent
				if host and host:IsA("BasePart") then
					local a0 = Instance.new("Attachment")
					a0.Name = "TrailA"
					a0.Position = d.Position + Vector3.new(0.18, 0, 0)
					a0.Parent = host
					local a1 = Instance.new("Attachment")
					a1.Name = "TrailB"
					a1.Position = d.Position - Vector3.new(0.18, 0, 0)
					a1.Parent = host
					local t = Instance.new("Trail")
					t.Attachment0 = a0
					t.Attachment1 = a1
					t.Color = ColorSequence.new(flame.trail, flame.trail2 or flame.trail)
					t.LightEmission = 1
					t.FaceCamera = true
					t.Lifetime = 0.45
					t.MinLength = 0.1
					t.WidthScale = NumberSequence.new(1, 0.1)
					t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
					t.Enabled = false
					t.Parent = host
					trail = t
				end
			end
			table.insert(emitters, { flame = fire, core = core, smoke = smoke, extra = extra, trail = trail })
		end
	end
	local started = os.clock()
	local lastColorAt = 0
	local function set(strength: number)
		local k = math.clamp(strength, 0, 1)
		local now = os.clock()
		local recolor = rainbow and now - lastColorAt > 0.1
		if recolor then
			lastColorAt = now
		end
		for i, e in emitters do
			e.flame.Rate = (18 + 62 * k) * size
			e.core.Rate = 10 + 40 * k
			e.smoke.Rate = 4 + 10 * k
			e.flame.Speed = NumberRange.new(6 + 8 * k, 9 + 10 * k)
			for _, x in e.extra do
				x.Rate = if x.Name == "Embers" then 3 + 22 * k else 2 + 16 * k
			end
			if e.trail then
				e.trail.Enabled = k > 0.35
			end
			if recolor then
				local a = Config.RainbowColor(now - started, i * 0.08)
				local b = Config.RainbowColor(now - started, 0.33 + i * 0.08)
				e.flame.Color = ColorSequence.new(a, b)
				e.core.Color = ColorSequence.new(Color3.new(1, 1, 1), a)
				if e.trail then
					e.trail.Color = ColorSequence.new(a, b)
				end
			end
		end
	end
	set(0.3)
	return set
end

return JetpackModel
