--!strict
--[[
	Sezon Kartı (Config.Season): oynadıkça XP → kademe → ödül.

	XP DataService sayaçlarından geliyor (DataService.Bumped): soygun, Void
	Leviathan soygunu, mini oyun, çark, görev, günlük giriş, oda görevi
	(Config.Season.xp). Başka bir yerden XP verilmiyor, yani
	istemci XP kazandıramıyor.

	Her kademede BEDAVA bir ödül; Sezon Kartı gamepass'i olana ayrıca
	PREMIUM ödül. Ödüller elle toplanıyor: "SeasonClaim"(kademe, "free" |
	"premium"). Sunucu kademeye ulaşılmış mı, alınmış mı, premium'a hakkı
	var mı bakıyor. Ödüller RewardService.Give'den (nakit gelire göre).

	Sezon kimliği değişince (yeni sezon) ilerleme sıfırlanıyor. Sezon
	bitmişse XP artmıyor ama kalan ödüller toplanabiliyor.

	İstemciye nitelikler: SeasonXp, SeasonClaimed ("f3,f7,p3..."), SeasonPass.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)

local SeasonService = {}

SeasonService.NotifyKind = "reward"

local notifyRemote: RemoteEvent? = nil
local passOwned: { [Player]: boolean } = {}
local lastClaim: { [Player]: number } = {}

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote and player.Parent then
		notifyRemote:FireClient(player, text, isError, SeasonService.NotifyKind)
	end
end

--[[ Profilin sezonu güncel mi; değilse sıfırla. ]]
local function roll(profile: any)
	if profile.season.id ~= Config.Season.id then
		profile.season = { id = Config.Season.id, xp = 0, free = {}, premium = {} }
	end
end

function SeasonService.HasPass(player: Player): boolean
	local id = Config.Season.pass.id
	if id <= 0 then
		return passOwned[player] == true
	end
	if passOwned[player] == nil then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
		end)
		passOwned[player] = ok and owns == true
	end
	return passOwned[player] == true
end

--[[ Testler için: pass sahipliğini elle ayarlar. ]]
function SeasonService._SetPass(player: Player, owned: boolean?)
	passOwned[player] = owned
end

function SeasonService.Publish(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	roll(profile)
	local claimed = {}
	for key in profile.season.free do
		table.insert(claimed, "f" .. key)
	end
	for key in profile.season.premium do
		table.insert(claimed, "p" .. key)
	end
	player:SetAttribute("SeasonXp", profile.season.xp)
	player:SetAttribute("SeasonClaimed", table.concat(claimed, ","))
	player:SetAttribute("SeasonPass", SeasonService.HasPass(player))
end

function SeasonService.AddXp(player: Player, amount: number)
	local profile = DataService.Get(player)
	if not profile or amount <= 0 then
		return
	end
	roll(profile)
	local now = os.time()
	if now < Config.Season.startsAt or now >= Config.SeasonEndsAt() then
		return
	end
	local before = Config.SeasonProgress(profile.season.xp)
	profile.season.xp += math.floor(amount)
	local after = Config.SeasonProgress(profile.season.xp)
	player:SetAttribute("SeasonXp", profile.season.xp)
	if after > before then
		notify(player, string.format("Season Pass: tier %d reached! Claim your reward.", after), false)
	end
end

function SeasonService.Claim(player: Player, tier: number, track: string): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	roll(profile)
	tier = math.floor(tier)
	if tier < 1 or tier > Config.Season.tiers or (track ~= "free" and track ~= "premium") then
		return false
	end
	local reached = Config.SeasonProgress(profile.season.xp)
	if tier > reached then
		notify(player, "Reach that tier first!", true)
		return false
	end
	local key = tostring(tier)
	local claimed = (profile.season :: any)[track]
	if claimed[key] then
		return false
	end
	if track == "premium" and not SeasonService.HasPass(player) then
		notify(player, "Premium rewards need the Season Pass", true)
		return false
	end
	local free, premium = Config.GetSeasonRewards(tier)
	local reward = if track == "free" then free else premium
	local what = RewardService.Give(player, reward :: any)
	if not what then
		return false
	end
	claimed[key] = true
	DataService.RequestSave(player)
	SeasonService.Publish(player)
	notify(player, string.format("Season tier %d: %s!", tier, what), false)
	return true
end

function SeasonService.Start()
	notifyRemote = Net.Get("Notify")

	DataService.Bumped.Event:Connect(function(player: Player, field: string, amount: number)
		local per = Config.Season.xp[field]
		if per then
			SeasonService.AddXp(player, per * amount)
		end
	end)

	Net.Get("SeasonClaim").OnServerEvent:Connect(function(player, tier, track)
		if typeof(tier) ~= "number" or typeof(track) ~= "string" then
			return
		end
		local t = os.clock()
		if t - (lastClaim[player] or 0) < 0.25 then
			return
		end
		lastClaim[player] = t
		SeasonService.Claim(player, tier, track)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if purchased and passId == Config.Season.pass.id and passId > 0 then
			passOwned[player] = true
			SeasonService.Publish(player)
			notify(player, "Season Pass unlocked! Premium rewards are yours to claim.", false)
		end
	end)

	local function onPlayer(player: Player)
		task.spawn(function()
			if DataService.WaitForProfile(player, 30) and player.Parent then
				SeasonService.Publish(player)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		passOwned[player] = nil
		lastClaim[player] = nil
	end)
end

return SeasonService
