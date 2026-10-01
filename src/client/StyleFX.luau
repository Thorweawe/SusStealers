--!strict
--[[
	Her şeye kendi tarzında efekt (2026-10-02, Yusuf: "her biri kendi tarzına
	uygun efekt alsın her şey") — tamamen istemcide, ağda bir şey taşınmıyor.

	  gezegenler  — SpaceZone.Planets.PlanetN.Planet (küre yüzeyinden): balçık
	                köpüğü, şeker konfetisi, kum fırtınası, lav koru, kar...
	  jetpackler  — karakterdeki SpaceJetpack (oyuncunun "Jetpack" niteliği) ve
	                Launch Bay vitrinindeki Jetpack_<id>: tankta plazma kıvılcımı,
	                nova yıldızı, pulsar halkası...
	  şapkalar    — karakterdeki CosmeticHat (oyuncunun "HatId" niteliği):
	                filizde yaprak ışıltısı, parti şapkasında konfeti, boynuzda kor...
	  yumurtalar  — kuluçkadaki Egg1..6 (EggStyle'ın süslerine ek): kabuktan
	                tema parçacıkları. Polus/Nebula'nın kendi karı ve tozu duruyor.

	Crewmate'ler UnitModel'de (CREW_FX), canavarlar MonsterModel'de. Hepsi
	aynı Config.Vfx dokularını kullanıyor, o yüzden tarzlar birbirine uyuyor.
	Yayıcılar "SFX_" ile başlıyor; kozmetik değişince eskiler silinip yenisi
	kuruluyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local StyleFX = {}

local V = Config.Vfx
local function c3(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

--[[
	Bir yayıcı tarifi. Boylar/hızlar/konumlar `scale` ile çarpılıyor (gezegen
	yarıçapı, jetpack boyu); renkler ve süreler sabit.
	  at      — ek noktası (parçanın yerel uzayında, ölçeklenir)
	  sphere  — parçanın küre yüzeyinden yay (gezegen, yumurta); inward: içe
	  up/down — yayma yönü yalnızca yukarı / aşağı (spread koni açısı)
	  grow    — ömür sonundaki boy çarpanı (> 1: büyüyerek söner, halka)
	  perp    — hıza dik yassı sprite (yükselen tarama halkası)
]]
type Spec = {
	tex: string,
	c1: Color3,
	c2: Color3,
	size: number,
	rate: number,
	life: number,
	speed: number?,
	spread: number?,
	accel: Vector3?,
	alpha: number?,
	spin: number?,
	grow: number?,
	emission: number?,
	drag: number?,
	at: Vector3?,
	sphere: boolean?,
	inward: boolean?,
	up: boolean?,
	down: boolean?,
	perp: boolean?,
}

local function emit(host: BasePart, name: string, s: Spec, scale: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "SFX_" .. name
	e.Texture = s.tex
	e.Color = ColorSequence.new(s.c1, s.c2)
	e.LightEmission = s.emission or 1
	e.LightInfluence = 0
	local size = s.size * scale
	local g = s.grow or 0.2
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * math.min(0.3, g)),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, size * g),
	})
	local a0 = s.alpha or 0.2
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, a0),
		NumberSequenceKeypoint.new(0.75, a0 + (1 - a0) * 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(s.life * 0.7, s.life * 1.3)
	local sp = (s.speed or 0.3) * scale
	e.Speed = NumberRange.new(sp * 0.5, sp)
	e.SpreadAngle = Vector2.new(s.spread or 180, s.spread or 180)
	e.Acceleration = (s.accel or Vector3.zero) * scale
	e.Drag = s.drag or 0
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-(s.spin or 40), s.spin or 40)
	e.Rate = s.rate
	if s.up then
		e.EmissionDirection = Enum.NormalId.Top
	elseif s.down then
		e.EmissionDirection = Enum.NormalId.Bottom
	end
	if s.perp then
		e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	end
	if s.sphere then
		e.Shape = Enum.ParticleEmitterShape.Sphere
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.ShapeInOut = if s.inward then Enum.ParticleEmitterShapeInOut.Inward else Enum.ParticleEmitterShapeInOut.Outward
		e.Parent = host
	else
		local a = Instance.new("Attachment")
		a.Name = "SFX_" .. name
		a.Position = (s.at or Vector3.zero) * scale
		a.Parent = host
		e.Parent = a
	end
	return e
end

local function clear(host: Instance)
	for _, d in host:GetChildren() do
		if string.sub(d.Name, 1, 4) == "SFX_" then
			d:Destroy()
		end
	end
end

local function apply(host: BasePart, list: { Spec }?, scale: number)
	clear(host)
	if not list then
		return
	end
	for i, s in list do
		emit(host, tostring(i), s, scale)
	end
end

local UP = Vector3.new(0, 1, 0)

-- ─── Gezegenler (Config.SpaceMonsters kimliğiyle; ölçek = yarıçap/44) ───────
--[[
	Uzaktan görünsün diye iri ama seyrek. Açık gezegenlerde (Glacira, Helion)
	ışık yayımı düşük: Batur'un uyarısı, bloom'la beyaza boğuluyordu.
]]
local PLANET: { [string]: { Spec } } = {
	Glorp = { -- Gloopus: balçık köpükleri + yeşil buğu
		{ tex = V.Bubble, c1 = c3(190, 255, 140), c2 = c3(90, 200, 80), size = 4, rate = 6, life = 4, speed = 3, sphere = true, alpha = 0.3 },
		{ tex = V.Wisp, c1 = c3(150, 255, 90), c2 = c3(60, 140, 60), size = 14, rate = 2, life = 5, speed = 1.5, sphere = true, alpha = 0.6, emission = 0.4, spin = 10 },
	},
	Chomper = { -- Candorra: şeker konfetisi + pembe ışıltı
		{ tex = V.Crystal, c1 = c3(255, 140, 210), c2 = c3(140, 220, 255), size = 3, rate = 6, life = 4, speed = 3, sphere = true, spin = 200 },
		{ tex = V.Star, c1 = c3(255, 240, 160), c2 = c3(255, 150, 220), size = 3, rate = 5, life = 2, speed = 1, sphere = true, spin = 120 },
	},
	Kraken = { -- Abyssia: derin deniz kabarcıkları + turkuaz bulut
		{ tex = V.Bubble, c1 = c3(170, 240, 255), c2 = c3(60, 150, 255), size = 3, rate = 8, life = 5, speed = 3, sphere = true, alpha = 0.3 },
		{ tex = V.Nebula, c1 = c3(80, 200, 220), c2 = c3(40, 70, 160), size = 22, rate = 1.2, life = 7, speed = 1, sphere = true, alpha = 0.65, emission = 0.5, spin = 6 },
	},
	SandMaw = { -- Duneveil: savrulan kum fırtınası
		{ tex = V.Dust, c1 = c3(240, 210, 150), c2 = c3(190, 140, 80), size = 16, rate = 4, life = 5, speed = 4, sphere = true, alpha = 0.55, emission = 0.15, accel = Vector3.new(3, 0, 0), spin = 30 },
		{ tex = V.Dust, c1 = c3(255, 230, 180), c2 = c3(220, 170, 100), size = 5, rate = 6, life = 3, speed = 6, sphere = true, alpha = 0.4, emission = 0.2, accel = Vector3.new(6, 0, 0) },
	},
	RiftStalker = { -- Cinderhold: lavdan yükselen kor + alev dilleri
		{ tex = V.Ember, c1 = c3(255, 220, 120), c2 = c3(255, 80, 20), size = 2.5, rate = 12, life = 3, speed = 5, sphere = true },
		{ tex = V.Flame, c1 = c3(255, 200, 100), c2 = c3(220, 40, 10), size = 8, rate = 3, life = 1.4, speed = 3, sphere = true, alpha = 0.15, spin = 30 },
	},
	VoidLeviathan = { -- Umbra Prime: karanlık duman + mor şimşek
		{ tex = V.Wisp, c1 = c3(90, 30, 140), c2 = c3(15, 0, 30), size = 16, rate = 3, life = 5, speed = 2, sphere = true, alpha = 0.5, emission = 0.1, spin = 15 },
		{ tex = V.Spark, c1 = c3(210, 140, 255), c2 = c3(120, 40, 255), size = 6, rate = 2, life = 0.35, speed = 0.5, sphere = true, spin = 200 },
	},
	FrostWyrm = { -- Glacira: kar + buz sisi (düşük ışık)
		{ tex = V.Snowflake, c1 = c3(255, 255, 255), c2 = c3(190, 230, 255), size = 3, rate = 10, life = 5, speed = 2.5, sphere = true, emission = 0.3, spin = 90 },
		{ tex = V.Dust, c1 = c3(230, 245, 255), c2 = c3(160, 210, 255), size = 18, rate = 1.5, life = 6, speed = 1, sphere = true, alpha = 0.7, emission = 0.1 },
	},
	CrystalGolem = { -- Prismara: süzülen kristal kırıkları + ışıltı
		{ tex = V.Crystal, c1 = c3(220, 170, 255), c2 = c3(120, 220, 255), size = 4, rate = 5, life = 5, speed = 2, sphere = true, spin = 60 },
		{ tex = V.Star, c1 = c3(255, 255, 255), c2 = c3(200, 160, 255), size = 4, rate = 6, life = 1, speed = 0.3, sphere = true, spin = 150 },
	},
	SolarPhoenix = { -- Helion: güneş patlamaları + korona (düşük ışık)
		{ tex = V.Flame, c1 = c3(255, 230, 140), c2 = c3(255, 110, 20), size = 12, rate = 3, life = 2, speed = 5, sphere = true, alpha = 0.2, emission = 0.5, spin = 20 },
		{ tex = V.Ember, c1 = c3(255, 240, 170), c2 = c3(255, 150, 40), size = 2.5, rate = 10, life = 3, speed = 7, sphere = true, emission = 0.5 },
	},
	BlackHole = { -- Event Horizon: içine çekilen yıldızlar + yığılma bulutu
		{ tex = V.Star, c1 = c3(255, 210, 150), c2 = c3(170, 90, 255), size = 3, rate = 12, life = 2.5, speed = 8, sphere = true, inward = true, spin = 100 },
		{ tex = V.Nebula, c1 = c3(255, 150, 80), c2 = c3(90, 30, 160), size = 24, rate = 1.2, life = 6, speed = 1, sphere = true, inward = true, alpha = 0.6, emission = 0.6, spin = 25 },
	},
	GalaxyTitan = { -- Titanis: galaksi bulutu + yıldız tozu
		{ tex = V.Nebula, c1 = c3(150, 110, 255), c2 = c3(50, 60, 160), size = 22, rate = 1.5, life = 7, speed = 1.2, sphere = true, alpha = 0.6, emission = 0.7, spin = 8 },
		{ tex = V.Star, c1 = c3(255, 255, 255), c2 = c3(170, 200, 255), size = 3, rate = 10, life = 2.5, speed = 1.5, sphere = true, spin = 140 },
	},
}

-- ─── Jetpackler (Pack parçasına göre; ölçek = Pack genişliği/1.7) ───────────
--[[
	Pack yerel uzayı: tanklar z ≈ +0.6 (sırtın arkası), tank tepesi y ≈ +1.05,
	meme ağzı y ≈ -1.55. İtki alevi JetpackModel/JetFlames'te; bunlar boşta da
	yanan hafif "imza" efektleri.
]]
local TANKS = Vector3.new(0, 0.2, 0.75)
local TOP = Vector3.new(0, 1.15, 0.6)
local NOZ = Vector3.new(0, -1.6, 0.6)
local JETPACK: { [string]: { Spec } } = {
	Starter = {
		{ tex = V.Dust, c1 = c3(200, 200, 205), c2 = c3(140, 140, 150), size = 0.5, rate = 0.8, life = 1.2, speed = 0.6, at = NOZ, down = true, spread = 30, alpha = 0.6, emission = 0.1 },
	},
	Scout = {
		{ tex = V.Star, c1 = c3(255, 255, 255), c2 = c3(255, 120, 120), size = 0.5, rate = 0.8, life = 0.6, speed = 0, at = TOP, spin = 120 },
	},
	Comet = { -- kuyruklu yıldız tozu geriye akıyor
		{ tex = V.Star, c1 = c3(200, 240, 255), c2 = c3(80, 150, 255), size = 0.35, rate = 3, life = 1.2, speed = 1.2, at = TANKS, spread = 25, accel = Vector3.new(0, 0, 1.5), spin = 120 },
		{ tex = V.Snowflake, c1 = c3(230, 250, 255), c2 = c3(140, 210, 255), size = 0.3, rate = 1, life = 1.4, speed = 0.6, at = NOZ, down = true, spread = 40, spin = 90 },
	},
	Plasma = { -- tanklarda yeşil plazma çıtırtısı
		{ tex = V.Spark, c1 = c3(200, 255, 170), c2 = c3(60, 230, 110), size = 0.6, rate = 2.5, life = 0.25, speed = 0.4, at = TANKS, spin = 300 },
		{ tex = V.Bubble, c1 = c3(190, 255, 170), c2 = c3(70, 230, 120), size = 0.25, rate = 1.5, life = 1.4, speed = 0.6, at = TOP, up = true, spread = 30, alpha = 0.3 },
	},
	Nova = { -- sırtta parlayan yıldız çekirdeği
		{ tex = V.Orb, c1 = c3(255, 240, 160), c2 = c3(255, 170, 50), size = 1.4, rate = 0.8, life = 1.4, speed = 0, at = TANKS, alpha = 0.5 },
		{ tex = V.Star, c1 = c3(255, 255, 220), c2 = c3(255, 200, 80), size = 0.6, rate = 1.2, life = 0.7, speed = 0.2, at = TANKS, spin = 140 },
	},
	Pulsar = { -- tanklardan ritimle yayılan mor halka
		{ tex = V.Ring, c1 = c3(230, 170, 255), c2 = c3(150, 70, 255), size = 1.6, rate = 1.2, life = 0.7, speed = 0.01, at = TANKS, grow = 1.5, alpha = 0.45, spin = 0 },
		{ tex = V.Spark, c1 = c3(230, 190, 255), c2 = c3(160, 80, 255), size = 0.4, rate = 1.5, life = 0.25, speed = 0.3, at = TOP, spin = 250 },
	},
	Quasar = { -- tank tepelerinde enerji küresi + kızıl ışın kıvılcımı
		{ tex = V.Orb, c1 = c3(255, 180, 210), c2 = c3(255, 60, 120), size = 1, rate = 1, life = 1, speed = 0, at = TOP, alpha = 0.45 },
		{ tex = V.Spark, c1 = c3(255, 200, 220), c2 = c3(255, 60, 120), size = 0.6, rate = 1.5, life = 0.3, speed = 1.5, at = TOP, up = true, spread = 10, spin = 200 },
	},
	Galaxy = { -- galaksi bulutu + yıldızlar
		{ tex = V.Nebula, c1 = c3(120, 100, 255), c2 = c3(60, 30, 140), size = 1.6, rate = 0.8, life = 2, speed = 0.15, at = TANKS, alpha = 0.55, emission = 0.6, spin = 10 },
		{ tex = V.Star, c1 = c3(255, 255, 255), c2 = c3(120, 230, 255), size = 0.35, rate = 2, life = 1.4, speed = 0.4, at = TANKS, spin = 120 },
	},
	NebulaJet = {
		{ tex = V.Nebula, c1 = c3(255, 150, 230), c2 = c3(150, 70, 230), size = 1.8, rate = 0.9, life = 2.2, speed = 0.15, at = TANKS, alpha = 0.55, emission = 0.6, spin = 10 },
		{ tex = V.Star, c1 = c3(255, 220, 250), c2 = c3(200, 120, 255), size = 0.35, rate = 2, life = 1.4, speed = 0.4, at = TANKS, spin = 120 },
	},
	Stellar = { -- altın yıldız yağmuru + beyaz ışık
		{ tex = V.Star, c1 = c3(255, 250, 210), c2 = c3(255, 200, 60), size = 0.45, rate = 2.5, life = 1.6, speed = 0.5, at = TOP, accel = Vector3.new(0, -1, 0), spin = 140 },
		{ tex = V.Orb, c1 = c3(255, 255, 240), c2 = c3(255, 220, 140), size = 1.4, rate = 0.7, life = 1.6, speed = 0, at = TANKS, alpha = 0.55 },
	},
	Supernova = { -- patlayan yıldız: kor + şok halkası
		{ tex = V.Ember, c1 = c3(255, 220, 120), c2 = c3(255, 60, 30), size = 0.3, rate = 4, life = 1, speed = 1.5, at = TANKS, spread = 120 },
		{ tex = V.Ring, c1 = c3(255, 200, 120), c2 = c3(255, 70, 30), size = 1.8, rate = 0.6, life = 0.6, speed = 0.01, at = TANKS, grow = 1.8, alpha = 0.4, spin = 0 },
	},
	CosmicJet = { -- gökkuşağı kristalleri + nebula + yıldız
		{ tex = V.Crystal, c1 = c3(150, 255, 240), c2 = c3(200, 120, 255), size = 0.4, rate = 2, life = 1.6, speed = 0.5, at = TANKS, spin = 160 },
		{ tex = V.Nebula, c1 = c3(110, 250, 230), c2 = c3(60, 60, 200), size = 2, rate = 0.8, life = 2.4, speed = 0.15, at = TANKS, alpha = 0.6, emission = 0.6, spin = 8 },
		{ tex = V.Star, c1 = c3(255, 255, 255), c2 = c3(150, 255, 240), size = 0.4, rate = 2, life = 1.2, speed = 0.4, at = TOP, spin = 140 },
	},
}

-- ─── Şapkalar (şapkanın tepesine göre; ölçek 1, kafa ~1.2 stud) ─────────────
local HTOP = Vector3.zero -- şapka sınır kutusunun tepesi (attachHat ekliyor)
local HAT: { [string]: { Spec } } = {
	Sprout = { -- yaprak ışıltısı
		{ tex = V.Star, c1 = c3(190, 255, 140), c2 = c3(90, 200, 80), size = 0.25, rate = 0.8, life = 1.2, speed = 0.4, at = HTOP, up = true, spread = 30 },
	},
	PartyHat = { -- tepeden fışkıran konfeti
		{ tex = V.Crystal, c1 = c3(255, 120, 220), c2 = c3(120, 230, 255), size = 0.2, rate = 2, life = 1.4, speed = 1.4, at = HTOP, up = true, spread = 35, accel = Vector3.new(0, -3, 0), spin = 300 },
	},
	ToiletPaper = { -- savrulan kâğıt tozu
		{ tex = V.Dust, c1 = c3(255, 255, 255), c2 = c3(220, 225, 235), size = 0.4, rate = 0.8, life = 1.4, speed = 0.4, at = HTOP, alpha = 0.5, emission = 0.2 },
	},
	Antenna = { -- uçta sinyal: kıvılcım + yayılan halka
		{ tex = V.Spark, c1 = c3(255, 200, 200), c2 = c3(255, 60, 60), size = 0.3, rate = 1.5, life = 0.25, speed = 0.2, at = HTOP, spin = 250 },
		{ tex = V.Ring, c1 = c3(255, 120, 120), c2 = c3(255, 40, 40), size = 0.8, rate = 0.8, life = 0.7, speed = 0.01, at = HTOP, grow = 1.6, alpha = 0.5, spin = 0 },
	},
	FriedEgg = { -- tavadan yeni çıkmış buhar
		{ tex = V.Wisp, c1 = c3(255, 255, 255), c2 = c3(230, 230, 230), size = 0.6, rate = 1.2, life = 1.4, speed = 0.6, at = HTOP, up = true, spread = 20, alpha = 0.6, emission = 0.2 },
	},
	ChefHat = { -- mutfak buharı + ışıltı
		{ tex = V.Wisp, c1 = c3(255, 255, 255), c2 = c3(235, 235, 240), size = 0.7, rate = 1, life = 1.6, speed = 0.5, at = HTOP, up = true, spread = 20, alpha = 0.6, emission = 0.2 },
		{ tex = V.Star, c1 = c3(255, 250, 220), c2 = c3(255, 220, 140), size = 0.25, rate = 0.6, life = 0.6, speed = 0, at = HTOP, spin = 120 },
	},
	TrafficCone = { -- tepede yanıp sönen turuncu uyarı ışığı
		{ tex = V.Orb, c1 = c3(255, 190, 90), c2 = c3(255, 110, 20), size = 0.7, rate = 1.5, life = 0.4, speed = 0, at = HTOP, alpha = 0.3 },
	},
	Horns = { -- boynuzlardan yükselen kızıl kor
		{ tex = V.Ember, c1 = c3(255, 120, 90), c2 = c3(200, 0, 30), size = 0.2, rate = 2, life = 1, speed = 0.8, at = HTOP, up = true, spread = 50 },
		{ tex = V.Wisp, c1 = c3(120, 0, 20), c2 = c3(30, 0, 0), size = 0.6, rate = 0.8, life = 1.4, speed = 0.3, at = HTOP, up = true, spread = 40, alpha = 0.5, emission = 0.1 },
	},
	Crown = { -- altın parıltılar
		{ tex = V.Star, c1 = c3(255, 250, 200), c2 = c3(255, 200, 60), size = 0.35, rate = 1.5, life = 0.6, speed = 0.1, at = HTOP + Vector3.new(0, -0.2, 0), spin = 150 },
	},
	Halo = { -- yumuşak kutsal ışık + süzülen ışıltı
		{ tex = V.Orb, c1 = c3(255, 245, 190), c2 = c3(255, 220, 120), size = 1.4, rate = 0.6, life = 1.6, speed = 0, at = HTOP, alpha = 0.6, spin = 10 },
		{ tex = V.Star, c1 = c3(255, 255, 255), c2 = c3(255, 230, 150), size = 0.2, rate = 1, life = 1.6, speed = 0.3, at = HTOP, accel = Vector3.new(0, -0.4, 0) },
	},
	NebulaCrown = {
		{ tex = V.Nebula, c1 = c3(255, 150, 230), c2 = c3(140, 70, 230), size = 1.2, rate = 0.7, life = 2, speed = 0.1, at = HTOP, alpha = 0.55, emission = 0.6, spin = 10 },
		{ tex = V.Star, c1 = c3(255, 230, 250), c2 = c3(200, 130, 255), size = 0.25, rate = 1.5, life = 1.2, speed = 0.3, at = HTOP, spin = 140 },
	},
	OrbitRings = { -- yörüngede ışıltı + yatay halka
		{ tex = V.Ring, c1 = c3(150, 255, 240), c2 = c3(80, 200, 255), size = 1.6, rate = 0.6, life = 1.2, speed = 0.4, at = HTOP + Vector3.new(0, -0.3, 0), up = true, spread = 0, grow = 1.1, alpha = 0.5, spin = 0, perp = true },
		{ tex = V.Star, c1 = c3(255, 255, 255), c2 = c3(150, 255, 240), size = 0.25, rate = 1.5, life = 1, speed = 0.6, at = HTOP, spin = 140 },
	},
	-- Sınırlı (etkinlik) şapkaları
	StarVisor = {
		{ tex = V.Star, c1 = c3(220, 245, 255), c2 = c3(120, 210, 255), size = 0.35, rate = 1.5, life = 0.7, speed = 0.2, at = HTOP, spin = 150 },
	},
	CometCrown = { -- tacın arkasından akan kuyruklu yıldız tozu
		{ tex = V.Star, c1 = c3(255, 245, 200), c2 = c3(255, 200, 90), size = 0.3, rate = 2.5, life = 1, speed = 0.8, at = HTOP, spread = 30, accel = Vector3.new(0, 0, 1.2), spin = 140 },
	},
	GalaxyHalo = {
		{ tex = V.Nebula, c1 = c3(190, 140, 255), c2 = c3(80, 50, 170), size = 1.2, rate = 0.7, life = 2, speed = 0.1, at = HTOP, alpha = 0.55, emission = 0.6, spin = 10 },
		{ tex = V.Star, c1 = c3(255, 255, 255), c2 = c3(190, 140, 255), size = 0.25, rate = 1.5, life = 1.2, speed = 0.3, at = HTOP, spin = 140 },
	},
	PumpkinHead = { -- balkabağından mum alevi ve kor
		{ tex = V.Ember, c1 = c3(255, 210, 110), c2 = c3(255, 110, 20), size = 0.2, rate = 1.5, life = 1, speed = 0.6, at = HTOP, up = true, spread = 40 },
	},
	WitchHat = { -- mor büyü ışıltısı
		{ tex = V.Star, c1 = c3(200, 150, 255), c2 = c3(110, 50, 200), size = 0.3, rate = 1.5, life = 1.2, speed = 0.4, at = HTOP, spin = 160 },
		{ tex = V.Wisp, c1 = c3(150, 80, 230), c2 = c3(60, 20, 110), size = 0.6, rate = 0.6, life = 1.6, speed = 0.3, at = HTOP, up = true, spread = 40, alpha = 0.5, emission = 0.4 },
	},
	CandyCrown = {
		{ tex = V.Crystal, c1 = c3(255, 120, 150), c2 = c3(255, 230, 240), size = 0.25, rate = 1.2, life = 1.2, speed = 0.4, at = HTOP, spin = 200 },
	},
}

-- ─── Yumurtalar (kuluçka Egg1..6; ölçek = boy/6) ────────────────────────────
local EGG: { [string]: { Spec } } = {
	SupplyEgg = { -- kargo: turuncu kıvılcım + toz
		{ tex = V.Spark, c1 = c3(255, 220, 150), c2 = c3(255, 140, 40), size = 0.6, rate = 1, life = 0.3, speed = 0.2, sphere = true, spin = 250 },
		{ tex = V.Dust, c1 = c3(220, 210, 200), c2 = c3(170, 160, 150), size = 1.4, rate = 1, life = 2, speed = 0.4, at = Vector3.new(0, -3, 0), spread = 80, alpha = 0.6, emission = 0.1 },
	},
	SkeldEgg = { -- gemi: lombozda mavi ışık + perçin parlaması
		{ tex = V.Orb, c1 = c3(140, 210, 255), c2 = c3(60, 140, 255), size = 1.2, rate = 0.8, life = 1.4, speed = 0, sphere = true, alpha = 0.5 },
		{ tex = V.Star, c1 = c3(255, 255, 255), c2 = c3(255, 200, 120), size = 0.6, rate = 1.2, life = 0.6, speed = 0, sphere = true, spin = 140 },
	},
	PolusEgg = { -- buz kristalleri (kar EggStyle'da)
		{ tex = V.Crystal, c1 = c3(220, 245, 255), c2 = c3(120, 190, 255), size = 0.6, rate = 1.5, life = 1.6, speed = 0.3, sphere = true, spin = 60 },
	},
	VoidEgg = { -- boşluğa çekilen mor duman + çatlak kıvılcımı
		{ tex = V.Wisp, c1 = c3(170, 60, 255), c2 = c3(40, 0, 80), size = 2, rate = 2, life = 1.4, speed = 2, sphere = true, inward = true, alpha = 0.45, emission = 0.4 },
		{ tex = V.Spark, c1 = c3(255, 140, 255), c2 = c3(190, 40, 255), size = 0.7, rate = 1.2, life = 0.25, speed = 0.1, sphere = true, spin = 250 },
	},
	NebulaEgg = { -- nebula bulutu (toz EggStyle'da)
		{ tex = V.Nebula, c1 = c3(255, 140, 220), c2 = c3(110, 80, 230), size = 3.5, rate = 0.8, life = 3, speed = 0.3, sphere = true, alpha = 0.6, emission = 0.6, spin = 10 },
	},
	CelestialEgg = { -- altın yıldızlar + kutsal ışık
		{ tex = V.Star, c1 = c3(255, 250, 210), c2 = c3(255, 210, 90), size = 0.6, rate = 3, life = 1.6, speed = 0.6, sphere = true, spin = 140 },
		{ tex = V.Orb, c1 = c3(200, 255, 245), c2 = c3(110, 250, 230), size = 2, rate = 0.8, life = 2, speed = 0, sphere = true, alpha = 0.6 },
	},
}

-- ─── Takma ──────────────────────────────────────────────────────────────────
local function jetpackFx(model: Model, id: string?)
	local pack = model:FindFirstChild("Pack")
	if not (pack and pack:IsA("BasePart")) then
		return
	end
	apply(pack, if id then JETPACK[id] else nil, pack.Size.X / 1.7)
end

local function hatFx(hat: Model, id: string?)
	local base = hat.PrimaryPart
	if not base then
		return
	end
	local list = if id then HAT[id] else nil
	clear(base)
	if not list then
		return
	end
	-- Ek noktaları sınır kutusunun tepesinden (her şapkanın boyu farklı)
	local cf, size = hat:GetBoundingBox()
	local top = base.CFrame:PointToObjectSpace(cf.Position + cf.UpVector * size.Y / 2)
	for i, s in list do
		local e = emit(base, tostring(i), s, 1)
		local a = e.Parent
		if a and a:IsA("Attachment") then
			a.Position = top + (s.at or Vector3.zero)
		end
	end
end

local function watchCharacter(player: Player, character: Model)
	local function refresh()
		local pack = character:FindFirstChild("SpaceJetpack")
		if pack and pack:IsA("Model") then
			jetpackFx(pack, player:GetAttribute("Jetpack") :: string?)
		end
		local hat = character:FindFirstChild("CosmeticHat")
		if hat and hat:IsA("Model") then
			hatFx(hat, player:GetAttribute("HatId") :: string?)
		end
	end
	character.ChildAdded:Connect(function(child: Instance)
		if child.Name == "SpaceJetpack" or child.Name == "CosmeticHat" then
			-- Parçalar ve nitelik aynı karede gelmeyebilir
			task.delay(0.2, refresh)
		end
	end)
	refresh()
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		watchCharacter(player, character)
	end)
	if player.Character then
		watchCharacter(player, player.Character)
	end
	local function onAttr()
		local character = player.Character
		if not character then
			return
		end
		task.delay(0.2, function()
			local pack = character:FindFirstChild("SpaceJetpack")
			if pack and pack:IsA("Model") then
				jetpackFx(pack, player:GetAttribute("Jetpack") :: string?)
			end
			local hat = character:FindFirstChild("CosmeticHat")
			if hat and hat:IsA("Model") then
				hatFx(hat, player:GetAttribute("HatId") :: string?)
			end
		end)
	end
	player:GetAttributeChangedSignal("Jetpack"):Connect(onAttr)
	player:GetAttributeChangedSignal("HatId"):Connect(onAttr)
end

local function planets()
	local zone = workspace:WaitForChild("SpaceZone", 60)
	local folder = zone and zone:WaitForChild("Planets", 30)
	if not folder then
		return
	end
	local function one(model: Instance)
		local index = tonumber(string.match(model.Name, "^Planet(%d+)$"))
		local def = index and Config.SpaceMonsters[index]
		local sphere = model:WaitForChild("Planet", 10)
		if def and sphere and sphere:IsA("BasePart") then
			apply(sphere, PLANET[def.id], sphere.Size.X / 2 / 44)
		end
	end
	for _, m in folder:GetChildren() do
		task.spawn(one, m)
	end
	folder.ChildAdded:Connect(function(m: Instance)
		task.spawn(one, m)
	end)
end

local function eggs()
	local decor = workspace:WaitForChild("Decor", 30)
	local hatchery: Instance? = nil
	for _ = 1, 60 do
		hatchery = decor and decor:FindFirstChild("Hatchery", true)
		if hatchery then
			break
		end
		task.wait(0.5)
	end
	if not hatchery then
		return
	end
	for index, def in Config.Eggs do
		local egg = hatchery:FindFirstChild("Egg" .. index)
		if egg and egg:IsA("BasePart") then
			apply(egg, EGG[def.id], egg.Size.Y / 6)
		end
	end
end

local function displays()
	-- Launch Bay vitrinindeki jetpackler (sunucu kuruyor, ad Jetpack_<id>)
	local function check(d: Instance)
		if d:IsA("Model") and string.sub(d.Name, 1, 8) == "Jetpack_" then
			task.defer(jetpackFx, d, string.sub(d.Name, 9))
		end
	end
	for _, d in workspace:GetDescendants() do
		check(d)
	end
	workspace.DescendantAdded:Connect(check)
end

function StyleFX.Start()
	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	task.spawn(planets)
	task.spawn(eggs)
	task.spawn(displays)
end

return StyleFX
