--!strict
--[[
	Harita kurucusunun ortak araç seti: ölçüler, palet, parça yardımcıları,
	Skeld tarzı duvar/zemin/tabela/mürettebat üreticileri.

	Her bölüm dosyası (tools/map/*.luau) bu tabloyu alıp kendi klasörlerini
	kuruyor. Ölçüler Config'ten geliyor; üs yerleşimi değişirse harita
	kendiliğinden uyuyor.

	STİL KURALLARI (Among Us / Skeld referansı):
	  - Malzeme neredeyse her yerde SmoothPlastic: çizgi film görünümü.
	    Metal/Concrete dokusu gerçekçi durup temayı bozuyor.
	  - Renkler açık ve doygun; koyu ton sadece gölge/oluk için.
	  - Yazılar FredokaOne, beyaz + koyu kontur (oyunun oda etiketleri).
	  - Parlayan yüzey sınıflıdır (emit): Fixture / Screen / Indicator.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local K = {}

-- ─── Ölçüler ────────────────────────────────────────────────────────────────

local cfg: any = nil
do
	local ok, result = pcall(function()
		-- Klon: Studio hatalı bir require'ı önbelleğe alıyor, klon almıyor
		local copy = ReplicatedStorage.Shared.Config:Clone()
		local r = require(copy)
		copy:Destroy()
		return r
	end)
	if ok and typeof(result) == "table" then
		cfg = result
	else
		warn("map/kit: Config okunamadi, varsayilanlar kullaniliyor")
		cfg = {}
	end
end
K.Config = cfg

local M = {}
K.M = M

M.PLOT_COUNT = cfg.PlotCount or 8
M.PLOT_SIZE = cfg.PlotSize or Vector3.new(72, 2, 52)
M.PLOT_SPACING = cfg.PlotSpacing or 120
M.COLUMNS = cfg.PlotColumns or 4
M.ROW_SPACING = cfg.PlotRowSpacing or 116
M.PODIUMS = cfg.PodiumsPerPlot or 8
M.PODIUM_GAP = cfg.PodiumSpacing or 7.5
M.PODIUM_ROW_Z = cfg.PodiumRowZ or 9
M.FLOOR_H = cfg.FloorHeight or 18
M.ROWS = math.ceil(M.PLOT_COUNT / M.COLUMNS)

M.halfX = M.PLOT_SIZE.X / 2
M.halfZ = M.PLOT_SIZE.Z / 2
M.topY = M.PLOT_SIZE.Y / 2

M.centerX = (M.COLUMNS - 1) * M.PLOT_SPACING / 2
M.centerZ = (M.ROWS - 1) * M.ROW_SPACING / 2

M.MARGIN = 42
-- İstasyon iç sınırları (duvar merkez çizgileri)
M.X0 = M.centerX - ((M.COLUMNS - 1) * M.PLOT_SPACING / 2 + M.halfX + M.MARGIN)
M.X1 = M.centerX + ((M.COLUMNS - 1) * M.PLOT_SPACING / 2 + M.halfX + M.MARGIN)
M.Z0 = M.centerZ - ((M.ROWS - 1) * M.ROW_SPACING / 2 + M.halfZ + M.MARGIN)
M.Z1 = M.centerZ + ((M.ROWS - 1) * M.ROW_SPACING / 2 + M.halfZ + M.MARGIN)

M.WALL_T = 2.4          -- duvar kalınlığı
M.WALL_H = 52           -- 3 kat (37) + karakter + etiket + pay
M.ROOM_HX = 42          -- oda (üs bölgesi) yarı genişliği: koridor 36 kalıyor
M.ROOM_FRONT = 8        -- odanın üs önünden koridora taşması
M.PART_WALL_H = 15      -- oda bölme duvarı yüksekliği
M.GATE_W = 36           -- lobiye açılan kapı = koridor genişliği
M.GATE_H = 24

-- Lobi (Cafeteria) — istasyonun önünde (+z), köprüyle bağlı
M.BRIDGE_LEN = 58
M.LOBBY_Z0 = M.Z1 + M.BRIDGE_LEN     -- kafeteryanın kuzey duvarı
M.CAF_W = 220
M.CAF_D = 156
M.CAF_CHAMFER = 40
M.CAF_H = 44
M.LOBBY_Z1 = M.LOBBY_Z0 + M.CAF_D
M.LOBBY_CZ = (M.LOBBY_Z0 + M.LOBBY_Z1) / 2
M.CAF_X0 = M.centerX - M.CAF_W / 2
M.CAF_X1 = M.centerX + M.CAF_W / 2
M.WING_W = 90                         -- MedBay / Weapons kanat genişliği
M.WING_H = 30

-- İç yüzler
M.IX0 = M.X0 + M.WALL_T / 2
M.IX1 = M.X1 - M.WALL_T / 2
M.IZ0 = M.Z0 + M.WALL_T / 2
M.IZ1 = M.Z1 - M.WALL_T / 2

-- Omurga koridoru (iki üs sırası arası) z aralığı
M.SPINE_Z0 = M.halfZ + M.ROOM_FRONT
M.SPINE_Z1 = M.ROW_SPACING - M.halfZ - M.ROOM_FRONT

-- Koridor uçlarındaki simge alanlar: batıda Reaktör, doğuda Navigasyon
-- Duvar yüzünden 0.3 içeride: süpürgelikle aynı düzlemde kalmasın
M.REACTOR_RECT = { M.IX0 + 0.3, M.SPINE_Z0 + 4, M.IX0 + 28, M.SPINE_Z1 - 4 }
M.NAV_RECT = { M.IX1 - 28, M.SPINE_Z0 + 4, M.IX1 - 0.3, M.SPINE_Z1 - 4 }

-- Yüzeye yatan ince parçaların çakışmasını önleyen küçük pay
M.LIFT = 0.03
-- Karo üst yüzü (istasyon ve lobi zemini)
M.TILE_TOP = 0.27

function K.plotOrigin(index: number): Vector3
	local col = (index - 1) % M.COLUMNS
	local row = math.floor((index - 1) / M.COLUMNS)
	return Vector3.new(col * M.PLOT_SPACING, 0, row * M.ROW_SPACING)
end

function K.plotRow(index: number): number
	return math.floor((index - 1) / M.COLUMNS)
end

--[[
	PlotService çift satırlı düzende ÜST satırı 180° çeviriyor (satırlar
	koridora baksın diye). flip = -1 ise üssün "arkası" (konveyör) -z'de.
	Aynı koşul PlotService'te; biri değişirse diğeri de değişmeli.
]]
function K.plotFlip(index: number): number
	local row = K.plotRow(index)
	return if M.ROWS > 1 and row % 2 == 0 then -1 else 1
end

-- Üssün koridora baktığı yön (+1: +z, -1: -z)
function K.plotFacing(index: number): number
	return -K.plotFlip(index)
end

--[[
	Oda bölgesi: üssün etrafı + arka duvara kadar olan alan. Dikdörtgen
	{x0, z0, x1, z1}.
]]
function K.roomRect(index: number): { number }
	local o = K.plotOrigin(index)
	local facing = K.plotFacing(index)
	local front = o.Z + facing * (M.halfZ + M.ROOM_FRONT)
	-- Arka kenar duvarın iç yüzünden 0.3 içeride: süpürgelikle aynı düzlemde kalmasın
	local back = if facing > 0 then M.Z0 + M.WALL_T / 2 + 0.3 else M.Z1 - M.WALL_T / 2 - 0.3
	return { o.X - M.ROOM_HX, math.min(front, back), o.X + M.ROOM_HX, math.max(front, back) }
end

function K.plotRect(index: number, pad: number?): { number }
	local o = K.plotOrigin(index)
	local p = pad or 0
	return { o.X - M.halfX - p, o.Z - M.halfZ - p, o.X + M.halfX + p, o.Z + M.halfZ + p }
end

-- ─── Palet ──────────────────────────────────────────────────────────────────

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
K.rgb = rgb

local C = {
	-- Skeld koridoru
	hallTile = rgb(168, 190, 202),
	hallTile2 = rgb(156, 179, 192),
	hallGrout = rgb(96, 118, 132),
	hallLane = rgb(186, 204, 214),

	-- Duvar katmanları (alttan üste)
	wallKick = rgb(52, 70, 82),
	wallLow = rgb(84, 112, 128),
	wallSeam = rgb(66, 90, 104),
	wallRail = rgb(214, 228, 236),
	wallMid = rgb(132, 158, 172),
	wallHigh = rgb(104, 130, 146),
	wallCap = rgb(222, 234, 240),
	hullOut = rgb(70, 88, 100),

	frame = rgb(226, 236, 242),
	frameDark = rgb(160, 178, 190),
	glass = rgb(170, 220, 250),
	ceiling = rgb(88, 108, 122),
	ceilingPanel = rgb(116, 138, 152),
	lamp = rgb(255, 250, 238),

	hazard = rgb(252, 204, 48),
	hazardDark = rgb(44, 44, 50),
	shadow = rgb(30, 38, 46),
	screenDark = rgb(16, 30, 44),
	red = rgb(222, 52, 52),
	green = rgb(70, 214, 110),
	cyan = rgb(90, 226, 246),
	orange = rgb(240, 138, 40),
	white = rgb(242, 246, 250),
	metal = rgb(176, 188, 196),
	metalDark = rgb(118, 130, 140),

	-- Kafeterya
	cafTile = rgb(236, 228, 206),
	cafTile2 = rgb(218, 210, 188),
	cafGrout = rgb(170, 160, 138),
	tableTop = rgb(92, 150, 212),
	tableRim = rgb(170, 214, 244),
	bench = rgb(60, 106, 170),

	-- MedBay / Weapons
	medTile = rgb(214, 228, 236),
	medTile2 = rgb(198, 214, 224),
	medGrout = rgb(140, 160, 172),
	weapTile = rgb(214, 198, 162),
	weapTile2 = rgb(198, 182, 148),
	weapGrout = rgb(146, 130, 100),
}
K.C = C

-- Mürettebat renkleri — oyunun kendi paleti
K.CREW = {
	rgb(197, 17, 17), rgb(19, 46, 209), rgb(17, 128, 45), rgb(238, 84, 187),
	rgb(239, 125, 13), rgb(245, 245, 87), rgb(63, 71, 78), rgb(215, 224, 240),
	rgb(107, 47, 187), rgb(113, 73, 30), rgb(56, 254, 220), rgb(80, 240, 57),
}

function K.crew(i: number): Color3
	return K.CREW[(i - 1) % #K.CREW + 1]
end

--[[
	Oda temaları. Sıra üs numarasına göre; 1-4 arka satır, 5-8 ön satır.
	Skeld'de motorlar solda üst üste — burada da 1 ve 5 (en soldaki sütun)
	motor odaları ve aralarındaki koridor ucunda Reaktör duruyor.
]]
export type Theme = {
	id: string,
	name: string,
	tile: Color3,
	tile2: Color3,
	grout: Color3,
	accent: Color3,
}

-- Tek kaynak Config.BayRooms (PlotService üs zeminini de aynı renge boyuyor)
K.THEMES = (cfg.BayRooms or {}) :: { Theme }
if #K.THEMES == 0 then
	warn("map/kit: Config.BayRooms yok; oda temaları kurulamaz")
end

function K.theme(index: number): Theme
	return K.THEMES[(index - 1) % #K.THEMES + 1]
end

-- ─── Klasörler ──────────────────────────────────────────────────────────────

local root = workspace:FindFirstChild("Decor")
if not root then
	root = Instance.new("Folder")
	root.Name = "Decor"
	root.Parent = workspace
end
K.root = root :: Folder

function K.folder(name: string, parent: Instance?): Folder
	local p = parent or K.root
	local existing = p:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = p
	return f
end

function K.clear(names: { string })
	for _, n in names do
		local old = K.root:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
end

-- ─── Parçalar ───────────────────────────────────────────────────────────────

--[[
	Parlayan yüzey sınıfları. Parlamanın toplam dozu tek yerden ayarlanıyor.
	  Fixture   — gerçek armatür, tam parlak, ışık saçabilir
	  Screen    — ekran, pano: orta parlaklık, ışık yok
	  Indicator — küçük gösterge ampulü: kısık parlaklık
]]
local EMIT = {
	Fixture = 0.0,
	Screen = 0.35,
	Indicator = 0.2,
}

export type Opts = {
	name: string?,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?,
	collide: boolean?,
	transparency: number?,
	shape: Enum.PartType?,
	emit: string?,
	reflect: number?,
	parent: Instance,
}

--[[
	Katılık varsayılanı: görünen katıdır. İstisnalar otomatik:
	parlayan yüzeyler (ışık hacim değildir) ve yere yatık ince kaplamalar
	(yükseklik <= 0.6: boya, şerit — üstünde yürünmeli, takılmamalı).
]]
local function solid(o: Opts): boolean
	if o.collide ~= nil then
		return o.collide
	end
	if o.emit ~= nil then
		return false
	end
	return o.size.Y > 0.6
end

function K.part(o: Opts): Part
	local p = Instance.new("Part")
	p.Name = o.name or "Deco"
	p.Size = o.size
	p.CFrame = o.cf
	p.Anchored = true
	p.CanCollide = solid(o)
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.shape then
		p.Shape = o.shape
	end
	if o.emit then
		p.Material = Enum.Material.Neon
		p.Color = o.color:Lerp(Color3.new(0, 0, 0), EMIT[o.emit] or 0)
		p.CastShadow = false
	else
		p.Material = o.material or Enum.Material.SmoothPlastic
		p.Color = o.color
	end
	p.Transparency = o.transparency or 0
	if o.reflect then
		p.Reflectance = o.reflect
	end
	p.Parent = o.parent
	return p
end

-- Kısayol: eksene hizalı kutu
function K.box(parent: Instance, name: string, cx: number, cy: number, cz: number, sx: number, sy: number, sz: number, color: Color3, extra: { [string]: any }?): Part
	local o: any = { name = name, size = Vector3.new(sx, sy, sz), cf = CFrame.new(cx, cy, cz), color = color, parent = parent }
	if extra then
		for k, v in extra do
			o[k] = v
		end
	end
	return K.part(o)
end

-- CFrame ile kutu
function K.boxAt(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, extra: { [string]: any }?): Part
	local o: any = { name = name, size = size, cf = cf, color = color, parent = parent }
	if extra then
		for k, v in extra do
			o[k] = v
		end
	end
	return K.part(o)
end

--[[
	Dikey silindir. Roblox silindirinin ekseni yerel X; dik durması için
	Z etrafında 90° çevriliyor. Boyut: (yükseklik, çap, çap).
]]
function K.vcyl(parent: Instance, name: string, x: number, y: number, z: number, height: number, diameter: number, color: Color3, extra: { [string]: any }?): Part
	return K.boxAt(parent, name, CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(height, diameter, diameter), color, K.merge({ shape = Enum.PartType.Cylinder }, extra))
end

-- Ekseni verilen CFrame'in X ekseni olan silindir
function K.cyl(parent: Instance, name: string, cf: CFrame, length: number, diameter: number, color: Color3, extra: { [string]: any }?): Part
	return K.boxAt(parent, name, cf, Vector3.new(length, diameter, diameter), color,
		K.merge({ shape = Enum.PartType.Cylinder }, extra))
end

function K.ball(parent: Instance, name: string, x: number, y: number, z: number, diameter: number, color: Color3, extra: { [string]: any }?): Part
	return K.boxAt(parent, name, CFrame.new(x, y, z), Vector3.new(diameter, diameter, diameter), color,
		K.merge({ shape = Enum.PartType.Ball }, extra))
end

--[[
	Elipsoit: kutu parça + SpecialMesh(Sphere). Mesh parçanın boyutunu
	kullanıyor, yani eşit olmayan eksenli yuvarlak şekil veriyor (vizör,
	yumurta, bitki yaprağı). Hazır asset değil, Roblox'un kendi şekli.
]]
function K.ellipsoid(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, extra: { [string]: any }?): Part
	local p = K.boxAt(parent, name, cf, size, color, extra)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

--[[
	Yatay üçgen prizma (tavan/zemin köşesi). Kama parçasının üçgen yüzü
	yerel YZ düzleminde; yatırmak için X etrafında çeviriyoruz.
	a, b, c: dik açılı üçgenin köşeleri — c dik açının köşesi.
]]
function K.flatTriangle(parent: Instance, name: string, a: Vector2, b: Vector2, c: Vector2, y: number, thick: number, color: Color3, extra: { [string]: any }?): Part
	-- Kama: yerel Y yüksekliği, Z derinliği; eğik yüz +Y/-Z köşesinden.
	-- Dik açı köşesi yerel (−Y, +Z)... basitlik için iki kenar vektörüyle
	-- CFrame.fromMatrix kuruyoruz: kama X = kalınlık ekseni.
	local ca = a - c
	local cb = b - c
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.CanQuery = false
	w.CanTouch = false
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.Material = Enum.Material.SmoothPlastic
	w.Color = color
	w.CanCollide = true
	-- Kamanın dik köşesi yerel (-Y, -Z)... WedgePart: eğim +Z tarafında
	-- yükselir; dik açı (y=-h/2, z=+d/2) değil, (y=-h/2, z=-d/2)... Roblox
	-- kamasında dolu köşe (-Y, +Z)'dir: arka alt köşe.
	-- Yerel Y ekseni = c->a yönü, yerel Z ekseni = b->c yönü (yani -cb).
	local yAxis = Vector3.new(ca.X, 0, ca.Y).Unit
	local zAxis = -Vector3.new(cb.X, 0, cb.Y).Unit
	local xAxis = yAxis:Cross(zAxis)
	-- xAxis yukarı ya da aşağı bakabilir; kalınlık simetrik olduğu için fark etmez
	local center2 = c + ca / 2 + cb / 2
	local cf = CFrame.fromMatrix(Vector3.new(center2.X, y, center2.Y), xAxis, yAxis, zAxis)
	w.Size = Vector3.new(thick, ca.Magnitude, cb.Magnitude)
	w.CFrame = cf
	if extra then
		for k, v in extra do
			(w :: any)[k] = v
		end
	end
	w.Parent = parent
	return w
end

function K.merge(a: { [string]: any }, b: { [string]: any }?): { [string]: any }
	local r = table.clone(a)
	if b then
		for k, v in b do
			r[k] = v
		end
	end
	return r
end

function K.light(part: BasePart, color: Color3, range: number, brightness: number, shadows: boolean?): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = shadows == true
	l.Parent = part
	return l
end

function K.surfaceLight(part: BasePart, face: Enum.NormalId, color: Color3, range: number, brightness: number, angle: number?): SurfaceLight
	local l = Instance.new("SurfaceLight")
	l.Face = face
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Angle = angle or 120
	l.Shadows = false
	l.Parent = part
	return l
end

-- ─── Yazı ───────────────────────────────────────────────────────────────────

--[[
	Yüzeye basılı yazı (SurfaceGui). Tabela gibi okunuyor; BillboardGui
	kameraya dönüp duvarın içine gömülüyordu.
]]
function K.text(part: BasePart, face: Enum.NormalId, text: string, color: Color3, opts: { [string]: any }?): TextLabel
	local o = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = o.guiName or "Label"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = o.ppu or 24
	gui.LightInfluence = 0
	gui.Brightness = o.brightness or 1.4
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(o.w or 0.92, o.h or 0.8)
	label.Position = UDim2.fromScale(o.x or 0.04, o.y or 0.1)
	label.Font = o.font or Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeColor3 = o.stroke or Color3.fromRGB(18, 22, 30)
	label.TextStrokeTransparency = if o.noStroke then 1 else 0.05
	label.Text = text
	label.RichText = o.rich == true
	label.Parent = gui
	return label
end

--[[
	Oda tabelası: koyu levha + açık çerçeve + beyaz, konturlu oda adı.
	Oyundaki oda etiketlerinin 3B karşılığı. `cf` levhanın merkezi, levha
	yerel -Z yönüne (LookVector) bakıyor.
]]
function K.sign(parent: Instance, name: string, cf: CFrame, w: number, h: number, text: string, accent: Color3?, textColor: Color3?): Part
	local board = K.boxAt(parent, name, cf, Vector3.new(w, h, 0.8), C.shadow, { collide = false })
	K.boxAt(parent, name .. "Frame", cf * CFrame.new(0, 0, 0.35), Vector3.new(w + 1.2, h + 1.2, 0.5), C.frame, { collide = false })
	if accent then
		K.boxAt(parent, name .. "Accent", cf * CFrame.new(0, -h / 2 + 0.35, -0.46), Vector3.new(w - 1.2, 0.3, 0.12), accent, { emit = "Screen" })
	end
	K.text(board, Enum.NormalId.Front, text, textColor or C.white, { h = 0.78, y = 0.08 })
	return board
end

-- ─── Yardımcı geometri ──────────────────────────────────────────────────────

--[[
	Sarı-siyah uyarı şeridi (zemine). `along` "x" ya da "z".
]]
function K.hazard(parent: Instance, cx: number, y: number, cz: number, length: number, width: number, along: string, step: number?)
	local s = step or 2.4
	local count = math.max(1, math.floor(length / s))
	local real = length / count
	for i = 0, count - 1 do
		local off = -length / 2 + (i + 0.5) * real
		local size = if along == "x" then Vector3.new(real, 0.12, width) else Vector3.new(width, 0.12, real)
		local pos = if along == "x" then Vector3.new(cx + off, y, cz) else Vector3.new(cx, y, cz + off)
		K.boxAt(parent, "Hazard", CFrame.new(pos), size, if i % 2 == 0 then C.hazard else C.hazardDark)
	end
end

-- ─── Zemin döşeme ───────────────────────────────────────────────────────────

export type Rect = { number } -- {x0, z0, x1, z1}

local function rectSubtract(a: Rect, b: Rect): { Rect }
	-- a − b: en fazla 4 dikdörtgen
	if b[3] <= a[1] or b[1] >= a[3] or b[4] <= a[2] or b[2] >= a[4] then
		return { a }
	end
	local out: { Rect } = {}
	-- sol şerit
	if b[1] > a[1] then
		table.insert(out, { a[1], a[2], b[1], a[4] })
	end
	-- sağ şerit
	if b[3] < a[3] then
		table.insert(out, { b[3], a[2], a[3], a[4] })
	end
	local mx0, mx1 = math.max(a[1], b[1]), math.min(a[3], b[3])
	-- alt
	if b[2] > a[2] then
		table.insert(out, { mx0, a[2], mx1, b[2] })
	end
	-- üst
	if b[4] < a[4] then
		table.insert(out, { mx0, b[4], mx1, a[4] })
	end
	return out
end
K.rectSubtract = rectSubtract

--[[
	Bir dikdörtgeni karolarla döşer. Karolar `gap` kadar aralıklı; aradan
	altındaki koyu zemin görünüyor ve oluk kendiliğinden oluşuyor.
	`holes` içindeki dikdörtgenlere (üs, oda) karo girmiyor — kesilip
	kenarından `gap/2` pay bırakılıyor. Gizli, üst üste binen karo yok.
]]
function K.tiles(parent: Instance, area: Rect, tileW: number, tileD: number, gap: number, yTop: number, thick: number, colA: Color3, colB: Color3, holes: { Rect }?, name: string?)
	local nx = math.max(1, math.floor((area[3] - area[1]) / tileW + 0.5))
	local nz = math.max(1, math.floor((area[4] - area[2]) / tileD + 0.5))
	local tw = (area[3] - area[1]) / nx
	local td = (area[4] - area[2]) / nz
	local g = gap / 2
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local pieces: { Rect } = { {
				area[1] + i * tw + g, area[2] + j * td + g,
				area[1] + (i + 1) * tw - g, area[2] + (j + 1) * td - g,
			} }
			if holes then
				for _, h in holes do
					local grown = { h[1] - g, h[2] - g, h[3] + g, h[4] + g }
					local nextPieces: { Rect } = {}
					for _, p in pieces do
						for _, q in rectSubtract(p, grown) do
							table.insert(nextPieces, q)
						end
					end
					pieces = nextPieces
				end
			end
			local color = if (i + j) % 2 == 0 then colA else colB
			for _, p in pieces do
				local w, d = p[3] - p[1], p[4] - p[2]
				if w >= 0.8 and d >= 0.8 then
					K.boxAt(parent, name or "Tile", CFrame.new((p[1] + p[3]) / 2, yTop - thick / 2, (p[2] + p[4]) / 2),
						Vector3.new(w, thick, d), color)
				end
			end
		end
	end
end

-- ─── Skeld duvarı ───────────────────────────────────────────────────────────

export type WallSpec = {
	h: number,
	t: number?,
	windows: boolean?,
	winBottom: number?,
	winTop: number?,
	winW: number?,
	winGap: number?,
	rail: number?,
	doors: { { u0: number, u1: number, h: number } }?,
	-- Kapı dışı açıklık (ör. kokpit camı): [u0,u1] × [y0,y1]
	openings: { { u0: number, u1: number, y0: number, y1: number } }?,
	inset0: number?,   -- süsleme/pencere başlangıç payı (köşe)
	inset1: number?,
	name: string?,
	noCove: boolean?,
	exterior: Color3?, -- dış yüze kaplama rengi (görünen dış cephe)
	cap: Color3?,      -- duvar tepesine kapak (alçak bölmeler için)
	twoSided: boolean?, -- süpürgelik/korkuluk iki yüzde (bölme duvarı)
	lowColor: Color3?, -- alt panel rengi (oda bölmelerinde tema tonu)
}

--[[
	Skeld tarzı duvar: dipte koyu süpürgelik, alt panel + dikey derz
	çıtaları, açık renkli korkuluk bandı, pencere kuşağı (köşeleri pahlı
	pencereler), üst panel ve tavana yakın gizli ışık bandı.

	a → b duvarın merkez çizgisi (x, z). `inside` +1 ise iç taraf a→b
	yönünün SOLUNDA. Pahlı (çapraz) duvarlar da aynı kodla kuruluyor;
	her şey duvarın yerel çerçevesinde hesaplanıp döndürülüyor.
]]
function K.wall(parent: Instance, a: Vector2, b: Vector2, inside: number, spec: WallSpec)
	local H = spec.h
	local T = spec.t or M.WALL_T
	local dir = b - a
	local len = dir.Magnitude
	local u = dir.Unit
	local n = Vector2.new(-u.Y, u.X) * inside            -- içe bakan normal
	local right = Vector3.new(u.X, 0, u.Y)
	local inward = Vector3.new(n.X, 0, n.Y)
	-- LookVector = inward: yerel -Z içeri bakıyor
	local frame = CFrame.fromMatrix(Vector3.new(a.X, 0, a.Y), right, Vector3.yAxis, -inward)
	local tag = spec.name or "Wall"

	-- Yerel kutu: u boyunca merkez, y merkez, d (içe doğru) merkez
	local function piece(name: string, uc: number, yc: number, dc: number, su: number, sy: number, sd: number, color: Color3, extra: { [string]: any }?)
		if su <= 0.05 or sy <= 0.05 then
			return nil
		end
		return K.boxAt(parent, name, frame * CFrame.new(uc, yc, -dc), Vector3.new(su, sy, sd), color, extra)
	end

	-- Kapılar ve açıklıklar aynı listede: kesik [u0,u1] × [y0,y1]
	local cuts: { { u0: number, u1: number, y0: number, y1: number } } = {}
	for _, d in spec.doors or {} do
		table.insert(cuts, { u0 = d.u0, u1 = d.u1, y0 = 0, y1 = d.h })
	end
	for _, o in spec.openings or {} do
		table.insert(cuts, { u0 = o.u0, u1 = o.u1, y0 = o.y0, y1 = o.y1 })
	end
	table.sort(cuts, function(x, y)
		return x.u0 < y.u0
	end)

	-- Kesiksiz aralıklar
	local spans: { { number } } = {}
	local cursor = 0
	for _, d in cuts do
		if d.u0 > cursor then
			table.insert(spans, { cursor, d.u0 })
		end
		cursor = d.u1
	end
	if cursor < len then
		table.insert(spans, { cursor, len })
	end

	local wb = spec.winBottom or 20
	local wt = spec.winTop or (H - 12)
	local ww = spec.winW or 16
	local wg = spec.winGap or 12
	--[[
		Korkuluk bandı pencere pervazının altında kalmalı: üst üste binerse
		pervaz ve çerçeve korkuluğun içinden geçiyor, dış cephedeki kuşak da
		dış çerçeveyle aynı düzleme düşüyor. Pervazın alt kenarı wb-FW-0.5.
	]]
	local rail = math.min(spec.rail or 16, wb - 3.3)
	local inset0 = spec.inset0 or (T / 2 + 0.6)
	local inset1 = spec.inset1 or (T / 2 + 0.6)

	-- ── Çekirdek duvar ────────────────────────────────────────────────────
	local windowsAt: { { number } } = {}
	for _, s in spans do
		local s0, s1 = s[1], s[2]
		local w = s1 - s0
		local useWin = spec.windows ~= false and ww > 0
		-- Pencere dizisi aralığın ortasına simetrik yerleşiyor
		local a0 = math.max(s0, inset0) + wg / 2
		local a1 = math.min(s1, len - inset1) - wg / 2
		local count = if useWin then math.floor((a1 - a0 + wg) / (ww + wg)) else 0
		if count > 0 then
			local total = count * ww + (count - 1) * wg
			local start = (a0 + a1) / 2 - total / 2
			for k = 0, count - 1 do
				local w0 = start + k * (ww + wg)
				table.insert(windowsAt, { w0, w0 + ww })
			end
		end
	end

	-- Alt bant (pencere altına kadar) ve üst bant, kapı aralıkları hariç
	for _, s in spans do
		local s0, s1 = s[1], s[2]
		piece(tag .. "Low", (s0 + s1) / 2, wb / 2, 0, s1 - s0, wb, T, spec.lowColor or C.wallLow)
		piece(tag .. "High", (s0 + s1) / 2, wt + (H - wt) / 2, 0, s1 - s0, H - wt, T, C.wallHigh)
		-- Pencere kuşağı: pencereler arası ayaklar
		local c = s0
		for _, win in windowsAt do
			if win[1] >= s0 and win[2] <= s1 then
				piece(tag .. "Pier", (c + win[1]) / 2, (wb + wt) / 2, 0, win[1] - c, wt - wb, T, C.wallMid)
				c = win[2]
			end
		end
		piece(tag .. "Pier", (c + s1) / 2, (wb + wt) / 2, 0, s1 - c, wt - wb, T, C.wallMid)
	end

	-- Başlık: alçak bölme duvarlarının tepesinde açık renkli kalın kapak
	if spec.cap then
		piece(tag .. "Cap", len / 2, H + 0.3, 0, len, 0.6, T + 0.6, spec.cap, { collide = true })
	end

	-- Kesiklerin altı ve üstü
	for _, d in cuts do
		piece(tag .. "OverCut", (d.u0 + d.u1) / 2, d.y1 + (H - d.y1) / 2, 0, d.u1 - d.u0, H - d.y1, T, C.wallHigh)
		if d.y0 > 0 then
			piece(tag .. "UnderCut", (d.u0 + d.u1) / 2, d.y0 / 2, 0, d.u1 - d.u0, d.y0, T, C.wallLow)
		end
	end

	-- ── Pencereler ────────────────────────────────────────────────────────
	local FW = 1.3       -- çerçeve genişliği
	local CH = 2.2       -- köşe pahı
	for _, win in windowsAt do
		local w0, w1 = win[1], win[2]
		local wc = (w0 + w1) / 2
		local wh = wt - wb
		piece(tag .. "Glass", wc, (wb + wt) / 2, 0, w1 - w0, wh, 0.4, C.glass,
			{ material = Enum.Material.Glass, transparency = 0.62, collide = true, reflect = 0.08 })
		-- Orta kayıt: camı böl, ölçek versin
		piece(tag .. "Mullion", wc, (wb + wt) / 2, 0, 0.7, wh + 0.2, 0.9, C.frame, { collide = false })
		-- İç ve dış çerçeve
		for _, side in { 1, -1 } do
			local dc = side * (T / 2 + 0.3)
			piece(tag .. "WinFrame", wc, wt + FW / 2, dc, (w1 - w0) + FW * 2, FW, 0.6, C.frame, { collide = false })
			piece(tag .. "WinFrame", wc, wb - FW / 2, dc, (w1 - w0) + FW * 2, FW, 0.6, C.frame, { collide = false })
			piece(tag .. "WinFrame", w0 - FW / 2, (wb + wt) / 2, dc, FW, wh, 0.6, C.frame, { collide = false })
			piece(tag .. "WinFrame", w1 + FW / 2, (wb + wt) / 2, dc, FW, wh, 0.6, C.frame, { collide = false })
		end
		-- Pahlı köşeler: açıklığı sekizgene çeviriyor (yuvarlak pencere hissi)
		for _, cu in { w0, w1 } do
			for _, cy in { wb, wt } do
				K.boxAt(parent, tag .. "WinCorner", frame * CFrame.new(cu, cy, 0) * CFrame.Angles(0, 0, math.rad(45)),
					Vector3.new(CH * 1.414, CH * 1.414, T - 0.12), C.frame, { collide = false })
			end
		end
		-- Pencere altı pervaz (iç)
		piece(tag .. "Sill", wc, wb - FW - 0.25, T / 2 + 0.55, (w1 - w0) + FW * 2 + 0.6, 0.5, 1.1, C.frameDark, { collide = false })
	end

	-- ── İç yüz süslemeleri (kapılar ve köşeler hariç) ─────────────────────
	for _, s in spans do
		local s0 = math.max(s[1], inset0)
		local s1 = math.min(s[2], len - inset1)
		-- kapı kenarında pervaz için pay
		if s[1] > 0 then
			s0 = s[1] + 2.2
		end
		if s[2] < len then
			s1 = s[2] - 2.2
		end
		local w = s1 - s0
		if w <= 1 then
			continue
		end
		local mid = (s0 + s1) / 2
		-- Bölme duvarları iki yüzden de görünüyor: süsleme iki yana
		for _, sd in (if spec.twoSided then { 1, -1 } else { 1 }) do
			piece(tag .. "Kick", mid, 1.3, sd * (T / 2 + 0.25), w, 2.6, 0.5, C.wallKick)
			piece(tag .. "Rail", mid, rail + 0.6, sd * (T / 2 + 0.35), w, 1.2, 0.7, C.wallRail, { collide = false })
			-- Dikey derzler: alt panelde ölçek veren ince çıtalar
			local seams = math.floor(w / 12)
			for k = 1, seams - 1 do
				piece(tag .. "Seam", s0 + k * (w / seams), 2.6 + (rail - 2.6) / 2, sd * (T / 2 + 0.08), 0.45, rail - 2.6, 0.16, C.wallSeam, { collide = false })
			end
		end
		-- Tavana yakın ışık bandı
		if not spec.noCove then
			piece(tag .. "Cove", mid, H - 2.2, T / 2 + 0.5, w - 2, 0.5, 0.5, C.lamp, { emit = "Screen" })
			piece(tag .. "CoveLip", mid, H - 1.6, T / 2 + 0.6, w, 0.4, 1.2, C.wallCap, { collide = false })
		end
		-- Dış cephe kaplaması: istasyonun dışarıdan görünen yüzü
		if spec.exterior then
			piece(tag .. "Belt", mid, rail + 0.6, -(T / 2 + 0.3), w, 1.6, 0.6, spec.exterior, { collide = false })
		end
	end
end

--[[
	Skeld kapısı: kalın açık gri söveler, lento, üstte yeşil durum lambası,
	eşikte uyarı şeridi. Kapı kanatları açık (sövelerin içine çekilmiş).
	Açıklık [u0, u1] × [0, h]; söveler açıklığa 0.3 taşıyor ki duvarın
	uç yüzüyle aynı düzlemde kalmasınlar.
]]
function K.door(parent: Instance, a: Vector2, b: Vector2, inside: number, u0: number, u1: number, h: number, T: number?, floorY: number?)
	local t = T or M.WALL_T
	local dir = b - a
	local u = dir.Unit
	local n = Vector2.new(-u.Y, u.X) * inside
	local frame = CFrame.fromMatrix(Vector3.new(a.X, 0, a.Y), Vector3.new(u.X, 0, u.Y), Vector3.yAxis, -Vector3.new(n.X, 0, n.Y))
	local fy = floorY or M.TILE_TOP
	local J = 2.6
	local D = t + 1.8
	for _, side in { -1, 1 } do
		local uc = if side < 0 then u0 - J / 2 + 0.3 else u1 + J / 2 - 0.3
		K.boxAt(parent, "DoorJamb", frame * CFrame.new(uc, h / 2, 0), Vector3.new(J, h, D), C.frame)
		-- Kanat: sövenin içinde, yarısı görünür
		K.boxAt(parent, "DoorLeaf", frame * CFrame.new(uc + side * 0.2, h / 2 - 0.2, 0), Vector3.new(J - 0.9, h - 0.8, D + 0.3), C.metal, { collide = false })
		-- Kanadın üstündeki sarı-siyah uyarı bandı
		K.boxAt(parent, "DoorBand", frame * CFrame.new(uc + side * 0.2, h * 0.55, 0), Vector3.new(J - 0.85, 1.2, D + 0.36), C.hazard, { collide = false })
	end
	K.boxAt(parent, "DoorLintel", frame * CFrame.new((u0 + u1) / 2, h + 1.1 - 0.3, 0), Vector3.new(u1 - u0 + J * 2 - 0.6, 2.2, D), C.frame)
	-- Durum lambası: iki yüzde
	for _, s in { 1, -1 } do
		local lamp = K.boxAt(parent, "DoorLamp", frame * CFrame.new((u0 + u1) / 2, h + 1.1, -s * (D / 2 + 0.2)), Vector3.new(3.2, 0.9, 0.4), C.green, { emit = "Indicator" })
		lamp.CastShadow = false
	end
	-- Eşik: uyarı şeridi (yere yatık)
	local mid = (u0 + u1) / 2
	local width = u1 - u0
	local count = math.max(2, math.floor(width / 2.4))
	local real = width / count
	for i = 0, count - 1 do
		K.boxAt(parent, "DoorSill", frame * CFrame.new(u0 + (i + 0.5) * real, fy + 0.07 + M.LIFT, 0),
			Vector3.new(real, 0.14, t + 1.2), if i % 2 == 0 then C.hazard else C.hazardDark)
	end
	return mid
end

-- ─── Mürettebat heykeli ─────────────────────────────────────────────────────

--[[
	Among Us fasulyesi: kapsül gövde (silindir + iki küre), elipsoit vizör
	ve üstünde parlak benek, yuvarlatılmış sırt çantası, iki kısa bacak.
	`cf` ayakların tabanı, LookVector vizörün baktığı yön. `s` ölçek:
	1 iken ~3.6 stud boy.

	pose: "stand" | "sit" (oturan: bacaklar öne) | "dead" (yarım gövde +
	kemik — Among Us'ın ceset görseli).
]]
function K.crewmate(parent: Instance, cf: CFrame, color: Color3, s: number, pose: string?): Model
	local model = Instance.new("Model")
	model.Name = "Crewmate"
	model.Parent = parent
	local p = pose or "stand"
	local dark = color:Lerp(Color3.new(0, 0, 0), 0.28)

	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x * s, y * s, z * s)
	end

	local legY = if p == "sit" then 0.55 else 0.5
	local bodyBase = if p == "sit" then 0.55 else 1.0

	if p == "dead" then
		-- Ceset: gövdenin alt yarısı, üstünden kemik çıkıyor
		K.boxAt(model, "Half", at(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(1.4 * s, 2.1 * s, 2.1 * s), color,
			{ shape = Enum.PartType.Cylinder, collide = false })
		K.boxAt(model, "Cut", at(0, 1.42, 0) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(0.12 * s, 1.95 * s, 1.95 * s), rgb(236, 226, 220),
			{ shape = Enum.PartType.Cylinder, collide = false })
		K.boxAt(model, "Bone", at(0, 1.9, 0), Vector3.new(0.34 * s, 1.0 * s, 0.34 * s), rgb(246, 244, 236), { collide = false })
		for _, x in { -0.18, 0.18 } do
			K.boxAt(model, "BoneEnd", at(x, 2.4, 0), Vector3.new(0.4 * s, 0.4 * s, 0.4 * s), rgb(246, 244, 236),
				{ shape = Enum.PartType.Ball, collide = false })
		end
		for i, x in { -0.5, 0.5 } do
			K.boxAt(model, "Leg" .. i, at(x, 0.3, -0.35) , Vector3.new(0.7 * s, 0.6 * s, 1.2 * s), color, { collide = false })
		end
		model.PrimaryPart = model:FindFirstChild("Half") :: BasePart
		return model
	end

	-- Gövde: kapsül
	local body = K.boxAt(model, "Body", at(0, bodyBase + 1.05, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(2.1 * s, 2.2 * s, 2.2 * s), color, { shape = Enum.PartType.Cylinder, collide = false })
	K.boxAt(model, "Head", at(0, bodyBase + 2.1, 0), Vector3.new(2.2 * s, 2.2 * s, 2.2 * s), color,
		{ shape = Enum.PartType.Ball, collide = false })
	K.boxAt(model, "Bottom", at(0, bodyBase, 0), Vector3.new(2.2 * s, 1.2 * s, 2.2 * s), color,
		{ collide = false }).Shape = Enum.PartType.Ball

	-- Vizör: elipsoit + parlak benek
	K.ellipsoid(model, "Visor", at(0.15, bodyBase + 2.0, -0.92), Vector3.new(1.55 * s, 0.95 * s, 0.75 * s), rgb(150, 206, 230), { collide = false, reflect = 0.15 })
	K.ellipsoid(model, "VisorShine", at(0.45, bodyBase + 2.18, -1.2), Vector3.new(0.55 * s, 0.26 * s, 0.2 * s), rgb(236, 250, 255), { collide = false })

	-- Sırt çantası: yuvarlatılmış
	K.boxAt(model, "Pack", at(0, bodyBase + 1.05, 1.15) * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(1.7 * s, 1.1 * s, 1.1 * s), dark, { shape = Enum.PartType.Cylinder, collide = false })

	-- Bacaklar
	for i, x in { -0.52, 0.52 } do
		if p == "sit" then
			K.boxAt(model, "Leg" .. i, at(x, legY, -0.9), Vector3.new(0.8 * s, 0.7 * s, 1.5 * s), color, { collide = false })
		else
			K.boxAt(model, "Leg" .. i, at(x, legY, 0) * CFrame.Angles(0, 0, math.rad(90)), Vector3.new(1.0 * s, 0.85 * s, 0.85 * s), color,
				{ shape = Enum.PartType.Cylinder, collide = false })
		end
	end
	model.PrimaryPart = body
	return model
end

-- ─── Sayaç ──────────────────────────────────────────────────────────────────

function K.count(folder: Instance): number
	local n = 0
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

return K
