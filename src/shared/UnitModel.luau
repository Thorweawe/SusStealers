--!strict
-- Among Us tarzı karakteri koddan üretir. Hazır asset gerekmiyor;
-- MCP bağlanınca modelleri Creator Store'dan değiştirmek isterse
-- sadece Build fonksiyonunu değiştirmek yeterli.

local Config = require(script.Parent.Config)

local UnitModel = {}

local function newPart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

--[[
	Verilen karakter tanımı için bir Model üretir.
	Model'in PrimaryPart'ı gövdedir, ayakların tabanı y=0 hizasındadır.
]]
function UnitModel.Build(unitId: string, mutationId: string?): Model
	local def = Config.GetUnit(unitId)
	assert(def, string.format("UnitModel: bilinmeyen karakter '%s'", unitId))

	local mutation = Config.GetMutation(mutationId)
	local bodyColor = def.color
	if mutation and mutation.tint then
		bodyColor = def.color:Lerp(mutation.tint, 0.65)
	end

	local model = Instance.new("Model")
	model.Name = def.id

	-- Gövde (Among Us fasulyesi: dikey silindir + yuvarlak üst)
	local body = newPart("Body", Vector3.new(2.0, 2.4, 2.0), bodyColor, Enum.Material.SmoothPlastic)
	body.Shape = Enum.PartType.Cylinder
	-- Cylinder ekseni X'tir, dikey durması için Z etrafında 90° çeviriyoruz
	body.CFrame = CFrame.new(0, 1.8, 0) * CFrame.Angles(0, 0, math.rad(90))
	body.Parent = model

	local head = newPart("Head", Vector3.new(2.0, 2.0, 2.0), bodyColor, Enum.Material.SmoothPlastic)
	head.Shape = Enum.PartType.Ball
	head.CFrame = CFrame.new(0, 3.0, 0)
	head.Parent = model

	-- Vizör
	local visor = newPart("Visor", Vector3.new(1.35, 0.85, 0.55), Color3.fromRGB(150, 220, 255), Enum.Material.Glass)
	visor.Shape = Enum.PartType.Block
	visor.CFrame = CFrame.new(0, 3.05, -0.85)
	visor.Reflectance = 0.25
	visor.Parent = model

	-- Sırt çantası
	local pack = newPart("Backpack", Vector3.new(0.8, 1.9, 0.9), bodyColor, Enum.Material.SmoothPlastic)
	pack.CFrame = CFrame.new(0, 2.0, 1.25)
	pack.Parent = model

	-- Bacaklar
	for index, offset in { -0.55, 0.55 } do
		local leg = newPart("Leg" .. index, Vector3.new(0.75, 1.3, 1.0), bodyColor, Enum.Material.SmoothPlastic)
		leg.CFrame = CFrame.new(offset, 0.65, 0)
		leg.Parent = model
	end

	-- Nadirlik halkası (zeminde parlayan disk)
	local rarity = Config.Rarities[def.rarity]
	local glow = Instance.new("PointLight")
	glow.Color = rarity.color
	glow.Range = 10
	glow.Brightness = if mutation then 2.5 else 1.2
	glow.Parent = body

	model.PrimaryPart = body

	-- Meta bilgiler: diğer sistemler modelden okuyabilsin
	local unitTag = Instance.new("StringValue")
	unitTag.Name = "UnitId"
	unitTag.Value = def.id
	unitTag.Parent = model

	local mutationTag = Instance.new("StringValue")
	mutationTag.Name = "MutationId"
	mutationTag.Value = if mutation then mutation.id else ""
	mutationTag.Parent = model

	return model
end

--[[ Karakterin üstünde duran isim/gelir etiketi. ]]
function UnitModel.BuildLabel(unitId: string, mutationId: string?): BillboardGui
	local def = Config.GetUnit(unitId)
	assert(def, string.format("UnitModel: bilinmeyen karakter '%s'", unitId))

	local mutation = Config.GetMutation(mutationId)
	local rarity = Config.Rarities[def.rarity]
	local income = def.income * (if mutation then mutation.incomeMul else 1)

	local gui = Instance.new("BillboardGui")
	gui.Name = "UnitLabel"
	gui.Size = UDim2.fromScale(7, 2.2)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 120

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.55)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = rarity.color
	title.TextStrokeTransparency = 0.2
	title.Text = if mutation then string.format("[%s] %s", mutation.name, def.name) else def.name
	title.Parent = gui

	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Income"
	subtitle.Position = UDim2.fromScale(0, 0.55)
	subtitle.Size = UDim2.fromScale(1, 0.45)
	subtitle.BackgroundTransparency = 1
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextScaled = true
	subtitle.TextColor3 = Color3.fromRGB(120, 255, 150)
	subtitle.TextStrokeTransparency = 0.4
	subtitle.Text = "$" .. Config.FormatCash(income) .. "/s"
	subtitle.Parent = gui

	return gui
end

return UnitModel
