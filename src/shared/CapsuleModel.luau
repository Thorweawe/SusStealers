--!strict
--[[
	Uzay kapsülü: her üssün arkasında, üssün zemininin dışında (oda ile
	duvar arasındaki boşlukta). İçinde duran sahibin uzay hızı artıyor
	(CapsuleService); içeride karakter süzülüyor ve "roketi alanda tut" mini
	oyunu ekstra hız veriyor (CapsuleFX).

	Cam tüp: 12 panellik halka, önde 3 panel boş (kapı). Kapı -Z'ye (üssün
	içine) bakıyor. Model ayak tabanı y = 0'da kuruluyor; PlotService üssün
	zemin üstüne taşıyor.

	Adı sabit parçalar (sunucu ve istemci bunlara bakıyor):
	  Zone      — görünmez hacim: içinde duran antrenman yapıyor
	  Pad       — zemindeki parlak disk (istemci nabız veriyor)
	  Screen    — kapının üstündeki tabela (SurfaceGui "Info": Title/Level)
	  Console   — kapının sağındaki yükseltme konsolu (prompt sunucudan)
	  Trainer   — kapının SOLUNDAKİ Training Console istasyonu: mini oyunu
	              kolaylaştıran yükseltme (prompt sunucudan, ekranı "TrainerInfo")
	  Warp      — tavandaki yıldız akışı (ParticleEmitter, antrenmanda açık)
]]

local CapsuleModel = {}

CapsuleModel.RADIUS = 7.5
CapsuleModel.HEIGHT = 16

local METAL = Color3.fromRGB(196, 206, 218)
local METAL_DARK = Color3.fromRGB(92, 102, 118)
local GLASS = Color3.fromRGB(150, 220, 255)
local NEON = Color3.fromRGB(80, 200, 255)

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if props then
		for k, v in props do
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

-- Dik silindir (ekseni Y)
local function vcyl(parent: Instance, name: string, center: Vector3, height: number, diameter: number, color: Color3, props: { [string]: any }?): BasePart
	local p = part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function text(parent: Instance, name: string, value: string, size: number, color: Color3, order: number)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.LayoutOrder = order
	t.Size = UDim2.new(1, 0, 0, size * 1.2)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextSize = size
	t.TextColor3 = color
	t.Text = value
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(16, 20, 40)
	s.Thickness = math.max(2, size / 12)
	s.Parent = t
	t.Parent = parent
end

--[[ Kapsülü kurar: ayak tabanı `origin`'de, kapı origin'in -Z'sine bakıyor. ]]
function CapsuleModel.Build(origin: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Capsule"
	local R = CapsuleModel.RADIUS
	local H = CapsuleModel.HEIGHT

	local function at(x: number, y: number, z: number): CFrame
		return origin * CFrame.new(x, y, z)
	end

	-- Taban: iki kademe metal + parlak halka
	local base = vcyl(model, "Base", at(0, 0.35, 0).Position, 0.7, R * 2 + 2.4, METAL_DARK)
	vcyl(model, "BaseTop", at(0, 0.78, 0).Position, 0.2, R * 2 + 1.2, METAL)
	vcyl(model, "BaseRing", at(0, 0.72, 0).Position, 0.24, R * 2 + 1.8, NEON, { Material = Enum.Material.Neon })
	local pad = vcyl(model, "Pad", at(0, 0.92, 0).Position, 0.1, R * 2 - 1.6, NEON, { Material = Enum.Material.Neon, Transparency = 0.2 })
	pad.CanCollide = false
	-- Pedde hedef halkaları
	vcyl(model, "PadRing", at(0, 0.95, 0).Position, 0.1, R * 1.1, Color3.fromRGB(220, 250, 255), { Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false })
	vcyl(model, "PadDot", at(0, 0.98, 0).Position, 0.1, 1.2, Color3.fromRGB(255, 255, 255), { Material = Enum.Material.Neon, CanCollide = false })

	-- Cam paneller ve direkler: 12 dilim, önde (a = 0, -Z) üç dilim kapı
	local panels = 12
	local panelW = 2 * R * math.tan(math.pi / panels) + 0.08
	for i = 0, panels - 1 do
		local a = i * (math.pi * 2 / panels)
		local dir = Vector3.new(math.sin(a), 0, -math.cos(a))
		local deg = math.deg(a)
		local isDoor = deg < 46 or deg > 314
		local center = at(0, 0, 0).Position + origin:VectorToWorldSpace(dir * R) + Vector3.new(0, 1 + (H - 1) / 2, 0)
		local worldDir = origin:VectorToWorldSpace(dir)
		if not isDoor then
			part(model, "Glass", Vector3.new(panelW, H - 1, 0.25), CFrame.lookAt(center, center + worldDir), GLASS,
				{ Material = Enum.Material.Glass, Transparency = 0.62, CastShadow = false })
		end
		-- Direk: dilimlerin köşesinde
		local ea = a + math.pi / panels
		local edge = Vector3.new(math.sin(ea), 0, -math.cos(ea)) * (R + 0.05)
		local ep = at(0, 0, 0).Position + origin:VectorToWorldSpace(edge) + Vector3.new(0, 1 + (H - 1) / 2, 0)
		vcyl(model, "Strut", ep, H - 1, 0.45, METAL)
	end
	-- Kapı kenarında kalın çerçeve ve parlak şerit
	for _, s in { -1, 1 } do
		local ea = s * (math.pi / panels) * 3
		local edge = Vector3.new(math.sin(ea), 0, -math.cos(ea)) * (R + 0.1)
		local ep = at(0, 0, 0).Position + origin:VectorToWorldSpace(edge)
		vcyl(model, "DoorPost", ep + Vector3.new(0, 1 + (H - 1) / 2, 0), H - 1, 0.9, METAL_DARK)
		vcyl(model, "DoorLight", ep + Vector3.new(0, 1 + (H - 1) / 2, 0) + origin:VectorToWorldSpace(Vector3.new(0, 0, -0.3)), H - 2, 0.35, NEON,
			{ Material = Enum.Material.Neon, CanCollide = false })
	end

	-- Tavan: kapak, kubbe, anten ve lamba
	vcyl(model, "TopRing", at(0, H + 0.3, 0).Position, 0.6, R * 2 + 0.8, METAL_DARK)
	vcyl(model, "Top", at(0, H + 0.8, 0).Position, 0.5, R * 2 + 0.2, METAL)
	local dome = part(model, "Dome", Vector3.new(R * 1.7, R * 1.7, R * 1.7), at(0, H + 0.9, 0), METAL, { Shape = Enum.PartType.Ball })
	dome.CastShadow = false
	-- Kubbenin alt yarısı kapağın içinde kalıyor; üstünde halka ışık
	vcyl(model, "DomeBand", at(0, H + 1.6, 0).Position, 0.3, R * 1.66, NEON, { Material = Enum.Material.Neon, CanCollide = false })
	vcyl(model, "Antenna", at(0, H + 3.6, 0).Position, 3, 0.25, METAL_DARK)
	local lamp = part(model, "Lamp", Vector3.new(0.8, 0.8, 0.8), at(0, H + 5.2, 0), Color3.fromRGB(255, 80, 80), { Shape = Enum.PartType.Ball, Material = Enum.Material.Neon })
	lamp:SetAttribute("PulsePeriod", 1.6)

	-- İçerideki ışık ve yıldız akışı
	local glow = Instance.new("PointLight")
	glow.Color = NEON
	glow.Range = 14
	glow.Brightness = 1.2
	glow.Parent = pad
	local emitterHost = part(model, "WarpSource", Vector3.new(1, 0.2, 1), at(0, H - 0.4, 0), NEON, { Transparency = 1, CanCollide = false, CanQuery = false })
	local warp = Instance.new("ParticleEmitter")
	warp.Name = "Warp"
	warp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	warp.Color = ColorSequence.new(Color3.fromRGB(200, 240, 255), NEON)
	warp.LightEmission = 1
	warp.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.1) })
	warp.Transparency = NumberSequence.new(0.1, 0.9)
	warp.Lifetime = NumberRange.new(0.5, 0.8)
	warp.Speed = NumberRange.new(14, 22)
	warp.EmissionDirection = Enum.NormalId.Bottom
	warp.SpreadAngle = Vector2.new(24, 24)
	warp.Rate = 60
	warp.Enabled = false
	warp.Parent = emitterHost

	-- Görünmez antrenman hacmi
	local zone = vcyl(model, "Zone", at(0, 1 + (H - 1) / 2, 0).Position, H - 1, R * 2 - 0.8, NEON,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	zone:SetAttribute("Radius", R - 0.4)

	-- Kapının üstünde tabela
	local screenCf = origin * CFrame.new(0, H - 2, -R - 0.35)
	local screen = part(model, "Screen", Vector3.new(10, 2.8, 0.3), screenCf, Color3.fromRGB(20, 26, 46))
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Info"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = screen
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = gui
	text(gui, "Title", "SPACE CAPSULE", 44, Color3.fromRGB(130, 225, 255), 1)
	text(gui, "Level", "LEVEL 0", 32, Color3.new(1, 1, 1), 2)

	-- Yükseltme konsolu: kapının sağında, üssün içine bakıyor
	local consoleCf = origin * CFrame.new(R + 2.2, 0, -R + 0.4)
	local console = part(model, "Console", Vector3.new(2.2, 3, 1.8), consoleCf * CFrame.new(0, 1.5, 0), METAL_DARK)
	part(model, "ConsoleTop", Vector3.new(2.4, 0.3, 2.1), consoleCf * CFrame.new(0, 3.1, -0.1) * CFrame.Angles(math.rad(20), 0, 0), METAL)
	part(model, "ConsoleScreen", Vector3.new(1.8, 0.1, 1.3), consoleCf * CFrame.new(0, 3.28, -0.15) * CFrame.Angles(math.rad(20), 0, 0), Color3.fromRGB(255, 200, 60),
		{ Material = Enum.Material.Neon, CanCollide = false })

	--[[
		Training Console (2026-09-28): kapının solunda ayrı bir istasyon.
		Kapsül mini oyununu kolaylaştıran yükseltme burada; eğik holografik
		panelinde yeşil hedef çizgisi, üstünde kendi tabelası var.
	]]
	local trainerCf = origin * CFrame.new(-(R + 2.4), 0, -R + 0.6)
	local TRAIN = Color3.fromRGB(110, 255, 140)
	local trainer = part(model, "Trainer", Vector3.new(2.6, 3.2, 2), trainerCf * CFrame.new(0, 1.6, 0), METAL_DARK)
	part(model, "TrainerBase", Vector3.new(3.2, 0.4, 2.6), trainerCf * CFrame.new(0, 0.2, 0), METAL)
	part(model, "TrainerTop", Vector3.new(2.8, 0.3, 2.3), trainerCf * CFrame.new(0, 3.3, -0.1) * CFrame.Angles(math.rad(22), 0, 0), METAL)
	part(model, "TrainerScreen", Vector3.new(2.2, 0.1, 1.6), trainerCf * CFrame.new(0, 3.48, -0.15) * CFrame.Angles(math.rad(22), 0, 0), TRAIN,
		{ Material = Enum.Material.Neon, CanCollide = false })
	-- Holografik hedef çizgisi: mini oyunun yeşil alanı gibi
	part(model, "TrainerHolo", Vector3.new(0.15, 2.2, 1.4), trainerCf * CFrame.new(0, 5, 0), TRAIN,
		{ Material = Enum.Material.Neon, Transparency = 0.45, CanCollide = false, CastShadow = false })
	part(model, "TrainerHoloBar", Vector3.new(0.2, 0.6, 1.5), trainerCf * CFrame.new(0, 5.2, 0), Color3.fromRGB(255, 255, 255),
		{ Material = Enum.Material.Neon, Transparency = 0.2, CanCollide = false, CastShadow = false })
	local trainerSign = part(model, "TrainerSign", Vector3.new(5.2, 1.4, 0.2), trainerCf * CFrame.new(0, 7, 0), Color3.fromRGB(20, 30, 26))
	local tgui = Instance.new("SurfaceGui")
	tgui.Name = "TrainerInfo"
	tgui.Face = Enum.NormalId.Front
	tgui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	tgui.PixelsPerStud = 40
	tgui.LightInfluence = 0
	tgui.Parent = trainerSign
	local tlist = Instance.new("UIListLayout")
	tlist.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tlist.VerticalAlignment = Enum.VerticalAlignment.Center
	tlist.Parent = tgui
	text(tgui, "Title", "TRAINING CONSOLE", 22, TRAIN, 1)
	text(tgui, "Level", "LEVEL 0", 18, Color3.new(1, 1, 1), 2)

	model.PrimaryPart = base
	local _ = console
	local _t = trainer
	return model
end

return CapsuleModel
