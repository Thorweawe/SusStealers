--!strict
-- Çalma mekaniği: kaideden söküp taşıma, kendi üssüne bırakma ve kilit savunması.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local UnitModel = require(Shared.UnitModel)

local PlotService = require(script.Parent.PlotService)
local PromptGuard = require(script.Parent.PromptGuard)
local MonetizationService = require(script.Parent.MonetizationService)
local UpgradeService = require(script.Parent.UpgradeService)
local EconomyService = require(script.Parent.EconomyService)

local StealService = {}

local notifyRemote: RemoteEvent
local alertRemote: RemoteEvent

type Carry = {
	model: Model,
	unitId: string,
	mutationId: string?,
	victim: Player?,
	-- Işınlanarak taşımayı atlamayı engellemek için: nereden, ne zaman
	origin: Vector3,
	startedAt: number,
}

local carrying: { [Player]: Carry } = {}
local lastStealAt: { [Player]: number } = {}

local function notify(player: Player, text: string, isError: boolean)
	notifyRemote:FireClient(player, text, isError)
end

--[[ Oyuncunun taşıma hızı: yükseltme seviyesine göre. ]]
local function carrySpeedFor(player: Player): number
	return Config.GetCarryWalkSpeed(UpgradeService.GetLevel(player, "CarrySpeed"))
end

--[[
	Kilit süresi ve bekleme. Yükseltme ve gamepass birbirine eklenmiyor,
	hangisi daha iyiyse o geçerli — ikisini de alan iki kat avantaj
	kazanmasın.
]]
local function lockValuesFor(player: Player): (number, number)
	local duration, cooldown = Config.GetLockValues(UpgradeService.GetLevel(player, "LockPower"))

	if MonetizationService.HasPass(player, "StrongLock") then
		duration = math.max(duration, Config.PassStrongLockDuration)
		cooldown = math.min(cooldown, Config.PassStrongLockCooldown)
	end

	return duration, cooldown
end

-- ─── Taşıma ─────────────────────────────────────────────────────────────────

local function attachToBack(player: Player, unitId: string, mutationId: string?): Model?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and root and root:IsA("BasePart")) then
		return nil
	end

	local model = UnitModel.Build(unitId, mutationId)
	model.Name = "CarriedUnit"
	model:PivotTo(root.CFrame * CFrame.new(0, 3.5, 0.4))

	local primary = model.PrimaryPart :: BasePart
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.Massless = true

			if descendant ~= primary then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		end
	end

	local rootWeld = Instance.new("WeldConstraint")
	rootWeld.Part0 = root
	rootWeld.Part1 = primary
	rootWeld.Parent = primary

	model.Parent = character

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = carrySpeedFor(player)
	end

	return model
end

local function stopCarrying(player: Player)
	local carry = carrying[player]
	if not carry then
		return
	end

	if carry.model.Parent then
		carry.model:Destroy()
	end
	carrying[player] = nil

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Config.NormalWalkSpeed
	end
end

--[[ Taşınan karakteri sahibine geri verir (ölüm / çıkış durumunda). ]]
local function returnToVictim(player: Player)
	local carry = carrying[player]
	if not carry then
		return
	end

	local victim = carry.victim
	if victim and victim.Parent then
		local plot = PlotService.GetPlotOf(victim)
		local podium = plot and PlotService.FindEmptyPodium(plot)

		if podium then
			PlotService.PlaceUnit(podium, carry.unitId, carry.mutationId)
			notify(victim, "Thief down! Your unit is back", false)
		else
			-- Boş kaide yoksa karakteri sessizce yok etmek yerine parasını iade et.
			-- Kurban çalınmayı takiben o slotu doldurmuş olabiliyor; eski hali
			-- oyuncunun en pahalı karakterini iz bırakmadan siliyordu.
			local refund = Config.GetPrice(carry.unitId, carry.mutationId)
			EconomyService.AddCash(victim, refund)
			notify(victim, string.format(
				"Thief down! No free podium - refunded $%s",
				Config.FormatCash(refund)
			), false)
		end
	end

	stopCarrying(player)
end

-- ─── Bırakma ────────────────────────────────────────────────────────────────

local function isInsidePlot(position: Vector3, plot: Model): boolean
	local base = plot:FindFirstChild("Base")
	if not (base and base:IsA("BasePart")) then
		return false
	end

	local delta = position - base.Position
	return math.abs(delta.X) <= Config.PlotSize.X / 2
		and math.abs(delta.Z) <= Config.PlotSize.Z / 2
		and math.abs(delta.Y) <= 30
end

local function tryDeposit(player: Player)
	local carry = carrying[player]
	if not carry then
		return
	end

	local plot = PlotService.GetPlotOf(player)
	if not plot then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end

	if not isInsidePlot(root.Position, plot) then
		return
	end

	-- Bu mesafe bu sürede yürünebilir miydi? Karakterin konumu istemcinin
	-- elinde olduğu için ışınlanan biri üsse anında varabiliyor. Reddetmek
	-- yerine bekletiyoruz: süre dolduğunda bırakma kendiliğinden olur.
	-- Böylece exploit hiçbir şey kazandırmaz ama meşru oyuncu da takılmaz.
	-- Hız yükseltmesi olan oyuncu gerçekten daha hızlı gidiyor; taban hızla
	-- hesaplarsak onu haksız yere bekletiriz.
	local travelled = (root.Position - carry.origin).Magnitude
	local minimumTime = travelled / carrySpeedFor(player) * Config.CarryTravelTolerance
	if os.clock() - carry.startedAt < minimumTime then
		return
	end

	local podium = PlotService.FindEmptyPodium(plot)
	if not podium then
		return -- yer açılana kadar taşımaya devam eder
	end

	PlotService.PlaceUnit(podium, carry.unitId, carry.mutationId)
	EconomyService.AddStealCount(player)

	local def = Config.GetUnit(carry.unitId)
	notify(player, string.format("%s added to your base", if def then def.name else carry.unitId), false)

	stopCarrying(player)
end

-- ─── Çalma ──────────────────────────────────────────────────────────────────

local function onStealPrompt(podium: Part, thief: Player)
	local victimPlot = PlotService.GetPlotFromDescendant(podium)
	if not victimPlot then
		return
	end

	local thiefPlot = PlotService.GetPlotOf(thief)
	if not thiefPlot then
		notify(thief, "You need a base first", true)
		return
	end

	if thiefPlot == victimPlot then
		notify(thief, "That is your own unit", true)
		return
	end

	if carrying[thief] then
		notify(thief, "You are already carrying one", true)
		return
	end

	if not PlotService.IsOccupied(podium) then
		return
	end

	if victimPlot:GetAttribute("Locked") then
		notify(thief, "This base is locked", true)
		return
	end

	-- Dokunulmazlık süresi kurbanın Unit Guard seviyesine göre
	local victimOwner = PlotService.GetOwner(victimPlot)
	local guardLevel = if victimOwner then UpgradeService.GetLevel(victimOwner, "UnitGuard") else 0
	local safeSeconds = Config.GetSafeSeconds(guardLevel)

	local placedAt = podium:GetAttribute("PlacedAt") :: number
	if os.clock() - placedAt < safeSeconds then
		notify(thief, "Unit is still protected", true)
		return
	end

	local cooldownLeft = Config.StealCooldown - (os.clock() - (lastStealAt[thief] or -math.huge))
	if cooldownLeft > 0 then
		notify(thief, string.format("Wait %d s", math.ceil(cooldownLeft)), true)
		return
	end

	if not PlotService.FindEmptyPodium(thiefPlot) then
		notify(thief, "No free podium - make room first", true)
		return
	end

	local unitId, mutationId = PlotService.ClearUnit(podium)
	if not unitId then
		return
	end

	local model = attachToBack(thief, unitId, mutationId)
	if not model then
		-- Karakter yoksa geri koy, kayıp olmasın
		PlotService.PlaceUnit(podium, unitId, mutationId)
		return
	end

	local victim = victimOwner
	carrying[thief] = {
		model = model,
		unitId = unitId,
		mutationId = mutationId,
		victim = victim,
		origin = podium.Position,
		startedAt = os.clock(),
	}
	lastStealAt[thief] = os.clock()

	local def = Config.GetUnit(unitId)
	local unitName = if def then def.name else unitId

	notify(thief, string.format("Stole %s! Run to your base", unitName), false)
	if victim then
		alertRemote:FireClient(victim, thief.DisplayName, unitName)
	end
end

-- ─── Promptlar ──────────────────────────────────────────────────────────────

local function setupPodiumPrompt(podium: Part)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "Steal"
	prompt.ObjectText = "Be the impostor"
	prompt.HoldDuration = Config.StealHoldTime
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = podium

	--[[
		Kaidedeki karakter değiştikçe promptu güncelle. HoldDuration
		karaktere göre değiştiği için yalnızca yaratılışta ayarlamak
		yetmiyor: kaideye yeni bir karakter konduğunda öncekinin süresi
		kalırdı.
	]]
	local function refresh()
		local unitId = podium:GetAttribute("UnitId") :: string
		if unitId == "" then
			prompt.Enabled = false
			return
		end

		local mutationId = podium:GetAttribute("MutationId") :: string
		local hold = Config.GetStealHoldTime(unitId, if mutationId == "" then nil else mutationId)

		-- Hızlı Çalma pass'i kişiye özel, prompt ise herkese ortak.
		-- Burada taban süre yazılıyor; kişisel indirim tetiklenme anında
		-- PromptGuard'ın beklediği süreye yansıyor.
		prompt.HoldDuration = hold
		prompt.ObjectText = string.format("%.1fs", hold)
		prompt.Enabled = true
	end

	podium:GetAttributeChangedSignal("UnitId"):Connect(refresh)
	refresh()

	PromptGuard.Connect(prompt, function(player)
		onStealPrompt(podium, player)
	end, function(player)
		-- Hızlı Çalma pass'i olan daha kısa tutuyor
		return prompt.HoldDuration * MonetizationService.GetStealHoldMultiplier(player)
	end)
end

local function setupLockPrompt(plot: Model)
	local sign = plot:FindFirstChild("Sign")
	if not (sign and sign:IsA("BasePart")) then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LockPrompt"
	prompt.ActionText = "Lock"
	prompt.ObjectText = string.format("%d s protection", Config.LockDuration)
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = sign

	PromptGuard.Connect(prompt, function(player)
		if PlotService.GetOwner(plot) ~= player then
			notify(player, "Not your base", true)
			return
		end

		-- Güçlü Kilit pass'i süreyi uzatıp beklemeyi kısaltıyor
		local duration, cooldown = lockValuesFor(player)

		local usedAt = plot:GetAttribute("LockUsedAt") :: number
		local cooldownLeft = cooldown - (os.clock() - usedAt)
		if usedAt > 0 and cooldownLeft > 0 then
			notify(player, string.format("Lock ready in %d s", math.ceil(cooldownLeft)), true)
			return
		end

		plot:SetAttribute("Locked", true)
		plot:SetAttribute("LockUsedAt", os.clock())
		notify(player, string.format("Base locked for %d s", duration), false)

		task.delay(duration, function()
			if plot.Parent then
				plot:SetAttribute("Locked", false)
				if PlotService.GetOwner(plot) == player and player.Parent then
					notify(player, "Lock expired", true)
				end
			end
		end)
	end)
end

-- ─── Başlangıç ──────────────────────────────────────────────────────────────

function StealService.Start()
	notifyRemote = Net.Get("Notify")
	alertRemote = Net.Get("StealAlert")

	for _, plot in PlotService.GetAllPlots() do
		setupLockPrompt(plot)
		for _, podium in PlotService.GetPodiums(plot) do
			setupPodiumPrompt(podium)
		end
	end

	RunService.Heartbeat:Connect(function()
		for player in carrying do
			tryDeposit(player)
		end
	end)

	local function watchCharacter(player: Player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid") :: Humanoid
			humanoid.WalkSpeed = Config.NormalWalkSpeed
			humanoid.Died:Connect(function()
				returnToVictim(player)
			end)
		end)
	end

	for _, player in Players:GetPlayers() do
		watchCharacter(player)
	end
	Players.PlayerAdded:Connect(watchCharacter)

	Players.PlayerRemoving:Connect(function(player)
		returnToVictim(player)
		carrying[player] = nil
		lastStealAt[player] = nil
	end)
end

return StealService
