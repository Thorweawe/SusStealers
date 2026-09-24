--!strict
--[[
	Yumurta stilleri: her yumurtanın kendine özgü görünüşü, boşta
	animasyonu ve açılış animasyonu.

	NEDEN: dört yumurta da aynı krem rengi ovaldi, aynı şekilde süzülüyor ve
	aynı şekilde çatlıyordu. Fark yalnızca kapsülün ışık efektindeydi;
	oyuncu $50K'lık kutuyla $9B'lık yumurtayı bakışta ayıramıyordu.

	Her yumurta kendi hikâyesini taşıyor:

	  Supply Egg  — kargo kolisi: karton kabuk, sarı koli bandı. Yerinde
	                sabırsızca zıplıyor, iniş anında basılıp sallanıyor.
	                Açılışta sert sarsıntı, karton parçaları saçılıyor.
	  Skeld Egg   — gemi kapsülü: beyaz gövde, mürettebat vizörü, anten.
	                Kendi ekseninde dönüyor, antenin lambası yanıp sönüyor.
	                Açılışta giderek hızlanan dönüş, vida/cıvata saçılıyor.
	  Polus Egg   — buz yumurtası: buz mavisi, tepesinde kar, dibinde buz
	                kristalleri, çevresinde kar taneleri. Ağır ağır süzülüyor.
	                Açılışta donup titriyor, kar saçılıyor.
	  Void Egg    — boşluk: koyu mor kabuk, parlayan yarık, nabız gibi atan
	                hale ve yörüngede dönen ışık küreleri. Açılışta içine
	                çöküp patlıyor, yıldızlar saçılıyor.

	Dünyadaki süsler İSTEMCİDE kuruluyor (yalnızca görsel; sunucunun
	bilmesine gerek yok, harita yeniden kurulmadan çalışıyor). Yumurta
	kabuğunun kendisi haritada (Decor.Hatchery.EggN); promptları sunucu
	ona bağlıyor, burada yalnızca rengi ve konumu yerelde değişiyor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local UiKit = require(script.Parent.UiKit)

local EggStyle = {}

export type Style = {
	title: string,     -- açılış başlığı
	shell: Color3,     -- kabuk
	accent: Color3,    -- desen (bant, kar, yarık)
	glow: Color3,      -- parlama ve ışınlar
	backdrop: Color3,  -- açılış ekranının zemini
	idle: string,      -- boşta: hop | spin | drift | pulse
	crack: string,     -- açılış: shake | spin | freeze | implode
	bits: string,      -- açılışta saçılanlar: cardboard | bolts | snow | stars
	reflect: number,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local STYLES: { [string]: Style } = {
	SupplyEgg = {
		title = "SUPPLY DROP", shell = rgb(206, 160, 104), accent = rgb(252, 204, 48),
		glow = rgb(255, 222, 140), backdrop = rgb(38, 26, 14),
		idle = "hop", crack = "shake", bits = "cardboard", reflect = 0,
	},
	SkeldEgg = {
		title = "SKELD POD", shell = rgb(218, 228, 238), accent = rgb(90, 226, 246),
		glow = rgb(140, 236, 255), backdrop = rgb(8, 22, 40),
		idle = "spin", crack = "spin", bits = "bolts", reflect = 0.12,
	},
	PolusEgg = {
		title = "POLUS FROST", shell = rgb(190, 228, 248), accent = rgb(250, 252, 255),
		glow = rgb(160, 224, 255), backdrop = rgb(10, 34, 52),
		idle = "drift", crack = "freeze", bits = "snow", reflect = 0.18,
	},
	VoidEgg = {
		title = "VOID RIFT", shell = rgb(52, 30, 88), accent = rgb(190, 110, 255),
		glow = rgb(200, 150, 255), backdrop = rgb(8, 3, 18),
		idle = "pulse", crack = "implode", bits = "stars", reflect = 0,
	},
}

local DEFAULT: Style = {
	title = "HATCHING", shell = rgb(236, 228, 210), accent = rgb(255, 255, 255),
	glow = rgb(255, 255, 255), backdrop = rgb(0, 0, 0),
	idle = "hop", crack = "shake", bits = "cardboard", reflect = 0,
}

function EggStyle.Get(eggId: string?): Style
	if eggId and STYLES[eggId] then
		return STYLES[eggId]
	end
	return DEFAULT
end

-- ─── Arayüzde yumurta ───────────────────────────────────────────────────────

--[[
	Yumurtanın 2B çizimi: UiKit'in yumurtası kabuk renginde, üstüne
	yumurtanın kendi deseni. Açılış ekranı, pet penceresi ve ödül listesi
	aynı çizimi kullanıyor.
]]
function EggStyle.Draw(parent: Instance, size: number, eggId: string?): Frame
	local style = EggStyle.Get(eggId)
	local h = UiKit.Egg(parent, size, style.shell)
	local S = UiKit.Shape
	local a = style.accent

	if eggId == "SupplyEgg" then
		-- Koli bandı ve üstünde uyarı çentikleri
		S(h, 0.5, 0.52, 0.76, 0.13, a, 4, 0.1)
		S(h, 0.5, 0.5, 0.12, 0.84, a:Lerp(Color3.new(0, 0, 0), 0.12), 4, 0.1)
		for k = -1, 1, 2 do
			S(h, 0.5 + k * 0.22, 0.52, 0.05, 0.13, rgb(44, 44, 50), 5, 0, 25)
		end
	elseif eggId == "SkeldEgg" then
		S(h, 0.5, 0.78, 0.66, 0.07, a, 4, 0.5)
		S(h, 0.6, 0.42, 0.44, 0.24, UiKit.VISOR, 4, 0.5)
		S(h, 0.68, 0.38, 0.14, 0.07, Color3.new(1, 1, 1), 5, 0.5).BackgroundTransparency = 0.2
		S(h, 0.5, 0.03, 0.04, 0.12, rgb(118, 130, 140), 1, 0)
		S(h, 0.5, -0.03, 0.09, 0.09, rgb(222, 52, 52), 4, 0.5)
	elseif eggId == "PolusEgg" then
		S(h, 0.5, 0.13, 0.5, 0.2, a, 4, 0.5)
		S(h, 0.36, 0.22, 0.1, 0.12, a, 4, 0.5)
		S(h, 0.62, 0.24, 0.08, 0.1, a, 4, 0.5)
		for _, c in { { 0.2, 0.82, -24 }, { 0.8, 0.82, 24 }, { 0.5, 0.95, 0 } } do
			S(h, c[1], c[2], 0.1, 0.26, style.glow, 4, 0.3, c[3]).BackgroundTransparency = 0.15
		end
	elseif eggId == "VoidEgg" then
		UiKit.Ring(h, 0.5, 0.52, 1.06, 1.02, a, 2, 0)
		S(h, 0.46, 0.4, 0.04, 0.2, a, 4, 0, 24)
		S(h, 0.52, 0.55, 0.04, 0.2, a, 4, 0, -28)
		S(h, 0.47, 0.7, 0.04, 0.14, a, 4, 0, 22)
		S(h, 0.66, 0.3, 0.05, 0.05, Color3.new(1, 1, 1), 5, 0.5)
	end
	return h
end

-- ─── Dünyada yumurta ────────────────────────────────────────────────────────

type Deco = {
	part: BasePart,
	offset: CFrame,
	-- Yörüngede dönenler: açısal hız (derece/sn), yarıçap, faz
	orbit: number?,
	radius: number?,
	phase: number?,
}

type Styled = {
	egg: BasePart,
	base: CFrame,
	style: Style,
	decos: { Deco },
	mesh: SpecialMesh?,
	halo: BasePart?,
	haloSize: Vector3?,
	light: PointLight?,
	blink: BasePart?,
	phase: number,
}

export type Handle = {
	Stop: () -> (),
}

local function decoPart(folder: Instance, name: string, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = folder
	return p
end

local function ellipsoid(folder: Instance, name: string, size: Vector3, color: Color3): Part
	local p = decoPart(folder, name, size, color)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Yumurtanın y yüksekliğindeki yatay yarıçapı (elipsoit)
local function radiusAt(egg: BasePart, y: number): number
	local rx, ry = egg.Size.X / 2, egg.Size.Y / 2
	return rx * math.sqrt(math.max(0, 1 - (y / ry) ^ 2))
end

--[[ Yumurtanın etrafına stiline göre süsleri kurar. ]]
local function dress(s: Styled, folder: Instance, id: string)
	local egg = s.egg
	local style = s.style
	local H = egg.Size.Y / 2

	local function add(part: BasePart, offset: CFrame): Deco
		local d: Deco = { part = part, offset = offset }
		table.insert(s.decos, d)
		return d
	end

	-- Yatay bant: dikey silindir, yumurtanın o yükseklikteki çapından biraz büyük
	local function band(y: number, thick: number, color: Color3, neon: boolean)
		local d = radiusAt(egg, y) * 2 + 0.16
		local p = decoPart(folder, "Band", Vector3.new(thick, d, d), color, Enum.PartType.Cylinder)
		if neon then
			p.Material = Enum.Material.Neon
		end
		add(p, CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)))
	end

	if id == "SupplyEgg" then
		band(0.6, 0.7, style.accent, false)
		band(-0.9, 0.5, style.accent:Lerp(Color3.new(0, 0, 0), 0.15), false)
		-- Bandın üstünde siyah çentikler: koli bandı değil uyarı bandı
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			local r = radiusAt(egg, 0.6) + 0.1
			-- Yerel X dışa bakıyor (yüzeyin normali); çentik teğet düzlemde eğik
			local tick = decoPart(folder, "Tick", Vector3.new(0.2, 0.74, 0.32), rgb(44, 44, 50))
			add(tick, CFrame.new(math.cos(a) * r, 0.6, math.sin(a) * r) * CFrame.Angles(0, -a, 0) * CFrame.Angles(math.rad(25), 0, 0))
		end
	elseif id == "SkeldEgg" then
		local visorY = H * 0.3
		local vr = radiusAt(egg, visorY)
		local visor = ellipsoid(folder, "Visor", Vector3.new(2.6, 1.5, 1.0), UiKit.VISOR)
		visor.Reflectance = 0.25
		add(visor, CFrame.new(0, visorY, -vr + 0.1))
		local shine = ellipsoid(folder, "VisorShine", Vector3.new(0.8, 0.35, 0.3), Color3.new(1, 1, 1))
		add(shine, CFrame.new(0.55, visorY + 0.25, -vr - 0.32))
		band(-H * 0.4, 0.35, style.accent, true)
		local mast = decoPart(folder, "Antenna", Vector3.new(1.1, 0.16, 0.16), rgb(118, 130, 140), Enum.PartType.Cylinder)
		add(mast, CFrame.new(0.35, H + 0.35, 0) * CFrame.Angles(0, 0, math.rad(90)))
		local tip = decoPart(folder, "AntennaTip", Vector3.new(0.45, 0.45, 0.45), rgb(222, 52, 52), Enum.PartType.Ball)
		tip.Material = Enum.Material.Neon
		add(tip, CFrame.new(0.35, H + 0.95, 0))
		s.blink = tip
	elseif id == "PolusEgg" then
		local cap = ellipsoid(folder, "SnowCap", Vector3.new(egg.Size.X * 0.74, 1.4, egg.Size.X * 0.74), style.accent)
		add(cap, CFrame.new(0, H - 0.45, 0))
		for k = 0, 2 do
			local a = k / 3 * math.pi * 2 + 0.4
			local r = radiusAt(egg, H * 0.62)
			local drip = ellipsoid(folder, "SnowDrip", Vector3.new(0.55, 0.95, 0.55), style.accent)
			add(drip, CFrame.new(math.cos(a) * r, H * 0.62, math.sin(a) * r))
		end
		-- Dipte dışa eğik buz kristalleri
		for k = 0, 4 do
			local a = k / 5 * math.pi * 2
			local crystal = decoPart(folder, "IceCrystal", Vector3.new(0.5, 1.8, 0.5), style.glow)
			crystal.Transparency = 0.2
			crystal.Reflectance = 0.2
			add(crystal, CFrame.new(math.cos(a) * 1.25, -H + 0.35, math.sin(a) * 1.25)
				* CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(-28)))
		end
		-- Kar taneleri
		local core = decoPart(folder, "SnowEmitter", Vector3.new(0.2, 0.2, 0.2), style.accent)
		core.Transparency = 1
		local snow = Instance.new("ParticleEmitter")
		snow.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		snow.Color = ColorSequence.new(Color3.new(1, 1, 1), style.glow)
		snow.LightEmission = 0.5
		snow.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		snow.Lifetime = NumberRange.new(1.8, 2.8)
		snow.Rate = 6
		snow.Speed = NumberRange.new(0.4, 0.9)
		snow.SpreadAngle = Vector2.new(180, 180)
		snow.Acceleration = Vector3.new(0, -0.8, 0)
		snow.Parent = core
		add(core, CFrame.new(0, H * 0.4, 0))
	elseif id == "VoidEgg" then
		local slit = ellipsoid(folder, "VoidSlit", Vector3.new(0.9, egg.Size.Y * 0.42, 0.5), style.accent)
		slit.Material = Enum.Material.Neon
		add(slit, CFrame.new(0, 0.2, -radiusAt(egg, 0.2) + 0.12))

		local halo = ellipsoid(folder, "VoidHalo", egg.Size * 1.22, style.accent)
		halo.Material = Enum.Material.Neon
		halo.Transparency = 0.8
		add(halo, CFrame.new())
		s.halo = halo
		s.haloSize = halo.Size

		local light = Instance.new("PointLight")
		light.Color = style.glow
		light.Range = 14
		light.Brightness = 1.5
		light.Parent = halo
		s.light = light

		for k = 0, 2 do
			local orb = decoPart(folder, "VoidOrb", Vector3.new(0.7, 0.7, 0.7), style.glow, Enum.PartType.Ball)
			orb.Material = Enum.Material.Neon
			local d = add(orb, CFrame.new())
			d.orbit = 95
			d.radius = 3.5
			d.phase = k / 3 * 360
		end
	end
end

--[[
	Boşta animasyon: yumurtanın o anki konumu. `t` saniye, `s.phase` her
	yumurtaya kaydırma (aynı anda zıplamasınlar).
]]
local function animate(s: Styled, t: number): CFrame
	local base = s.base
	local tt = t + s.phase
	local kind = s.style.idle

	if kind == "hop" then
		-- Kısa zıplama, inişte basılma ve sönümlü sallanma
		local P = 2.6
		local u = tt % P
		local y = 0.12 * math.sin(tt * 2)
		local tilt = 0
		local squash = 0
		if u < 0.55 then
			y += 1.0 * math.sin(math.pi * u / 0.55)
		elseif u < 1.6 then
			local w = u - 0.55
			tilt = 7 * math.exp(-3 * w) * math.sin(12 * w)
			if w < 0.25 then
				squash = 0.08 * math.sin(math.pi * w / 0.25)
			end
		end
		if s.mesh then
			s.mesh.Scale = Vector3.new(1 + squash, 1 - squash, 1 + squash)
		end
		return base * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(tilt))
	elseif kind == "spin" then
		local y = 0.35 * math.sin(tt * 2 * math.pi / 2.6)
		if s.blink then
			s.blink.Transparency = if tt % 1.2 < 0.25 then 0 else 0.75
		end
		return base * CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(tt * 40), 0)
	elseif kind == "drift" then
		local y = 0.5 * math.sin(tt * 2 * math.pi / 3.6)
		local tilt = 4 * math.sin(tt * 2 * math.pi / 5)
		return base * CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(tt * 12), math.rad(tilt))
	elseif kind == "pulse" then
		local p = 0.5 + 0.5 * math.sin(tt * 2 * math.pi / 1.8)
		if s.halo and s.haloSize then
			s.halo.Transparency = 0.84 - 0.14 * p
			s.halo.Size = s.haloSize * (1 + 0.05 * p)
		end
		if s.light then
			s.light.Brightness = 1 + 2 * p
		end
		local y = 0.6 + 0.3 * math.sin(tt * 2 * math.pi / 2.2)
		return base * CFrame.new(0, y, 0) * CFrame.Angles(0, math.rad(-tt * 22), 0)
	end
	return base
end

--[[
	Kuluçkadaki yumurtaları bulur, süsler ve her karede canlandırır.
	Harita kalıcı model (Persistent) olduğu için yumurtalar girişte hazır;
	yine de bir süre bekleniyor.
]]
function EggStyle.Start(): Handle
	local styled: { Styled } = {}
	local folder = Instance.new("Folder")
	folder.Name = "EggStyleFX"
	folder.Parent = workspace

	local connection: RBXScriptConnection? = nil
	local stopped = false

	task.spawn(function()
		local decor = workspace:FindFirstChild("Decor") or workspace:WaitForChild("Decor", 30)
		local hatchery: Instance? = nil
		for _ = 1, 60 do
			hatchery = decor and decor:FindFirstChild("Hatchery", true)
			if hatchery or stopped then
				break
			end
			task.wait(0.5)
		end
		if not hatchery or stopped then
			return
		end

		for index, def in Config.Eggs do
			local egg = hatchery:FindFirstChild("Egg" .. index)
			if not (egg and egg:IsA("BasePart")) then
				continue
			end
			local style = EggStyle.Get(def.id)
			local s: Styled = {
				egg = egg,
				base = egg.CFrame,
				style = style,
				decos = {},
				mesh = egg:FindFirstChildOfClass("SpecialMesh"),
				phase = index * 0.83,
			}

			-- Kabuk rengi yerelde; sunucu sonradan boyarsa geri al
			local function paint()
				if egg.Color ~= style.shell then
					egg.Color = style.shell
				end
				egg.Reflectance = style.reflect
			end
			paint()
			egg:GetPropertyChangedSignal("Color"):Connect(paint)

			dress(s, folder, def.id)
			table.insert(styled, s)
		end

		local t = 0
		connection = RunService.RenderStepped:Connect(function(dt: number)
			t += dt
			for _, s in styled do
				local cf = animate(s, t)
				s.egg.CFrame = cf
				for _, d in s.decos do
					if d.orbit and d.radius then
						local a = math.rad((d.phase or 0) + t * d.orbit)
						d.part.CFrame = s.base * CFrame.new(0, 0.6, 0) * CFrame.Angles(math.rad(18), 0, 0)
							* CFrame.new(math.cos(a) * d.radius, 0, math.sin(a) * d.radius)
					else
						d.part.CFrame = cf * d.offset
					end
				end
			end
		end)
	end)

	return {
		Stop = function()
			stopped = true
			if connection then
				connection:Disconnect()
			end
			folder:Destroy()
		end,
	}
end

return EggStyle
