--!strict
--[[
	Deneyim bildirimleri (2026-09-29): oyun kapalıyken oyuncunun telefonuna
	/ Roblox'una "günlük ödülün hazır" bildirimi. Oyuncuyu ertesi gün geri
	getiren en güçlü araç.

	NASIL:
	  • Oyuncu çıkarken, günlük ödülünün ne zaman hazır olacağı MemoryStore
	    sıralı haritasına yazılıyor ("NotifyQueue_v1": anahtar userId,
	    sıralama anahtarı gönderim zamanı). Geri gelirse siliniyor.
	  • Açık olan HER sunucu dakikada bir vakti gelenlere bakıyor; bir
	    girdiyi önce UpdateAsync ile "benim" diye işaretleyen gönderiyor
	    (iki sunucu aynı bildirimi iki kez atmasın), sonra siliyor.
	  • Gönderim Open Cloud User Notifications API'si (HttpService):
	    Creator Hub'daki şablon (Config.Notifications.daily) + Secrets'taki
	    Open Cloud anahtarı (Config.Notifications.secretName).

	Oyuncu bildirime izin vermediyse Roblox göndermiyor (izin istemi
	istemcide, Engagement). Şablon kimliği boşsa servis hiçbir şey yapmıyor.

	GEREKENLER (panelde, kodda değil): Creator Hub > Engagement >
	Notifications'ta şablon; Open Cloud API anahtarı (user.user-notification
	yazma izni, bu deneyim); Game Settings > Security > Allow HTTP Requests;
	anahtar Creator Hub > Secrets'a Config.Notifications.secretName adıyla.
]]

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local DataService = require(script.Parent.DataService)

local NotifyService = {}

local QUEUE_TTL = 7 * 86400
local POLL = 60
local BATCH = 20

local queue: MemoryStoreSortedMap? = nil
local warned = false

local function enabled(): boolean
	return Config.Notifications.daily ~= "" and queue ~= nil
end

--[[ Günlük ödül bildirimi ne zaman gitsin (UTC sn) ve seri; gerekmiyorsa nil. ]]
function NotifyService.DailyAt(profile: any, now: number): (number?, number)
	local today = Config.DayIndex(now)
	local streak = profile.dailyStreak or 0
	if streak < 1 then
		return nil, 0
	end
	if profile.lastDailyDay == today then
		-- Bugün alındı: yarın gün dönünce hazır
		return (today + 1) * 86400 + 600, streak
	elseif profile.lastDailyDay == today - 1 then
		-- Dün alındı, bugün alınmadı: gün bitmeden 4 saat önce "seri bitiyor"
		return math.max(now + 3600, (today + 1) * 86400 - 4 * 3600), streak
	end
	return nil, 0
end

local function send(userId: number, streak: number): boolean
	local ok, err = pcall(function()
		local secret = HttpService:GetSecret(Config.Notifications.secretName)
		local response = HttpService:RequestAsync({
			Url = string.format("https://apis.roblox.com/cloud/v2/users/%d/notifications", userId),
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/json",
				["x-api-key"] = secret :: any,
			},
			Body = HttpService:JSONEncode({
				source = { universe = "universes/" .. tostring(game.GameId) },
				payload = {
					messageId = Config.Notifications.daily,
					type = "MOMENT",
					parameters = { streak = { stringValue = tostring(streak) } },
					joinExperience = { launchData = "notif:daily" },
					analyticsData = { category = "daily_reward" },
				},
			}),
		})
		if not response.Success then
			error(string.format("HTTP %d %s", response.StatusCode, string.sub(response.Body, 1, 200)))
		end
	end)
	if not ok and not warned then
		warned = true
		warn("[Notify] bildirim gönderilemedi (şablon/anahtar/HTTP ayarı?): " .. tostring(err))
	end
	return ok
end

-- Profil tablosunun kendisi: DataService çıkışta onu bırakabiliyor, biz tutuyoruz
local held: { [Player]: any } = {}

local function schedule(player: Player)
	local profile = held[player] or DataService.Get(player)
	held[player] = nil
	if not (enabled() and profile) then
		return
	end
	local at, streak = NotifyService.DailyAt(profile, os.time())
	if not at then
		return
	end
	local userId = player.UserId
	task.spawn(function()
		pcall(function()
			(queue :: MemoryStoreSortedMap):SetAsync(tostring(userId), { s = streak }, QUEUE_TTL, at)
		end)
	end)
end

local function cancel(player: Player)
	if not queue then
		return
	end
	local key = tostring(player.UserId)
	task.spawn(function()
		pcall(function()
			(queue :: MemoryStoreSortedMap):RemoveAsync(key)
		end)
	end)
end

local function poll()
	if not enabled() then
		return
	end
	local map = queue :: MemoryStoreSortedMap
	local ok, items = pcall(function()
		return map:GetRangeAsync(Enum.SortDirection.Ascending, BATCH, nil, { sortKey = os.time() })
	end)
	if not ok or typeof(items) ~= "table" then
		return
	end
	for _, item in items do
		local key = item.key
		local mine = false
		pcall(function()
			map:UpdateAsync(key, function(old, sortKey)
				if typeof(old) ~= "table" or old.c then
					return nil
				end
				old.c = game.JobId
				mine = true
				return old, sortKey
			end, 3600)
		end)
		if mine then
			local userId = tonumber(key)
			local streak = if typeof(item.value) == "table" then tonumber(item.value.s) or 1 else 1
			if userId and not Players:GetPlayerByUserId(userId) then
				send(userId, streak)
			end
			pcall(function()
				map:RemoveAsync(key)
			end)
		end
	end
end

function NotifyService.Start()
	local ok, map = pcall(function()
		return MemoryStoreService:GetSortedMap("NotifyQueue_v1")
	end)
	queue = if ok then map else nil

	local function onPlayer(player: Player)
		cancel(player)
		task.spawn(function()
			local profile = DataService.WaitForProfile(player, 60)
			if player.Parent then
				held[player] = profile
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(schedule)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			schedule(player)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(POLL + math.random() * 10)
			poll()
		end
	end)
end

return NotifyService
