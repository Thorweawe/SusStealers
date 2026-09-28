--!strict
--[[
	Haftalık sıralama: bu hafta EN ÇOK UZAY SOYGUNU yapanlar (bütün sunucular).

	Hafta Pazartesi 00:00 UTC'de başlıyor (Config.Weekly). Sayaç profilde
	(weekId / weekStolen): hafta değişince sıfırlanıyor. Değerler
	OrderedDataStore "Weekly_Heists_<hafta>"ya dakikada bir (ve çıkarken)
	yazılıyor, ilk 10 dakikada bir okunuyor.

	ÖDÜL: hafta bitince ilk 10 (Config.Weekly.Rewards). Oyuncu o an oyunda
	olmayabilir; bu yüzden ödül GİRİŞTE veriliyor: geçen haftanın listesine
	bakılıyor, oyuncu içindeyse nakit + unvan sayacı (weeklyBest) + birinciye
	Champion Blaze alevi. profile.weeklyChecked hangi haftaya bakıldığını
	tutuyor (ödül bir kez). DataStore'a ulaşılamazsa işaretlenmiyor, sonra
	yeniden deneniyor.

	İSTEMCİYE: workspace nitelikleri — WeeklyTop (JSON: {n, v, u} listesi),
	WeeklyEndsAt, WeeklyGlobal (küresel mi, yoksa bu sunucu mu). Oyuncu
	niteliği WeeklyHeists. Pencere istemcide (WeeklyPanel); lobideki MOST
	HEISTS panosunda "Weekly Top" promptu onu açıyor. Remote yok.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local DataService = require(script.Parent.DataService)
local RewardService = require(script.Parent.RewardService)
local TitleService = require(script.Parent.TitleService)
local AnnounceService = require(script.Parent.AnnounceService)

local WeeklyService = {}

WeeklyService.NotifyKind = "reward"

local INTERVAL = 60

type Row = { n: string, v: number, u: number }

local notifyRemote: RemoteEvent? = nil
local stores: { [number]: OrderedDataStore | false } = {}
local names: { [number]: string } = {}
-- Geçen haftanın ilk 10'u (hafta -> liste), sunucu başına bir kez okunuyor
local finals: { [number]: { Row } } = {}

local function notify(player: Player, text: string, isError: boolean)
	if notifyRemote and player.Parent then
		notifyRemote:FireClient(player, text, isError, WeeklyService.NotifyKind)
	end
end

local function now(): number
	return os.time()
end

local function storeFor(week: number): OrderedDataStore?
	local cached = stores[week]
	if cached == nil then
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore("Weekly_Heists_" .. week)
		end)
		stores[week] = if ok and store then store else false
		cached = stores[week]
	end
	return if cached then cached :: OrderedDataStore else nil
end

local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local online = Players:GetPlayerByUserId(userId)
	local result = "Crewmate"
	if online then
		result = online.DisplayName
	else
		local ok, name = pcall(function()
			return Players:GetNameFromUserIdAsync(userId)
		end)
		if ok and typeof(name) == "string" then
			result = name
		end
	end
	names[userId] = result
	return result
end

--[[ Hafta değiştiyse sayacı sıfırlar. Her okuma/yazmadan önce. ]]
local function roll(player: Player, profile: any)
	local week = Config.WeekIndex(now())
	if profile.weekId ~= week then
		profile.weekId = week
		profile.weekStolen = 0
	end
	player:SetAttribute("WeeklyHeists", profile.weekStolen)
end

--[[ Bir haftanın ilk 10'u (DataStore). Başarısızsa nil. ]]
local function readTop(week: number): { Row }?
	if not DataService.IsAvailable() then
		return nil
	end
	local store = storeFor(week)
	if not store then
		return nil
	end
	local hidden = 0
	for _ in Config.LeaderboardHidden do
		hidden += 1
	end
	local ok, page = pcall(function()
		return (store :: OrderedDataStore):GetSortedAsync(false, Config.Weekly.Rows + hidden):GetCurrentPage()
	end)
	if not ok or typeof(page) ~= "table" then
		return nil
	end
	local rows: { Row } = {}
	for _, entry in page do
		local userId = tonumber(entry.key)
		if userId and not Config.LeaderboardHidden[userId] and entry.value > 0 and #rows < Config.Weekly.Rows then
			table.insert(rows, { n = nameOf(userId), v = entry.value, u = userId })
		end
	end
	return rows
end

--[[ Yedek: bu sunucudaki oyuncular. ]]
local function localTop(): { Row }
	local rows: { Row } = {}
	for _, player in Players:GetPlayers() do
		local profile = DataService.Get(player)
		if profile and not Config.LeaderboardHidden[player.UserId] then
			roll(player, profile)
			if profile.weekStolen > 0 then
				table.insert(rows, { n = player.DisplayName, v = profile.weekStolen, u = player.UserId })
			end
		end
	end
	table.sort(rows, function(a, b)
		return a.v > b.v
	end)
	while #rows > Config.Weekly.Rows do
		table.remove(rows)
	end
	return rows
end

local function write(player: Player)
	local profile = DataService.Get(player)
	if not profile or not DataService.IsAvailable() then
		return
	end
	roll(player, profile)
	if profile.weekStolen <= 0 then
		return
	end
	local store = storeFor(profile.weekId)
	if store then
		pcall(function()
			(store :: OrderedDataStore):SetAsync(tostring(player.UserId), profile.weekStolen)
		end)
	end
end

local function publish()
	local week = Config.WeekIndex(now())
	local rows = readTop(week)
	local global = rows ~= nil
	if not rows or #rows == 0 then
		rows = localTop()
		global = false
	end
	workspace:SetAttribute("WeeklyTop", HttpService:JSONEncode(rows))
	workspace:SetAttribute("WeeklyGlobal", global)
	workspace:SetAttribute("WeeklyEndsAt", Config.WeekEndsAt(now()))
end

--[[
	Geçen haftanın ödülü. `top` verilirse (testler) DataStore'a bakılmıyor.
	Döner: verilen sıra (yoksa nil).
]]
function WeeklyService.Settle(player: Player, top: { Row }?, week: number?): number?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local current = week or Config.WeekIndex(now())
	if profile.weeklyChecked >= current then
		return nil
	end
	local last = current - 1
	local list = top or finals[last]
	if not list then
		list = readTop(last)
		if not list then
			return nil -- DataStore yok: işaretleme, sonra tekrar dene
		end
		finals[last] = list
	end
	profile.weeklyChecked = current
	local rank: number? = nil
	for i, row in list do
		if row.u == player.UserId then
			rank = i
			break
		end
	end
	if not rank then
		return nil
	end
	local reward = Config.GetWeeklyReward(rank)
	if not reward then
		return nil
	end
	local got = {}
	local cash = RewardService.Give(player, { kind = "cash", seconds = reward.seconds, minimum = reward.minimum })
	if cash then
		table.insert(got, cash)
	end
	if reward.flame then
		local flame = RewardService.Give(player, { kind = "flame", flame = reward.flame })
		if flame then
			table.insert(got, flame)
		end
	end
	profile.weeklyBest = math.max(profile.weeklyBest, reward.best)
	TitleService.Check(player)
	DataService.RequestSave(player)
	notify(player, string.format("Last week you were #%d heister! Reward: %s", rank, table.concat(got, " + ")), false)
	player:SetAttribute("WeeklyResult", string.format("%d|%s", rank, table.concat(got, " + ")))
	if rank <= 3 then
		AnnounceService.Summon(AnnounceService.Paint(string.format("%s was last week's #%d heister!", player.DisplayName, rank),
			Color3.fromRGB(255, 205, 60)))
	end
	return rank
end

function WeeklyService.Start()
	notifyRemote = Net.Get("Notify")
	workspace:SetAttribute("WeeklyEndsAt", Config.WeekEndsAt(now()))
	workspace:SetAttribute("WeeklyTop", "[]")

	DataService.Bumped.Event:Connect(function(player: Player, field: string, amount: number)
		if field ~= "salvaged" then
			return
		end
		local profile = DataService.Get(player)
		if profile then
			roll(player, profile)
			profile.weekStolen += amount
			player:SetAttribute("WeeklyHeists", profile.weekStolen)
		end
	end)

	local function onPlayer(player: Player)
		task.spawn(function()
			local profile = DataService.WaitForProfile(player, 30)
			if profile and player.Parent then
				roll(player, profile)
				WeeklyService.Settle(player)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
	Players.PlayerRemoving:Connect(function(player)
		task.spawn(write, player)
	end)

	-- MOST HEISTS panosuna "Weekly Top" promptu: pencereyi istemci açıyor
	task.spawn(function()
		local decor = workspace:WaitForChild("Decor", 30)
		local boards = decor and decor:WaitForChild("Boards", 30)
		local screen = boards and boards:WaitForChild("BoardScreen2", 30)
		if screen and screen:IsA("BasePart") and not screen:FindFirstChild("WeeklyPrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "WeeklyPrompt"
			prompt.ActionText = "Weekly Top"
			prompt.ObjectText = "Heist Rankings"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 16
			prompt.RequiresLineOfSight = false
			prompt.Parent = screen
		end
	end)

	task.spawn(function()
		task.wait(3)
		publish()
		while true do
			task.wait(INTERVAL)
			for _, player in Players:GetPlayers() do
				write(player)
				-- Hafta oyun sırasında dönerse (Pazartesi gece yarısı) ödül de o an
				WeeklyService.Settle(player)
			end
			publish()
		end
	end)
end

--[[ Testler için: bu sunucunun listesini hemen yayınlar. ]]
function WeeklyService._Publish()
	publish()
end

return WeeklyService
