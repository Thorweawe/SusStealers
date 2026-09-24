--!strict
--[[
	Sabotaj eşyaları (Config.Sabotages): oyun içi parayla alınan, rakibin
	üssüne uzaktan kullanılan tek kullanımlıklar.

	  Blackout — üssün ışıkları sönüyor (sunucuda, herkes görüyor) ve
	             "Blackout" niteliği yüzünden StealService oradaki çalma
	             sürelerini Config.BlackoutHoldMul ile kısaltıyor.
	  LockJam  — "LockJam" niteliği: StealService kilit promptu reddediyor;
	             üs o an kilitliyse kilit Config.LockJamDropDelay sn sonra
	             düşüyor.
	  CommsJam — kurbanın "CommsJam" niteliği: StealService çalındı
	             uyarısını göndermiyor.

	StealService bu servisi require ETMİYOR, yalnızca nitelikleri okuyor;
	bağımlılık tek yönlü.

	═══ GÜVENLİK ══════════════════════════════════════════════════════════

	Tek remote: "SabotageAction"(action, id, targetUserId?).
	  "buy" — oyuncunun KENDİ parasını harcıyor, fiyat sunucuda
	          (gelire göre), yığın sınırı sunucuda.
	  "use" — envanterdeki bir eşyayı harcıyor. Hedef sunucuda doğrulanıyor:
	          kendisi olamaz, üssü olmalı, kaidesinde en az bir karakter
	          olmalı, dokunulmazlıkta olmamalı. Kullanıcı başına 25 dk bekleme
          var (profilde, unix saati).
	Hiçbiri bedava bir şey VERMİYOR.

	İstemciye nitelikler: oyuncuda "Sabotages" ("Blackout=2,LockJam=0,..."),
	"SabotageReadyAt" (unix; istemci GetServerTimeNow ile karşılaştırıyor),
	hedef oyuncuda "SabotageShieldUntil" (sunucu saati; seçici "korumalı"
	yazıyor — istemci üs sahipliğini bilmiyor, o yüzden oyuncuda).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local PlotService = require(script.Parent.PlotService)

local SabotageService = {}

local NOTIFY_KIND = "sabotage"
SabotageService.NotifyKind = NOTIFY_KIND

local notifyRemote: RemoteEvent
local lastAction: { [Player]: number } = {}
-- Üs -> son sabotaj zamanı (os.clock). Dokunulmazlık buradan.
local lastHitAt: { [Model]: number } = {}
-- Süre bitince yalnızca EN SON uygulamanın sıfırlaması için sayaç:
-- üs ya da oyuncu -> sabotaj kimliği -> sayaç
local tokens: { [Instance]: { [string]: number } } = {}
local ACTION_DEBOUNCE = 0.25

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError, NOTIFY_KIND)
	end
end

local function nextToken(holder: Instance, id: string): number
	local map = tokens[holder] or {}
	tokens[holder] = map
	map[id] = (map[id] or 0) + 1
	return map[id]
end

local function holderOf(id: string, plot: Model, victim: Player): Instance
	return if id == "CommsJam" then victim else plot
end

-- ─── Etkiler ────────────────────────────────────────────────────────────────

--[[
	Üssün ışıklarını söndürür ya da geri yakar. Kaidelerdeki karakterlerin
	neon parçalarına dokunulmuyor (onlar karakter, lamba değil); kilit
	düğmesi de yanık kalıyor — karanlıkta tek kırmızı ışık, konsolun
	yerini belli ediyor.
]]
local function setLights(plot: Model, on: boolean)
	local podiums = plot:FindFirstChild("Podiums")
	for _, d in plot:GetDescendants() do
		if podiums and d:IsDescendantOf(podiums) then
			continue
		end
		if d:IsA("Light") then
			if on then
				if d:GetAttribute("SabotageOff") then
					d.Enabled = true
					d:SetAttribute("SabotageOff", nil)
				end
			elseif d.Enabled and d.Parent and d.Parent.Name ~= "LockButton" then
				d.Enabled = false
				d:SetAttribute("SabotageOff", true)
			end
		elseif d:IsA("BasePart") then
			if on then
				if d:GetAttribute("SabotageOff") then
					d.Material = Enum.Material.Neon
					d:SetAttribute("SabotageOff", nil)
				end
			elseif d.Material == Enum.Material.Neon and d.Name ~= "LockButton" then
				d.Material = Enum.Material.SmoothPlastic
				d:SetAttribute("SabotageOff", true)
			end
		end
	end
end

local function endEffect(plot: Model, victim: Player, id: string, token: number)
	local map = tokens[holderOf(id, plot, victim)]
	if not map or map[id] ~= token then
		return
	end
	if id == "Blackout" then
		if plot.Parent then
			plot:SetAttribute("Blackout", nil)
			setLights(plot, true)
		end
	elseif id == "LockJam" then
		if plot.Parent then
			plot:SetAttribute("LockJam", nil)
		end
	elseif id == "CommsJam" then
		victim:SetAttribute("CommsJam", nil)
	end
	if victim.Parent then
		notify(victim, "Sabotage cleared", false)
	end
end

local function apply(def: Config.SabotageDef, plot: Model, victim: Player)
	local token = nextToken(holderOf(def.id, plot, victim), def.id)
	if def.id == "Blackout" then
		plot:SetAttribute("Blackout", true)
		setLights(plot, false)
	elseif def.id == "LockJam" then
		plot:SetAttribute("LockJam", true)
		if plot:GetAttribute("Locked") then
			local usedAt = plot:GetAttribute("LockUsedAt")
			task.delay(Config.LockJamDropDelay, function()
				-- Arada yeniden kilitlenmediyse (aynı kilit hâlâ açıksa) düşür
				if plot.Parent and plot:GetAttribute("LockUsedAt") == usedAt then
					plot:SetAttribute("Locked", false)
				end
			end)
		end
	else
		victim:SetAttribute("CommsJam", true)
	end
	task.delay(def.duration, endEffect, plot, victim, def.id, token)
end

-- ─── İşlemler ───────────────────────────────────────────────────────────────

--[[ Envanteri istemcinin okuyacağı niteliğe yazar. ]]
function SabotageService.Publish(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local parts = {}
	for _, def in Config.Sabotages do
		table.insert(parts, string.format("%s=%d", def.id, profile.sabotages[def.id] or 0))
	end
	player:SetAttribute("Sabotages", table.concat(parts, ","))
	player:SetAttribute("SabotageReadyAt", profile.lastSabotageAt + Config.SabotageUserCooldown)
end

function SabotageService.GetCount(player: Player, id: string): number
	local profile = DataService.Get(player)
	return if profile then profile.sabotages[id] or 0 else 0
end

--[[ Satın alır. Parası yoksa, yığın doluysa ya da kimlik bilinmiyorsa false. ]]
function SabotageService.TryBuy(player: Player, id: string): boolean
	local def = Config.GetSabotage(id)
	local profile = DataService.Get(player)
	if not (def and profile) then
		return false
	end
	local have = profile.sabotages[id] or 0
	if have >= Config.SabotageMaxStack then
		notify(player, string.format("You can hold %d %s at most", Config.SabotageMaxStack, def.name), true)
		return false
	end
	local price = Config.GetSabotagePrice(def, EconomyService.GetIncome(player))
	if not EconomyService.TrySpend(player, price) then
		notify(player, string.format("You need $%s for %s", Config.FormatCash(price), def.name), true)
		return false
	end
	profile.sabotages[id] = have + 1
	SabotageService.Publish(player)
	DataService.RequestSave(player)
	notify(player, string.format("Bought %s", def.name), false)
	return true
end

--[[
	Kullanır. Sebebini döner: "ok" | "unknown" | "none" | "self" |
	"target" | "empty" | "immune" | "cooldown". Testler sebebe bakıyor.
	Oyuncu beklemesi unix saatiyle (profilde), üs dokunulmazlığı os.clock
	ile; `now` / `unixNow` testlerin saati ilerletmesi için.
]]
function SabotageService.TryUse(player: Player, id: string, target: Player?, now: number?, unixNow: number?): string
	local def = Config.GetSabotage(id)
	local profile = DataService.Get(player)
	if not (def and profile) then
		return "unknown"
	end
	if (profile.sabotages[id] or 0) <= 0 then
		notify(player, string.format("You have no %s", def.name), true)
		return "none"
	end
	if target == player then
		return "self"
	end
	-- Bekleme hedeften önce: hedef ne olursa olsun cevap aynı
	local unix = unixNow or os.time()
	local waitLeft = profile.lastSabotageAt + Config.SabotageUserCooldown - unix
	if waitLeft > 0 then
		notify(player, string.format("Sabotage recharging (%s)", Config.FormatDuration(waitLeft)), true)
		return "cooldown"
	end
	local plot = target and PlotService.GetPlotOf(target)
	if not (target and target.Parent and plot) then
		notify(player, "That player has no base", true)
		return "target"
	end

	local hasUnit = false
	for _, podium in PlotService.GetPodiums(plot) do
		if PlotService.IsOccupied(podium) then
			hasUnit = true
			break
		end
	end
	if not hasUnit then
		notify(player, string.format("%s has nothing to steal yet", target.DisplayName), true)
		return "empty"
	end

	local t = now or os.clock()
	local hitAt = lastHitAt[plot]
	if hitAt and t - hitAt < Config.SabotageTargetImmunity then
		notify(player, string.format("%s's base is shielded for %ds", target.DisplayName,
			math.ceil(Config.SabotageTargetImmunity - (t - hitAt))), true)
		return "immune"
	end

	profile.sabotages[id] -= 1
	profile.lastSabotageAt = unix
	lastHitAt[plot] = t
	target:SetAttribute("SabotageShieldUntil", workspace:GetServerTimeNow() + Config.SabotageTargetImmunity)
	apply(def, plot, target)
	SabotageService.Publish(player)
	DataService.RequestSave(player)

	notify(player, string.format("%s used on %s's base (%ds)", def.name, target.DisplayName, def.duration), false)
	local what = if id == "Blackout" then "turned off your lights"
		elseif id == "LockJam" then "jammed your lock"
		else "jammed your comms (no steal alerts)"
	notify(target, string.format("SABOTAGE! %s %s for %ds", player.DisplayName, what, def.duration), true)
	return "ok"
end

--[[
	Testler için: etkiyi doğrulamadan uygular. Testte tek oyuncu var ve
	TryUse kendine kullanmayı (doğru olarak) reddediyor.
]]
function SabotageService._Apply(id: string, victim: Player)
	local def = Config.GetSabotage(id)
	local plot = PlotService.GetPlotOf(victim)
	if def and plot then
		apply(def, plot, victim)
	end
end

--[[ Üsteki bütün etkileri ve dokunulmazlığı hemen kaldırır. ]]
local function clearPlot(plot: Model)
	tokens[plot] = nil
	lastHitAt[plot] = nil
	plot:SetAttribute("Blackout", nil)
	plot:SetAttribute("LockJam", nil)
	setLights(plot, true)
	local owner = PlotService.GetOwner(plot)
	if owner then
		owner:SetAttribute("SabotageShieldUntil", nil)
	end
end

--[[ Testler için: bekleme ve dokunulmazlıkları sıfırlar, etkileri kaldırır. ]]
function SabotageService._Reset(player: Player, target: Player?)
	for _, p in { player, target } do
		local plot = p and PlotService.GetPlotOf(p)
		if plot then
			clearPlot(plot)
		end
		if p then
			tokens[p] = nil
			p:SetAttribute("CommsJam", nil)
		end
	end
end

local function onAction(player: Player, action: any, id: any, targetUserId: any)
	if typeof(action) ~= "string" or typeof(id) ~= "string" or #id > 40 then
		return
	end
	local now = os.clock()
	if now - (lastAction[player] or 0) < ACTION_DEBOUNCE then
		return
	end
	lastAction[player] = now

	if action == "buy" then
		SabotageService.TryBuy(player, id)
	elseif action == "use" and typeof(targetUserId) == "number" then
		SabotageService.TryUse(player, id, Players:GetPlayerByUserId(targetUserId))
	end
end

function SabotageService.Start()
	notifyRemote = Net.Get("Notify")
	Net.Get("SabotageAction").OnServerEvent:Connect(onAction)

	local function onPlayer(player: Player)
		task.spawn(function()
			if DataService.WaitForProfile(player) then
				SabotageService.Publish(player)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		lastAction[player] = nil
		tokens[player] = nil
		--[[
			Üs yeni sahibine sabotajlı geçmesin. PlotService sahipliği bu
			olaydan önce silmiş olabilir, o yüzden sahibi yok olan ya da bu
			oyuncu olan bütün üsler temizleniyor.
		]]
		for _, plot in PlotService.GetAllPlots() do
			local owner = PlotService.GetOwner(plot)
			if (owner == nil or owner == player) and tokens[plot] then
				clearPlot(plot)
			end
		end
	end)
end

return SabotageService
