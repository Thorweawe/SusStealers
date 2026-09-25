--!strict
--[[
	Peti koddan üretir. UnitModel'in küçük kardeşi: hazır varlık yok,
	her şey Part'tan.

	═══ NEDEN YENİDEN YAZILDI ══════════════════════════════════════════════

	İlk hâli köşeli bloklardan kuruluydu ve "pet" değil "eşya" gibi
	duruyordu. Roblox'un pet oyunlarındaki petleri sevimli yapan üç şey var
	ve üçü de burada:

	  1. YUVARLAK GÖVDE — kutu yerine küre/kapsül. Part'ın kendi şekilleri
	     yetmiyor (Ball her yönde eşit), o yüzden yerleşik ağlar
	     kullanılıyor: SpecialMesh Sphere (elips) ve Head (kapsül). Bunlar
	     Roblox'un içinde, mağaza varlığı değil; her yerde yükleniyor.
	  2. BÜYÜK, PARLAK YÜZ — mürettebatın vizörü büyütüldü, üstünde iki
	     beyaz parlama noktası var. Robotta ekranda iki göz, yengeçte sap
	     üstünde gözler.
	  3. KÜÇÜK GÖVDE, BÜYÜK KAFA — chibi oranı.

	Tema korunuyor: her pet Skeld'in bir parçası (mini mürettebat, havalan-
	dırma faresi, görev robotu, acil durum zili...). Tür detayları (kulak,
	boynuz, hale, kuyruk) pet kimliğine göre ekleniyor.

	═══ BOYUT ═════════════════════════════════════════════════════════════

	Anahtar "pet[:mutasyon][:boyut]" (Config.PetKey). Boyut (Big/Huge/
	Titan) modeli ölçekliyor; en sonda "Radius" niteliği yazılıyor ki
	PetService petleri yan yana dizerken birbirinin içine sokmasın.
]]

local Config = require(script.Parent.Config)

local PetModel = {}

--[[
	Pet -> biçim. Listede olmayan pet "blob" oluyor; yeni pet eklenince
	model yine de çıkıyor, sadece jenerik görünüyor.
]]
local FORMS: { [string]: string } = {
	MiniCrew = "blob",     Bolt = "bot",         VentRat = "blob",
	BrainSlug = "crab",    SparePod = "orb",     Hamster = "blob",
	MedDrone = "orb",      TaskBot = "bot",      VentCrab = "crab",
	SusShadow = "blob",    CoreShard = "shard",  SecurityCam = "bot",
	MiniImp = "blob",      EscapePod = "orb",    SnowPal = "blob",
	GhostCrew = "blob",    MeetingBell = "orb",
	TheEgg = "orb",        VoidShard = "shard",
	-- Void yumurtası
	VoidMite = "crab",     StarJelly = "blob",   CometPup = "orb",
	NebulaEye = "orb",
}

--[[ Petin biçim adı. Arayüz (UiKit.PetFigure) aynı biçimi 2B çiziyor. ]]
function PetModel.FormOf(petId: string): string
	return FORMS[petId] or "blob"
end

--[[
	Sahadaki taban ölçek. Boyut kademesi (Config.PetSizes) bunun üstüne
	çarpılıyor: Titan ~ oyuncudan büyük.
]]
local SCALE = 1.35

-- Parıltı dokusu Roblox'un kendi içinde (rbxasset), mağaza varlığı değil
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local VISOR = Color3.fromRGB(150, 220, 255)
local METAL = Color3.fromRGB(198, 206, 214)
local DARK = Color3.fromRGB(26, 28, 34)
local WHITE = Color3.fromRGB(250, 252, 255)
local PINK = Color3.fromRGB(255, 150, 180)

type Builder = {
	model: Model,
	color: Color3,
	part: (name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?) -> Part,
	ellipsoid: (name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?) -> Part,
	capsule: (name: string, size: Vector3, cf: CFrame, color: Color3) -> Part,
	cylinder: (name: string, length: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?) -> Part,
}

local function newBuilder(model: Model, color: Color3): Builder
	local function part(name: string, size: Vector3, cf: CFrame, tint: Color3, material: Enum.Material?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = tint
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end

	--[[ Elips: Sphere ağı parçanın boyutuna uyuyor, yani her eksende
	     ayrı ölçü verilebiliyor. Ball şekli bunu yapamıyor. ]]
	local function ellipsoid(name: string, size: Vector3, cf: CFrame, tint: Color3, material: Enum.Material?): Part
		local p = part(name, size, cf, tint, material)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
		return p
	end

	--[[ Kapsül: Head ağı — yuvarlatılmış silindir. Mürettebat gövdesinin
	     silueti tam olarak bu. ]]
	local function capsule(name: string, size: Vector3, cf: CFrame, tint: Color3): Part
		local p = part(name, size, cf, tint)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Head
		mesh.Parent = p
		return p
	end

	local function cylinder(name: string, length: number, diameter: number, cf: CFrame, tint: Color3, material: Enum.Material?): Part
		local p = part(name, Vector3.new(length, diameter, diameter), cf, tint, material)
		p.Shape = Enum.PartType.Cylinder
		return p
	end

	return {
		model = model, color = color, part = part,
		ellipsoid = ellipsoid, capsule = capsule, cylinder = cylinder,
	}
end

--[[
	Parlak vizör: elips cam + iki beyaz parlama. Parlamalar vizörü
	"camdan bir yüz" yapıyor; onlarsız düz mavi bir leke gibi duruyor.
]]
local function visor(b: Builder, center: Vector3, width: number, height: number, depth: number, tint: Color3?)
	--[[
		Arkada koyu çerçeve: Among Us vizörünün kalın konturu. Onsuz vizör
		gövdeden ayrılmıyor, yandan bakınca öne uzamış bir gaga gibi
		okunuyordu.
	]]
	b.ellipsoid("VisorRim", Vector3.new(width + 0.14, height + 0.14, depth * 0.7),
		CFrame.new(center + Vector3.new(0, 0, depth * 0.2)), b.color:Lerp(Color3.new(0, 0, 0), 0.45))
	local v = b.ellipsoid("Visor", Vector3.new(width, height, depth), CFrame.new(center), tint or VISOR, Enum.Material.Glass)
	v.Reflectance = 0.25
	local front = center.Z - depth / 2
	b.ellipsoid("VisorGlint", Vector3.new(width * 0.28, height * 0.26, 0.08),
		CFrame.new(center.X + width * 0.2, center.Y + height * 0.16, front + 0.02), WHITE, Enum.Material.Neon)
	b.ellipsoid("VisorGlint", Vector3.new(width * 0.12, height * 0.12, 0.08),
		CFrame.new(center.X + width * 0.34, center.Y - height * 0.06, front + 0.03), WHITE, Enum.Material.Neon)
end

--[[ Sapın ucunda göz: beyaz küre + siyah bebek + minik parlama. ]]
local function eyeBall(b: Builder, at: Vector3, radius: number)
	b.ellipsoid("EyeWhite", Vector3.new(radius * 2, radius * 2, radius * 2), CFrame.new(at), WHITE)
	b.ellipsoid("EyePupil", Vector3.new(radius * 1.1, radius * 1.1, radius * 0.6),
		CFrame.new(at + Vector3.new(0, 0, -radius * 0.78)), DARK)
	b.ellipsoid("VisorGlint", Vector3.new(radius * 0.4, radius * 0.4, 0.06),
		CFrame.new(at + Vector3.new(radius * 0.25, radius * 0.3, -radius * 1.02)), WHITE, Enum.Material.Neon)
end

-- ─── Biçimler ───────────────────────────────────────────────────────────────

--[[
	Blob: chibi mürettebat. Kapsül gövde (kafa ile gövde bir), iri vizör,
	kısa bacak, sırtta küçük çanta. Tepesi y ≈ 2.1.
]]
local function buildBlob(b: Builder): (Part, number)
	local body = b.capsule("Body", Vector3.new(1.55, 1.75, 1.45), CFrame.new(0, 1.12, 0), b.color)
	-- Vizör gövdeye yaslı: önü gövde yüzeyinden yalnızca bir tık önde
	visor(b, Vector3.new(0.05, 1.45, -0.56), 1.16, 0.6, 0.4)
	b.capsule("Backpack", Vector3.new(0.9, 0.95, 0.5), CFrame.new(0, 1.0, 0.72), b.color:Lerp(Color3.new(0, 0, 0), 0.18))
	for index, side in { -0.36, 0.36 } do
		b.ellipsoid("Leg" .. index, Vector3.new(0.55, 0.5, 0.6), CFrame.new(side, 0.27, -0.02), b.color)
	end
	-- Yanak allığı: vizörün altında iki pembe leke; chibi yüzü tamamlıyor
	for _, side in { -1, 1 } do
		local blush = b.ellipsoid("Blush", Vector3.new(0.28, 0.14, 0.08), CFrame.new(side * 0.5, 1.02, -0.57) * CFrame.Angles(0, math.rad(side * 32), 0), PINK)
		blush.Transparency = 0.25
	end
	return body, 2.05
end

--[[ Orb: süzülen küre + eğik halka + vizör. Tepesi y ≈ 1.75. ]]
local function buildOrb(b: Builder): (Part, number)
	local body = b.ellipsoid("Body", Vector3.new(1.6, 1.6, 1.6), CFrame.new(0, 0.95, 0), b.color)
	b.cylinder("Ring", 0.12, 2.35, CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(16), 0, 0), METAL, Enum.Material.Metal)
	visor(b, Vector3.new(0, 1.05, -0.64), 0.95, 0.5, 0.36)
	return body, 1.75
end

--[[
	Bot: yuvarlatılmış kutu gövde, önde koyu ekran ve ekranda parlayan iki
	göz, tepede anten. Göz ekranı robotu "yüzü olan" bir şey yapıyor.
]]
local function buildBot(b: Builder): (Part, number)
	local body = b.capsule("Body", Vector3.new(1.55, 1.3, 1.25), CFrame.new(0, 0.95, 0), b.color)
	b.part("Screen", Vector3.new(1.05, 0.62, 0.1), CFrame.new(0, 1.0, -0.6), DARK)
	for _, side in { -0.22, 0.22 } do
		b.ellipsoid("ScreenEye", Vector3.new(0.2, 0.26, 0.06), CFrame.new(side, 1.02, -0.66), VISOR, Enum.Material.Neon)
	end
	b.part("Antenna", Vector3.new(0.08, 0.5, 0.08), CFrame.new(0, 1.8, 0), METAL, Enum.Material.Metal)
	b.ellipsoid("AntennaTip", Vector3.new(0.24, 0.24, 0.24), CFrame.new(0, 2.08, 0), VISOR, Enum.Material.Neon)
	for index, side in { -0.45, 0.45 } do
		b.ellipsoid("Wheel" .. index, Vector3.new(0.34, 0.38, 0.7), CFrame.new(side, 0.26, 0), DARK)
	end
	return body, 2.2
end

--[[
	Crab: basık elips gövde, saplar üstünde iri gözler, iki kıskaç ve
	altı bacak. Havalandırmadan çıkan şey.
]]
local function buildCrab(b: Builder): (Part, number)
	local body = b.ellipsoid("Body", Vector3.new(1.8, 0.95, 1.4), CFrame.new(0, 0.72, 0), b.color)
	for _, side in { -0.32, 0.32 } do
		b.part("Stalk", Vector3.new(0.09, 0.55, 0.09), CFrame.new(side, 1.32, -0.3), b.color:Lerp(Color3.new(0, 0, 0), 0.2))
		eyeBall(b, Vector3.new(side, 1.66, -0.34), 0.2)
	end
	for _, side in { -1, 1 } do
		b.ellipsoid("Claw", Vector3.new(0.5, 0.4, 0.45), CFrame.new(side * 1.02, 0.72, -0.45), b.color:Lerp(Color3.new(1, 1, 1), 0.12))
		for row = -1, 1 do
			local leg = b.part("Leg", Vector3.new(0.5, 0.1, 0.1),
				CFrame.new(side * 0.85, 0.3, row * 0.35) * CFrame.Angles(0, 0, math.rad(side * -24)), DARK)
			leg.Name = "Leg"
		end
	end
	return body, 1.95
end

--[[
	Kristal yaratık: yuvarlak cam gövde, içinde parlayan çekirdek, sırtında
	üç kristal diken ve iri iki göz. İlk hâli yüzü olmayan eğik bloklardı
	ve pet değil maden parçası gibi duruyordu; artık bir canlı.
]]
local function buildShard(b: Builder): (Part, number)
	local body = b.ellipsoid("Body", Vector3.new(1.5, 1.3, 1.35), CFrame.new(0, 0.82, 0), b.color, Enum.Material.Glass)
	body.Transparency = 0.18
	local core = b.ellipsoid("ShardCore", Vector3.new(0.62, 0.62, 0.62), CFrame.new(0, 0.82, 0.05), b.color:Lerp(Color3.new(1, 1, 1), 0.55), Enum.Material.Neon)
	core.Name = "ShardCore"
	-- Kristal dikenler: 45° dönmüş, sırta doğru yatık bloklar
	for index, spec in { { 0, 1.55, 0.12, 0, 0.95 }, { -0.42, 1.38, 0.18, -28, 0.7 }, { 0.42, 1.38, 0.18, 28, 0.7 } } do
		local spike = b.part("Spike" .. index, Vector3.new(0.34, spec[5], 0.34),
			CFrame.new(spec[1], spec[2], spec[3]) * CFrame.Angles(math.rad(-12), 0, math.rad(spec[4])) * CFrame.Angles(0, math.rad(45), 0),
			b.color, Enum.Material.Glass)
		spike.Transparency = 0.1
	end
	for _, side in { -0.28, 0.28 } do
		eyeBall(b, Vector3.new(side, 0.95, -0.52), 0.19)
	end
	return body, 2.0
end

-- ─── Tür detayları ──────────────────────────────────────────────────────────

--[[
	Pet kimliğine göre küçük eklemeler. Biçim kaba silueti veriyor, bu
	tablo "hangi pet" sorusunu cevaplıyor: fare kulağından, hamster
	yanağından, hayalet halesinden tanınıyor.
]]
local DETAILS: { [string]: (b: Builder, top: number) -> () } = {
	VentRat = function(b, top)
		for _, side in { -0.42, 0.42 } do
			b.ellipsoid("Ear", Vector3.new(0.55, 0.55, 0.14), CFrame.new(side, top - 0.1, 0.05), b.color)
			b.ellipsoid("EarInner", Vector3.new(0.34, 0.34, 0.06), CFrame.new(side, top - 0.1, -0.03), PINK)
		end
		b.part("Tail", Vector3.new(0.09, 0.09, 1.1), CFrame.new(0, 0.5, 1.15) * CFrame.Angles(math.rad(-25), 0, 0), PINK)
	end,
	Hamster = function(b, top)
		for _, side in { -0.45, 0.45 } do
			b.ellipsoid("Ear", Vector3.new(0.38, 0.38, 0.14), CFrame.new(side, top - 0.2, 0.05), b.color:Lerp(Color3.new(0, 0, 0), 0.12))
			b.ellipsoid("Cheek", Vector3.new(0.34, 0.24, 0.12), CFrame.new(side * 1.25, 0.98, -0.62), PINK)
		end
	end,
	MiniImp = function(b, top)
		for _, side in { -1, 1 } do
			local horn = b.part("Horn", Vector3.new(0.16, 0.45, 0.16),
				CFrame.new(side * 0.38, top + 0.1, 0) * CFrame.Angles(0, 0, math.rad(side * -20)), DARK)
			horn.Name = "Horn"
		end
	end,
	GhostCrew = function(b, top)
		local halo = b.cylinder("Halo", 0.08, 1.1, CFrame.new(0, top + 0.35, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 236, 150), Enum.Material.Neon)
		halo.Transparency = 0.1
		for _, p in b.model:GetChildren() do
			if p:IsA("BasePart") and p.Name ~= "Halo" and not string.find(p.Name, "Glint") then
				p.Transparency = math.max(p.Transparency, 0.3)
			end
		end
	end,
	SnowPal = function(b, _)
		b.part("Nose", Vector3.new(0.14, 0.14, 0.45), CFrame.new(0, 1.2, -0.95), Color3.fromRGB(255, 140, 40))
		b.cylinder("Scarf", 0.28, 1.62, CFrame.new(0, 0.85, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 40, 50))
		for _, side in { -1, 1 } do
			b.part("Arm", Vector3.new(0.7, 0.07, 0.07),
				CFrame.new(side * 1.05, 1.0, 0) * CFrame.Angles(0, 0, math.rad(side * 25)), Color3.fromRGB(110, 70, 40))
		end
	end,
	SusShadow = function(b, _)
		-- Kırmızı vizör: "sus" bakış
		for _, p in b.model:GetChildren() do
			if p:IsA("BasePart") and p.Name == "Visor" then
				p.Color = Color3.fromRGB(255, 60, 70)
				p.Material = Enum.Material.Neon
			end
		end
	end,
	MedDrone = function(b, top)
		b.part("CrossV", Vector3.new(0.16, 0.5, 0.06), CFrame.new(0, 0.55, -0.74), Color3.fromRGB(230, 50, 60))
		b.part("CrossH", Vector3.new(0.5, 0.16, 0.06), CFrame.new(0, 0.55, -0.74), Color3.fromRGB(230, 50, 60))
		b.part("PropMast", Vector3.new(0.08, 0.3, 0.08), CFrame.new(0, top + 0.1, 0), METAL)
		b.part("Prop", Vector3.new(1.4, 0.05, 0.18), CFrame.new(0, top + 0.26, 0), DARK)
	end,
	SparePod = function(b, top)
		local dome = b.ellipsoid("Dome", Vector3.new(1.2, 0.8, 1.2), CFrame.new(0, top - 0.15, 0), VISOR, Enum.Material.Glass)
		dome.Transparency = 0.45
	end,
	EscapePod = function(b, _)
		for _, side in { -1, 1 } do
			b.part("Fin", Vector3.new(0.1, 0.6, 0.5), CFrame.new(side * 0.85, 0.6, 0.3), METAL, Enum.Material.Metal)
		end
	end,
	MeetingBell = function(b, top)
		b.ellipsoid("Button", Vector3.new(0.8, 0.45, 0.8), CFrame.new(0, top - 0.05, 0), Color3.fromRGB(230, 40, 50), Enum.Material.Neon)
		local cover = b.ellipsoid("Cover", Vector3.new(1.05, 0.7, 1.05), CFrame.new(0, top - 0.05, 0), VISOR, Enum.Material.Glass)
		cover.Transparency = 0.6
	end,
	TheEgg = function(b, _)
		for i = -2, 2 do
			local zig = b.part("Crack", Vector3.new(0.34, 0.06, 0.06),
				CFrame.new(i * 0.3, 1.32, -0.66 - math.abs(i) * -0.04) * CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 30 else -30)), DARK)
			zig.Name = "Crack"
		end
	end,
	SecurityCam = function(b, _)
		-- Ekran yerine lens: kamera "bakıyor"
		for _, p in b.model:GetChildren() do
			if p:IsA("BasePart") and (p.Name == "Screen" or p.Name == "ScreenEye") then
				p:Destroy()
			end
		end
		b.cylinder("Lens", 0.35, 0.75, CFrame.new(0, 1.0, -0.72) * CFrame.Angles(0, math.rad(90), 0), DARK)
		b.ellipsoid("LensGlass", Vector3.new(0.5, 0.5, 0.1), CFrame.new(0, 1.0, -0.9), Color3.fromRGB(255, 60, 70), Enum.Material.Neon)
	end,
	BrainSlug = function(b, _)
		b.ellipsoid("Brain", Vector3.new(1.0, 0.5, 0.8), CFrame.new(0, 1.05, 0.2), PINK:Lerp(Color3.new(1, 1, 1), 0.2))
	end,

	-- ── Void yumurtası ──────────────────────────────────────────────────────
	VoidMite = function(b, _)
		-- Sırtında parlayan iki boşluk lekesi, gözleri mor ışık
		for _, side in { -0.35, 0.35 } do
			b.ellipsoid("VoidSpot", Vector3.new(0.34, 0.14, 0.34), CFrame.new(side, 1.17, 0.15), Color3.fromRGB(190, 120, 255), Enum.Material.Neon)
		end
		for _, p in b.model:GetChildren() do
			if p:IsA("BasePart") and p.Name == "EyePupil" then
				p.Color = Color3.fromRGB(170, 90, 255)
				p.Material = Enum.Material.Neon
			end
		end
	end,
	StarJelly = function(b, top)
		-- Yarı saydam jöle gövde, altında dokunaçlar, tepede yıldız
		for _, p in b.model:GetChildren() do
			if p:IsA("BasePart") and (p.Name == "Body" or p.Name == "Backpack" or string.find(p.Name, "Leg")) then
				p.Material = Enum.Material.Glass
				p.Transparency = math.max(p.Transparency, 0.25)
			end
		end
		for i = 0, 3 do
			local a = math.rad(45 + i * 90)
			b.ellipsoid("Tentacle", Vector3.new(0.22, 0.7, 0.22), CFrame.new(math.cos(a) * 0.45, 0.2, math.sin(a) * 0.4), b.color:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Material.Glass).Transparency = 0.2
		end
		for k = 0, 1 do
			b.part("Star", Vector3.new(0.42, 0.42, 0.1), CFrame.new(0, top + 0.15, 0) * CFrame.Angles(0, 0, math.rad(45 * k)), Color3.fromRGB(255, 230, 90), Enum.Material.Neon)
		end
	end,
	CometPup = function(b, top)
		-- Kulaklar ve arkasında kuyruklu yıldız izi
		for _, side in { -0.45, 0.45 } do
			b.ellipsoid("Ear", Vector3.new(0.3, 0.5, 0.18), CFrame.new(side, top - 0.05, 0.1) * CFrame.Angles(0, 0, math.rad(side * -30)), b.color:Lerp(Color3.new(0, 0, 0), 0.15))
		end
		for i, s in { 0.62, 0.46, 0.3 } do
			local tail = b.ellipsoid("CometTail", Vector3.new(s, s, s * 1.3), CFrame.new(0, 0.95 + i * 0.08, 0.7 + i * 0.42), Color3.fromRGB(180, 245, 255), Enum.Material.Neon)
			tail.Transparency = 0.15 + i * 0.18
		end
	end,
	NebulaEye = function(b, top)
		-- Vizör yerine tek iri göz: nebula gözü
		for _, p in b.model:GetChildren() do
			if p:IsA("BasePart") and (p.Name == "Visor" or p.Name == "VisorRim" or p.Name == "VisorGlint") then
				p:Destroy()
			end
		end
		b.ellipsoid("EyeWhite", Vector3.new(1.0, 1.0, 0.5), CFrame.new(0, 0.98, -0.62), WHITE)
		b.ellipsoid("EyeIris", Vector3.new(0.6, 0.6, 0.2), CFrame.new(0, 0.98, -0.84), Color3.fromRGB(255, 120, 220), Enum.Material.Neon)
		b.ellipsoid("EyePupil", Vector3.new(0.3, 0.3, 0.12), CFrame.new(0, 0.98, -0.92), DARK)
		b.ellipsoid("VisorGlint", Vector3.new(0.16, 0.16, 0.05), CFrame.new(0.14, 1.12, -0.96), WHITE, Enum.Material.Neon)
		-- Tepede küçük nebula bulutları
		for i, spec in { { -0.3, 0.3 }, { 0.25, 0.26 }, { 0, 0.34 } } do
			local puff = b.ellipsoid("Nebula" .. i, Vector3.new(spec[2] * 2, spec[2] * 1.4, spec[2] * 2), CFrame.new(spec[1], top - 0.05 + i * 0.05, 0.1), Color3.fromRGB(120, 200, 255):Lerp(b.color, i / 3), Enum.Material.Neon)
			puff.Transparency = 0.35
		end
	end,
}

-- ─── Kurulum ────────────────────────────────────────────────────────────────

--[[
	Pet modelini kurar. PrimaryPart gövdedir, taban y = 0 hizasındadır.

	`key` envanter anahtarı (Config.PetKey). Model adı anahtarın kendisi —
	PetService sahadaki modelle takılı listeyi adla eşleştiriyor.

	Bilinmeyen anahtar nil döndürüyor, hata atmıyor: eski bir kayıtta
	kaldırılmış bir pet varsa sunucu düşmemeli.
]]
function PetModel.Build(key: string): Model?
	local def, mutation, size = Config.ParsePetKey(key)
	if not def then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = key

	local b = newBuilder(model, def.color)
	local form = FORMS[def.id] or "blob"

	local body: Part
	local top: number
	if form == "orb" then
		body, top = buildOrb(b)
	elseif form == "bot" then
		body, top = buildBot(b)
	elseif form == "crab" then
		body, top = buildCrab(b)
	elseif form == "shard" then
		body, top = buildShard(b)
	else
		body, top = buildBlob(b)
	end

	--[[
		Gövde parlaması: sol üstte küçük beyaz benek. Pet oyunlarındaki
		petleri "oyuncak" gibi gösteren şey bu cilalı parıltı; mat gövde
		plastik bir blok gibi duruyordu. Cam gövdeli kristalde gerek yok.
	]]
	if form ~= "shard" then
		local s = body.Size
		b.ellipsoid("BodyGlint", Vector3.new(s.X * 0.2, s.Y * 0.13, 0.05),
			CFrame.new(body.Position + Vector3.new(-s.X * 0.28, s.Y * 0.26, -s.Z * 0.34)) * CFrame.Angles(0, math.rad(-30), math.rad(25)),
			WHITE, Enum.Material.Neon).Transparency = 0.35
	end

	local detail = DETAILS[def.id]
	if detail then
		detail(b, top)
	end

	local rarity = Config.Rarities[def.rarity]
	local order = rarity.order
	local glow = if def.rarity == "Secret" then Color3.fromRGB(170, 120, 255) else rarity.color

	--[[
		Secret: gövde yarı saydam cam, içinde parlayan bir çekirdek. Diğer
		kademeler "daha çok ışık" üzerine kurulu; Secret o merdivenden
		çıkıyor ve bu yüzden hemen fark ediliyor.
	]]
	if def.rarity == "Secret" then
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and p.Color == def.color then
				p.Transparency = math.max(p.Transparency, 0.3)
				p.Material = Enum.Material.Glass
			end
		end
		b.ellipsoid("SecretCore", Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, top * 0.5, 0), glow, Enum.Material.Neon)
	end

	--[[
		═══ AURA ═════════════════════════════════════════════════════════

		Uzaktan okunan şey IŞIK. Kademeler üst üste ekleniyor:
		  Rare+      ayak altında kademe renginde yarı saydam halka
		  Epic+      çevresine kademe renginde ışık
		  Legendary+ gövdeden kopan parıltılar
		Common ve Uncommon'da hiçbiri yok: ışık kazanılan bir şey olmalı.
	]]
	if order >= Config.Rarities.Rare.order then
		local aura = b.cylinder("Aura", 0.08, 2.4, CFrame.new(0, 0.04, 0) * CFrame.Angles(0, 0, math.rad(90)), glow, Enum.Material.Neon)
		aura.Transparency = 0.55
	end

	if order >= Config.Rarities.Epic.order then
		local light = Instance.new("PointLight")
		light.Name = "RarityLight"
		light.Color = glow
		light.Range = 7
		light.Brightness = 0.9
		light.Parent = body
	end

	if order >= Config.Rarities.Legendary.order then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "Sparkles"
		sparkles.Texture = SPARKLE
		sparkles.Color = ColorSequence.new(glow, Color3.new(1, 1, 1))
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkles.Transparency = NumberSequence.new(0.1)
		sparkles.Lifetime = NumberRange.new(0.8, 1.4)
		-- Mythic ve Secret daha yoğun: kademe farkı uzaktan da seçilsin
		sparkles.Rate = if order >= Config.Rarities.Mythic.order then 9 else 4
		sparkles.Speed = NumberRange.new(0.6, 1.4)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Parent = body
	end

	--[[
		═══ MUTASYON ════════════════════════════════════════════════════

		Aura kademeyi söylüyor, mutasyon GÖVDEYİ değiştiriyor:
		  Golden  — altın ve metalik
		  Crystal — camgöbeği cam; Polus kristallerinin rengi
		  Cosmic  — mor neon ve etrafında ışık; uzaktan parlayan tek pet

		Yalnızca petin KENDİ renginde boyanmış parçalar gövde sayılıyor:
		vizör, gözler, aura ve metal aksam farklı renkte kurulduğu için
		ayrıca listelemeye gerek kalmıyor.
	]]
	if mutation then
		for _, p in model:GetChildren() do
			if not p:IsA("BasePart") or p.Color ~= def.color then
				continue
			end
			p.Color = mutation.tint
			if mutation.id == "Golden" then
				p.Material = Enum.Material.Metal
				p.Reflectance = 0.2
			elseif mutation.id == "Crystal" then
				p.Material = Enum.Material.Glass
				p.Transparency = math.max(p.Transparency, 0.25)
			else
				p.Material = Enum.Material.Neon
			end
		end
		if mutation.id == "Cosmic" then
			local light = Instance.new("PointLight")
			light.Color = mutation.tint
			light.Range = 9
			light.Brightness = 1.4
			light.Parent = body
		end
	end

	model.PrimaryPart = body

	local tag = Instance.new("StringValue")
	tag.Name = "PetId"
	tag.Value = def.id
	tag.Parent = model

	--[[
		Ölçek en sonda: bütün ölçüler 1.0'a göre yazıldı. Işık ve parıltı da
		ScaleTo ile birlikte büyüyor. Titan oyuncudan büyük — adının hakkı.
	]]
	model:ScaleTo(SCALE * (if size then size.scale else 1))

	--[[
		Takip için iki ölçü (PetService okuyor):
		  Radius — yan yana dizerken aralık; Titan komşusunun içine girmesin
		  Lift   — gövde merkezinin modelin en altından yüksekliği; büyük pet
		           yerin içine gömülmesin diye o kadar yukarıda tutuluyor
	]]
	local boxCf, extents = model:GetBoundingBox()
	model:SetAttribute("Radius", math.max(extents.X, extents.Z) / 2)
	model:SetAttribute("Lift", body.Position.Y - (boxCf.Position.Y - extents.Y / 2))

	return model
end

return PetModel
