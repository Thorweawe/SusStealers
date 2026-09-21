--!strict
-- Üs yükseltmeleri: oyun içi parayla alınan kalıcı iyileştirmeler.
--
-- Nakdin karakter almak dışında bir harcama yeri yoktu; kaideler dolunca
-- para birikip anlamsızlaşıyordu. Robux ürünlerinin aksine bunlar herkese
-- açık, tek şart yeterince oynamış olmak.
--
-- Her üssün doğuş pedinin yanında yükseltme başına bir pano duruyor.
-- Arayüz gerektirmiyor: seviye ve fiyat panonun üstünde yazıyor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlotService = require(script.Parent.PlotService)
local PromptGuard = require(script.Parent.PromptGuard)
local EconomyService = require(script.Parent.EconomyService)
local DataService = require(script.Parent.DataService)

local UpgradeService = {}

local notifyRemote: RemoteEvent

-- plot -> yükseltme id -> pano (sahip değişince tazelemek için)
local boards: { [Model]: { [string]: BasePart } } = {}

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError)
	end
end

-- ─── Seviye ─────────────────────────────────────────────────────────────────

--[[ Oyuncunun bir yükseltmedeki seviyesi. Profili yoksa 0. ]]
function UpgradeService.GetLevel(player: Player, id: string): number
	local profile = DataService.Get(player)
	if not profile then
		return 0
	end
	return profile.upgrades[id] or 0
end

--[[ Üssün sahibinin seviyesi. Sahipsiz üste 0. ]]
function UpgradeService.GetPlotLevel(plot: Model, id: string): number
	local owner = PlotService.GetOwner(plot)
	if not owner then
		return 0
	end
	return UpgradeService.GetLevel(owner, id)
end

-- ─── Satın alma ─────────────────────────────────────────────────────────────

--[[ Yükseltmeyi bir seviye yükseltmeyi dener. ]]
function UpgradeService.TryUpgrade(player: Player, id: string): boolean
	local def = Config.GetUpgrade(id)
	if not def then
		return false
	end

	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	local level = profile.upgrades[id] or 0
	local cost = Config.GetUpgradeCost(id, level)

	if not cost then
		notify(player, string.format("%s is already maxed", def.name), true)
		return false
	end

	if not EconomyService.TrySpend(player, cost) then
		notify(player, string.format(
			"%s costs $%s - you have $%s",
			def.name, Config.FormatCash(cost),
			Config.FormatCash(EconomyService.GetCash(player))
		), true)
		return false
	end

	profile.upgrades[id] = level + 1
	notify(player, string.format("%s upgraded to level %d", def.name, level + 1), false)
	return true
end

-- ─── Panolar ────────────────────────────────────────────────────────────────

local function refreshBoard(plot: Model, id: string)
	local board = boards[plot] and boards[plot][id]
	if not board then
		return
	end

	local def = Config.GetUpgrade(id)
	local prompt = board:FindFirstChildOfClass("ProximityPrompt")
	local gui = board:FindFirstChild("Label")
	local label = gui and gui:FindFirstChild("Text")
	if not (def and prompt and label and label:IsA("TextLabel")) then
		return
	end

	local level = UpgradeService.GetPlotLevel(plot, id)
	local cost = Config.GetUpgradeCost(id, level)

	label.Text = string.format("%s  %d/%d", def.name, level, def.maxLevel)

	if cost then
		prompt.ObjectText = "$" .. Config.FormatCash(cost)
		prompt.Enabled = true
	else
		prompt.ObjectText = "MAX"
		prompt.Enabled = false
	end
end

local function refreshAll(plot: Model)
	for _, def in Config.Upgrades do
		refreshBoard(plot, def.id)
	end
end

local function buildBoard(plot: Model, def: Config.UpgradeDef, index: number, total: number): BasePart?
	local base = plot:FindFirstChild("Base")
	if not (base and base:IsA("BasePart")) then
		return nil
	end

	-- Doğuş pedinin solunda, arka duvar boyunca dizili
	local spacing = 7
	local offsetX = (index - (total + 1) / 2) * spacing - 16

	local board = Instance.new("Part")
	board.Name = "Upgrade_" .. def.id
	board.Size = Vector3.new(5, 4, 0.5)
	board.CFrame = base.CFrame * CFrame.new(offsetX, Config.PlotSize.Y / 2 + 2, -Config.PlotSize.Z / 2 + 2)
	board.Color = Color3.fromRGB(34, 40, 52)
	board.Material = Enum.Material.SmoothPlastic
	board.Anchored = true
	board.CanCollide = false
	board.Parent = plot

	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromScale(7, 1.6)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	-- AlwaysOnTop kapatildi: yukseltme tabelalari HUD'un (minimap, siralama
	-- tablosu) uzerine ciziliyor ve yaklasinca ekrani kapatiyordu.
	gui.AlwaysOnTop = false
	gui.MaxDistance = 80
	gui.Parent = board

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(150, 220, 255)
	label.TextStrokeTransparency = 0.3
	label.Text = def.name
	label.Parent = gui

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "UpgradePrompt"
	prompt.ActionText = "Upgrade"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonB
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = board

	PromptGuard.Connect(prompt, function(player)
		if PlotService.GetOwner(plot) ~= player then
			notify(player, "Not your base", true)
			return
		end

		if UpgradeService.TryUpgrade(player, def.id) then
			refreshBoard(plot, def.id)
		end
	end)

	return board
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

function UpgradeService.Start()
	notifyRemote = Net.Get("Notify")

	for _, plot in PlotService.GetAllPlots() do
		boards[plot] = {}

		for index, def in Config.Upgrades do
			local board = buildBoard(plot, def, index, #Config.Upgrades)
			if board then
				boards[plot][def.id] = board
			end
		end

		-- Sahip değişince panolar yeni sahibin seviyelerini göstersin
		plot:GetAttributeChangedSignal("UnlockedFloors"):Connect(function()
			refreshAll(plot)
		end)

		refreshAll(plot)
	end

	-- Üs sahipliği anında değişiyor ama profil sonra yükleniyor; kısa bir
	-- döngüyle panoları güncel tutmak, her servise kanca takmaktan basit.
	task.spawn(function()
		while true do
			task.wait(3)
			for _, plot in PlotService.GetAllPlots() do
				refreshAll(plot)
			end
		end
	end)
end

return UpgradeService
