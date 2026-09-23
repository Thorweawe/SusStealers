--!strict
--[[
	Haritadaki oynanabilir görevler. Şimdilik bir tane: Weapons odasındaki
	"Clear Asteroids" (Among Us'taki görevin aynısı).

	Akış:
	  1. Oyuncu topçu konsolundaki promptu tetikler → başlangıç zamanı
	     SUNUCUDA yazılır. (İstemci kendi tetiklemesini görüp oyunu açıyor.)
	  2. Oyuncu 20 asteroidi vurunca istemci AsteroidsDone gönderir.
	  3. TryComplete doğrular: başlamış mı, yeterince sürmüş mü, çok eski
	     mi, bekleme süresi dolmuş mu, konsolun yakınında mı. Hepsi
	     tutarsa gelirle ölçekli küçük bir ödül.

	Sonucu istemci söylediği için ödül kasten küçük ve seyrek; sahte bir
	istek, oyunu oynamaktan fazlasını kazandıramıyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local EconomyService = require(script.Parent.EconomyService)
local PromptGuard = require(script.Parent.PromptGuard)

local MinigameService = {}

-- Bildirim sesi: ödül tınısı (Config.NotifyCues)
MinigameService.NotifyKind = "reward"

local startedAt: { [Player]: number } = {}
local lastReward: { [Player]: number } = {}
local console: BasePart? = nil
local notifyRemote: RemoteEvent? = nil

local function notify(player: Player, text: string)
	if notifyRemote then
		notifyRemote:FireClient(player, text, false, MinigameService.NotifyKind)
	end
end

--[[ Ödül: saniyelik gelirin belli katı, tabanlı. ]]
function MinigameService.RewardFor(player: Player): number
	local rules = Config.AsteroidTask
	return math.max(rules.minReward, math.floor(EconomyService.GetIncome(player) * rules.rewardSeconds))
end

--[[
	Oyuncu konsolun yakınında mı. Konsol yoksa (harita kurulmamış) kısıt
	uygulanmıyor. Ayrı fonksiyon: test karakteri konsola taşımak yerine
	bunu geçici olarak değiştiriyor (PetService.NearFuseMachine gibi).
]]
function MinigameService.NearConsole(player: Player): boolean
	if not (console and console.Parent) then
		return true
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	return (root.Position - console.Position).Magnitude <= Config.AsteroidTask.range
end

--[[ Oyunun başladığını sunucuya yazar (prompt tetiklenince). `now` testler için. ]]
function MinigameService.Begin(player: Player, now: number?)
	startedAt[player] = now or os.clock()
end

--[[
	Oyunun bittiğini doğrular ve ödülü verir. Verilen ödülü döndürür,
	reddedilirse nil. Red sessiz: sahte isteğe geri bildirim verilmiyor.
]]
function MinigameService.TryComplete(player: Player, now: number?): number?
	local rules = Config.AsteroidTask
	local t = now or os.clock()

	local started = startedAt[player]
	if not started then
		return nil
	end
	local elapsed = t - started
	if elapsed < rules.minSeconds or elapsed > rules.maxSeconds then
		return nil
	end
	local last = lastReward[player]
	if last and t - last < rules.cooldown then
		return nil
	end

	if not MinigameService.NearConsole(player) then
		return nil
	end

	startedAt[player] = nil
	lastReward[player] = t
	local reward = MinigameService.RewardFor(player)
	EconomyService.AddCash(player, reward)
	notify(player, string.format("Asteroids cleared! +$%s", Config.FormatCash(reward)))
	return reward
end

--[[ Bekleme süresini sıfırlar (yalnızca testler). ]]
function MinigameService._Reset(player: Player)
	startedAt[player] = nil
	lastReward[player] = nil
end

--[[
	Konsola promptu bağlar. Mimari haritada (tools/map/wings.luau,
	"GearShop.AsteroidConsole"); burada yalnızca adı belli parçaya iş
	bağlanıyor. Harita yoksa sessizce atlanıyor.
]]
function MinigameService.WireConsole(): boolean
	local decor = workspace:FindFirstChild("Decor")
	local part = decor and decor:FindFirstChild("AsteroidConsole", true)
	if not (part and part:IsA("BasePart")) then
		warn("[MinigameService] Decor.AsteroidConsole yok; asteroit gorevi kurulmadi")
		return false
	end
	console = part
	part.CanQuery = true

	local old = part:FindFirstChild("AsteroidPrompt")
	if old then
		old:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AsteroidPrompt"
	prompt.ActionText = "Clear Asteroids"
	prompt.ObjectText = "Weapons"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	PromptGuard.Connect(prompt, function(player)
		MinigameService.Begin(player)
	end)
	return true
end

function MinigameService.Start()
	notifyRemote = Net.Get("Notify")
	MinigameService.WireConsole()

	Net.Get("AsteroidsDone").OnServerEvent:Connect(function(player)
		MinigameService.TryComplete(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		startedAt[player] = nil
		lastReward[player] = nil
	end)
end

return MinigameService
