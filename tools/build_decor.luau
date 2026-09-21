--!strict
--[[
	Harita dekorunu tamamen koddan kurar. Studio'da MCP ile:

	    local src = game:GetService("HttpService"):GetAsync(
	        "http://127.0.0.1:8788/tools/build_decor.luau")
	    loadstring(src)()

	Tasarım: Among Us / Skeld estetiği — sade geometri, temiz paneller,
	camgöbeği neon, uzaya bakan pencereler. Karakterler koddan üretilmiş
	basit silindirler olduğu için dekor da aynı sadelikte; gerçekçi mesh
	koyarsak karakterler oyuncak gibi kalıyor.

	Her şey workspace.Decor altına gider. PlotService.Start() sadece
	workspace.Plots'u siliyor, dekor sunucu yeniden başlayınca kalır.

	Tekrar çalıştırılabilir: eski Decor'u silip sıfırdan kurar.

	OYUNU ENGELLEMEME KURALI: üsler arası geçiş açık kalmalı. Çalmanın
	bütün riski rakip üsse koşmakta. Kapalı duvar, alçak kemer, yola
	taşan sütun konmaz. Duvarlar sadece dış çeperde (ön ve arka).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Config bozuksa da çalışsın diye değerler yedekli okunuyor
local PLOT_COUNT, PLOT_SPACING, PLOT_SIZE, PODIUMS, PODIUM_GAP = 8, 76, Vector3.new(60, 2, 44), 8, 6.5
do
	local ok, cfg = pcall(function()
		return require(ReplicatedStorage.Shared.Config)
	end)
	if ok and typeof(cfg) == "table" then
		PLOT_COUNT = cfg.PlotCount or PLOT_COUNT
		PLOT_SPACING = cfg.PlotSpacing or PLOT_SPACING
		PLOT_SIZE = cfg.PlotSize or PLOT_SIZE
		PODIUMS = cfg.PodiumsPerPlot or PODIUMS
		PODIUM_GAP = cfg.PodiumSpacing or PODIUM_GAP
	else
		warn("build_decor: Config okunamadi, varsayilan olculer kullaniliyor")
	end
end

-- ─── Palet ──────────────────────────────────────────────────────────────────

local HULL = Color3.fromRGB(38, 44, 58)        -- gövde paneli
local HULL_DARK = Color3.fromRGB(26, 31, 42)   -- derin gölge
local TRIM = Color3.fromRGB(72, 82, 100)       -- kenar metali
local NEON = Color3.fromRGB(80, 220, 255)      -- ana neon
local NEON_WARM = Color3.fromRGB(255, 190, 90) -- uyarı neonu
local HAZARD = Color3.fromRGB(255, 176, 40)    -- tehlike şeridi
local GLASS = Color3.fromRGB(150, 210, 255)
local RED = Color3.fromRGB(197, 17, 17)        -- acil durum düğmesi

-- ─── Ölçüler ────────────────────────────────────────────────────────────────

local halfX = PLOT_SIZE.X / 2
local halfZ = PLOT_SIZE.Z / 2
local topY = PLOT_SIZE.Y / 2          -- üs tabanının üst yüzeyi (y=1)
local span = (PLOT_COUNT - 1) * PLOT_SPACING
local centerX = span / 2
local stationHalf = span / 2 + halfX + 26   -- istasyonun x yarı genişliği

-- ─── Kurulum ────────────────────────────────────────────────────────────────

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

type PartOpts = {
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

local function build(opts: PartOpts): Part
	local p = Instance.new("Part")
	p.Name = opts.name or "Deco"
	p.Size = opts.size
	p.CFrame = opts.cf
	p.Color = opts.color
	p.Material = opts.material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = opts.collide == true
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = opts.transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts.shape then
		p.Shape = opts.shape
	end
	p.Parent = opts.parent
	return p
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- ─── 1. Zemin: panel dikişleri ve yürüyüş şeridi ────────────────────────────
-- Büyük döşeme parçaları yerine ince neon dikişler: aynı görüntü, 20 kat az parça.

do
	local f = group("Floor")

	build({
		name = "Deck",
		size = Vector3.new(stationHalf * 2, 1, halfZ * 2 + 52),
		cf = at(centerX, -0.5, 0),
		color = HULL_DARK,
		material = Enum.Material.Metal,
		collide = true,
		parent = f,
	})

	-- Üsler arası her boşlukta enine dikiş
	for i = 0, PLOT_COUNT do
		local x = (i - 0.5) * PLOT_SPACING
		build({
			name = "Seam",
			size = Vector3.new(0.6, 0.12, halfZ * 2 + 50),
			cf = at(x, 0.06, 0),
			color = NEON,
			material = Enum.Material.Neon,
			parent = f,
		})
	end

	-- Üslerin önünden geçen yürüyüş şeridi: oyuncuya yön verir
	for _, z in { -halfZ - 6, halfZ + 6 } do
		build({
			name = "Walkway",
			size = Vector3.new(stationHalf * 2 - 8, 0.12, 1.2),
			cf = at(centerX, 0.06, z),
			color = NEON,
			material = Enum.Material.Neon,
			parent = f,
		})
	end
end

-- ─── 2. Dış çeper: pencereli duvar ──────────────────────────────────────────
-- Sadece ön ve arkada. Yanlar açık, oyuncu x ekseninde serbest dolaşır.

do
	local f = group("Hull")
	local WALL_H = 26
	local SEG = 26          -- duvar parçası genişliği
	local WINDOW = 12       -- aradaki pencere boşluğu

	for _, z in { -halfZ - 30, halfZ + 30 } do
		local facing = if z < 0 then -1 else 1

		-- Alt bant: kesintisiz, oyuncu dışarı düşmesin
		build({
			name = "Kick",
			size = Vector3.new(stationHalf * 2, 3, 2),
			cf = at(centerX, 1.5, z),
			color = TRIM,
			material = Enum.Material.Metal,
			collide = true,
			parent = f,
		})

		local x = -stationHalf
		while x < stationHalf do
			local width = math.min(SEG, stationHalf - x)
			build({
				name = "Panel",
				size = Vector3.new(width, WALL_H - 3, 2),
				cf = at(x + width / 2, 3 + (WALL_H - 3) / 2, z),
				color = HULL,
				material = Enum.Material.Metal,
				collide = true,
				parent = f,
			})
			-- Panel kenarına dikey neon
			build({
				name = "PanelEdge",
				size = Vector3.new(0.3, WALL_H - 5, 0.3),
				cf = at(x + width, 3 + (WALL_H - 3) / 2, z - facing * 1.1),
				color = NEON,
				material = Enum.Material.Neon,
				parent = f,
			})

			x += width
			if x >= stationHalf then
				break
			end

			-- Pencere: uzaya bakan cam + çerçeve
			local w = math.min(WINDOW, stationHalf - x)
			build({
				name = "Glass",
				size = Vector3.new(w, WALL_H - 9, 0.6),
				cf = at(x + w / 2, 3 + (WALL_H - 3) / 2, z),
				color = GLASS,
				material = Enum.Material.Glass,
				transparency = 0.72,
				parent = f,
			})
			build({
				name = "GlassTop",
				size = Vector3.new(w, 3, 2),
				cf = at(x + w / 2, WALL_H - 1.5, z),
				color = HULL,
				material = Enum.Material.Metal,
				collide = true,
				parent = f,
			})
			build({
				name = "GlassSill",
				size = Vector3.new(w, 0.4, 2.2),
				cf = at(x + w / 2, 3 + WALL_H - 9, z),
				color = NEON,
				material = Enum.Material.Neon,
				parent = f,
			})
			x += w
		end

		-- Üst korniş
		build({
			name = "Cornice",
			size = Vector3.new(stationHalf * 2, 1.4, 3.4),
			cf = at(centerX, WALL_H + 0.7, z),
			color = TRIM,
			material = Enum.Material.Metal,
			parent = f,
		})
	end

	--[[
		Uç duvarlar. İstasyon boşlukta yüzdüğü için dört tarafı da kapalı
		olmalı, yoksa oyuncu kenardan düşüp boşluğa gider. Üsler x ekseninde
		sıralı ama uçlarda geçilecek bir şey yok, kapatmak oyunu engellemiyor.
	]]
	local depth = halfZ * 2 + 62
	for _, side in { -1, 1 } do
		local x = centerX + side * stationHalf

		build({
			name = "EndWall",
			size = Vector3.new(2, WALL_H, depth),
			cf = at(x, WALL_H / 2, 0),
			color = HULL,
			material = Enum.Material.Metal,
			collide = true,
			parent = f,
		})
		build({
			name = "EndGlow",
			size = Vector3.new(0.4, 0.4, depth - 4),
			cf = at(x - side * 1.1, WALL_H - 3, 0),
			color = NEON,
			material = Enum.Material.Neon,
			parent = f,
		})
		build({
			name = "EndCornice",
			size = Vector3.new(3.4, 1.4, depth),
			cf = at(x, WALL_H + 0.7, 0),
			color = TRIM,
			material = Enum.Material.Metal,
			parent = f,
		})
	end

	--[[
		Güverte altı: istasyonun kalınlığı görünsün. Yandan bakınca havada
		yüzen ince bir levha değil, gövdesi olan bir yapı gibi dursun.
	]]
	build({
		name = "Underside",
		size = Vector3.new(stationHalf * 2 - 6, 7, depth - 8),
		cf = at(centerX, -4.2, 0),
		color = HULL_DARK,
		material = Enum.Material.Metal,
		parent = f,
	})
	build({
		name = "Keel",
		size = Vector3.new(stationHalf * 2 - 24, 3, depth - 26),
		cf = at(centerX, -9, 0),
		color = TRIM,
		material = Enum.Material.Metal,
		parent = f,
	})
	-- Alt kenar boyunca konum ışıkları
	for i = 0, PLOT_COUNT do
		local x = (i - 0.5) * PLOT_SPACING
		for _, side in { -1, 1 } do
			build({
				name = "MarkerLight",
				size = Vector3.new(1.2, 1.2, 1.2),
				cf = at(x, -7.5, side * (depth / 2 - 5)),
				color = NEON_WARM,
				material = Enum.Material.Neon,
				shape = Enum.PartType.Ball,
				parent = f,
			})
		end
	end
end

-- ─── 3. Üs başına: çerçeve, sütun, kemer, kaide halkaları ───────────────────

do
	local f = group("Plots")
	local FRAME_H = 0.25
	local PILLAR = 2.2
	local PILLAR_H = 13
	local ARCH_CLEAR = 15    -- kemer altı boşluk: zıplayan oyuncu takılmasın

	for index = 1, PLOT_COUNT do
		local ox = (index - 1) * PLOT_SPACING
		local pf = group(string.format("Plot%d", index), f)

		-- Taban altlığı: üssü zeminden ayırır, kalınlık hissi verir
		build({
			name = "Plinth",
			size = Vector3.new(PLOT_SIZE.X + 5, 1.4, PLOT_SIZE.Z + 5),
			cf = at(ox, -0.7, 0),
			color = TRIM,
			material = Enum.Material.Metal,
			collide = true,
			parent = pf,
		})

		-- Neon çerçeve (dört kenar, çarpışmasız)
		local frameY = topY + FRAME_H / 2
		for _, side in { -1, 1 } do
			build({
				name = "FrameX",
				size = Vector3.new(0.8, FRAME_H, PLOT_SIZE.Z),
				cf = at(ox + side * halfX, frameY, 0),
				color = NEON,
				material = Enum.Material.Neon,
				parent = pf,
			})
			build({
				name = "FrameZ",
				size = Vector3.new(PLOT_SIZE.X, FRAME_H, 0.8),
				cf = at(ox, frameY, side * halfZ),
				color = NEON,
				material = Enum.Material.Neon,
				parent = pf,
			})
		end

		-- Köşe sütunları + panel bandı + tepe ışığı
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local px, pz = ox + sx * halfX, sz * halfZ

				build({
					name = "Pillar",
					size = Vector3.new(PILLAR, PILLAR_H, PILLAR),
					cf = at(px, topY + PILLAR_H / 2, pz),
					color = HULL,
					material = Enum.Material.Metal,
					collide = true,
					parent = pf,
				})
				build({
					name = "PillarBand",
					size = Vector3.new(PILLAR + 0.5, 0.45, PILLAR + 0.5),
					cf = at(px, topY + PILLAR_H * 0.62, pz),
					color = NEON,
					material = Enum.Material.Neon,
					parent = pf,
				})
				build({
					name = "PillarCap",
					size = Vector3.new(PILLAR + 0.9, 0.7, PILLAR + 0.9),
					cf = at(px, topY + PILLAR_H + 0.35, pz),
					color = TRIM,
					material = Enum.Material.Metal,
					parent = pf,
				})

				local lamp = build({
					name = "CapLamp",
					size = Vector3.new(PILLAR * 0.6, 0.5, PILLAR * 0.6),
					cf = at(px, topY + PILLAR_H + 0.9, pz),
					color = NEON,
					material = Enum.Material.Neon,
					parent = pf,
				})
				local light = Instance.new("PointLight")
				light.Color = NEON
				light.Range = 26
				light.Brightness = 1.4
				light.Parent = lamp
			end
		end

		-- Kaide halkaları: her kaidenin altına parlayan disk
		local perRow = math.ceil(PODIUMS / 2)
		for slot = 1, PODIUMS do
			local front = slot <= perRow
			local col = if front then slot - 1 else slot - perRow - 1
			local px = ox + (col - (perRow - 1) / 2) * PODIUM_GAP
			local pz = if front then -8 else 8

			build({
				name = "PodiumRing",
				size = Vector3.new(5.6, 0.1, 5.6),
				cf = at(px, topY + 0.05, pz),
				color = NEON,
				material = Enum.Material.Neon,
				transparency = 0.35,
				parent = pf,
			})
		end

		-- Konveyör tehlike şeridi (konveyör z = halfZ - 5)
		local convZ = halfZ - 5
		for _, edge in { -1, 1 } do
			build({
				name = "HazardStrip",
				size = Vector3.new(PLOT_SIZE.X - 8, 0.12, 0.7),
				cf = at(ox, topY + 0.06, convZ + edge * 3.2),
				color = HAZARD,
				material = Enum.Material.Neon,
				parent = pf,
			})
		end

		-- Konveyörün başında dağıtıcı kemer: karakterler oradan çıkıyor
		local dispX = ox - (PLOT_SIZE.X - 8) / 2
		build({
			name = "DispenserLeg",
			size = Vector3.new(1.2, 7, 1.2),
			cf = at(dispX - 3.4, topY + 3.5, convZ),
			color = TRIM,
			material = Enum.Material.Metal,
			parent = pf,
		})
		build({
			name = "DispenserLeg",
			size = Vector3.new(1.2, 7, 1.2),
			cf = at(dispX + 3.4, topY + 3.5, convZ),
			color = TRIM,
			material = Enum.Material.Metal,
			parent = pf,
		})
		build({
			name = "DispenserHead",
			size = Vector3.new(9, 1.6, 6),
			cf = at(dispX, topY + 7.5, convZ),
			color = HULL,
			material = Enum.Material.Metal,
			parent = pf,
		})
		build({
			name = "DispenserGlow",
			size = Vector3.new(8, 0.25, 5),
			cf = at(dispX, topY + 6.6, convZ),
			color = NEON_WARM,
			material = Enum.Material.Neon,
			parent = pf,
		})

		-- Üsler arası kemer (son üsten sonra yok)
		if index < PLOT_COUNT then
			local ax = ox + PLOT_SPACING / 2
			for _, sz in { -1, 1 } do
				build({
					name = "ArchLeg",
					size = Vector3.new(1.6, ARCH_CLEAR, 1.6),
					cf = at(ax, ARCH_CLEAR / 2, sz * (halfZ + 3)),
					color = HULL,
					material = Enum.Material.Metal,
					collide = true,
					parent = pf,
				})
			end
			build({
				name = "ArchBeam",
				size = Vector3.new(2.2, 1.6, (halfZ + 3) * 2),
				cf = at(ax, ARCH_CLEAR + 0.8, 0),
				color = HULL,
				material = Enum.Material.Metal,
				parent = pf,
			})
			build({
				name = "ArchGlow",
				size = Vector3.new(0.5, 0.2, (halfZ + 3) * 2 - 2),
				cf = at(ax, ARCH_CLEAR - 0.1, 0),
				color = NEON,
				material = Enum.Material.Neon,
				parent = pf,
			})
		end
	end
end

-- ─── 4. Havalandırma kapakları (Among Us imzası) ────────────────────────────

do
	local f = group("Vents")

	local function vent(x: number, z: number, yaw: number)
		local cf = CFrame.new(x, 0.06, z) * CFrame.Angles(0, math.rad(yaw), 0)

		build({
			name = "VentFrame",
			size = Vector3.new(6.4, 0.2, 4.4),
			cf = cf,
			color = TRIM,
			material = Enum.Material.Metal,
			parent = f,
		})
		for i = -1, 1 do
			build({
				name = "VentSlat",
				size = Vector3.new(5.4, 0.26, 0.7),
				cf = cf * CFrame.new(0, 0.05, i * 1.2),
				color = HULL_DARK,
				material = Enum.Material.Metal,
				parent = f,
			})
		end
	end

	-- Üsler arası boşluklarda, yürüyüş şeridinin üstünde
	for i = 1, PLOT_COUNT - 1 do
		local x = (i - 0.5) * PLOT_SPACING
		vent(x, -halfZ - 6, 0)
		vent(x, halfZ + 6, 0)
	end
end

-- ─── 5. Acil toplantı düğmesi (merkez parça) ────────────────────────────────

do
	local f = group("EmergencyButton")
	local z = halfZ + 18

	build({
		name = "Base",
		size = Vector3.new(11, 1.2, 11),
		cf = at(centerX, 0.6, z),
		color = TRIM,
		material = Enum.Material.Metal,
		collide = true,
		parent = f,
	})
	build({
		name = "Column",
		size = Vector3.new(6, 4, 6),
		cf = at(centerX, 3.2, z),
		color = HULL,
		material = Enum.Material.Metal,
		collide = true,
		parent = f,
	})
	build({
		name = "Ring",
		size = Vector3.new(9, 0.3, 9),
		cf = at(centerX, 5.3, z),
		color = NEON,
		material = Enum.Material.Neon,
		parent = f,
	})
	build({
		name = "Top",
		size = Vector3.new(8, 1, 8),
		cf = at(centerX, 5.9, z),
		color = HULL,
		material = Enum.Material.Metal,
		collide = true,
		parent = f,
	})

	local dome = build({
		name = "Button",
		size = Vector3.new(4.6, 4.6, 4.6),
		cf = at(centerX, 6.6, z),
		color = RED,
		material = Enum.Material.Neon,
		shape = Enum.PartType.Ball,
		parent = f,
	})
	local glow = Instance.new("PointLight")
	glow.Color = RED
	glow.Range = 30
	glow.Brightness = 2.2
	glow.Parent = dome
end

-- ─── Baseplate: istasyonun altına gizle ─────────────────────────────────────
--[[
	Varsayılan Baseplate 2048x2048 ve Slate malzemesi koyu rengi yıkıyor;
	uzaktan bakınca devasa açık gri bir düzlem olarak her şeyi bastırıyordu.
	İstasyon uzayda yüzüyor, altında sonsuz zemin olmamalı.

	Tamamen silmek yerine istasyonun altına, görünmeyecek şekilde küçültüyoruz:
	bir şey ters giderse (oyuncu bir delikten düşerse) yakalayacak bir taban
	kalsın, ama kamerada görünmesin.
]]
do
	local bp = workspace:FindFirstChild("Baseplate")
	if bp and bp:IsA("BasePart") then
		bp.Size = Vector3.new(stationHalf * 2 - 10, 4, halfZ * 2 + 50)
		bp.CFrame = at(centerX, -14, 0)
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

print(string.format("Decor kuruldu: %d us, %d parca", PLOT_COUNT, parts))
print(string.format("Istasyon: x %.0f..%.0f, z %.0f..%.0f",
	centerX - stationHalf, centerX + stationHalf, -halfZ - 32, halfZ + 32))
