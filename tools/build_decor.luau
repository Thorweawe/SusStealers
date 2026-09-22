--!strict
--[[
	Harita dekorunu tamamen koddan kurar. Studio'da MCP ile:

	    local src = game:GetService("HttpService"):GetAsync(
	        "http://127.0.0.1:8788/tools/build_decor.luau")
	    loadstring(src)()

	Tasarım: Among Us / Skeld estetiği — sade geometri, temiz paneller,
	camgöbeği neon, uzaya bakan pencereler. Karakterler koddan üretilmiş
	basit silindirler; gerçekçi mesh koyarsak onlar oyuncak gibi kalıyor.

	IZGARA DESTEĞİ: PlotService tek sıra kuruyorsa COLUMNS = PlotCount olur
	ve her şey eskisi gibi çalışır. Config'e PlotColumns / PlotRowSpacing
	eklenirse dekor kendiliğinden ızgaraya uyar, burada değişiklik gerekmez.

	Her şey workspace.Decor altına gider. PlotService.Start() sadece
	workspace.Plots'u siliyor, dekor sunucu yeniden başlayınca kalır.

	OYUNU ENGELLEMEME KURALI: üsler arası geçiş açık kalmalı. Çalmanın
	bütün riski rakip üsse koşmakta. Kapalı duvar, alçak kemer, yola taşan
	sütun konmaz. Duvarlar sadece dış çeperde.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── Ölçüler ────────────────────────────────────────────────────────────────

local PLOT_COUNT, PLOT_SPACING, PLOT_SIZE, PODIUMS, PODIUM_GAP = 8, 76, Vector3.new(60, 2, 44), 8, 6.5
local COLUMNS, ROW_SPACING = PLOT_COUNT, 0
-- Ön/arka kaide sırasının merkezden uzaklığı; Config'ten okunuyor ki
-- gerçek kaidelerle aynı sayı olsun (bkz. Config.PodiumRowZ)
local PODIUM_ROW_Z = 9

do
	--[[
		Klon üzerinden okuyoruz. Studio'da bir modül bir kez hatalı yüklenirse
		Luau o hatayı önbelleğe alıyor; kaynak düzeltilse bile require aynı
		hatayı döndürmeye devam ediyor. Klon yeni bir örnek olduğu için
		önbelleğe takılmadan güncel kaynağı çalıştırır.
	]]
	local ok, cfg = pcall(function()
		local copy = ReplicatedStorage.Shared.Config:Clone()
		local result = require(copy)
		copy:Destroy()
		return result
	end)
	if ok and typeof(cfg) == "table" then
		PLOT_COUNT = cfg.PlotCount or PLOT_COUNT
		PLOT_SPACING = cfg.PlotSpacing or PLOT_SPACING
		PLOT_SIZE = cfg.PlotSize or PLOT_SIZE
		PODIUMS = cfg.PodiumsPerPlot or PODIUMS
		PODIUM_GAP = cfg.PodiumSpacing or PODIUM_GAP
		PODIUM_ROW_Z = cfg.PodiumRowZ or PODIUM_ROW_Z
		COLUMNS = cfg.PlotColumns or PLOT_COUNT
		ROW_SPACING = cfg.PlotRowSpacing or 0
	else
		warn("build_decor: Config okunamadi, varsayilan olculer kullaniliyor")
	end
end

local ROWS = math.ceil(PLOT_COUNT / COLUMNS)
if ROWS > 1 and ROW_SPACING <= 0 then
	ROW_SPACING = PLOT_SIZE.Z + 32
end

local halfX = PLOT_SIZE.X / 2
local halfZ = PLOT_SIZE.Z / 2
local topY = PLOT_SIZE.Y / 2

local spanX = (COLUMNS - 1) * PLOT_SPACING
local spanZ = (ROWS - 1) * ROW_SPACING
local centerX = spanX / 2
local centerZ = spanZ / 2

local MARGIN = 42
local halfW = spanX / 2 + halfX + MARGIN     -- istasyon yarı genişliği
local halfD = spanZ / 2 + halfZ + MARGIN     -- istasyon yarı derinliği

--[[
	DUVAR YÜKSEKLİĞİ — "istasyon çok dar hissettiriyor" şikâyetinin sayısal
	sebebi buydu.

	Üsler 3 katlı: taban 1 + 2 × FloorHeight(18) = 37 stud. Duvar 34'tü,
	tavan 38.6'ydı. Yani en üst kattaki kaideler tavana 1.6 stud kalıyor,
	üstlerindeki karakterler (6 stud) ve isim etiketleri tavanın İÇİNDEN
	geçiyordu. Koridorda yürürken üstünde ezici bir kapak var gibi
	duruyordu.

	52'de en üst kat ile tavan arası 19 stud kalıyor: karakter, etiket ve
	üstünde nefes alacak boşluk sığıyor. Hesap: 1 + 2*18 + 6 (karakter) +
	7 (etiket) = 44, üstüne pay.

	Kat sayısı veya FloorHeight değişirse buranın da değişmesi gerekir —
	altta bir kontrol var, delen parça olursa uyarı basıyor.
]]
local WALL_H = 52          -- çeper duvar yüksekliği
local HULL_DEPTH = 24      -- güverte altı gövde derinliği
local ARCH_CLEAR = 19      -- kemer altı boşluk (eski 15: alçak geliyordu)

-- ─── Lobi ölçüleri ──────────────────────────────────────────────────────────
-- Üslerin önünde ayrı bir platform: ışınlanma, sıralama panoları, çark.
-- Oyun alanından ayrı tutuluyor ki çalma koşuşturması ile sakin işler
-- birbirine karışmasın.
local LOBBY_GATE_WIDTH = 36   -- kopru ayni genislikte; 28'de tunel gibi dardi
local LOBBY_BRIDGE = 58      -- köprü uzunluğu
local LOBBY_W = 230          -- lobi genişliği
local LOBBY_D = 156          -- lobi derinliği
--[[
	Lobi duvarı 30'du ve üstü açıktı — "transit bölgesinin üstü açık"
	şikâyeti buydu. Tavan kapatılınca çark (tepesindeki tabelayla birlikte
	~57 stud) tavanı deliyordu. İkisi birden çözülüyor: duvar 40'a çıktı,
	tavan 42.6'ya kondu, çark da ölçü olarak küçültüldü.
]]
local LOBBY_WALL_H = 46
local LOBBY_CEIL_Y = LOBBY_WALL_H + 2.6

--[[
	Yüzeye yatırılan ince parçaların (dikiş, halka, şerit, ped) alt yüzeyi
	dayandığı zeminle tam aynı hizada olmamalı. Çakışık yüzeylerde Roblox
	hangisini çizeceğine karar veremiyor ve kamera oynadıkça titriyorlar.
	Bu pay onları bir tık yukarı alıyor; gözle fark edilmiyor ama titremeyi
	tamamen bitiriyor.
]]
local LIFT = 0.03

--[[ Üs merkezleri. PlotService ile aynı formül. ]]
local function plotOrigin(index: number): Vector3
	local col = (index - 1) % COLUMNS
	local row = math.floor((index - 1) / COLUMNS)
	return Vector3.new(col * PLOT_SPACING, 0, row * ROW_SPACING)
end

-- ─── Palet ──────────────────────────────────────────────────────────────────

--[[
	TEMA: Among Us'ın nakliye gemisi / Skeld koridorları.

	Referans oyunun kendi ekranları: duvarlar DOYGUNLUĞU DÜŞÜK gri-yeşil
	boyalı çelik, zemin daha koyu aynı aileden, kenarlar açık gri metal,
	aksan olarak sadece soluk sarı hatlar ve turkuaz dolap/panel yüzeyleri.
	Işık sıcak beyaz ve TAVANDAN gelir. Oyunun hiçbir yerinde parlayan duvar
	yoktur.

	Önceki palet lacivert + camgöbeğiydi; teknik olarak koyu ve "uzay" idi
	ama gemi değil siberpunk tüneli gibi okunuyordu. Renkler tek aileye
	(mavi-yeşil gri) indirildi ve doygunluk düşürüldü. Sahneye rengi artık
	mürettebat tulumları veriyor, mimari değil — referansta da öyle.
]]
local STEEL = Color3.fromRGB(126, 140, 144)      -- açık panel (duvar üstü)
local STEEL_MID = Color3.fromRGB(94, 108, 114)   -- ana gövde paneli
local STEEL_DARK = Color3.fromRGB(64, 76, 82)    -- güverte plakası
local STEEL_DEEP = Color3.fromRGB(44, 54, 60)    -- gölgeli gövde
local SHADOW = Color3.fromRGB(27, 34, 39)        -- oluk, çukur, boşluk
local EDGE = Color3.fromRGB(168, 181, 184)       -- çıplak metal kenar
local TEAL = Color3.fromRGB(84, 124, 132)        -- dolap/panel aksanı
local BRASS = Color3.fromRGB(198, 172, 100)      -- soluk sarı hat

local HULL = STEEL_MID
local HULL_DARK = STEEL_DEEP
local TRIM = STEEL

-- Güverte: üç kademe. Plaka / ikinci ton / oluk.
local DECK = STEEL_DARK
local DECK_ALT = Color3.fromRGB(56, 67, 73)
local GROOVE = SHADOW

local NEON = TEAL                                -- ekran/panel yüzeyi
local NEON_DIM = Color3.fromRGB(38, 56, 62)      -- sönük gösterge
local NEON_MID = Color3.fromRGB(62, 92, 99)      -- ara ton: çerçeveler

local LAMP = Color3.fromRGB(255, 244, 222)       -- aydınlatma: SICAK beyaz
local NEON_WARM = BRASS
local HAZARD = Color3.fromRGB(206, 172, 72)      -- uyarı sarısı (soluk)
local HAZARD_DARK = Color3.fromRGB(38, 36, 28)   -- şeridin koyu aralığı
local GLASS = Color3.fromRGB(150, 210, 255)
local RED = Color3.fromRGB(178, 44, 40)

--[[
	Mürettebat renkleri — oyunun kendi paleti. Heykeller, sandık bantları,
	pano vurguları buradan besleniyor. Kendi uydurduğumuz tonlar yerine
	bunları kullanmak tek başına sahneyi "Among Us" yapıyor.
]]
local CREW = {
	Color3.fromRGB(197, 17, 17),    -- red
	Color3.fromRGB(19, 46, 209),    -- blue
	Color3.fromRGB(17, 128, 45),    -- green
	Color3.fromRGB(238, 84, 187),   -- pink
	Color3.fromRGB(239, 125, 13),   -- orange
	Color3.fromRGB(245, 245, 87),   -- yellow
	Color3.fromRGB(63, 71, 78),     -- black
	Color3.fromRGB(215, 224, 240),  -- white
	Color3.fromRGB(107, 47, 187),   -- purple
	Color3.fromRGB(113, 73, 30),    -- brown
	Color3.fromRGB(56, 254, 220),   -- cyan
	Color3.fromRGB(80, 240, 57),    -- lime
}

local function crewColor(i: number): Color3
	return CREW[(i - 1) % #CREW + 1]
end

--[[
	Bölge kimliği. İki sıra üs birbirinin aynıydı; hangi taraftasın anlamak
	için tabela okumak gerekiyordu. Üst sıra soğuk, alt sıra sıcak tonda —
	bir bakışta yerini biliyorsun. Üs sahibinin rengiyle karışmasın diye
	ikisi de doygunluğu düşük.
]]
-- Doygunluk kasten düşük: bunlar boya, ışık değil. Parlak tonlar
-- mürettebat tulumlarına ayrıldı.
local ZONE_COOL = Color3.fromRGB(88, 140, 150)
local ZONE_WARM = Color3.fromRGB(176, 132, 74)

local function zoneColor(row: number): Color3
	return if row % 2 == 0 then ZONE_COOL else ZONE_WARM
end

-- ─── Yardımcılar ────────────────────────────────────────────────────────────

local old = workspace:FindFirstChild("Decor")
if old then
	old:Destroy()
end

local root = Instance.new("Folder")
root.Name = "Decor"
root.Parent = workspace

local function group(name: string, parent: Instance?): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent or root
	return f
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function glow(part: Part, color: Color3, range: number, brightness: number)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Parent = part
end

--[[
	═══ IŞIK SINIFLARI ═══════════════════════════════════════════════════════

	"Her yerde çok fazla neon parıltısı var" şikâyetinin sebebi teknikti:
	parlayan yüzey her seferinde elle kuruluyordu (`material = Neon` + bazen
	`glow`). Otuz yedi ayrı çağrı, otuz yedi ayrı karar. Kimse toplamına
	bakmadığı için sahne yavaş yavaş ışık tablosuna döndü.

	Çözüm kural koymak: parlayan HER yüzey aşağıdaki dört sınıftan birine
	girer. Sınıf; malzemeyi, rengin ne kadar kısılacağını ve ışık salıp
	salmayacağını belirler. Denge bozulursa tek yerden ayarlanır.

	  Fixture  — gerçek armatür. Tam parlak + PointLight. SADECE tavan
	             lambaları, duvar aplikleri, acil düğmesi, ışınlanma feneri.
	             Sahnede otuzu geçmemeli.
	  Screen   — konsol ekranı, pano. Orta parlaklık, ışık SAÇMAZ. Ekranın
	             kendisi görünür ama odayı aydınlatmaz.
	  Indicator— küçük gösterge, ampul, şerit ucu. Kısık parlaklık, ışık yok.
	             Sadece 3 studdan küçük parçalarda.
	  Paint    — uzun hat, zemin çizgisi, çerçeve, bant. HİÇ parlamaz; mat
	             boya. Eskiden bunların çoğu neondu, asıl parıltı buradan
	             geliyordu.

	Renk kısma çarpanla değil Lerp ile yapılıyor: Neon malzemesi rengi
	doğrudan parlaklık olarak bastığı için siyaha doğru harmanlamak,
	çarpmaktan daha öngörülebilir bir sönüm veriyor.
]]
type EmitClass = "Fixture" | "Screen" | "Indicator" | "Paint"

local EMIT: { [string]: { material: Enum.Material, dim: number, light: boolean } } = {
	Fixture = { material = Enum.Material.Neon, dim = 0.00, light = true },
	Screen = { material = Enum.Material.Neon, dim = 0.45, light = false },
	Indicator = { material = Enum.Material.Neon, dim = 0.62, light = false },
	Paint = { material = Enum.Material.SmoothPlastic, dim = 0.00, light = false },
}

--[[
	Verilen sınıfa göre parçanın malzemesini ve rengini ayarlar; Fixture ise
	ışığını da takar. `range`/`brightness` sadece Fixture'da anlamlı.
]]
local function emit(part: Part, class: EmitClass, color: Color3, range: number?, brightness: number?): Part
	local spec = EMIT[class]
	part.Material = spec.material
	part.Color = if spec.dim > 0 then color:Lerp(Color3.new(0, 0, 0), spec.dim) else color

	if spec.light and range then
		glow(part, color, range, brightness or 1)
	end
	return part
end

type Opts = {
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	collide: boolean?,
	transparency: number?,
	shape: Enum.PartType?,
	parent: Instance,
	name: string?,

	--[[
		Parlayan yüzeyler `material` yerine BUNU kullanır. Çağrı yerinde
		"hangi malzeme" değil "bu ne işe yarıyor" yazıyor; parlaklık kararı
		tek yerde (EMIT tablosu) kalıyor.
	]]
	emit: EmitClass?,
	range: number?,        -- sadece Fixture: ışık menzili
	brightness: number?,   -- sadece Fixture: ışık şiddeti
}

--[[
	Bir parçanın katı olup olmadığına karar verir.

	Varsayılan KATI. Eskiden geçirgendi ve dekorun tamamı içinden
	geçilebiliyordu: gemi duvarları, sütunlar, kasalar, korkuluklar. "Katı
	görünen şey katıdır" bir oyunun en temel beklentisi ve tersi haritayı
	inandırıcılıktan çıkarıyordu.

	İki istisna otomatik, çünkü ikisi de katı OLMAMALI:

	  - Işık veren yüzeyler (emit). Lamba, parıltı, ışın huzmesi. Bunlar
	    hacim değil ışık; katı olsalar oyuncu havada takılırdı.

	  - Yere yatık ince kaplamalar (yükseklik <= 0.6). Zemin boyası, şerit,
	    ok işareti. Katı olsalar zeminin bir tık üstünde yürünür, adım sesi
	    ve kamera bozulurdu.

	Bunların dışında bir şeyin geçirgen olması gerekiyorsa çağrı yerinde
	`collide = false` yazılmalı — yani bilinçli bir karar olmalı, unutulmuş
	bir varsayılan değil.
]]
local function isSolid(o: Opts): boolean
	if o.collide ~= nil then
		return o.collide
	end
	if o.emit ~= nil then
		return false
	end
	if o.size.Y <= 0.6 then
		return false
	end
	return true
end

local function build(o: Opts): Part
	local p = Instance.new("Part")
	p.Name = o.name or "Deco"
	p.Size = o.size
	p.CFrame = o.cf
	p.Color = o.color
	p.Material = o.material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = isSolid(o)
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = o.transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.shape then
		p.Shape = o.shape
	end
	p.Parent = o.parent

	if o.emit then
		emit(p, o.emit, o.color, o.range, o.brightness)
	end
	return p
end


--[[
	Mürettebat heykeli. UnitModel'deki karakterin aynı geometrisi, ölçeklenmiş
	ve kaideye oturtulmuş hâli: dikey silindir gövde, küre kafa, vizör, sırt
	çantası, iki bacak. Ayrı bir mesh indirmek yerine aynı dili kullanıyoruz —
	sahadaki karakterlerle heykeller birbirinin aynı okunsun diye.

	`scale` 1 iken karakter ~4 stud; heykellerde 3-4 arası kullanılıyor.
	Dönüş `yaw` derece cinsinden; heykel oraya BAKAR.
]]
local function crewStatue(parent: Instance, x: number, z: number, y: number, scale: number, color: Color3, yaw: number)
	local base = CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw), 0)
	local s = scale

	-- Gövde: silindir ekseni X, dikey durması için Z etrafında 90°
	local body = build({
		name = "StatueBody", size = Vector3.new(2.0 * s, 2.4 * s, 2.0 * s),
		cf = base * CFrame.new(0, 1.8 * s, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color = color, shape = Enum.PartType.Cylinder, parent = parent,
	})
	body.Reflectance = 0.04

	build({
		name = "StatueHead", size = Vector3.new(2.0 * s, 2.0 * s, 2.0 * s),
		cf = base * CFrame.new(0, 3.0 * s, 0),
		color = color, shape = Enum.PartType.Ball, parent = parent,
	})

	local visor = build({
		name = "StatueVisor", size = Vector3.new(1.35 * s, 0.85 * s, 0.6 * s),
		cf = base * CFrame.new(0, 3.05 * s, -0.85 * s),
		color = Color3.fromRGB(150, 220, 255), material = Enum.Material.Glass, parent = parent,
	})
	visor.Reflectance = 0.3

	build({
		name = "StatuePack", size = Vector3.new(0.8 * s, 1.9 * s, 0.9 * s),
		cf = base * CFrame.new(0, 2.0 * s, 1.25 * s), color = color, parent = parent,
	})

	for i, offset in { -0.55, 0.55 } do
		build({
			name = "StatueLeg" .. i, size = Vector3.new(0.75 * s, 1.3 * s, 1.0 * s),
			cf = base * CFrame.new(offset * s, 0.65 * s, 0), color = color, parent = parent,
		})
	end
end

-- ─── 1. Güverte ─────────────────────────────────────────────────────────────
--[[
	Zemin baştan yazıldı. Eskisi tek koyu levha + birkaç neon dikişti; uzaktan
	"zemin yok, boşlukta duruyoruz" gibi görünüyordu ve yakından tamamen
	düzdü.

	Skeld'in zemini plakalı: kare çelik levhalar, aralarında gerçek oluk,
	kenarlarda perçin, yürüyüş yollarında sarı-siyah uyarı şeridi ve yer yer
	havalandırma ızgarası. Hepsi FİZİKSEL geometri — parlayan çizgi değil.
	Işık tavandan gelsin, zeminden değil.
]]

local TILE = 23                   -- plaka kenarı (stud)

--[[
	Güvertenin GÖRÜNEN üstü. Ham zemin y=0'da ama üstünde 0.24 kalınlığında
	plaka döşemesi var; zemine yatan her işaret (bay pedi, bölge bandı, yön
	oku, havalandırma kapağı) bunun üstünden başlamak zorunda. Yoksa
	plakaların içinde kalıp kamera açısına göre görünüp kayboluyorlar —
	"gri platform yok olup geri geliyor" şikâyetinin sebebi tam olarak buydu.
]]
local DECK_TOP = 0.24 + LIFT

do
	local f = group("Floor")

	build({
		name = "Deck",
		size = Vector3.new(halfW * 2, 1, halfD * 2),
		cf = at(centerX, -0.5, centerZ),
		color = GROOVE,
		material = Enum.Material.Metal,
		collide = true,
		parent = f,
	})

	--[[
		Plaka ızgarası. Güvertenin tamamını tek tek karelerle döşemek yerine
		kareleri güverteden 0.12 yukarıda duran levhalar olarak koyuyoruz;
		aralarındaki 0.9 studluk boşluktan altındaki koyu gövde görünüyor ve
		oluk kendiliğinden oluşuyor. Ek parça harcamadan derinlik.

		İki ton dama deseninde değişiyor — düz tek renk levha dizisi göze
		"tekrar eden doku" olarak okunuyor, hafif fark onu kırıyor.
	]]
	local cols = math.ceil(halfW * 2 / TILE)
	local rows = math.ceil(halfD * 2 / TILE)
	local x0 = centerX - halfW
	local z0 = centerZ - halfD

	local plates = group("Plates", f)
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			local w = math.min(TILE, halfW * 2 - i * TILE) - 0.9
			local d = math.min(TILE, halfD * 2 - j * TILE) - 0.9
			if w < 2 or d < 2 then
				continue
			end
			build({
				name = "Plate",
				size = Vector3.new(w, 0.24, d),
				cf = at(x0 + i * TILE + (w + 0.9) / 2, 0.12 + LIFT, z0 + j * TILE + (d + 0.9) / 2),
				color = if (i + j) % 2 == 0 then DECK else DECK_ALT,
				material = Enum.Material.Metal,
				parent = plates,
			})
		end
	end

	--[[
		Perçinler. Plaka köşelerine küçük silindirler. Ölçek hissini bunlar
		veriyor: perçin 0.6 stud olduğu için oyuncu zemine bakınca büyüklüğünü
		karşılaştıracak bir referans buluyor. Her kesişime değil, ikide bire
		koyuyoruz — hem parça sayısı yarıya iniyor hem de sıklık gerçekçi.
	]]
	local rivets = group("Rivets", f)
	for i = 1, cols - 1, 2 do
		for j = 1, rows - 1, 2 do
			-- Silindirin ekseni yerel X. Dik durması (yassı disk olması) için
			-- uzunluğu X'e yazıp Z etrafında 90° çeviriyoruz.
			build({
				name = "Rivet",
				size = Vector3.new(0.2, 0.8, 0.8),
				cf = at(x0 + i * TILE, 0.3 + LIFT, z0 + j * TILE) * CFrame.Angles(0, 0, math.rad(90)),
				color = TRIM,
				material = Enum.Material.Metal,
				shape = Enum.PartType.Cylinder,
				parent = rivets,
			})
		end
	end

	--[[
		Yürüyüş yolları. Üs sıralarının önünden ve iki sıranın arasından geçen
		bantlar; kenarları sarı-siyah uyarı şeridi. Neon çizgi yerine boyalı
		zemin: Skeld'de yön bilgisi hep boya ile verilir.
	]]
	local paint = group("Walkway", f)

	--[[
		`along` "x" ise yol x boyunca uzanır, "z" ise z boyunca. Kenar şeridi
		her zaman yolun uzun kenarlarına geliyor.
	]]
	local function walkway(cx: number, cz: number, length: number, width: number, along: string)
		local function box(l: number, w: number): Vector3
			return if along == "x" then Vector3.new(l, 0.1, w) else Vector3.new(w, 0.1, l)
		end

		build({
			name = "WalkPaint",
			size = box(length, width),
			cf = at(cx, 0.28 + LIFT, cz),
			color = DECK_ALT:Lerp(Color3.fromRGB(150, 160, 180), 0.3),
			material = Enum.Material.SmoothPlastic,
			parent = paint,
		})

		-- Kenarlarda kesikli sarı-siyah uyarı şeridi
		local step = 6
		local count = math.floor(length / step)
		for _, side in { -1, 1 } do
			for i = 0, count - 1 do
				local offset = -length / 2 + (i + 0.5) * step
				local px = if along == "x" then cx + offset else cx + side * width / 2
				local pz = if along == "x" then cz + side * width / 2 else cz + offset
				build({
					name = "WalkStripe",
					size = box(step * 0.55, 0.9),
					cf = at(px, 0.3 + LIFT, pz),
					color = if i % 2 == 0 then HAZARD else HAZARD_DARK,
					material = Enum.Material.SmoothPlastic,
					parent = paint,
				})
			end
		end
	end

	--[[
		Sadece iki ana yol var: sıralar arasındaki omurga ve her üssü ona
		bağlayan dikey bağlantılar. Üslerin ÖNÜNDEN geçen bir yol denendi ama
		altlık kenarına (halfZ+3) ve kablo hattına (halfZ+12) denk geliyordu;
		aynı yükseklikteki iki yüzey titriyordu. Dikey bağlantılar hem temiz
		hem de "üsten çık, koridora gir, karşıya geç" akışını anlatıyor.
	]]
	if ROWS > 1 then
		walkway(centerX, centerZ, halfW * 2 - 12, 14, "x")

		for i = 1, COLUMNS do
			local lx = (i - 1) * PLOT_SPACING
			for r = 0, ROWS - 1 do
				local z = r * ROW_SPACING
				local side = if z < centerZ then 1 else -1
				local from = z + side * (halfZ + 4)
				local to = centerZ - side * 7
				walkway(lx, (from + to) / 2, math.abs(to - from), 8, "z")
			end
		end
	else
		walkway(centerX, centerZ, halfW * 2 - 12, 14, "x")
	end

	--[[
		Havalandırma ızgaraları. Çukur bir çerçeve + içinde paralel çıtalar.
		Duvar diplerine ve koridor kesişimlerine dağıtılmış. Zeminin "içinde
		bir şeyler var" hissini bunlar veriyor; tamamen düz bir güverte hep
		kartondan görünür.
	]]
	local grates = group("Grates", f)

	local function grate(x: number, z: number, w: number, d: number)
		-- Karanlık çukur: plakaların üstünde ama ince, altında boşluk varmış
		-- gibi okunsun diye neredeyse siyah.
		build({ name = "GrateWell", size = Vector3.new(w, 0.3, d),
			cf = at(x, 0.32 + LIFT, z), color = Color3.fromRGB(16, 20, 29),
			material = Enum.Material.Metal, parent = grates })

		-- Çevre lipi: dört ince çıta, dolu levha değil — ortası çukur kalsın
		for _, s in { -1, 1 } do
			build({ name = "GrateLip", size = Vector3.new(w + 1.4, 0.4, 0.7),
				cf = at(x, 0.38 + LIFT, z + s * (d / 2 + 0.35)), color = TRIM,
				material = Enum.Material.Metal, parent = grates })
			build({ name = "GrateLip", size = Vector3.new(0.7, 0.4, d + 1.4),
				cf = at(x + s * (w / 2 + 0.35), 0.38 + LIFT, z), color = TRIM,
				material = Enum.Material.Metal, parent = grates })
		end

		-- Çıtalar: aralarından karanlık görünüyor
		local bars = math.max(2, math.floor(w / 1.9))
		for i = 1, bars do
			build({ name = "GrateBar", size = Vector3.new(0.6, 0.42, d - 0.6),
				cf = at(x - w / 2 + i * (w / (bars + 1)), 0.4 + LIFT, z),
				color = Color3.fromRGB(62, 71, 90),
				material = Enum.Material.Metal, parent = grates })
		end
	end

	for i = 1, COLUMNS do
		local gx = (i - 1) * PLOT_SPACING
		grate(gx, centerZ - halfD + 10, 10, 7)
		grate(gx, centerZ + halfD - 10, 10, 7)
	end
	for c = 1, COLUMNS - 1 do
		grate((c - 0.5) * PLOT_SPACING, centerZ, 8, 8)
	end
end

-- ─── 2. Çeper: dört tarafta pencereli duvar ─────────────────────────────────

do
	local f = group("Hull")
	local SEG, WINDOW = 24, 18

	--[[ Bir kenar boyunca panel-pencere-panel dizisi kurar.
	     axis "x": duvar x boyunca uzanır (ön/arka). "z": z boyunca (yanlar). ]]
	--[[
		`anchor` desenin hangi uçtan başlayacağını söyler.

		Kapının iki yanındaki duvarlar aynı uzunlukta ama ikisi de SOL
		uçtan başlıyordu. Panel-pencere dizisi soldan sağa yürüdüğü için
		kapıya varıldığında iki tarafta farklı eleman kalıyordu: bir yanda
		pencere, öbür yanda düz panel. Girişte göze çarpan asimetri buydu.

		anchor = "end" verildiğinde desen sağ uçtan sola yürüyor; böylece
		kapının iki yanı birbirinin aynadaki görüntüsü oluyor.
	]]
	local function wall(axis: string, fixed: number, from: number, to: number, facing: number, anchor: string?)
		local mirror = anchor == "end"

		local function place(name: string, along: number, width: number, height: number, y: number, thick: number, color: Color3, material: Enum.Material, collide: boolean, trans: number?)
			-- Ayna modunda konum, aralığın diğer ucuna göre yansıtılıyor
			local at2 = if mirror then (from + to) - along else along
			local size = if axis == "x"
				then Vector3.new(width, height, thick)
				else Vector3.new(thick, height, width)
			local cf = if axis == "x"
				then at(at2, y, fixed)
				else at(fixed, y, at2)
			build({ name = name, size = size, cf = cf, color = color, material = material, collide = collide, transparency = trans, parent = f })
		end

		local length = to - from
		local mid = (from + to) / 2

		-- Alt bant: kesintisiz
		place("Kick", mid, length, 3.5, 1.75, 2.4, TRIM, Enum.Material.Metal, true)

		local cursor = from
		while cursor < to do
			local w = math.min(SEG, to - cursor)
			place("Panel", cursor + w / 2, w, WALL_H - 3.5, 3.5 + (WALL_H - 3.5) / 2, 2.4, HULL, Enum.Material.Metal, true)

			cursor += w
			if cursor >= to then break end

			--[[
				Pencere. Önceki hali sadece 0.75 saydam koyu bir levhaydı;
				dışarısı zaten siyah olduğu için duvardan ayırt edilmiyordu.
				Şimdi gerçek bir açıklık: cam neredeyse tamamen şeffaf,
				etrafında metal çerçeve ve altında neon hat var. Çerçeve
				olmadan göz "burada pencere var" diyemiyor.
			]]
			local g = math.min(WINDOW, to - cursor)
			local center = cursor + g / 2
			local openBottom = 9
			local openTop = WALL_H - 5
			local openH = openTop - openBottom
			local openMid = (openBottom + openTop) / 2

			--[[
				Cam KATI olmalı. İlk halinde CanCollide kapalıydı ve açıklık
				gerçek bir delikti — oyuncu pencereden dışarı atlayıp boşluğa
				düşüyordu. Geçilmez ama bakılabilir.

				Saydamlık 0.93'ten 0.72'ye indi. Neredeyse tamamen şeffafken
				camın kendisi görünmüyordu: dışarısı siyah olduğu için duvarda
				kara bir boşluk gibi duruyordu, "orada cam var" okunmuyordu.
				0.72'de yüzey hafifçe yakalıyor ve pencere pencere gibi duruyor.
			]]
			place("Glass", center, g, openH, openMid, 0.5, GLASS, Enum.Material.Glass, true, 0.72)

			--[[
				Camı bölen çıtalar: biri dikey ortada, biri yatay.

				Kenar çıtaları (aşağıdaki WinMullion'lar) zaten vardı ama
				açıklığın ORTASI tek parça bir levhaydı ve ne kadar büyük
				olduğu okunmuyordu. Bölünmüş cam ölçeğini kendi veriyor.

				Alt kenardaki neon hat zaten var (WinGlow), tekrarlanmadı.
			]]
			place("WinBar", center, 0.5, openH, openMid, 0.7, TRIM, Enum.Material.Metal, true)
			place("WinTransom", center, g, 0.5, openMid, 0.7, TRIM, Enum.Material.Metal, true)

			place("WinBelow", center, g, openBottom - 3.5, 3.5 + (openBottom - 3.5) / 2, 2.4, HULL, Enum.Material.Metal, true)
			place("WinAbove", center, g, WALL_H - openTop, openTop + (WALL_H - openTop) / 2, 2.4, HULL, Enum.Material.Metal, true)

			place("WinRail", center, g + 1.6, 1, openBottom, 3, TRIM, Enum.Material.Metal, false)
			place("WinRail", center, g + 1.6, 1, openTop, 3, TRIM, Enum.Material.Metal, false)

			for _, s in { -1, 1 } do
				place("WinMullion", center + s * (g / 2), 1.4, openH + 2, openMid, 3, TRIM, Enum.Material.Metal, false)
			end

			place("WinSill", center, g + 0.8, 0.7, openBottom - 0.4, 3.2, TRIM, Enum.Material.Metal, false)

			cursor += g
		end

		-- Üst korniş
		place("Cornice", mid, length, 1.6, WALL_H + 0.8, 4, TRIM, Enum.Material.Metal, false)
	end

	local x0, x1 = centerX - halfW, centerX + halfW
	local z0, z1 = centerZ - halfD, centerZ + halfD

	--[[
		Ön duvarda lobiye açılan kapı boşluğu. Duvarı tek parça kurmak yerine
		boşluğun iki yanına ayrı ayrı kuruyoruz — fonksiyona "burayı atla"
		mantığı eklemekten basit ve okunaklı.
	]]
	local gapHalf = LOBBY_GATE_WIDTH / 2

	wall("x", z0, x0, x1, -1)
	-- Kapının iki yanı aynadaki gibi: sol parça sondan başlıyor
	wall("x", z1, x0, centerX - gapHalf, 1, "end")
	wall("x", z1, centerX + gapHalf, x1, 1)
	wall("z", x0, z0, z1, -1)
	wall("z", x1, z0, z1, 1)

	-- Kapı boşluğunun kenar dikmeleri ve üst kirişi
	for _, s in { -1, 1 } do
		build({ name = "GateJamb", size = Vector3.new(2.6, WALL_H, 3.4),
			cf = at(centerX + s * gapHalf, WALL_H / 2, z1),
			color = TRIM, material = Enum.Material.Metal, collide = true, parent = f })
	end
	build({ name = "GateLintel", size = Vector3.new(LOBBY_GATE_WIDTH + 5, 3, 3.4),
		cf = at(centerX, WALL_H - 1.5, z1), color = HULL,
		material = Enum.Material.Metal, collide = true, parent = f })
	build({ name = "GateGlow", size = Vector3.new(LOBBY_GATE_WIDTH + 2, 0.3, 0.5),
		cf = at(centerX, WALL_H - 3.4, z1 - 1.6), color = NEON,
		emit = "Paint", parent = f })

	-- ─── Gövde altı: kalınlık hissi ─────────────────────────────────────────
	-- Kademeli daralan üç katman: yandan bakınca gemi gövdesi gibi

	build({
		name = "HullUpper",
		size = Vector3.new(halfW * 2 - 4, HULL_DEPTH * 0.45, halfD * 2 - 4),
		cf = at(centerX, -HULL_DEPTH * 0.225 - 0.5, centerZ),
		color = HULL,
		material = Enum.Material.Metal,
		parent = f,
	})
	build({
		name = "HullMid",
		size = Vector3.new(halfW * 2 - 26, HULL_DEPTH * 0.35, halfD * 2 - 26),
		cf = at(centerX, -HULL_DEPTH * 0.63 - 0.5, centerZ),
		color = HULL_DARK,
		material = Enum.Material.Metal,
		parent = f,
	})
	build({
		name = "Keel",
		size = Vector3.new(halfW * 2 - 70, HULL_DEPTH * 0.3, halfD * 2 - 70),
		cf = at(centerX, -HULL_DEPTH * 0.92 - 0.5, centerZ),
		color = TRIM,
		material = Enum.Material.Metal,
		parent = f,
	})

	-- Gövde boyunca yatay kaburga çizgileri: ölçek hissi verir
	for i = 0, COLUMNS do
		local x = (i - 0.5) * PLOT_SPACING
		build({
			name = "Rib",
			size = Vector3.new(1.4, HULL_DEPTH * 0.45, halfD * 2 - 2),
			cf = at(x, -HULL_DEPTH * 0.225 - 0.5, centerZ),
			color = TRIM,
			material = Enum.Material.Metal,
			parent = f,
		})
	end

	-- Alt kenarda konum ışıkları
	for i = 0, COLUMNS do
		local x = (i - 0.5) * PLOT_SPACING
		for _, side in { -1, 1 } do
			local lamp = build({
				name = "MarkerLight",
				size = Vector3.new(1.6, 1.6, 1.6),
				cf = at(x, -HULL_DEPTH * 0.45, centerZ + side * (halfD - 3)),
				color = NEON_WARM,
				emit = "Indicator",
				shape = Enum.PartType.Ball,
				parent = f,
			})
		end
	end
end

-- ─── 3. Üs başına detay ─────────────────────────────────────────────────────

do
	local f = group("Plots")
	local FRAME_H = 0.25
	local PILLAR = 2.4
	local PILLAR_H = 14

	for index = 1, PLOT_COUNT do
		local o = plotOrigin(index)
		local ox, oz = o.X, o.Z
		local pf = group(string.format("Plot%d", index), f)

		--[[
			Altlığın üstü güvertenin üstüyle aynı hizada olmamalı. İkisi de
			y=0'da olunca Roblox hangisini çizeceğine karar veremiyor ve
			kamera oynadıkça yüzeyler birbirinin önüne geçip titriyordu
			(z-fighting). 0.3 yukarı alınca altlık ayrı bir basamak oluyor.
		]]
		build({
			name = "Plinth",
			size = Vector3.new(PLOT_SIZE.X + 6, 1.6, PLOT_SIZE.Z + 6),
			cf = at(ox, -0.5, oz),
			color = TRIM,
			material = Enum.Material.Metal,
			collide = true,
			parent = pf,
		})

		local frameY = topY + FRAME_H / 2 + LIFT
		for _, s in { -1, 1 } do
			build({
				name = "FrameX",
				size = Vector3.new(0.8, FRAME_H, PLOT_SIZE.Z),
				cf = at(ox + s * halfX, frameY, oz),
				color = NEON_MID, emit = "Paint", parent = pf,
			})
			build({
				name = "FrameZ",
				size = Vector3.new(PLOT_SIZE.X, FRAME_H, 0.8),
				cf = at(ox, frameY, oz + s * halfZ),
				color = NEON_MID, emit = "Paint", parent = pf,
			})
		end

		--[[
			Sütunlar üssün KÖŞELERİNDE duruyordu ve oyun alanını yiyordu:
			bazı üslerde yükseltme kulübesinin önüne denk gelip kapatıyordu.

			Dışarı alındılar. Üssü çerçeveleme işlevi aynen duruyor — hatta
			daha okunur, çünkü artık sınırı gösteriyorlar — ama içeride
			kimseyi engellemiyorlar.
		]]
		--[[
			4'ten 7'ye çıktı ve ÇARPIŞMA KAPANDI.

			4'te sütun, çıkış kapağının gövdesine 0.2 stud kalıyordu
			(ölçüldü: gövde x 81.4'te bitiyor, sütun 81.2'de başlıyor).
			Kapaktan çıkan karakteri almaya giden oyuncu tam orada sütuna
			takılıyordu.

			Çarpışma da kapatıldı: bunlar üssün sınırını gösteren işaretler,
			duvar değil. Katı kalmalarının oyuna hiçbir katkısı yok, köşede
			sıkışmanın ise bariz zararı var.
		]]
		local PILLAR_OUT = 7

		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local px = ox + sx * (halfX + PILLAR_OUT)
				local pz = oz + sz * (halfZ + PILLAR_OUT)

				--[[
					collide = false AÇIKÇA yazılıyor.

					Dekorun varsayılanı artık katı (bkz. isSolid) ve bu
					doğru bir varsayılan. Ama bu dört sütun üssün köşesinde,
					tam da oyuncunun kapaktan çıkan karakteri almaya
					koştuğu yerde duruyor. Sınırı göstermeleri yeterli;
					katı olmalarının oyuna katkısı yok, köşede sıkışmanın
					ise bariz zararı var.
				]]
				build({ name = "Pillar", size = Vector3.new(PILLAR, PILLAR_H, PILLAR),
					cf = at(px, topY + PILLAR_H / 2, pz), color = HULL,
					material = Enum.Material.Metal, collide = false, parent = pf })
				build({ name = "PillarBand", size = Vector3.new(PILLAR + 0.5, 0.45, PILLAR + 0.5),
					cf = at(px, topY + PILLAR_H * 0.62, pz), color = TEAL,
					-- 8 üste 4'er tane, yani 32 adet. Gösterge sınıfında
					-- havada parlayan 32 halka oluyordu; boyalı bant yeter.
					emit = "Paint", parent = pf })
				build({ name = "PillarCap", size = Vector3.new(PILLAR + 1, 0.7, PILLAR + 1),
					cf = at(px, topY + PILLAR_H + 0.35, pz), color = TRIM,
					material = Enum.Material.Metal, parent = pf })

				-- Sütun tepesindeki ışık: 8 üste 4'er tane, hepsi camgöbeği
				-- olunca sahneyi maviye boğuyordu. Nötr beyaz aydınlatıyor,
				-- renk vurgusunu sütundaki bant yapıyor.
				local lamp = build({ name = "CapLamp", size = Vector3.new(PILLAR * 0.6, 0.5, PILLAR * 0.6),
					cf = at(px, topY + PILLAR_H + 0.9, pz), color = LAMP,
					emit = "Fixture", parent = pf })
				glow(lamp, LAMP, 18, 0.5)
			end
		end

		-- Kaide halkaları
		local perRow = math.ceil(PODIUMS / 2)
		for slot = 1, PODIUMS do
			local front = slot <= perRow
			local col = if front then slot - 1 else slot - perRow - 1
			--[[
				Kaide zemini. Eskiden yarı saydam mavi bir neon kareydi;
				uzaktan zemine yapıştırılmış çıkartma gibi duruyor ve üssün
				zeminiyle hizası tutmuyordu. Şimdi fiziksel bir basamak:
				koyu plaka + üstünde metal kenar çıtası. Karakterin üstünde
				durduğu yer olduğu belli oluyor.
			]]
			local px = ox + (col - (perRow - 1) / 2) * PODIUM_GAP
			-- Gerçek kaidelerle aynı sayı; ayrı yazılıydı ve bir stud kayıyordu
			local pz = oz + (if front then -PODIUM_ROW_Z else PODIUM_ROW_Z)

			build({
				name = "PodiumPad",
				size = Vector3.new(5.6, 0.3, 5.6),
				cf = at(px, topY + 0.15 + LIFT, pz),
				color = HULL_DARK, material = Enum.Material.Metal, parent = pf,
			})
			for _, s in { -1, 1 } do
				build({ name = "PodiumEdge", size = Vector3.new(6, 0.36, 0.5),
					cf = at(px, topY + 0.18 + LIFT, pz + s * 2.75),
					color = TRIM, material = Enum.Material.Metal, parent = pf })
				build({ name = "PodiumEdge", size = Vector3.new(0.5, 0.36, 6),
					cf = at(px + s * 2.75, topY + 0.18 + LIFT, pz),
					color = TRIM, material = Enum.Material.Metal, parent = pf })
			end
		end

		--[[
			═══ KONVEYÖR SAHNESİ ═══════════════════════════════════════════

			AYNALAMA. PlotService çift satırlı düzende ÜST satırı 180°
			çeviriyor (satırlar koridora baksın diye). Dekor çevrilmiyordu:
			üst satırdaki dört üste bant, kapak ve giriş makinesi gerçek
			konveyörün TAM TERSİ tarafında duruyordu. Ölçüldü: Plot2'nin
			konveyörü z=-21'de, kapağı z=+21'deydi.

			`flip` bu farkı kapatıyor. Aynı formül PlotService'teki dönme
			koşulunun aynısı; biri değişirse diğeri de değişmeli.

			ÖLÇÜ. Kapaklar 11x9x7'ydi ve üssün içinde iki dev kutu gibi
			duruyorlardı ("portalların dizaynı berbat ve çok büyük"). Yeni
			hâl bir gemi hava kilidi gibi: alçak, geniş değil derin, etrafı
			çerçeveli ve içi karanlık. Işık sadece ağızdan geliyor.
		]]
		local rowIndex = math.floor((index - 1) / COLUMNS)
		local flip = if ROWS > 1 and rowIndex % 2 == 0 then -1 else 1

		local convZ = oz + flip * (halfZ - 5)

		--[[
			BANT YÜKSEKLİĞİ. Dekor şimdiye kadar üssün güvertesinden (topY)
			kuruluyordu ama karakterler gerçek Conveyor parçasının ÜSTÜNDE
			yürüyor: parça topY+0.5'te ve 1 stud kalın, yani yürüme yüzeyi
			topY+1. Aradaki farktan dolayı karakterler dekoratif çıtaların
			havasında süzülüyor, kapaklar da onların altında kalıyordu —
			"tam ortadan çıkmıyor" bundandı.

			beltLen, ConveyorService'in kullandığı mesafenin AYNISI:
			travel = Conveyor.Size.X - 4 = (PLOT_SIZE.X - 8) - 4.
		]]
		local beltY = topY + 1
		local beltLen = PLOT_SIZE.X - 12

		for _, e in { -1, 1 } do
			build({ name = "HazardStrip", size = Vector3.new(beltLen + 4, 0.12, 0.7),
				cf = at(ox, beltY + 0.06 + LIFT, convZ + e * 3.2), color = HAZARD,
				emit = "Paint", parent = pf })
		end

		--[[
			Hava kilidi. İki uçta aynı gövde, sadece ağzın rengi ve baktığı
			yön farklı: çıkışta sıcak sarı, girişte soğuk turkuaz. `dir` +1
			ise makine +x yönüne bakıyor.

			`flip` x eksenine de uygulanıyor: üs 180° döndüğünde çıkış ucu da
			yer değiştirmeli, yoksa karakterler yanlış uçtan doğuyor.
		]]
		local function airlock(name: string, ax: number, dir: number, tone: Color3, bright: number)
			local W, H, D = 8, 7, 5.6      -- eski: 11 x 9 x 7

			-- Çerçeve: dört ince kenar, dolu kutu değil
			for _, e in { -1, 1 } do
				build({ name = name .. "Jamb", size = Vector3.new(1.1, H, 1.1),
					cf = at(ax, beltY + H / 2, convZ + e * (D / 2 - 0.4)),
					color = TRIM, material = Enum.Material.Metal, parent = pf })
			end
			build({ name = name .. "Lintel", size = Vector3.new(1.6, 1.2, D + 1),
				cf = at(ax, beltY + H, convZ), color = TRIM,
				material = Enum.Material.Metal, parent = pf })
			build({ name = name .. "Sill", size = Vector3.new(1.6, 0.5, D + 1),
				cf = at(ax, beltY + 0.25, convZ), color = TRIM,
				material = Enum.Material.Metal, parent = pf })

			-- Gövde: çerçevenin ARKASINDA, üsse taşmıyor
			build({ name = name .. "Body", size = Vector3.new(W, H + 1.4, D + 2.6),
				cf = at(ax + dir * (W / 2 + 0.6), beltY + (H + 1.4) / 2, convZ),
				color = HULL, material = Enum.Material.Metal, parent = pf })
			build({ name = name .. "Cap", size = Vector3.new(W + 1.2, 0.9, D + 3.4),
				cf = at(ax + dir * (W / 2 + 0.6), beltY + H + 1.8, convZ),
				color = STEEL, material = Enum.Material.Metal, parent = pf })

			-- Karanlık boğaz: içeriye devam ettiği hissi
			build({ name = name .. "Throat", size = Vector3.new(W - 1, H - 1, D - 1),
				cf = at(ax + dir * (W / 2 + 0.4), beltY + (H - 1) / 2 + 0.5, convZ),
				color = SHADOW, material = Enum.Material.SmoothPlastic, parent = pf })

			-- Ağız: tek ışık kaynağı
			local mouth = build({ name = name .. "Mouth", size = Vector3.new(0.35, H - 1.6, D - 1.4),
				cf = at(ax, beltY + (H - 1.6) / 2 + 0.6, convZ),
				color = tone, emit = "Fixture", transparency = 0.3, parent = pf })
			glow(mouth, tone, 14, bright)

			-- Uyarı şeridi: çerçevenin üstünde kısa kesikler
			for i = -1, 1 do
				build({ name = name .. "Mark", size = Vector3.new(1.1, 0.4, 0.9),
					cf = at(ax, beltY + H + 0.9, convZ + i * 1.7),
					color = if i == 0 then HAZARD else HAZARD_DARK,
					emit = "Paint", parent = pf })
			end
		end

		local dx = ox - flip * beltLen / 2
		local ix = ox + flip * beltLen / 2

		airlock("Hatch", dx, -flip, NEON_WARM, 1.1)
		airlock("Intake", ix, flip, TEAL, 0.8)

		--[[
			Bant çıtaları. Kayma yönü de aynalanıyor: SlideRange negatif
			olamıyor, o yüzden başlangıç noktası flip'e göre seçiliyor ve
			çıtalar her zaman kapaktan girişe doğru akıyor.
		]]
		local SLATS = 8
		local slatGap = beltLen / SLATS
		for i = 0, SLATS - 1 do
			local slat = build({
				name = "BeltSlat",
				size = Vector3.new(0.9, 0.18, 4.4),
				cf = at(dx + flip * i * slatGap, beltY + 0.14 + LIFT, convZ),
				color = NEON_DIM,
				emit = "Paint",
				parent = pf,
			})
			slat:SetAttribute("SlideSpeed", 5 * flip)
			slat:SetAttribute("SlideRange", beltLen)
		end

		-- Bant kenarındaki çıtalar
		for _, e in { -1, 1 } do
			build({ name = "BeltEdge", size = Vector3.new(beltLen, 0.5, 0.5),
				cf = at(ox, beltY + 0.3, convZ + e * 2.6), color = TRIM,
				material = Enum.Material.Metal, parent = pf })
		end

		-- Aynı satırdaki komşuya kemer
		local col = (index - 1) % COLUMNS
		if col < COLUMNS - 1 and index < PLOT_COUNT then
			local ax = ox + PLOT_SPACING / 2
			for _, sz in { -1, 1 } do
				build({ name = "ArchLeg", size = Vector3.new(1.6, ARCH_CLEAR, 1.6),
					cf = at(ax, ARCH_CLEAR / 2, oz + sz * (halfZ + 3)), color = HULL,
					material = Enum.Material.Metal, collide = true, parent = pf })
			end
			build({ name = "ArchBeam", size = Vector3.new(2.2, 1.6, (halfZ + 3) * 2),
				cf = at(ax, ARCH_CLEAR + 0.8, oz), color = HULL,
				material = Enum.Material.Metal, parent = pf })
			-- Kemer şeridi sıranın kimlik renginde: koridorda ilerlerken
			-- hangi bölgede olduğun üstünden geçen ışıktan okunuyor
			build({ name = "ArchGlow", size = Vector3.new(0.5, 0.2, (halfZ + 3) * 2 - 2),
				cf = at(ax, ARCH_CLEAR - 0.1, oz),
				color = zoneColor(math.floor((index - 1) / COLUMNS)):Lerp(Color3.new(0, 0, 0), 0.55),
				emit = "Paint", parent = pf })
		end
	end
end

-- ─── 4. Havalandırma kapakları ──────────────────────────────────────────────

do
	local f = group("Vents")

	local function vent(x: number, z: number)
		local cf = at(x, DECK_TOP + 0.17, z)
		build({ name = "VentFrame", size = Vector3.new(6.4, 0.24, 4.4), cf = cf,
			color = TRIM, material = Enum.Material.Metal, parent = f })
		-- Kapağın içi karanlık: altında bir kanal varmış gibi dursun
		build({ name = "VentThroat", size = Vector3.new(5.6, 0.26, 3.6),
			cf = cf * CFrame.new(0, 0.02, 0), color = Color3.fromRGB(14, 18, 26),
			material = Enum.Material.Metal, parent = f })
		for i = -1, 1 do
			build({ name = "VentSlat", size = Vector3.new(5.4, 0.3, 0.7),
				cf = cf * CFrame.new(0, 0.06, i * 1.2), color = HULL_DARK,
				material = Enum.Material.Metal, parent = f })
		end
	end

	for r = 0, ROWS - 1 do
		local z = r * ROW_SPACING
		for c = 1, COLUMNS - 1 do
			vent((c - 0.5) * PLOT_SPACING, z - halfZ - 8)
			vent((c - 0.5) * PLOT_SPACING, z + halfZ + 8)
		end
	end
end

-- ─── 5. Acil toplantı düğmesi ───────────────────────────────────────────────

do
	local f = group("EmergencyButton")

	--[[
		Düğme kapının TAM ÖNÜNDEYDİ. Lobi kapısı centerX'te ve 24 stud
		genişliğinde; düğmenin 12x12 kaidesi de centerX'teydi, yani geçidin
		ortasını tıkıyordu — "transit bölgesinde blokaj var" şikâyeti buydu.
		Yana alındı, kapı boşluğu (centerX ± 12) tamamen serbest kaldı.
	]]
	local z = centerZ + halfD - 18
	local bx = centerX + LOBBY_GATE_WIDTH / 2 + 20

	build({ name = "Base", size = Vector3.new(12, 1.2, 12), cf = at(bx, 0.6, z),
		color = TRIM, material = Enum.Material.Metal, collide = true, parent = f })
	build({ name = "Column", size = Vector3.new(6.5, 4, 6.5), cf = at(bx, 3.2, z),
		color = HULL, material = Enum.Material.Metal, collide = true, parent = f })
	build({ name = "Ring", size = Vector3.new(9.5, 0.3, 9.5), cf = at(bx, 5.3, z),
		color = NEON, emit = "Indicator", parent = f })
	build({ name = "Top", size = Vector3.new(8.5, 1, 8.5), cf = at(bx, 5.9, z),
		color = HULL, material = Enum.Material.Metal, collide = true, parent = f })

	local dome = build({ name = "Button", size = Vector3.new(4.8, 4.8, 4.8),
		cf = at(bx, 6.7, z), color = RED, emit = "Fixture",
		shape = Enum.PartType.Ball, parent = f })
	glow(dome, RED, 34, 2.4)
end

-- ─── 6. Çatı ────────────────────────────────────────────────────────────────
--[[
	Eskiden sadece kafes kiriş vardı; lambalar boşlukta asılı duruyordu ve
	"kapalı bir istasyondayız" hissi hiç kurulmuyordu — tavan yokken tavan
	lambası olmaz.

	Şimdi gerçek bir tavan var: kirişlerin üstüne panel döşemesi, panellerin
	arasına gömülü lamba yuvaları. Yıldızları tamamen kaybetmemek için ana
	koridorun üstü cam şerit bırakıldı — hem dışarısı görünüyor hem de
	"burada bir kapak var" bilgisi veriyor.
]]

do
	local f = group("Roof")
	local Y = WALL_H + 3
	local BEAM = 1.5

	-- Enine ana kirişler
	for i = 0, COLUMNS do
		local x = (i - 0.5) * PLOT_SPACING
		build({ name = "Truss", size = Vector3.new(BEAM, BEAM, halfD * 2),
			cf = at(x, Y, centerZ), color = TRIM, material = Enum.Material.Metal, parent = f })
		-- Alt payanda: kirişe derinlik verir
		build({ name = "TrussLower", size = Vector3.new(BEAM * 0.7, BEAM * 0.7, halfD * 2 - 6),
			cf = at(x, Y - 2.4, centerZ), color = HULL, material = Enum.Material.Metal, parent = f })
		-- Zikzak dikmeler
		local steps = 8
		for s = 0, steps do
			local z = centerZ - halfD + (halfD * 2) * (s / steps)
			build({ name = "TrussWeb", size = Vector3.new(BEAM * 0.5, 2.4, BEAM * 0.5),
				cf = at(x, Y - 1.2, z), color = HULL, material = Enum.Material.Metal, parent = f })
		end
	end

	-- Boyuna bağlantılar
	for i = 0, ROWS do
		local z = (i - 0.5) * (if ROWS > 1 then ROW_SPACING else halfD * 2)
		build({ name = "Purlin", size = Vector3.new(halfW * 2, BEAM * 0.8, BEAM * 0.8),
			cf = at(centerX, Y, z), color = TRIM, material = Enum.Material.Metal, parent = f })
	end

	--[[
		Tavan döşemesi. Kirişlerin hemen üstünde, panel panel. Ana koridorun
		üstündeki şerit cam bırakılıyor: yıldızlar oradan görünüyor, gerisi
		kapalı. Tek dev levha yerine panel dizisi, çünkü aralarındaki çizgi
		ölçek veriyor ve tavan "gökyüzü" değil "yapı" gibi okunuyor.
	]]
	local ceil = group("Ceiling", f)
	local CY = Y + 1.6
	local SKY_HALF = if ROWS > 1 then 9 else 0     -- cam şeridin yarı genişliği

	local panelW = PLOT_SPACING / 2
	local panelD = 26
	local nx = math.ceil(halfW * 2 / panelW)
	local nz = math.ceil(halfD * 2 / panelD)

	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local pw = math.min(panelW, halfW * 2 - i * panelW)
			local pd = math.min(panelD, halfD * 2 - j * panelD)
			if pw < 2 or pd < 2 then
				continue
			end
			local px = centerX - halfW + i * panelW + pw / 2
			local pz = centerZ - halfD + j * panelD + pd / 2

			-- Koridor camının üstüne denk gelen paneli atlıyoruz
			local overSky = SKY_HALF > 0 and math.abs(pz - centerZ) < SKY_HALF + pd / 2 - 1
			if overSky then
				continue
			end

			build({ name = "CeilPanel", size = Vector3.new(pw - 0.5, 1, pd - 0.5),
				cf = at(px, CY, pz), color = if (i + j) % 2 == 0 then HULL else HULL_DARK,
				material = Enum.Material.Metal, parent = ceil })
		end
	end

	--[[
		Çeper bandı. Duvarın üstü 34, tavan 38.6'da; arada kalan boşluktan
		yanlardan dışarısı görünüyordu ve tavan "asılı bir levha" gibi
		duruyordu. Bu bant duvarı tavana bağlıyor, mekân kapanıyor.
	]]
	for _, s in { -1, 1 } do
		build({ name = "Fascia", size = Vector3.new(halfW * 2, CY - WALL_H + 1, 2.6),
			cf = at(centerX, (WALL_H + CY) / 2, centerZ + s * halfD), color = HULL_DARK,
			material = Enum.Material.Metal, parent = ceil })
		build({ name = "Fascia", size = Vector3.new(2.6, CY - WALL_H + 1, halfD * 2),
			cf = at(centerX + s * halfW, (WALL_H + CY) / 2, centerZ), color = HULL_DARK,
			material = Enum.Material.Metal, parent = ceil })
	end

	-- Koridor camı: dışarısı görünsün
	if SKY_HALF > 0 then
		build({ name = "Skylight", size = Vector3.new(halfW * 2 - 8, 0.4, SKY_HALF * 2),
			cf = at(centerX, CY, centerZ), color = GLASS,
			material = Enum.Material.Glass, transparency = 0.55, parent = ceil })
		for _, s in { -1, 1 } do
			build({ name = "SkyRail", size = Vector3.new(halfW * 2 - 8, 1.4, 1.4),
				cf = at(centerX, CY - 0.4, centerZ + s * SKY_HALF), color = TRIM,
				material = Enum.Material.Metal, parent = ceil })
		end
	end

	--[[
		Aydınlatma artık tavana GÖMÜLÜ: koyu bir yuva, içinde sıcak beyaz
		panel. Boşlukta asılı parlak çubuk yerine gerçek armatür. Sıcak beyaz
		çünkü Skeld'in iç mekânı mavi değil, sarımsı beyaz aydınlanır.
	]]
	for i = 1, COLUMNS do
		for r = 0, ROWS - 1 do
			for _, dz in { -13, 13 } do
				local lx = (i - 1) * PLOT_SPACING
				local lz = r * ROW_SPACING + dz

				build({ name = "LampHousing", size = Vector3.new(PLOT_SIZE.X * 0.5 + 1.6, 1.1, 3.6),
					cf = at(lx, CY - 0.9, lz), color = HULL_DARK,
					material = Enum.Material.Metal, parent = f })

				local lamp = build({
					name = "RoofLamp",
					size = Vector3.new(PLOT_SIZE.X * 0.5, 0.35, 2.4),
					cf = at(lx, CY - 1.5, lz),
					color = LAMP, emit = "Fixture", parent = f,
				})
				glow(lamp, LAMP, 46, 1.4)
			end
		end
	end

	-- Koridor boyunca ara aydınlatma: iki sıra arası karanlık kalmasın
	if ROWS > 1 then
		for c = 0, COLUMNS do
			local lx = (c - 0.5) * PLOT_SPACING
			local lamp = build({ name = "CorridorLamp", size = Vector3.new(3, 0.35, 5),
				cf = at(lx, Y - 2.6, centerZ), color = LAMP,
				emit = "Fixture", parent = f })
			glow(lamp, LAMP, 34, 1.1)
		end
	end
end

-- ─── 7. Görev konsolları ────────────────────────────────────────────────────
-- Skeld'deki görev panelleri gibi: çeper duvarların dibinde eğik ekranlı masalar.

do
	local f = group("Consoles")

	local function console(x: number, z: number, yaw: number)
		local base = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0)

		build({ name = "ConsoleBody", size = Vector3.new(6, 3.4, 2.6),
			cf = base * CFrame.new(0, 1.7, 0), color = HULL,
			material = Enum.Material.Metal, collide = true, parent = f })
		build({ name = "ConsoleTop", size = Vector3.new(6.4, 0.4, 3),
			cf = base * CFrame.new(0, 3.5, 0), color = TRIM,
			material = Enum.Material.Metal, parent = f })

		-- Eğik ekran
		local screen = build({ name = "ConsoleScreen", size = Vector3.new(5.2, 3, 0.3),
			cf = base * CFrame.new(0, 5, -0.9) * CFrame.Angles(math.rad(-28), 0, 0),
			color = NEON, emit = "Screen", parent = f })
		screen.Transparency = 0.15

		-- Ekran çerçevesi
		build({ name = "ScreenFrame", size = Vector3.new(5.8, 3.6, 0.5),
			cf = base * CFrame.new(0, 5, -0.7) * CFrame.Angles(math.rad(-28), 0, 0),
			color = HULL_DARK, material = Enum.Material.Metal, parent = f })
	end

	-- Ön ve arka duvar diplerine, üs sütunlarının arasına
	local inset = 7
	for i = 1, COLUMNS do
		local x = (i - 1) * PLOT_SPACING
		console(x, centerZ - halfD + inset, 0)
		console(x, centerZ + halfD - inset, 180)
	end
	-- Yan duvarlara
	for r = 0, ROWS - 1 do
		local z = r * ROW_SPACING
		console(centerX - halfW + inset, z, 90)
		console(centerX + halfW - inset, z, -90)
	end
end

-- ─── 8. Üs işaretleri ───────────────────────────────────────────────────────
-- Her üssün girişine kat numarası: oyuncu kendi üssünü uzaktan bulabilsin.

do
	local f = group("BayMarkers")

	for index = 1, PLOT_COUNT do
		local o = plotOrigin(index)
		local row = math.floor((index - 1) / COLUMNS)
		-- Üsler koridora bakıyor; işaret de koridor tarafında dursun
		local side = if row % 2 == 0 then 1 else -1
		local z = o.Z + side * (halfZ + 14)   -- kapi esigi 30.4'te bitiyor, ped onu asmali

		-- İsimlere numara: istemci tarafı bunları üs sahibine göre
		-- renklendiriyor, hangisinin hangi üs olduğunu bilmesi gerek.
		--[[
			Boyalı ped. Eskiden yarı saydam neon bir levhaydı ve plakaların
			içinde kaldığı için kamera açısına göre görünüp kayboluyordu.
			Artık güvertenin üstünde duran mat bir boya + çerçeve; hem stabil
			hem de Skeld'in zemin işaretlerine benziyor.
		]]
		build({ name = "BayPad" .. index, size = Vector3.new(14, 0.14, 7),
			cf = at(o.X, DECK_TOP + 0.12, z), color = DECK_ALT:Lerp(NEON_MID, 0.35),
			material = Enum.Material.SmoothPlastic, parent = f })
		for _, s in { -1, 1 } do
			build({ name = "BayPadEdge", size = Vector3.new(14.8, 0.16, 0.6),
				cf = at(o.X, DECK_TOP + 0.13, z + s * 3.7), color = HAZARD,
				material = Enum.Material.SmoothPlastic, parent = f })
		end

		local post = build({ name = "BayPost" .. index, size = Vector3.new(1, 1, 1),
			cf = at(o.X, 6, z), color = HULL,
			material = Enum.Material.Metal, transparency = 1, parent = f })

		--[[
			Boyut stud cinsinden ve mesafeyle ölçekleniyor. 11x4 uzaktan
			okunaklıydı ama yaklaşınca ekranın yarısını kaplıyordu. 6x2
			uzakta da seçiliyor, yanına gelince de önü kapatmıyor.
		]]
		local gui = Instance.new("BillboardGui")
		gui.Name = "BayLabel"
		gui.Size = UDim2.fromScale(6, 2)
		gui.AlwaysOnTop = false
		gui.MaxDistance = 260
		gui.Parent = post

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = NEON
		label.TextStrokeTransparency = 0.25
		label.Text = string.format("BAY %02d", index)
		label.Parent = gui
	end
end

-- ─── 9. Hareketli detaylar (geometri) ───────────────────────────────────────
-- Dönen radar ve yanıp sönen uyarı lambaları. Animasyonu istemci tarafındaki
-- DecorFX modülü yapıyor; burada sadece parçalar kuruluyor ve etiketleniyor.

do
	local f = group("Animated")

	-- Radar: köşede direk + tabak
	local rx = centerX - halfW + 16
	local rz = centerZ - halfD + 16

	build({ name = "RadarMast", size = Vector3.new(2, 16, 2),
		cf = at(rx, WALL_H + 8, rz), color = TRIM,
		material = Enum.Material.Metal, parent = f })

	local dish = build({ name = "RadarDish", size = Vector3.new(11, 1, 6),
		cf = at(rx, WALL_H + 16.5, rz), color = HULL,
		material = Enum.Material.Metal, parent = f })
	dish:SetAttribute("SpinSpeed", 22)   -- derece/saniye

	build({ name = "RadarPin", size = Vector3.new(0.6, 2.4, 0.6),
		cf = at(rx, WALL_H + 17.7, rz), color = NEON_WARM,
		emit = "Indicator", parent = f })

	-- Uyarı lambaları: çeperin dört köşesinde
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local lamp = build({
				name = "WarnLight",
				size = Vector3.new(2.2, 2.2, 2.2),
				cf = at(centerX + sx * (halfW - 3), WALL_H + 2.5, centerZ + sz * (halfD - 3)),
				color = HAZARD, emit = "Fixture",
				shape = Enum.PartType.Ball, parent = f,
			})
			lamp:SetAttribute("PulsePeriod", 1.6)
			glow(lamp, HAZARD, 22, 1.6)
		end
	end
end

-- ─── 10. Boru hatları ───────────────────────────────────────────────────────
-- Çeper duvarların dibinde dolaşan borular. Düz duvar yerine "işleyen bir
-- tesis" hissi veriyor; aralıklı kelepçeler ölçek algısını güçlendiriyor.

do
	local f = group("Pipes")
	local Y = 6.5
	local R = 1.1

	local function run(axis: string, fixed: number, from: number, to: number, inset: number)
		local length = to - from
		local mid = (from + to) / 2

		for lane, dy in { 0, 3.2 } do
			local y = Y + dy
			local size = if axis == "x"
				then Vector3.new(length, R * 2, R * 2)
				else Vector3.new(R * 2, R * 2, length)
			local cf = if axis == "x" then at(mid, y, fixed + inset) else at(fixed + inset, y, mid)

			build({ name = "Pipe", size = size, cf = cf,
				color = if lane == 1 then TRIM else HULL,
				material = Enum.Material.Metal, parent = f })

			-- Kelepçeler
			local steps = math.max(2, math.floor(length / 22))
			for s = 0, steps do
				local along = from + length * (s / steps)
				local csize = if axis == "x"
					then Vector3.new(1, R * 2.7, R * 2.7)
					else Vector3.new(R * 2.7, R * 2.7, 1)
				local ccf = if axis == "x" then at(along, y, fixed + inset) else at(fixed + inset, y, along)
				build({ name = "PipeCollar", size = csize, cf = ccf,
					color = TRIM, material = Enum.Material.Metal, parent = f })
			end
		end
	end

	local x0, x1 = centerX - halfW, centerX + halfW
	local z0, z1 = centerZ - halfD, centerZ + halfD

	run("x", z0, x0 + 6, x1 - 6, 3.2)

	--[[
		Arka duvardaki hat kapı boşluğunu ATLIYOR.

		Eskiden tek parça olarak bütün genişlik boyunca uzanıyordu; iki boru
		(alt ve üst hat) tam lobiye açılan kapının önünden geçiyordu.
		Koridordan bakınca yolun ortasında havada duran iki uzun çubuk
		görünüyordu — geçişi engellemiyordu ama görüntüyü bozuyordu.
	]]
	local gateHalf = LOBBY_GATE_WIDTH / 2 + 4
	run("x", z1, x0 + 6, centerX - gateHalf, -3.2)
	run("x", z1, centerX + gateHalf, x1 - 6, -3.2)

	run("z", x0, z0 + 6, z1 - 6, 3.2)
	run("z", x1, z0 + 6, z1 - 6, -3.2)
end

-- ─── 11. Üs kapı eşikleri ───────────────────────────────────────────────────
-- Koridordan üsse geçerken "içeri girdim" hissi. Kapı yok, sadece çerçeve:
-- geçiş engellenmemeli.

do
	local f = group("Doorways")
	local H = 12
	local W = 16
	local T = 1.4

	for index = 1, PLOT_COUNT do
		local o = plotOrigin(index)
		local row = math.floor((index - 1) / COLUMNS)
		--[[
			Üs koridora bakıyor; eşik de o tarafta.

			Mesafe altlıktan hesaplanıyor, üs zemininden değil. Altlık
			üsten 3 stud daha taşıyor (PLOT_SIZE.Z + 6) ve eşik halfZ + 2'de
			duruyordu: söveler altlığın içine 2.4 stud gömülüyor, kapı
			blokların içinden çıkıyormuş gibi görünüyordu.

			Artık altlığın dış kenarına dayanıyor, içine girmiyor.
		]]
		local side = if row % 2 == 0 then 1 else -1
		local plinthHalf = halfZ + 3
		local z = o.Z + side * (plinthHalf + T)

		for _, sx in { -1, 1 } do
			build({ name = "DoorJamb", size = Vector3.new(T, H, T * 2),
				cf = at(o.X + sx * (W / 2), H / 2, z),
				color = HULL, material = Enum.Material.Metal, parent = f })
		end

		build({ name = "DoorLintel", size = Vector3.new(W + T, T * 1.6, T * 2),
			cf = at(o.X, H, z), color = TRIM,
			material = Enum.Material.Metal, parent = f })

		-- İsimde numara: istemci bunu üs sahibinin rengine boyuyor
		build({ name = "DoorGlow" .. index, size = Vector3.new(W - 1, 0.3, 0.4),
			cf = at(o.X, H - 1.2, z), color = NEON_MID,
			emit = "Paint", parent = f })
	end
end

-- ─── 12. Pencere dışında süzülen nesneler ───────────────────────────────────
-- Uzay hareketsiz olunca ölü görünüyor. Dışarıda yavaşça geçen birkaç nesne
-- pencerelere bakma sebebi veriyor. Hareketi DecorFX yapıyor.

do
	local f = group("Drifters")

	--[[
		Her süzülen nesne bir Model: parçaları tek tek taşımak yerine
		DecorFX modeli bir bütün olarak kaydırıyor, parçalar birbirinden
		ayrılmıyor.
	]]
	local function drifter(x: number, y: number, z: number, scale: number, speed: number)
		local model = Instance.new("Model")
		model.Name = "Drifter"
		model.Parent = f

		local body = build({
			name = "Body",
			size = Vector3.new(9 * scale, 3 * scale, 5 * scale),
			cf = at(x, y, z),
			color = HULL,
			material = Enum.Material.Metal,
			parent = model,
		})
		model.PrimaryPart = body

		build({ name = "Fin", size = Vector3.new(3 * scale, 0.6 * scale, 8 * scale),
			cf = at(x, y, z), color = TRIM, material = Enum.Material.Metal, parent = model })

		local lamp = build({ name = "Lamp", size = Vector3.new(1.2 * scale, 1.2 * scale, 1.2 * scale),
			cf = at(x - 4.5 * scale, y, z), color = NEON_WARM,
			emit = "Indicator", shape = Enum.PartType.Ball, parent = model })

		model:SetAttribute("DriftSpeed", speed)
		model:SetAttribute("DriftRange", halfW * 2 + 260)
	end

	--[[
		Yükseklikler pencere açıklığının içinde kalmalı (y 9..29). İlk denemede
		biri y=40'taydı ve içeriden hiç görünmüyordu. Mesafe de önemli: çok
		uzaktakiler siyah fonda kayboluyor, bu yüzden çepere yakın tutuluyorlar.
	]]
	local near = halfD + 34
	local far = halfD + 62

	drifter(centerX - halfW - 90,  15, centerZ - near, 1.6, 8)
	drifter(centerX - halfW - 230, 24, centerZ - far,  2.6, 5)
	drifter(centerX - halfW - 40,  20, centerZ + near, 1.3, 12)
	drifter(centerX - halfW - 300, 13, centerZ + far,  2.2, 6.5)
	drifter(centerX - halfW - 160, 26, centerZ + near + 26, 1.8, 9.5)
end

-- ─── 12b. Koridor dolgusu, bölge kimliği ve yön işaretleri ─────────────────
--[[
	Üç sorunu birden çözüyor:

	1. Koridorlar bomboştu. Üsler arasındaki geniş boşluklarda göz tutunacak
	   bir şey bulamıyordu; harita büyük ama ıssız hissettiriyordu.

	2. İki sıra birbirinin aynıydı. Hangi tarafta olduğunu anlamak için
	   tabelaları okumak gerekiyordu. Artık üst sıra soğuk (camgöbeği), alt
	   sıra sıcak (kehribar) kimlikte — bir bakışta yerini biliyorsun.

	3. Lobinin nerede olduğu belli değildi. Zeminde ok işaretleri kapıya
	   götürüyor.
]]

do
	local f = group("Corridors")

	--[[ Kablo demeti: koridor boyunca uzanan, aralıklı kelepçeli hat. ]]
	local function cableRun(x: number, z: number, length: number, along: string, tone: Color3)
		local size = if along == "z"
			then Vector3.new(1.1, 1.1, length)
			else Vector3.new(length, 1.1, 1.1)

		build({ name = "Cable", size = size, cf = at(x, 0.9, z),
			color = HULL_DARK, material = Enum.Material.Metal, parent = f })
		build({
			name = "CableGlow",
			size = if along == "z" then Vector3.new(0.3, 0.3, length - 4) else Vector3.new(length - 4, 0.3, 0.3),
			cf = at(x, 1.5, z), color = tone, emit = "Paint", parent = f,
		})

		local steps = math.max(2, math.floor(length / 20))
		for i = 0, steps do
			local t = i / steps
			local cx = if along == "x" then x - length / 2 + length * t else x
			local cz = if along == "z" then z - length / 2 + length * t else z
			build({ name = "CableClamp", size = Vector3.new(1.8, 1.8, 1.8),
				cf = at(cx, 0.9, cz), color = TRIM,
				material = Enum.Material.Metal, parent = f })
		end
	end

	--[[ Sandık istifi: koddan basit kutu yığını. Koridorun boşluğunu
	     kırıyor ve ölçek hissi veriyor. ]]
	--[[
		Sandık istifi.

		Önceki hâlde her sandığın ölçüsü rastgele (3–4.6) ama yüksekliği
		sabit 3.2 artıyordu; üstelik her biri x/z'de ±1.5 rastgele
		kaydırılıyordu. Sonuç: kutular ne üst üste oturuyordu ne de yan
		yana — havada duran, birbirine girmiş bloklar ("kutu gibi durmuyor,
		tam oturmamışlar"). Bandı da sabit yükseklikteydi, kutunun
		kenarıyla hizalanmıyordu.

		Şimdi istif gerçekten istif: her kat bir öncekinin TAM ÜSTÜNE
		oturuyor (yükseklik kutunun kendi boyundan geliyor), yukarı
		çıktıkça kutular küçülüyor ve her katın kayması bir öncekinin
		kenarını aşmayacak kadar. Dönüş serbest, çünkü kare bir kutu
		döndüğünde de aynı yerde duruyor.
	]]
	local function crates(x: number, z: number, tone: Color3, seed: number)
		local rng = Random.new(seed)
		local count = 2 + rng:NextInteger(0, 1)
		local y = 0
		local width = 4.4

		for i = 1, count do
			local h = 3.2 - (i - 1) * 0.4
			-- Kayma, alttaki kutunun içinde kalacak kadar
			local slip = if i == 1 then 0 else (width * 0.18)
			local cx = x + rng:NextNumber(-slip, slip)
			local cz = z + rng:NextNumber(-slip, slip)
			-- Dönüş BİR KEZ hesaplanıyor: kutu ve bandı aynı açıda olmalı,
			-- ayrı ayrı çekilirse bant kutunun köşesinden taşıyor
			local yaw = rng:NextNumber(0, math.pi / 2)

			build({
				name = "Crate",
				size = Vector3.new(width, h, width),
				cf = CFrame.new(cx, y + h / 2, cz) * CFrame.Angles(0, yaw, 0),
				color = if i % 2 == 0 then HULL else STEEL_DARK,
				material = Enum.Material.Metal,
				collide = true,
				parent = f,
			})
			build({
				name = "CrateBand",
				size = Vector3.new(width + 0.16, 0.4, width + 0.16),
				cf = CFrame.new(cx, y + h * 0.62, cz) * CFrame.Angles(0, yaw, 0),
				color = tone,
				emit = "Paint",
				parent = f,
			})

			y += h
			width -= 0.5
		end
	end

	for r = 0, ROWS - 1 do
		local z = r * ROW_SPACING
		local tone = zoneColor(r)

		-- Sıranın iki yanında kablo hattı
		for _, side in { -1, 1 } do
			cableRun(centerX, z + side * (halfZ + 12), halfW * 2 - 30, "x", tone)
		end

		-- Üsler arası boşluklarda sandık istifi
		for c = 1, COLUMNS - 1 do
			local gx = (c - 0.5) * PLOT_SPACING
			crates(gx, z - halfZ - 5, tone, c * 97 + r * 13)
			crates(gx, z + halfZ + 5, tone, c * 131 + r * 29)
		end

		-- Sıra kimliği: koridor girişine renkli bant
		build({ name = "ZoneBar", size = Vector3.new(halfW * 2 - 40, 0.16, 1.6),
			cf = at(centerX, DECK_TOP + 0.13, z - halfZ - 14), color = tone,
			emit = "Paint", parent = f })
		build({ name = "ZoneBar", size = Vector3.new(halfW * 2 - 40, 0.16, 1.6),
			cf = at(centerX, DECK_TOP + 0.13, z + halfZ + 14), color = tone,
			emit = "Paint", parent = f })
	end

	--[[
		Lobiye yön okları. Zemine gömülü, kapıya doğru sıralı. Ok yerine
		"V" şekli: iki eğik çubuk, yönü açıkça gösteriyor ve tek parçadan
		daha canlı duruyor.
	]]
	local gateZ = centerZ + halfD
	for i = 1, 6 do
		local az = centerZ + (i - 3.5) * 26
		if az >= gateZ - 10 then
			continue
		end
		for _, s in { -1, 1 } do
			build({
				name = "WayArrow",
				size = Vector3.new(0.7, 0.14, 5),
				cf = CFrame.new(centerX, DECK_TOP + 0.18, az)
					* CFrame.Angles(0, math.rad(s * 34), 0)
					* CFrame.new(s * 1.6, 0, 0),
				color = NEON,
				emit = "Paint",
				transparency = 0.25,
				parent = f,
			})
		end
	end
end

-- ─── 13. Lobi ───────────────────────────────────────────────────────────────
--[[
	Üslerin önünde ayrı bir platform. Oyun alanından ayrı olması bilinçli:
	çalma koşuşturmasıyla sıralama okumak, çark çevirmek gibi sakin işler
	birbirine karışmasın. Köprüyle bağlı, kapıdan geçilip gidiliyor.

	İçinde: ışınlanma kürsüsü (arayüz buradan açılıyor), sıralama panoları,
	çark. Çarkın ödül vermesi sunucu işi; burada sadece geometrisi var.
]]

local lobbyZ = centerZ + halfD + LOBBY_BRIDGE + LOBBY_D / 2

do
	local f = group("Lobby")
	local halfLW, halfLD = LOBBY_W / 2, LOBBY_D / 2

	--[[
		── KÖPRÜ ──────────────────────────────────────────────────────────
		Önceki hâli 1 stud kalınlığında bir levha ve iki yanında 4 stud
		korkuluktu. Roblox karakteri yaklaşık 7 stud zıplıyor; yani
		korkuluğun üstünden atlanıp boşluğa düşülebiliyordu.

		Artık kapalı bir geçiş tüpü: iki yanda belden yukarı camlı duvar,
		üstte kaburgalı tavan, altta destek ayakları. Hem düşmek imkânsız
		hem de "istasyondan lobiye geçiyorum" hissi kuruluyor — daha önce
		sadece havada bir tahta vardı.
	]]
	local bridgeZ = centerZ + halfD + LOBBY_BRIDGE / 2
	local bridgeLen = LOBBY_BRIDGE + 2

	--[[
		Ölçüler büyütüldü: geçit 28 studdu ve iki yanda 1.2'lik duvarlarla
		birlikte 25 studluk bir koridor kalıyordu; tavan da 11'deydi. İçeride
		yürürken tünel gibi dar hissettiriyordu. Şimdi 36 geniş, 14 yüksek.

		Kaburgalar duvar üstünden tavana kadar TEK parça; önceki hâlde
		kaburga tavanda, ayağı aşağıda ayrı duruyordu ve aralarında görünür
		bir boşluk kalıyordu ("eklediğin şeyler temas etmiyor").
	]]
	--[[
		YÜKSEKLİK. Köprü 14 studdu; istasyon duvarı 52, lobi duvarı 46. İki
		yüksek salonu birbirine bağlayan tünel onların üçte biriydi ve
		kapıdan çıkınca tavan çöküyormuş gibi oluyordu.

		26 ikisinin ortası: hâlâ bir geçit, salon değil — ama iki uçtaki
		kapı boşluklarıyla aynı ölçek ailesinde.
	]]
	local WALL_LOW = 6         -- dolu alt duvar
	local WALL_TOP = 26        -- tavan yüksekliği

	build({ name = "Bridge", size = Vector3.new(LOBBY_GATE_WIDTH, 1, bridgeLen),
		cf = at(centerX, -0.5, bridgeZ),
		color = HULL_DARK, material = Enum.Material.Metal, collide = true, parent = f })
	build({ name = "BridgeUnder", size = Vector3.new(LOBBY_GATE_WIDTH - 4, 2.4, bridgeLen - 6),
		cf = at(centerX, -2.2, bridgeZ),
		color = HULL, material = Enum.Material.Metal, parent = f })

	--[[
		Köprünün iki ucundaki geçiş çerçevesi.

		Köprünün kesiti 36 geniş ve 14 yüksek; istasyonun ve lobinin gövde
		açıklıkları başka ölçüde. Zeminler bir stud bindiriyor, yani
		düşülmüyor — ama YUKARIDA, köprü tavanı ile gövde arasında açık bir
		bant kalıyordu ve içerisi boşluğa bakıyordu.

		Çerçeve o bandı kapatıyor: iki yanda sövme, üstte lento. Aynı zamanda
		"burada bir geçiş var" diyen mimari bir işaret — köprü artık havada
		başlayıp bitmiyor, bir kapıdan giriyor.
	]]
	local COLLAR_T = 2.5
	local collarW = LOBBY_GATE_WIDTH + COLLAR_T * 2

	for _, endZ in { bridgeZ - bridgeLen / 2, bridgeZ + bridgeLen / 2 } do
		-- Üst lento: tavandan gövdenin üstüne kadar
		build({ name = "BridgeCollarTop", size = Vector3.new(collarW, COLLAR_T + 3, COLLAR_T),
			cf = at(centerX, WALL_TOP + (COLLAR_T + 3) / 2 - 1, endZ),
			color = HULL, material = Enum.Material.Metal, collide = true, parent = f })

		for _, s2 in { -1, 1 } do
			-- Yan sövmeler: zeminden tavana
			build({ name = "BridgeCollarSide",
				size = Vector3.new(COLLAR_T, WALL_TOP + 2, COLLAR_T),
				cf = at(centerX + s2 * (LOBBY_GATE_WIDTH + COLLAR_T) / 2, (WALL_TOP + 2) / 2 - 1, endZ),
				color = HULL, material = Enum.Material.Metal, collide = true, parent = f })
		end

		-- Çerçeveyi okutan neon hat
		build({ name = "BridgeCollarGlow", size = Vector3.new(collarW - 1, 0.4, 0.5),
			cf = at(centerX, WALL_TOP - 0.6, endZ),
			color = NEON_MID, emit = "Paint", parent = f })
	end

	for _, s in { -1, 1 } do
		local wx = centerX + s * LOBBY_GATE_WIDTH / 2

		-- Dolu alt duvar: düşmeyi fiziksel olarak imkânsız kılan kısım
		build({ name = "BridgeWall", size = Vector3.new(1.2, WALL_LOW, bridgeLen),
			cf = at(wx, WALL_LOW / 2, bridgeZ),
			color = HULL, material = Enum.Material.Metal, collide = true, parent = f })
		build({ name = "BridgeRail", size = Vector3.new(1.8, 0.6, bridgeLen),
			cf = at(wx, WALL_LOW + 0.3, bridgeZ),
			color = TRIM, material = Enum.Material.Metal, collide = true, parent = f })

		-- Üst kısım cam: dışarısı görünsün ama geçilmesin.
		-- Duvarın üstünden tavanın altına kadar, arada boşluk yok.
		build({ name = "BridgeGlass", size = Vector3.new(0.5, WALL_TOP - WALL_LOW - 0.7, bridgeLen),
			cf = at(wx, (WALL_LOW + WALL_TOP - 0.7) / 2, bridgeZ),
			color = GLASS, material = Enum.Material.Glass, collide = true,
			transparency = 0.9, parent = f })

		-- Zeminde yön şeridi
		build({ name = "BridgeStripe", size = Vector3.new(0.7, 0.14, bridgeLen - 4),
			cf = at(centerX + s * (LOBBY_GATE_WIDTH / 2 - 4), 0.08, bridgeZ),
			color = HAZARD, emit = "Paint", parent = f })

		--[[
			GÖRÜNMEZ EMNİYET DUVARI.

			Cam 14'e kadar çıkıyor ama Roblox karakteri ~7 stud zıplıyor ve
			eğimli bir yüzeyden sekerek daha yükseğe çıkabiliyor. Köprünün
			iki yanına, camın da üstüne uzanan görünmez bir duvar konuyor:
			artık hiçbir açıdan dışarı çıkılamıyor.
		]]
		build({ name = "BridgeSafety", size = Vector3.new(1, 40, bridgeLen),
			cf = at(wx, 20, bridgeZ), color = GLASS,
			material = Enum.Material.SmoothPlastic, collide = true,
			transparency = 1, parent = f })
	end

	--[[ Tavan çerçeveleri. Duvar üstünden tavana kadar TEK parça ayak +
	     üstte kiriş: tünelin uzunluğu bunlarla okunuyor. ]]
	local RIBS = 7
	for i = 0, RIBS do
		local rz = bridgeZ - bridgeLen / 2 + (bridgeLen / RIBS) * i

		build({ name = "BridgeRib", size = Vector3.new(LOBBY_GATE_WIDTH + 2.4, 1.4, 1.8),
			cf = at(centerX, WALL_TOP, rz), color = TRIM,
			material = Enum.Material.Metal, parent = f })

		for _, s in { -1, 1 } do
			build({ name = "BridgeRibLeg", size = Vector3.new(1.6, WALL_TOP - WALL_LOW, 1.8),
				cf = at(centerX + s * (LOBBY_GATE_WIDTH / 2 + 1.4), (WALL_LOW + WALL_TOP) / 2, rz),
				color = TRIM, material = Enum.Material.Metal, parent = f })
		end

		-- Çerçevelerin arasına gömme lamba
		if i < RIBS then
			local lamp = build({ name = "BridgeLamp", size = Vector3.new(5, 0.3, 3.4),
				cf = at(centerX, WALL_TOP - 1, rz + bridgeLen / RIBS / 2),
				color = LAMP, emit = "Fixture", parent = f })
			glow(lamp, LAMP, 22, 0.7)
		end
	end

	-- Tavan levhası: kaburgaların arasını kapatıyor
	build({ name = "BridgeCeil", size = Vector3.new(LOBBY_GATE_WIDTH, 0.8, bridgeLen),
		cf = at(centerX, WALL_TOP + 1.1, bridgeZ), color = HULL_DARK,
		material = Enum.Material.Metal, parent = f })

	-- Köprüyü taşıyan ayaklar
	for _, t in { 0.3, 0.7 } do
		local pz = centerZ + halfD + LOBBY_BRIDGE * t
		for _, s in { -1, 1 } do
			build({ name = "BridgePylon", size = Vector3.new(2.2, 16, 2.2),
				cf = at(centerX + s * (LOBBY_GATE_WIDTH / 2 - 2), -11, pz),
				color = HULL_DARK, material = Enum.Material.Metal, parent = f })
		end
	end

	-- Güverte ve gövde
	build({ name = "LobbyDeck", size = Vector3.new(LOBBY_W, 1, LOBBY_D),
		cf = at(centerX, -0.5, lobbyZ), color = HULL_DARK,
		material = Enum.Material.Metal, collide = true, parent = f })
	build({ name = "LobbyHull", size = Vector3.new(LOBBY_W - 8, 14, LOBBY_D - 8),
		cf = at(centerX, -8, lobbyZ), color = HULL,
		material = Enum.Material.Metal, parent = f })
	build({ name = "LobbyKeel", size = Vector3.new(LOBBY_W - 50, 6, LOBBY_D - 50),
		cf = at(centerX, -17, lobbyZ), color = TRIM,
		material = Enum.Material.Metal, parent = f })

	-- Çeper duvarlar: köprünün geldiği kenar açık
	local edges = {
		{ x = centerX, z = lobbyZ + halfLD, sx = LOBBY_W, sz = 2 },          -- arka
		{ x = centerX - halfLW, z = lobbyZ, sx = 2, sz = LOBBY_D },          -- sol
		{ x = centerX + halfLW, z = lobbyZ, sx = 2, sz = LOBBY_D },          -- sağ
	}
	for _, e in edges do
		build({ name = "LobbyWall", size = Vector3.new(e.sx, LOBBY_WALL_H, e.sz),
			cf = at(e.x, LOBBY_WALL_H / 2, e.z), color = HULL,
			material = Enum.Material.Metal, collide = true, parent = f })
		build({ name = "LobbyCornice", size = Vector3.new(e.sx + 3, 1.4, e.sz + 3),
			cf = at(e.x, LOBBY_WALL_H + 0.7, e.z), color = TRIM,
			material = Enum.Material.Metal, parent = f })
	end

	-- Ön kenarın köprü dışında kalan kısımları
	local sideW = (LOBBY_W - LOBBY_GATE_WIDTH) / 2
	for _, s in { -1, 1 } do
		build({ name = "LobbyWall", size = Vector3.new(sideW, LOBBY_WALL_H, 2),
			cf = at(centerX + s * (LOBBY_GATE_WIDTH / 2 + sideW / 2), LOBBY_WALL_H / 2, lobbyZ - halfLD),
			color = HULL, material = Enum.Material.Metal, collide = true, parent = f })
	end

	-- Zemin deseni: merkeze doğru halkalar, göz ortadaki kürsüye gider
	for i = 1, 3 do
		local r = 22 + i * 16
		build({ name = "LobbyRing", size = Vector3.new(r * 2, 0.12, 0.7),
			cf = at(centerX, 0.06 + LIFT, lobbyZ - r), color = NEON_DIM,
			emit = "Paint", parent = f })
		build({ name = "LobbyRing", size = Vector3.new(r * 2, 0.12, 0.7),
			cf = at(centerX, 0.06 + LIFT, lobbyZ + r), color = NEON_DIM,
			emit = "Paint", parent = f })
	end

	-- Tavan kirişleri
	for i = -2, 2 do
		build({ name = "LobbyTruss", size = Vector3.new(1.4, 1.4, LOBBY_D),
			cf = at(centerX + i * 34, LOBBY_WALL_H + 1, lobbyZ),
			color = TRIM, material = Enum.Material.Metal, parent = f })
	end

	--[[
		TAVAN. Lobinin üstü açıktı: duvarlar bitiyor, üstünde hiçbir şey yok,
		ama içeride tavan lambaları asılı duruyordu. İstasyondaki tavanla aynı
		mantık — panel panel döşeme, aralarında çizgi, lambalar panellerin
		arasına gömülü.
	]]
	local ceil = group("LobbyCeiling", f)
	local panelW, panelD = 30, 24
	local nx = math.ceil(LOBBY_W / panelW)
	local nz = math.ceil(LOBBY_D / panelD)

	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local pw = math.min(panelW, LOBBY_W - i * panelW)
			local pd = math.min(panelD, LOBBY_D - j * panelD)
			if pw < 2 or pd < 2 then
				continue
			end
			build({
				name = "LobbyCeilPanel",
				size = Vector3.new(pw - 0.5, 1, pd - 0.5),
				cf = at(
					centerX - halfLW + i * panelW + pw / 2,
					LOBBY_CEIL_Y,
					lobbyZ - halfLD + j * panelD + pd / 2
				),
				color = if (i + j) % 2 == 0 then HULL else HULL_DARK,
				material = Enum.Material.Metal,
				parent = ceil,
			})
		end
	end

	-- Duvar üstü ile tavan arasındaki boşluğu kapatan bant
	local band = LOBBY_CEIL_Y - LOBBY_WALL_H + 1
	local rim = {
		{ centerX, lobbyZ + halfLD, LOBBY_W + 3, 2.6 },
		{ centerX, lobbyZ - halfLD, LOBBY_W + 3, 2.6 },
		{ centerX - halfLW, lobbyZ, 2.6, LOBBY_D + 3 },
		{ centerX + halfLW, lobbyZ, 2.6, LOBBY_D + 3 },
	}
	for _, r in rim do
		build({ name = "LobbyFascia", size = Vector3.new(r[3], band, r[4]),
			cf = at(r[1], (LOBBY_WALL_H + LOBBY_CEIL_Y) / 2, r[2]), color = HULL_DARK,
			material = Enum.Material.Metal, parent = ceil })
	end

	--[[
		Gömülü armatürler. Beş uzun şerit yerine ızgara hâlinde panel lambalar:
		gölge daha eşit dağılıyor ve tavan yüksekliği arttığı için tek tip uzun
		şerit zemine yetmiyordu.
	]]
	for i = -2, 2 do
		for _, dz in { -30, 0, 30 } do
			local lx = centerX + i * 34
			local lz = lobbyZ + dz

			build({ name = "LobbyLampHousing", size = Vector3.new(6, 1.1, 10),
				cf = at(lx, LOBBY_CEIL_Y - 0.9, lz), color = HULL_DARK,
				material = Enum.Material.Metal, parent = ceil })

			local lamp = build({ name = "LobbyLamp", size = Vector3.new(4.6, 0.35, 8.6),
				cf = at(lx, LOBBY_CEIL_Y - 1.5, lz),
				color = LAMP, emit = "Fixture", parent = ceil })
			glow(lamp, LAMP, 40, 0.9)
		end
	end
end

-- ─── 13b. Mürettebat heykelleri ─────────────────────────────────────────────
--[[
	Haritanın teması "Among Us" ama içinde tek bir mürettebat figürü yoktu;
	kaidedeki karakterler dışında sahne herhangi bir uzay istasyonu olabilirdi.
	Heykeller bunu tek başına çözüyor — oyuncu kapıdan girer girmez ne
	oynadığını anlıyor.

	Üç yerde duruyorlar:
	  • Lobi kapısının iki yanında iki dev nöbetçi (ölçek 4)
	  • Lobinin arka duvarında renk galerisi (ölçek 2.4, 6 mürettebat rengi)
	  • İstasyonun dört köşesinde gözcüler (ölçek 3)

	Ayrıca havalandırmanın yanında devrilmiş bir figür var: oyunun kendi
	şakası, keşfedene küçük bir ödül.
]]

do
	local f = group("Statues")

	--[[ Heykel + kaide + üstten aydınlatma. Kaide olmadan figür zeminden
	     bitmiş gibi duruyor; kaide onu "sergilenen nesne" yapıyor. ]]
	local function pedestal(x: number, z: number, scale: number, color: Color3, yaw: number, label: string?)
		local h = 2.2 + scale * 0.4

		build({ name = "PedBase", size = Vector3.new(4.4 * scale, 1, 4.4 * scale),
			cf = at(x, 0.5, z), color = HULL_DARK,
			material = Enum.Material.Metal, collide = true, parent = f })
		build({ name = "PedShaft", size = Vector3.new(3.4 * scale, h, 3.4 * scale),
			cf = at(x, 1 + h / 2, z), color = HULL,
			material = Enum.Material.Metal, collide = true, parent = f })
		build({ name = "PedCap", size = Vector3.new(4 * scale, 0.5, 4 * scale),
			cf = at(x, 1 + h + 0.25, z), color = TRIM,
			material = Enum.Material.Metal, collide = true, parent = f })

		-- Kaidenin altında figür rengiyle bir bant: uzaktan hangi mürettebat
		-- olduğu okunuyor
		build({ name = "PedBand", size = Vector3.new(3.6 * scale, 0.35, 3.6 * scale),
			cf = at(x, 1.5, z), color = color,
			emit = "Paint", parent = f })

		crewStatue(f, x, z, 1 + h + 0.5, scale, color, yaw)

		-- Üstten spot: heykeli sahneden ayırıyor
		local spot = build({ name = "PedSpot", size = Vector3.new(1.2, 0.3, 1.2),
			cf = at(x, 1 + h + 5.2 * scale, z), color = LAMP,
			emit = "Fixture", parent = f })
		glow(spot, LAMP, 16 + scale * 4, 1.2)

		if label then
			local anchor = build({ name = "PedLabelAnchor", size = Vector3.new(1, 1, 1),
				cf = at(x, 1.1, z), color = HULL, transparency = 1, parent = f })

			local gui = Instance.new("BillboardGui")
			gui.Name = "Label"
			gui.Size = UDim2.fromScale(6, 1.4)
			gui.StudsOffsetWorldSpace = Vector3.new(0, 1.2, 0)
			gui.MaxDistance = 90
			gui.Parent = anchor

			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.Font = Enum.Font.GothamBold
			text.TextScaled = true
			text.TextColor3 = color
			text.TextStrokeTransparency = 0.3
			text.Text = label
			text.Parent = gui
		end
	end

	--[[
		Lobi kapısının iki yanında nöbetçiler. Köprüden çıkan oyuncu tam
		aralarından geçiyor; birbirlerine baktıkları için kapı bir "geçit"
		gibi okunuyor.

		yaw kuralı: figürün vizörü yerel -Z'ye bakar. yaw=90 → -X yönü,
		yaw=-90 → +X yönü.
	]]
	--[[
		Ölçek 4'ten 2.8'e indi. 4'te kaide 17.6 stud genişliğindeydi; iki
		tanesi girişin iki yanında birer DUVAR gibi duruyor ve kapıdan çıkan
		oyuncu dar bir yarıktan geçiyordu ("önünde engeller var"). 2.8'de
		kaide 12.3 stud, aradaki açıklık 40 stud — geçit değil meydan.
	]]
	local gateZ = lobbyZ - LOBBY_D / 2 + 18
	pedestal(centerX - LOBBY_GATE_WIDTH / 2 - 16, gateZ, 2.8, CREW[1], -90)
	pedestal(centerX + LOBBY_GATE_WIDTH / 2 + 16, gateZ, 2.8, CREW[2], 90)

	--[[
		Renk galerisi. Arka duvara koyamıyoruz — sıralama panoları orada ve
		heykeller ekranların önünü kapatırdı. Sağ duvar boyunca diziliyorlar,
		hepsi içeri bakıyor. Sol taraf çarkın alanı.
	]]
	--[[
		Galeri ARKA şeritte ve duvardan biraz içeride. Önceki yerleşimde
		dolapların (lobiZ+4) ve oturakların hemen yanındaydı; üçü aynı
		duvarda sıkışıyordu. Şimdi aralarında en az 20 stud var.
	]]
	for i = 1, 4 do
		pedestal(centerX + LOBBY_W / 2 - 20, lobbyZ + 28 + (i - 1) * 22, 2.4, crewColor(i * 3), 90)
	end

	--[[
		İstasyondaki gözcüler DUVAR DİPLERİNDE, köşelerde değil. Köşe denendi
		ama orası hem radar direğinin hem de ilk üssün altlığının alanı;
		heykel üssün içinde kalıyordu. Duvar dibinde üs ayak izinin dışında
		kalan şerit var (üsler x=-33..306 arası, gövde -64..340) ve orası
		zaten boştu.

		Koridorun kendisine hiçbir şey konmuyor: çalmanın bütün riski rakip
		üsse koşmakta, yolu daraltan dekor oyunu bozar.
	]]
	--[[
		yaw kuralı: vizör yerel -Z'ye bakar. yaw=0 → -Z, 180 → +Z,
		90 → -X, -90 → +X. Ön/arka duvardakiler ilk kurulumda ters yazılmıştı
		ve haritaya değil DUVARA bakıyorlardı; sırtı dönük heykel garip
		duruyordu. Hepsi içeri, sahanın ortasına bakıyor.
	]]
	local watchers = {
		{ centerX - halfW + 16, centerZ, -90 },              -- sol duvar → +X
		{ centerX + halfW - 16, centerZ, 90 },               -- sağ duvar → -X
		{ (COLUMNS >= 2 and 0.5 or 0) * PLOT_SPACING, centerZ - halfD + 16, 180 },   -- ön duvar → +Z
		{ (COLUMNS >= 2 and COLUMNS - 1.5 or 0) * PLOT_SPACING, centerZ + halfD - 16, 0 }, -- arka duvar → -Z
	}
	for i, w in watchers do
		pedestal(w[1], w[2], 3, crewColor(i * 3 + 1), w[3])
	end

	--[[
		Devrilmiş figür. Oyunun kendi şakası: havalandırmanın yanında yatıyor.
		Kaide yok, doğrudan zeminde ve yan yatmış — heykel değil "olay yeri"
		gibi duruyor. Koridoru kapatmasın diye duvar dibinde.
	]]
	do
		-- Üs ayak izinin dışında kalan duvar şeridinde. 30 denendi ama orası
		-- 5. üssün altlığına (x = -33) değiyordu.
		local bx = centerX - halfW + 14
		local bz = centerZ + halfD - 26
		local lying = group("FallenCrew", f)

		--[[
			Figürü dik kuruyoruz, sonra bütün parçaları TEK bir dönüşle
			yatırıyoruz. Her parçanın yatık konumunu ayrı ayrı hesaplamak
			yerine, her birinin tabana göre bağıl konumunu alıp aynı dönüşle
			yeniden yerleştiriyoruz — gövde, kafa, vizör, bacaklar arasındaki
			ilişki bozulmadan korunuyor.
		]]
		crewStatue(lying, bx, bz, 0, 2.2, CREW[5], 0)

		--[[
			Z ekseni etrafında yatırıyoruz, X etrafında değil. X denendi:
			figür sırtüstü kalıyor ve sırt çantası zeminin 2.6 stud altına
			gömülüyordu. Z ile yan yatıyor, bütün parçalar y=0 civarında
			kalıyor ve hiçbiri güvertenin altına düşmüyor.
		]]
		local ground = CFrame.new(bx, 0, bz)
		local tip = CFrame.new(bx, 3, bz)
			* CFrame.Angles(0, math.rad(-35), 0)
			* CFrame.Angles(0, 0, math.rad(90))
		for _, part in lying:GetDescendants() do
			if part:IsA("BasePart") then
				part.CFrame = tip * ground:ToObjectSpace(part.CFrame)
			end
		end

		--[[
			Sahneleme. Yerde yatan bir figür tek başına "hata" gibi okunuyordu:
			neden orada olduğu belli değildi, sanki heykel devrilmiş gibi.
			Etrafına bir OLAY YERİ kuruyoruz ve okuma tamamen değişiyor —
			kordon, yerde tebeşir hattı, yukarıdan tek spot ve yavaş yanıp
			sönen bir uyarı lambası. Hepsi oyunun kendi şakasını anlatıyor.

			Işık tek: üstten dar bir spot. Ortamı aydınlatmıyor, sadece figürü
			karanlıktan çekip alıyor. Sahnede parıltı dengesini bozmasın diye
			menzili küçük tutuldu.
		]]
		local scene = group("FallenScene", f)

		-- Yerde tebeşir hattı: figürün etrafını saran kesikli oval
		for i = 0, 15 do
			local a = i * (math.pi * 2 / 16)
			build({
				name = "ChalkMark",
				size = Vector3.new(1.8, 0.12, 0.5),
				cf = CFrame.new(bx, DECK_TOP + 0.06, bz)
					* CFrame.Angles(0, -a, 0)
					* CFrame.new(0, 0, 7.5)
					* CFrame.Angles(0, math.rad(90), 0),
				color = Color3.fromRGB(196, 200, 188),
				emit = "Paint",
				transparency = 0.25,
				parent = scene,
			})
		end

		-- Kordon: dört direk, aralarında sarı-siyah şerit
		local posts = {}
		for i = 0, 3 do
			local a = i * (math.pi / 2) + math.pi / 4
			local px = bx + math.cos(a) * 10
			local pz = bz + math.sin(a) * 10
			posts[i + 1] = Vector3.new(px, 0, pz)

			build({ name = "CordonPost", size = Vector3.new(0.6, 4, 0.6),
				cf = at(px, 2, pz), color = TRIM,
				material = Enum.Material.Metal, parent = scene })
			build({ name = "CordonCap", size = Vector3.new(1.1, 0.4, 1.1),
				cf = at(px, 4.1, pz), color = HAZARD,
				emit = "Indicator", parent = scene })
		end

		--[[ Şeritler direkleri birleştiriyor. İki nokta arasındaki uzunluk ve
		     yön CFrame.lookAt ile bulunuyor; elle açı hesaplamaya gerek yok. ]]
		for i = 1, 4 do
			local a = posts[i]
			local b = posts[i % 4 + 1]
			local mid = (a + b) / 2 + Vector3.new(0, 3.4, 0)
			local span = (b - a).Magnitude

			build({ name = "CordonTape", size = Vector3.new(0.12, 0.7, span),
				cf = CFrame.lookAt(mid, mid + (b - a).Unit),
				color = HAZARD, emit = "Paint", parent = scene })
		end

		-- Üstten tek spot
		local spot = build({ name = "SceneSpot", size = Vector3.new(2.4, 0.4, 2.4),
			cf = at(bx, 13, bz), color = LAMP, emit = "Fixture", parent = scene })
		glow(spot, LAMP, 20, 1.1)
		build({ name = "SceneSpotShroud", size = Vector3.new(3.2, 1.2, 3.2),
			cf = at(bx, 13.6, bz), color = HULL_DARK,
			material = Enum.Material.Metal, parent = scene })

		-- Yavaş yanıp sönen uyarı lambası: DecorFX fazı kendi veriyor
		local beacon = build({ name = "SceneBeacon", size = Vector3.new(1.4, 1.4, 1.4),
			cf = at(bx + 8, 5, bz - 8), color = RED,
			emit = "Fixture", shape = Enum.PartType.Ball, parent = scene })
		beacon:SetAttribute("PulsePeriod", 2.2)
		glow(beacon, RED, 14, 1.2)
	end
end

-- ─── 13c. Lobi mimarisi ─────────────────────────────────────────────────────
--[[
	Lobi "üstü kapalı boş bir platform"du. Kapıdan giriyordun, ortada bir
	kürsü, solda bir çark, arkada üç ekran vardı ama aralarındaki alan
	tamamen boştu — nereye gideceğini anlatan hiçbir şey yoktu ve çarkın
	oraya bir yol olduğu belli olmuyordu.

	Eksik olan şey dekor değil YÖNLENDİRMEydi. Gerçek bir terminalde yolu
	üç şey anlatır:

	  1. Zeminde boyalı güzergâh. Nereye basacağını gözün kendiliğinden
	     takip ediyor.
	  2. Üstte kapı/portal. Bir alandan diğerine geçtiğini beden hissediyor.
	  3. Kenarda oturma/dolap sırası. Boşluğu daraltıyor ve mekânı
	     "koridor" değil "oda" yapıyor.

	Üçü de burada. Çark artık kendi nişinde: portal altından giriliyor,
	sıra korkulukları var, üstünde tabelası var. Uzaktan bakınca "orada bir
	şey var" diyorsun — istenen buydu.
]]

do
	local f = group("Concourse")
	local halfLW, halfLD = LOBBY_W / 2, LOBBY_D / 2
	local gateFront = lobbyZ - halfLD
	local wheelX = centerX - LOBBY_W / 2 + 36
	local wheelZ = lobbyZ + 6

	local PAINT_Y = 0.32

	--[[ Boyalı güzergâh. `along` yönünde uzanan bant + kenarlarında kesikli
	     uyarı şeridi. İstasyondaki yürüme yolunun aynısı; iki alanın aynı
	     dilde konuşması bilinçli. ]]
	local function lane(cx: number, cz: number, length: number, width: number, along: string)
		local function box(l: number, w: number): Vector3
			return if along == "x" then Vector3.new(l, 0.1, w) else Vector3.new(w, 0.1, l)
		end

		build({ name = "LanePaint", size = box(length, width),
			cf = at(cx, PAINT_Y, cz),
			color = DECK_ALT:Lerp(Color3.fromRGB(150, 160, 180), 0.3),
			emit = "Paint", parent = f })

		local step = 6
		local count = math.floor(length / step)
		for _, side in { -1, 1 } do
			for i = 0, count - 1 do
				local off = -length / 2 + (i + 0.5) * step
				build({
					name = "LaneStripe",
					size = box(step * 0.55, 0.9),
					cf = at(
						if along == "x" then cx + off else cx + side * width / 2,
						PAINT_Y + 0.02,
						if along == "x" then cz + side * width / 2 else cz + off
					),
					color = if i % 2 == 0 then HAZARD else HAZARD_DARK,
					emit = "Paint", parent = f,
				})
			end
		end
	end

	--[[
		═══ GÜZERGÂH AĞI ═══════════════════════════════════════════════════

		Yollar artık BİRBİRİNE BAĞLI. Önceki hâlde arka tarafta havada
		duran 30 studluk bir parça vardı; nereden başlayıp nereye gittiği
		belli değildi ve ana aksa değmiyordu ("transitin arkasındaki yolun
		amacını anlamadım, birleşik değil").

		Ağın tamamı tek noktadan çıkıyor — ışınlanma kürsüsü:

		    kapı ──► kürsü ──► arka aks ──► panolar önü ──► her panoya kol
		               └──► çark kolu ──► portal

		Her kol bir öncekiyle üst üste binecek kadar uzun; yürürken boyanın
		kesildiği bir yer yok.
	]]
	local boardZ = lobbyZ + halfLD - 20      -- panoların önündeki enine aks

	-- Kapıdan ışınlanma kürsüsüne
	lane(centerX, (gateFront + lobbyZ) / 2, lobbyZ - gateFront + 4, 18, "z")

	-- Kürsüden panoların önüne: aradaki bütün mesafeyi kapatıyor
	lane(centerX, (lobbyZ + boardZ) / 2, boardZ - lobbyZ + 10, 16, "z")

	-- Panoların önünde enine aks
	lane(centerX, boardZ, LOBBY_W - 60, 14, "x")

	-- Her panoya ayrı kol. Panolar 52 stud arayla; enine akstan duvara
	-- doğru kısa birer bağlantı.
	for i = -1, 1 do
		lane(centerX + i * 52, boardZ + 9, 20, 10, "z")
	end

	-- Çark kolu: ana akstan sola, portalın önüne kadar
	lane((centerX + wheelX) / 2, lobbyZ - 22, centerX - wheelX + 12, 12, "x")
	lane(wheelX, lobbyZ - 15, 18, 12, "z")

	--[[
		Portal. Çark nişinin girişinde iki ayak + üstünde kiriş + tabela.
		Bir kapıdan geçiyor olmak, "burası ayrı bir yer" bilgisini tek
		başına veriyor; zemin boyası yönü, portal varışı anlatıyor.
	]]
	local PORTAL_W, PORTAL_H = 30, 22
	local portalZ = lobbyZ - 9

	for _, s in { -1, 1 } do
		build({ name = "PortalLeg", size = Vector3.new(3, PORTAL_H, 3),
			cf = at(wheelX + s * PORTAL_W / 2, PORTAL_H / 2, portalZ),
			color = HULL, material = Enum.Material.Metal, collide = true, parent = f })
		build({ name = "PortalFoot", size = Vector3.new(5, 1, 5),
			cf = at(wheelX + s * PORTAL_W / 2, 0.5, portalZ),
			color = TRIM, material = Enum.Material.Metal, collide = true, parent = f })
	end

	build({ name = "PortalBeam", size = Vector3.new(PORTAL_W + 5, 4, 3.4),
		cf = at(wheelX, PORTAL_H + 1, portalZ), color = HULL,
		material = Enum.Material.Metal, parent = f })

	--[[
		Portalın alınlığı YAZISIZ. Önce "PRIZE DECK" yazıyordu ama çarkın
		kendi tabelası zaten "LUCKY SPIN" diyor; üst üste iki başlık hem
		gereksiz hem de haritayı tabela tarlasına çeviriyordu. Yön bilgisini
		zemindeki boya ve portalın kendisi veriyor.

		Yazı yerine şerit: kapının bir geçit olduğunu anlatan yatay bant.
	]]
	build({ name = "PortalBand", size = Vector3.new(PORTAL_W - 2, 1.4, 0.5),
		cf = at(wheelX, PORTAL_H + 1.6, portalZ - 1.9), color = BRASS,
		emit = "Paint", parent = f })
	build({ name = "PortalBand", size = Vector3.new(PORTAL_W - 8, 0.8, 0.5),
		cf = at(wheelX, PORTAL_H - 0.2, portalZ - 1.9), color = BRASS,
		emit = "Paint", parent = f })

	-- Portalın altını yıkayan iki gömme lamba
	for _, s in { -1, 1 } do
		local wash = build({ name = "PortalWash", size = Vector3.new(4, 0.4, 1.6),
			cf = at(wheelX + s * 9, PORTAL_H - 1.6, portalZ - 1.2),
			color = LAMP, emit = "Fixture", parent = f })
		glow(wash, LAMP, 16, 0.8)
	end

	--[[
		Sıra korkulukları. Çarka giden son on studu daraltıyorlar; oyuncu
		"burada sıraya giriliyor" hissiyle yaklaşıyor. Direk + iki yatay
		çubuk; gerçek halat yerine çubuk çünkü halat eğrisi tek parçayla
		yapılamıyor ve sahte duruyor.
	]]
	for _, s in { -1, 1 } do
		local qx = wheelX + s * 9
		for i = 0, 3 do
			local qz = portalZ + 2 + i * 5
			build({ name = "QueuePost", size = Vector3.new(0.7, 4, 0.7),
				cf = at(qx, 2, qz), color = TRIM,
				material = Enum.Material.Metal, parent = f })
			build({ name = "QueueCap", size = Vector3.new(1.1, 0.5, 1.1),
				cf = at(qx, 4.2, qz), color = BRASS,
				emit = "Indicator", parent = f })

			if i < 3 then
				for _, h in { 2.2, 3.4 } do
					build({ name = "QueueRail", size = Vector3.new(0.35, 0.35, 5),
						cf = at(qx, h, qz + 2.5), color = BRASS,
						emit = "Paint", parent = f })
				end
			end
		end
	end

	--[[
		Nakliye gemisi oturakları. Among Us'ın lobi ekranındaki sıra sıra
		koltuklar: sırtlık duvarda, oturak önde, aralarında kolçak. Lobinin
		iki yan duvarına diziliyorlar — hem boşluğu dolduruyor hem de
		referansın en tanınır detayı.
	]]
	local function bench(bx: number, bz: number, facing: number)
		local base = CFrame.new(bx, 0, bz) * CFrame.Angles(0, math.rad(facing), 0)

		build({ name = "BenchBack", size = Vector3.new(14, 6, 1.2),
			cf = base * CFrame.new(0, 4.2, 1.4), color = TEAL,
			material = Enum.Material.SmoothPlastic, collide = true, parent = f })
		build({ name = "BenchSeat", size = Vector3.new(14, 1.2, 4.6),
			cf = base * CFrame.new(0, 2.6, -0.8), color = TEAL,
			material = Enum.Material.SmoothPlastic, collide = true, parent = f })
		build({ name = "BenchApron", size = Vector3.new(14, 2, 1),
			cf = base * CFrame.new(0, 1.2, -2.6), color = STEEL_DEEP,
			material = Enum.Material.Metal, parent = f })

		for _, s in { -1, 1 } do
			build({ name = "BenchArm", size = Vector3.new(0.8, 1.6, 5),
				cf = base * CFrame.new(s * 7, 3.9, -0.8), color = EDGE,
				material = Enum.Material.Metal, parent = f })
			build({ name = "BenchLeg", size = Vector3.new(1, 2, 1),
				cf = base * CFrame.new(s * 6, 1, -0.8), color = EDGE,
				material = Enum.Material.Metal, parent = f })
		end
	end

	--[[
		Oturaklar giriş bölgesinde, heykel galerisinden UZAKTA.

		İlk yerleşimde hem oturaklar hem dolaplar hem de galeri aynı duvar
		şeridini paylaşıyordu; heykeller dolapların dibinde, oturaklar
		heykellerin arkasında kalıyordu ("dekorasyonlar statülerle dip dibe").
		Artık lobi üç şeride ayrıldı:

		    ön üçte bir   → oturaklar (giriş, bekleme)
		    orta          → ışınlanma kürsüsü, çark, dolaplar
		    arka üçte bir → heykel galerisi ve sıralama panoları
	]]
	for i = 0, 1 do
		bench(centerX - halfLW + 11, lobbyZ - halfLD + 26 + i * 22, -90)
		bench(centerX + halfLW - 11, lobbyZ - halfLD + 26 + i * 22, 90)
	end

	--[[
		Duvar dolapları. Oturakların arasındaki boşluğu dolduruyor ve
		duvarı düz bir levha olmaktan çıkarıyor. Kapak çizgileri ve kulp
		dışında bir şey yok — Skeld'in dolapları da bu kadar sade.
	]]
	local function lockers(lx: number, lz: number, facing: number, count: number)
		local base = CFrame.new(lx, 0, lz) * CFrame.Angles(0, math.rad(facing), 0)

		build({ name = "LockerBody", size = Vector3.new(count * 5, 12, 3),
			cf = base * CFrame.new(0, 6, 0), color = STEEL_MID,
			material = Enum.Material.Metal, collide = true, parent = f })
		build({ name = "LockerTop", size = Vector3.new(count * 5 + 1, 0.8, 4),
			cf = base * CFrame.new(0, 12.4, 0), color = EDGE,
			material = Enum.Material.Metal, parent = f })

		for i = 1, count do
			local ox = (i - (count + 1) / 2) * 5
			build({ name = "LockerDoor", size = Vector3.new(4.2, 10.4, 0.4),
				cf = base * CFrame.new(ox, 6, -1.6), color = STEEL_DARK,
				material = Enum.Material.Metal, parent = f })
			build({ name = "LockerVent", size = Vector3.new(2.6, 0.9, 0.5),
				cf = base * CFrame.new(ox, 10, -1.8), color = SHADOW,
				material = Enum.Material.Metal, parent = f })
			build({ name = "LockerHandle", size = Vector3.new(0.4, 2.2, 0.5),
				cf = base * CFrame.new(ox + 1.5, 5.6, -1.9), color = EDGE,
				material = Enum.Material.Metal, parent = f })
		end
	end

	-- Dolaplar orta şeritte, galerinin başladığı yerden önce
	lockers(centerX - halfLW + 10, lobbyZ + 6, -90, 4)
	lockers(centerX + halfLW - 10, lobbyZ - 6, 90, 4)

	--[[
		YÖN TABELALARI KALDIRILDI.

		Girişin iki yanında "LUCKY SPIN" ve "LEADERBOARDS" yazan iki direk
		vardı. Amaçları yönlendirmekti ama ikisi de yolun tam ortasında
		duruyor ve gereksiz görünüyordu: çarkın kendi tabelası zaten LUCKY
		SPIN diyor, panolar da başlıklarını taşıyor. Yönü artık sadece
		zemindeki boyalı güzergâh anlatıyor — okunacak bir şey yok, takip
		edilecek bir çizgi var.
	]]

	--[[
		GÖRÜNMEZ EMNİYET ÇEPERİ.

		Lobi duvarları 46 stud ama köprüyle duvarın buluştuğu köşelerde,
		eğimli yüzeylerden sekerek dışarı çıkılabiliyordu. Bütün çevreye
		görünmez bir duvar çekiliyor: beş parça, hiçbir açıdan boşluk yok.
	]]
	local safety = {
		{ centerX, lobbyZ + halfLD + 1, LOBBY_W + 4, 2 },
		{ centerX - halfLW - 1, lobbyZ, 2, LOBBY_D + 4 },
		{ centerX + halfLW + 1, lobbyZ, 2, LOBBY_D + 4 },
	}
	for _, s in safety do
		build({ name = "LobbySafety", size = Vector3.new(s[3], 70, s[4]),
			cf = at(s[1], 35, s[2]), color = GLASS,
			material = Enum.Material.SmoothPlastic, collide = true,
			transparency = 1, parent = f })
	end

	-- Ön kenar: kapı boşluğu açık kalacak şekilde iki parça
	local safeSide = (LOBBY_W - LOBBY_GATE_WIDTH) / 2
	for _, s in { -1, 1 } do
		build({ name = "LobbySafety", size = Vector3.new(safeSide, 70, 2),
			cf = at(centerX + s * (LOBBY_GATE_WIDTH / 2 + safeSide / 2), 35, lobbyZ - halfLD - 1),
			color = GLASS, material = Enum.Material.SmoothPlastic, collide = true,
			transparency = 1, parent = f })
	end
end

-- ─── 14. Işınlanma kürsüsü ──────────────────────────────────────────────────
-- Ped yerine kürsü: üstüne basınca değil, yanına gelince arayüz açılıyor.
-- Yanlışlıkla basıp ışınlanmak sinir bozucu olurdu.

do
	local f = group("TeleportPad")
	local z = lobbyZ

	build({ name = "PadBase", size = Vector3.new(16, 1.2, 16),
		cf = at(centerX, 0.6, z), color = TRIM,
		material = Enum.Material.Metal, collide = true, parent = f })
	build({ name = "PadRing", size = Vector3.new(13, 0.2, 13),
		cf = at(centerX, 1.3, z), color = NEON,
		emit = "Indicator", transparency = 0.25, parent = f })

	local column = build({ name = "PadColumn", size = Vector3.new(4, 7, 4),
		cf = at(centerX, 4.7, z), color = HULL,
		material = Enum.Material.Metal, collide = true, parent = f })
	column:SetAttribute("TeleportHub", true)

	build({ name = "PadTop", size = Vector3.new(6.5, 1, 6.5),
		cf = at(centerX, 8.7, z), color = TRIM,
		material = Enum.Material.Metal, parent = f })

	local beacon = build({ name = "PadBeacon", size = Vector3.new(3, 3, 3),
		cf = at(centerX, 10, z), color = NEON,
		emit = "Fixture", shape = Enum.PartType.Ball, parent = f })
	glow(beacon, NEON, 34, 2)
	beacon:SetAttribute("PulsePeriod", 2.4)

	-- Başlık
	local anchor = build({ name = "PadLabel", size = Vector3.new(1, 1, 1),
		cf = at(centerX, 14, z), color = HULL, transparency = 1, parent = f })

	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromScale(12, 3)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 220
	gui.Parent = anchor

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextColor3 = NEON
	text.TextStrokeTransparency = 0.25
	text.Text = "TRANSIT"
	text.Parent = gui
end

-- ─── 15. Sıralama panoları ──────────────────────────────────────────────────
-- Arka duvarda üç büyük ekran. İçeriklerini istemci dolduruyor.

do
	local f = group("Boards")
	local z = lobbyZ + LOBBY_D / 2 - 2.6
	local titles = { "RICHEST", "MOST STOLEN", "TOP INCOME" }

	for i, title in titles do
		local x = centerX + (i - 2) * 52

		build({ name = "BoardFrame", size = Vector3.new(46, 26, 1.2),
			cf = at(x, 17, z), color = TRIM,
			material = Enum.Material.Metal, parent = f })

		local screen = build({ name = "BoardScreen" .. i, size = Vector3.new(43, 23, 0.6),
			cf = at(x, 17, z - 0.8), color = Color3.fromRGB(10, 14, 22),
			material = Enum.Material.SmoothPlastic, parent = f })

		local surface = Instance.new("SurfaceGui")
		surface.Name = "Display"
		surface.Face = Enum.NormalId.Front
		surface.CanvasSize = Vector2.new(430, 230)
		surface.LightInfluence = 0
		surface.Parent = screen

		local header = Instance.new("TextLabel")
		header.Name = "Header"
		header.Size = UDim2.new(1, 0, 0, 40)
		header.BackgroundTransparency = 1
		header.Font = Enum.Font.GothamBold
		header.TextSize = 26
		header.TextColor3 = NEON
		header.Text = title
		header.Parent = surface

		local body = Instance.new("TextLabel")
		body.Name = "Body"
		body.Position = UDim2.fromOffset(0, 44)
		body.Size = UDim2.new(1, 0, 1, -50)
		body.BackgroundTransparency = 1
		body.Font = Enum.Font.GothamMedium
		body.TextSize = 20
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.TextColor3 = Color3.fromRGB(235, 240, 250)
		body.Text = "..."
		body.Parent = surface

		build({ name = "BoardGlow", size = Vector3.new(44, 0.3, 0.4),
			cf = at(x, 4.4, z - 0.9), color = NEON_MID,
			emit = "Paint", parent = f })
	end
end

-- ─── 16. Çark (şimdilik dekor) ──────────────────────────────────────────────
--[[
	Ödül verme kısmı sunucu işi. Burada geometri ve dönüş var.

	Çark baştan yazıldı. Eskisi bir disk + sekiz ince çubuktu; "dilim" olması
	gereken parçalar tel gibi ince kaldığı için çark değil pervane gibi
	duruyordu. Gerçek bir şans çarkının okunması üç şeye bağlı:

	  1. Dilimler BİTİŞİK olmalı — aralarından arka levha görünmemeli.
	     Dilim genişliği yarıçapa göre hesaplanır: dış kiriş 2R·sin(pi/N).
	     Eskisi sabit 2.6 studdu, R=13 için gereken 6.7 idi.
	  2. Bir jant olmalı. Çemberi kapatan kalın halka, diski çarka çevirir.
	  3. Durdurucu dil ve pimler olmalı. Çarkın nerede duracağını anlatan
	     tek eleman o; olmayınca dönen disk sadece dekor kalıyor.

	Ayrıca ampul çerçevesi artık DÖNMÜYOR. Eskiden ampuller diskle beraber
	döndüğü için ışık deseni hiç değişmiyordu; şimdi sabit çerçevede sırayla
	yanıyorlar (DecorFX her ampule eklenme sırasına göre faz veriyor).

	Renkler mürettebat paletinden: on iki dilim, on iki tulum rengi.
]]

do
	local f = group("Wheel")
	local x = centerX - LOBBY_W / 2 + 36
	local z = lobbyZ + 6

	local R = 11                 -- çark yarıçapı
	local SLICES = 12            -- mürettebat rengi sayısı kadar
	local hubY = 16              -- lobi tavanı 42.6; çark buna göre alçaltıldı
	local SPIN = 26

	-- ── Kaide: iki bacaklı A çerçeve ────────────────────────────────────────

	build({ name = "WheelDeck", size = Vector3.new(30, 1, 18),
		cf = at(x, 0.5, z), color = HULL_DARK,
		material = Enum.Material.Metal, collide = true, parent = f })

	-- Kaidenin önünde uyarı şeridi: burası bir makine, üstüne çıkılmaz
	for i = 0, 9 do
		build({ name = "WheelHazard", size = Vector3.new(2.4, 0.16, 1.2),
			cf = at(x - 13.5 + i * 3, 1.05, z - 8.4),
			color = if i % 2 == 0 then HAZARD else HAZARD_DARK,
			material = Enum.Material.SmoothPlastic, parent = f })
	end

	build({ name = "WheelPlinth", size = Vector3.new(14, 5, 10),
		cf = at(x, 3.5, z), color = HULL,
		material = Enum.Material.Metal, collide = true, parent = f })
	build({ name = "WheelPlinthCap", size = Vector3.new(15, 0.6, 11),
		cf = at(x, 6.3, z), color = TRIM,
		material = Enum.Material.Metal, collide = true, parent = f })

	--[[ Eğik bacaklar. Dik iki çubuk yerine içe yatan çerçeve: gerçek çark
	     standı böyle durur ve siluet çok daha sağlam okunur. ]]
	local legH = hubY - 6
	for _, s in { -1, 1 } do
		build({ name = "WheelLeg", size = Vector3.new(2.4, legH + 3, 2.4),
			cf = at(x + s * 8, 6 + legH / 2, z + 1.2) * CFrame.Angles(0, 0, math.rad(-s * 11)),
			color = HULL, material = Enum.Material.Metal, collide = true, parent = f })
		build({ name = "WheelBrace", size = Vector3.new(11, 1.4, 1.4),
			cf = at(x + s * 4, 13, z + 1.2), color = TRIM,
			material = Enum.Material.Metal, parent = f })
	end

	-- ── Sabit arka çerçeve ve ampul kuşağı ──────────────────────────────────

	build({ name = "WheelBacking", size = Vector3.new(R * 2 + 5, R * 2 + 5, 0.8),
		cf = at(x, hubY, z + 2.2), color = HULL_DARK,
		material = Enum.Material.Metal, parent = f })

	local BULBS = 24
	for i = 1, BULBS do
		local a = (i - 1) * (math.pi * 2 / BULBS)
		local bulb = build({
			name = "WheelBulb",
			size = Vector3.new(1.3, 1.3, 1.3),
			cf = CFrame.new(x, hubY, z + 1.6) * CFrame.Angles(0, 0, a) * CFrame.new(R + 2.6, 0, 0),
			color = if i % 2 == 0 then LAMP else NEON_WARM,
			emit = "Indicator",
			shape = Enum.PartType.Ball,
			parent = f,
		})
		bulb:SetAttribute("PulsePeriod", 1.4)
	end

	-- ── Dönen kısım ─────────────────────────────────────────────────────────

	local function spins(part: Part): Part
		part:SetAttribute("SpinSpeed", SPIN)
		part:SetAttribute("SpinAxis", "Z")
		return part
	end

	spins(build({ name = "WheelDisc", size = Vector3.new(R * 2 - 1, R * 2 - 1, 0.9),
		cf = at(x, hubY, z), color = HULL_DARK,
		material = Enum.Material.Metal, parent = f }))

	local chord = 2 * R * math.sin(math.pi / SLICES)
	local taper = math.tan(math.pi / SLICES)   -- yarıçap başına yarım genişlik

	--[[
		Dilim kademeli kuruluyor. Tek dikdörtgen denendi: dış kirişe göre
		genişlettiğinde göbeğe yakın kısımda komşusuyla üst üste biniyor,
		iki yüzey aynı düzlemde olduğu için kamera oynadıkça titriyordu.
		Dar tuttuğunda da dilim değil çubuk oluyordu.

		Çözüm: her dilimi yarıçap boyunca RINGS parçaya bölmek ve her
		parçanın genişliğini bulunduğu yarıçapa göre hesaplamak. Sonuç
		kademeli ama gerçek bir pasta dilimi — boşluk da yok, çakışma da.
	]]
	local RINGS = 5

	for i = 1, SLICES do
		local a = (i - 1) * (math.pi * 2 / SLICES)
		local pivot = CFrame.new(x, hubY, z - 0.7) * CFrame.Angles(0, 0, a)
		local tone = crewColor(i)

		for j = 1, RINGS do
			local rMid = R * (j - 0.5) / RINGS
			spins(build({
				name = "WheelSlice",
				size = Vector3.new(R / RINGS + 0.05, 2 * rMid * taper * 0.98, 0.7),
				cf = pivot * CFrame.new(rMid, 0, 0),
				-- Dışa doğru hafif açılan ton: düz tek renk dilim yassı
				-- duruyordu, bu kademe çarka hacim veriyor
				color = tone:Lerp(Color3.new(1, 1, 1), (j - 1) / RINGS * 0.18),
				material = Enum.Material.SmoothPlastic,
				parent = f,
			}))
		end

		-- Dilimler arası ayraç: sınır net olsun
		spins(build({
			name = "WheelSpoke",
			size = Vector3.new(R * 0.96, 0.5, 1),
			cf = pivot * CFrame.Angles(0, 0, math.pi / SLICES) * CFrame.new(R * 0.5, 0, 0),
			color = TRIM,
			material = Enum.Material.Metal,
			parent = f,
		}))

		-- Jant parçası: çokgen halka, çarkın çevresini kapatıyor
		spins(build({
			name = "WheelRim",
			size = Vector3.new(1.6, chord + 0.3, 2.2),
			cf = pivot * CFrame.new(R + 0.4, 0, 0),
			color = TRIM,
			material = Enum.Material.Metal,
			parent = f,
		}))

		-- Pim: durdurucu dilin çarptığı çubuk
		spins(build({
			name = "WheelPeg",
			size = Vector3.new(1, 0.7, 0.7),
			cf = pivot * CFrame.Angles(0, 0, math.pi / SLICES) * CFrame.new(R + 1.8, 0, 0),
			color = LAMP,
			material = Enum.Material.Metal,
			parent = f,
		}))
	end

	-- Göbek. Silindirin ekseni yerel X; çarka baksın diye Y etrafında 90°.
	local hub = build({ name = "WheelHub", size = Vector3.new(2, 6, 6),
		cf = at(x, hubY, z - 1.2) * CFrame.Angles(0, math.rad(90), 0),
		color = TRIM, material = Enum.Material.Metal,
		shape = Enum.PartType.Cylinder, parent = f })

	build({ name = "WheelHubCap", size = Vector3.new(1, 2.6, 2.6),
		cf = at(x, hubY, z - 2.2) * CFrame.Angles(0, math.rad(90), 0),
		color = HULL_DARK, material = Enum.Material.Metal,
		shape = Enum.PartType.Cylinder, parent = f })

	-- ── Durdurucu dil ───────────────────────────────────────────────────────

	build({ name = "TickerMount", size = Vector3.new(3, 1.6, 3),
		cf = at(x, hubY + R + 4.4, z - 0.8), color = HULL,
		material = Enum.Material.Metal, parent = f })
	build({ name = "TickerArm", size = Vector3.new(1.2, 4.2, 1.6),
		cf = at(x, hubY + R + 1.8, z - 0.8) * CFrame.Angles(0, 0, math.rad(7)),
		color = TRIM, material = Enum.Material.Metal, parent = f })
	local tip = build({ name = "TickerTip", size = Vector3.new(2.2, 1.4, 2),
		cf = at(x, hubY + R - 0.3, z - 0.8), color = HAZARD,
		emit = "Indicator", parent = f })

	--[[
		── Marka tabelası ──────────────────────────────────────────────────

		Yazı artık BillboardGui değil, panonun yüzeyine basılı SurfaceGui.

		BillboardGui her zaman kameraya döner ve kendi çapa noktasının
		derinliğinde çizilir; çapa panonun içinde kaldığı için pano yazıyı
		kesiyor, belli açılardan da yazı panoyla iç içe geçiyordu. SurfaceGui
		yüzeye boyanmış gibi durur, derinlik sorunu olmaz ve asıl önemlisi:
		gerçek bir tabela gibi okunur, havada yüzen yazı gibi değil.

		YÜKSEKLİK: ilk denemede tabela hubY+R+4'teydi, durdurucu dil de
		hubY+R+4.4'te — ikisi üst üste geliyordu ve dilin gövdesi tam
		"LUCKY" ile "SPIN" arasına oturuyordu. Tabela +10'a çıktı, çark
		küçültüldü (R 13→11, göbek 19→16). Artık durdurucunun tepesi 31.2,
		tabelanın altı 33.0 — arada 1.8 stud boşluk var.
	]]
	local signY = hubY + R + 11

	local board = build({ name = "SignBoard", size = Vector3.new(34, 7, 1),
		cf = at(x, signY, z + 1.6), color = SHADOW,
		material = Enum.Material.SmoothPlastic, parent = f })
	build({ name = "SignFrame", size = Vector3.new(36, 8.6, 0.6),
		cf = at(x, signY, z + 2.1), color = TRIM,
		material = Enum.Material.Metal, parent = f })
	for _, s in { -1, 1 } do
		build({ name = "SignPost", size = Vector3.new(1.4, 6, 1.4),
			cf = at(x + s * 15, signY - 6.5, z + 1.6), color = TRIM,
			material = Enum.Material.Metal, parent = f })
	end

	-- Tabelanın altına iki gömme spot: yazıyı yıkasın
	for _, s in { -1, 1 } do
		local wash = build({ name = "SignWash", size = Vector3.new(3, 0.5, 1),
			cf = at(x + s * 9, signY - 4.6, z + 0.9), color = LAMP,
			emit = "Fixture", parent = f })
		glow(wash, LAMP, 12, 0.7)
	end

	local surface = Instance.new("SurfaceGui")
	surface.Name = "Label"
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(340, 80)
	surface.LightInfluence = 0
	surface.Parent = board

	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextScaled = true
	text.TextColor3 = BRASS
	text.Text = "LUCKY SPIN"
	text.Parent = surface

	-- Çarkı çeviren mürettebat: tabelanın üstünde değil, kaidenin yanında.
	-- Tabelanın üstündeyken lobi tavanını deliyordu.
	crewStatue(f, x + 12, z - 6, 1, 1.5, CREW[6], -60)
end

-- ─── 16b. Varsayılan doğuş noktasını gizle ──────────────────────────────────
--[[
	Yerleşimin kendi SpawnLocation'ı haritanın merkezine yakın duruyor ve
	istasyon büyüdükçe BAY 06'nın tam içine düştü: camgöbeği bir kare ve
	ortasında Roblox'un siyah yıldız dokusu. Oyuncular zaten kendi üslerine
	doğuyor (PlotService bunu SpawnPad ile yapıyor), yani bu nesnenin
	oyunda hiçbir işlevi yok.

	Silinmiyor çünkü Studio boş bir yerleşimde onu yeniden yaratıyor;
	kapatılıp gövdenin altına alınıyor.
]]
do
	local spawn = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawn then
		spawn.Enabled = false
		spawn.Transparency = 1
		spawn.CanCollide = false
		spawn.CFrame = at(centerX, -HULL_DEPTH - 14, centerZ)
		for _, d in spawn:GetChildren() do
			if d:IsA("Decal") or d:IsA("Texture") then
				d:Destroy()
			end
		end
	end
end

-- ─── 17. Baseplate'i gövdenin altına gizle ──────────────────────────────────
--[[
	Varsayılan 2048x2048 Baseplate, Slate malzemesiyle koyu rengi yıkıyor ve
	uzaktan devasa açık gri bir düzlem olarak her şeyi bastırıyordu. İstasyon
	uzayda yüzüyor, altında sonsuz zemin olmamalı. Silmek yerine gövdenin
	altına gizliyoruz: bir şey ters giderse yakalayacak taban kalsın.
]]
do
	local bp = workspace:FindFirstChild("Baseplate")
	if bp and bp:IsA("BasePart") then
		bp.Size = Vector3.new(halfW * 2 - 80, 4, halfD * 2 - 80)
		bp.CFrame = at(centerX, -HULL_DEPTH - 6, centerZ)
		bp.Color = HULL_DARK
		bp.Material = Enum.Material.SmoothPlastic
		bp.Anchored = true
		bp.TopSurface = Enum.SurfaceType.Smooth
		bp.BottomSurface = Enum.SurfaceType.Smooth
	end
end

-- ─── Özet ───────────────────────────────────────────────────────────────────

local parts = 0
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	end
end

print(string.format("Decor: %d us (%d sutun x %d satir), %d parca", PLOT_COUNT, COLUMNS, ROWS, parts))
print(string.format("Istasyon: %.0f x %.0f stud, duvar %d, govde alti %d",
	halfW * 2, halfD * 2, WALL_H, HULL_DEPTH))
print(string.format("Oran: %.1f:1  (dusukse daha derli toplu gorunur)", (halfW * 2) / (halfD * 2)))
