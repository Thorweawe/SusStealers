--!strict
-- Rebirth: her şeyi sıfırlar, karşılığında kalıcı gelir çarpanı ve yeni kat verir.
--
-- Tavana ulaşan oyuncunun yapacak bir şeyi kalmıyordu: 8 kaide dolduktan
-- sonra biriken para hiçbir işe yaramıyordu. Rebirth o parayı harcanabilir
-- bir hedefe çeviriyor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlotService = require(script.Parent.PlotService)
local PromptGuard = require(script.Parent.PromptGuard)
local EconomyService = require(script.Parent.EconomyService)
local DataService = require(script.Parent.DataService)

local RebirthService = {}

local notifyRemote: RemoteEvent

local function notify(player: Player, text: string, isError: boolean)
	notifyRemote:FireClient(player, text, isError)
end

-- ─── Rebirth ────────────────────────────────────────────────────────────────

--[[
	Oyuncunun rebirth yapmasını dener. Başarılıysa true döner.
	Prompt dışından da çağrılabilsin diye dışa açık.
]]
function RebirthService.TryRebirth(player: Player): boolean
	local plot = PlotService.GetPlotOf(player)
	if not plot then
		notify(player, "You need a base first", true)
		return false
	end

	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	if profile.rebirths >= Config.MaxFloors - 1 then
		notify(player, "You are already at max rebirth", true)
		return false
	end

	local cost = Config.GetRebirthCost(profile.rebirths)
	if not EconomyService.TrySpend(player, cost) then
		notify(player, string.format(
			"Rebirth costs $%s - you have $%s",
			Config.FormatCash(cost),
			Config.FormatCash(EconomyService.GetCash(player))
		), true)
		return false
	end

	-- Sıfırlama: kaideler boşalır, nakit başlangıca döner.
	-- Kalan parayı da alıyoruz; rebirth "her şeyi bırak" demek.
	for _, podium in PlotService.GetPodiums(plot) do
		if PlotService.IsOccupied(podium) then
			PlotService.ClearUnit(podium)
		end
	end

	EconomyService.AddCash(player, Config.StartingCash - EconomyService.GetCash(player))

	profile.rebirths += 1
	PlotService.SetUnlockedFloors(plot, Config.GetUnlockedFloors(profile.rebirths))
	PlotService.RefreshSign(plot)

	local multiplier = Config.GetIncomeMultiplier(profile.rebirths)
	local floors = Config.GetUnlockedFloors(profile.rebirths)

	notify(player, string.format(
		"REBIRTH %d! Income x%.1f, floor %d unlocked",
		profile.rebirths, multiplier, floors
	), false)

	-- Rebirth pahalı ve geri alınamaz; bir sonraki autosave'i beklemeyelim
	DataService.Save(player)
	return true
end

-- ─── Prompt ─────────────────────────────────────────────────────────────────

local function setupPrompt(plot: Model)
	local sign = plot:FindFirstChild("Sign")
	if not (sign and sign:IsA("BasePart")) then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RebirthPrompt"
	prompt.ActionText = "Rebirth"
	prompt.KeyboardKeyCode = Enum.KeyCode.R
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 1.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = sign

	--[[ Sahip değiştikçe veya rebirth oldukça fiyatı tazele. ]]
	local function refresh()
		local owner = PlotService.GetOwner(plot)
		local profile = owner and DataService.Get(owner)
		local rebirths = if profile then profile.rebirths else 0

		if rebirths >= Config.MaxFloors - 1 then
			prompt.ObjectText = "MAX"
			return
		end

		prompt.ObjectText = "$" .. Config.FormatCash(Config.GetRebirthCost(rebirths))
	end

	plot:GetAttributeChangedSignal("UnlockedFloors"):Connect(refresh)
	refresh()

	PromptGuard.Connect(prompt, function(player)
		RebirthService.TryRebirth(player)
		refresh()
	end)
end

function RebirthService.Start()
	notifyRemote = Net.Get("Notify")

	for _, plot in PlotService.GetAllPlots() do
		setupPrompt(plot)
	end
end

return RebirthService
