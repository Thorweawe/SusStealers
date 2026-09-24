--!strict
--[[
	Kozmetiklerin görünüşü: oyuncunun başındaki şapka, mağazadaki önizleme
	ve koşarken arkasında kalan iz aynı koddan çıkıyor — oyuncu mağazada
	gördüğünü başında görsün.

	Hazır varlık yok (oyunun kuralı, UiKit başındaki nota bak): her şapka
	parçalar ve yerleşik ağlardan (Sphere / Cylinder) kuruluyor. Among Us'ın
	tanınan şapkalarının siluetleri: filiz, parti şapkası, tuvalet kâğıdı,
	sahanda yumurta, aşçı şapkası, taç, hale...

	Şapka modelinin "Base" parçası kafanın tepesine oturan tabandır; alt
	yüzü modelin y=0'ında. Parçalar Base'e kaynaklı, sabitlenmemiş ve
	kütlesiz: karakterin dengesini bozmasın.
]]

local Config = require(script.Parent.Config)

local CosmeticModel = {}

type Piece = {
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	mesh: string?,     -- "Sphere" | "Cylinder" (SpecialMesh)
	shape: Enum.PartType?,
	neon: boolean?,
	transparency: number?,
}

local WHITE = Color3.fromRGB(242, 244, 248)
local GOLD = Color3.fromRGB(250, 200, 60)
local RED = Color3.fromRGB(210, 40, 50)
local GREEN = Color3.fromRGB(90, 200, 90)
local ORANGE = Color3.fromRGB(245, 120, 30)
local DARK = Color3.fromRGB(40, 44, 52)

--[[ Dik silindir: yerleşik silindirin ekseni X, Z etrafında 90° çevrilince dik duruyor. ]]
local function vcyl(name: string, y: number, height: number, diameter: number, color: Color3, extra: { [string]: any }?): Piece
	local p: any = {
		name = name,
		size = Vector3.new(height, diameter, diameter),
		cf = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color = color,
		shape = Enum.PartType.Cylinder,
	}
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end

--[[ Koni: üst üste daralan diskler. Gerçek koni ağı yok (hazır varlık kuralı). ]]
local function cone(list: { Piece }, name: string, y0: number, height: number, base: number, colors: { Color3 })
	local steps = 6
	for i = 0, steps - 1 do
		local t = i / steps
		local h = height / steps
		table.insert(list, vcyl(name, y0 + h * (i + 0.5), h + 0.01, base * (1 - t * 0.85), colors[i % #colors + 1]))
	end
end

--[[ Şapkanın parçaları. y=0 kafanın tepesi; ilk parça (Base) tabandır. ]]
local function pieces(id: string): { Piece }
	local list: { Piece } = {}
	if id == "Sprout" then
		table.insert(list, vcyl("Base", 0.05, 0.1, 0.3, GREEN))
		table.insert(list, vcyl("Stem", 0.45, 0.8, 0.12, GREEN))
		table.insert(list, { name = "Leaf", size = Vector3.new(0.7, 0.12, 0.35), cf = CFrame.new(-0.28, 0.85, 0) * CFrame.Angles(0, 0, math.rad(20)), color = GREEN, mesh = "Sphere" })
		table.insert(list, { name = "Leaf", size = Vector3.new(0.7, 0.12, 0.35), cf = CFrame.new(0.28, 0.85, 0) * CFrame.Angles(0, 0, math.rad(-20)), color = GREEN, mesh = "Sphere" })
	elseif id == "PartyHat" then
		table.insert(list, vcyl("Base", 0.05, 0.1, 1, Color3.fromRGB(60, 140, 240)))
		cone(list, "Cone", 0.1, 1.4, 1, { Color3.fromRGB(60, 140, 240), Color3.fromRGB(250, 90, 180) })
		table.insert(list, { name = "Pom", size = Vector3.new(0.35, 0.35, 0.35), cf = CFrame.new(0, 1.6, 0), color = GOLD, mesh = "Sphere" })
	elseif id == "ToiletPaper" then
		table.insert(list, vcyl("Base", 0.45, 0.9, 1, WHITE))
		table.insert(list, vcyl("Hole", 0.91, 0.03, 0.4, Color3.fromRGB(150, 120, 90)))
		table.insert(list, { name = "Tail", size = Vector3.new(0.5, 0.7, 0.04), cf = CFrame.new(0.3, 0.35, -0.5), color = WHITE })
	elseif id == "Antenna" then
		table.insert(list, vcyl("Base", 0.06, 0.12, 0.35, DARK))
		table.insert(list, vcyl("Rod", 0.7, 1.2, 0.08, Color3.fromRGB(180, 188, 200)))
		table.insert(list, { name = "Bulb", size = Vector3.new(0.35, 0.35, 0.35), cf = CFrame.new(0, 1.35, 0), color = RED, mesh = "Sphere", neon = true })
	elseif id == "FriedEgg" then
		table.insert(list, { name = "Base", size = Vector3.new(1.2, 0.12, 1.05), cf = CFrame.new(0, 0.06, 0), color = WHITE, mesh = "Sphere" })
		table.insert(list, { name = "Yolk", size = Vector3.new(0.45, 0.3, 0.45), cf = CFrame.new(0.1, 0.15, 0.05), color = GOLD, mesh = "Sphere" })
	elseif id == "ChefHat" then
		table.insert(list, vcyl("Base", 0.25, 0.5, 1, WHITE))
		table.insert(list, { name = "Puff", size = Vector3.new(1.3, 0.8, 1.3), cf = CFrame.new(0, 0.8, 0), color = WHITE, mesh = "Sphere" })
	elseif id == "TrafficCone" then
		table.insert(list, { name = "Base", size = Vector3.new(1.1, 0.12, 1.1), cf = CFrame.new(0, 0.06, 0), color = ORANGE })
		cone(list, "Cone", 0.12, 1.5, 0.9, { ORANGE, ORANGE, WHITE, ORANGE, WHITE, ORANGE })
	elseif id == "Horns" then
		table.insert(list, vcyl("Base", 0.04, 0.08, 0.9, DARK, { transparency = 1 }))
		for _, side in { -1, 1 } do
			for i = 0, 4 do
				local t = i / 5
				table.insert(list, {
					name = "Horn",
					size = Vector3.new(0.14, 0.3 * (1 - t * 0.7), 0.3 * (1 - t * 0.7)),
					cf = CFrame.new(side * (0.35 + t * 0.12), 0.1 + t * 0.55, 0) * CFrame.Angles(0, 0, math.rad(90 - side * 20)),
					color = Color3.fromRGB(200, 20, 30),
					shape = Enum.PartType.Cylinder,
				})
			end
		end
	elseif id == "Crown" then
		table.insert(list, vcyl("Base", 0.2, 0.4, 1.05, GOLD))
		for i = 0, 4 do
			local a = i / 5 * math.pi * 2
			table.insert(list, { name = "Spike", size = Vector3.new(0.18, 0.35, 0.18), cf = CFrame.new(math.cos(a) * 0.45, 0.55, math.sin(a) * 0.45) * CFrame.Angles(math.rad(45), 0, math.rad(45)), color = GOLD })
			table.insert(list, { name = "Jewel", size = Vector3.new(0.12, 0.12, 0.12), cf = CFrame.new(math.cos(a) * 0.53, 0.2, math.sin(a) * 0.53), color = if i % 2 == 0 then RED else Color3.fromRGB(60, 140, 240), mesh = "Sphere", neon = true })
		end
	elseif id == "Halo" then
		table.insert(list, vcyl("Base", 0.02, 0.04, 0.2, GOLD, { transparency = 1 }))
		for i = 0, 11 do
			local a = i / 12 * math.pi * 2
			table.insert(list, {
				name = "Ring",
				size = Vector3.new(0.3, 0.1, 0.12),
				cf = CFrame.new(math.cos(a) * 0.55, 0.7, math.sin(a) * 0.55) * CFrame.Angles(0, -a + math.pi / 2, 0),
				color = GOLD,
				neon = true,
			})
		end
	end
	return list
end

--[[
	Şapka modelini kurar. `anchored` önizleme için (ViewportFrame): orada
	fizik yok, parçalar yerinde dursun diye sabitleniyor. Karakterde
	sabitlenmemiş ve Base'e kaynaklı.
]]
function CosmeticModel.BuildHat(id: string, anchored: boolean?): Model?
	local list = pieces(id)
	if #list == 0 then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "CosmeticHat"
	local base: BasePart? = nil
	for _, piece in list do
		local p = Instance.new("Part")
		p.Name = piece.name
		p.Size = piece.size
		p.CFrame = piece.cf
		p.Color = piece.color
		p.Material = if piece.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		p.Transparency = piece.transparency or 0
		if piece.shape then
			p.Shape = piece.shape
		end
		if piece.mesh then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = if piece.mesh == "Cylinder" then Enum.MeshType.Cylinder else Enum.MeshType.Sphere
			mesh.Parent = p
		end
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.Anchored = anchored == true
		p.Parent = model
		if not base then
			base = p
		elseif not anchored then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = base
			weld.Part1 = p
			weld.Parent = p
		end
	end
	model.PrimaryPart = base
	return model
end

--[[
	İz: karakterin kök parçasına iki ek noktası ve bir Trail. Renk ve
	uzunluk Config'teki tanımdan.
]]
function CosmeticModel.ApplyTrail(root: BasePart, id: string): Trail?
	local def = Config.GetCosmetic(id)
	if not def or def.kind ~= "trail" then
		return nil
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "CosmeticTrail0"
	a0.Position = Vector3.new(0, 0.9, 0.4)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "CosmeticTrail1"
	a1.Position = Vector3.new(0, -0.9, 0.4)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Name = "CosmeticTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.6
	trail.LightEmission = 0.7
	trail.FaceCamera = true
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.WidthScale = NumberSequence.new(1, 0.1)
	local colors = def.colors or { def.color }
	if #colors == 1 then
		trail.Color = ColorSequence.new(colors[1])
	else
		local keys = {}
		for i, c in colors do
			table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
		end
		trail.Color = ColorSequence.new(keys)
	end
	trail.Parent = root
	return trail
end

--[[ Kök parçadan izi (ve ek noktalarını) kaldırır. ]]
function CosmeticModel.RemoveTrail(root: BasePart)
	for _, name in { "CosmeticTrail", "CosmeticTrail0", "CosmeticTrail1" } do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
end

return CosmeticModel
