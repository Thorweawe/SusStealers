--!strict
--[[
	Sunucu geneli duyurular: sohbette "Summons" sekmesi.

	Ne düşüyor: nadir çıkışlar. Birinin konveyöründe Mythic/Secret belirdi,
	saatli çağrı geldi ya da gelmek üzere, biri yumurtadan Mythic/Secret
	pet çıkardı. Bunlar herkesin bilmesi gereken anlar — hırsız hedef
	seçiyor, sahibi üssüne koşuyor.

	═══ NEDEN AYRI KANAL ═══════════════════════════════════════════════════

	General'e yazsaydık oyuncuların konuşması duyuruların arasında
	kaybolurdu (ya da tersi). Ayrı sekme ikisini de okunur tutuyor ve
	oyuncu isterse sadece Summons'a bakabiliyor.

	═══ NEDEN REMOTE ═══════════════════════════════════════════════════════

	TextChannel:DisplaySystemMessage YALNIZCA istemcide çalışıyor. Sunucu
	kanalı kurup oyuncuları üye yapıyor (AddUserAsync sunucu tarafı),
	metni de "Summons" remote'uyla gönderiyor; istemci (SummonsChat)
	kanala yazıyor.

	Sunucudan istemciye tek yönlü: istemci bu kanala bir şey
	gönderemiyor, yani sahte duyuru yapılamıyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local AnnounceService = {}

local CHANNEL_NAME = "Summons"
AnnounceService.ChannelName = CHANNEL_NAME

local summonsRemote: RemoteEvent
local channel: TextChannel? = nil

--[[
	Aynı olayın saniyede birden fazla kez duyurulmasını engelliyor. Saatli
	çağrı sekiz üsse aynı anda düşüyor; her üs için ayrı satır basmak
	kanalı sekiz kopya ile dolduruyordu.
]]
local recent: { [string]: number } = {}
local DEDUPE_SECONDS = 3

local function ensureChannel(): TextChannel?
	if channel and channel.Parent then
		return channel
	end

	local folder = TextChatService:FindFirstChild("TextChannels")
	if not folder then
		-- TextChatService kapalı (eski sohbet): kanal kurulamaz, duyurular
		-- yine de bildirim olarak gidiyor
		return nil
	end

	local existing = folder:FindFirstChild(CHANNEL_NAME)
	if existing and existing:IsA("TextChannel") then
		channel = existing
		return existing
	end

	local created = Instance.new("TextChannel")
	created.Name = CHANNEL_NAME
	created.Parent = folder
	channel = created
	return created
end

local function join(player: Player)
	local target = ensureChannel()
	if not target then
		return
	end
	-- AddUserAsync ağ çağrısı yapıyor ve oyuncu hazır olmadan başarısız
	-- olabiliyor; birkaç kez deniyoruz
	task.spawn(function()
		for attempt = 1, 5 do
			local ok = pcall(function()
				target:AddUserAsync(player.UserId)
			end)
			if ok then
				return
			end
			task.wait(attempt)
		end
		warn(string.format("[Announce] %s Summons kanalina eklenemedi", player.Name))
	end)
end

--[[
	Herkese bir duyuru gönderir.

	`text` RichText olabilir; renkleri çağıran seçiyor (nadirlik rengi).
	İstemci metni olduğu gibi kanala yazıyor.
]]
function AnnounceService.Summon(text: string)
	local now = os.clock()
	if recent[text] and now - recent[text] < DEDUPE_SECONDS then
		return
	end
	recent[text] = now

	-- Eski kayıtları temizle ki tablo büyümesin
	for key, at in recent do
		if now - at > 60 then
			recent[key] = nil
		end
	end

	if summonsRemote then
		summonsRemote:FireAllClients(text)
	end
end

--[[ Renk -> "#RRGGBB". Duyuru metinlerinde nadirlik rengi için. ]]
function AnnounceService.Hex(color: Color3): string
	return string.format("#%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5))
end

--[[ Metni verilen renkte ve kalın yazar. ]]
function AnnounceService.Paint(text: string, color: Color3): string
	return string.format('<font color="%s"><b>%s</b></font>', AnnounceService.Hex(color), text)
end

function AnnounceService.Start()
	summonsRemote = Net.Get("Summons")

	--[[
		Sekmeler kapalıysa kanal sohbette görünmüyor; mesajlar yine
		düşüyor ama General'in içinde karışık. Sekmeyi açıyoruz ki
		Summons ayrı bir yer olsun.
	]]
	pcall(function()
		local tabs = TextChatService:FindFirstChildOfClass("ChannelTabsConfiguration")
		if tabs then
			tabs.Enabled = true
		end
	end)

	ensureChannel()

	for _, player in Players:GetPlayers() do
		join(player)
	end
	Players.PlayerAdded:Connect(join)
end

return AnnounceService
