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
local EconomyService = require(script.Parent.EconomyService)

local StealService = {}

local notifyRemote: RemoteEvent
local alertRemote: RemoteEvent

type Carry = {
	model: Model,
	unitId: string,
	mutationId: string?,
	victim: Player?,
}

local carrying: { [Player]: Carry } = {}
local lastStealAt: { [Player]: number } = {}

local function notify(player: Player, text: string, isError: boolean)
	notifyRemote:FireClient(player, text, isError)
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
		humanoid.WalkSpeed = Config.CarryWalkSpeed
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
			notify(victim, "Hırsız yakalandı, karakterin geri döndü", false)
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

	local podium = PlotService.FindEmptyPodium(plot)
	if not podium then
		return -- yer açılana kadar taşımaya devam eder
	end

	PlotService.PlaceUnit(podium, carry.unitId, carry.mutationId)
	EconomyService.AddStealCount(player)

	local def = Config.GetUnit(carry.unitId)
	notify(player, string.format("%s üssüne eklendi", if def then def.name else carry.unitId), false)

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
		notify(thief, "Önce bir üs sahibi olman gerek", true)
		return
	end

	if thiefPlot == victimPlot then
		notify(thief, "Kendi karakterini çalamazsın", true)
		return
	end

	if carrying[thief] then
		notify(thief, "Zaten bir karakter taşıyorsun", true)
		return
	end

	if not PlotService.IsOccupied(podium) then
		return
	end

	if victimPlot:GetAttribute("Locked") then
		notify(thief, "Bu üs kilitli", true)
		return
	end

	local placedAt = podium:GetAttribute("PlacedAt") :: number
	if os.clock() - placedAt < Config.SafeSeconds then
		notify(thief, "Karakter henüz korumada", true)
		return
	end

	local cooldownLeft = Config.StealCooldown - (os.clock() - (lastStealAt[thief] or -math.huge))
	if cooldownLeft > 0 then
		notify(thief, string.format("%d sn bekle", math.ceil(cooldownLeft)), true)
		return
	end

	if not PlotService.FindEmptyPodium(thiefPlot) then
		notify(thief, "Boş kaiden yok, önce yer aç", true)
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

	local victim = PlotService.GetOwner(victimPlot)
	carrying[thief] = { model = model, unitId = unitId, mutationId = mutationId, victim = victim }
	lastStealAt[thief] = os.clock()

	local def = Config.GetUnit(unitId)
	local unitName = if def then def.name else unitId

	notify(thief, string.format("%s çalındı! Üssüne kaç", unitName), false)
	if victim then
		alertRemote:FireClient(victim, thief.DisplayName, unitName)
	end
end

-- ─── Promptlar ──────────────────────────────────────────────────────────────

local function setupPodiumPrompt(podium: Part)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "StealPrompt"
	prompt.ActionText = "Çal"
	prompt.ObjectText = "Hain ol"
	prompt.HoldDuration = Config.StealHoldTime
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = podium

	local function refresh()
		prompt.Enabled = PlotService.IsOccupied(podium)
	end

	podium:GetAttributeChangedSignal("UnitId"):Connect(refresh)
	refresh()

	prompt.Triggered:Connect(function(player)
		onStealPrompt(podium, player)
	end)
end

local function setupLockPrompt(plot: Model)
	local sign = plot:FindFirstChild("Sign")
	if not (sign and sign:IsA("BasePart")) then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LockPrompt"
	prompt.ActionText = "Kilitle"
	prompt.ObjectText = string.format("%d sn koruma", Config.LockDuration)
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = sign

	prompt.Triggered:Connect(function(player)
		if PlotService.GetOwner(plot) ~= player then
			notify(player, "Bu senin üssün değil", true)
			return
		end

		local usedAt = plot:GetAttribute("LockUsedAt") :: number
		local cooldownLeft = Config.LockCooldown - (os.clock() - usedAt)
		if usedAt > 0 and cooldownLeft > 0 then
			notify(player, string.format("Kilit %d sn sonra hazır", math.ceil(cooldownLeft)), true)
			return
		end

		plot:SetAttribute("Locked", true)
		plot:SetAttribute("LockUsedAt", os.clock())
		notify(player, string.format("Üs %d sn kilitlendi", Config.LockDuration), false)

		task.delay(Config.LockDuration, function()
			if plot.Parent then
				plot:SetAttribute("Locked", false)
				if PlotService.GetOwner(plot) == player and player.Parent then
					notify(player, "Kilit açıldı", true)
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
