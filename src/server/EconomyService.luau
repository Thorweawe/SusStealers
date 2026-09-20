--!strict
-- Nakit, leaderstats ve saniyelik gelir üretimi.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local PlotService = require(script.Parent.PlotService)

local EconomyService = {}

local cash: { [Player]: number } = {}

-- ─── Nakit ──────────────────────────────────────────────────────────────────

local function refreshStats(player: Player)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Nakit")
	if value and value:IsA("StringValue") then
		value.Value = "$" .. Config.FormatCash(cash[player] or 0)
	end
	player:SetAttribute("Cash", cash[player] or 0)
end

function EconomyService.GetCash(player: Player): number
	return cash[player] or 0
end

function EconomyService.AddCash(player: Player, amount: number)
	cash[player] = (cash[player] or 0) + amount
	refreshStats(player)
end

--[[ Parası yeterliyse düşer ve true döner. ]]
function EconomyService.TrySpend(player: Player, amount: number): boolean
	local current = cash[player] or 0
	if current < amount then
		return false
	end

	cash[player] = current - amount
	refreshStats(player)
	return true
end

-- ─── Gelir ──────────────────────────────────────────────────────────────────

--[[ Oyuncunun kaidelerindeki karakterlerin toplam saniyelik geliri. ]]
function EconomyService.GetIncome(player: Player): number
	local plot = PlotService.GetPlotOf(player)
	if not plot then
		return 0
	end

	local total = 0
	for _, podium in PlotService.GetPodiums(plot) do
		local unitId = podium:GetAttribute("UnitId") :: string
		if unitId ~= "" then
			local def = Config.GetUnit(unitId)
			if def then
				local mutationId = podium:GetAttribute("MutationId") :: string
				local mutation = Config.GetMutation(if mutationId == "" then nil else mutationId)
				total += def.income * (if mutation then mutation.incomeMul else 1)
			end
		end
	end
	return total
end

-- ─── Yaşam döngüsü ──────────────────────────────────────────────────────────

local function onPlayerAdded(player: Player)
	cash[player] = Config.StartingCash

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"

	local cashValue = Instance.new("StringValue")
	cashValue.Name = "Nakit"
	cashValue.Value = "$" .. Config.FormatCash(Config.StartingCash)
	cashValue.Parent = stats

	local stolenValue = Instance.new("IntValue")
	stolenValue.Name = "Çalınan"
	stolenValue.Value = 0
	stolenValue.Parent = stats

	stats.Parent = player
	player:SetAttribute("Cash", Config.StartingCash)
end

function EconomyService.AddStealCount(player: Player)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Çalınan")
	if value and value:IsA("IntValue") then
		value.Value += 1
	end
end

function EconomyService.Start()
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)

	Players.PlayerRemoving:Connect(function(player)
		cash[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(Config.IncomeInterval)
			for _, player in Players:GetPlayers() do
				local income = EconomyService.GetIncome(player)
				if income > 0 then
					EconomyService.AddCash(player, income * Config.IncomeInterval)
				end
				player:SetAttribute("Income", income)
			end
		end
	end)
end

return EconomyService
