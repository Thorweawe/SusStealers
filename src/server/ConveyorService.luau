--!strict
-- Her üssün konveyöründe karakter üretir, kaydırır, satın alma promptunu yönetir.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local UnitModel = require(Shared.UnitModel)

local PlotService = require(script.Parent.PlotService)
local EconomyService = require(script.Parent.EconomyService)

local ConveyorService = {}

local rng = Random.new()
local notifyRemote: RemoteEvent

type ConveyorItem = {
	model: Model,
	plot: Model,
	unitId: string,
	mutationId: string?,
	price: number,
	startCFrame: CFrame,
	travel: number,
	spawnedAt: number,
}

local activeItems: { ConveyorItem } = {}

-- ─── Üretim ─────────────────────────────────────────────────────────────────

local function spawnItem(plot: Model)
	local conveyor = plot:FindFirstChild("Conveyor")
	local items = plot:FindFirstChild("Items")
	if not (conveyor and conveyor:IsA("Part") and items) then
		return
	end

	local def = Config.RollUnit(rng)
	local mutation = Config.RollMutation(rng)
	local mutationId = if mutation then mutation.id else nil
	local price = Config.GetPrice(def.id, mutationId)

	local model = UnitModel.Build(def.id, mutationId)
	model.Name = "ConveyorItem"

	local travel = conveyor.Size.X - 4
	local startCFrame = conveyor.CFrame * CFrame.new(-travel / 2, conveyor.Size.Y / 2, 0)
	model:PivotTo(startCFrame)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
		end
	end

	local label = UnitModel.BuildLabel(def.id, mutationId)
	label.Parent = model.PrimaryPart

	-- Satın alma promptu
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BuyPrompt"
	prompt.ActionText = "Buy"
	prompt.ObjectText = string.format("$%s", Config.FormatCash(price))
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart

	model.Parent = items

	local item: ConveyorItem = {
		model = model,
		plot = plot,
		unitId = def.id,
		mutationId = mutationId,
		price = price,
		startCFrame = startCFrame,
		travel = travel,
		spawnedAt = os.clock(),
	}
	table.insert(activeItems, item)

	prompt.Triggered:Connect(function(player)
		ConveyorService.TryBuy(player, item, prompt)
	end)
end

-- ─── Satın alma ─────────────────────────────────────────────────────────────

local function notify(player: Player, text: string, isError: boolean)
	notifyRemote:FireClient(player, text, isError)
end

function ConveyorService.TryBuy(player: Player, item: ConveyorItem, prompt: ProximityPrompt)
	if item.model.Parent == nil then
		return
	end

	local plot = PlotService.GetPlotOf(player)
	if not plot then
		notify(player, "You need a base first", true)
		return
	end

	if plot ~= item.plot then
		notify(player, "Not your conveyor", true)
		return
	end

	local podium = PlotService.FindEmptyPodium(plot)
	if not podium then
		notify(player, "No free podium", true)
		return
	end

	if not EconomyService.TrySpend(player, item.price) then
		notify(player, "Not enough cash", true)
		return
	end

	prompt.Enabled = false
	PlotService.PlaceUnit(podium, item.unitId, item.mutationId)

	local def = Config.GetUnit(item.unitId)
	notify(player, string.format("%s purchased", if def then def.name else item.unitId), false)

	item.model:Destroy()
end

-- ─── Döngü ──────────────────────────────────────────────────────────────────

local function stepItems()
	local now = os.clock()

	for index = #activeItems, 1, -1 do
		local item = activeItems[index]

		if item.model.Parent == nil then
			table.remove(activeItems, index)
			continue
		end

		local elapsed = now - item.spawnedAt
		local progress = elapsed / Config.ConveyorLifetime

		if progress >= 1 then
			item.model:Destroy()
			table.remove(activeItems, index)
			continue
		end

		item.model:PivotTo(item.startCFrame * CFrame.new(item.travel * progress, 0, 0))
	end
end

function ConveyorService.Start()
	notifyRemote = Net.Get("Notify")

	RunService.Heartbeat:Connect(stepItems)

	task.spawn(function()
		while true do
			task.wait(Config.ConveyorInterval)
			for _, plot in PlotService.GetAllPlots() do
				-- Sahipsiz üste karakter üretmeye gerek yok
				if PlotService.GetOwner(plot) then
					spawnItem(plot)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local plot = PlotService.GetPlotOf(player)
		if not plot then
			return
		end
		for index = #activeItems, 1, -1 do
			if activeItems[index].plot == plot then
				activeItems[index].model:Destroy()
				table.remove(activeItems, index)
			end
		end
	end)
end

return ConveyorService
