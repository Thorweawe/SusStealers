--!strict
--[[
	Admin masası (Among Us'taki gibi): doğu tünelinin altındaki ADMIN
	odasında, masanın ekranında istasyonun haritası ve her odada / üste kaç
	kişi olduğu (nokta olarak). Masanın gövdesi haritada (tools/map/admin.luau,
	"AdminScreen"); harita ve noktalar burada, sunucuda çiziliyor —
	SurfaceGui dünyada olduğu için herkese aynı görünüyor. Masadaki prompt
	aynı haritayı istemcide ekranın ortasında büyük açıyor (AdminView).
	Yeraltı odaları (Security, Admin) ayrı bölge.

	  - Nokta = oyuncu, TAM YERİ değil odası: Among Us'taki gibi sayı
	    veriyor, kimin nerede olduğunu değil.
	  - Başkasının üssünde biri varsa o üs kırmızı yanıyor ("davetsiz
	    misafir"): savunan masaya bakıp üssüne koşabilsin.
	  - Gezen impostor (RogueService) kırmızı nokta.
	  - Tünel (zeminin altı) ayrı bölge: içindekiler tünel çizgisinde.

	Bölgeler çalışma anında haritadan ölçülüyor (Decor klasörlerinin
	sınırları, Plots'taki Base parçaları): harita değişirse burası da
	kendiliğinden uyuyor.
]]

local Players = game:GetService("Players")

local PlotService = require(script.Parent.PlotService)
local RogueService = require(script.Parent.RogueService)

local AdminMapService = {}

local UPDATE_EVERY = 1
local PIXELS_PER_STUD = 40
local UNDERGROUND_Y = -2

type Rect = { number } -- {x0, z0, x1, z1}

export type Zone = {
	name: string,
	label: string,
	kind: string,       -- "plot" | "room" | "hall" | "tunnel"
	rect: Rect,
	plot: Model?,
	frame: Frame?,
	title: TextLabel?,
	dots: Frame?,
}

local zones: { Zone } = {}
local bounds: Rect = { 0, 0, 1, 1 }
local mapFrame: Frame? = nil

-- ─── Ölçüm ──────────────────────────────────────────────────────────────────

--[[ Bir örneğin (ve altındakilerin) x-z sınırları. Dönük parçalar için yarı boyut izdüşümle. ]]
local function extents(inst: Instance): Rect?
	local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
	local any = false
	local function add(p: BasePart)
		local cf, s = p.CFrame, p.Size
		local hx = math.abs(cf.RightVector.X) * s.X / 2 + math.abs(cf.UpVector.X) * s.Y / 2 + math.abs(cf.LookVector.X) * s.Z / 2
		local hz = math.abs(cf.RightVector.Z) * s.X / 2 + math.abs(cf.UpVector.Z) * s.Y / 2 + math.abs(cf.LookVector.Z) * s.Z / 2
		x0 = math.min(x0, p.Position.X - hx)
		x1 = math.max(x1, p.Position.X + hx)
		z0 = math.min(z0, p.Position.Z - hz)
		z1 = math.max(z1, p.Position.Z + hz)
		any = true
	end
	if inst:IsA("BasePart") then
		add(inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			add(d)
		end
	end
	return if any then { x0, z0, x1, z1 } else nil
end

local function inside(r: Rect, x: number, z: number): boolean
	return x >= r[1] and x <= r[3] and z >= r[2] and z <= r[4]
end

--[[ Haritadan bölgeleri çıkarır. Sıra önemli: sınıflandırmada ilk eşleşen kazanıyor. ]]
local function collectZones(): { Zone }
	local out: { Zone } = {}
	local decor = workspace:FindFirstChild("Decor")
	if not decor then
		return out
	end

	-- Yeraltı odaları (Security, Admin) tünelden ÖNCE: tünelin içinden geçtiği yer oda sayılsın
	local underRooms = decor:FindFirstChild("UnderRooms")
	if underRooms then
		for _, r in underRooms:GetChildren() do
			local rect = extents(r)
			if rect then
				table.insert(out, { name = r.Name, label = string.upper(r.Name), kind = "underroom", rect = rect })
			end
		end
	end

	local tunnels = decor:FindFirstChild("Tunnels")
	if tunnels then
		for _, t in tunnels:GetChildren() do
			local r = extents(t)
			if r then
				table.insert(out, { name = t.Name, label = "", kind = "tunnel", rect = r })
			end
		end
	end

	for _, plot in PlotService.GetAllPlots() do
		local base = plot:FindFirstChild("Base")
		local r = base and extents(base)
		if r then
			table.insert(out, { name = plot.Name, label = "", kind = "plot", rect = r, plot = plot })
		end
	end

	local rooms = {
		{ path = { "Landmarks", "Reactor" }, label = "REACTOR" },
		{ path = { "Landmarks", "Navigation" }, label = "NAV" },
		{ path = { "Annex", "Storage" }, label = "STORAGE" },
		{ path = { "Annex", "Laboratory" }, label = "LAB" },
		{ path = { "Wings", "MedBay" }, label = "MEDBAY" },
		{ path = { "Wings", "Weapons" }, label = "WEAPONS" },
		{ path = { "Lobby" }, label = "CAFETERIA" },
		{ path = { "Bridge" }, label = "" },
	}
	for _, room in rooms do
		local inst: Instance? = decor
		for _, name in room.path do
			inst = inst and inst:FindFirstChild(name)
		end
		local r = inst and extents(inst)
		if r then
			table.insert(out, { name = room.path[#room.path], label = room.label, kind = "room", rect = r })
		end
	end

	-- İstasyon koridoru en sonda: üslerin ve odaların dışında kalan her şey
	local floor = decor:FindFirstChild("Floor")
	local r = floor and extents(floor)
	if r then
		table.insert(out, { name = "Station", label = "", kind = "hall", rect = r })
	end
	return out
end

--[[ Dünya konumunun bölgesi (yoksa nil). Testler ve nokta sayımı buna bakıyor. ]]
function AdminMapService.Classify(pos: Vector3): Zone?
	local underground = pos.Y < UNDERGROUND_Y
	for _, zone in zones do
		local below = zone.kind == "tunnel" or zone.kind == "underroom"
		if below == underground and inside(zone.rect, pos.X, pos.Z) then
			return zone
		end
	end
	return nil
end

function AdminMapService.GetZones(): { Zone }
	return zones
end

-- ─── Çizim ──────────────────────────────────────────────────────────────────

local COLORS = {
	hall = Color3.fromRGB(40, 62, 80),
	room = Color3.fromRGB(58, 88, 110),
	plot = Color3.fromRGB(70, 112, 90),
	plotEmpty = Color3.fromRGB(52, 66, 76),
	intruder = Color3.fromRGB(200, 50, 60),
	tunnel = Color3.fromRGB(240, 160, 40),
	underroom = Color3.fromRGB(150, 110, 40),
	text = Color3.fromRGB(210, 236, 250),
	dot = Color3.fromRGB(245, 250, 255),
	rogue = Color3.fromRGB(255, 50, 50),
}

--[[
	Dünya → harita: KUZEY (-z, istasyonun arka duvarı) yukarıda, DOĞU (+x,
	Navigation) sağda — standart harita yönü. Eskiden masaya güneyden bakan
	biri için +z yukarı çiziliyordu; ekranda büyük açılınca (AdminView)
	doğu solda kalıyor, harita ayna görüntüsü gibi okunuyordu. Masa da
	artık bu yöne göre döndürülmüş (tools/map/admin.luau).
]]
local function toScale(r: Rect): (UDim2, UDim2)
	local w, h = bounds[3] - bounds[1], bounds[4] - bounds[2]
	local u0 = (r[1] - bounds[1]) / w
	local u1 = (r[3] - bounds[1]) / w
	local v0 = (r[2] - bounds[2]) / h
	local v1 = (r[4] - bounds[2]) / h
	return UDim2.fromScale(u0, v0), UDim2.fromScale(u1 - u0, v1 - v0)
end

local function drawZone(parent: Frame, zone: Zone, z: number)
	local pos, size = toScale(zone.rect)
	local frame = Instance.new("Frame")
	frame.Name = zone.name
	frame.Position = pos
	frame.Size = size
	frame.BorderSizePixel = 0
	frame.ZIndex = z
	frame.BackgroundColor3 = COLORS[zone.kind] or COLORS.room
	frame.BackgroundTransparency = if zone.kind == "tunnel" then 0.25 else 0
	frame.Parent = parent
	if zone.kind ~= "tunnel" and zone.kind ~= "hall" then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 3)
		corner.Parent = frame
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(120, 170, 200)
		stroke.Thickness = 1
		stroke.Parent = frame
	end

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 12)
	title.Position = UDim2.fromOffset(0, 2)
	title.Font = Enum.Font.GothamBold
	-- Dar bölgelerde (Reactor, Navigation) yazı kesilmesin, küçülsün
	title.TextScaled = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 10
	limit.MinTextSize = 5
	limit.Parent = title
	title.TextColor3 = COLORS.text
	title.Text = zone.label
	title.ZIndex = z + 1
	title.Parent = frame

	local dots = Instance.new("Frame")
	dots.Name = "Dots"
	dots.BackgroundTransparency = 1
	dots.Size = UDim2.new(1, -4, 1, if zone.kind == "tunnel" then -4 else -16)
	dots.Position = UDim2.new(0, 2, 0, if zone.kind == "tunnel" then 2 else 14)
	dots.ZIndex = z + 1
	dots.Parent = frame
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(8, 8)
	grid.CellPadding = UDim2.fromOffset(3, 3)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.VerticalAlignment = Enum.VerticalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = dots

	zone.frame = frame
	zone.title = title
	zone.dots = dots
end

local function setDots(zone: Zone, players: number, rogue: boolean)
	local holder = zone.dots
	if not holder then
		return
	end
	local want = players + (if rogue then 1 else 0)
	local have = {}
	for _, c in holder:GetChildren() do
		if c:IsA("Frame") then
			table.insert(have, c)
		end
	end
	for i = #have + 1, want do
		local dot = Instance.new("Frame")
		dot.Name = "Dot"
		dot.BorderSizePixel = 0
		dot.ZIndex = holder.ZIndex + 1
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot
		dot.Parent = holder
		table.insert(have, dot)
	end
	for i, dot in have do
		dot.Visible = i <= want
		dot.LayoutOrder = i
		-- Impostor noktası en sonda, kırmızı
		dot.BackgroundColor3 = if rogue and i == want then COLORS.rogue else COLORS.dot
	end
end

local function build(screen: BasePart)
	local old = screen:FindFirstChild("AdminMap")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "AdminMap"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.Brightness = 1.3
	gui.MaxDistance = 60
	gui.Parent = screen

	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(10, 20, 30)
	bg.BorderSizePixel = 0
	bg.Parent = gui

	local map = Instance.new("Frame")
	map.Name = "Map"
	map.BackgroundTransparency = 1
	map.Position = UDim2.fromScale(0.04, 0.05)
	map.Size = UDim2.fromScale(0.92, 0.9)
	map.Parent = bg
	mapFrame = map

	-- Çizim sırası: koridor altta, Cafeteria + köprü, odalar, üsler, tüneller üstte
	-- (Cafeteria'nın sınırı kanatlara biniyor, kanatlar onun üstünde çizilsin)
	local order = { hall = 1, room = 3, plot = 5, tunnel = 7, underroom = 8 }
	for _, zone in zones do
		local z = if zone.name == "Lobby" or zone.name == "Bridge" then 2 else order[zone.kind] or 3
		drawZone(map, zone, z)
	end

	local head = Instance.new("TextLabel")
	head.Name = "Heading"
	head.BackgroundTransparency = 1
	head.Position = UDim2.fromOffset(8, 2)
	head.Size = UDim2.new(1, -16, 0, 16)
	head.Font = Enum.Font.GothamBlack
	head.TextSize = 14
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.TextColor3 = Color3.fromRGB(90, 226, 246)
	head.Text = "ADMIN  ·  CREW LOCATIONS"
	head.ZIndex = 10
	head.Parent = bg
end

--[[ Bir tur: oyuncuları say, noktaları ve davetsiz misafir rengini güncelle. ]]
function AdminMapService.Update()
	local counts: { [Zone]: number } = {}
	local intruders: { [Zone]: boolean } = {}
	for _, player in Players:GetPlayers() do
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local zone = AdminMapService.Classify(root.Position)
			if zone then
				counts[zone] = (counts[zone] or 0) + 1
				if zone.plot and PlotService.GetOwner(zone.plot) ~= player then
					intruders[zone] = true
				end
			end
		end
	end

	local rogueZone: Zone? = nil
	local rogue = RogueService.GetCurrent()
	if rogue and rogue.root and rogue.root.Parent then
		rogueZone = AdminMapService.Classify(rogue.root.Position)
	end

	for _, zone in zones do
		setDots(zone, counts[zone] or 0, zone == rogueZone)
		if zone.kind == "plot" and zone.frame and zone.title and zone.plot then
			local owner = PlotService.GetOwner(zone.plot)
			zone.title.Text = if owner then owner.DisplayName else "EMPTY"
			zone.frame.BackgroundColor3 = if intruders[zone] then COLORS.intruder
				elseif owner then COLORS.plot
				else COLORS.plotEmpty
		end
	end
end

function AdminMapService.Start()
	task.spawn(function()
		local decor = workspace:WaitForChild("Decor", 30)
		local tableModel = decor and decor:WaitForChild("AdminTable", 10)
		local screen = tableModel and tableModel:FindFirstChild("AdminScreen")
		if not (screen and screen:IsA("BasePart")) then
			warn("[AdminMap] Decor.AdminTable.AdminScreen yok: harita admin bölümü kurulmamış, masa kapalı")
			return
		end

		zones = collectZones()
		bounds = { math.huge, math.huge, -math.huge, -math.huge }
		for _, zone in zones do
			local r = zone.rect
			bounds = { math.min(bounds[1], r[1]), math.min(bounds[2], r[2]), math.max(bounds[3], r[3]), math.max(bounds[4], r[4]) }
		end
		build(screen)

		while true do
			AdminMapService.Update()
			task.wait(UPDATE_EVERY)
		end
	end)
end

return AdminMapService
