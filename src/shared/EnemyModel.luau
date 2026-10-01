--!strict
--[[
	Gezegen savunmasının düşmanları: gezegenin renginde küçük yaratıklar
	(DefenseConfig.Enemies). Parçalardan, fiziksiz; istemci kendi savaşını
	çizerken kuruyor (DefenseFX). Kök "Root" ayak hizasında, yüzü -Z'ye
	(CFrame.lookAt ile döndürülüyor).

	Tür başına şekil:
	  Grub    — yuvarlak gövde, iki göz, kısa ayaklar
	  Skitter — basık, uzun bacaklı, tek büyük göz
	  Spitter — armut gövde, öne uzanan hortum
	  Brute   — iri, boynuzlu, kollu
	  Boss    — dev, taçlı, dikenli; gezegen canavarının yavrusu
]]

local EnemyModel = {}

local BLACK = Color3.fromRGB(20, 18, 26)
local WHITE = Color3.fromRGB(245, 245, 250)

type Props = { [string]: any }

local function part(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?, props: Props?): Part
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
	if shape then
		p.Shape = shape
	end
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = model
	return p
end

local function eye(model: Model, at: CFrame, size: number)
	part(model, "Eye", Vector3.one * size, at, WHITE, Enum.PartType.Ball)
	part(model, "Pupil", Vector3.one * size * 0.5, at * CFrame.new(0, 0, -size * 0.32), BLACK, Enum.PartType.Ball)
end

--[[
	kind: DefenseConfig.Enemies kimliği. body/dark/glow: gezegenin paleti.
	Dönen modelin her parçası Root'a göre sabit (istemci Root'u taşıyıp
	PivotTo yapıyor).
]]
function EnemyModel.Build(kind: string, body: Color3, dark: Color3, glow: Color3): Model
	local model = Instance.new("Model")
	model.Name = "Enemy_" .. kind
	local root = part(model, "Root", Vector3.new(1, 1, 1), CFrame.new(), body, nil, { Transparency = 1 })
	model.PrimaryPart = root

	local o = CFrame.new()
	if kind == "Skitter" then
		part(model, "Body", Vector3.new(2.6, 1.2, 2.2), o * CFrame.new(0, 1.3, 0), body, Enum.PartType.Ball)
		eye(model, o * CFrame.new(0, 1.6, -0.9), 0.9)
		for _, s in { -1, 1 } do
			for _, z in { -0.6, 0.6 } do
				part(model, "Leg", Vector3.new(0.2, 1.4, 0.2), o * CFrame.new(s * 1.3, 0.6, z) * CFrame.Angles(0, 0, math.rad(s * 35)), dark)
			end
		end
	elseif kind == "Spitter" then
		part(model, "Body", Vector3.new(2.2, 2.8, 2.2), o * CFrame.new(0, 1.6, 0), body, Enum.PartType.Ball)
		part(model, "Belly", Vector3.new(1.6, 1.8, 1.4), o * CFrame.new(0, 1.3, -0.5), body:Lerp(WHITE, 0.25), Enum.PartType.Ball)
		eye(model, o * CFrame.new(-0.45, 2.5, -0.85), 0.6)
		eye(model, o * CFrame.new(0.45, 2.5, -0.85), 0.6)
		part(model, "Snout", Vector3.new(1.4, 0.6, 0.6), o * CFrame.new(0, 2, -1.3) * CFrame.Angles(0, math.rad(90), 0), dark, Enum.PartType.Cylinder)
		part(model, "SnoutGlow", Vector3.new(0.2, 0.5, 0.5), o * CFrame.new(0, 2, -2) * CFrame.Angles(0, math.rad(90), 0), glow, Enum.PartType.Cylinder, { Material = Enum.Material.Neon })
		for _, s in { -1, 1 } do
			part(model, "Foot", Vector3.new(0.8, 0.5, 1), o * CFrame.new(s * 0.6, 0.25, 0), dark, Enum.PartType.Ball)
		end
	elseif kind == "Brute" then
		part(model, "Body", Vector3.new(3.6, 3.4, 3), o * CFrame.new(0, 2.2, 0), body, Enum.PartType.Ball)
		part(model, "Brow", Vector3.new(2.6, 0.5, 0.8), o * CFrame.new(0, 3.2, -1.1), dark)
		eye(model, o * CFrame.new(-0.6, 2.8, -1.25), 0.55)
		eye(model, o * CFrame.new(0.6, 2.8, -1.25), 0.55)
		for _, s in { -1, 1 } do
			part(model, "Horn", Vector3.new(0.5, 1.4, 0.5), o * CFrame.new(s * 1.2, 4, -0.3) * CFrame.Angles(0, 0, math.rad(-s * 25)), WHITE, nil, { Shape = Enum.PartType.Block })
			part(model, "Arm", Vector3.new(1, 2.4, 1), o * CFrame.new(s * 2, 1.6, -0.3), body:Lerp(dark, 0.4), Enum.PartType.Ball)
			part(model, "Foot", Vector3.new(1.2, 0.8, 1.4), o * CFrame.new(s * 0.9, 0.4, 0), dark, Enum.PartType.Ball)
		end
	elseif kind == "Boss" then
		part(model, "Body", Vector3.new(5.6, 5.2, 4.8), o * CFrame.new(0, 3.2, 0), body, Enum.PartType.Ball)
		part(model, "Belly", Vector3.new(3.6, 3.4, 2), o * CFrame.new(0, 2.6, -1.6), body:Lerp(WHITE, 0.2), Enum.PartType.Ball)
		eye(model, o * CFrame.new(-1, 4.4, -2), 1.1)
		eye(model, o * CFrame.new(1, 4.4, -2), 1.1)
		part(model, "Mouth", Vector3.new(2.4, 0.5, 0.4), o * CFrame.new(0, 3.1, -2.35), BLACK)
		-- Taç
		part(model, "CrownBand", Vector3.new(0.8, 3, 3), o * CFrame.new(0, 6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 205, 60), Enum.PartType.Cylinder, { Material = Enum.Material.Neon })
		for k = 0, 4 do
			local a = k / 5 * math.pi * 2
			part(model, "CrownSpike", Vector3.new(0.4, 1, 0.4), o * CFrame.new(math.cos(a) * 1.2, 6.8, math.sin(a) * 1.2), Color3.fromRGB(255, 205, 60))
		end
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			part(model, "Spike", Vector3.new(0.6, 1.6, 0.6), o * CFrame.new(math.cos(a) * 2.6, 3.4, math.sin(a) * 2.4) * CFrame.Angles(math.sin(a) * 0.6, 0, -math.cos(a) * 0.9), glow, nil, { Material = Enum.Material.Neon })
		end
		for _, s in { -1, 1 } do
			part(model, "Foot", Vector3.new(1.8, 1, 2), o * CFrame.new(s * 1.5, 0.5, 0), dark, Enum.PartType.Ball)
		end
	else
		-- Grub
		part(model, "Body", Vector3.new(2.4, 2.2, 2.4), o * CFrame.new(0, 1.4, 0), body, Enum.PartType.Ball)
		eye(model, o * CFrame.new(-0.45, 1.9, -0.95), 0.6)
		eye(model, o * CFrame.new(0.45, 1.9, -0.95), 0.6)
		part(model, "Antenna", Vector3.new(0.15, 1, 0.15), o * CFrame.new(0, 2.8, 0), dark)
		part(model, "AntennaTip", Vector3.one * 0.4, o * CFrame.new(0, 3.3, 0), glow, Enum.PartType.Ball, { Material = Enum.Material.Neon })
		for _, s in { -1, 1 } do
			part(model, "Foot", Vector3.new(0.7, 0.5, 0.9), o * CFrame.new(s * 0.6, 0.25, 0), dark, Enum.PartType.Ball)
		end
	end
	return model
end

return EnemyModel
