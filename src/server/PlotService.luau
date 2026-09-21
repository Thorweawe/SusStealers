--!strict
-- Üsleri koddan kurar, oyunculara dağıtır, kaide (podium) durumunu tutar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local UnitModel = require(Shared.UnitModel)

local PlotService = {}

local plotsFolder: Folder
local plots: { Model } = {}
local ownerByPlot: { [Model]: Player? } = {}
local plotByOwner: { [Player]: Model } = {}

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

	-- Kaideler: iki sıra halinde
	local podiums = Instance.new("Folder")
	podiums.Name = "Podiums"
	podiums.Parent = plot

	local perRow = math.ceil(Config.PodiumsPerPlot / 2)
	for slot = 1, Config.PodiumsPerPlot do
		local isFrontRow = slot <= perRow
		local column = if isFrontRow then slot - 1 else slot - perRow - 1

		local offset = Vector3.new(
			(column - (perRow - 1) / 2) * Config.PodiumSpacing,
			Config.PlotSize.Y / 2 + 0.5,
			if isFrontRow then -8 else 8
		)

		local podium = newAnchoredPart(
			"Podium",
			Vector3.new(4, 1, 4),
			CFrame.new(origin + offset),
			Color3.fromRGB(90, 98, 112),
			podiums
		)
		podium:SetAttribute("SlotIndex", slot)
		podium:SetAttribute("UnitId", "")
		podium:SetAttribute("MutationId", "")
		podium:SetAttribute("PlacedAt", 0)
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

function PlotService.FindEmptyPodium(plot: Model): Part?
	for _, podium in PlotService.GetPodiums(plot) do
		if not PlotService.IsOccupied(podium) then
			return podium
		end
	end
	return nil
end

--[[ Kaideye karakter yerleştirir. Doluysa false döner. ]]
function PlotService.PlaceUnit(podium: Part, unitId: string, mutationId: string?): boolean
	if PlotService.IsOccupied(podium) then
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

local function assignPlot(player: Player)
	for _, plot in plots do
		if ownerByPlot[plot] == nil then
			ownerByPlot[plot] = player
			plotByOwner[player] = plot
			setSignText(plot, string.upper(player.DisplayName))
			PlotService.TeleportToPlot(player)
			return
		end
	end
	warn(string.format("PlotService: %s icin bos us kalmadi", player.Name))
end

local function releasePlot(player: Player)
	local plot = plotByOwner[player]
	if not plot then
		return
	end

	for _, podium in PlotService.GetPodiums(plot) do
		PlotService.ClearUnit(podium)
	end

	local items = plot:FindFirstChild("Items")
	if items then
		items:ClearAllChildren()
	end

	plot:SetAttribute("Locked", false)
	setSignText(plot, "EMPTY BASE")

	ownerByPlot[plot] = nil
	plotByOwner[player] = nil
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

function PlotService.Start()
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

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(releasePlot)
end

return PlotService
