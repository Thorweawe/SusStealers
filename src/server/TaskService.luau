--!strict
--[[
	Ek odalardaki Among Us görevleri (Storage, Laboratory): Fuel Engines,
	Fix Wiring, Swipe Card. Tanımlar Config.Tasks'ta.

	Akış (asteroit göreviyle aynı, MinigameService):
	  1. Oyuncu konsoldaki "TaskPrompt"u tetikler → başlangıç SUNUCUDA
	     yazılır. İstemci kendi tetiklemesini görüp görev penceresini açar
	     (TaskGames).
	  2. Görev bitince istemci TaskDone(taskId) gönderir.
	  3. TryComplete doğrular: başlamış mı, en kısa süre geçmiş mi, çok eski
	     mi, bekleme dolmuş mu, konsolun yakınında mı. Tutarsa küçük ödül.

	Konsollar haritada "TaskId" niteliğiyle işaretli (tools/map/annex.luau);
	adla değil nitelikle bulunuyor.

	Bekleme bitişi oyuncuya "TaskReady_<id>" niteliğiyle yazılıyor: istemci
	konsolun üstündeki sarı "!" işaretini ve penceredeki kalan süreyi buna
	göre gösteriyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local EconomyService = require(script.Parent.EconomyService)
local PromptGuard = require(script.Parent.PromptGuard)

local TaskService = {}

-- Bildirim sesi: ödül tınısı (MinigameService ile aynı)
TaskService.NotifyKind = "reward"

local startedAt: { [Player]: { [string]: number } } = {}
local lastReward: { [Player]: { [string]: number } } = {}
local consoles: { [string]: BasePart } = {}
local notifyRemote: RemoteEvent? = nil

local function notify(player: Player, text: string)
	if notifyRemote then
		notifyRemote:FireClient(player, text, false, TaskService.NotifyKind)
	end
end

--[[ Ödül: saniyelik gelirin belli katı, tabanlı. ]]
function TaskService.RewardFor(player: Player, def: Config.TaskDef): number
	return math.max(def.minReward, math.floor(EconomyService.GetIncome(player) * def.rewardSeconds))
end

--[[
	Oyuncu görevin konsoluna yakın mı. Konsol yoksa (harita kurulmamış)
	kısıt uygulanmıyor. Testler bunu geçici olarak değiştiriyor.
]]
function TaskService.NearConsole(player: Player, taskId: string): boolean
	local console = consoles[taskId]
	local def = Config.GetTask(taskId)
	if not (console and console.Parent and def) then
		return true
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	return (root.Position - console.Position).Magnitude <= def.range
end

--[[ Görevin başladığını yazar (prompt tetiklenince). `now` testler için. ]]
function TaskService.Begin(player: Player, taskId: string, now: number?)
	if not Config.GetTask(taskId) then
		return
	end
	startedAt[player] = startedAt[player] or {}
	startedAt[player][taskId] = now or os.clock()
end

--[[
	Görevin bittiğini doğrular ve ödülü verir. Verilen ödülü döndürür,
	reddedilirse nil. Red sessiz: sahte isteğe geri bildirim verilmiyor.
]]
function TaskService.TryComplete(player: Player, taskId: any, now: number?): number?
	if typeof(taskId) ~= "string" then
		return nil
	end
	local def = Config.GetTask(taskId)
	if not def then
		return nil
	end
	local t = now or os.clock()
	local mine = startedAt[player]
	local started = mine and mine[taskId]
	if not started then
		return nil
	end
	local elapsed = t - started
	if elapsed < def.minSeconds or elapsed > def.maxSeconds then
		return nil
	end

	local rewards = lastReward[player] or {}
	lastReward[player] = rewards
	local last = rewards[taskId]
	if last and t - last < def.cooldown then
		-- Gerçekten oynanmış bir görev: ödül yok ama ne zaman geleceğini söyle
		(mine :: any)[taskId] = nil
		local left = math.ceil(def.cooldown - (t - last))
		notify(player, string.format("%s done! Next reward in %d:%02d", def.name, left // 60, left % 60))
		return nil
	end
	if not TaskService.NearConsole(player, taskId) then
		return nil
	end

	(mine :: any)[taskId] = nil
	rewards[taskId] = t
	player:SetAttribute("TaskReady_" .. taskId, os.time() + def.cooldown)
	local reward = TaskService.RewardFor(player, def)
	EconomyService.AddCash(player, reward)
	notify(player, string.format("%s complete! +$%s", def.name, Config.FormatCash(reward)))
	return reward
end

--[[ Bekleme sürelerini sıfırlar (yalnızca testler). ]]
function TaskService._Reset(player: Player)
	startedAt[player] = nil
	lastReward[player] = nil
	for _, def in Config.Tasks do
		player:SetAttribute("TaskReady_" .. def.id, nil)
	end
end

--[[ Bağlanan konsollar (testler). ]]
function TaskService.GetConsoles(): { [string]: BasePart }
	return consoles
end

function TaskService.WireConsoles(): number
	local decor = workspace:FindFirstChild("Decor")
	if not decor then
		return 0
	end
	local count = 0
	for _, part in decor:GetDescendants() do
		local taskId = part:GetAttribute("TaskId")
		if not (part:IsA("BasePart") and typeof(taskId) == "string") then
			continue
		end
		local def = Config.GetTask(taskId)
		if not def then
			warn(string.format("[TaskService] Config.Tasks'ta olmayan görev: %s", taskId))
			continue
		end
		consoles[taskId] = part
		local old = part:FindFirstChild("TaskPrompt")
		if old then
			old:Destroy()
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TaskPrompt"
		prompt.ActionText = def.name
		prompt.ObjectText = def.room
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 9
		prompt.RequiresLineOfSight = false
		prompt:SetAttribute("TaskId", taskId)
		prompt.Parent = part
		PromptGuard.Connect(prompt, function(player)
			TaskService.Begin(player, taskId)
		end)
		count += 1
	end
	if count == 0 then
		warn("[TaskService] Decor'da TaskId'li konsol yok; ek oda görevleri kurulmadı")
	end
	return count
end

function TaskService.Start()
	notifyRemote = Net.Get("Notify")
	TaskService.WireConsoles()
	Net.Get("TaskDone").OnServerEvent:Connect(function(player, taskId)
		TaskService.TryComplete(player, taskId)
	end)
	Players.PlayerRemoving:Connect(function(player)
		startedAt[player] = nil
		lastReward[player] = nil
	end)
end

return TaskService
