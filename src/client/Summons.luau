--!strict
--[[
	Summons sohbet sekmesi, istemci tarafı.

	Sunucu (AnnounceService) "Summons" kanalını kuruyor ve metni remote'la
	gönderiyor; burada kanala yazılıyor. DisplaySystemMessage yalnızca
	istemcide çalıştığı için bu iş burada.

	Kanal henüz gelmediyse (sunucu oyuncuyu üye yapmadan önce) sistem
	kanalına düşüyor — duyuru kaybolmasın.

	Eskiden burada saatli çağrıların geri sayımı da vardı; çağrılar
	kaldırıldı, sayaç da onlarla gitti.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Net = require(ReplicatedStorage:WaitForChild("Shared").Net)

local Summons = {}

local CHANNEL_NAME = "Summons"

export type Handle = {
	Destroy: () -> (),
}

function Summons.Create(_screen: ScreenGui): Handle
	--[[
		Sekmeler kapalıysa Summons ayrı görünmüyor. Sunucu da açıyor ama
		yayılması bir kare sürebiliyor; burada da açmak zararsız.
	]]
	pcall(function()
		local tabs = TextChatService:FindFirstChildOfClass("ChannelTabsConfiguration")
		if tabs then
			tabs.Enabled = true
		end
	end)

	local function channel(): TextChannel?
		local folder = TextChatService:FindFirstChild("TextChannels")
		if not folder then
			return nil
		end
		local own = folder:FindFirstChild(CHANNEL_NAME)
		if own and own:IsA("TextChannel") then
			return own
		end
		local system = folder:FindFirstChild("RBXSystem")
		if system and system:IsA("TextChannel") then
			return system
		end
		return nil
	end

	local connection = Net.Get("Summons").OnClientEvent:Connect(function(text)
		if typeof(text) ~= "string" then
			return
		end
		local target = channel()
		if target then
			pcall(function()
				target:DisplaySystemMessage("[SUMMON] " .. text)
			end)
		end
	end)

	return {
		Destroy = function()
			connection:Disconnect()
		end,
	}
end

return Summons
