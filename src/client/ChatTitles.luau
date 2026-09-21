--!strict
--[[
	Sohbette isimden önce unvan gösterir.

	Unvanı sunucu belirliyor ve oyuncunun "Title" niteliğine yazıyor
	(TitleService). Nitelik replike olduğu için burada herkesin unvanını
	okuyabiliyoruz; ek remote gerekmiyor.

	Sohbet mesajının görünümü yalnızca istemcide değiştirilebiliyor,
	o yüzden bu kısım burada.

	DİKKAT: TextChatService.OnIncomingMessage tek bir fonksiyon tutuyor.
	Başka bir yerde de atanırsa biri diğerini eziyor. Bu modül zaten
	atanmış bir işleyici varsa onu çağırıp sonucunu koruyor, yani
	üzerine yazmıyor.

	Kullanım (init.client.luau içinde bir kez):
		require(script.ChatTitles).Start()
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

local ChatTitles = {}

--[[
	Unvan rengi sırasına göre: alt unvanlar sönük, üst unvanlar parlak.
	Nadirlik renkleriyle aynı mantık, oyuncu bir bakışta seviyeyi anlıyor.
]]
local TIER_COLORS = {
	Color3.fromRGB(170, 176, 186),  -- 1-2   sönük gri
	Color3.fromRGB(120, 200, 255),  -- 3-4   mavi
	Color3.fromRGB( 80, 220, 140),  -- 5-6   yeşil
	Color3.fromRGB(190, 130, 255),  -- 7-8   mor
	Color3.fromRGB(255, 175,  60),  -- 9-10  turuncu
}

local colorById: { [string]: Color3 } = {}
local nameById: { [string]: string } = {}

local function buildLookup()
	local highest = 1
	for _, def in Config.Titles do
		if def.order > highest then
			highest = def.order
		end
	end

	for _, def in Config.Titles do
		nameById[def.name] = def.id

		-- order 1..highest aralığını renk kademelerine yay
		local ratio = (def.order - 1) / math.max(1, highest - 1)
		local index = math.clamp(math.floor(ratio * #TIER_COLORS) + 1, 1, #TIER_COLORS)
		colorById[def.name] = TIER_COLORS[index]
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

	-- Varsa önceki işleyiciyi koru, üzerine yazma
	local previous = TextChatService.OnIncomingMessage

	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local properties: TextChatMessageProperties

		if previous then
			local ok, result = pcall(previous, message)
			properties = if ok and result then result else Instance.new("TextChatMessageProperties")
		else
			properties = Instance.new("TextChatMessageProperties")
		end

		local title = titleOf(message)
		if title == "" then
			return properties
		end

		-- Önceki işleyici öneki değiştirdiyse onun üstüne ekliyoruz
		local prefix = if properties.PrefixText ~= "" then properties.PrefixText else message.PrefixText
		local color = colorById[title] or TIER_COLORS[1]

		properties.PrefixText = string.format(
			'<font color="#%s">[%s]</font> %s',
			toHex(color), title, prefix
		)

		return properties
	end
end

return ChatTitles
