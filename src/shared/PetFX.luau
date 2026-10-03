--!strict
--[[
	Petlere kendi temalarında parçacık efekti (2026-10-02, Yusuf: "bütün
	petleri 3D kaliteli şekilde yapalım, efektlerle kendi temalarına uygun").

	PetModel.Build ölçeklemeden ÖNCE çağırıyor (ScaleTo yayıcıları da
	büyütüyor; Titan petin efekti de iri olsun). Konumlar gövdeye göre, 1.0
	ölçekte (pet ~2 stud). Common/Uncommon tek hafif yayıcı, Legendary+ iki.
	Dokular VfxThemes'ten (yüklenmeden genel Config.Vfx'e düşüyor) — crewmate,
	canavar ve gezegen efektleriyle aynı aile.
]]

local Config = require(script.Parent.Config)
local T = require(script.Parent.VfxThemes)

local PetFX = {}

local V = Config.Vfx

type Opts = { speed: number?, spread: number?, accel: Vector3?, alpha: number?, spin: number?, grow: number?, emission: number?, up: boolean?, down: boolean?, surface: boolean?, inward: boolean? }

local function c3(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

--[[
	2026-10-03 (kullanıcı: "petlerde efektler yok gibi"): saniyede 0.6–2
	parçacık oyunda fark edilmiyordu. Tüm pet efektleri buradan güçleniyor.
]]
local RATE_BOOST = 3
local SIZE_BOOST = 1.35

local function emit(body: BasePart, name: string, at: Vector3, tex: string, c1: Color3, c2: Color3, size: number, rate: number, life: number, o: Opts?)
	local opts: Opts = o or {}
	size *= SIZE_BOOST
	rate = math.max(2, rate * RATE_BOOST)
	local e = Instance.new("ParticleEmitter")
	e.Name = "PetFX_" .. name
	e.Texture = tex
	e.Color = ColorSequence.new(c1, c2)
	e.LightEmission = opts.emission or 1
	e.LightInfluence = 0
	local g = opts.grow or 0.2
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * math.min(0.3, g)),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, size * g),
	})
	local a0 = opts.alpha or 0.2
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, a0),
		NumberSequenceKeypoint.new(0.75, a0 + (1 - a0) * 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(life * 0.7, life * 1.3)
	local sp = opts.speed or 0.3
	e.Speed = NumberRange.new(sp * 0.5, sp)
	e.SpreadAngle = Vector2.new(opts.spread or 180, opts.spread or 180)
	e.Acceleration = opts.accel or Vector3.zero
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-(opts.spin or 40), opts.spin or 40)
	e.Rate = rate
	if opts.up then
		e.EmissionDirection = Enum.NormalId.Top
	elseif opts.down then
		e.EmissionDirection = Enum.NormalId.Bottom
	end
	if opts.surface then
		e.Shape = Enum.ParticleEmitterShape.Sphere
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		if opts.inward then
			e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		end
		e.Parent = body
	else
		local a = Instance.new("Attachment")
		a.Name = "PetFX_" .. name
		a.Position = at
		a.Parent = body
		e.Parent = a
	end
end

local O = Vector3.zero
local TOP = Vector3.new(0, 0.9, 0)
local BACK = Vector3.new(0, 0, 0.8)
local LOW = Vector3.new(0, -0.8, 0)
local RISE = Vector3.new(0, 0.6, 0)

local FX: { [string]: (b: BasePart) -> () } = {
	-- Supply Egg
	Bolt = function(b) -- metal kıvılcım
		emit(b, "Spark", O, V.Spark, c3(255, 240, 200), c3(255, 180, 80), 0.3, 0.8, 0.2, { surface = true, spin = 250 })
	end,
	VentRat = function(b) -- havalandırma tozu
		emit(b, "Dust", LOW, V.Dust, c3(170, 150, 130), c3(110, 95, 80), 0.6, 0.8, 1.2, { speed = 0.4, spread = 80, alpha = 0.6, emission = 0.1 })
	end,
	Hamster = function(b) -- kargo dişlisi
		emit(b, "Gear", TOP, T("gear", V.Star), c3(255, 230, 170), c3(220, 170, 90), 0.25, 0.6, 1.2, { speed = 0.4, up = true, spread = 30, spin = 90 })
	end,
	SparePod = function(b) -- vizörde parıltı + iticiden duman
		emit(b, "Glint", Vector3.new(0.2, 0.2, -0.7), V.Star, c3(255, 255, 255), c3(150, 230, 255), 0.35, 0.8, 0.5, { speed = 0, spin = 120 })
		emit(b, "Puff", LOW, V.Dust, c3(220, 240, 255), c3(160, 200, 230), 0.4, 1, 0.8, { speed = 0.6, down = true, spread = 25, alpha = 0.5, emission = 0.2 })
	end,
	FuelCan = function(b) -- kapaktan alev + kor
		emit(b, "Flame", TOP, V.Flame, c3(255, 230, 130), c3(255, 100, 30), 0.4, 3, 0.4, { speed = 0.6, up = true, spread = 15, accel = RISE, alpha = 0.1 })
		emit(b, "Ember", TOP, V.Ember, c3(255, 220, 120), c3(255, 120, 40), 0.15, 1.5, 0.9, { speed = 0.8, up = true, spread = 40 })
	end,

	-- Skeld Egg
	MiniCrew = function(b) -- vizör parlaması
		emit(b, "Visor", Vector3.new(0.2, 0.3, -0.7), V.Star, c3(255, 255, 255), c3(170, 230, 255), 0.3, 0.6, 0.5, { speed = 0, spin = 120 })
	end,
	BrainSlug = function(b) -- düşünce kabarcıkları
		emit(b, "Think", TOP, V.Bubble, c3(255, 190, 230), c3(240, 120, 200), 0.2, 1, 1.4, { speed = 0.4, up = true, spread = 30, alpha = 0.3 })
	end,
	TaskBot = function(b) -- iş bitti işareti
		emit(b, "Task", TOP, T("wrench", V.Star), c3(180, 255, 240), c3(60, 230, 200), 0.25, 0.5, 1.2, { speed = 0.4, up = true, spread = 20, spin = 60 })
	end,
	MedDrone = function(b) -- tarama halkası
		emit(b, "Scan", LOW, V.Ring, c3(150, 230, 255), c3(80, 180, 255), 1.4, 0.8, 1, { speed = 1, up = true, spread = 0, grow = 1, alpha = 0.4, spin = 0 })
	end,
	SecurityCam = function(b) -- mercek parlaması + kayıt kıvılcımı
		emit(b, "Lens", Vector3.new(0, 0, -0.8), T("eye", V.Star), c3(180, 240, 255), c3(90, 200, 255), 0.4, 0.6, 0.6, { speed = 0, spin = 30 })
		emit(b, "Rec", TOP, V.Spark, c3(255, 120, 120), c3(255, 40, 40), 0.2, 0.8, 0.25, { speed = 0.1, spin = 200 })
	end,
	PrimeShield = function(b) -- kalkan halkası + mavi ışıltı
		emit(b, "Shield", O, T("shield", V.Ring), c3(150, 200, 255), c3(70, 150, 255), 1.2, 0.6, 1, { speed = 0, grow = 1.4, alpha = 0.5, spin = 0 })
		emit(b, "Glow", O, V.Star, c3(220, 240, 255), c3(90, 160, 255), 0.25, 2, 0.8, { surface = true, speed = 0.2, spin = 150 })
	end,

	-- Polus Egg
	SnowPal = function(b) -- kar
		emit(b, "Snow", TOP, V.Snowflake, c3(255, 255, 255), c3(200, 230, 255), 0.2, 1.2, 1.6, { speed = 0.3, accel = Vector3.new(0, -0.6, 0), spin = 90 })
	end,
	VentCrab = function(b) -- havalandırma buharı
		emit(b, "Steam", TOP, T("steam", V.Wisp), c3(220, 230, 235), c3(160, 175, 185), 0.5, 0.8, 1.2, { speed = 0.5, up = true, spread = 25, alpha = 0.6, emission = 0.2 })
	end,
	CoreShard = function(b) -- reaktör koru
		emit(b, "Core", O, V.Ember, c3(255, 210, 110), c3(255, 100, 20), 0.15, 2, 1, { surface = true, speed = 0.4, accel = RISE })
	end,
	EscapePod = function(b) -- iticiden alev
		emit(b, "Thrust", LOW, V.Flame, c3(255, 230, 160), c3(255, 120, 40), 0.35, 3, 0.3, { speed = 1.2, down = true, spread = 12, alpha = 0.15 })
	end,
	SusShadow = function(b) -- mor gölge dumanı + göz
		emit(b, "Smoke", O, V.Wisp, c3(130, 70, 200), c3(40, 10, 70), 0.8, 1.6, 1.4, { surface = true, speed = 0.3, accel = RISE, alpha = 0.45, emission = 0.2 })
		emit(b, "Eyes", Vector3.new(0, 0.2, -0.7), T("eye", V.Star), c3(255, 240, 120), c3(255, 200, 40), 0.3, 0.5, 0.4, { speed = 0, spin = 20 })
	end,
	MeetingBell = function(b) -- alarm halkası + "!"
		emit(b, "Alarm", O, V.Ring, c3(255, 110, 140), c3(255, 40, 80), 1.6, 0.9, 0.7, { speed = 0, grow = 1.6, alpha = 0.45, spin = 0 })
		emit(b, "Alert", TOP, T("alert", V.Star), c3(255, 140, 160), c3(255, 60, 90), 0.35, 0.5, 0.9, { speed = 0.4, up = true, spread = 10, spin = 0 })
	end,
	TheEgg = function(b) -- çatlaktan altın ışık + ışık hüzmesi
		emit(b, "Crack", O, V.Star, c3(255, 245, 200), c3(255, 200, 80), 0.3, 2.5, 0.8, { surface = true, speed = 0.1, spin = 160 })
		emit(b, "Halo", O, V.Orb, c3(255, 240, 190), c3(255, 210, 120), 2, 0.5, 1.6, { speed = 0, alpha = 0.65 })
	end,

	-- Void Egg
	VoidMite = function(b) -- mor boşluk tozu
		emit(b, "Void", O, V.Dust, c3(150, 100, 220), c3(60, 30, 110), 0.4, 1, 1.2, { surface = true, speed = 0.2, alpha = 0.55, emission = 0.3 })
	end,
	StarJelly = function(b) -- dökülen yıldızlar
		emit(b, "Stars", LOW, V.Star, c3(255, 200, 240), c3(255, 120, 210), 0.2, 1.5, 1.2, { speed = 0.3, accel = Vector3.new(0, -0.5, 0), spin = 120 })
	end,
	CometPup = function(b) -- kuyruklu yıldız izi
		emit(b, "Tail", BACK, T("comet", V.Star), c3(200, 245, 255), c3(90, 200, 255), 0.3, 2, 0.8, { speed = 0.6, spread = 20, accel = Vector3.new(0, 0, 1), spin = 40 })
	end,
	GhostCrew = function(b) -- hayalet buğusu
		emit(b, "Ghost", LOW, V.Wisp, c3(210, 225, 255), c3(140, 160, 230), 0.7, 1.4, 1.4, { speed = 0.3, up = true, spread = 50, alpha = 0.5, emission = 0.5 })
	end,
	MiniImp = function(b) -- kızıl kor + bakış
		emit(b, "Glare", Vector3.new(0.2, 0.3, -0.7), T("eye", V.Star), c3(255, 80, 80), c3(200, 0, 30), 0.35, 0.6, 0.5, { speed = 0, spin = 20 })
		emit(b, "Ember", LOW, V.Ember, c3(255, 110, 90), c3(190, 0, 40), 0.15, 2, 1, { speed = 0.6, up = true, spread = 50 })
	end,
	NebulaEye = function(b) -- nebula bulutu + yıldız
		emit(b, "Neb", O, V.Nebula, c3(210, 120, 255), c3(90, 40, 180), 1.4, 0.6, 1.8, { speed = 0.05, alpha = 0.6, emission = 0.6, spin = 10 })
		emit(b, "Stars", O, V.Star, c3(255, 230, 255), c3(200, 120, 255), 0.18, 1.5, 0.8, { surface = true, speed = 0.2, spin = 140 })
	end,
	VoidShard = function(b) -- içe çekilen boşluk + çatlak kıvılcımı
		emit(b, "Pull", O, V.Wisp, c3(150, 60, 230), c3(30, 0, 60), 1, 1.6, 1, { surface = true, inward = true, speed = 0.4, alpha = 0.45, emission = 0.4 })
		emit(b, "Crack", O, V.Spark, c3(220, 140, 255), c3(140, 40, 255), 0.35, 1.2, 0.2, { surface = true, speed = 0.1, spin = 250 })
	end,

	-- Nebula Egg
	DustBunny = function(b) -- yıldız tozu
		emit(b, "Dust", O, V.Star, c3(255, 220, 245), c3(255, 150, 220), 0.15, 2, 1, { surface = true, speed = 0.2, accel = RISE, spin = 140 })
	end,
	NebSlime = function(b) -- nebula balçık kabarcığı
		emit(b, "Blob", TOP, T("slime", V.Bubble), c3(190, 160, 255), c3(120, 80, 230), 0.22, 1, 1.4, { speed = 0.4, up = true, spread = 35, alpha = 0.3 })
	end,
	WarpDrone = function(b) -- warp halkası
		emit(b, "Warp", O, T("soundwave", V.Ring), c3(150, 240, 255), c3(60, 190, 255), 1.2, 1, 0.6, { speed = 0, grow = 1.6, alpha = 0.45, spin = 0 })
	end,
	CosmoRay = function(b) -- kanattan yıldız izi
		emit(b, "Trail", BACK, V.Star, c3(170, 200, 255), c3(70, 120, 255), 0.18, 2.5, 1, { speed = 0.4, spread = 60, accel = Vector3.new(0, 0, 0.6), spin = 120 })
	end,
	PhantomCrew = function(b) -- pelerinden hayalet buğusu + yıldız
		emit(b, "Cloak", LOW, V.Wisp, c3(210, 190, 255), c3(120, 90, 220), 0.8, 1.4, 1.6, { speed = 0.3, spread = 60, alpha = 0.45, emission = 0.5 })
		emit(b, "Spirit", O, V.Star, c3(240, 230, 255), c3(180, 150, 255), 0.18, 1.5, 1, { surface = true, speed = 0.2, accel = RISE, spin = 140 })
	end,
	StarWhale = function(b) -- sırttan yıldız fıskiyesi + takımyıldızı
		emit(b, "Spout", TOP, V.Star, c3(220, 235, 255), c3(120, 160, 255), 0.22, 3, 1.2, { speed = 1.6, up = true, spread = 20, accel = Vector3.new(0, -2.5, 0), spin = 140 })
		emit(b, "Const", O, T("galaxy", V.Nebula), c3(120, 140, 255), c3(40, 50, 140), 1.4, 0.5, 2, { speed = 0.05, alpha = 0.6, emission = 0.6, spin = 8 })
	end,
	RiftWalker = function(b) -- yarıktan kopan boşluk + mor şimşek
		emit(b, "Rift", O, T("vortex", V.Nebula), c3(170, 80, 255), c3(40, 0, 80), 1.2, 0.8, 1.2, { speed = 0, alpha = 0.5, emission = 0.5, spin = 90 })
		emit(b, "Arc", O, V.Spark, c3(220, 150, 255), c3(140, 40, 255), 0.4, 1.2, 0.2, { surface = true, speed = 0.1, spin = 250 })
	end,

	-- Celestial Egg
	LuckyStar = function(b) -- altın ışıltı
		emit(b, "Lucky", O, V.Star, c3(255, 250, 200), c3(255, 210, 70), 0.2, 2, 0.8, { surface = true, speed = 0.2, spin = 160 })
	end,
	CloverBot = function(b) -- yonca yaprakları
		emit(b, "Clover", TOP, T("leaf", V.Star), c3(170, 255, 170), c3(70, 200, 100), 0.22, 0.8, 1.4, { speed = 0.4, up = true, spread = 40, spin = 60 })
	end,
	FrostSprite = function(b) -- buz kristali + kar
		emit(b, "Ice", O, T("snowflake2", V.Snowflake), c3(230, 250, 255), c3(140, 210, 255), 0.22, 1.6, 1.4, { surface = true, speed = 0.2, accel = Vector3.new(0, -0.4, 0), spin = 90 })
	end,
	SunBeetle = function(b) -- güneş diski ışığı + kor
		emit(b, "Sun", Vector3.new(0, 0.4, 0.3), T("sun", V.Orb), c3(255, 230, 140), c3(255, 160, 40), 0.9, 0.6, 1.2, { speed = 0, alpha = 0.4, spin = 20 })
		emit(b, "Ember", O, V.Ember, c3(255, 220, 130), c3(255, 140, 40), 0.14, 1.5, 1, { surface = true, speed = 0.3, accel = RISE })
	end,
	PrismFox = function(b) -- gökkuşağı kırıkları
		emit(b, "Prism", O, T("shard", V.Crystal), c3(255, 160, 230), c3(120, 255, 235), 0.22, 2, 1.2, { surface = true, speed = 0.3, spin = 90 })
		emit(b, "Glint", O, V.Star, c3(255, 255, 255), c3(160, 255, 240), 0.2, 1.5, 0.6, { surface = true, speed = 0.1, spin = 160 })
	end,
	CometKing = function(b) -- kuyruktan alev + taç parıltısı
		emit(b, "Tail", BACK, V.Flame, c3(255, 200, 170), c3(255, 80, 120), 0.5, 3, 0.6, { speed = 0.6, spread = 20, accel = Vector3.new(0, 0, 1), alpha = 0.15 })
		emit(b, "Crown", TOP, T("crown", V.Star), c3(255, 240, 180), c3(255, 200, 60), 0.3, 0.6, 0.8, { speed = 0.2, up = true, spread = 10, spin = 20 })
	end,
	CelestCore = function(b) -- yörüngede yıldız + çekirdek ışığı
		emit(b, "Orbit", O, T("ringed", V.Ring), c3(150, 255, 240), c3(80, 200, 220), 1.4, 0.6, 1.4, { speed = 0, alpha = 0.5, spin = 30 })
		emit(b, "Stars", O, V.Star, c3(255, 255, 230), c3(110, 250, 230), 0.2, 2.5, 1, { surface = true, speed = 0.3, spin = 160 })
	end,
}

-- ⭐ Starfall Egg (SINIRLI): hepsi yıldız ailesinde, kademe yükseldikçe gösterişli
FX.StarMote = function(b) -- yıldız tozu
	emit(b, "Dust", O, V.Star, c3(230, 240, 255), c3(150, 200, 255), 0.16, 2, 1, { surface = true, speed = 0.2, accel = RISE, spin = 140 })
end
FX.MeteorMole = function(b) -- kabuktan kor + toz
	emit(b, "Ember", TOP, V.Ember, c3(255, 200, 110), c3(255, 100, 30), 0.16, 1.6, 1, { speed = 0.6, up = true, spread = 40 })
	emit(b, "Dust", LOW, V.Dust, c3(150, 120, 100), c3(90, 70, 60), 0.5, 0.6, 1.2, { speed = 0.3, spread = 80, alpha = 0.6, emission = 0.1 })
end
FX.StarOwl = function(b) -- kuyruktan kayan yıldız izi
	emit(b, "Trail", BACK, T("shooting", V.Star), c3(220, 235, 255), c3(255, 210, 100), 0.28, 2.5, 0.9, { speed = 0.6, spread = 25, accel = Vector3.new(0, -0.4, 0.8), spin = 60 })
end
FX.StarDrake = function(b) -- kanatlardan yıldız + mor nebula nefesi
	emit(b, "Stars", O, V.Star, c3(255, 245, 200), c3(150, 120, 255), 0.22, 2.5, 1, { surface = true, speed = 0.3, spin = 160 })
	emit(b, "Breath", Vector3.new(0, 0.2, -0.9), V.Nebula, c3(180, 140, 255), c3(80, 50, 200), 0.8, 1, 0.9, { speed = 0.8, spread = 20, alpha = 0.45, emission = 0.6, spin = 30 })
end
FX.GalaxyCorn = function(b) -- galaksi yelesi + gökkuşağı ışıltısı
	emit(b, "Mane", TOP, T("galaxy", V.Nebula), c3(200, 150, 255), c3(90, 60, 200), 1, 0.8, 1.6, { speed = 0.2, up = true, spread = 40, alpha = 0.5, emission = 0.7, spin = 20 })
	emit(b, "Sparkle", O, V.Star, c3(255, 200, 240), c3(150, 230, 255), 0.2, 3, 0.8, { surface = true, speed = 0.2, spin = 160 })
end
FX.WishStar = function(b) -- dilek: altın yıldız yağmuru + sıcak hale
	emit(b, "Wish", TOP, T("shooting", V.Star), c3(255, 250, 210), c3(255, 210, 90), 0.3, 3, 1.4, { speed = 0.8, spread = 70, accel = Vector3.new(0, -1.2, 0), spin = 140 })
	emit(b, "Halo", O, V.Orb, c3(255, 245, 200), c3(255, 215, 120), 2.2, 0.5, 1.6, { speed = 0, alpha = 0.6 })
end

--[[ Petin tema efektini gövdeye takar (yoksa bir şey yapmaz). ]]
function PetFX.Apply(body: BasePart, petId: string)
	local f = FX[petId]
	if f then
		f(body)
	end
end

function PetFX.Has(petId: string): boolean
	return FX[petId] ~= nil
end

return PetFX
