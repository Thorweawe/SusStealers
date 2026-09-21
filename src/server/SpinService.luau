--!strict
-- Şans çarkı: günde bir bedava çevirme, fazlası Robux ile.
--
-- Çarkın geometrisi ve dönüşü dekorda hazır (workspace.Decor.Wheel).
-- Parçalar SpinSpeed niteliğiyle istemci tarafında dönüyor; burada o
-- niteliği geçici yükseltip bırakıyoruz. Böylece animasyon için ağ
-- trafiği yok, sunucu sadece bir sayı yazıyor.
--
-- Ödüller oyuncunun kendi gelirinin katı. Sabit tutar olsaydı geç oyunda
-- anlamsızlaşır, erken oyunda dengeyi bozardı.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PlotService = require(script.Parent.PlotService)
local PromptGuard = require(script.Parent.PromptGuard)
local EconomyService = require(script.Parent.EconomyService)
local DataService = require(script.Parent.DataService)
local ConveyorService = require(script.Parent.ConveyorService)
local MonetizationService = require(script.Parent.MonetizationService)
local BadgeService = require(script.Parent.BadgeService)

local SpinService = {}

local rng = Random.new()
local notifyRemote: RemoteEvent

-- Çark dönerken ikinci çevirme kabul edilmiyor; ödül animasyonu bitsin
local spinning = false
local spinPrompt: ProximityPrompt? = nil

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote then
		notifyRemote:FireClient(player, text, isError)
	end
end

-- ─── Bedava hak ─────────────────────────────────────────────────────────────

--[[ Bedava çevirmeye kaç saniye kaldı. 0 ise hak hazır. ]]
function SpinService.GetCooldown(player: Player): number
	local profile = DataService.Get(player)
	if not profile then
		return math.huge
	end

	local elapsed = os.time() - profile.lastSpinAt
	local total = Config.SpinCooldownHours * 3600
	return math.max(0, total - elapsed)
end

-- ─── Ödül ───────────────────────────────────────────────────────────────────

--[[
	Ödülü uygular ve oyuncuya gösterilecek metni döner.
	Uygulanamazsa nil döner; çağıran hakkı harcamamalı.
]]
local function grantReward(player: Player, reward: Config.SpinReward): string?
	if reward.kind == "cash" then
		local amount = Config.GetSpinCash(reward, EconomyService.GetIncome(player))
		EconomyService.AddCash(player, amount)
		return string.format("$%s", Config.FormatCash(amount))

	elseif reward.kind == "spawn" then
		if not ConveyorService.SpawnFor(player) then
			return nil
		end
		return "a unit on your conveyor"

	elseif reward.kind == "mutation" then
		if not ConveyorService.GrantLuckyRoll(player) then
			return nil
		end
		return "a guaranteed mutation"

	elseif reward.kind == "unit" then
		--[[
			Doğrudan kaideye konan bedava karakter. Boş kaide yoksa
			ödülü kaybetmesin diye nakde çevriliyor.
		]]
		local plot = PlotService.GetPlotOf(player)
		local podium = plot and PlotService.FindEmptyPodium(plot)
		local def = Config.RollUnit(rng, 0)

		if podium and PlotService.PlaceUnit(podium, def.id, nil) then
			if def.rarity == "Secret" then
				BadgeService.Award(player, "SecretFind")
			end
			return def.name
		end

		local amount = Config.GetPrice(def.id, nil)
		EconomyService.AddCash(player, amount)
		return string.format("$%s (no free podium)", Config.FormatCash(amount))
	end

	return nil
end

-- ─── Çevirme ────────────────────────────────────────────────────────────────

local function animate()
	local decor = workspace:FindFirstChild("Decor")
	local wheel = decor and decor:FindFirstChild("Wheel")
	if not wheel then
		return
	end

	-- Parçaların kendi hızları farklı olabilir; oranı koruyarak hızlandır
	local originals: { [BasePart]: number } = {}
	for _, part in wheel:GetDescendants() do
		if part:IsA("BasePart") then
			local speed = part:GetAttribute("SpinSpeed")
			if typeof(speed) == "number" then
				originals[part] = speed
				part:SetAttribute("SpinSpeed", speed * 14)
			end
		end
	end

	task.delay(Config.SpinDuration, function()
		for part, speed in originals do
			if part.Parent then
				part:SetAttribute("SpinSpeed", speed)
			end
		end
		spinning = false
	end)
end

--[[
	Çarkı çevirir. free true ise günlük hak harcanıyor, false ise
	Robux ürününden geliyor ve hak kontrolü yapılmıyor.
]]
function SpinService.Spin(player: Player, free: boolean): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end

	if not PlotService.GetPlotOf(player) then
		notify(player, "You need a base first", true)
		return false
	end

	if spinning then
		notify(player, "The wheel is already spinning", true)
		return false
	end

	if free then
		local remaining = SpinService.GetCooldown(player)
		if remaining > 0 then
			local hours = math.floor(remaining / 3600)
			local minutes = math.ceil((remaining % 3600) / 60)
			notify(player, string.format("Next free spin in %dh %dm", hours, minutes), true)
			return false
		end
	end

	local reward = Config.RollSpinReward(rng)
	local description = grantReward(player, reward)
	if not description then
		notify(player, "Could not grant the prize - try again", true)
		return false
	end

	-- Ödül verildikten sonra hakkı harca: veremezsek hak da gitmesin
	DataService.Bump(player, "spins")
	if free then
		profile.lastSpinAt = os.time()
		DataService.Save(player)
	end

	spinning = true
	animate()

	notify(player, string.format("%s! You won %s", reward.name, description), false)
	BadgeService.Award(player, "FirstSpin")
	return true
end

-- ─── Prompt ─────────────────────────────────────────────────────────────────

local function setupPrompt()
	local decor = workspace:FindFirstChild("Decor")
	local wheel = decor and decor:FindFirstChild("Wheel")
	if not wheel then
		warn("[Spin] workspace.Decor.Wheel bulunamadi, cark promptu kurulmadi")
		return
	end

	-- Göbek çarkın ortasında ve dönmüyor; prompt için en uygun yer
	local anchor = wheel:FindFirstChild("WheelHub") or wheel:FindFirstChild("WheelPlinth")
	if not (anchor and anchor:IsA("BasePart")) then
		warn("[Spin] Cark govdesi bulunamadi")
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SpinPrompt"
	prompt.ActionText = "Lucky Spin"
	prompt.ObjectText = "Free"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = anchor

	spinPrompt = prompt

	PromptGuard.Connect(prompt, function(player)
		SpinService.Spin(player, true)
	end)

	--[[
		Prompt herkese ortak, bekleme süresi kişisel. En yakın oyuncunun
		durumunu yazmak yanıltıcı olurdu; onun yerine genel bir metin
		duruyor ve kişisel süre tetiklendiğinde bildirimle söyleniyor.
	]]
	task.spawn(function()
		while true do
			task.wait(5)
			local ready = 0
			for _, player in Players:GetPlayers() do
				if SpinService.GetCooldown(player) <= 0 then
					ready += 1
				end
			end
			prompt.ObjectText = if ready > 0 then "Free spin ready" else "Daily"
		end
	end)
end

function SpinService.Start()
	notifyRemote = Net.Get("Notify")

	MonetizationService.RegisterGranter("spin", function(player)
		return SpinService.Spin(player, false)
	end)

	setupPrompt()
end

return SpinService
