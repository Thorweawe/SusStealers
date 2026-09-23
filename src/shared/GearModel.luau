--!strict
--[[
	Ekipmanın görünüşü: eldeki Tool ve dükkândaki vitrin modeli aynı
	koddan çıkıyor, oyuncu vitrinde gördüğünü elinde görsün.

	Hazır varlık yok; parçalar ve yerleşik ağlar (Sphere / Cylinder).

	  Slap Glove   — kırmızı eldiven: avuç, dört parmak, başparmak, bilek
	  Gravity Coil — mor yay: üst üste halkalar, altta sap
	  Speed Coil   — kırmızı-mavi yay: daha sık halkalar, parlayan uç

	Tool'da her parça "Handle"a kaynaklı, sabitlenmemiş ve kütlesiz: eldeki
	alet karakterin dengesini bozmasın.
]]

local Config = require(script.Parent.Config)

local GearModel = {}

type Piece = { name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, mesh: string?, shape: Enum.PartType? }

local RED = Color3.fromRGB(210, 40, 50)
local CUFF = Color3.fromRGB(240, 240, 245)
local METAL = Color3.fromRGB(190, 198, 210)
local PURPLE = Color3.fromRGB(140, 70, 230)
local BLUE = Color3.fromRGB(40, 110, 240)

--[[ Aletin parçaları, sapın merkezine göre (sap = ilk parça). ]]
local function pieces(id: string): { Piece }
	if id == "SlapGlove" then
		local list: { Piece } = {
			{ name = "Handle", size = Vector3.new(0.7, 0.7, 0.7), cf = CFrame.new(0, 0, 0), color = CUFF, mesh = "Cylinder" },
			{ name = "Palm", size = Vector3.new(1.3, 1.1, 0.6), cf = CFrame.new(0, 0.85, 0), color = RED, mesh = "Sphere" },
			{ name = "Thumb", size = Vector3.new(0.3, 0.7, 0.3), cf = CFrame.new(-0.65, 0.9, -0.05) * CFrame.Angles(0, 0, math.rad(35)), color = RED, mesh = "Sphere" },
		}
		for i = 0, 3 do
			table.insert(list, {
				name = "Finger", size = Vector3.new(0.26, 0.75, 0.3),
				cf = CFrame.new(-0.36 + i * 0.24, 1.5, 0), color = RED, mesh = "Sphere",
			})
		end
		return list
	end

	local tint = if id == "SpeedCoil" then RED else PURPLE
	local accent = if id == "SpeedCoil" then BLUE else Color3.fromRGB(230, 200, 255)
	local rings = if id == "SpeedCoil" then 7 else 5
	local list: { Piece } = {
		{ name = "Handle", size = Vector3.new(0.35, 0.9, 0.35), cf = CFrame.new(0, 0, 0), color = METAL, material = Enum.Material.Metal },
	}
	for i = 1, rings do
		table.insert(list, {
			name = "Ring",
			size = Vector3.new(0.14, 0.9, 0.9),
			cf = CFrame.new(0, 0.45 + i * 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			color = if i % 2 == 0 then accent else tint,
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Cylinder,
		})
	end
	table.insert(list, {
		name = "Tip", size = Vector3.new(0.4, 0.4, 0.4), cf = CFrame.new(0, 0.55 + rings * 0.2, 0),
		color = accent, material = Enum.Material.Neon, mesh = "Sphere",
	})
	return list
end

local function makePart(piece: Piece): Part
	local p = Instance.new("Part")
	p.Name = piece.name
	p.Size = piece.size
	p.Color = piece.color
	p.Material = piece.material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = piece.name == "Handle"
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if piece.shape then
		p.Shape = piece.shape
	end
	if piece.mesh then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = if piece.mesh == "Cylinder" then Enum.MeshType.Cylinder else Enum.MeshType.Sphere
		mesh.Parent = p
	end
	return p
end

--[[ Sırt çantasına giden Tool. Tanınmayan kimlik nil. ]]
function GearModel.BuildTool(id: string): Tool?
	local def = Config.GetGear(id)
	if not def then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.Name = def.name
	tool.ToolTip = def.blurb
	tool.CanBeDropped = false
	tool:SetAttribute("GearId", def.id)

	local list = pieces(id)
	local handle = makePart(list[1])
	handle.Massless = true
	handle.Parent = tool

	for i = 2, #list do
		local part = makePart(list[i])
		part.CFrame = handle.CFrame * list[i].cf
		part.Massless = true
		part.Parent = tool
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = part
		weld.Parent = part
	end

	-- Eldiven avucu öne dönük tutulsun; yaylar dik
	if id == "SlapGlove" then
		tool.Grip = CFrame.new(0, -0.3, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	else
		tool.Grip = CFrame.new(0, -0.2, 0)
	end
	return tool
end

--[[
	Dükkân vitrini: aynı parçalar, sabitlenmiş, verilen noktada duruyor
	ve 1.6 kat büyük — tezgâhın üstünde uzaktan seçilsin.
]]
function GearModel.BuildDisplay(id: string, at: CFrame): Model?
	if not Config.GetGear(id) then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Display_" .. id
	local base: Part? = nil
	for i, piece in pieces(id) do
		local part = makePart(piece)
		part.Anchored = true
		part.CanTouch = false
		part.CFrame = at * piece.cf
		part.Parent = model
		if i == 1 then
			base = part
		end
	end
	model.PrimaryPart = base
	model:ScaleTo(1.6)
	return model
end

return GearModel
