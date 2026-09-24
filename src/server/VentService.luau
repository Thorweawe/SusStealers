--!strict
--[[
	Vent ağı: Among Us havalandırmaları.

	Kapaklar haritada eşli (tools/map/polish.luau, "VentPad" parçaları,
	aynı "VentPair" niteliğini taşıyan iki pad bir çift). Kapağa basan
	oyuncu eşine ışınlanıyor.

	═══ KURAL: TAŞIRKEN YOK ════════════════════════════════════════════════

	Çalmanın bütün riski karakteri sırtında rakip üssünden koşarak
	götürmek. Vent taşırken çalışsaydı hırsız rakibin yanındaki kapaktan
	girip kendi üssünün yanından çıkardı ve kovalamaca diye bir şey
	kalmazdı. Boş elle girmek serbest: saldırmaya gitmek ve eve dönmek
	hızlanıyor, kaçış hızlanmıyor.

	Bekleme süresi var ki iki kapak arasında gidip gelip kovalayanı
	sonsuza kadar atlatmak mümkün olmasın.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local PromptGuard = require(script.Parent.PromptGuard)

local VentService = {}

local notifyRemote: RemoteEvent
local lastVentAt: { [Player]: number } = {}
local pads: { BasePart } = {}

local function notifyError(player: Player, text: string)
	if notifyRemote then
		notifyRemote:FireClient(player, text, true)
	end
end

--[[
	Işınlanma denemesi. Sebebini döner: "ok" | "carrying" | "cooldown" |
	"nochar". Testler sebebe bakıyor; `now` testlerin saati ilerletmesi için.
]]
function VentService.TryVent(player: Player, from: BasePart, to: BasePart, now: number?): string
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (character and root and root:IsA("BasePart")) then
		return "nochar"
	end

	if character:FindFirstChild("CarriedUnit") then
		notifyError(player, "You can't use vents while carrying a crewmate!")
		return "carrying"
	end

	local t = now or os.clock()
	local last = lastVentAt[player]
	if last and t - last < Config.VentCooldown then
		notifyError(player, string.format("Vent cooling down (%ds)", math.ceil(Config.VentCooldown - (t - last))))
		return "cooldown"
	end
	lastVentAt[player] = t

	-- Oturuyorsa önce kalksın: kaynaklı koltuk da ışınlanıyordu
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if humanoid and seat then
		humanoid.Sit = false
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
	end

	-- Varışta kapağın biraz yukarısı, oyuncunun baktığı yön korunarak
	local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local arrive = to.Position + Vector3.new(0, 3, 0)
	root.CFrame = if look.Magnitude > 0.01
		then CFrame.lookAt(arrive, arrive + look.Unit)
		else CFrame.new(arrive)
	return "ok"
end

--[[ Testler için: bekleme süresini sıfırlar. ]]
function VentService._Reset(player: Player)
	lastVentAt[player] = nil
end

--[[ Kurulu pad listesi (testler). ]]
function VentService.GetPads(): { BasePart }
	return pads
end

local function link(from: BasePart, to: BasePart)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "VentPrompt"
	prompt.ActionText = "Vent"
	prompt.ObjectText = "Vent"
	prompt.HoldDuration = Config.VentHoldTime
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = from

	PromptGuard.Connect(prompt, function(player)
		VentService.TryVent(player, from, to)
	end)
end

function VentService.Start()
	notifyRemote = Net.Get("Notify")

	local decor = workspace:FindFirstChild("Decor")
	local polish = decor and decor:FindFirstChild("Polish")
	local net = polish and polish:FindFirstChild("VentNet")
	if not net then
		warn("[Vent] Decor.Polish.VentNet yok: harita polish bölümü kurulmamış, ventler kapalı")
		return
	end

	local byPair: { [string]: { BasePart } } = {}
	for _, d in net:GetChildren() do
		if d:IsA("BasePart") and d.Name == "VentPad" then
			local id = d:GetAttribute("VentPair")
			if typeof(id) == "string" then
				byPair[id] = byPair[id] or {}
				table.insert(byPair[id], d)
			end
		end
	end

	for id, list in byPair do
		if #list ~= 2 then
			warn(string.format("[Vent] %s çiftinde %d kapak var, 2 olmalı; atlandı", id, #list))
			continue
		end
		link(list[1], list[2])
		link(list[2], list[1])
		table.insert(pads, list[1])
		table.insert(pads, list[2])
	end

	Players.PlayerRemoving:Connect(function(player)
		lastVentAt[player] = nil
	end)
end

return VentService
