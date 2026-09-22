--!strict
--[[
	Çağrılar, istemci tarafı: sohbetteki Summons sekmesi ve ekranın
	üstündeki geri sayım.

	═══ SOHBET ═════════════════════════════════════════════════════════════

	Sunucu (AnnounceService) "Summons" kanalını kuruyor ve metni remote'la
	gönderiyor; burada kanala yazılıyor. DisplaySystemMessage yalnızca
	istemcide çalıştığı için bu iş burada.

	Kanal henüz gelmediyse (sunucu oyuncuyu üye yapmadan önce) sistem
	kanalına düşüyor — duyuru kaybolmasın.

	═══ GERİ SAYIM ═════════════════════════════════════════════════════════

	Sunucuya sorulmuyor: çağrılar os.time'a hizalı ve formül Config'te
	(GetNextSummonAt). İstemci aynı formülü sunucu saatiyle
	(GetServerTimeNow) çalıştırıyor, yani iki taraf aynı saniyeyi görüyor
	ve saniyede bir paket gitmiyor.

	Oyuncunun konveyörü o kademeyi henüz açmadıysa sayaç SÖNÜK ve altında
	nasıl açılacağı yazıyor. Sayaç hem "ne zaman" hem "nasıl alırım"
	sorusunun cevabı.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local UiKit = require(script.Parent.UiKit)

local Summons = {}

local player = Players.LocalPlayer

local CHANNEL_NAME = "Summons"

export type Handle = {
	Destroy: () -> (),
}

local function formatClock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local h = math.floor(seconds / 3600)
	local m = math.floor(seconds % 3600 / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

function Summons.Create(screen: ScreenGui): Handle
	-- ─── Sohbet ─────────────────────────────────────────────────────────────

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

	local chatConnection = Net.Get("Summons").OnClientEvent:Connect(function(text)
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

	-- ─── Geri sayım ─────────────────────────────────────────────────────────

	local bar = Instance.new("Frame")
	bar.Name = "SummonTimer"
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 8)
	bar.Size = UDim2.fromOffset(0, 40)
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.BackgroundColor3 = UiKit.SHELL_DEEP
	bar.BackgroundTransparency = 0.15
	bar.BorderSizePixel = 0
	bar.ZIndex = 2
	bar.Parent = screen
	UiKit.Corner(bar, 20)
	UiKit.Stroke(bar, UiKit.DIM, 1.2, 0.4)

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = bar

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 16)
	layout.Parent = bar

	type Cell = { event: Config.SummonEvent, title: TextLabel, clock: TextLabel, hint: TextLabel }
	local cells: { Cell } = {}

	--[[
		Sıra ekranda Mythic önce: daha yakın ve daha sık olan önde.
		Config'teki sıra (Secret önce) çakışma önceliği için, gösterim için
		değil.
	]]
	local shown = table.clone(Config.SummonEvents)
	table.sort(shown, function(a, b)
		return a.every < b.every
	end)

	for index, event in shown do
		local rarity = Config.Rarities[event.rarity]
		local tone = if rarity then rarity.color else UiKit.INK

		local cell = Instance.new("Frame")
		cell.LayoutOrder = index
		cell.Size = UDim2.fromOffset(0, 34)
		cell.AutomaticSize = Enum.AutomaticSize.X
		cell.BackgroundTransparency = 1
		cell.ZIndex = 3
		cell.Parent = bar

		local title = Instance.new("TextLabel")
		title.Position = UDim2.fromOffset(0, 1)
		title.Size = UDim2.fromOffset(0, 16)
		title.AutomaticSize = Enum.AutomaticSize.X
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBlack
		title.TextSize = 12
		title.TextColor3 = tone
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.Text = string.upper(event.rarity) .. " SUMMON"
		title.ZIndex = 3
		title.Parent = cell

		local clock = Instance.new("TextLabel")
		clock.Position = UDim2.fromOffset(0, 16)
		clock.Size = UDim2.fromOffset(0, 18)
		clock.AutomaticSize = Enum.AutomaticSize.X
		clock.BackgroundTransparency = 1
		clock.Font = Enum.Font.GothamBold
		clock.TextSize = 15
		clock.TextColor3 = UiKit.INK
		clock.TextXAlignment = Enum.TextXAlignment.Left
		clock.Text = "--:--"
		clock.ZIndex = 3
		clock.Parent = cell

		-- Kilitliyken saatin yanında kısa not; açıkken boş ve yer kaplamıyor
		local hint = Instance.new("TextLabel")
		hint.AnchorPoint = Vector2.new(0, 0)
		hint.Position = UDim2.fromOffset(0, 16)
		hint.Size = UDim2.fromOffset(0, 18)
		hint.AutomaticSize = Enum.AutomaticSize.X
		hint.BackgroundTransparency = 1
		hint.Font = Enum.Font.GothamMedium
		hint.TextSize = 11
		hint.TextColor3 = UiKit.DIM
		hint.TextXAlignment = Enum.TextXAlignment.Left
		hint.Text = ""
		hint.ZIndex = 3
		hint.Parent = cell

		table.insert(cells, { event = event, title = title, clock = clock, hint = hint })
	end

	local elapsed = 1
	local tick = RunService.Heartbeat:Connect(function(delta)
		elapsed += delta
		if elapsed < 0.25 then
			return
		end
		elapsed = 0

		local now = workspace:GetServerTimeNow()
		local level = player:GetAttribute("Upg_ConveyorSpeed") :: number?

		for _, cell in cells do
			local at = Config.GetNextSummonAt(cell.event, math.floor(now))
			local left = at - now
			cell.clock.Text = formatClock(left)

			local unlocked = Config.IsRarityUnlocked(cell.event.rarity, level or 0)
			local rarity = Config.Rarities[cell.event.rarity]
			cell.title.TextColor3 = if unlocked and rarity then rarity.color else UiKit.DIM
			cell.clock.TextColor3 = if unlocked
				then (if left <= Config.SummonWarning then UiKit.WARN else UiKit.INK)
				else UiKit.DIM

			if unlocked then
				cell.hint.Text = ""
			else
				local gate = Config.RarityUnlock[cell.event.rarity]
				cell.hint.Text = string.format("needs Conveyor Speed %d", if gate then gate.unlockLevel else 0)
			end

			-- Not saatin sağına düşsün: saatin genişliği değiştikçe kayıyor
			cell.hint.Position = UDim2.fromOffset(cell.clock.AbsoluteSize.X + 8, 17)
		end
	end)

	return {
		Destroy = function()
			chatConnection:Disconnect()
			tick:Disconnect()
			bar:Destroy()
		end,
	}
end

return Summons
