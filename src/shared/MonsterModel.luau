--!strict
--[[
	Uzay canavarlarının modelleri (Config.SpaceMonsters) ve iskelet
	animasyonu. Parçalardan kuruluyor: yuvarlak hatlar SpecialMesh küreli
	elipsoidler, dişler/boynuzlar kama, gözler neon.

	İSKELET: Root parçasının altında Attachment'lar = kemikler.
	    Position  eklem noktası (Root'a göre, dinlenme pozu)
	    Parent    üst kemiğin adı ("" = gövde)
	    Axis      dönme ekseni (Root uzayında)
	    Sway      boştaki salınım genliği (radyan), Rate hızı, Phase fazı
	    Grab      kavrarken eklenen açı (kolu kaldırır / dokunacı kıvırır)
	    Roar      kükrerken eklenen açı (çene açılır)
	Her görsel parçanın "Bone" niteliği bağlı olduğu kemik ("" = gövde).
	Dünya konumu: rootCF × T(kemik) × dinlenme; T kemik zinciri boyunca
	eklem etrafındaki dönmelerin çarpımı (ileri kinematik).

	"Hand" adlı görünmez parça kavrama noktası: yakalanan oyuncu (istemcide)
	buna yapıştırılıyor.

	Sunucu bu modeli KULLANMIYOR (yalnızca görünmez bir kök taşıyor);
	istemci her canavar için bir kopya kurup her karede Pose ile çiziyor.
	Yön: ileri -Z, yukarı +Y, ayak tabanı y = 0.
]]

local MonsterModel = {}

type Opts = {
	bone: string?,
	material: Enum.Material?,
	transparency: number?,
	reflect: number?,
}

type Ctx = {
	model: Model,
	root: BasePart,
	S: number,
}

-- ─── Yapı yardımcıları ──────────────────────────────────────────────────────

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function scaled(ctx: Ctx, cf: CFrame): CFrame
	return CFrame.new(cf.Position * ctx.S) * cf.Rotation
end

local function finish(ctx: Ctx, p: BasePart, name: string, color: Color3, opts: Opts?)
	p.Name = name
	p.Color = color
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = if opts and opts.material then opts.material else Enum.Material.SmoothPlastic
	if opts and opts.transparency then
		p.Transparency = opts.transparency
	end
	if opts and opts.reflect then
		p.Reflectance = opts.reflect
	end
	p:SetAttribute("Bone", if opts and opts.bone then opts.bone else "")
	p.Parent = ctx.model
end

--[[ Elipsoit: blok + küre mesh (boyut = elipsoidin kutusu). ]]
local function blob(ctx: Ctx, name: string, size: Vector3, cf: CFrame, color: Color3, opts: Opts?): BasePart
	local p = Instance.new("Part")
	p.Size = size * ctx.S
	p.CFrame = scaled(ctx, cf)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	finish(ctx, p, name, color, opts)
	return p
end

local function ball(ctx: Ctx, name: string, d: number, pos: Vector3, color: Color3, opts: Opts?): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * d * ctx.S
	p.CFrame = CFrame.new(pos * ctx.S)
	finish(ctx, p, name, color, opts)
	return p
end

local function box(ctx: Ctx, name: string, size: Vector3, cf: CFrame, color: Color3, opts: Opts?): BasePart
	local p = Instance.new("Part")
	p.Size = size * ctx.S
	p.CFrame = scaled(ctx, cf)
	finish(ctx, p, name, color, opts)
	return p
end

--[[ Kama: ince ucu +Y yönünde (WedgePart'ın eğimi -Z'den +Y'ye). ]]
local function wedge(ctx: Ctx, name: string, size: Vector3, cf: CFrame, color: Color3, opts: Opts?): BasePart
	local p = Instance.new("WedgePart")
	p.Size = size * ctx.S
	p.CFrame = scaled(ctx, cf)
	finish(ctx, p, name, color, opts)
	return p
end

--[[ a'dan b'ye uzanan parça: X ekseni a→b. ]]
local function along(a: Vector3, b: Vector3): CFrame
	local mid = (a + b) / 2
	local dir = b - a
	if dir.Magnitude < 1e-4 then
		return CFrame.new(mid)
	end
	local up = if math.abs(dir.Unit.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis
	return CFrame.lookAt(mid, b, up) * CFrame.Angles(0, math.rad(90), 0)
end

--[[ a→b arası silindir (çap d). ]]
local function rod(ctx: Ctx, name: string, a: Vector3, b: Vector3, d: number, color: Color3, opts: Opts?): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new((b - a).Magnitude, d, d) * ctx.S
	p.CFrame = scaled(ctx, along(a, b))
	finish(ctx, p, name, color, opts)
	return p
end

--[[ a→b arası uzun elipsoit (kas/boğum); uçlar biraz taşar. ]]
local function capsule(ctx: Ctx, name: string, a: Vector3, b: Vector3, d: number, color: Color3, opts: Opts?): BasePart
	local len = (b - a).Magnitude + d * 0.7
	return blob(ctx, name, Vector3.new(len, d, d), along(a, b), color, opts)
end

--[[ Disk: normal yönü `normal`, çap d, kalınlık t. ]]
local function disk(ctx: Ctx, name: string, center: Vector3, normal: Vector3, d: number, t: number, color: Color3, opts: Opts?): BasePart
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(t, d, d) * ctx.S
	p.CFrame = scaled(ctx, along(center - normal.Unit * t / 2, center + normal.Unit * t / 2))
	finish(ctx, p, name, color, opts)
	return p
end

type BoneSpec = {
	parent: string?,
	axis: Vector3?,
	sway: number?,
	rate: number?,
	phase: number?,
	grab: number?,
	roar: number?,
}

local function bone(ctx: Ctx, name: string, joint: Vector3, spec: BoneSpec)
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = joint * ctx.S
	a:SetAttribute("Parent", spec.parent or "")
	a:SetAttribute("Axis", (spec.axis or Vector3.xAxis).Unit)
	a:SetAttribute("Sway", spec.sway or 0)
	a:SetAttribute("Rate", spec.rate or 1)
	a:SetAttribute("Phase", spec.phase or 0)
	a:SetAttribute("Grab", spec.grab or 0)
	a:SetAttribute("Roar", spec.roar or 0)
	a.Parent = ctx.root
end

local function hand(ctx: Ctx, pos: Vector3, boneName: string)
	local p = box(ctx, "Hand", Vector3.one, CFrame.new(pos), Color3.new(1, 1, 1), { bone = boneName, transparency = 1 })
	p.Size = Vector3.one
end

--[[ Göz: beyaz küre + renkli iris + bebek + parıltı. dir = bakış yönü. ]]
local function eye(ctx: Ctx, pos: Vector3, d: number, iris: Color3, dir: Vector3, boneName: string?, pupil: Color3?)
	local o = { bone = boneName }
	ball(ctx, "Eye", d, pos, rgb(250, 250, 245), o)
	local ip = pos + dir.Unit * d * 0.36
	ball(ctx, "Iris", d * 0.58, ip, iris, { bone = boneName, material = Enum.Material.Neon })
	ball(ctx, "Pupil", d * 0.3, pos + dir.Unit * d * 0.47, pupil or rgb(16, 12, 24), o)
	ball(ctx, "Glint", d * 0.13, pos + dir.Unit * d * 0.5 + Vector3.new(d * 0.12, d * 0.14, 0), Color3.new(1, 1, 1), { bone = boneName, material = Enum.Material.Neon })
end

--[[ Küre yüzeyine yassı benek (yüzeye yatık). ]]
local function spot(ctx: Ctx, center: Vector3, radii: Vector3, dir: Vector3, d: number, color: Color3, opts: Opts?)
	local u = dir.Unit
	local p = center + Vector3.new(u.X * radii.X, u.Y * radii.Y, u.Z * radii.Z) * 0.97
	blob(ctx, "Spot", Vector3.new(d, d, d * 0.22), CFrame.lookAt(p, p + u), color, opts)
end

local function newCtx(name: string, scale: number): Ctx
	local model = Instance.new("Model")
	model.Name = name
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root
	return { model = model, root = root, S = scale }
end

local function sparkles(ctx: Ctx, pos: Vector3, color: Color3, rate: number)
	local a = Instance.new("Attachment")
	a.Name = "FX"
	a.Position = pos * ctx.S
	a.Parent = ctx.root
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 * ctx.S), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0.2, 1)
	e.Lifetime = NumberRange.new(1.2, 2.2)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = rate
	e.Parent = a
end

local function light(ctx: Ctx, pos: Vector3, color: Color3, range: number, brightness: number)
	local a = Instance.new("Attachment")
	a.Name = "Light"
	a.Position = pos * ctx.S
	a.Parent = ctx.root
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range * ctx.S
	l.Brightness = brightness
	l.Parent = a
end

-- ─── 1. Glorp: tek gözlü yeşil balçık ───────────────────────────────────────

local function glorp(ctx: Ctx)
	local body = rgb(118, 226, 72)
	local dark = rgb(70, 160, 52)
	local belly = rgb(196, 255, 150)
	local glow = rgb(170, 255, 90)

	bone(ctx, "Body", Vector3.new(0, 0, 0), { axis = Vector3.xAxis, sway = 0.035, rate = 1.6 })
	local B = { bone = "Body" }

	-- Taban birikintisi ve damlalar
	blob(ctx, "Puddle", Vector3.new(14, 1.4, 13), CFrame.new(0, 0.55, 0.3), dark)
	for i = 1, 7 do
		local a = math.rad(i * 51 + 10)
		ball(ctx, "Drip", 1.4 + (i % 3) * 0.5, Vector3.new(math.sin(a) * 6.4, 0.6, math.cos(a) * 6), dark)
	end
	-- Gövde
	local C = Vector3.new(0, 5.6, 0)
	local R = Vector3.new(5.6, 5.2, 5.2)
	blob(ctx, "Body", R * 2, CFrame.new(C), body, { bone = "Body", reflect = 0.05 })
	blob(ctx, "Belly", Vector3.new(8, 6.5, 2.6), CFrame.new(0, 4.3, -3.9), belly, B)
	for _, d in { Vector3.new(0.8, 0.6, 0.4), Vector3.new(-0.9, 0.3, 0.5), Vector3.new(0.6, -0.2, 0.9), Vector3.new(-0.5, 0.8, 0.6), Vector3.new(0.95, 0.1, -0.1), Vector3.new(-0.95, -0.1, -0.2) } do
		spot(ctx, C, R, d, 1.6, dark, B)
	end
	-- Parlak iç damlacıklar
	for _, d in { Vector3.new(0.5, 0.7, -0.4), Vector3.new(-0.6, 0.5, -0.5) } do
		spot(ctx, C, R, d, 0.9, glow, { bone = "Body", material = Enum.Material.Neon })
	end

	-- Dev tek göz + göz kapağı
	eye(ctx, Vector3.new(0, 7.3, -4.1), 4.8, rgb(255, 190, 40), Vector3.new(0, 0, -1), "Body")
	blob(ctx, "Lid", Vector3.new(5.4, 1.4, 3.2), CFrame.new(0, 9.5, -3.7) * CFrame.Angles(math.rad(-18), 0, 0), dark, B)

	-- Ağız, dil, iki diş
	bone(ctx, "Jaw", Vector3.new(0, 4.2, -2.5), { parent = "Body", axis = Vector3.xAxis, sway = 0.05, rate = 2.2, roar = -0.45 })
	blob(ctx, "Mouth", Vector3.new(5.6, 1.8, 1.2), CFrame.new(0, 3.5, -4.85), rgb(70, 16, 40), { bone = "Jaw" })
	blob(ctx, "Tongue", Vector3.new(2.4, 0.8, 1), CFrame.new(0, 3.1, -5.1), rgb(255, 110, 150), { bone = "Jaw" })
	for _, x in { -1.2, 1.2 } do
		wedge(ctx, "Tooth", Vector3.new(0.7, 0.9, 0.5), CFrame.new(x, 4.05, -5.25) * CFrame.Angles(0, 0, math.rad(180)), rgb(250, 250, 235), B)
	end

	-- Antenler: üç boğumlu zincir + parlak uç
	for side, x in { -1, 1 } do
		local base = Vector3.new(x * 2.2, 10.2, 0.2)
		local pts = { base, base + Vector3.new(x * 0.7, 1.8, 0.3), base + Vector3.new(x * 1.6, 3.4, 0.2), base + Vector3.new(x * 2.6, 4.6, -0.3) }
		local parent = "Body"
		for k = 1, 3 do
			local name = "Ant" .. side .. "_" .. k
			bone(ctx, name, pts[k], { parent = parent, axis = Vector3.zAxis, sway = 0.12 + k * 0.03, rate = 2.4, phase = side * 1.3 + k * 0.5 })
			rod(ctx, "Antenna", pts[k], pts[k + 1], 0.55 - k * 0.08, dark, { bone = name })
			parent = name
		end
		ball(ctx, "AntennaTip", 1.3, pts[4], glow, { bone = parent, material = Enum.Material.Neon })
	end

	-- Kısa kollar; sağ kol kavrıyor (öne kalkar)
	for side, x in { -1, 1 } do
		local name = if x > 0 then "ArmR" else "ArmL"
		local shoulder = Vector3.new(x * 5.2, 6.6, -0.6)
		bone(ctx, name, shoulder, { parent = "Body", axis = Vector3.xAxis, sway = 0.12, rate = 1.8, phase = side, grab = if x > 0 then 1.45 else 0.5, roar = 0.6 })
		local tip = shoulder + Vector3.new(x * 1.2, -3.8, -0.4)
		capsule(ctx, "Arm", shoulder, tip, 2.3, body, { bone = name })
		for f = -1, 1 do
			ball(ctx, "Finger", 0.9, tip + Vector3.new(x * 0.3 + f * 0.55, -0.9, -0.3), body, { bone = name })
		end
		if x > 0 then
			hand(ctx, tip + Vector3.new(0, -1.4, -1.2), name)
		end
	end

	sparkles(ctx, Vector3.new(0, 6, 0), glow, 6)
	light(ctx, Vector3.new(0, 8, -6), glow, 16, 0.8)
end

-- ─── 2. Chomper: pembe dişli, üç gözlü, boynuzlu ────────────────────────────

local function chomper(ctx: Ctx)
	local skin = rgb(236, 88, 150)
	local light2 = rgb(255, 168, 204)
	local dark = rgb(170, 48, 110)
	local horn = rgb(255, 176, 62)
	local tooth = rgb(252, 250, 238)

	bone(ctx, "Body", Vector3.new(0, 1, 0), { axis = Vector3.xAxis, sway = 0.04, rate = 1.4 })
	local B = { bone = "Body" }

	-- Bacaklar ve tırnaklar
	for side, x in { -1, 1 } do
		local name = "Leg" .. side
		bone(ctx, name, Vector3.new(x * 3.2, 3.6, 0.6), { parent = "Body", axis = Vector3.xAxis, sway = 0.06, rate = 1.4, phase = side * 1.5 })
		blob(ctx, "Leg", Vector3.new(3.4, 4.2, 3.6), CFrame.new(x * 3.3, 2, 0.6), dark, { bone = name })
		for t = -1, 1 do
			ball(ctx, "Toe", 1, Vector3.new(x * 3.3 + t * 1, 0.45, -1.1), tooth, { bone = name })
		end
	end

	-- Gövde
	local C = Vector3.new(0, 7, 0)
	local R = Vector3.new(6.2, 5.6, 5.6)
	blob(ctx, "Body", R * 2, CFrame.new(C), skin, B)
	blob(ctx, "Belly", Vector3.new(8.6, 5, 2.6), CFrame.new(0, 3.9, -4.3), light2, B)
	for _, d in { Vector3.new(0.7, 0.7, 0.3), Vector3.new(-0.8, 0.5, 0.4), Vector3.new(0.3, 0.9, 0.6), Vector3.new(-0.4, 0.3, 0.9), Vector3.new(0.9, -0.1, 0.5), Vector3.new(-0.9, 0.2, -0.3), Vector3.new(0.6, 0.2, 0.8) } do
		spot(ctx, C, R, d, 1.9, light2, B)
	end

	-- Kocaman ağız: karanlık iç, üst dişler gövdede, alt çene kemikte
	blob(ctx, "Maw", Vector3.new(9.4, 4.8, 2.2), CFrame.new(0, 6, -4.7), rgb(96, 8, 36), B)
	blob(ctx, "Tongue", Vector3.new(4.2, 1.4, 2.4), CFrame.new(0, 4.6, -4.8), rgb(255, 96, 130), B)
	for i = -3, 3 do
		local z = -5.5 + math.abs(i) * 0.25
		wedge(ctx, "Fang", Vector3.new(1.05, 1.9 - math.abs(i) * 0.15, 0.8), CFrame.new(i * 1.25, 7.6 - math.abs(i) * 0.12, z) * CFrame.Angles(0, 0, math.rad(180)), tooth, B)
	end
	bone(ctx, "Jaw", Vector3.new(0, 4.8, -1.2), { parent = "Body", axis = Vector3.xAxis, sway = 0.07, rate = 2.4, roar = -0.5 })
	blob(ctx, "Jaw", Vector3.new(9, 2.6, 4.4), CFrame.new(0, 3.9, -3.4), skin, { bone = "Jaw" })
	for i = -2, 2 do
		local z = -5.35 + math.abs(i) * 0.25
		wedge(ctx, "LowFang", Vector3.new(0.95, 1.3, 0.7), CFrame.new(i * 1.35, 5.05, z), tooth, { bone = "Jaw" })
	end

	-- Üç göz sapı
	for i, spec in { { -3.2, 11.4, -1.6, 2.2 }, { 0, 12.8, -2.4, 2.8 }, { 3.2, 11.4, -1.6, 2.2 } } do
		local base = Vector3.new(spec[1] * 0.8, 10.8, spec[3] + 0.8)
		local top = Vector3.new(spec[1], spec[2], spec[3])
		local name = "Stalk" .. i
		bone(ctx, name, base, { parent = "Body", axis = Vector3.zAxis, sway = 0.1, rate = 2, phase = i * 1.1, roar = (i - 2) * 0.25 })
		rod(ctx, "Stalk", base, top, 0.9, dark, { bone = name })
		eye(ctx, top + Vector3.new(0, spec[4] * 0.35, 0), spec[4], rgb(255, 214, 40), Vector3.new(0, -0.15, -1), name, rgb(200, 20, 30))
	end

	-- Kıvrık boynuzlar (üç kademe)
	for side, x in { -1, 1 } do
		local pts = { Vector3.new(x * 4.2, 10.4, 0.6), Vector3.new(x * 6.2, 12.2, 0.9), Vector3.new(x * 7.2, 14.4, 0.4), Vector3.new(x * 6.8, 16.2, -0.6) }
		for k = 1, 3 do
			capsule(ctx, "Horn", pts[k], pts[k + 1], 1.9 - k * 0.45, if k == 3 then rgb(255, 230, 150) else horn, B)
		end
		local _ = side
	end

	-- Kollar ve pençeler; sağ kol kavrıyor
	for side, x in { -1, 1 } do
		local name = if x > 0 then "ArmR" else "ArmL"
		local shoulder = Vector3.new(x * 5.9, 7.6, -0.4)
		bone(ctx, name, shoulder, { parent = "Body", axis = Vector3.xAxis, sway = 0.1, rate = 1.6, phase = side * 2, grab = if x > 0 then 1.35 else 0.4, roar = 0.8 })
		local elbow = shoulder + Vector3.new(x * 1.6, -2.4, -0.3)
		local wrist = elbow + Vector3.new(x * 0.2, -2.6, -0.8)
		capsule(ctx, "UpperArm", shoulder, elbow, 2.4, skin, { bone = name })
		capsule(ctx, "Forearm", elbow, wrist, 2.2, skin, { bone = name })
		for f = -1, 1 do
			wedge(ctx, "Claw", Vector3.new(0.5, 1.4, 0.6), CFrame.new(wrist + Vector3.new(f * 0.7, -1, -0.4)) * CFrame.Angles(math.rad(180), 0, 0), tooth, { bone = name })
		end
		if x > 0 then
			hand(ctx, wrist + Vector3.new(0, -1.8, -1.2), name)
		end
	end

	-- Kısa kuyruk
	local parent = "Body"
	local pts = { Vector3.new(0, 4, 4.8), Vector3.new(0, 3.2, 7), Vector3.new(0, 3.4, 9), Vector3.new(0, 4.6, 10.4) }
	for k = 1, 3 do
		local name = "Tail" .. k
		bone(ctx, name, pts[k], { parent = parent, axis = Vector3.yAxis, sway = 0.25, rate = 2.2, phase = k * 0.6 })
		capsule(ctx, "Tail", pts[k], pts[k + 1], 2 - k * 0.45, dark, { bone = name })
		parent = name
	end

	sparkles(ctx, Vector3.new(0, 7, 0), rgb(255, 150, 210), 5)
	light(ctx, Vector3.new(0, 7, -7), rgb(255, 120, 190), 18, 0.8)
end

-- ─── 3. Nebula Kraken: mor ahtapot, sekiz dokunaç ───────────────────────────

local function kraken(ctx: Ctx)
	local skin = rgb(142, 70, 214)
	local dark = rgb(92, 40, 150)
	local pale = rgb(214, 170, 255)
	local glow = rgb(90, 236, 255)

	bone(ctx, "Body", Vector3.new(0, 3, 0), { axis = Vector3.xAxis, sway = 0.05, rate = 1.1 })
	local B = { bone = "Body" }

	-- Kafa (göz hizası) ve arkaya yatık manto
	local head = Vector3.new(0, 6.8, -0.6)
	blob(ctx, "Head", Vector3.new(11.5, 8.4, 10.5), CFrame.new(head), skin, B)
	local mantle = Vector3.new(0, 13, 2.6)
	blob(ctx, "Mantle", Vector3.new(10.4, 14, 11), CFrame.new(mantle) * CFrame.Angles(math.rad(22), 0, 0), skin, B)
	-- Mantodaki nebula benekleri
	local mr = Vector3.new(5.2, 7, 5.5)
	for i = 1, 14 do
		local a = i * 2.39
		local y = math.cos(i * 1.7) * 0.8
		local d = Vector3.new(math.cos(a), y, math.sin(a))
		if d.Z > -0.2 or y > 0.3 then
			spot(ctx, mantle, mr, d, 0.9 + (i % 3) * 0.35, if i % 4 == 0 then glow else pale,
				{ bone = "Body", material = if i % 4 == 0 then Enum.Material.Neon else Enum.Material.SmoothPlastic })
		end
	end
	-- Sifon ve kaş çıkıntıları
	for _, x in { -1, 1 } do
		blob(ctx, "Brow", Vector3.new(4.4, 1.3, 2.4), CFrame.new(x * 2.9, 9.8, -4.4) * CFrame.Angles(0, 0, math.rad(x * -16)), dark, B)
	end
	-- Büyük gözler (yatay yarık bebek)
	for _, x in { -1, 1 } do
		local p = Vector3.new(x * 3, 7.8, -5.2)
		blob(ctx, "Eye", Vector3.new(3.8, 3.2, 1.8), CFrame.new(p), rgb(250, 250, 245), B)
		blob(ctx, "Iris", Vector3.new(2.5, 2.2, 1), CFrame.new(p + Vector3.new(0, 0, -0.55)), glow, { bone = "Body", material = Enum.Material.Neon })
		box(ctx, "Pupil", Vector3.new(1.7, 0.45, 0.3), CFrame.new(p + Vector3.new(0, 0, -1)), rgb(14, 10, 26), B)
	end
	-- Ağız gagası
	bone(ctx, "Jaw", Vector3.new(0, 4.6, -3.8), { parent = "Body", axis = Vector3.xAxis, sway = 0.05, rate = 2, roar = -0.4 })
	wedge(ctx, "Beak", Vector3.new(2.2, 1.6, 1.4), CFrame.new(0, 3.9, -5.2) * CFrame.Angles(math.rad(180), 0, 0), rgb(40, 30, 50), { bone = "Jaw" })

	-- Sekiz dokunaç: altı boğum, ucu yukarı kıvrık. 2 numara (öne sağ) kavrıyor.
	for i = 1, 8 do
		local ang = math.rad((i - 1) * 45 + 22.5)
		local out = Vector3.new(math.sin(ang), 0, -math.cos(ang))
		local side = out:Cross(Vector3.yAxis).Unit
		local grabber = i == 2
		local pts = {}
		local r0 = 3.4
		for k = 0, 6 do
			local t = k / 6
			local reach = r0 + t * 13
			local y = 3.2 - math.sin(t * math.pi * 0.8) * 2.4 + t ^ 3 * 3
			table.insert(pts, out * reach + Vector3.new(0, y, 0))
		end
		local parent = "Body"
		for k = 1, 6 do
			local name = string.format("T%d_%d", i, k)
			bone(ctx, name, pts[k], {
				parent = parent, axis = side, sway = 0.07 + k * 0.025, rate = 1.5, phase = i * 0.8 - k * 0.55,
				grab = if grabber then (if k <= 2 then 0.3 else 0.2) else 0,
				roar = if grabber then 0 else 0.1,
			})
			local d = 2.3 - k * 0.27
			capsule(ctx, "Tentacle", pts[k], pts[k + 1], d, if k % 2 == 0 then skin else dark, { bone = name })
			if k <= 4 then
				ball(ctx, "Sucker", d * 0.42, (pts[k] + pts[k + 1]) / 2 - Vector3.new(0, d * 0.42, 0), pale, { bone = name })
			end
			parent = name
		end
		ball(ctx, "TipGlow", 0.9, pts[7], glow, { bone = parent, material = Enum.Material.Neon })
		if grabber then
			hand(ctx, pts[7] + Vector3.new(0, 0.8, 0), parent)
		end
	end

	sparkles(ctx, Vector3.new(0, 12, 2), glow, 7)
	light(ctx, Vector3.new(0, 8, -7), glow, 22, 1)
end

-- ─── 4. Sand Maw: yerden yükselen kum solucanı, mavi parlayan ağız ─────────

local function sandMaw(ctx: Ctx)
	local sand = rgb(216, 172, 112)
	local band = rgb(158, 110, 66)
	local shell = rgb(186, 140, 88)
	local maw = rgb(80, 200, 255)

	-- Yuva tümseği ve kayalar (kemiksiz)
	blob(ctx, "Mound", Vector3.new(15, 3.4, 15), CFrame.new(0, 0.9, 1.5), band)
	for i = 1, 8 do
		local a = math.rad(i * 45 + 12)
		local s = 1.4 + (i % 3) * 0.6
		box(ctx, "Rubble", Vector3.new(s, s * 0.7, s * 1.2), CFrame.new(math.sin(a) * 7.6, 0.5, 1.5 + math.cos(a) * 7.6) * CFrame.Angles(i, i * 2, 0), band)
	end

	-- Omurga: S kıvrımı, 10 boğum
	local pts = {}
	for k = 0, 10 do
		local t = k / 10
		table.insert(pts, Vector3.new(math.sin(t * 5) * 1.2, 0.6 + t * 22, 2 + math.sin(t * 4.2) * 3.4 - t * 5.5))
	end
	local parent = ""
	for k = 1, 10 do
		local name = "Seg" .. k
		bone(ctx, name, pts[k], { parent = parent, axis = Vector3.xAxis, sway = 0.035 + k * 0.004, rate = 1.1, phase = -k * 0.45, roar = if k >= 7 then -0.06 else 0 })
		local d = 7.6 - k * 0.18
		rod(ctx, "Body", pts[k], pts[k + 1], d, if k % 2 == 0 then sand else shell, { bone = name })
		disk(ctx, "Ring", pts[k + 1], pts[k + 1] - pts[k], d + 0.5, 0.8, band, { bone = name })
		-- Sırt plakası
		local mid = (pts[k] + pts[k + 1]) / 2
		local dir = (pts[k + 1] - pts[k]).Unit
		local back = Vector3.zAxis - dir * dir.Z
		if back.Magnitude > 0.1 then
			back = back.Unit
			wedge(ctx, "Plate", Vector3.new(d * 0.6, 1.6, 2.2), CFrame.lookAt(mid + back * d * 0.45, mid + back * d * 0.45 + dir) * CFrame.Angles(math.rad(-90), 0, 0), band, { bone = name })
		end
		parent = name
	end

	-- Kafa: öne ve biraz aşağı bakan kalın silindir, ön yüzünde halka ağız
	local neck = pts[11]
	local headDir = Vector3.new(0, -0.35, -1).Unit
	local face = neck + headDir * 5
	bone(ctx, "Head", neck, { parent = parent, axis = Vector3.xAxis, sway = 0.05, rate = 1.3, roar = -0.18, grab = -0.15 })
	local H = { bone = "Head" }
	rod(ctx, "Head", neck, face, 9.2, shell, H)
	disk(ctx, "Lip", face, headDir, 9.8, 0.9, band, H)
	disk(ctx, "Throat", face + headDir * 0.2, headDir, 7.6, 0.6, rgb(26, 16, 20), H)
	disk(ctx, "MawGlow", face + headDir * 0.35, headDir, 5.4, 0.3, maw, { bone = "Head", material = Enum.Material.Neon })
	disk(ctx, "MawCore", face + headDir * 0.45, headDir, 2.8, 0.3, rgb(220, 250, 255), { bone = "Head", material = Enum.Material.Neon })
	-- Halka dişler: içe dönük
	local right = headDir:Cross(Vector3.yAxis).Unit
	local up = right:Cross(headDir).Unit
	for i = 1, 14 do
		local a = i / 14 * math.pi * 2
		local radial = right * math.cos(a) + up * math.sin(a)
		local p = face + headDir * 0.5 + radial * 3.3
		wedge(ctx, "Tooth", Vector3.new(0.5, 1.5, 0.6), CFrame.lookAt(p, p + headDir, -radial) * CFrame.Angles(0, 0, 0), rgb(250, 244, 226), H)
	end
	-- Açılan dört yaprak çene
	for i = 1, 4 do
		local a = (i - 0.5) / 4 * math.pi * 2
		local radial = right * math.cos(a) + up * math.sin(a)
		local hinge = face + radial * 4.4
		local name = "Petal" .. i
		bone(ctx, name, hinge, { parent = "Head", axis = radial:Cross(headDir).Unit, sway = 0.05, rate = 2, phase = i, roar = 0.55 })
		local tip = hinge + headDir * 3.2 - radial * 0.8
		capsule(ctx, "Petal", hinge, tip, 1.5, shell, { bone = name })
	end
	-- İki duyarga (kavrayıcı): kafanın yanından sarkan dört boğum
	for side, x in { -1, 1 } do
		local base = neck + right * x * 4.4 + headDir * 2 - up * 1.2
		local fpts = { base }
		for k = 1, 4 do
			table.insert(fpts, base + right * x * (k * 0.6) + Vector3.new(0, -k * 2.1, -k * 0.7))
		end
		local p = "Head"
		for k = 1, 4 do
			local name = "Feeler" .. side .. "_" .. k
			bone(ctx, name, fpts[k], { parent = p, axis = Vector3.xAxis, sway = 0.12, rate = 1.9, phase = side + k * 0.5,
				grab = if x > 0 then 0.42 else 0.1 })
			capsule(ctx, "Feeler", fpts[k], fpts[k + 1], 1.3 - k * 0.18, band, { bone = name })
			p = name
		end
		ball(ctx, "FeelerTip", 0.8, fpts[5], maw, { bone = p, material = Enum.Material.Neon })
		if x > 0 then
			hand(ctx, fpts[5] + Vector3.new(0, -0.6, -0.8), p)
		end
	end

	sparkles(ctx, Vector3.new(0, 1, 2), rgb(255, 220, 160), 5)
	light(ctx, face + headDir * 3, maw, 26, 2)
end

-- ─── 5. Rift Stalker: kemik örümcek, turkuaz kabarcıklar ────────────────────

local function riftStalker(ctx: Ctx)
	local boneC = rgb(196, 186, 172)
	local dark = rgb(112, 102, 98)
	local glow = rgb(80, 255, 214)

	bone(ctx, "Body", Vector3.new(0, 9, 2), { axis = Vector3.xAxis, sway = 0.04, rate = 1.2 })
	local B = { bone = "Body" }

	-- Göğüs, karın, kafa
	blob(ctx, "Thorax", Vector3.new(6.4, 5.2, 8.4), CFrame.new(0, 9.2, 0), boneC, B)
	local AB = Vector3.new(0, 11, 7.4)
	local ABR = Vector3.new(4.8, 4.2, 6)
	blob(ctx, "Abdomen", ABR * 2, CFrame.new(AB) * CFrame.Angles(math.rad(-12), 0, 0), dark, B)
	-- Karındaki parlayan kabarcıklar
	for i = 1, 18 do
		local a = i * 2.4
		local d = Vector3.new(math.cos(a) * 0.9, 0.35 + (i % 5) * 0.14, math.sin(a) * 0.9)
		spot(ctx, AB, ABR, d, 0.8 + (i % 3) * 0.35, glow, { bone = "Body", material = Enum.Material.Neon })
	end
	-- Sırt dikenleri
	for i = 1, 6 do
		local z = -2.4 + i * 2
		local y = if z < 3 then 11.8 else 14.4 - (z - 7) ^ 2 * 0.04
		wedge(ctx, "Spike", Vector3.new(0.7, 2.6 - math.abs(i - 3.5) * 0.25, 1.6), CFrame.new(0, y, z) * CFrame.Angles(math.rad(-15), 0, 0), boneC, B)
	end
	-- Kafa ve göz kümesi
	local head = Vector3.new(0, 9.6, -5.6)
	blob(ctx, "Head", Vector3.new(4.8, 4, 5.2), CFrame.new(head), boneC, B)
	for i, e in { { -1, 10.6, 0.7 }, { 1, 10.6, 0.7 }, { -1.7, 9.8, 0.5 }, { 1.7, 9.8, 0.5 }, { -0.6, 11.4, 0.45 }, { 0.6, 11.4, 0.45 } } do
		ball(ctx, "Eye", e[3], Vector3.new(e[1], e[2], -7.9 + math.abs(e[1]) * 0.3), glow, { bone = "Body", material = Enum.Material.Neon })
		local _ = i
	end
	-- Çeneler (mandibula)
	for side, x in { -1, 1 } do
		local name = "Mandible" .. side
		bone(ctx, name, Vector3.new(x * 1.2, 8.4, -7.4), { parent = "Body", axis = Vector3.yAxis, sway = 0.08, rate = 3, phase = side, roar = x * 0.5 })
		wedge(ctx, "Mandible", Vector3.new(0.6, 2.2, 0.9), CFrame.new(x * 1.3, 7.6, -8.2) * CFrame.Angles(math.rad(160), 0, math.rad(x * 12)), boneC, { bone = name })
	end

	-- Altı bacak: üst (yukarı-dışarı), diz yumrusu, alt (aşağı ayağa)
	for side, x in { -1, 1 } do
		for i, z in { -2.6, 1, 4.6 } do
			local hip = Vector3.new(x * 2.8, 9.4, z)
			local knee = Vector3.new(x * 9, 15.2, z + (i - 2) * 1.6)
			local foot = Vector3.new(x * 12.6, 0.2, z + (i - 2) * 3.4)
			local name = string.format("Leg%d_%d", side, i)
			bone(ctx, name, hip, { parent = "Body", axis = Vector3.zAxis, sway = 0.03, rate = 1.8, phase = side * 2 + i })
			rod(ctx, "Femur", hip, knee, 0.95, boneC, { bone = name })
			ball(ctx, "Knee", 1.5, knee, dark, { bone = name })
			rod(ctx, "Tibia", knee, foot, 0.7, boneC, { bone = name })
			wedge(ctx, "Foot", Vector3.new(0.6, 1.4, 0.8), CFrame.new(foot + Vector3.new(0, 0.5, 0)) * CFrame.Angles(math.rad(180), 0, 0), dark, { bone = name })
		end
	end

	-- Tırpan kollar; sağ kol kavrıyor
	for side, x in { -1, 1 } do
		local name = if x > 0 then "ArmR" else "ArmL"
		local shoulder = Vector3.new(x * 2.4, 10.2, -3.6)
		local elbow = Vector3.new(x * 4.2, 15.6, -7.4)
		local tip = Vector3.new(x * 4.6, 8.4, -12.2)
		bone(ctx, name, shoulder, { parent = "Body", axis = Vector3.xAxis, sway = 0.07, rate = 1.5, phase = side * 1.7, grab = if x > 0 then 0.5 else 0.15, roar = 0.35 })
		rod(ctx, "UpperArm", shoulder, elbow, 1.1, boneC, { bone = name })
		ball(ctx, "Elbow", 1.7, elbow, dark, { bone = name })
		local mid = (elbow + tip) / 2
		local dir = (tip - elbow).Unit
		wedge(ctx, "Scythe", Vector3.new(0.4, 1.8, (tip - elbow).Magnitude + 1), CFrame.lookAt(mid, mid + dir) * CFrame.Angles(0, 0, math.rad(x * 90)), rgb(230, 222, 206), { bone = name })
		if x > 0 then
			hand(ctx, tip + Vector3.new(0, 0.6, 0.4), name)
		end
	end

	sparkles(ctx, AB, glow, 6)
	light(ctx, Vector3.new(0, 10, -9), glow, 22, 1.2)
end

-- ─── 6. Void Leviathan: kıvrılmış biyomekanik yılan, mor halka ─────────────

local function voidLeviathan(ctx: Ctx)
	local hull = rgb(48, 40, 70)
	local plate = rgb(76, 66, 104)
	local glow = rgb(206, 90, 255)
	local eyeC = rgb(255, 70, 170)

	-- Kıvrım: kuyruk ucundan boyuna
	local pts = {
		Vector3.new(-7, 1.4, 9.5), Vector3.new(-9, 1.8, 4.5), Vector3.new(-7.6, 2.2, -0.8), Vector3.new(-2, 2.6, -3.4),
		Vector3.new(4.6, 3, -1.6), Vector3.new(7.8, 3.6, 3.2), Vector3.new(5.4, 4.6, 8), Vector3.new(0, 6.4, 9),
		Vector3.new(-3.8, 9.4, 6.2), Vector3.new(-3.4, 13, 2.2), Vector3.new(-1.2, 16, -1.2), Vector3.new(0, 18, -4.6),
		Vector3.new(0, 19, -8),
	}
	local parent = ""
	local n = #pts - 1
	for k = 1, n do
		local name = "Coil" .. k
		local upper = k >= 8
		bone(ctx, name, pts[k], {
			parent = parent, axis = if upper then Vector3.xAxis else Vector3.yAxis,
			sway = if upper then 0.045 else 0.02, rate = 1, phase = -k * 0.5,
			roar = if k >= 10 then -0.05 else 0,
		})
		local t = k / n
		local d = 2.4 + math.sin(math.min(1, t * 1.25) * math.pi * 0.6) * 4
		capsule(ctx, "Body", pts[k], pts[k + 1], d, if k % 2 == 0 then hull else plate, { bone = name, reflect = 0.08 })
		-- Parlayan kaburga halkası
		disk(ctx, "Rib", pts[k + 1], pts[k + 1] - pts[k], d * 0.92, 0.35, glow, { bone = name, material = Enum.Material.Neon })
		-- Sırt yüzgeci (her iki boğumda bir)
		if k % 2 == 1 then
			local mid = (pts[k] + pts[k + 1]) / 2
			local dir = (pts[k + 1] - pts[k]).Unit
			local upv = (Vector3.yAxis - dir * dir.Y)
			if upv.Magnitude > 0.2 then
				upv = upv.Unit
				local p = mid + upv * d * 0.5
				wedge(ctx, "Fin", Vector3.new(0.5, d * 0.7, d * 1.1), CFrame.lookAt(p, p - dir, upv), rgb(120, 50, 170), { bone = name })
			end
		end
		parent = name
	end

	-- Kafa
	local neck = pts[#pts]
	bone(ctx, "Head", neck, { parent = parent, axis = Vector3.xAxis, sway = 0.05, rate = 1.2, roar = -0.12, grab = -0.1 })
	local H = { bone = "Head" }
	local hc = neck + Vector3.new(0, 0.6, -2.4)
	blob(ctx, "Skull", Vector3.new(6, 4.6, 8), CFrame.new(hc), hull, H)
	blob(ctx, "Crest", Vector3.new(4.2, 2.4, 6.4), CFrame.new(hc + Vector3.new(0, 1.9, 0.6)), plate, H)
	wedge(ctx, "Snout", Vector3.new(4.4, 2.2, 4), CFrame.new(hc + Vector3.new(0, 0.9, -4.8)), plate, H)
	for _, x in { -1, 1 } do
		blob(ctx, "Eye", Vector3.new(1.9, 0.8, 1.2), CFrame.new(hc + Vector3.new(x * 2.3, 1.1, -2.6)) * CFrame.Angles(0, math.rad(x * -20), math.rad(x * 18)), eyeC, { bone = "Head", material = Enum.Material.Neon })
		blob(ctx, "Eye2", Vector3.new(1, 0.5, 0.8), CFrame.new(hc + Vector3.new(x * 2.6, 0.1, -1.6)) * CFrame.Angles(0, 0, math.rad(x * 18)), eyeC, { bone = "Head", material = Enum.Material.Neon })
		-- Geriye yatık boynuzlar
		for h = 1, 2 do
			local a = hc + Vector3.new(x * (1.6 + h * 0.6), 2 + h * 0.3, 1 + h * 0.6)
			local b = a + Vector3.new(x * (1.2 + h * 0.5), 1.6 - h * 0.2, 4.6 - h * 0.6)
			capsule(ctx, "Horn", a, b, 1.1 - h * 0.2, rgb(210, 200, 230), H)
		end
	end
	-- Alt çene ve dişler
	bone(ctx, "Jaw", hc + Vector3.new(0, -1.2, 1.6), { parent = "Head", axis = Vector3.xAxis, sway = 0.04, rate = 2, roar = -0.5 })
	blob(ctx, "Jaw", Vector3.new(4.6, 1.7, 7), CFrame.new(hc + Vector3.new(0, -2, -2.2)), plate, { bone = "Jaw" })
	for i = -2, 2 do
		wedge(ctx, "Fang", Vector3.new(0.5, 1.5, 0.5), CFrame.new(hc + Vector3.new(i * 0.9, -0.7, -5.1 + math.abs(i) * 0.5)) * CFrame.Angles(0, 0, math.rad(180)), rgb(250, 240, 255), H)
		wedge(ctx, "LowFang", Vector3.new(0.45, 1.1, 0.45), CFrame.new(hc + Vector3.new(i * 0.85, -1.3, -4.9 + math.abs(i) * 0.5)), rgb(250, 240, 255), { bone = "Jaw" })
	end
	blob(ctx, "MouthGlow", Vector3.new(3, 0.6, 4), CFrame.new(hc + Vector3.new(0, -1.1, -2.8)), glow, { bone = "Head", material = Enum.Material.Neon })
	-- Boşluk tacı: başın arkasında neon halka
	local crown = hc + Vector3.new(0, 3.4, 3.8)
	for i = 1, 16 do
		local a = i / 16 * math.pi * 2
		local p = crown + Vector3.new(math.cos(a) * 5.4, math.sin(a) * 5.4, 0)
		local q = crown + Vector3.new(math.cos(a + math.pi / 8) * 5.4, math.sin(a + math.pi / 8) * 5.4, 0)
		rod(ctx, "Crown", p, q, 0.45, glow, { bone = "Head", material = Enum.Material.Neon })
	end
	ball(ctx, "CrownCore", 1.4, crown, rgb(255, 220, 255), { bone = "Head", material = Enum.Material.Neon })

	-- İki mekanik kol (boynun altından); sağ kol kavrıyor
	local armBase = pts[11]
	for side, x in { -1, 1 } do
		local name = if x > 0 then "ArmR" else "ArmL"
		local shoulder = armBase + Vector3.new(x * 2.6, -0.6, 0)
		local elbow = shoulder + Vector3.new(x * 3.4, -3.2, -1.6)
		local wrist = elbow + Vector3.new(x * 0.6, -3.4, -2.6)
		bone(ctx, name, shoulder, { parent = "Coil11", axis = Vector3.xAxis, sway = 0.08, rate = 1.3, phase = side * 1.4, grab = if x > 0 then 1.25 else 0.3, roar = 0.5 })
		ball(ctx, "Shoulder", 2, shoulder, plate, { bone = name })
		rod(ctx, "UpperArm", shoulder, elbow, 1.2, hull, { bone = name })
		ball(ctx, "Elbow", 1.6, elbow, glow, { bone = name, material = Enum.Material.Neon })
		rod(ctx, "Forearm", elbow, wrist, 1, hull, { bone = name })
		for f = -1, 1 do
			local tip = wrist + Vector3.new(f * 0.8, -1.4, -1)
			capsule(ctx, "Claw", wrist, tip, 0.5, rgb(230, 220, 250), { bone = name })
		end
		if x > 0 then
			hand(ctx, wrist + Vector3.new(0, -1.8, -1.6), name)
		end
	end

	sparkles(ctx, crown, glow, 10)
	light(ctx, hc + Vector3.new(0, 0, -5), glow, 30, 1.6)
end

local BUILDERS: { [string]: (Ctx) -> () } = {
	Glorp = glorp,
	Chomper = chomper,
	Kraken = kraken,
	SandMaw = sandMaw,
	RiftStalker = riftStalker,
	VoidLeviathan = voidLeviathan,
}

--[[ Canavarı kurar. Kök (Root) ayak tabanının ortasında, model ileri -Z. ]]
function MonsterModel.Build(id: string, scale: number?): Model
	local ctx = newCtx(id, scale or 1)
	local builder = BUILDERS[id] or glorp
	builder(ctx)
	return ctx.model
end

-- ─── İskelet ────────────────────────────────────────────────────────────────

export type Pose = {
	sway: number,    -- salınım çarpanı (kovalarken büyük)
	rate: number,    -- salınım hızı çarpanı
	grab: number,    -- 0..1 kavrama
	roar: number,    -- 0..1 kükreme
}

type BoneData = {
	name: string,
	parent: string,
	joint: Vector3,
	axis: Vector3,
	sway: number,
	rate: number,
	phase: number,
	grab: number,
	roar: number,
}

export type Rig = {
	model: Model,
	Pose: (self: Rig, rootCF: CFrame, t: number, pose: Pose) -> (),
	HandCFrame: (self: Rig) -> CFrame,
}

--[[
	Modelin iskeletini okur ve her karede çağrılacak Pose'u verir.
	Kemikler üst kemikten sonra gelecek şekilde sıralanıyor.
]]
function MonsterModel.Rig(model: Model): Rig
	local root = model.PrimaryPart :: BasePart
	local bones: { BoneData } = {}
	local byName: { [string]: BoneData } = {}
	for _, a in root:GetChildren() do
		if a:IsA("Attachment") and a:GetAttribute("Parent") ~= nil then
			local b: BoneData = {
				name = a.Name,
				parent = a:GetAttribute("Parent") :: string,
				joint = a.Position,
				axis = a:GetAttribute("Axis") :: Vector3,
				sway = a:GetAttribute("Sway") :: number,
				rate = a:GetAttribute("Rate") :: number,
				phase = a:GetAttribute("Phase") :: number,
				grab = a:GetAttribute("Grab") :: number,
				roar = a:GetAttribute("Roar") :: number,
			}
			byName[b.name] = b
		end
	end
	-- Üst kemik önce
	local total = 0
	for _ in byName do
		total += 1
	end
	local ordered: { BoneData } = {}
	local placed: { [string]: boolean } = { [""] = true }
	local guard = 0
	while #ordered < total and guard < 64 do
		guard += 1
		for name, b in byName do
			if not placed[name] and (placed[b.parent] or not byName[b.parent]) then
				placed[name] = true
				table.insert(ordered, b)
			end
		end
	end
	bones = ordered

	local parts: { BasePart } = {}
	local rest: { CFrame } = {}
	local partBone: { string } = {}
	local handPart: BasePart? = nil
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d ~= root then
			table.insert(parts, d)
			table.insert(rest, root.CFrame:ToObjectSpace(d.CFrame))
			table.insert(partBone, (d:GetAttribute("Bone") :: string?) or "")
			if d.Name == "Hand" then
				handPart = d
			end
		end
	end

	local transforms: { [string]: CFrame } = { [""] = CFrame.identity }
	local cframes: { CFrame } = table.create(#parts)
	local lastRoot = CFrame.identity

	local rig = {} :: any
	rig.model = model

	function rig.Pose(_self: Rig, rootCF: CFrame, t: number, pose: Pose)
		lastRoot = rootCF
		for _, b in bones do
			local angle = b.sway * pose.sway * math.sin(t * b.rate * pose.rate + b.phase)
				+ b.grab * pose.grab + b.roar * pose.roar
			local parentT = transforms[b.parent] or CFrame.identity
			if angle ~= 0 then
				transforms[b.name] = parentT * CFrame.new(b.joint) * CFrame.fromAxisAngle(b.axis, angle) * CFrame.new(-b.joint)
			else
				transforms[b.name] = parentT
			end
		end
		for i, p in parts do
			cframes[i] = rootCF * (transforms[partBone[i]] or CFrame.identity) * rest[i]
		end
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		root.CFrame = rootCF
	end

	function rig.HandCFrame(_self: Rig): CFrame
		if handPart then
			return handPart.CFrame
		end
		return lastRoot * CFrame.new(0, 6, -6)
	end

	return rig :: Rig
end

return MonsterModel
