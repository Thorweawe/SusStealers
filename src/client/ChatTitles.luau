--!strict
--[[
	Sohbette isimden önce unvan gösterir.

	Unvanı sunucu belirliyor ve oyuncunun "Title" niteliğine yazıyor
	(TitleService). Nitelik replike olduğu için burada herkesin unvanını
	okuyabiliyoruz; ek remote gerekmiyor.

	Sohbet mesajının görünümü yalnızca istemcide değiştirilebiliyor,
	o yüzden bu kısım burada.

	DİKKAT: TextChatService.OnIncomingMessage tek bir fonksiyon tutuyor ve
	Roblox bu callback'in OKUNMASINA izin vermiyor ("you can only set the
	callback value"). Eski sürüm önceki işleyiciyi okuyup zincirlemeye
	çalışıyordu; okuma hata verdiği için panel hiç kurulmuyor, unvanlar
	sohbette hiç çıkmıyordu. Artık callback'in TEK sahibi bu modül: başka
	bir modül mesajları değiştirmek isterse ChatTitles.AddTransform ile
	kaydolsun, OnIncomingMessage'a kendisi yazmasın.

	Kullanım (init.client.luau içinde bir kez):
		require(script.ChatTitles).Start()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local ChatTitles = {}

--[[
	Unvan rengi NADİRLİĞİNE göre (Config.GetTitleColor): 2026-09-28'den beri
	unvanlar Common..Secret kademeli; Epic ve üstü kalın, Mythic/Secret ✦ ile.
]]

-- Başka modüllerin mesaj dönüştürücüleri (unvandan ÖNCE çalışıyor)
type Transform = (message: TextChatMessage, properties: TextChatMessageProperties) -> ()
local transforms: { Transform } = {}

--[[ Gelen mesajlara ek bir dönüştürücü kaydeder (OnIncomingMessage'ın yerine). ]]
function ChatTitles.AddTransform(fn: Transform)
	table.insert(transforms, fn)
end

local rarityByName: { [string]: string } = {}

local function buildLookup()
	for _, def in Config.Titles do
		rarityByName[def.name] = def.rarity
	end
end

local function toHex(color: Color3): string
	return string.format("%02X%02X%02X",
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5))
end

--[[ Mesajı gönderenin unvanı. Bulunamazsa boş dizi. ]]
local function titleOf(message: TextChatMessage): string
	local source = message.TextSource
	if not source then
		return ""
	end

	local player = Players:GetPlayerByUserId(source.UserId)
	if not player then
		return ""
	end

	local title = player:GetAttribute("Title")
	return if typeof(title) == "string" then title else ""
end

function ChatTitles.Start()
	buildLookup()

	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local properties = Instance.new("TextChatMessageProperties")
		for _, fn in transforms do
			pcall(fn, message, properties)
		end

		local title = titleOf(message)
		if title == "" then
			return properties
		end

		-- Bir dönüştürücü öneki değiştirdiyse onun üstüne ekliyoruz
		local prefix = if properties.PrefixText ~= "" then properties.PrefixText else message.PrefixText
		local rarity = rarityByName[title] or "Common"
		local color = Config.GetTitleColor(rarity)
		local order = Config.Rarities[rarity] and Config.Rarities[rarity].order or 1

		-- Geliştirici: kalın, kırmızı köşeli parantez, altın yazı
		if title == Config.DeveloperTitle then
			properties.PrefixText = string.format(
				'<b><font color="#FF4655">[</font><font color="#FFD23C">%s</font><font color="#FF4655">]</font></b> %s',
				title, prefix
			)
			return properties
		end

		local shown = if order >= 6 then "✦ " .. title .. " ✦" elseif order >= 5 then "★ " .. title else title
		properties.PrefixText = string.format(
			if order >= 4 then '<b><font color="#%s">[%s]</font></b> %s' else '<font color="#%s">[%s]</font> %s',
			toHex(color), shown, prefix
		)

		return properties
	end
end

return ChatTitles
