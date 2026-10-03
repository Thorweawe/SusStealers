--!strict
--[[
	Crewmate birleştirme (2026-10-03, Batur: "iki aynı crewmate birleşince
	level 2, iki level 2 birleşince level 3; Sell'in altında 'can merge'
	yazsın").

	Kaidede aynı karakterden (aynı seviyede) iki tane varsa ikisinin de
	kaidesinde MergePrompt açılıyor (F). Basılan kaide bir üst seviyeye
	çıkıyor, eşi boşalıyor. Mutasyon ikisinden değerlisi kalıyor. Gelir ve
	boy çarpanları Config.MergeLevels'ta (Lv2 ×2.5 / ×2, Lv3 ×6 / ×3).

	Sahada ya da hastanede olan (Away) birleşmiyor. Prompt istemcide yalnızca
	kendi üssünde ve kaidenin "CanMerge" niteliği açıkken görünüyor
	(PromptFilter); ProximityPrompt.Enabled oyuncu bazında ayarlanamıyor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlotService = require(script.Parent.PlotService)
local PromptGuard = require(script.Parent.PromptGuard)
local DataService = require(script.Parent.DataService)

local MergeService = {}

local NOTIFY_KIND = "merge"
-- Testler her servisin bildirim türünün sesi olduğunu doğruluyor
MergeService.NotifyKind = NOTIFY_KIND

local notifyRemote: RemoteEvent? = nil

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError, NOTIFY_KIND)
	end
end

local function key(podium: Part): string?
	local unitId = podium:GetAttribute("UnitId") :: string
	if unitId == "" or PlotService.GetAway(podium) then
		return nil
	end
	local level = PlotService.GetLevel(podium)
	if level >= Config.MergeMaxLevel then
		return nil
	end
	return unitId .. "#" .. level
end

--[[ Aynı üste bu kaideyle birleşebilecek başka bir kaide (yoksa nil). ]]
function MergeService.FindPartner(podium: Part): Part?
	local plot = PlotService.GetPlotFromDescendant(podium)
	local k = key(podium)
	if not (plot and k) then
		return nil
	end
	for _, other in PlotService.GetPodiums(plot) do
		if other ~= podium and key(other) == k then
			return other
		end
	end
	return nil
end

-- Bir üssün bütün kaidelerinde "CanMerge" niteliğini ve prompt yazısını yeniler
local function refreshPlot(plot: Model)
	for _, podium in PlotService.GetPodiums(plot) do
		local can = MergeService.FindPartner(podium) ~= nil
		if podium:GetAttribute("CanMerge") ~= can then
			podium:SetAttribute("CanMerge", can)
		end
		local prompt = podium:FindFirstChild("MergePrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			local nextLevel = PlotService.GetLevel(podium) + 1
			prompt.ActionText = string.format("Merge → LV%d", nextLevel)
			prompt.ObjectText = "✨ CAN MERGE!"
			prompt.Enabled = can
		end
	end
end

local function mutationValue(mutationId: string?): number
	local m = Config.GetMutation(mutationId)
	return if m then m.incomeMul else 1
end

--[[ Basılan kaide bir üst seviyeye çıkar, eşi boşalır. Başarılıysa true. ]]
function MergeService.Merge(player: Player, podium: Part): boolean
	local plot = PlotService.GetPlotFromDescendant(podium)
	if not plot or PlotService.GetOwner(plot) ~= player then
		return false
	end
	local partner = MergeService.FindPartner(podium)
	if not partner then
		notify(player, "You need two of the same crewmate (same level) to merge", true)
		return false
	end
	local unitId, mutA, level = PlotService.ClearUnit(podium)
	local _, mutB = PlotService.ClearUnit(partner)
	if not (unitId and level) then
		return false
	end
	local mutation = if mutationValue(mutB) > mutationValue(mutA) then mutB else mutA
	local newLevel = Config.MergeLevel(level + 1)
	PlotService.PlaceUnit(podium, unitId, mutation, newLevel)
	DataService.RequestSave(player)
	local def = Config.GetUnit(unitId)
	notify(player, string.format("%s merged to LV%d! Income ×%s", if def then def.name else unitId, newLevel,
		tostring(Config.MergeIncome(newLevel))), false)
	return true
end

local function setupPodium(plot: Model, podium: Part)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MergePrompt"
	prompt.ActionText = "Merge"
	prompt.ObjectText = "✨ CAN MERGE!"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = podium

	local function changed()
		refreshPlot(plot)
	end
	podium:GetAttributeChangedSignal("UnitId"):Connect(changed)
	podium:GetAttributeChangedSignal("Level"):Connect(changed)
	podium:GetAttributeChangedSignal("Away"):Connect(changed)

	PromptGuard.Connect(prompt, function(player)
		MergeService.Merge(player, podium)
	end)
end

function MergeService.Start()
	notifyRemote = Net.Get("Notify")
	for _, plot in PlotService.GetAllPlots() do
		for _, podium in PlotService.GetPodiums(plot) do
			setupPodium(plot, podium)
		end
		refreshPlot(plot)
	end
end

-- Testler için
MergeService._refreshPlot = refreshPlot

return MergeService
