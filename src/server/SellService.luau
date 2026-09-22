--!strict
-- Karakter satma: kaideyi boşaltıp parayı geri verir.
--
-- Kaideler dolduğunda oyuncunun tıkanmaması için tek çıkış yolu bu.
-- Çalma promptuyla aynı parçada duruyor ama farklı tuşta (Q), çünkü
-- ProximityPrompt.Enabled oyuncu bazında ayarlanamıyor: kaideye yaklaşan
-- herkes iki promptu da görür, hangisinin çalıştığını sahiplik belirler.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlotService = require(script.Parent.PlotService)
local PromptGuard = require(script.Parent.PromptGuard)
local EconomyService = require(script.Parent.EconomyService)
local DataService = require(script.Parent.DataService)

local SellService = {}

local notifyRemote: RemoteEvent

--[[
	Bildirimin TÜRÜ. İstemci buna bakıp hangi sesi çalacağına karar veriyor.

	Eskiden yalnızca metin ve hata bayrağı gidiyordu; istemci de bütün
	başarılı işlemlerde aynı sesi çalıyordu — satın alma, satma, yükseltme,
	görev, hepsi tek tınıydı ve hangi işlemin tuttuğu kulaktan anlaşılmıyordu.

	Tür servisin kendi alanı olduğu için sabit; bir çağrı farklı bir şey
	anlatıyorsa dördüncü argümanla değiştirilebiliyor.
]]
local NOTIFY_KIND = "sell"

-- Dışa açık: bir test her servisin türünün Config.NotifyCues'ta
-- karşılığı olduğunu doğruluyor, yani sessiz kalan işlem olmuyor.
SellService.NotifyKind = NOTIFY_KIND

local function notify(player: Player, text: string, isError: boolean, kind: string?)
	notifyRemote:FireClient(player, text, isError, kind or NOTIFY_KIND)
end

-- ─── Satış ──────────────────────────────────────────────────────────────────

--[[
	Kaidedeki karakteri satar. Başarılıysa true döner.
	Prompt dışından da çağrılabilir olsun diye dışa açık: arayüzden
	gelecek "hepsini sat" gibi işlemler de buradan geçecek.
]]
function SellService.Sell(player: Player, podium: Part): boolean
	local plot = PlotService.GetPlotFromDescendant(podium)
	if not plot then
		return false
	end

	if PlotService.GetOwner(plot) ~= player then
		notify(player, "Not your podium", true)
		return false
	end

	if not PlotService.IsOccupied(podium) then
		return false
	end

	-- Son karakterini satan oyuncunun geliri sıfırlanıyor. Eline geçen
	-- para en ucuz karakteri almaya yetmezse oyun tamamen kilitleniyor:
	-- kazanç yok, alacak parası yok. İstemci promptu gizliyor ama asıl
	-- kontrol burada olmalı, istemci kontrolü atlanabilir.
	local occupied = 0
	for _, other in PlotService.GetPodiums(plot) do
		if PlotService.IsOccupied(other) then
			occupied += 1
		end
	end

	if occupied <= 1 then
		notify(player, "You cannot sell your last unit", true)
		return false
	end

	-- Fiyatı kaide boşalmadan önce oku
	local unitId = podium:GetAttribute("UnitId") :: string
	local mutationId = podium:GetAttribute("MutationId") :: string
	local payout = Config.GetSellPrice(unitId, if mutationId == "" then nil else mutationId)

	local cleared = PlotService.ClearUnit(podium)
	if not cleared then
		return false
	end

	EconomyService.AddCash(player, payout)
	DataService.Bump(player, "sold")

	local def = Config.GetUnit(unitId)
	notify(player, string.format(
		"Sold %s for $%s",
		if def then def.name else unitId,
		Config.FormatCash(payout)
	), false)

	return true
end

-- ─── Promptlar ──────────────────────────────────────────────────────────────

local function setupPodiumPrompt(podium: Part)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SellPrompt"
	prompt.ActionText = "Sell"
	prompt.ObjectText = ""
	prompt.KeyboardKeyCode = Enum.KeyCode.Q
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = podium

	--[[ Kaide dolduğunda promptu aç, fiyatı da üstünde göster. ]]
	local function refresh()
		local unitId = podium:GetAttribute("UnitId") :: string
		if unitId == "" then
			prompt.Enabled = false
			return
		end

		local mutationId = podium:GetAttribute("MutationId") :: string
		local payout = Config.GetSellPrice(unitId, if mutationId == "" then nil else mutationId)

		prompt.ObjectText = "$" .. Config.FormatCash(payout)
		prompt.Enabled = true
	end

	podium:GetAttributeChangedSignal("UnitId"):Connect(refresh)
	refresh()

	PromptGuard.Connect(prompt, function(player)
		SellService.Sell(player, podium)
	end)
end

function SellService.Start()
	notifyRemote = Net.Get("Notify")

	for _, plot in PlotService.GetAllPlots() do
		for _, podium in PlotService.GetPodiums(plot) do
			setupPodiumPrompt(podium)
		end
	end
end

return SellService
