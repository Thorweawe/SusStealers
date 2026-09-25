--!strict
--[[
	Ekipmanın görünüşü: eldeki Tool ve dükkândaki vitrin modeli aynı
	koddan çıkıyor, oyuncu vitrinde gördüğünü elinde görsün.

	Hazır varlık yok; parçalar ve yerleşik ağlar (Sphere / Cylinder).

	  Slap Glove       — kırmızı eldiven: avuç, dört parmak, başparmak, bilek
	  Speed Coil       — kırmızı-mavi yay: sık halkalar, parlayan uç
	  Stun Gun         — sarı gövdeli şok tabancası, ucunda mavi elektrot
	  Ghost Serum      — cam şişe, içinde parlayan hayalet sıvısı, mantar tıpa
	  Emergency Button — Among Us'ın acil toplantı düğmesi: gri kaide,
	                     cam kubbe altında kırmızı düğme

	Tool'da her parça "Handle"a kaynaklı, sabitlenmemiş ve kütlesiz: eldeki
	alet karakterin dengesini bozmasın.

	YÖN: Grip birim matrisken aletin +Y'si yukarı, -Z'si karakterin önü
	(RightGripAttachment dünya eksenli duruyor, kol önde). Parçalar bu
	eksenlerle çiziliyor; eldiven tek istisna (parmaklar +Y'de çizili,
	Grip onları öne yatırıyor).
]]

local Config = require(script.Parent.Config)

local GearModel = {}

type Piece = { name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, mesh: string?, shape: Enum.PartType?, transparency: number? }

local RED = Color3.fromRGB(210, 40, 50)
local CUFF = Color3.fromRGB(240, 240, 245)
local METAL = Color3.fromRGB(190, 198, 210)
local DARK = Color3.fromRGB(40, 44, 52)
local BLUE = Color3.fromRGB(40, 110, 240)
local YELLOW = Color3.fromRGB(250, 196, 40)
local GHOST = Color3.fromRGB(120, 255, 220)

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
	elseif id == "StunGun" then
		return {
			{ name = "Handle", size = Vector3.new(0.34, 0.9, 0.5), cf = CFrame.new(0, 0, 0), color = DARK },
			{ name = "Body", size = Vector3.new(0.5, 0.55, 1.7), cf = CFrame.new(0, 0.6, -0.45), color = YELLOW },
			{ name = "Stripe", size = Vector3.new(0.52, 0.14, 1.2), cf = CFrame.new(0, 0.62, -0.5), color = DARK },
			{ name = "Trigger", size = Vector3.new(0.1, 0.3, 0.12), cf = CFrame.new(0, 0.2, -0.38), color = DARK },
			{ name = "Nose", size = Vector3.new(0.4, 0.4, 0.3), cf = CFrame.new(0, 0.6, -1.42), color = DARK },
			{ name = "ProngL", size = Vector3.new(0.08, 0.08, 0.3), cf = CFrame.new(-0.12, 0.6, -1.66), color = METAL, material = Enum.Material.Metal },
			{ name = "ProngR", size = Vector3.new(0.08, 0.08, 0.3), cf = CFrame.new(0.12, 0.6, -1.66), color = METAL, material = Enum.Material.Metal },
			{ name = "Tip", size = Vector3.new(0.22, 0.22, 0.22), cf = CFrame.new(0, 0.6, -1.66), color = Color3.fromRGB(110, 200, 255), material = Enum.Material.Neon, mesh = "Sphere" },
			{ name = "Battery", size = Vector3.new(0.3, 0.2, 0.4), cf = CFrame.new(0, 0.95, 0.1), color = Color3.fromRGB(110, 200, 255), material = Enum.Material.Neon },
		}
	elseif id == "GhostSerum" then
		return {
			{ name = "Handle", size = Vector3.new(0.8, 0.9, 0.8), cf = CFrame.new(0, 0, 0), color = Color3.fromRGB(220, 250, 255), material = Enum.Material.Glass, mesh = "Cylinder", transparency = 0.45 },
			{ name = "Liquid", size = Vector3.new(0.66, 0.66, 0.66), cf = CFrame.new(0, -0.08, 0), color = GHOST, material = Enum.Material.Neon, mesh = "Cylinder", transparency = 0.15 },
			{ name = "Shoulder", size = Vector3.new(0.8, 0.36, 0.8), cf = CFrame.new(0, 0.5, 0), color = Color3.fromRGB(220, 250, 255), material = Enum.Material.Glass, mesh = "Sphere", transparency = 0.45 },
			{ name = "Neck", size = Vector3.new(0.3, 0.4, 0.3), cf = CFrame.new(0, 0.76, 0), color = Color3.fromRGB(220, 250, 255), material = Enum.Material.Glass, mesh = "Cylinder", transparency = 0.4 },
			{ name = "Cork", size = Vector3.new(0.34, 0.24, 0.34), cf = CFrame.new(0, 1.02, 0), color = Color3.fromRGB(160, 110, 60), mesh = "Cylinder" },
			{ name = "Label", size = Vector3.new(0.5, 0.3, 0.05), cf = CFrame.new(0, 0, -0.41), color = Color3.fromRGB(245, 245, 250) },
			{ name = "Ghost", size = Vector3.new(0.22, 0.22, 0.05), cf = CFrame.new(0, 0, -0.44), color = GHOST:Lerp(Color3.new(0, 0, 0), 0.4), mesh = "Sphere" },
		}
	elseif id == "EmergencyButton" then
		return {
			{ name = "Handle", size = Vector3.new(1.4, 0.4, 1.4), cf = CFrame.new(0, 0, 0), color = Color3.fromRGB(150, 158, 170), material = Enum.Material.Metal, mesh = "Cylinder" },
			{ name = "Rim", size = Vector3.new(1.2, 0.14, 1.2), cf = CFrame.new(0, 0.26, 0), color = DARK, mesh = "Cylinder" },
			{ name = "Button", size = Vector3.new(0.8, 0.5, 0.8), cf = CFrame.new(0, 0.34, 0), color = Color3.fromRGB(230, 30, 40), material = Enum.Material.Neon, mesh = "Sphere" },
			{ name = "Dome", size = Vector3.new(1.16, 0.9, 1.16), cf = CFrame.new(0, 0.3, 0), color = Color3.fromRGB(200, 230, 255), material = Enum.Material.Glass, mesh = "Sphere", transparency = 0.6 },
			{ name = "Stripe", size = Vector3.new(1.42, 0.1, 1.42), cf = CFrame.new(0, -0.08, 0), color = YELLOW, mesh = "Cylinder" },
		}
	end

	-- Speed Coil
	local tint, accent, rings = RED, BLUE, 7
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
	p.Transparency = piece.transparency or 0
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

	--[[
		Eldiven: parmaklar (+Y) öne, başparmak (-X) yukarı; avuç yana dönük,
		sağdan sola tokat atarken avuç içi vuruyor. Eskiden Grip parmakları
		oyuncunun kendisine çeviriyordu ("ters duruyor").
	]]
	if id == "SlapGlove" then
		local held = CFrame.fromMatrix(Vector3.new(0, 0, -0.25), Vector3.new(0, -1, 0), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0))
		tool.Grip = held:Inverse()
	elseif id == "StunGun" then
		tool.Grip = CFrame.new(0, -0.1, 0)
	elseif id == "EmergencyButton" then
		tool.Grip = CFrame.new(0, 0.35, 0)
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
