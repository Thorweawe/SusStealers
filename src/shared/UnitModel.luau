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
	═══ KARAKTERE ÖZEL AKSESUAR ════════════════════════════════════════════

	Eskiden karakterleri yalnızca tulum rengi ve NADİRLİK şapkası ayırıyordu:
	aynı kademedeki dört karakter (Engineer, Scientist, Janitor, Guardian)
	aynı kepi takmış, renkleri dışında birebir aynıydı; indekste de hepsi
	aynı fasulyeydi ("çok sıradan"). Artık her karakterin adını anlatan
	kendi eşyası var. Bazıları nadirlik şapkasının YERİNE geçiyor
	(noHat: Sheriff'in kovboy şapkası, Jester'ın soytarı külahı).

	Ölçü rehberi (model yerel, ayak tabanı y=0, yüz -Z'de):
	  kafa merkezi (0, 3.0, 0) yarıçap ~1.03 · vizör önü z ≈ -1.1
	  gövde merkezi (0, 1.85, 0) · sırt çantası (0, 2.05, 1.18)
	  sağ el yanı x ≈ +1.15, sol el yanı x ≈ -1.15
]]
type Kit = {
	part: (name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?) -> Part,
	ball: (name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?) -> Part,
	cyl: (name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?) -> Part,
	body: Part,
	head: Part,
	visor: Part,
	rim: Part,
	pack: Part,
	color: Color3,
}

local METAL = Color3.fromRGB(198, 206, 214)
local DARK = Color3.fromRGB(26, 28, 34)
local WHITE = Color3.fromRGB(245, 245, 250)
local GOLD = Color3.fromRGB(255, 200, 50)
local WOOD = Color3.fromRGB(120, 80, 45)

-- Küçük yardımcı: bir mürettebat daha (Lime'ın pet mürettebatı, Double/Triple)
local function miniCrew(k: Kit, prefix: string, at: CFrame, scale: number, color: Color3)
	k.part(prefix .. "Body", Vector3.new(2.05, 2.5, 2.0) * scale, at * CFrame.new(0, 1.85 * scale, 0), color)
	k.ball(prefix .. "Head", Vector3.new(2.05, 2.05, 2.05) * scale, at * CFrame.new(0, 3.0 * scale, 0), color)
	k.ball(prefix .. "Visor", Vector3.new(1.46, 0.88, 0.6) * scale, at * CFrame.new(0.12 * scale, 3.04 * scale, -0.8 * scale),
		Color3.fromRGB(150, 216, 240), Enum.Material.Glass)
	k.part(prefix .. "Pack", Vector3.new(0.85, 1.9, 0.95) * scale, at * CFrame.new(0, 2.05 * scale, 1.18 * scale), color:Lerp(Color3.new(0, 0, 0), 0.12))
end

local EXTRAS: { [string]: { noHat: boolean?, build: (k: Kit) -> () } } = {
	-- ── Common: küçük ama tanınır eşyalar ────────────────────────────────
	RedCrew = { build = function(k)
		-- Filiz (Among Us'ın meşhur yaprak şapkası)
		k.cyl("Sprout", Vector3.new(0.7, 0.14, 0.14), CFrame.new(0, 4.3, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(80, 170, 60))
		for _, sx in { -1, 1 } do
			k.ball("SproutLeaf", Vector3.new(0.75, 0.16, 0.42), CFrame.new(sx * 0.32, 4.62, 0) * CFrame.Angles(0, 0, math.rad(sx * 25)),
				Color3.fromRGB(100, 210, 80))
		end
	end },
	BlueCrew = { build = function(k)
		-- Kulaklık: kafa bandı, iki kulaklık, mikrofon
		k.part("HeadsetBand", Vector3.new(2.25, 0.2, 0.3), CFrame.new(0, 4.02, 0.1), DARK)
		for _, sx in { -1, 1 } do
			k.cyl("HeadsetCup", Vector3.new(0.3, 0.72, 0.72), CFrame.new(sx * 1.08, 3.1, 0.1), DARK)
			k.cyl("HeadsetPad", Vector3.new(0.08, 0.5, 0.5), CFrame.new(sx * 1.25, 3.1, 0.1), Color3.fromRGB(60, 140, 255), Enum.Material.Neon)
		end
		k.part("HeadsetMic", Vector3.new(0.12, 0.12, 0.9), CFrame.new(-1.0, 2.8, -0.45) * CFrame.Angles(0, math.rad(-20), 0), DARK)
		k.ball("HeadsetMicTip", Vector3.new(0.26, 0.26, 0.26), CFrame.new(-0.85, 2.8, -0.9), DARK)
	end },
	YellowCrew = { build = function(k)
		-- Güneş gözlüğü vizörün üstünde
		k.part("ShadesBar", Vector3.new(1.7, 0.14, 0.12), CFrame.new(0.12, 3.28, -1.12), DARK)
		for _, sx in { -1, 1 } do
			k.ball("ShadesLens", Vector3.new(0.62, 0.42, 0.14), CFrame.new(0.12 + sx * 0.4, 3.1, -1.14), Color3.fromRGB(20, 20, 30), Enum.Material.Glass)
		end
	end },
	LimeCrew = { build = function(k)
		-- Yanında minik pet mürettebat
		miniCrew(k, "MiniPet", CFrame.new(1.45, 0, 0.3) * CFrame.Angles(0, math.rad(-20), 0), 0.32, Color3.fromRGB(255, 140, 190))
	end },

	-- ── Uncommon ──────────────────────────────────────────────────────────
	Engineer = { build = function(k)
		-- Alet kemeri ve elinde İngiliz anahtarı
		k.cyl("ToolBelt", Vector3.new(0.34, 2.18, 2.12), CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(90, 60, 30))
		k.part("BeltPouch", Vector3.new(0.5, 0.5, 0.35), CFrame.new(-0.6, 1.1, -1.02), Color3.fromRGB(120, 85, 45))
		k.part("WrenchHandle", Vector3.new(0.22, 1.5, 0.22), CFrame.new(1.2, 1.9, -0.3) * CFrame.Angles(0, 0, math.rad(-18)), METAL)
		k.part("WrenchJaw", Vector3.new(0.6, 0.3, 0.22), CFrame.new(1.42, 2.65, -0.3) * CFrame.Angles(0, 0, math.rad(-18)), METAL)
	end },
	Scientist = { build = function(k)
		-- Laboratuvar önlüğü yakası, gözlük ve elde tüp
		k.part("LabCoat", Vector3.new(2.12, 1.5, 0.12), CFrame.new(0, 1.7, -0.98), WHITE)
		k.part("LabCoatSplit", Vector3.new(0.08, 1.5, 0.14), CFrame.new(0, 1.7, -1.0), Color3.fromRGB(200, 200, 210))
		k.part("GogglesBand", Vector3.new(2.15, 0.16, 2.15), CFrame.new(0, 3.62, 0), DARK)
		k.cyl("Goggle", Vector3.new(0.2, 0.55, 0.55), CFrame.new(-0.35, 3.62, -1.0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(120, 255, 170), Enum.Material.Glass)
		k.cyl("Goggle", Vector3.new(0.2, 0.55, 0.55), CFrame.new(0.35, 3.62, -1.0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(120, 255, 170), Enum.Material.Glass)
		k.cyl("TestTube", Vector3.new(0.9, 0.26, 0.26), CFrame.new(1.2, 1.8, -0.3) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(90, 255, 120), Enum.Material.Neon)
	end },
	Janitor = { build = function(k)
		-- Elinde paspas, başında bandana
		k.part("MopStick", Vector3.new(0.2, 4.2, 0.2), CFrame.new(1.25, 2.1, -0.2) * CFrame.Angles(0, 0, math.rad(-8)), WOOD)
		k.part("MopHead", Vector3.new(0.9, 0.4, 0.7), CFrame.new(1.05, 0.2, -0.2), Color3.fromRGB(210, 210, 190))
		k.part("Bandana", Vector3.new(2.14, 0.4, 2.14), CFrame.new(0, 3.72, 0), Color3.fromRGB(60, 100, 200))
		k.ball("BandanaKnot", Vector3.new(0.4, 0.4, 0.5), CFrame.new(0, 3.72, 1.1), Color3.fromRGB(60, 100, 200))
	end },
	Guardian = { noHat = true, build = function(k)
		-- Hale ve kanatlar
		local halo = k.cyl("Halo", Vector3.new(0.14, 1.6, 1.6), CFrame.new(0, 4.5, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Neon)
		halo.Transparency = 0.1
		for _, sx in { -1, 1 } do
			k.ball("Wing", Vector3.new(0.3, 1.9, 1.2), CFrame.new(sx * 0.75, 2.5, 1.5) * CFrame.Angles(math.rad(-15), 0, math.rad(sx * 35)), WHITE)
			k.ball("WingTip", Vector3.new(0.25, 1.2, 0.8), CFrame.new(sx * 1.3, 3.1, 1.6) * CFrame.Angles(math.rad(-15), 0, math.rad(sx * 55)), WHITE)
		end
	end },

	-- ── Rare ──────────────────────────────────────────────────────────────
	Shapeshift = { build = function(k)
		-- Yarısı başka renk: ikinci kimliğin maskesi, ellerinde duman
		k.ball("MaskHalf", Vector3.new(1.0, 0.95, 0.3), CFrame.new(-0.42, 3.0, -1.0), Color3.fromRGB(240, 240, 250))
		k.ball("MaskEye", Vector3.new(0.22, 0.12, 0.08), CFrame.new(-0.45, 3.1, -1.16), DARK)
		for i = 1, 3 do
			local puff = k.ball("Smoke", Vector3.new(0.6, 0.6, 0.6) * (1 - i * 0.15), CFrame.new(1.25, 1.2 + i * 0.45, -0.2), Color3.fromRGB(170, 120, 230))
			puff.Transparency = 0.25 + i * 0.15
		end
	end },
	VentCrawler = { build = function(k)
		-- Omzunda vent ızgarası, gövdesinde toz
		k.part("VentGrate", Vector3.new(1.4, 0.14, 1.0), CFrame.new(1.0, 3.9, 0.3) * CFrame.Angles(0, 0, math.rad(-28)), METAL)
		for i = -1, 1 do
			k.part("VentSlot", Vector3.new(1.2, 0.16, 0.1), CFrame.new(1.0, 3.9, 0.3) * CFrame.Angles(0, 0, math.rad(-28)) * CFrame.new(0, 0.02, i * 0.28), DARK)
		end
		for _, spot in { { -0.6, 1.3 }, { 0.5, 2.3 }, { -0.2, 0.6 } } do
			k.ball("Dust", Vector3.new(0.45, 0.35, 0.1), CFrame.new(spot[1], spot[2], -1.0), Color3.fromRGB(40, 44, 50))
		end
	end },
	MedbayScan = { build = function(k)
		-- Gövdeyi saran tarama halkası ve göğüste artı
		local ring = k.cyl("ScanRing", Vector3.new(0.12, 3.0, 3.0), CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(90, 255, 150), Enum.Material.Neon)
		ring.Transparency = 0.3
		k.part("CrossV", Vector3.new(0.22, 0.7, 0.1), CFrame.new(0, 1.9, -1.02), Color3.fromRGB(240, 60, 60))
		k.part("CrossH", Vector3.new(0.7, 0.22, 0.1), CFrame.new(0, 1.9, -1.02), Color3.fromRGB(240, 60, 60))
	end },
	Sheriff = { noHat = true, build = function(k)
		-- Kovboy şapkası ve yıldız rozet
		k.cyl("CowboyBrim", Vector3.new(0.14, 3.0, 3.0), CFrame.new(0, 3.95, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(130, 85, 40))
		k.part("CowboyCrown", Vector3.new(1.5, 0.95, 1.4), CFrame.new(0, 4.45, 0), Color3.fromRGB(140, 92, 45))
		k.part("CowboyDent", Vector3.new(0.3, 0.2, 1.42), CFrame.new(0, 4.9, 0), Color3.fromRGB(110, 70, 34))
		k.part("CowboyBand", Vector3.new(1.54, 0.2, 1.44), CFrame.new(0, 4.08, 0), DARK)
		local star = k.part("SheriffStar", Vector3.new(0.5, 0.5, 0.1), CFrame.new(-0.45, 2.1, -1.02) * CFrame.Angles(0, 0, math.rad(45)), GOLD, Enum.Material.Neon)
		star.Transparency = 0.05
		k.part("SheriffStar2", Vector3.new(0.5, 0.5, 0.1), CFrame.new(-0.45, 2.1, -1.03), GOLD)
	end },

	-- ── Epic ──────────────────────────────────────────────────────────────
	Impostor = { build = function(k)
		-- Kırmızı parlayan vizör ve bıçak
		k.visor.Color = Color3.fromRGB(255, 40, 40)
		k.visor.Material = Enum.Material.Neon
		k.part("KnifeBlade", Vector3.new(0.12, 1.1, 0.34), CFrame.new(1.25, 2.3, -0.4) * CFrame.Angles(0, 0, math.rad(-12)), METAL, Enum.Material.Metal)
		k.part("KnifeHandle", Vector3.new(0.2, 0.55, 0.3), CFrame.new(1.15, 1.55, -0.4) * CFrame.Angles(0, 0, math.rad(-12)), DARK)
	end },
	Reactor = { build = function(k)
		-- Sırtta parlayan çekirdek, gövdede tehlike şeritleri
		k.pack.Color = Color3.fromRGB(60, 60, 64)
		local core = k.ball("ReactorCore", Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, 2.3, 1.62), Color3.fromRGB(255, 150, 40), Enum.Material.Neon)
		core.Transparency = 0.05
		for i = 0, 2 do
			k.part("Hazard", Vector3.new(2.1, 0.2, 0.1), CFrame.new(0, 1.0 + i * 0.12, -1.0) * CFrame.Angles(0, 0, math.rad(25)) * CFrame.new(-0.6 + i * 0.6, 0, 0),
				if i % 2 == 0 then GOLD else DARK)
		end
	end },
	O2Sabotage = { build = function(k)
		-- Oksijen tüpü ve maske hortumu
		k.pack.Transparency = 1
		k.cyl("O2Tank", Vector3.new(2.1, 0.8, 0.8), CFrame.new(0, 2.1, 1.28) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(80, 170, 240))
		k.cyl("O2Valve", Vector3.new(0.3, 0.36, 0.36), CFrame.new(0, 3.3, 1.28) * CFrame.Angles(0, 0, math.rad(90)), METAL)
		k.part("O2Hose", Vector3.new(0.14, 0.14, 2.4), CFrame.new(0.95, 2.9, 0.1) * CFrame.Angles(math.rad(-10), 0, 0), DARK)
		k.ball("O2Mask", Vector3.new(0.7, 0.5, 0.3), CFrame.new(0.4, 2.6, -1.05), Color3.fromRGB(230, 235, 240))
	end },
	Emergency = { noHat = true, build = function(k)
		-- Kafasında acil durum düğmesi (cam fanus içinde)
		k.cyl("ButtonBase", Vector3.new(0.4, 1.6, 1.6), CFrame.new(0, 3.95, 0) * CFrame.Angles(0, 0, math.rad(90)), METAL)
		k.ball("RedButton", Vector3.new(1.1, 0.7, 1.1), CFrame.new(0, 4.25, 0), Color3.fromRGB(230, 30, 30), Enum.Material.Neon)
		local dome = k.ball("ButtonDome", Vector3.new(1.5, 1.2, 1.5), CFrame.new(0, 4.3, 0), Color3.fromRGB(200, 230, 255), Enum.Material.Glass)
		dome.Transparency = 0.55
	end },

	-- ── Legendary ─────────────────────────────────────────────────────────
	Ejected = { build = function(k)
		-- Etrafında yıldızlar ve yörünge halkası (uzaya atıldı)
		local ring = k.cyl("Orbit", Vector3.new(0.1, 4.2, 4.2), CFrame.new(0, 2.4, 0) * CFrame.Angles(math.rad(15), 0, math.rad(90)), Color3.fromRGB(200, 210, 255), Enum.Material.Neon)
		ring.Transparency = 0.35
		for i = 1, 5 do
			local a = i * math.pi * 2 / 5
			k.ball("Star", Vector3.new(0.28, 0.28, 0.28), CFrame.new(math.cos(a) * 2.0, 2.4 + math.sin(a * 2) * 0.4, math.sin(a) * 2.0),
				Color3.fromRGB(255, 250, 200), Enum.Material.Neon)
		end
	end },
	Polus = { build = function(k)
		-- Omuzlarda kar, gövdeden sarkan buz sarkıtları, atkı
		k.ball("Snow", Vector3.new(2.3, 0.5, 2.2), CFrame.new(0, 3.85, 0), Color3.fromRGB(245, 250, 255))
		k.cyl("Scarf", Vector3.new(0.45, 2.18, 2.12), CFrame.new(0, 2.55, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(80, 160, 230))
		k.part("ScarfTail", Vector3.new(0.4, 1.0, 0.2), CFrame.new(0.5, 2.0, -1.05), Color3.fromRGB(80, 160, 230))
		for i = -1, 1 do
			k.part("Icicle", Vector3.new(0.18, 0.5 - math.abs(i) * 0.12, 0.18), CFrame.new(i * 0.6, 0.95, -0.98), Color3.fromRGB(190, 230, 255), Enum.Material.Glass)
		end
	end },
	TheSkeld = { build = function(k)
		-- Sırtında mini roket, alevli iticiler
		k.pack.Transparency = 1
		k.cyl("Rocket", Vector3.new(2.0, 0.9, 0.9), CFrame.new(0, 2.3, 1.3) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(220, 225, 235))
		k.ball("RocketNose", Vector3.new(0.9, 0.9, 0.9), CFrame.new(0, 3.3, 1.3), Color3.fromRGB(230, 60, 60))
		for _, sx in { -1, 1 } do
			k.part("RocketFin", Vector3.new(0.12, 0.6, 0.5), CFrame.new(sx * 0.5, 1.45, 1.3), Color3.fromRGB(230, 60, 60))
		end
		local flame = k.ball("Thrust", Vector3.new(0.6, 0.9, 0.6), CFrame.new(0, 1.0, 1.3), Color3.fromRGB(255, 170, 40), Enum.Material.Neon)
		flame.Transparency = 0.15
	end },
	Airship = { noHat = true, build = function(k)
		-- Pervaneli şapka ve pilot gözlüğü
		k.ball("PropCap", Vector3.new(1.9, 1.0, 1.9), CFrame.new(0, 3.85, 0), Color3.fromRGB(150, 110, 60))
		k.cyl("PropStem", Vector3.new(0.5, 0.14, 0.14), CFrame.new(0, 4.5, 0) * CFrame.Angles(0, 0, math.rad(90)), METAL)
		for _, a in { 0, 90 } do
			k.part("PropBlade", Vector3.new(2.2, 0.08, 0.35), CFrame.new(0, 4.78, 0) * CFrame.Angles(0, math.rad(a + 20), 0),
				Color3.fromRGB(230, 80, 60))
		end
		k.part("AviatorBand", Vector3.new(2.15, 0.18, 2.15), CFrame.new(0, 3.55, 0), DARK)
		for _, sx in { -1, 1 } do
			k.cyl("Aviator", Vector3.new(0.22, 0.5, 0.5), CFrame.new(sx * 0.38, 3.55, -1.0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 190, 90), Enum.Material.Glass)
		end
	end },

	-- ── Mythic ────────────────────────────────────────────────────────────
	DoubleImp = { build = function(k)
		-- İki kafa: yanında ikinci bir impostor kafası, iki kırmızı vizör
		k.visor.Color = Color3.fromRGB(255, 40, 40)
		k.visor.Material = Enum.Material.Neon
		k.ball("TwinHead", Vector3.new(1.4, 1.4, 1.4), CFrame.new(1.05, 3.55, 0.2), k.color)
		k.ball("TwinVisor", Vector3.new(1.0, 0.6, 0.4), CFrame.new(1.12, 3.58, -0.38), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
	end },
	TripleImp = { build = function(k)
		k.visor.Color = Color3.fromRGB(255, 40, 40)
		k.visor.Material = Enum.Material.Neon
		for _, sx in { -1, 1 } do
			k.ball("TwinHead", Vector3.new(1.3, 1.3, 1.3), CFrame.new(sx * 1.1, 3.45, 0.2), k.color)
			k.ball("TwinVisor", Vector3.new(0.9, 0.55, 0.38), CFrame.new(sx * 1.14, 3.48, -0.34), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
		end
	end },
	Jester = { noHat = true, build = function(k)
		-- Üç uçlu soytarı külahı, uçlarında zil
		k.part("JesterBand", Vector3.new(2.2, 0.4, 2.2), CFrame.new(0, 3.85, 0), GOLD)
		local colors = { Color3.fromRGB(150, 60, 220), Color3.fromRGB(60, 200, 120), Color3.fromRGB(150, 60, 220) }
		for i, a in { -45, 0, 45 } do
			local cf = CFrame.new(0, 4.0, 0) * CFrame.Angles(0, 0, math.rad(a)) * CFrame.new(0, 0.9, 0)
			k.part("JesterPoint", Vector3.new(0.7, 1.7, 0.7), cf, colors[i])
			k.ball("JesterBell", Vector3.new(0.4, 0.4, 0.4), cf * CFrame.new(0, 0.95, 0), GOLD, Enum.Material.Neon)
		end
		k.part("JesterCollar", Vector3.new(2.2, 0.3, 2.14), CFrame.new(0, 2.45, 0), GOLD)
	end },

	-- ── Secret ────────────────────────────────────────────────────────────
	AmogusPrime = { build = function(k)
		-- Kızıl parlayan gözler, ayaklarında gölge halkası
		k.visor.Color = Color3.fromRGB(255, 20, 60)
		k.visor.Material = Enum.Material.Neon
		local ring = k.cyl("ShadowRing", Vector3.new(0.1, 3.4, 3.4), CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(180, 0, 60), Enum.Material.Neon)
		ring.Transparency = 0.3
	end },
	TheCrewmate = { build = function(k)
		-- Altın tulum çizgileri, göğüste yıldız, arkada ışık halesi
		k.part("GoldStripe", Vector3.new(2.1, 0.22, 2.06), CFrame.new(0, 1.45, 0), GOLD, Enum.Material.Neon)
		local star = k.part("ChestStar", Vector3.new(0.6, 0.6, 0.1), CFrame.new(0, 2.1, -1.03) * CFrame.Angles(0, 0, math.rad(45)), GOLD, Enum.Material.Neon)
		star.Transparency = 0.05
		local glow = k.cyl("Aura", Vector3.new(0.1, 5.2, 5.2), CFrame.new(0, 2.6, 1.6) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(255, 240, 180), Enum.Material.Neon)
		glow.Transparency = 0.75
	end },
}

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

	--[[
		Among Us fasulyesi. Yuvarlak şekiller Roblox'un yerleşik ağlarından
		(SpecialMesh Head = yuvarlatılmış silindir, Sphere = elips) — mağaza
		varlığı değil, her yerde yükleniyor.

		Eski hâli keskin kenarlı silindir, küre ve KUTU vizördü; uzaktan
		bakınca vizör yüze yapıştırılmış mavi bir tuğla gibi duruyordu.
		Ölçüler aynı (boy 4.0, kafa merkezi 3.0): şapkalar yerinde kalıyor.
	]]
	local function rounded(part: Part, meshType: Enum.MeshType): Part
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = meshType
		mesh.Parent = part
		return part
	end

	-- Gövde: kenarları yuvarlatılmış silindir (dik, döndürmeye gerek yok)
	local body = rounded(newPart("Body", Vector3.new(2.05, 2.5, 2.0), bodyColor, Enum.Material.SmoothPlastic), Enum.MeshType.Head)
	body.CFrame = CFrame.new(0, 1.85, 0)
	body.Parent = model

	local head = newPart("Head", Vector3.new(2.05, 2.05, 2.05), bodyColor, Enum.Material.SmoothPlastic)
	head.Shape = Enum.PartType.Ball
	head.CFrame = CFrame.new(0, 3.0, 0)
	head.Parent = model

	-- Vizör: arkada koyu çerçeve, önde elips cam ve iki parlama
	local rim = rounded(newPart("VisorRim", Vector3.new(1.62, 1.04, 0.5), bodyColor:Lerp(Color3.new(0, 0, 0), 0.5), Enum.Material.SmoothPlastic), Enum.MeshType.Sphere)
	rim.CFrame = CFrame.new(0.12, 3.02, -0.7)
	rim.Parent = model

	local visor = rounded(newPart("Visor", Vector3.new(1.46, 0.88, 0.6), Color3.fromRGB(150, 216, 240), Enum.Material.Glass), Enum.MeshType.Sphere)
	visor.CFrame = CFrame.new(0.12, 3.04, -0.8)
	visor.Reflectance = 0.2
	visor.Parent = model

	for index, spec in { { 0.42, 3.22, 0.42, 0.22 }, { 0.62, 2.98, 0.16, 0.12 } } do
		local glint = rounded(newPart("VisorGlint" .. index, Vector3.new(spec[3], spec[4], 0.06), Color3.fromRGB(245, 252, 255), Enum.Material.Neon), Enum.MeshType.Sphere)
		glint.CFrame = CFrame.new(spec[1], spec[2], -1.09)
		glint.Parent = model
	end

	-- Kafada cilalı parıltı: oyuncak gibi okunsun
	local shine = rounded(newPart("BodyGlint", Vector3.new(0.42, 0.26, 0.06), Color3.fromRGB(255, 255, 255), Enum.Material.Neon), Enum.MeshType.Sphere)
	shine.CFrame = CFrame.new(-0.55, 3.62, -0.5) * CFrame.Angles(math.rad(-35), math.rad(-35), math.rad(25))
	shine.Transparency = 0.45
	shine.Parent = model

	-- Sırt çantası: yuvarlatılmış
	local pack = rounded(newPart("Backpack", Vector3.new(0.85, 1.9, 0.95), bodyColor:Lerp(Color3.new(0, 0, 0), 0.12), Enum.Material.SmoothPlastic), Enum.MeshType.Head)
	pack.CFrame = CFrame.new(0, 2.05, 1.18)
	pack.Parent = model

	-- Bacaklar: kısa ve yuvarlak uçlu
	for index, offset in { -0.55, 0.55 } do
		local leg = rounded(newPart("Leg" .. index, Vector3.new(0.8, 1.3, 1.02), bodyColor, Enum.Material.SmoothPlastic), Enum.MeshType.Head)
		leg.CFrame = CFrame.new(offset, 0.65, 0)
		leg.Parent = model
	end

	local rarity = Config.Rarities[def.rarity]

	--[[
		═══ NADİRLİK KOZMETİĞİ ═══════════════════════════════════════════════

		Among Us'ta bir karakteri diğerinden ayıran şey tulum rengi değil,
		KAFASINA TAKTIĞI ŞEY. Oyunun bütün kozmetik ekonomisi şapka üstüne
		kurulu. Bizde de nadirlik sadece etiket rengiyle anlatılıyordu:
		kaidedeki sekiz karakter uzaktan birbirinin aynıydı, hangisinin
		değerli olduğunu anlamak için yanına gidip yazıyı okumak gerekiyordu.

		Artık her nadirlik kademesinin kendi başlığı var. Silueti farklı
		olduğu için koridorun öbür ucundan bile okunuyor — hırsız hangi üsse
		gideceğine bakmadan karar verebiliyor.

		Kademeler kasten ARTAN SİLUET büyüklüğünde: Common'da hiçbir şey yok,
		Mythic'te kafanın iki katı bir taç var. Değer arttıkça karakter
		fiziksel olarak da büyüyor gibi duruyor.
	]]
	local function cosmetic(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
		local part = newPart(name, size, color, material or Enum.Material.SmoothPlastic)
		part.CFrame = cf
		part.Parent = model
		return part
	end

	local accent = rarity.color
	local extra = EXTRAS[def.id]
	-- Karakterin kendi başlığı varsa nadirlik şapkası takılmıyor
	local hatRarity = if extra and extra.noHat then "" else def.rarity

	if hatRarity == "Uncommon" then
		--[[ Kep. Tepe + siperlik + dikiş bandı + tepe düğmesi. İlk hâli iki
		     parçaydı ve "kutu" gibi duruyordu; dikiş ve düğme onu giyilmiş
		     bir eşya yapıyor. ]]
		cosmetic("HatCrown", Vector3.new(1.75, 0.6, 1.75), CFrame.new(0, 4.05, 0), accent)
		cosmetic("HatSeam", Vector3.new(1.85, 0.16, 1.85), CFrame.new(0, 3.78, 0), DARK)
		cosmetic("HatBrim", Vector3.new(1.6, 0.2, 1.25), CFrame.new(0, 3.82, -1.05), accent)
		cosmetic("HatBrimEdge", Vector3.new(1.6, 0.1, 0.25), CFrame.new(0, 3.76, -1.6), DARK)
		cosmetic("HatButton", Vector3.new(0.34, 0.22, 0.34), CFrame.new(0, 4.42, 0), DARK)

	elseif hatRarity == "Rare" then
		--[[ Miğfer. Kubbe + çene bandı + yan kulaklık + anten + anten ucu.
		     Kubbe hafif saydam: altından vizör görünsün, kafayı tamamen
		     yutmasın. ]]
		local dome = cosmetic("HatDome", Vector3.new(2.15, 2.15, 2.15), CFrame.new(0, 4.05, 0.1), accent)
		dome.Shape = Enum.PartType.Ball
		dome.Transparency = 0.12

		cosmetic("HelmBand", Vector3.new(2.25, 0.3, 2.25), CFrame.new(0, 3.55, 0.1), METAL)
		for _, s in { -1, 1 } do
			cosmetic("HelmEar", Vector3.new(0.35, 0.8, 0.8), CFrame.new(s * 1.05, 3.9, 0.1), METAL)
		end
		cosmetic("HatAntenna", Vector3.new(0.16, 1.2, 0.16), CFrame.new(0.65, 4.95, 0.1), METAL)
		local bulb = cosmetic("AntennaTip", Vector3.new(0.34, 0.34, 0.34), CFrame.new(0.65, 5.6, 0.1), accent, Enum.Material.Neon)
		bulb.Shape = Enum.PartType.Ball

	elseif hatRarity == "Epic" then
		--[[ Silindir şapka. Kenar + gövde + kurdele + toka + üst kapak.
		     Toka silueti kırıyor: düz silindir uzaktan sadece bir sütun. ]]
		cosmetic("HatBrim", Vector3.new(2.7, 0.24, 2.7), CFrame.new(0, 3.95, 0), accent)
		cosmetic("HatBrimLip", Vector3.new(2.9, 0.12, 2.9), CFrame.new(0, 3.86, 0), DARK)
		cosmetic("HatBody", Vector3.new(1.65, 1.6, 1.65), CFrame.new(0, 4.85, 0), accent)
		cosmetic("HatBand", Vector3.new(1.78, 0.42, 1.78), CFrame.new(0, 4.32, 0), DARK)
		cosmetic("HatBuckle", Vector3.new(0.5, 0.5, 0.2), CFrame.new(0, 4.32, -0.92), METAL)
		cosmetic("HatTop", Vector3.new(1.72, 0.14, 1.72), CFrame.new(0, 5.7, 0), DARK)

	elseif hatRarity == "Legendary" then
		--[[ Taç. Halka + beş uç + her ucun tepesinde taş + önde büyük taş.
		     Uçlar dışa doğru eğik; dimdik duran uçlar tarak gibi görünüyordu. ]]
		cosmetic("CrownBase", Vector3.new(2.05, 0.28, 2.05), CFrame.new(0, 3.9, 0), METAL)
		cosmetic("CrownRing", Vector3.new(1.95, 0.5, 1.95), CFrame.new(0, 4.16, 0), accent)

		for i = 1, 5 do
			local a = (i - 1) * (math.pi * 2 / 5)
			local seat = CFrame.new(0, 4.62, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 0.76)
			cosmetic("CrownSpike", Vector3.new(0.3, 1.5, 0.3), seat * CFrame.Angles(math.rad(-9), 0, 0), accent)
			local gem = cosmetic("CrownGem", Vector3.new(0.34, 0.34, 0.34), seat * CFrame.new(0, 0.86, -0.12), METAL, Enum.Material.Neon)
			gem.Shape = Enum.PartType.Ball
		end

		local front = cosmetic("CrownJewel", Vector3.new(0.6, 0.6, 0.28), CFrame.new(0, 4.24, -0.98), METAL, Enum.Material.Neon)
		front.Transparency = 0.1

	elseif hatRarity == "Mythic" then
		--[[ Boynuzlu taç. Halka + iki boynuz + boynuz halkaları + arkada
		     yüzen ay. Halka artık DÖNMÜYOR (dönen her şey kaldırıldı), hafif
		     eğik duruyor ki tabak gibi görünmesin. ]]
		cosmetic("CrownBase", Vector3.new(2.35, 0.3, 2.35), CFrame.new(0, 3.92, 0), DARK)
		cosmetic("CrownRing", Vector3.new(2.25, 0.55, 2.25), CFrame.new(0, 4.2, 0), accent)

		for _, s in { -1, 1 } do
			cosmetic("CrownHorn", Vector3.new(0.38, 2.0, 0.38),
				CFrame.new(s * 0.88, 5.1, 0) * CFrame.Angles(0, 0, math.rad(-s * 24)), accent)
			cosmetic("HornRing", Vector3.new(0.52, 0.16, 0.52),
				CFrame.new(s * 1.16, 5.6, 0) * CFrame.Angles(0, 0, math.rad(-s * 24)), METAL)
			local tip = cosmetic("HornTip", Vector3.new(0.3, 0.3, 0.3),
				CFrame.new(s * 1.35, 6.05, 0), accent, Enum.Material.Neon)
			tip.Shape = Enum.PartType.Ball
		end

		local halo = cosmetic("Halo", Vector3.new(3.1, 0.18, 3.1),
			CFrame.new(0, 5.75, 0) * CFrame.Angles(math.rad(10), 0, math.rad(6)), accent, Enum.Material.Neon)
		halo.Transparency = 0.35

	elseif def.rarity == "Secret" then
		--[[
			Gizli kademe hiçbir şey TAKMIYOR: tam tersine, karakterin kendisi
			yarı saydam ve gövdesi karanlık. "Bu ne takmış" değil "bu ne
			böyle" dedirtiyor. En üst kademede kozmetik yarışına girmek yerine
			kuralı bozmak daha güçlü bir sinyal.
		]]
		body.Transparency = 0.35
		head.Transparency = 0.35
		pack.Transparency = 0.35
		local shroud = cosmetic("Shroud", Vector3.new(2.6, 2.6, 2.6), CFrame.new(0, 3.0, 0), accent, Enum.Material.Neon)
		shroud.Shape = Enum.PartType.Ball
		shroud.Transparency = 0.86
	end

	if extra then
		local function shaped(shape: Enum.PartType?)
			return function(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
				local part = cosmetic(name, size, cf, color, material)
				if shape then
					part.Shape = shape
				end
				return part
			end
		end
		local ballPart = function(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
			-- Elips: yuvarlatılmış ağ (Ball şekli yalnızca eşit kenarda küre)
			local part = cosmetic(name, size, cf, color, material)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
			return part
		end
		extra.build({
			part = shaped(nil),
			ball = ballPart,
			cyl = shaped(Enum.PartType.Cylinder),
			body = body,
			head = head,
			visor = visor,
			rim = rim,
			pack = pack,
			color = bodyColor,
		})
	end

	--[[
		Nadirlik ışığı. Eskiden her karakter ışık saçıyordu; bir üste sekiz
		karakter konunca sekiz ışık kaynağı oluyor ve sahne yıkanıyordu
		("her yerde çok fazla parıltı var"). Artık sadece Epic ve üstü ışık
		veriyor — ışığın kendisi bir ödül. Alt kademeler kozmetikten okunuyor.
	]]
	local LIT = { Epic = true, Legendary = true, Mythic = true, Secret = true }
	if LIT[def.rarity] or mutation then
		local light = Instance.new("PointLight")
		light.Color = rarity.color
		light.Range = if mutation then 9 else 7
		light.Brightness = if mutation then 1.4 else 0.8
		light.Parent = body
	end

	-- Pivot parçası: ayakların tabanında ve dönüşsüz.
	-- Gövde silindir olduğu için 90° çevrili duruyor. Onu PrimaryPart yaparsak
	-- model pivotu da çevrili olur; PivotTo pivotu hedefe birebir oturttuğu için
	-- o dönüşü sıfırlar ve karakter yan yatıp kaideye gömülür.
	local root = newPart("Root", Vector3.new(0.2, 0.2, 0.2), bodyColor, Enum.Material.SmoothPlastic)
	root.CFrame = CFrame.new(0, 0, 0)
	root.Transparency = 1
	root.Parent = model

	model.PrimaryPart = root

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
	--[[
		Etiket PrimaryPart'a (Root) bağlanıyor, o da ayak hizasında.
		Nadirlik kozmetikleri gelince karakterin boyu 4.10'dan 6.05'e çıktı
		(Mythic tacı + halkası); etiket 5.0'da kalınca tacın içinden geçiyordu.
		En uzun figürün üstünde kalacak kadar yukarı alındı.
	]]
	gui.StudsOffsetWorldSpace = Vector3.new(0, 6.8, 0)

	--[[
		Boyut küçültüldü. Kaideler 6.5 stud arayla dizili; 7 stud genişliğinde
		etiket komşusununkiyle üst üste biniyor ve yaklaşınca ikisi de
		okunmaz hale geliyordu. MaxDistance da düştü: uzaktan onlarca etiket
		birbirine girmesin, yaklaşınca okunsun.
	]]
	gui.Size = UDim2.fromScale(4.6, 1.5)
	-- AlwaysOnTop kapali: acikken etiketler duvarlarin ve 2B HUD'un uzerine
	-- ciziliyor, kaide sirasina yaklasinca ekran okunmaz hale geliyordu.
	gui.AlwaysOnTop = false
	gui.MaxDistance = 70

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
