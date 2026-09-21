--!strict
-- Üsleri koddan kurar, oyunculara dağıtır, kaide (podium) durumunu tutar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local UnitModel = require(Shared.UnitModel)

local DataService = require(script.Parent.DataService)

local PlotService = {}

local plotsFolder: Folder
local plots: { Model } = {}
local ownerByPlot: { [Model]: Player? } = {}
local plotByOwner: { [Player]: Model } = {}

-- Start() tekrar çağrılabilsin diye: eski bağlantılar burada tutulur,
-- yeniden kurarken kesilir. Yoksa PlayerAdded iki kez tetiklenir.
local connections: { RBXScriptConnection } = {}

-- Oyuncu çıkarken üssü boşaltılıyor. O sırada profile yazarsak kayıtlı
-- karakterleri kaydedilmeden hemen önce sileriz. Bu bayrak onu engelliyor.
local releasing: { [Player]: boolean } = {}

-- Üs bekleyen oyuncular, giriş sırasına göre
local waiting: { Player } = {}

local notifyRemote: RemoteEvent

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError)
	end
end

-- ─── Kurulum ────────────────────────────────────────────────────────────────

local function newAnchoredPart(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = parent
	return part
end

local function buildPlot(index: number): Model
	local plot = Instance.new("Model")
	plot.Name = string.format("Plot%d", index)

	local origin = Vector3.new((index - 1) * Config.PlotSpacing, 0, 0)

	-- Zemin
	local base = newAnchoredPart("Base", Config.PlotSize, CFrame.new(origin), Color3.fromRGB(58, 64, 76), plot)
	base.Material = Enum.Material.Concrete
	plot.PrimaryPart = base

	-- Kaideler: her katta iki sıra. 1. kat zeminde ve açık gelir,
	-- üst katlar rebirth ile açılır. Slot numaraları katlar boyunca
	-- kesintisiz devam ediyor ki kayıttaki slot -> kaide eşlemesi bozulmasın.
	local podiums = Instance.new("Folder")
	podiums.Name = "Podiums"
	podiums.Parent = plot

	local floors = Instance.new("Folder")
	floors.Name = "Floors"
	floors.Parent = plot

	local perRow = math.ceil(Config.PodiumsPerPlot / 2)
	local groundY = Config.PlotSize.Y / 2   -- 1. katın yürüme yüzeyi

	for floor = 1, Config.MaxFloors do
		local deckTop = groundY + (floor - 1) * Config.FloorHeight

		local floorModel = Instance.new("Model")
		floorModel.Name = string.format("Floor%d", floor)
		floorModel.Parent = floors

		if floor > 1 then
			-- Üst katın zemini
			local deck = newAnchoredPart(
				"Deck",
				Vector3.new(Config.PlotSize.X, 1, Config.PlotSize.Z - 12),
				CFrame.new(origin + Vector3.new(0, deckTop - 0.5, 0)),
				Color3.fromRGB(48, 54, 66),
				floorModel
			)
			deck.Material = Enum.Material.Metal

			-- Rampa: 24 stud yatay, FloorHeight kadar dikey.
			-- Uzunluk ve açı bu ikisinden türetiliyor, elle sayı girilmiyor;
			-- FloorHeight değişirse rampa kendiliğinden uyuyor.
			local run = 24
			local rise = Config.FloorHeight
			local length = math.sqrt(run * run + rise * rise)
			local angle = math.atan2(rise, run)

			-- Sağ kenarda, arka tarafta: konveyör (ön kenar), tabela ve
			-- doğuş pedi (orta) ile çakışmasın. Yatay koşu plot içinde
			-- kalsın diye merkez arka kenardan run/2 kadar içeride.
			local ramp = newAnchoredPart(
				"Ramp",
				Vector3.new(10, 1, length),
				CFrame.new(origin + Vector3.new(
					Config.PlotSize.X / 2 - 7,
					deckTop - rise / 2 - 0.5,
					-Config.PlotSize.Z / 2 + run / 2
				)) * CFrame.Angles(-angle, 0, 0),
				Color3.fromRGB(60, 68, 82),
				floorModel
			)
			ramp.Material = Enum.Material.Metal
		end

		for index = 1, Config.PodiumsPerPlot do
			local isFrontRow = index <= perRow
			local column = if isFrontRow then index - 1 else index - perRow - 1

			local offset = Vector3.new(
				(column - (perRow - 1) / 2) * Config.PodiumSpacing,
				deckTop + 0.5,
				if isFrontRow then -8 else 8
			)

			local podium = newAnchoredPart(
				"Podium",
				Vector3.new(4, 1, 4),
				CFrame.new(origin + offset),
				Color3.fromRGB(90, 98, 112),
				podiums
			)
			podium:SetAttribute("SlotIndex", (floor - 1) * Config.PodiumsPerPlot + index)
			podium:SetAttribute("Floor", floor)
			podium:SetAttribute("UnitId", "")
			podium:SetAttribute("MutationId", "")
			podium:SetAttribute("PlacedAt", 0)
		end
	end

	-- Konveyör (görsel şerit)
	local conveyor = newAnchoredPart(
		"Conveyor",
		Vector3.new(Config.PlotSize.X - 8, 1, 5),
		CFrame.new(origin + Vector3.new(0, Config.PlotSize.Y / 2 + 0.5, Config.PlotSize.Z / 2 - 5)),
		Color3.fromRGB(38, 42, 52),
		plot
	)
	conveyor.Material = Enum.Material.DiamondPlate

	local items = Instance.new("Folder")
	items.Name = "Items"
	items.Parent = plot

	-- Sahip tabelası
	local sign = newAnchoredPart(
		"Sign",
		Vector3.new(6, 0.4, 0.4),
		CFrame.new(origin + Vector3.new(0, 8, -Config.PlotSize.Z / 2 + 1)),
		Color3.fromRGB(30, 34, 42),
		plot
	)

	local gui = Instance.new("BillboardGui")
	gui.Name = "OwnerLabel"
	gui.Size = UDim2.fromScale(12, 3)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 250
	gui.Parent = sign

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(235, 240, 255)
	label.TextStrokeTransparency = 0.3
	label.Text = "EMPTY BASE"
	label.Parent = gui

	-- Doğuş pedi: oyuncu ortada değil, kendi üssünde başlasın
	local spawnPad = newAnchoredPart(
		"SpawnPad",
		Vector3.new(8, 0.4, 8),
		CFrame.new(origin + Vector3.new(0, Config.PlotSize.Y / 2 + 0.3, -Config.PlotSize.Z / 2 + 7)),
		Color3.fromRGB(70, 200, 255),
		plot
	)
	spawnPad.Material = Enum.Material.Neon
	spawnPad.Transparency = 0.45

	plot:SetAttribute("Locked", false)
	plot:SetAttribute("LockUsedAt", 0)
	plot:SetAttribute("UnlockedFloors", 1)

	plot.Parent = plotsFolder
	return plot
end

-- ─── Kaide işlemleri ────────────────────────────────────────────────────────

function PlotService.GetPodiums(plot: Model): { Part }
	local result: { Part } = {}
	local folder = plot:FindFirstChild("Podiums")
	if not folder then
		return result
	end

	for _, child in folder:GetChildren() do
		if child:IsA("Part") then
			table.insert(result, child)
		end
	end

	table.sort(result, function(a, b)
		return (a:GetAttribute("SlotIndex") :: number) < (b:GetAttribute("SlotIndex") :: number)
	end)
	return result
end

function PlotService.IsOccupied(podium: Part): boolean
	return (podium:GetAttribute("UnitId") :: string) ~= ""
end

--[[ Kaidenin bulunduğu kat açık mı. Kapalı kattaki kaide kullanılamaz. ]]
function PlotService.IsPodiumUnlocked(podium: Part): boolean
	local plot = PlotService.GetPlotFromDescendant(podium)
	if not plot then
		return false
	end

	local floor = (podium:GetAttribute("Floor") :: number?) or 1
	local unlocked = (plot:GetAttribute("UnlockedFloors") :: number?) or 1
	return floor <= unlocked
end

--[[ Yalnızca açık katlardaki kaideler. ]]
function PlotService.GetUnlockedPodiums(plot: Model): { Part }
	local unlocked = (plot:GetAttribute("UnlockedFloors") :: number?) or 1
	local result: { Part } = {}

	for _, podium in PlotService.GetPodiums(plot) do
		local floor = (podium:GetAttribute("Floor") :: number?) or 1
		if floor <= unlocked then
			table.insert(result, podium)
		end
	end
	return result
end

function PlotService.FindEmptyPodium(plot: Model): Part?
	for _, podium in PlotService.GetUnlockedPodiums(plot) do
		if not PlotService.IsOccupied(podium) then
			return podium
		end
	end
	return nil
end

--[[
	Açık kat sayısını değiştirir ve kapalı katları hayalete çevirir:
	görünür ama üstüne çıkılamaz, kaidesi kullanılamaz. Tamamen
	gizlemek yerine böyle bırakıyoruz ki oyuncu ne kazanacağını görsün.
]]
function PlotService.SetUnlockedFloors(plot: Model, count: number)
	local unlocked = math.clamp(count, 1, Config.MaxFloors)
	plot:SetAttribute("UnlockedFloors", unlocked)

	local floors = plot:FindFirstChild("Floors")
	if floors then
		for _, floorModel in floors:GetChildren() do
			local index = tonumber(string.match(floorModel.Name, "%d+")) or 1
			local open = index <= unlocked

			for _, part in floorModel:GetDescendants() do
				if part:IsA("BasePart") then
					part.CanCollide = open
					part.Transparency = if open then 0 else 0.75
				end
			end
		end
	end

	for _, podium in PlotService.GetPodiums(plot) do
		local floor = (podium:GetAttribute("Floor") :: number?) or 1
		local open = floor <= unlocked
		podium.Transparency = if open then 0 else 0.75
		podium.CanCollide = open
	end
end

--[[
	Üssün güncel kaide içeriğini sahibinin profiline yazar.
	Profil DataService'in kaydettiği tablo olduğu için ayrıca kaydetmek
	gerekmiyor; bir sonraki autosave veya çıkış kaydı bunu diske alır.
]]
local function syncProfile(podium: Part)
	local plot = PlotService.GetPlotFromDescendant(podium)
	local owner = plot and ownerByPlot[plot]
	if not (plot and owner) or releasing[owner] then
		return
	end

	local profile = DataService.Get(owner)
	if not profile then
		return
	end

	local units = {}
	for _, other in PlotService.GetPodiums(plot) do
		local unitId = other:GetAttribute("UnitId") :: string
		if unitId ~= "" then
			local mutationId = other:GetAttribute("MutationId") :: string
			table.insert(units, {
				slot = other:GetAttribute("SlotIndex") :: number,
				unitId = unitId,
				mutationId = if mutationId == "" then nil else mutationId,
			})
		end
	end

	profile.units = units
end

--[[ Kaideye karakter yerleştirir. Doluysa false döner. ]]
function PlotService.PlaceUnit(podium: Part, unitId: string, mutationId: string?): boolean
	if PlotService.IsOccupied(podium) then
		return false
	end

	-- Kayıt geri yüklenirken kapalı kata denk gelebilir; sessizce atla
	if not PlotService.IsPodiumUnlocked(podium) then
		return false
	end

	local model = UnitModel.Build(unitId, mutationId)
	model.Name = "Unit"
	model:PivotTo(podium.CFrame * CFrame.new(0, podium.Size.Y / 2, 0))

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	local label = UnitModel.BuildLabel(unitId, mutationId)
	label.Parent = model.PrimaryPart

	model.Parent = podium

	podium:SetAttribute("UnitId", unitId)
	podium:SetAttribute("MutationId", mutationId or "")
	podium:SetAttribute("PlacedAt", os.clock())

	syncProfile(podium)
	return true
end

--[[ Kaideyi boşaltır ve üstündeki karakterin kimliğini döner. ]]
function PlotService.ClearUnit(podium: Part): (string?, string?)
	if not PlotService.IsOccupied(podium) then
		return nil, nil
	end

	local unitId = podium:GetAttribute("UnitId") :: string
	local mutationId = podium:GetAttribute("MutationId") :: string

	local model = podium:FindFirstChild("Unit")
	if model then
		model:Destroy()
	end

	podium:SetAttribute("UnitId", "")
	podium:SetAttribute("MutationId", "")
	podium:SetAttribute("PlacedAt", 0)

	syncProfile(podium)
	return unitId, (if mutationId == "" then nil else mutationId)
end

-- ─── Sahiplik ───────────────────────────────────────────────────────────────

function PlotService.GetPlotOf(player: Player): Model?
	return plotByOwner[player]
end

function PlotService.GetOwner(plot: Model): Player?
	return ownerByPlot[plot]
end

--[[ Herhangi bir parçadan üstteki plot'u bulur. ]]
function PlotService.GetPlotFromDescendant(instance: Instance): Model?
	local current: Instance? = instance
	while current and current ~= plotsFolder do
		if current:IsA("Model") and current.Parent == plotsFolder then
			return current
		end
		current = current.Parent
	end
	return nil
end

function PlotService.GetAllPlots(): { Model }
	return plots
end

local function setSignText(plot: Model, text: string)
	local sign = plot:FindFirstChild("Sign")
	local gui = sign and sign:FindFirstChild("OwnerLabel")
	local label = gui and gui:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

--[[ Oyuncuyu kendi üssünün doğuş pedine taşır. Üssü yoksa hiçbir şey yapmaz. ]]
function PlotService.TeleportToPlot(player: Player)
	local plot = plotByOwner[player]
	if not plot then
		return
	end

	local pad = plot:FindFirstChild("SpawnPad")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (pad and pad:IsA("BasePart") and root and root:IsA("BasePart")) then
		return
	end

	character:PivotTo(pad.CFrame * CFrame.new(0, 4, 0))
end

--[[ Kayıtlı karakterleri oyuncunun kaidelerine geri koyar. ]]
local function restoreUnits(player: Player)
	local plot = plotByOwner[player]
	local profile = DataService.Get(player)
	if not (plot and profile) then
		return
	end

	-- PlaceUnit profile geri yazıyor; kopyayı gezmezsek listeyi altımızdan çeker
	local stored = table.clone(profile.units)
	local podiums = PlotService.GetPodiums(plot)

	for _, entry in stored do
		local podium = podiums[entry.slot]
		if podium and not PlotService.IsOccupied(podium) then
			PlotService.PlaceUnit(podium, entry.unitId, entry.mutationId)
		end
	end
end

local function grantPlot(player: Player, plot: Model)
	ownerByPlot[plot] = player
	plotByOwner[player] = plot
	setSignText(plot, string.upper(player.DisplayName))
	PlotService.TeleportToPlot(player)

	-- Profil hâlâ yükleniyor olabilir
	task.spawn(function()
		local profile = DataService.WaitForProfile(player)
		if not profile then
			return
		end

		-- Katları karakterleri geri koymadan ÖNCE aç: kayıtlı karakter
		-- üst kattaysa kapalı kata konamaz ve sessizce kaybolurdu.
		PlotService.SetUnlockedFloors(plot, Config.GetUnlockedFloors(profile.rebirths))
		PlotService.RefreshSign(plot)
		restoreUnits(player)
	end)
end

--[[
	Boş üs varsa verir, yoksa sıraya alır. Üssü olmayan oyuncu hiçbir şey
	yapamıyor — satın alamıyor, çalamıyor, kazanç üretemiyor. Eskiden bu
	durumda sadece sunucuya uyarı basılıyordu ve oyuncu ne olduğunu
	anlamadan boş bir ekrana bakıyordu.
]]
--[[ Tabelaya sahibin adını ve rebirth seviyesini yazar. ]]
function PlotService.RefreshSign(plot: Model)
	local owner = ownerByPlot[plot]
	if not owner then
		setSignText(plot, "EMPTY BASE")
		return
	end

	local profile = DataService.Get(owner)
	local rebirths = if profile then profile.rebirths else 0

	if rebirths > 0 then
		setSignText(plot, string.format("%s  [R%d]", string.upper(owner.DisplayName), rebirths))
	else
		setSignText(plot, string.upper(owner.DisplayName))
	end
end

local function assignPlot(player: Player)
	for _, plot in plots do
		if ownerByPlot[plot] == nil then
			grantPlot(player, plot)
			return
		end
	end

	if not table.find(waiting, player) then
		table.insert(waiting, player)
	end

	local position = table.find(waiting, player) or #waiting
	notify(player, string.format("All bases taken - you are #%d in line", position), true)
end

--[[ Boşalan üssü sıradaki oyuncuya verir. ]]
local function grantToNextInLine(plot: Model)
	while #waiting > 0 do
		local next = table.remove(waiting, 1)
		if next and next.Parent then
			grantPlot(next, plot)
			notify(next, "A base opened up - it is yours", false)
			return
		end
	end
end

local function releasePlot(player: Player)
	local plot = plotByOwner[player]
	if not plot then
		return
	end

	-- Kaideleri boşaltırken profile dokunma: kayıt henüz alınmamış olabilir
	releasing[player] = true

	for _, podium in PlotService.GetPodiums(plot) do
		PlotService.ClearUnit(podium)
	end

	releasing[player] = nil

	local items = plot:FindFirstChild("Items")
	if items then
		items:ClearAllChildren()
	end

	plot:SetAttribute("Locked", false)
	PlotService.SetUnlockedFloors(plot, 1)
	setSignText(plot, "EMPTY BASE")

	ownerByPlot[plot] = nil
	plotByOwner[player] = nil

	grantToNextInLine(plot)
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

function PlotService.Start()
	-- Tekrar çağrılabilir olmalı: eski dünya siliniyorsa ona ait durum da
	-- silinmeli. Aksi halde plots listesinde yok edilmiş modeller kalır ve
	-- oyuncular artık var olmayan üslere atanır.
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(plots)
	table.clear(ownerByPlot)
	table.clear(plotByOwner)
	table.clear(waiting)

	notifyRemote = Net.Get("Notify")

	local existing = workspace:FindFirstChild("Plots")
	if existing then
		existing:Destroy()
	end

	plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = workspace

	for index = 1, Config.PlotCount do
		table.insert(plots, buildPlot(index))
	end

	-- Üs ver + her doğuşta o üsse taşı
	local function onPlayerAdded(player: Player)
		assignPlot(player)

		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart")
			task.wait(0.1) -- karakter tam oturmadan ışınlarsak geri kayıyor
			PlotService.TeleportToPlot(player)
		end)

		if player.Character then
			PlotService.TeleportToPlot(player)
		end
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	table.insert(connections, Players.PlayerAdded:Connect(onPlayerAdded))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		local index = table.find(waiting, player)
		if index then
			table.remove(waiting, index)
		end
		releasePlot(player)
	end))
end

return PlotService
