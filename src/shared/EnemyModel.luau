--!strict
--[[
	Gezegen savunmasının düşmanları (DefenseConfig.Enemies), istemcide
	kuruluyor (DefenseFX). Kök "Root" ayak hizasında, yüzü -Z.

	2026-10-01 (Batur: "tek canavar gelmesin, gezegenin lore'una uygun
	farklı türde canavarlar, büyük olsunlar"). Gloopus bir balçık gezegeni
	(canavarı Glorp, yeşil jöle); yaratıklar da onun ekosisteminden:

	  Grub    — Goo Slug: sümüklü balçık sümüklüböceği, göz sapları
	  Skitter — Gloop Mite: kabuklu küçük balçık böceği, altı bacak
	  Spitter — Spore Spitter: şişkin spor kesesi, öne uzanan hortum
	  Brute   — Ooze Golem: içine taş gömülü dev balçık, iri kollar
	  Boss    — (DefenseFX gezegenin canavarını kullanıyor: Glorp)

	Gövdeler blok + SpecialMesh(Sphere) elipsler: "Body" parçasının
	SpecialMesh'i istemcide sıkışıp esneyerek (jöle) oynatılıyor.
	Renkler gezegenin paleti.
]]

local EnemyModel = {}

local BLACK = Color3.fromRGB(20, 18, 26)
local WHITE = Color3.fromRGB(245, 245, 250)

type Props = { [string]: any }

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): Part
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
	p.Material = Enum.Material.SmoothPlastic
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = model
	return p
end

-- Gerçek elips (Ball şekli hep küre çiziyor)
local function blob(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, props: Props?): Part
	local p = part(model, name, size, cf, color, props)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function slime(color: Color3): Props
	-- Islak, parlak balçık
	return { Material = Enum.Material.SmoothPlastic, Reflectance = 0.12, Color = color }
end

local function eye(model: Model, at: CFrame, size: number)
	blob(model, "Eye", Vector3.one * size, at, WHITE)
	blob(model, "Pupil", Vector3.one * size * 0.5, at * CFrame.new(0, 0, -size * 0.34), BLACK)
	blob(model, "Shine", Vector3.one * size * 0.18, at * CFrame.new(size * 0.14, size * 0.16, -size * 0.45), WHITE,
		{ Material = Enum.Material.Neon })
end

--[[
	3D ağ (2026-10-02, Yusuf): ReplicatedStorage.DefenseMeshes.<kind> varsa
	(ChatGPT konsepti → TRELLIS → tools/normalize_meshes.lua; taban y=0,
	yüzü -Z, boy aşağıdaki parça modelle aynı) parça gövde yerine o ağ.
	En büyük MeshPart "Body" adını alıyor: DefenseFX onu SpecialMesh yerine
	Size ile esnetiyor, parlamayı Highlight ile yapıyor.
]]
local function meshEnemy(model: Model, kind: string): boolean
	local meshes = game:GetService("ReplicatedStorage"):FindFirstChild("DefenseMeshes")
	local template = meshes and meshes:FindFirstChild(kind)
	if not (template and template:IsA("Model")) then
		return false
	end
	local best: MeshPart? = nil
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
		p.Name = "Mesh"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = model
		if not best or p.Size.Magnitude > best.Size.Magnitude then
			best = p
		end
	end
	if not best then
		return false
	end
	best.Name = "Body"
	return true
end

--[[ kind: DefenseConfig.Enemies kimliği. body/dark/glow: gezegenin paleti. ]]
function EnemyModel.Build(kind: string, body: Color3, dark: Color3, glow: Color3): Model
	local model = Instance.new("Model")
	model.Name = "Enemy_" .. kind
	local root = part(model, "Root", Vector3.new(1, 1, 1), CFrame.new(), body, { Transparency = 1 })
	model.PrimaryPart = root
	if meshEnemy(model, kind) then
		return model
	end
	local o = CFrame.new()
	local light = body:Lerp(WHITE, 0.3)

	if kind == "Skitter" then
		-- Gloop Mite: kabuk + altı bacak + iki anten
		blob(model, "Body", Vector3.new(3.4, 1.8, 3.8), o * CFrame.new(0, 1.5, 0), body, slime(body))
		blob(model, "Shell", Vector3.new(3.6, 1.4, 3.2), o * CFrame.new(0, 2.1, 0.4), dark, { Reflectance = 0.25 })
		blob(model, "ShellSpot", Vector3.new(1, 0.4, 1), o * CFrame.new(0.6, 2.75, 0.6), glow, { Material = Enum.Material.Neon })
		eye(model, o * CFrame.new(-0.55, 1.9, -1.7), 0.75)
		eye(model, o * CFrame.new(0.55, 1.9, -1.7), 0.75)
		for _, s in { -1, 1 } do
			part(model, "Antenna", Vector3.new(0.12, 1.4, 0.12), o * CFrame.new(s * 0.5, 2.8, -1.6) * CFrame.Angles(math.rad(-25), 0, math.rad(s * 20)), dark)
			blob(model, "AntennaTip", Vector3.one * 0.35, o * CFrame.new(s * 0.75, 3.45, -1.9), glow, { Material = Enum.Material.Neon })
			for _, z in { -1, 0, 1 } do
				part(model, "Leg", Vector3.new(0.22, 1.7, 0.22), o * CFrame.new(s * 1.8, 0.75, z * 1.1) * CFrame.Angles(0, 0, math.rad(s * 40)), dark)
			end
		end
	elseif kind == "Spitter" then
		-- Spore Spitter: şişkin kese, parlayan spor damarları, hortum
		blob(model, "Body", Vector3.new(3.6, 4.6, 3.6), o * CFrame.new(0, 2.6, 0), body, slime(body))
		blob(model, "Sac", Vector3.new(2.2, 2.4, 2), o * CFrame.new(0, 3.6, 1.2), glow, { Material = Enum.Material.Neon, Transparency = 0.25 })
		for k = 0, 4 do
			local a = k / 5 * math.pi * 2
			blob(model, "Spore", Vector3.one * 0.55, o * CFrame.new(math.cos(a) * 1.6, 4.2 + (k % 2) * 0.5, math.sin(a) * 1.6), glow,
				{ Material = Enum.Material.Neon })
		end
		eye(model, o * CFrame.new(-0.6, 3.9, -1.55), 0.8)
		eye(model, o * CFrame.new(0.6, 3.9, -1.55), 0.8)
		part(model, "Snout", Vector3.new(0.9, 0.9, 2.2), o * CFrame.new(0, 2.8, -2.2), dark)
		blob(model, "SnoutTip", Vector3.new(1.3, 1.3, 0.6), o * CFrame.new(0, 2.8, -3.3), glow, { Material = Enum.Material.Neon })
		for _, s in { -1, 1 } do
			blob(model, "Foot", Vector3.new(1.4, 0.8, 1.8), o * CFrame.new(s * 0.9, 0.4, 0), dark)
		end
	elseif kind == "Brute" then
		-- Ooze Golem: dev balçık, içine gömülü taşlar, iri kollar
		blob(model, "Body", Vector3.new(6.4, 6.8, 5.6), o * CFrame.new(0, 3.8, 0), body, slime(body))
		blob(model, "Belly", Vector3.new(4.2, 4, 2.6), o * CFrame.new(0, 3.2, -1.7), light, slime(light))
		for k, v in { Vector3.new(-1.8, 5.6, 1.4), Vector3.new(1.6, 6.4, 0.6), Vector3.new(0.4, 2.2, 2.2) } do
			part(model, "Rock", Vector3.new(1.6, 1.3, 1.5), o * CFrame.new(v) * CFrame.Angles(k, k * 0.7, 0), Color3.fromRGB(90, 84, 78),
				{ Material = Enum.Material.Slate })
		end
		blob(model, "Brow", Vector3.new(4, 0.9, 1.2), o * CFrame.new(0, 5.9, -2.3), dark)
		eye(model, o * CFrame.new(-1, 5.2, -2.45), 1)
		eye(model, o * CFrame.new(1, 5.2, -2.45), 1)
		blob(model, "Mouth", Vector3.new(2.4, 0.7, 0.5), o * CFrame.new(0, 3.9, -2.8), BLACK)
		for _, s in { -1, 1 } do
			blob(model, "Arm", Vector3.new(2, 4.6, 2), o * CFrame.new(s * 3.7, 3.2, -0.4) * CFrame.Angles(0, 0, math.rad(s * 12)), body, slime(body))
			blob(model, "Fist", Vector3.new(2.6, 2.4, 2.6), o * CFrame.new(s * 4.1, 1.1, -0.8), dark)
			blob(model, "Foot", Vector3.new(2.4, 1.2, 2.8), o * CFrame.new(s * 1.6, 0.6, 0), dark)
		end
	else
		-- Grub → Goo Slug: uzun sümüklü gövde, göz sapları, iz bırakan balçık
		blob(model, "Body", Vector3.new(3.2, 3, 5.4), o * CFrame.new(0, 1.5, 0.4), body, slime(body))
		blob(model, "Head", Vector3.new(2.8, 2.6, 2.6), o * CFrame.new(0, 2.4, -1.8), body, slime(body))
		blob(model, "Trail", Vector3.new(2.6, 0.3, 6.4), o * CFrame.new(0, 0.15, 1), light, { Material = Enum.Material.Glass, Transparency = 0.4 })
		for _, s in { -1, 1 } do
			part(model, "Stalk", Vector3.new(0.3, 1.6, 0.3), o * CFrame.new(s * 0.7, 4, -2.2) * CFrame.Angles(math.rad(-15), 0, math.rad(s * 15)), body)
			eye(model, o * CFrame.new(s * 0.9, 4.9, -2.4), 0.8)
		end
		blob(model, "Mouth", Vector3.new(1.2, 0.4, 0.3), o * CFrame.new(0, 1.9, -3.05), BLACK)
		for k = 0, 2 do
			blob(model, "Spot", Vector3.new(0.7, 0.3, 0.7), o * CFrame.new(-0.6 + k * 0.6, 3, 0.2 + k * 0.9), glow, { Material = Enum.Material.Neon })
		end
	end
	return model
end

-- Liste/arayüz için yaratık adları (DefenseConfig.Enemies.name ile aynı)
return EnemyModel
