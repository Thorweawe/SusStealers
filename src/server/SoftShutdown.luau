--!strict
--[[
	Yumuşak yeniden başlatma (2026-09-30): Creator Hub'dan "Restart servers"
	denince oyuncular oyundan ATILMIYOR — ekranda 10'dan geri sayım çıkıyor,
	sonra otomatik olarak yeni sürümün sunucusuna taşınıyorlar.

	NASIL (bilinen "soft shutdown" kalıbı):
	  1. Sunucu kapanırken (game:BindToClose) geri sayım, sonra bütün
	     oyuncular geçici bir özel sunucuya (ReserveServer) ışınlanıyor.
	     Doğrudan aynı yere ışınlamak, hâlâ kapanmakta olan ESKİ sürümlü
	     bir sunucuya düşürebiliyor; geçici durak bunu önlüyor.
	  2. Geçici sunucu (IsTemporary) oyunun HİÇBİR servisini başlatmıyor
	     (init.server erken çıkıyor: profil yüklenmiyor, kilit alınmıyor);
	     birkaç saniye bekleyip oyuncuyu normal oyuna geri ışınlıyor — o
	     sırada eski sunucular kapanmış, yeni sunucular yeni sürümle açılıyor.

	Kayıt: oyuncu ışınlanınca PlayerRemoving çalışıyor, DataService profili
	kaydedip oturum kilidini bırakıyor (normal çıkışla aynı yol).

	BindToClose en fazla 30 sn veriyor: 10 sn sayım + ışınlama buna sığıyor.
	Studio'da ve boş sunucuda hiçbir şey yapmıyor.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local SoftShutdown = {}

local COUNTDOWN = 10
local TEMP_WAIT = 6

--[[ Bu sunucu yeniden başlatmanın geçici durağı mı (ayrılmış özel sunucu)? ]]
function SoftShutdown.IsTemporary(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

local function banner(text: string): Message
	local old = workspace:FindFirstChild("SoftShutdownMessage")
	local message = if old and old:IsA("Message") then old else Instance.new("Message")
	message.Name = "SoftShutdownMessage"
	message.Text = text
	message.Parent = workspace
	return message
end

--[[ Geçici sunucu: gelen herkesi birkaç saniye sonra normal oyuna geri yolla. ]]
function SoftShutdown.RunTemporary()
	banner("UPDATING... You will rejoin automatically in a few seconds. Your progress is saved!")
	local function bounce(player: Player)
		task.spawn(function()
			task.wait(TEMP_WAIT)
			for attempt = 1, 6 do
				if not player.Parent then
					return
				end
				local ok = pcall(function()
					TeleportService:TeleportAsync(game.PlaceId, { player })
				end)
				if ok then
					-- Işınlama başladı; gitmezse bir süre sonra yeniden dene
					task.wait(12)
				else
					task.wait(2 * attempt)
				end
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		bounce(player)
	end
	Players.PlayerAdded:Connect(bounce)
end

function SoftShutdown.Start()
	game:BindToClose(function()
		if RunService:IsStudio() or #Players:GetPlayers() == 0 then
			return
		end
		-- Temalı bant (istemci RestartScreen); eski Message kutusu yedek olarak
		workspace:SetAttribute("RestartTitle", "UPDATE")
		workspace:SetAttribute("RestartAt", workspace:GetServerTimeNow() + COUNTDOWN)
		local message = banner("")
		message.Parent = nil
		for left = COUNTDOWN, 1, -1 do
			message.Text = string.format("UPDATE! Rejoining automatically in %d... Your progress is saved!", left)
			task.wait(1)
		end
		message.Text = "REJOINING NOW..."

		local players = Players:GetPlayers()
		if #players == 0 then
			return
		end
		local ok, code = pcall(function()
			return TeleportService:ReserveServer(game.PlaceId)
		end)
		local sent = false
		if ok and typeof(code) == "string" then
			local options = Instance.new("TeleportOptions")
			options.ReservedServerAccessCode = code
			sent = pcall(function()
				TeleportService:TeleportAsync(game.PlaceId, players, options)
			end)
		end
		if not sent then
			-- Geçici durak ayrılamadı: doğrudan aynı yere dene
			pcall(function()
				TeleportService:TeleportAsync(game.PlaceId, players)
			end)
		end
		-- Oyuncular gidene kadar sunucu açık kalsın (kayıtlar PlayerRemoving'de)
		local deadline = os.clock() + 15
		while #Players:GetPlayers() > 0 and os.clock() < deadline do
			task.wait(0.5)
		end
	end)
end

return SoftShutdown
