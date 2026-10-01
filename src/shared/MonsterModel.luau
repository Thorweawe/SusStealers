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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.Config)

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

type VfxSpec = {
	texture: string,
	color: Color3,
	color2: Color3?,
	size: number,
	rate: number,
	life: number,
	speed: number,
	spread: number?,
	accel: Vector3?,
	alpha: number?,
	spin: number?,
	box: Vector3?,
	inward: boolean?,  -- kutu yüzeyinden içe (kara delik emişi)
	emission: number?, -- LightEmission (koyu duman için düşük)
	drag: number?,
	lockY: boolean?,   -- hıza dik yassı sprite (zemin halkası)
}

--[[ Özel dokulu parçacık (Config.Vfx). Boyut ve hız ctx.S ile ölçekli.
     `box` verilirse kutu hacminden doğuyor (gövdeyi saran bulut). ]]
local function vfx(ctx: Ctx, name: string, pos: Vector3, spec: VfxSpec)
	local holder: Instance
	if spec.box then
		local p = Instance.new("Part")
		p.Name = name
		p.Size = spec.box * ctx.S
		p.CFrame = CFrame.new(pos * ctx.S)
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p:SetAttribute("Bone", "Body")
		p.Parent = ctx.model
		holder = p
	else
		local a = Instance.new("Attachment")
		a.Name = name
		a.Position = pos * ctx.S
		a.Parent = ctx.root
		holder = a
	end
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = spec.texture
	e.Color = if spec.color2 then ColorSequence.new(spec.color, spec.color2) else ColorSequence.new(spec.color)
	e.LightEmission = spec.emission or 1
	e.LightInfluence = 0
	e.Drag = spec.drag or 0
	if spec.lockY then
		e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	end
	local sz = spec.size * ctx.S
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, sz * 0.3), NumberSequenceKeypoint.new(0.25, sz), NumberSequenceKeypoint.new(1, sz * 0.15) })
	local a0 = spec.alpha or 0.15
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, a0), NumberSequenceKeypoint.new(0.7, a0 + (1 - a0) * 0.4), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(spec.life * 0.7, spec.life * 1.3)
	e.Speed = NumberRange.new(spec.speed * 0.6 * ctx.S, spec.speed * ctx.S)
	e.SpreadAngle = Vector2.new(spec.spread or 180, spec.spread or 180)
	e.Acceleration = (spec.accel or Vector3.zero) * ctx.S
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-(spec.spin or 30), spec.spin or 30)
	e.Rate = spec.rate
	if spec.box then
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = if spec.inward then Enum.ParticleEmitterShapeStyle.Surface else Enum.ParticleEmitterShapeStyle.Volume
		if spec.inward then
			e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		end
	end
	e.Parent = holder
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

	-- Balçık: yükselen köpükler, gövdeden damlayan sümük, yeşil ışıltı
	vfx(ctx, "SlimeBubbles", Vector3.new(0, 3, 0), { texture = Config.Vfx.Bubble, color = glow, color2 = belly, size = 1.1, rate = 3, life = 2.4, speed = 1.2, spread = 30, accel = Vector3.new(0, 1.4, 0), alpha = 0.2, box = Vector3.new(10, 2, 9) })
	vfx(ctx, "SlimeDrips", Vector3.new(0, 6, 0), { texture = Config.Vfx.Orb, color = body, color2 = dark, size = 0.7, rate = 2, life = 1.4, speed = 0.2, accel = Vector3.new(0, -9, 0), alpha = 0.1, box = Vector3.new(9, 3, 8) })
	vfx(ctx, "SlimeGlints", Vector3.new(0, 6, 0), { texture = Config.Vfx.Star, color = rgb(230, 255, 200), size = 0.9, rate = 2, life = 1.2, speed = 0.3, box = Vector3.new(11, 10, 10), spin = 70 })
	light(ctx, Vector3.new(0, 8, -6), glow, 16, 0.8)
end

-- ─── 2. Chomper: pembe dişli, üç gözlü, boynuzlu ────────────────────────────

--[[ Chomper'ın efektleri (ağ ve parça sürümünde ortak): şeker pembesi
     ışıltılar, ağızdan süzülen aç nefes, ayaklardan yükselen ışık
     kabarcıkları. Az ve yavaş: sahne parıltıyla yıkanmasın. ]]
local function chomperFx(ctx: Ctx)
	local pink = rgb(255, 120, 200)
	vfx(ctx, "CandyStars", Vector3.new(0, 8, 0), { texture = Config.Vfx.Star, color = rgb(255, 210, 240), color2 = pink, size = 1.3, rate = 3, life = 1.6, speed = 0.6, box = Vector3.new(15, 14, 13), spin = 60 })
	vfx(ctx, "HungryBreath", Vector3.new(0, 6, -6.5), { texture = Config.Vfx.Wisp, color = rgb(255, 170, 215), color2 = rgb(255, 235, 245), size = 3.2, rate = 1.6, life = 2.2, speed = 2.2, spread = 25, accel = Vector3.new(0, 1.2, 0), alpha = 0.45, spin = 25 })
	vfx(ctx, "SugarBubbles", Vector3.new(0, 1, 0), { texture = Config.Vfx.Orb, color = pink, color2 = rgb(255, 200, 120), size = 0.9, rate = 2.5, life = 2.6, speed = 1.5, spread = 35, accel = Vector3.new(0, 1.5, 0), alpha = 0.3, box = Vector3.new(12, 1, 10) })
	light(ctx, Vector3.new(0, 7, -7), rgb(255, 120, 190), 18, 0.8)
end

--[[
	3D ağ sürümü (2026-10-01): ChatGPT konsepti → TRELLIS (resimden 3D) →
	tools/split_mesh.py → Studio Import 3D. Şablon ReplicatedStorage
	.MonsterMeshes.Chomper: MeshPart'lar ölçek 1'de, ayak tabanı y=0, yüz -Z,
	boy 17 stud. Ağ tek parça kabuk (kollar gövdeden ayrılmıyor), o yüzden
	hepsi "Body" kemiğinde; çene açılmıyor ama ağız zaten kocaman açık.
	Şablon yoksa (ör. testte) eski parça modeli kuruluyor.
]]
local function meshTemplate(id: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("MonsterMeshes")
	local m = folder and folder:FindFirstChild(id)
	return if m and m:IsA("Model") then m else nil
end

local function fromTemplate(ctx: Ctx, template: Model, boneName: string)
	for _, src in template:GetDescendants() do
		if src:IsA("MeshPart") then
			local p = src:Clone()
			for _, c in p:GetChildren() do
				if not (c:IsA("SurfaceAppearance") or c:IsA("Decal") or c:IsA("Texture")) then
					c:Destroy()
				end
			end
			p.Size = src.Size * ctx.S
			p.CFrame = CFrame.new(src.Position * ctx.S) * src.CFrame.Rotation
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p:SetAttribute("Bone", boneName)
			p.Parent = ctx.model
		end
	end
end

local function chomperMesh(ctx: Ctx, template: Model)
	bone(ctx, "Body", Vector3.new(0, 1, 0), { axis = Vector3.xAxis, sway = 0.05, rate = 1.4, roar = -0.12 })
	fromTemplate(ctx, template, "Body")
	-- Kavrama: sağ pençenin önü; kemik omuzda, yakalarken öne/yukarı kalkıyor
	bone(ctx, "ArmR", Vector3.new(5.9, 7.6, -0.4), { parent = "Body", axis = Vector3.xAxis, grab = 1.1, roar = 0.5 })
	hand(ctx, Vector3.new(6.6, 4.6, -4.2), "ArmR")
	chomperFx(ctx)
end

local function chomper(ctx: Ctx)
	local template = meshTemplate("Chomper")
	if template then
		chomperMesh(ctx, template)
		return
	end
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

	chomperFx(ctx)
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

	-- Derin uzay ahtapotu: mürekkep nebulası, yükselen camgöbeği köpükler, ışıltı
	vfx(ctx, "InkNebula", Vector3.new(0, 8, 3), { texture = Config.Vfx.Nebula, color = skin, color2 = rgb(40, 20, 90), size = 7, rate = 1, life = 4, speed = 0.4, alpha = 0.6, spin = 10, emission = 0.6 })
	vfx(ctx, "DeepBubbles", Vector3.new(0, 4, 0), { texture = Config.Vfx.Bubble, color = glow, color2 = pale, size = 1, rate = 3.5, life = 3, speed = 1, spread = 40, accel = Vector3.new(0, 1.6, 0), alpha = 0.2, box = Vector3.new(14, 3, 14) })
	vfx(ctx, "AbyssGlints", Vector3.new(0, 12, 2), { texture = Config.Vfx.Star, color = glow, color2 = pale, size = 1, rate = 3, life = 1.4, speed = 0.3, box = Vector3.new(14, 10, 12), spin = 60 })
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

	-- Kum solucanı: dibinden kalkan toz bulutları, savrulan kum taneleri, ağızda camgöbeği ark
	vfx(ctx, "DuneDust", Vector3.new(0, 1, 2), { texture = Config.Vfx.Dust, color = sand, color2 = band, size = 6, rate = 2, life = 2.6, speed = 2, spread = 60, accel = Vector3.new(0, 0.6, 0), alpha = 0.45, drag = 1, box = Vector3.new(12, 1, 12), emission = 0.15 })
	vfx(ctx, "SandGrains", Vector3.new(0, 4, 2), { texture = Config.Vfx.Ember, color = rgb(255, 225, 170), color2 = sand, size = 0.8, rate = 6, life = 1.2, speed = 6, spread = 70, accel = Vector3.new(0, -6, 0), alpha = 0.2, box = Vector3.new(10, 4, 10), emission = 0.4 })
	vfx(ctx, "MawArcs", face + headDir * 2, { texture = Config.Vfx.Spark, color = maw, color2 = rgb(220, 250, 255), size = 2.4, rate = 2.5, life = 0.35, speed = 0.5, spin = 200 })
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

	-- Cinderhold örümceği: yanardağ korları yükseliyor, karnından camgöbeği enerji dumanı, rift kıvılcımları
	vfx(ctx, "Cinders", Vector3.new(0, 1, 0), { texture = Config.Vfx.Ember, color = rgb(255, 200, 90), color2 = rgb(255, 70, 30), size = 0.9, rate = 7, life = 2, speed = 3, spread = 25, accel = Vector3.new(0, 3, 0), alpha = 0.1, box = Vector3.new(18, 1, 18) })
	vfx(ctx, "RiftWisp", AB, { texture = Config.Vfx.Wisp, color = glow, color2 = rgb(20, 120, 140), size = 4, rate = 2, life = 2, speed = 1, spread = 60, accel = Vector3.new(0, 1, 0), alpha = 0.4, spin = 30 })
	vfx(ctx, "RiftSparks", AB, { texture = Config.Vfx.Spark, color = glow, color2 = rgb(220, 255, 250), size = 2, rate = 2, life = 0.3, speed = 0.4, spin = 200, box = Vector3.new(8, 5, 8) })
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

	-- Boşluk yılanı: koyu boşluk dumanı, mor nebula, taçta kıvılcım, dökülen yıldız tozu
	vfx(ctx, "VoidSmoke", hc, { texture = Config.Vfx.Wisp, color = rgb(60, 20, 90), color2 = rgb(10, 5, 20), size = 7, rate = 2, life = 3, speed = 1.2, alpha = 0.35, spin = 20, emission = 0.1 })
	vfx(ctx, "VoidNebula", hc, { texture = Config.Vfx.Nebula, color = glow, color2 = eyeC, size = 9, rate = 0.8, life = 4, speed = 0.5, alpha = 0.65, spin = 8, emission = 0.7 })
	vfx(ctx, "CrownSparks", crown, { texture = Config.Vfx.Spark, color = glow, color2 = eyeC, size = 2.4, rate = 3, life = 0.35, speed = 0.5, spin = 220 })
	vfx(ctx, "VoidMotes", crown, { texture = Config.Vfx.Star, color = rgb(240, 200, 255), color2 = glow, size = 1, rate = 5, life = 2.2, speed = 1.5, accel = Vector3.new(0, -1.5, 0), spin = 60 })
	light(ctx, hc + Vector3.new(0, 0, -5), glow, 30, 1.6)
end

-- ─── 7. Frost Wyrm: buz ejderhası, kanat çırparak süzülüyor (rebirth 2) ────

local function frostWyrm(ctx: Ctx)
	local ice = rgb(170, 220, 250)
	local deep = rgb(90, 150, 210)
	local belly = rgb(235, 248, 255)
	local crystal = rgb(140, 240, 255)

	bone(ctx, "Body", Vector3.new(0, 6, 0), { axis = Vector3.xAxis, sway = 0.05, rate = 1.3 })
	local B = { bone = "Body" }

	-- Gövde ve karın
	blob(ctx, "Body", Vector3.new(7.5, 6.5, 12), CFrame.new(0, 8, 1), ice, { bone = "Body", reflect = 0.08 })
	blob(ctx, "Belly", Vector3.new(5.5, 3.5, 9), CFrame.new(0, 6.2, 0.4), belly, B)
	-- Sırt boyunca buz dikenleri
	for k = 0, 5 do
		local z = -3 + k * 1.8
		wedge(ctx, "Spike", Vector3.new(0.5, 1.8 - k * 0.15, 1.3), CFrame.new(0, 11.3 - k * 0.15, z), crystal, { bone = "Body", material = Enum.Material.Neon })
	end

	-- Boyun ve baş
	bone(ctx, "Neck", Vector3.new(0, 10, -4), { parent = "Body", axis = Vector3.xAxis, sway = 0.08, rate = 1.5, roar = -0.25, grab = 0.2 })
	capsule(ctx, "Neck", Vector3.new(0, 10, -4), Vector3.new(0, 14, -8), 3.2, ice, { bone = "Neck" })
	blob(ctx, "Head", Vector3.new(4.6, 3.8, 5.8), CFrame.new(0, 15, -9.6), ice, { bone = "Neck" })
	blob(ctx, "Snout", Vector3.new(3.4, 2.2, 3.6), CFrame.new(0, 14.7, -12.2), deep, { bone = "Neck" })
	for _, x in { -1, 1 } do
		eye(ctx, Vector3.new(x * 1.7, 15.9, -11), 1.4, rgb(90, 220, 255), Vector3.new(x * 0.5, 0, -1), "Neck")
		wedge(ctx, "Horn", Vector3.new(0.6, 3, 1), CFrame.new(x * 1.4, 17.6, -8.6) * CFrame.Angles(math.rad(-30), 0, math.rad(x * -15)), crystal, { bone = "Neck", material = Enum.Material.Neon })
	end
	-- Alt çene (kükreyince açılıyor) ve buz dişleri
	bone(ctx, "Jaw", Vector3.new(0, 14, -9), { parent = "Neck", axis = Vector3.xAxis, sway = 0.05, rate = 2, roar = -0.6 })
	blob(ctx, "Jaw", Vector3.new(3.2, 1.1, 4.6), CFrame.new(0, 13.5, -11.4), deep, { bone = "Jaw" })
	blob(ctx, "Mouth", Vector3.new(2.6, 0.8, 3.6), CFrame.new(0, 13.9, -11.6), rgb(30, 70, 120), { bone = "Jaw" })
	for i = -2, 2 do
		wedge(ctx, "Tooth", Vector3.new(0.35, 0.7, 0.35), CFrame.new(i * 0.55, 14.1, -13.1 + math.abs(i) * 0.3), belly, { bone = "Jaw" })
	end

	-- Kanatlar: kemikler ayna, çırparken yukarı-aşağı (Z ekseni)
	for side, x in { -1, 1 } do
		local name = if x > 0 then "WingR" else "WingL"
		local root = Vector3.new(x * 3, 10.5, 0)
		bone(ctx, name, root, { parent = "Body", axis = Vector3.new(0, 0, -x), sway = 0.42, rate = 1.6, phase = 0, roar = 0.5, grab = 0.3 })
		rod(ctx, "WingArm", root, root + Vector3.new(x * 9, 2.5, 1), 0.7, deep, { bone = name })
		for f = 0, 3 do
			local tip = root + Vector3.new(x * (3 + f * 2.2), 2.4 - f * 0.4, 1)
			local low = root + Vector3.new(x * (2.5 + f * 2), -3.6 + f * 0.4, 5 + f * 0.6)
			capsule(ctx, "WingSkin", tip, low, 1.1, crystal, { bone = name, transparency = 0.35, material = Enum.Material.Glass })
		end
		local _ = side
	end

	-- Kuyruk (dört boğum)
	local pts = { Vector3.new(0, 8, 6.5), Vector3.new(0, 7.2, 10), Vector3.new(0, 6.8, 13.4), Vector3.new(0, 7.2, 16.6), Vector3.new(0, 8.4, 19.4) }
	local parent = "Body"
	for k = 1, 4 do
		local name = "Tail" .. k
		bone(ctx, name, pts[k], { parent = parent, axis = Vector3.yAxis, sway = 0.12, rate = 1.3, phase = -k * 0.6 })
		capsule(ctx, "Tail", pts[k], pts[k + 1], 2.6 - k * 0.45, ice, { bone = name })
		parent = name
	end
	wedge(ctx, "TailBlade", Vector3.new(0.5, 2.4, 2), CFrame.new(pts[5] + Vector3.new(0, 0.6, 0.6)), crystal, { bone = parent, material = Enum.Material.Neon })

	-- Pençeli ön ayaklar; sağ ayak kavrıyor, arkada iki kısa bacak
	for side, x in { -1, 1 } do
		local name = if x > 0 then "ArmR" else "ArmL"
		local shoulder = Vector3.new(x * 2.8, 6.4, -3)
		bone(ctx, name, shoulder, { parent = "Body", axis = Vector3.xAxis, sway = 0.1, rate = 1.3, phase = side, grab = if x > 0 then 1.3 else 0.3, roar = 0.3 })
		local foot = shoulder + Vector3.new(x * 0.5, -4, -1.2)
		capsule(ctx, "Leg", shoulder, foot, 1.8, deep, { bone = name })
		for f = -1, 1 do
			wedge(ctx, "Claw", Vector3.new(0.4, 1, 0.5), CFrame.new(foot + Vector3.new(f * 0.5, -0.6, -0.5)) * CFrame.Angles(math.rad(180), 0, 0), belly, { bone = name })
		end
		if x > 0 then
			hand(ctx, foot + Vector3.new(0, -1.2, -1.3), name)
		end
		capsule(ctx, "HindLeg", Vector3.new(x * 3, 6, 5), Vector3.new(x * 3.4, 2.6, 5.6), 2, deep, B)
	end

	-- Buz ejderi: savrulan kar taneleri, yerde soğuk sis, kristal ışıltıları
	vfx(ctx, "Snowfall", Vector3.new(0, 16, 0), { texture = Config.Vfx.Snowflake, color = rgb(240, 252, 255), color2 = crystal, size = 1, rate = 8, life = 3, speed = 0.8, accel = Vector3.new(0, -2.5, 0), alpha = 0.1, box = Vector3.new(22, 2, 22), spin = 90 })
	vfx(ctx, "FrostMist", Vector3.new(0, 1, 0), { texture = Config.Vfx.Dust, color = rgb(220, 245, 255), color2 = deep, size = 8, rate = 1.5, life = 3.5, speed = 1, spread = 80, alpha = 0.6, drag = 0.8, box = Vector3.new(16, 1, 16), emission = 0.3 })
	vfx(ctx, "IceGlints", Vector3.new(0, 9, 0), { texture = Config.Vfx.Star, color = crystal, color2 = rgb(255, 255, 255), size = 1.2, rate = 3, life = 1.2, speed = 0.2, box = Vector3.new(14, 12, 14), spin = 80 })
	light(ctx, Vector3.new(0, 12, -6), crystal, 20, 1)
end

-- ─── 8. Crystal Golem: kristal sırtlı taş dev, ağır adımlar (rebirth 4) ────

local function crystalGolem(ctx: Ctx)
	local stone = rgb(118, 104, 140)
	local dark = rgb(78, 66, 98)
	local pink = rgb(255, 120, 235)
	local cyan = rgb(120, 240, 255)

	bone(ctx, "Body", Vector3.new(0, 1, 0), { axis = Vector3.zAxis, sway = 0.03, rate = 1 })
	local B = { bone = "Body" }

	-- Kütük bacaklar
	for side, x in { -1, 1 } do
		local name = "Leg" .. side
		bone(ctx, name, Vector3.new(x * 3, 6, 0), { parent = "Body", axis = Vector3.xAxis, sway = 0.08, rate = 1, phase = side * 1.6 })
		box(ctx, "Leg", Vector3.new(3.4, 6, 3.6), CFrame.new(x * 3, 3, 0) * CFrame.Angles(0, 0, math.rad(x * 3)), dark, { bone = name })
		box(ctx, "Foot", Vector3.new(4, 1.4, 4.8), CFrame.new(x * 3.1, 0.7, -0.4), stone, { bone = name })
	end

	-- Kaba gövde (iki blok, hafif eğik) ve göğüste parlayan çekirdek
	box(ctx, "Torso", Vector3.new(10, 8, 7), CFrame.new(0, 10.5, 0) * CFrame.Angles(math.rad(-6), 0, 0), stone, { bone = "Body", reflect = 0.05 })
	box(ctx, "Chest", Vector3.new(8.4, 5, 7.6), CFrame.new(0, 12.4, -0.3) * CFrame.Angles(math.rad(-8), math.rad(4), 0), dark, B)
	ball(ctx, "Core", 2.6, Vector3.new(0, 11.4, -3.9), pink, { bone = "Body", material = Enum.Material.Neon })
	-- Sırtta ve omuzlarda kristal kümeleri
	for i, spec in { { -3, 15, 1.5, 4.6, 12 }, { 0, 15.8, 2.4, 5.6, -6 }, { 3, 15, 1.4, 4.4, -18 }, { -5, 14, -0.5, 3.2, 28 }, { 5.2, 14, -0.4, 3.4, -30 }, { -1.5, 13.8, 3.8, 3.6, 20 } } do
		local color = if i % 2 == 0 then cyan else pink
		wedge(ctx, "Crystal", Vector3.new(1.3, spec[4], 1.3), CFrame.new(spec[1], spec[2], spec[3]) * CFrame.Angles(math.rad(-12), 0, math.rad(spec[5])), color, { bone = "Body", material = Enum.Material.Glass, reflect = 0.3 })
		wedge(ctx, "CrystalCore", Vector3.new(0.6, spec[4] * 0.7, 0.6), CFrame.new(spec[1], spec[2] - 0.2, spec[3]) * CFrame.Angles(math.rad(-12), 0, math.rad(spec[5])), color, { bone = "Body", material = Enum.Material.Neon })
	end

	-- Küçük kafa, çatık kaş, iki göz; alt çene taş plaka
	bone(ctx, "Head", Vector3.new(0, 15, -1), { parent = "Body", axis = Vector3.yAxis, sway = 0.06, rate = 0.8, roar = 0.05 })
	box(ctx, "Head", Vector3.new(4.6, 3.6, 4), CFrame.new(0, 16.8, -2), stone, { bone = "Head" })
	box(ctx, "Brow", Vector3.new(4.8, 0.9, 1.2), CFrame.new(0, 17.9, -4) * CFrame.Angles(math.rad(10), 0, 0), dark, { bone = "Head" })
	for _, x in { -1, 1 } do
		ball(ctx, "Eye", 0.9, Vector3.new(x * 1.1, 17.1, -4.05), cyan, { bone = "Head", material = Enum.Material.Neon })
	end
	bone(ctx, "Jaw", Vector3.new(0, 15.6, -1), { parent = "Head", axis = Vector3.xAxis, sway = 0.03, rate = 1.2, roar = -0.55 })
	box(ctx, "Jaw", Vector3.new(4.2, 1.2, 3.8), CFrame.new(0, 14.9, -2.3), dark, { bone = "Jaw" })
	box(ctx, "Maw", Vector3.new(3.4, 0.7, 0.4), CFrame.new(0, 15.6, -4), pink, { bone = "Jaw", material = Enum.Material.Neon })

	-- Kocaman kollar ve kristal yumruklar; sağ kol kavrıyor
	for side, x in { -1, 1 } do
		local name = if x > 0 then "ArmR" else "ArmL"
		local shoulder = Vector3.new(x * 6.4, 13.6, -0.2)
		bone(ctx, name, shoulder, { parent = "Body", axis = Vector3.xAxis, sway = 0.1, rate = 1, phase = side * 1.6 + 1.6, grab = if x > 0 then 1.4 else 0.35, roar = 0.9 })
		box(ctx, "Shoulder", Vector3.new(4, 3.4, 4), CFrame.new(shoulder + Vector3.new(x * 0.6, 0.4, 0)), dark, { bone = name })
		local elbow = shoulder + Vector3.new(x * 1.6, -4, -0.6)
		local wrist = elbow + Vector3.new(0, -3.4, -1)
		capsule(ctx, "UpperArm", shoulder, elbow, 2.8, stone, { bone = name })
		capsule(ctx, "Forearm", elbow, wrist, 3.2, stone, { bone = name })
		box(ctx, "Fist", Vector3.new(3.8, 3.6, 3.8), CFrame.new(wrist + Vector3.new(0, -1.6, -0.3)), dark, { bone = name })
		wedge(ctx, "Knuckle", Vector3.new(0.9, 1.6, 0.9), CFrame.new(wrist + Vector3.new(x * 0.6, -0.4, -2.2)) * CFrame.Angles(math.rad(-70), 0, 0), cyan, { bone = name, material = Enum.Material.Neon })
		if x > 0 then
			hand(ctx, wrist + Vector3.new(0, -2.4, -2.4), name)
		end
	end

	-- Kristal dev: etrafında süzülen kristal kırıkları, pembe-camgöbeği ışıltı, prizma halkası
	vfx(ctx, "FloatingShards", Vector3.new(0, 10, 0), { texture = Config.Vfx.Crystal, color = pink, color2 = cyan, size = 1.6, rate = 2.5, life = 3, speed = 0.5, accel = Vector3.new(0, 0.8, 0), alpha = 0.1, box = Vector3.new(16, 14, 14), spin = 40 })
	vfx(ctx, "PrismGlints", Vector3.new(0, 14, 1), { texture = Config.Vfx.Star, color = rgb(255, 230, 250), color2 = cyan, size = 1.3, rate = 4, life = 1.2, speed = 0.3, box = Vector3.new(12, 10, 10), spin = 90 })
	vfx(ctx, "PrismRing", Vector3.new(0, 0.4, 0), { texture = Config.Vfx.Ring, color = pink, color2 = cyan, size = 14, rate = 0.5, life = 2.5, speed = 0.01, spread = 0, alpha = 0.5, lockY = true, spin = 5 })
	light(ctx, Vector3.new(0, 12, -5), pink, 18, 1.1)
end

-- ─── 9. Solar Phoenix: alevli kanatlı güneş kuşu (rebirth 6) ─────────────────

local function solarPhoenix(ctx: Ctx)
	local body = rgb(255, 140, 40)
	local gold = rgb(255, 210, 80)
	local red = rgb(230, 60, 30)
	local fire = rgb(255, 170, 40)

	bone(ctx, "Body", Vector3.new(0, 7, 0), { axis = Vector3.xAxis, sway = 0.06, rate = 1.4 })
	local B = { bone = "Body" }

	blob(ctx, "Body", Vector3.new(6.4, 6.8, 9.6), CFrame.new(0, 9, 0.5) * CFrame.Angles(math.rad(-15), 0, 0), body, B)
	blob(ctx, "Chest", Vector3.new(4.8, 5, 4), CFrame.new(0, 9.6, -3.2), gold, B)

	-- Baş, tepelik, gaga (alt gaga = çene)
	bone(ctx, "Head", Vector3.new(0, 12.5, -3.5), { parent = "Body", axis = Vector3.xAxis, sway = 0.07, rate = 1.8, roar = -0.25 })
	ball(ctx, "Head", 4.4, Vector3.new(0, 14.6, -5), body, { bone = "Head" })
	for _, x in { -1, 1 } do
		eye(ctx, Vector3.new(x * 1.35, 15.2, -6.6), 1.2, rgb(255, 240, 120), Vector3.new(x * 0.4, 0, -1), "Head", rgb(120, 20, 10))
	end
	for i = -2, 2 do
		wedge(ctx, "Crest", Vector3.new(0.5, 3.4 - math.abs(i) * 0.5, 1.6), CFrame.new(i * 0.55, 17.4 - math.abs(i) * 0.3, -3.6 + math.abs(i) * 0.3) * CFrame.Angles(math.rad(-35), 0, math.rad(i * 12)), if i == 0 then gold else fire, { bone = "Head", material = Enum.Material.Neon })
	end
	wedge(ctx, "Beak", Vector3.new(1.4, 1, 2.8), CFrame.new(0, 14.6, -7.9) * CFrame.Angles(math.rad(-90), 0, 0), gold, { bone = "Head" })
	bone(ctx, "Jaw", Vector3.new(0, 13.9, -6.6), { parent = "Head", axis = Vector3.xAxis, sway = 0.04, rate = 2.2, roar = -0.55 })
	wedge(ctx, "LowerBeak", Vector3.new(1.1, 0.7, 2.2), CFrame.new(0, 13.8, -7.8) * CFrame.Angles(math.rad(-90), 0, math.rad(180)), rgb(220, 150, 40), { bone = "Jaw" })

	-- Alevli kanatlar: büyük çırpış, tüyler neon
	for side, x in { -1, 1 } do
		local name = if x > 0 then "WingR" else "WingL"
		local root = Vector3.new(x * 2.8, 11, 0)
		bone(ctx, name, root, { parent = "Body", axis = Vector3.new(0, 0, -x), sway = 0.5, rate = 2, phase = 0, roar = 0.6, grab = 0.2 })
		for f = 0, 5 do
			local len = 7 + f * 1.2
			local a = math.rad(15 - f * 11)
			local tip = root + Vector3.new(x * math.cos(a) * len, math.sin(a) * len * 0.6 + 1, 1 + f * 0.8)
			capsule(ctx, "Feather", root + Vector3.new(x * 1, 0, f * 0.4), tip, 1.5 - f * 0.1, if f % 2 == 0 then fire else red, { bone = name, material = Enum.Material.Neon })
		end
	end

	-- Kuyruk tüyleri (üç boğum, uçları altın)
	for i = -1, 1 do
		local pts = { Vector3.new(i * 0.8, 8, 5), Vector3.new(i * 1.8, 6.5, 9.5), Vector3.new(i * 3, 5.4, 14), Vector3.new(i * 4.2, 5, 18) }
		local parent = "Body"
		for k = 1, 3 do
			local name = "Tail" .. i .. "_" .. k
			bone(ctx, name, pts[k], { parent = parent, axis = Vector3.yAxis, sway = 0.1, rate = 1.4, phase = -k * 0.5 + i })
			capsule(ctx, "TailFeather", pts[k], pts[k + 1], 1.3 - k * 0.2, if k == 3 then gold else fire, { bone = name, material = Enum.Material.Neon })
			parent = name
		end
	end

	-- Pençeli bacaklar; sağ pençe kavrıyor
	for side, x in { -1, 1 } do
		local name = if x > 0 then "ArmR" else "ArmL"
		local hip = Vector3.new(x * 1.6, 6.5, 1)
		bone(ctx, name, hip, { parent = "Body", axis = Vector3.xAxis, sway = 0.08, rate = 1.4, phase = side, grab = if x > 0 then 1.5 else 0.3, roar = 0.2 })
		local foot = hip + Vector3.new(0, -4.8, -0.6)
		rod(ctx, "Leg", hip, foot, 0.8, gold, { bone = name })
		for f = -1, 1 do
			wedge(ctx, "Talon", Vector3.new(0.35, 1.1, 0.4), CFrame.new(foot + Vector3.new(f * 0.5, -0.4, -0.7)) * CFrame.Angles(math.rad(-110), 0, 0), rgb(60, 30, 20), { bone = name })
		end
		if x > 0 then
			hand(ctx, foot + Vector3.new(0, -1.2, -1.4), name)
		end
	end

	-- Güneş anka kuşu: gövdeden yükselen alev dilleri, havada uçuşan korlar, ısı dalgası
	vfx(ctx, "SolarFlames", Vector3.new(0, 9, 2), { texture = Config.Vfx.Flame, color = rgb(255, 230, 120), color2 = red, size = 4, rate = 9, life = 0.9, speed = 3, spread = 25, accel = Vector3.new(0, 6, 0), alpha = 0.1, box = Vector3.new(8, 6, 6), spin = 20 })
	vfx(ctx, "SolarEmbers", Vector3.new(0, 10, 2), { texture = Config.Vfx.Ember, color = gold, color2 = red, size = 1, rate = 10, life = 1.8, speed = 5, accel = Vector3.new(0, 3, 0), alpha = 0.05, box = Vector3.new(18, 8, 10) })
	vfx(ctx, "HeatWave", Vector3.new(0, 9, 2), { texture = Config.Vfx.Ring, color = fire, color2 = red, size = 18, rate = 0.6, life = 1.4, speed = 0.01, spread = 0, alpha = 0.55 })
	light(ctx, Vector3.new(0, 11, -3), fire, 26, 1.6)
end

-- ─── 10. Black Hole Devourer: ağzı kara delik, etrafında dönen halka (rebirth 8)

local function blackHole(ctx: Ctx)
	local void = rgb(14, 10, 24)
	local purple = rgb(170, 90, 255)
	local pink = rgb(255, 110, 200)
	local rim = rgb(60, 40, 100)

	bone(ctx, "Body", Vector3.new(0, 11, 0), { axis = Vector3.xAxis, sway = 0.05, rate = 0.9 })
	local B = { bone = "Body" }

	-- Kapkara küre, parlak kenar halkası
	ball(ctx, "Core", 12, Vector3.new(0, 11, 0), void, { bone = "Body", reflect = 0.15 })
	ball(ctx, "Rim", 12.6, Vector3.new(0, 11, 0), rim, { bone = "Body", transparency = 0.7, material = Enum.Material.Neon })

	-- Birikim diski: iki halka boncuk, sürekli dönüyor gibi salınıyor
	bone(ctx, "Ring", Vector3.new(0, 11, 0), { parent = "Body", axis = Vector3.yAxis, sway = 1.4, rate = 0.45, roar = 0.8 })
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		local r = 9.5
		ball(ctx, "Disk", 1.5 - (i % 3) * 0.25, Vector3.new(math.cos(a) * r, 11 + math.sin(a * 3) * 0.4, math.sin(a) * r), if i % 2 == 0 then purple else pink, { bone = "Ring", material = Enum.Material.Neon })
	end
	bone(ctx, "Ring2", Vector3.new(0, 11, 0), { parent = "Body", axis = Vector3.new(0.3, 1, 0).Unit, sway = -1.1, rate = 0.6 })
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		ball(ctx, "Debris", 1.1, Vector3.new(math.cos(a) * 12.5, 11 + math.sin(a) * 2, math.sin(a) * 12.5), rgb(120, 110, 140), { bone = "Ring2" })
	end

	-- Göz kümesi üstte
	for i, spec in { { -3, 15.6, -3.2, 1.6 }, { 0, 16.6, -3.4, 2.2 }, { 3, 15.6, -3.2, 1.6 }, { -1.6, 14.4, -4.6, 1.1 }, { 1.6, 14.4, -4.6, 1.1 } } do
		eye(ctx, Vector3.new(spec[1], spec[2], spec[3]), spec[4], purple, Vector3.new(spec[1] * 0.1, 0, -1), "Body", rgb(255, 255, 255))
		local _ = i
	end

	-- Dev ağız: üst dişler gövdede, alt dudak + dişler çenede
	blob(ctx, "Maw", Vector3.new(8, 4.4, 2.4), CFrame.new(0, 10, -5.4), rgb(80, 0, 40), B)
	ball(ctx, "Throat", 3, Vector3.new(0, 10, -5.2), pink, { bone = "Body", material = Enum.Material.Neon })
	for i = -3, 3 do
		wedge(ctx, "Fang", Vector3.new(0.8, 1.6 - math.abs(i) * 0.15, 0.6), CFrame.new(i * 1.05, 11.8, -6.2 + math.abs(i) * 0.2) * CFrame.Angles(0, 0, math.rad(180)), rgb(240, 230, 255), B)
	end
	bone(ctx, "Jaw", Vector3.new(0, 9, -3), { parent = "Body", axis = Vector3.xAxis, sway = 0.08, rate = 1.8, roar = -0.6 })
	blob(ctx, "Lip", Vector3.new(8.6, 2, 3.6), CFrame.new(0, 8, -5.2), void, { bone = "Jaw" })
	for i = -2, 2 do
		wedge(ctx, "LowFang", Vector3.new(0.75, 1.2, 0.6), CFrame.new(i * 1.2, 8.8, -6.4 + math.abs(i) * 0.2), rgb(240, 230, 255), { bone = "Jaw" })
	end

	-- İki dokunaç kol; sağdaki kavrıyor
	for side, x in { -1, 1 } do
		local pts = { Vector3.new(x * 5.6, 8, -1), Vector3.new(x * 8, 5.5, -2), Vector3.new(x * 9, 2.8, -3.2), Vector3.new(x * 8.4, 0.8, -4.6) }
		local parent = "Body"
		local name = ""
		for k = 1, 3 do
			name = (if x > 0 then "ArmR" else "ArmL") .. (if k == 1 then "" else tostring(k))
			bone(ctx, name, pts[k], { parent = parent, axis = Vector3.xAxis, sway = 0.12, rate = 1.3, phase = side + k * 0.6, grab = if x > 0 then 0.55 else 0.15, roar = 0.3 })
			capsule(ctx, "Tentacle", pts[k], pts[k + 1], 2 - k * 0.4, rim, { bone = name })
			parent = name
		end
		ball(ctx, "TentacleTip", 1.1, pts[4], purple, { bone = name, material = Enum.Material.Neon })
		if x > 0 then
			hand(ctx, pts[4] + Vector3.new(0, -0.4, -1.2), name)
		end
	end

	-- Kara delik: her yandan İÇERİ emilen yıldız tozu, dönen nebula, olay ufku halkası
	vfx(ctx, "Accretion", Vector3.new(0, 11, 0), { texture = Config.Vfx.Star, color = pink, color2 = purple, size = 1, rate = 14, life = 1.2, speed = 9, box = Vector3.new(26, 26, 26), inward = true, spin = 120 })
	vfx(ctx, "SpiralNebula", Vector3.new(0, 11, 0), { texture = Config.Vfx.Nebula, color = purple, color2 = rim, size = 12, rate = 1, life = 3.5, speed = 0.2, alpha = 0.55, spin = 45, emission = 0.6 })
	vfx(ctx, "HorizonRing", Vector3.new(0, 11, 0), { texture = Config.Vfx.Ring, color = pink, color2 = purple, size = 16, rate = 0.7, life = 1.8, speed = 0.01, spread = 0, alpha = 0.4 })
	light(ctx, Vector3.new(0, 11, -7), purple, 26, 1.3)
end

-- ─── 11. Galaxy Titan: yıldızlı dev, pelerin ve taç (rebirth 10, son boss) ──

local function galaxyTitan(ctx: Ctx)
	local navy = rgb(34, 40, 96)
	local deep = rgb(20, 22, 60)
	local gold = rgb(255, 214, 110)
	local star = rgb(255, 250, 230)
	local nebula = rgb(170, 110, 255)

	bone(ctx, "Body", Vector3.new(0, 9, 0), { axis = Vector3.zAxis, sway = 0.03, rate = 0.8 })
	local B = { bone = "Body" }

	-- Bacaklar (adım adım salınım)
	for side, x in { -1, 1 } do
		local name = "Leg" .. side
		local hip = Vector3.new(x * 2.6, 9, 0)
		bone(ctx, name, hip, { parent = "Body", axis = Vector3.xAxis, sway = 0.14, rate = 1, phase = side * 1.6 })
		capsule(ctx, "Thigh", hip, hip + Vector3.new(x * 0.3, -4.5, 0), 3.2, navy, { bone = name })
		capsule(ctx, "Shin", hip + Vector3.new(x * 0.3, -4.5, 0), hip + Vector3.new(x * 0.4, -8.2, -0.4), 2.8, deep, { bone = name })
		box(ctx, "Boot", Vector3.new(3, 1.4, 4), CFrame.new(hip + Vector3.new(x * 0.4, -8.4, -0.9)), gold, { bone = name })
	end

	-- Gövde, kemer, göğüste galaksi girdabı ve yıldızlar
	blob(ctx, "Torso", Vector3.new(9.4, 10, 6), CFrame.new(0, 14.4, 0), navy, B)
	box(ctx, "Belt", Vector3.new(8.2, 1.2, 5.6), CFrame.new(0, 10.4, 0), gold, B)
	disk(ctx, "Galaxy", Vector3.new(0, 15, -3.05), Vector3.new(0, 0, -1), 4.6, 0.2, nebula, { bone = "Body", material = Enum.Material.Neon, transparency = 0.1 })
	disk(ctx, "GalaxyCore", Vector3.new(0, 15, -3.2), Vector3.new(0, 0, -1), 1.8, 0.2, star, { bone = "Body", material = Enum.Material.Neon })
	for _, p in { Vector3.new(-3, 17.5, -2.4), Vector3.new(3.2, 12.6, -2.5), Vector3.new(-2.6, 12, -2.6), Vector3.new(2.4, 18, -2.2), Vector3.new(-3.8, 14.6, -1.6), Vector3.new(3.8, 15.6, -1.6) } do
		ball(ctx, "Star", 0.6, p, star, { bone = "Body", material = Enum.Material.Neon })
	end

	-- Yıldız pelerini (arkada, salınıyor)
	bone(ctx, "Cape", Vector3.new(0, 18.5, 2.6), { parent = "Body", axis = Vector3.xAxis, sway = 0.06, rate = 0.9, roar = 0.15 })
	box(ctx, "Cape", Vector3.new(9.6, 14, 0.4), CFrame.new(0, 11.8, 3.6) * CFrame.Angles(math.rad(8), 0, 0), deep, { bone = "Cape" })
	for i = 1, 8 do
		ball(ctx, "CapeStar", 0.45, Vector3.new(-4 + (i * 1.37) % 8, 6 + (i * 2.3) % 11, 3.95 + (i % 3) * 0.05), star, { bone = "Cape", material = Enum.Material.Neon })
	end

	-- Baş, parlayan gözler, yıldız taç; çene
	bone(ctx, "Head", Vector3.new(0, 19.5, 0), { parent = "Body", axis = Vector3.xAxis, sway = 0.05, rate = 0.9, roar = -0.15 })
	blob(ctx, "Head", Vector3.new(5, 5.6, 5), CFrame.new(0, 22, -0.2), navy, { bone = "Head" })
	for _, x in { -1, 1 } do
		blob(ctx, "Eye", Vector3.new(1.3, 0.7, 0.4), CFrame.new(x * 1.1, 22.6, -2.6), gold, { bone = "Head", material = Enum.Material.Neon })
	end
	for i = -2, 2 do
		wedge(ctx, "Crown", Vector3.new(0.9, 2.4 - math.abs(i) * 0.3, 0.9), CFrame.new(i * 1.1, 25.6 - math.abs(i) * 0.3, -0.3 + math.abs(i) * 0.4), gold, { bone = "Head", material = Enum.Material.Neon })
		ball(ctx, "CrownGem", 0.6, Vector3.new(i * 1.1, 26.9 - math.abs(i) * 0.45, -0.3 + math.abs(i) * 0.4), if i == 0 then nebula else star, { bone = "Head", material = Enum.Material.Neon })
	end
	bone(ctx, "Jaw", Vector3.new(0, 20.6, -0.6), { parent = "Head", axis = Vector3.xAxis, sway = 0.03, rate = 1.3, roar = -0.5 })
	blob(ctx, "Jaw", Vector3.new(3.8, 1.6, 3.4), CFrame.new(0, 20.3, -1.6), deep, { bone = "Jaw" })
	blob(ctx, "Mouth", Vector3.new(2.8, 0.6, 0.4), CFrame.new(0, 20.9, -3.1), nebula, { bone = "Jaw", material = Enum.Material.Neon })

	-- Uzun kollar, altın bilezik; sağ kol kavrıyor
	for side, x in { -1, 1 } do
		local name = if x > 0 then "ArmR" else "ArmL"
		local shoulder = Vector3.new(x * 5.4, 18, 0)
		bone(ctx, name, shoulder, { parent = "Body", axis = Vector3.xAxis, sway = 0.12, rate = 1, phase = side * 1.6 + 1.6, grab = if x > 0 then 1.45 else 0.3, roar = 0.7 })
		ball(ctx, "Pauldron", 3.4, shoulder + Vector3.new(x * 0.4, 0.4, 0), gold, { bone = name })
		local elbow = shoulder + Vector3.new(x * 1.2, -5, -0.5)
		local wrist = elbow + Vector3.new(0, -4.6, -1)
		capsule(ctx, "UpperArm", shoulder, elbow, 2.6, navy, { bone = name })
		capsule(ctx, "Forearm", elbow, wrist, 2.4, navy, { bone = name })
		disk(ctx, "Bracer", elbow + (wrist - elbow) * 0.6, (wrist - elbow).Unit, 2.8, 0.8, gold, { bone = name })
		ball(ctx, "Fist", 2.6, wrist + Vector3.new(0, -1, -0.3), deep, { bone = name })
		if x > 0 then
			hand(ctx, wrist + Vector3.new(0, -2, -1.6), name)
		end
	end

	-- Galaksi titanı: altın yıldız yağmuru, omuzlarında nebula, kozmik kıvılcımlar
	vfx(ctx, "StarShower", Vector3.new(0, 15, 0), { texture = Config.Vfx.Star, color = star, color2 = gold, size = 1.4, rate = 8, life = 2, speed = 0.4, accel = Vector3.new(0, -1, 0), box = Vector3.new(18, 18, 12), spin = 80 })
	vfx(ctx, "TitanNebula", Vector3.new(0, 18, 2), { texture = Config.Vfx.Nebula, color = nebula, color2 = navy, size = 12, rate = 1, life = 4, speed = 0.3, alpha = 0.6, spin = 8, emission = 0.7 })
	vfx(ctx, "CosmicSparks", Vector3.new(0, 15, 0), { texture = Config.Vfx.Spark, color = gold, color2 = star, size = 2.2, rate = 2, life = 0.35, speed = 0.4, box = Vector3.new(14, 14, 8), spin = 200 })
	light(ctx, Vector3.new(0, 16, -5), gold, 28, 1.3)
end

local BUILDERS: { [string]: (Ctx) -> () } = {
	Glorp = glorp,
	Chomper = chomper,
	Kraken = kraken,
	SandMaw = sandMaw,
	RiftStalker = riftStalker,
	VoidLeviathan = voidLeviathan,
	FrostWyrm = frostWyrm,
	CrystalGolem = crystalGolem,
	SolarPhoenix = solarPhoenix,
	BlackHole = blackHole,
	GalaxyTitan = galaxyTitan,
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
