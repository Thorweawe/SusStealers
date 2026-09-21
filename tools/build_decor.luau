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

local MARGIN = 34
local halfW = spanX / 2 + halfX + MARGIN     -- istasyon yarı genişliği
local halfD = spanZ / 2 + halfZ + MARGIN     -- istasyon yarı derinliği

local WALL_H = 34          -- çeper duvar yüksekliği
local HULL_DEPTH = 24      -- güverte altı gövde derinliği
local ARCH_CLEAR = 15      -- kemer altı boşluk

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

local HULL = Color3.fromRGB(38, 44, 58)
local HULL_DARK = Color3.fromRGB(24, 29, 39)
local TRIM = Color3.fromRGB(78, 88, 108)

--[[
	Neon malzemesi rengi tam parlaklıkta basıyor; kısmanın tek yolu rengi
	koyulaştırmak. Uzun çizgiler (zemin dikişi, yürüyüş şeridi, kemer) sönük
	tonu kullanıyor, parlak ton sadece küçük vurgularda. Hepsi parlak olunca
	göz dinlenecek yer bulamıyor ve sahne camgöbeğine boğuluyordu.
]]
local NEON = Color3.fromRGB(80, 220, 255)        -- parlak: küçük vurgu
local NEON_DIM = Color3.fromRGB(22, 68, 88)      -- sönük: uzun çizgiler
local NEON_MID = Color3.fromRGB(44, 124, 152)    -- ara ton: çerçeveler

local LAMP = Color3.fromRGB(225, 240, 255)       -- aydınlatma: nötr beyaz
local NEON_WARM = Color3.fromRGB(255, 190, 90)
local HAZARD = Color3.fromRGB(180, 118, 26)      -- sönük kehribar
local GLASS = Color3.fromRGB(150, 210, 255)
local RED = Color3.fromRGB(197, 17, 17)

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
}

local function build(o: Opts): Part
	local p = Instance.new("Part")
	p.Name = o.name or "Deco"
	p.Size = o.size
	p.CFrame = o.cf
	p.Color = o.color
	p.Material = o.material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = o.collide == true
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = o.transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if o.shape then
		p.Shape = o.shape
	end
	p.Parent = o.parent
	return p
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

-- ─── 1. Güverte ─────────────────────────────────────────────────────────────

do
	local f = group("Floor")

	build({
		name = "Deck",
		size = Vector3.new(halfW * 2, 1, halfD * 2),
		cf = at(centerX, -0.5, centerZ),
		color = HULL_DARK,
		material = Enum.Material.Metal,
		collide = true,
		parent = f,
	})

	-- Sütunlar arası enine dikişler (sönük: zeminin her yerinde var)
	for i = 0, COLUMNS do
		build({
			name = "SeamX",
			size = Vector3.new(0.6, 0.12, halfD * 2 - 6),
			cf = at((i - 0.5) * PLOT_SPACING, 0.06 + LIFT, centerZ),
			color = NEON_DIM,
			material = Enum.Material.Neon,
			parent = f,
		})
	end

	-- Satırlar arası boyuna dikişler
	for i = 0, ROWS do
		build({
			name = "SeamZ",
			size = Vector3.new(halfW * 2 - 6, 0.12, 0.6),
			cf = at(centerX, 0.06 + LIFT, (i - 0.5) * (if ROWS > 1 then ROW_SPACING else halfD * 2)),
			color = NEON_DIM,
			material = Enum.Material.Neon,
			parent = f,
		})
	end

	--[[
		İki sıra üssün arasındaki ana koridor. Tek parlak zemin çizgisi bu;
		oyuncunun gözü doğal olarak onu takip ediyor ve haritanın omurgasını
		anlıyor. Diğer bütün dikişler sönük tam da bu ayrım görünsün diye.
	]]
	if ROWS > 1 then
		build({
			name = "MainCorridor",
			size = Vector3.new(halfW * 2 - 20, 0.14, 2),
			cf = at(centerX, 0.07 + LIFT, centerZ),
			color = NEON,
			material = Enum.Material.Neon,
			parent = f,
		})
	end
end

-- ─── 2. Çeper: dört tarafta pencereli duvar ─────────────────────────────────

do
	local f = group("Hull")
	local SEG, WINDOW = 26, 13

	--[[ Bir kenar boyunca panel-pencere-panel dizisi kurar.
	     axis "x": duvar x boyunca uzanır (ön/arka). "z": z boyunca (yanlar). ]]
	local function wall(axis: string, fixed: number, from: number, to: number, facing: number)
		local function place(name: string, along: number, width: number, height: number, y: number, thick: number, color: Color3, material: Enum.Material, collide: boolean, trans: number?)
			local size = if axis == "x"
				then Vector3.new(width, height, thick)
				else Vector3.new(thick, height, width)
			local cf = if axis == "x"
				then at(along, y, fixed)
				else at(fixed, y, along)
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

			local g = math.min(WINDOW, to - cursor)
			-- Pencere camı
			place("Glass", cursor + g / 2, g, WALL_H - 13, 3.5 + (WALL_H - 3.5) / 2, 0.7, GLASS, Enum.Material.Glass, false, 0.75)
			-- Üst kapak ve alt denizlik
			place("GlassTop", cursor + g / 2, g, 4, WALL_H - 2, 2.4, HULL, Enum.Material.Metal, true)
			place("Sill", cursor + g / 2, g, 0.5, 3.5 + 3, 2.8, NEON_MID, Enum.Material.Neon, false)
			cursor += g
		end

		-- Üst korniş
		place("Cornice", mid, length, 1.6, WALL_H + 0.8, 4, TRIM, Enum.Material.Metal, false)
	end

	local x0, x1 = centerX - halfW, centerX + halfW
	local z0, z1 = centerZ - halfD, centerZ + halfD

	wall("x", z0, x0, x1, -1)
	wall("x", z1, x0, x1, 1)
	wall("z", x0, z0, z1, -1)
	wall("z", x1, z0, z1, 1)

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
				material = Enum.Material.Neon,
				shape = Enum.PartType.Ball,
				parent = f,
			})
			glow(lamp, NEON_WARM, 18, 1.2)
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
				color = NEON_MID, material = Enum.Material.Neon, parent = pf,
			})
			build({
				name = "FrameZ",
				size = Vector3.new(PLOT_SIZE.X, FRAME_H, 0.8),
				cf = at(ox, frameY, oz + s * halfZ),
				color = NEON_MID, material = Enum.Material.Neon, parent = pf,
			})
		end

		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local px, pz = ox + sx * halfX, oz + sz * halfZ

				build({ name = "Pillar", size = Vector3.new(PILLAR, PILLAR_H, PILLAR),
					cf = at(px, topY + PILLAR_H / 2, pz), color = HULL,
					material = Enum.Material.Metal, collide = true, parent = pf })
				build({ name = "PillarBand", size = Vector3.new(PILLAR + 0.5, 0.45, PILLAR + 0.5),
					cf = at(px, topY + PILLAR_H * 0.62, pz), color = NEON,
					material = Enum.Material.Neon, parent = pf })
				build({ name = "PillarCap", size = Vector3.new(PILLAR + 1, 0.7, PILLAR + 1),
					cf = at(px, topY + PILLAR_H + 0.35, pz), color = TRIM,
					material = Enum.Material.Metal, parent = pf })

				-- Sütun tepesindeki ışık: 8 üste 4'er tane, hepsi camgöbeği
				-- olunca sahneyi maviye boğuyordu. Nötr beyaz aydınlatıyor,
				-- renk vurgusunu sütundaki bant yapıyor.
				local lamp = build({ name = "CapLamp", size = Vector3.new(PILLAR * 0.6, 0.5, PILLAR * 0.6),
					cf = at(px, topY + PILLAR_H + 0.9, pz), color = LAMP,
					material = Enum.Material.Neon, parent = pf })
				glow(lamp, LAMP, 24, 0.9)
			end
		end

		-- Kaide halkaları
		local perRow = math.ceil(PODIUMS / 2)
		for slot = 1, PODIUMS do
			local front = slot <= perRow
			local col = if front then slot - 1 else slot - perRow - 1
			build({
				name = "PodiumRing",
				size = Vector3.new(5.6, 0.1, 5.6),
				cf = at(ox + (col - (perRow - 1) / 2) * PODIUM_GAP, topY + 0.05 + LIFT, oz + (if front then -8 else 8)),
				color = NEON_DIM, material = Enum.Material.Neon, transparency = 0.3, parent = pf,
			})
		end

		-- Konveyör şeridi ve dağıtıcı
		local convZ = oz + halfZ - 5
		for _, e in { -1, 1 } do
			build({ name = "HazardStrip", size = Vector3.new(PLOT_SIZE.X - 8, 0.12, 0.7),
				cf = at(ox, topY + 0.06 + LIFT, convZ + e * 3.2), color = HAZARD,
				material = Enum.Material.Neon, parent = pf })
		end

		local dx = ox - (PLOT_SIZE.X - 8) / 2
		for _, e in { -1, 1 } do
			build({ name = "DispenserLeg", size = Vector3.new(1.2, 7, 1.2),
				cf = at(dx + e * 3.4, topY + 3.5, convZ), color = TRIM,
				material = Enum.Material.Metal, parent = pf })
		end
		build({ name = "DispenserHead", size = Vector3.new(9, 1.6, 6),
			cf = at(dx, topY + 7.5, convZ), color = HULL,
			material = Enum.Material.Metal, parent = pf })
		local dg = build({ name = "DispenserGlow", size = Vector3.new(8, 0.25, 5),
			cf = at(dx, topY + 6.6, convZ), color = NEON_WARM,
			material = Enum.Material.Neon, parent = pf })
		glow(dg, NEON_WARM, 16, 1)

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
			build({ name = "ArchGlow", size = Vector3.new(0.5, 0.2, (halfZ + 3) * 2 - 2),
				cf = at(ax, ARCH_CLEAR - 0.1, oz), color = NEON_DIM,
				material = Enum.Material.Neon, parent = pf })
		end
	end
end

-- ─── 4. Havalandırma kapakları ──────────────────────────────────────────────

do
	local f = group("Vents")

	local function vent(x: number, z: number)
		local cf = at(x, 0.06 + LIFT, z)
		build({ name = "VentFrame", size = Vector3.new(6.4, 0.2, 4.4), cf = cf,
			color = TRIM, material = Enum.Material.Metal, parent = f })
		for i = -1, 1 do
			build({ name = "VentSlat", size = Vector3.new(5.4, 0.26, 0.7),
				cf = cf * CFrame.new(0, 0.05, i * 1.2), color = HULL_DARK,
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
	local z = centerZ + halfD - 18

	build({ name = "Base", size = Vector3.new(12, 1.2, 12), cf = at(centerX, 0.6, z),
		color = TRIM, material = Enum.Material.Metal, collide = true, parent = f })
	build({ name = "Column", size = Vector3.new(6.5, 4, 6.5), cf = at(centerX, 3.2, z),
		color = HULL, material = Enum.Material.Metal, collide = true, parent = f })
	build({ name = "Ring", size = Vector3.new(9.5, 0.3, 9.5), cf = at(centerX, 5.3, z),
		color = NEON, material = Enum.Material.Neon, parent = f })
	build({ name = "Top", size = Vector3.new(8.5, 1, 8.5), cf = at(centerX, 5.9, z),
		color = HULL, material = Enum.Material.Metal, collide = true, parent = f })

	local dome = build({ name = "Button", size = Vector3.new(4.8, 4.8, 4.8),
		cf = at(centerX, 6.7, z), color = RED, material = Enum.Material.Neon,
		shape = Enum.PartType.Ball, parent = f })
	glow(dome, RED, 34, 2.4)
end

-- ─── 6. Çatı kirişleri ──────────────────────────────────────────────────────
-- Üstü tamamen kapatmıyoruz; kafes kirişler kapalı mekân hissi verirken
-- yıldızlar aradan görünmeye devam ediyor.

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

	-- Kirişlere asılı aydınlatma
	for i = 1, COLUMNS do
		for r = 0, ROWS - 1 do
			-- Aydınlatma nötr beyaz: camgöbeği olunca "lamba" değil
			-- "dekor şeridi" gibi okunuyordu ve sahneyi maviye boğuyordu.
			local lamp = build({
				name = "RoofLamp",
				size = Vector3.new(PLOT_SIZE.X * 0.5, 0.4, 2),
				cf = at((i - 1) * PLOT_SPACING, Y - 3.2, r * ROW_SPACING),
				color = LAMP, material = Enum.Material.Neon, parent = f,
			})
			glow(lamp, LAMP, 42, 1.3)
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
			color = NEON, material = Enum.Material.Neon, parent = f })
		screen.Transparency = 0.15
		glow(screen, NEON, 14, 0.8)

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
		local z = o.Z + side * (halfZ + 9)

		build({ name = "BayPad", size = Vector3.new(14, 0.14, 7),
			cf = at(o.X, 0.07 + LIFT, z), color = NEON_DIM,
			material = Enum.Material.Neon, transparency = 0.4, parent = f })

		local post = build({ name = "BayPost", size = Vector3.new(1, 1, 1),
			cf = at(o.X, 6, z), color = HULL,
			material = Enum.Material.Metal, transparency = 1, parent = f })

		local gui = Instance.new("BillboardGui")
		gui.Name = "BayLabel"
		gui.Size = UDim2.fromScale(11, 4)
		gui.AlwaysOnTop = false
		gui.MaxDistance = 320
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
		material = Enum.Material.Neon, parent = f })

	-- Uyarı lambaları: çeperin dört köşesinde
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local lamp = build({
				name = "WarnLight",
				size = Vector3.new(2.2, 2.2, 2.2),
				cf = at(centerX + sx * (halfW - 3), WALL_H + 2.5, centerZ + sz * (halfD - 3)),
				color = HAZARD, material = Enum.Material.Neon,
				shape = Enum.PartType.Ball, parent = f,
			})
			lamp:SetAttribute("PulsePeriod", 1.6)
			glow(lamp, HAZARD, 22, 1.6)
		end
	end
end

-- ─── 10. Baseplate'i gövdenin altına gizle ──────────────────────────────────
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
