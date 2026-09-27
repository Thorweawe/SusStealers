--!strict
--[[
	Uzay kapsülü: üssün arkasındaki cam tüp (PlotService kuruyor, model
	shared/CapsuleModel). Sahibi içinde durdukça uzay hızı artıyor —
	"uzay yürüyüşü simülasyonu". Hız profilde kalıcı (spaceSpeed) ve
	oyuncunun "SpaceSpeed" niteliğinde; uçuş (SpaceFX) ve canavar
	kovalaması (SpaceService) onu okuyor.

	Kazanç Config.GetCapsuleGain(seviye, hız): seviye SpaceCapsule
	yükseltmesi (UpgradeService, kapsülün yanındaki konsoldan da alınıyor).

	Oyuncu nitelikleri:
	  SpaceSpeed  — uzay hızı (iki ondalık)
	  InCapsule   — şu an kendi kapsülünde antrenmanda
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local PromptGuard = require(script.Parent.PromptGuard)
local UpgradeService = require(script.Parent.UpgradeService)

local CapsuleService = {}

CapsuleService.NotifyKind = "upgrade"

local UPGRADE_ID = "SpaceCapsule"

local notifyRemote: RemoteEvent? = nil
local paused = false
-- Mini oyun sınırları: antrenmana başlama anı ve son bonus
local trainingSince: { [Player]: number } = {}
local lastCatch: { [Player]: number } = {}

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote and player.Parent then
		notifyRemote:FireClient(player, text, isError, CapsuleService.NotifyKind)
	end
end

local function publish(player: Player, speed: number)
	local rounded = math.floor(speed * 100 + 0.5) / 100
	if player:GetAttribute("SpaceSpeed") ~= rounded then
		player:SetAttribute("SpaceSpeed", rounded)
	end
end

function CapsuleService.GetSpeed(player: Player): number
	local profile = DataService.Get(player)
	return if profile then profile.spaceSpeed else Config.Space.BaseSpeed
end

--[[ Hızı değiştirir (test, kod ödülü). Tabanın altına inmiyor. ]]
function CapsuleService.SetSpeed(player: Player, speed: number)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	profile.spaceSpeed = math.clamp(speed, Config.Space.BaseSpeed, Config.Space.MaxSpeed)
	publish(player, profile.spaceSpeed)
end

--[[ Karakter kapsülün hacminde mi (dikey silindir). ]]
local function insideCapsule(capsule: Instance, position: Vector3): boolean
	local zone = capsule:FindFirstChild("Zone")
	if not (zone and zone:IsA("BasePart")) then
		return false
	end
	local radius = (zone:GetAttribute("Radius") :: number?) or 4
	local d = position - zone.Position
	-- Silindirin ekseni Y (parça X'e yatık kurulu, boyu Size.X)
	return Vector2.new(d.X, d.Z).Magnitude <= radius and math.abs(d.Y) <= zone.Size.X / 2 + 1
end

local function refreshCapsule(plot: Model)
	local capsule = plot:FindFirstChild("Capsule")
	if not capsule then
		return
	end
	local owner = PlotService.GetOwner(plot)
	local level = if owner then UpgradeService.GetLevel(owner, UPGRADE_ID) else 0
	local screen = capsule:FindFirstChild("Screen")
	local info = screen and screen:FindFirstChild("Info")
	local label = info and info:FindFirstChild("Level")
	if label and label:IsA("TextLabel") then
		local text = if owner then string.format("LEVEL %d", level) else "NO OWNER"
		if label.Text ~= text then
			label.Text = text
		end
	end
	local console = capsule:FindFirstChild("Console")
	local prompt = console and console:FindFirstChild("CapsulePrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		local cost: number? = nil
		if owner then
			local profile = DataService.Get(owner)
			local floors = if profile then Config.GetUnlockedFloors(profile.floorsBought) else 1
			cost = Config.GetUpgradeCost(UPGRADE_ID, level, floors)
		end
		local text = if not owner then "Space Capsule" elseif cost then string.format("Space Capsule  $%s", Config.FormatCash(cost)) else "Space Capsule  MAX"
		if prompt.ObjectText ~= text then
			prompt.ObjectText = text
		end
	end
end

local function setupConsole(plot: Model)
	local capsule = plot:FindFirstChild("Capsule")
	local console = capsule and capsule:FindFirstChild("Console")
	if not (console and console:IsA("BasePart")) or console:FindFirstChild("CapsulePrompt") then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CapsulePrompt"
	prompt.ActionText = "Upgrade"
	prompt.ObjectText = "Space Capsule"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	-- İstemci (PromptFilter OWN_ONLY) başkasının üssünde gizliyor
	prompt.Parent = console
	PromptGuard.Connect(prompt, function(player)
		if PlotService.GetOwner(plot) ~= player then
			notify(player, "This isn't your capsule", true)
			return
		end
		if UpgradeService.TryUpgrade(player, UPGRADE_ID) then
			refreshCapsule(plot)
		end
	end)
end

local function tick(dt: number)
	for _, plot in PlotService.GetAllPlots() do
		setupConsole(plot)
		refreshCapsule(plot)
		local capsule = plot:FindFirstChild("Capsule")
		local owner = PlotService.GetOwner(plot)
		local training = false
		if capsule and owner then
			local character = owner.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local profile = DataService.Get(owner)
			if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 and profile
				and insideCapsule(capsule, root.Position) then
				training = true
				local level = UpgradeService.GetLevel(owner, UPGRADE_ID)
				local gain = Config.GetCapsuleGain(level, profile.spaceSpeed) * dt
				profile.spaceSpeed = math.min(Config.Space.MaxSpeed, profile.spaceSpeed + gain)
				publish(owner, profile.spaceSpeed)
				owner:SetAttribute("CapsuleGain", math.floor(gain / dt * 1000 + 0.5) / 1000)
			end
			if (owner:GetAttribute("InCapsule") == true) ~= training then
				owner:SetAttribute("InCapsule", if training then true else nil)
				trainingSince[owner] = if training then os.clock() else nil
			end
		end
		local source = capsule and capsule:FindFirstChild("WarpSource")
		local warp = source and source:FindFirstChild("Warp")
		if warp and warp:IsA("ParticleEmitter") and warp.Enabled ~= training then
			warp.Enabled = training
		end
	end
end

--[[
	Mini oyun bonusu (istemci CapsuleCatch gönderiyor). Kendi kapsülünde
	antrenmanda, ısınma ve bekleme süreleri geçmiş olmalı. Verilen bonusu
	döner (reddedilirse nil).
]]
function CapsuleService.TryCatch(player: Player): number?
	local c = Config.Capsule
	local now = os.clock()
	local since = trainingSince[player]
	if player:GetAttribute("InCapsule") ~= true or not since or now - since < c.CatchWarmup then
		return nil
	end
	if now - (lastCatch[player] or -math.huge) < c.CatchCooldown then
		return nil
	end
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	lastCatch[player] = now
	local level = UpgradeService.GetLevel(player, UPGRADE_ID)
	local bonus = Config.GetCapsuleGain(level, profile.spaceSpeed) * c.CatchBonusSeconds
	profile.spaceSpeed = math.min(Config.Space.MaxSpeed, profile.spaceSpeed + bonus)
	publish(player, profile.spaceSpeed)
	return bonus
end

-- ─── Testler için ───────────────────────────────────────────────────────────

function CapsuleService._ResetCatch(player: Player, trainingAgo: number?)
	lastCatch[player] = nil
	trainingSince[player] = if trainingAgo then os.clock() - trainingAgo else nil
end

function CapsuleService._Tick(dt: number)
	tick(dt)
end

--[[ Testler hızı elle kurcalıyor; periyodik antrenman araya girmesin. ]]
function CapsuleService.SetPaused(value: boolean)
	paused = value
end

function CapsuleService.Start()
	notifyRemote = Net.Get("Notify")

	local function onPlayer(player: Player)
		task.spawn(function()
			local profile = DataService.WaitForProfile(player, 30)
			if profile and player.Parent then
				publish(player, profile.spaceSpeed)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		trainingSince[player] = nil
		lastCatch[player] = nil
	end)

	Net.Get("CapsuleCatch").OnServerEvent:Connect(function(player)
		CapsuleService.TryCatch(player)
	end)

	task.spawn(function()
		local step = Config.Capsule.Tick
		while true do
			task.wait(step)
			if paused then
				continue
			end
			local ok, err = pcall(tick, step)
			if not ok then
				warn("CapsuleService:", err)
			end
		end
	end)
end

return CapsuleService
