--!strict
--[[
	Yönetici komutları (2026-09-30): canlı oyunda Geliştirici Konsolu'ndan
	(F9 > Server > komut satırı) çağrılıyor.

	NEDEN BindableEvent: konsoldan `require(...)` ile çağrılan modül, oyunun
	çalışan kopyası DEĞİL — ayrı, boş bir kopya açılıyor (profiller yok) ve
	komut sessizce hiçbir şey yapmıyor. Olay (ServerStorage.AdminCommand)
	ise iki taraf arasında ortak: konsol ateşliyor, çalışan oyun dinliyor.

	Güvenlik: ServerStorage istemciye hiç gitmiyor ve sunucu komut satırını
	yalnızca oyunun sahibi / yetkili grup üyesi kullanabiliyor. Remote yok.

	KULLANIM (konsola):
	  game.ServerStorage.AdminCommand:Fire("addspeed", "OyuncuAdi", 50)
	  game.ServerStorage.AdminCommand:Fire("setspeed", "OyuncuAdi", 120)
	  game.ServerStorage.AdminCommand:Fire("cash", "OyuncuAdi", 100000)
	  game.ServerStorage.AdminCommand:Fire("trainboost", 2, 15)        -- bu sunucuda 15 dk 2x antrenman
	  game.ServerStorage.AdminCommand:Fire("announce", "metin")        -- bütün sunucular
	  game.ServerStorage.AdminCommand:Fire("restart", 60, "BUG FIX UPDATE")  -- bütün sunucularda geri sayım
	Oyuncu adı yerine "all" = sunucudaki herkes. Ad baştan eşleşiyor
	(büyük/küçük harf önemsiz). Sonuç sunucu günlüğüne yazılıyor.

	"restart" sunucuyu KAPATMIYOR: bütün sunucularda ekranın ortasında geri
	sayım gösteriyor; sıfırlanınca Creator Hub'dan Restart servers.
]]

local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local Net = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Net)

local AnnounceService = require(script.Parent.AnnounceService)
local CapsuleService = require(script.Parent.CapsuleService)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local AdminService = {}

local TOPIC = "SusAdminCountdown"
local countdownToken = 0

local function targets(name: any): { Player }
	if typeof(name) ~= "string" then
		return {}
	end
	local lower = string.lower(name)
	if lower == "all" then
		return Players:GetPlayers()
	end
	local found = {}
	for _, player in Players:GetPlayers() do
		if string.sub(string.lower(player.Name), 1, #lower) == lower
			or string.sub(string.lower(player.DisplayName), 1, #lower) == lower then
			table.insert(found, player)
		end
	end
	return found
end

--[[ Bu sunucuda ekranın ortasında geri sayım (Message: eski ama herkeste çalışıyor). ]]
local function countdown(seconds: number, title: string)
	countdownToken += 1
	local token = countdownToken
	local old = workspace:FindFirstChild("AdminCountdown")
	if old then
		old:Destroy()
	end
	local message = Instance.new("Message")
	message.Name = "AdminCountdown"
	message.Parent = workspace
	task.spawn(function()
		for left = math.floor(seconds), 1, -1 do
			if token ~= countdownToken then
				return
			end
			message.Text = string.format("%s! Server restarting in %d... Your progress is saved, just rejoin!", title, left)
			task.wait(1)
		end
		if token ~= countdownToken then
			return
		end
		message.Text = "RESTARTING NOW! Rejoin in a few seconds."
		task.wait(30)
		if token == countdownToken then
			message:Destroy()
		end
	end)
end

--[[ Komutu işler; ne yaptığını döner (testler de çağırıyor). ]]
function AdminService.Run(command: any, a: any, b: any): string
	if command == "addspeed" or command == "setspeed" then
		local amount = tonumber(b)
		if not amount then
			return "kullanım: " .. command .. ", ad, sayı"
		end
		local done = {}
		for _, player in targets(a) do
			if DataService.Get(player) then
				local speed = if command == "addspeed" then CapsuleService.GetSpeed(player) + amount else amount
				CapsuleService.SetSpeed(player, speed)
				DataService.RequestSave(player)
				table.insert(done, string.format("%s=%.1f", player.Name, CapsuleService.GetSpeed(player)))
			end
		end
		return if #done > 0 then "hız: " .. table.concat(done, ", ") else "oyuncu bulunamadı"
	elseif command == "cash" then
		local amount = tonumber(b)
		if not amount then
			return "kullanım: cash, ad, sayı"
		end
		local done = {}
		for _, player in targets(a) do
			if DataService.Get(player) then
				EconomyService.AddCash(player, amount)
				table.insert(done, player.Name)
			end
		end
		return if #done > 0 then "nakit verildi: " .. table.concat(done, ", ") else "oyuncu bulunamadı"
	elseif command == "announce" then
		if typeof(a) ~= "string" or a == "" then
			return "kullanım: announce, metin"
		end
		AnnounceService.Global(a)
		return "duyuruldu"
	elseif command == "trainboost" then
		-- Bu sunucudaki herkese kapsül antrenmanı çarpanı: ("trainboost", 2, 15) = 15 dk 2x
		local mul = math.clamp(tonumber(a) or 2, 1, 10)
		local minutes = math.clamp(tonumber(b) or 15, 0, 240)
		workspace:SetAttribute("TrainBoostMul", mul)
		workspace:SetAttribute("TrainBoostUntil", workspace:GetServerTimeNow() + minutes * 60)
		if minutes > 0 and mul > 1 then
			-- Yalnızca bu sunucu (takviye de yalnızca burada): sohbet + bildirim
			local text = string.format("%gx SPACE SPEED TRAINING for %g minutes! Get in your capsule!", mul, minutes)
			AnnounceService.Summon(text)
			Net.Get("Notify"):FireAllClients(text, false, "reward")
		end
		return string.format("antrenman x%g, %g dk", mul, minutes)
	elseif command == "restart" then
		local seconds = math.clamp(tonumber(a) or 60, 5, 600)
		local title = if typeof(b) == "string" and b ~= "" then string.sub(b, 1, 60) else "UPDATE"
		countdown(seconds, title)
		task.spawn(function()
			pcall(function()
				MessagingService:PublishAsync(TOPIC, { s = seconds, t = title, j = game.JobId })
			end)
		end)
		return string.format("geri sayım başladı (%g sn, bütün sunucular)", seconds)
	end
	return "bilinmeyen komut: " .. tostring(command)
end

function AdminService.Start()
	local event = ServerStorage:FindFirstChild("AdminCommand")
	if not (event and event:IsA("BindableEvent")) then
		event = Instance.new("BindableEvent")
		event.Name = "AdminCommand"
		event.Parent = ServerStorage
	end
	(event :: BindableEvent).Event:Connect(function(command, a, b)
		local ok, result = pcall(AdminService.Run, command, a, b)
		print("[Admin] " .. tostring(command) .. " -> " .. tostring(result), if ok then "" else "(hata)")
	end)

	-- Başka sunucudan başlatılan geri sayım
	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(message)
				local data = message.Data
				if typeof(data) == "table" and data.j ~= game.JobId and typeof(data.s) == "number" and typeof(data.t) == "string" then
					countdown(math.clamp(data.s, 5, 600), string.sub(data.t, 1, 60))
				end
			end)
		end)
	end)
end

return AdminService
