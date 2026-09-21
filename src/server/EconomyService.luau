--!strict
-- Nakit, leaderstats ve saniyelik gelir üretimi.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local PlotService = require(script.Parent.PlotService)
local DataService = require(script.Parent.DataService)

local EconomyService = {}

local cash: { [Player]: number } = {}

-- ─── Nakit ──────────────────────────────────────────────────────────────────

local function refreshStats(player: Player)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Cash")
	if value and value:IsA("StringValue") then
		value.Value = "$" .. Config.FormatCash(cash[player] or 0)
	end
	player:SetAttribute("Cash", cash[player] or 0)
end

--[[
	Nakdi hem arayüze hem profile yazar. Profil DataService'in kaydettiği
	tablonun ta kendisi, dolayısıyla ayrıca "kaydet" demeye gerek yok.
]]
local function commitCash(player: Player)
	local profile = DataService.Get(player)
	if profile then
		profile.cash = cash[player] or 0
	end
	refreshStats(player)
end

function EconomyService.GetCash(player: Player): number
	return cash[player] or 0
end

function EconomyService.AddCash(player: Player, amount: number)
	cash[player] = (cash[player] or 0) + amount
	commitCash(player)
end

--[[ Parası yeterliyse düşer ve true döner. ]]
function EconomyService.TrySpend(player: Player, amount: number): boolean
	local current = cash[player] or 0
	if current < amount then
		return false
	end

	cash[player] = current - amount
	commitCash(player)
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
	-- leaderstats hemen kurulsun ki profil gelene kadar tablo boş görünmesin
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"

	local cashValue = Instance.new("StringValue")
	cashValue.Name = "Cash"
	cashValue.Value = "$0"
	cashValue.Parent = stats

	local stolenValue = Instance.new("IntValue")
	stolenValue.Name = "Stolen"
	stolenValue.Value = 0
	stolenValue.Parent = stats

	stats.Parent = player

	-- Kayıtlı veri gelene kadar bekle; gelmezse oyuncu zaten atılmış olur
	local profile = DataService.WaitForProfile(player)
	if not profile or player.Parent == nil then
		return
	end

	cash[player] = profile.cash
	stolenValue.Value = profile.stolen
	refreshStats(player)
end

function EconomyService.AddStealCount(player: Player)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Stolen")
	if value and value:IsA("IntValue") then
		value.Value += 1

		local profile = DataService.Get(player)
		if profile then
			profile.stolen = value.Value
		end
	end
end

function EconomyService.Start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
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
