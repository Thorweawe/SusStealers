--!strict
--[[
	Gear Shop penceresi: lobideki dükkânın tezgâhında E'ye basınca açılıyor
	(prompt "GearPrompt"; istemci kendi tetiklemesini görüyor).

	Her alet bir kart: ikon, ad, ne yaptığı, sayısı (hız / zıplama /
	bekleme), fiyat ve BUY ya da OWNED. Satın alma GearBuy remote'uyla;
	fiyat ve sahiplik sunucuda (GearService). Sahip olunanlar "GearOwned"
	niteliğinden okunuyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local UiKit = require(script.Parent.UiKit)

local GearPanel = {}

local player = Players.LocalPlayer

local ACCENT = UiKit.CREW.ORANGE
local Z = 45

export type Panel = {
	Open: () -> (),
	Destroy: () -> (),
}

--[[ Kartın sayı satırı: aletin ölçülebilir etkisi. ]]
local function statLine(def: Config.GearDef): string
	if def.walkSpeed then
		return string.format("Speed %d  (normal %d)", def.walkSpeed, Config.NormalWalkSpeed)
	elseif def.jumpHeight then
		return string.format("Jump %d  (normal 7)", def.jumpHeight)
	elseif def.cooldown then
		return string.format("Range %d  ·  cooldown %ds", def.range or 8, def.cooldown)
	end
	return ""
end

function GearPanel.Create(screen: ScreenGui): Panel
	local root = UiKit.Window(screen, "GearPanel", ACCENT)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(560, 340)
	root.Visible = false
	root.ZIndex = Z

	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0, 52)
	band.BackgroundColor3 = ACCENT:Lerp(Color3.new(0, 0, 0), 0.6)
	band.BorderSizePixel = 0
	band.ZIndex = Z + 1
	band.Parent = root
	UiKit.Corner(band, 14)
	local bandFoot = Instance.new("Frame")
	bandFoot.Position = UDim2.new(0, 0, 1, -14)
	bandFoot.Size = UDim2.new(1, 0, 0, 14)
	bandFoot.BackgroundColor3 = band.BackgroundColor3
	bandFoot.BorderSizePixel = 0
	bandFoot.ZIndex = Z + 1
	bandFoot.Parent = band

	local badge = Instance.new("Frame")
	badge.Position = UDim2.fromOffset(14, 10)
	badge.Size = UDim2.fromOffset(32, 32)
	badge.BackgroundTransparency = 1
	badge.ZIndex = Z + 2
	badge.Parent = band
	UiKit.Crewmate(badge, 30, ACCENT)

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(56, 6)
	title.Size = UDim2.new(1, -100, 0, 26)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.5
	title.Text = "GEAR SHOP"
	title.ZIndex = Z + 2
	title.Parent = band

	local hint = Instance.new("TextLabel")
	hint.Position = UDim2.fromOffset(56, 30)
	hint.Size = UDim2.new(1, -100, 0, 16)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 12
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = UiKit.MUTED
	hint.Text = "Bought once, yours forever. Equip from your hotbar (1-3)."
	hint.ZIndex = Z + 2
	hint.Parent = band

	local close = UiKit.CloseButton(root)
	close.ZIndex = Z + 3

	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(14, 64)
	row.Size = UDim2.new(1, -28, 1, -78)
	row.BackgroundTransparency = 1
	row.ZIndex = Z + 1
	row.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local buyRemote = Net.Get("GearBuy")

	type Card = { def: Config.GearDef, button: TextButton, price: TextLabel }
	local cards: { Card } = {}

	for index, def in Config.Gear do
		local card = Instance.new("Frame")
		card.LayoutOrder = index
		card.Size = UDim2.new(1 / #Config.Gear, -7, 1, 0)
		card.BackgroundColor3 = ACCENT:Lerp(UiKit.ROW, 0.85)
		card.BorderSizePixel = 0
		card.ZIndex = Z + 2
		card.Parent = row
		UiKit.Corner(card, 12)
		UiKit.Stroke(card, ACCENT, 1.4, 0.55)

		local stage = Instance.new("Frame")
		stage.AnchorPoint = Vector2.new(0.5, 0)
		stage.Position = UDim2.new(0.5, 0, 0, 12)
		stage.Size = UDim2.fromOffset(76, 76)
		stage.BackgroundColor3 = UiKit.SHELL_DEEP
		stage.BorderSizePixel = 0
		stage.ZIndex = Z + 3
		stage.Parent = card
		UiKit.Corner(stage, 38)
		UiKit.GearIcon(stage, 56, def.id)

		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromOffset(6, 94)
		name.Size = UDim2.new(1, -12, 0, 20)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBlack
		name.TextSize = 15
		name.TextColor3 = UiKit.INK
		name.Text = def.name
		name.ZIndex = Z + 3
		name.Parent = card

		local blurb = Instance.new("TextLabel")
		blurb.Position = UDim2.fromOffset(8, 116)
		blurb.Size = UDim2.new(1, -16, 0, 44)
		blurb.BackgroundTransparency = 1
		blurb.Font = Enum.Font.GothamMedium
		blurb.TextSize = 11
		blurb.TextWrapped = true
		blurb.TextYAlignment = Enum.TextYAlignment.Top
		blurb.TextColor3 = UiKit.MUTED
		blurb.Text = def.blurb
		blurb.ZIndex = Z + 3
		blurb.Parent = card

		local stat = Instance.new("TextLabel")
		stat.Position = UDim2.fromOffset(6, 160)
		stat.Size = UDim2.new(1, -12, 0, 16)
		stat.BackgroundTransparency = 1
		stat.Font = Enum.Font.GothamBold
		stat.TextSize = 11
		stat.TextColor3 = ACCENT:Lerp(Color3.new(1, 1, 1), 0.3)
		stat.Text = statLine(def)
		stat.ZIndex = Z + 3
		stat.Parent = card

		local holder, button = UiKit.Raised(card, "Buy", UiKit.CREW.GREEN:Lerp(UiKit.GOOD, 0.35), UDim2.new(1, -16, 0, 40), 10)
		holder.AnchorPoint = Vector2.new(0.5, 1)
		holder.Position = UDim2.new(0.5, 0, 1, -8)
		holder.ZIndex = Z + 3
		local price = Instance.new("TextLabel")
		price.Size = UDim2.fromScale(1, 1)
		price.BackgroundTransparency = 1
		price.Font = Enum.Font.GothamBlack
		price.TextSize = 15
		price.TextColor3 = Color3.new(1, 1, 1)
		price.TextStrokeTransparency = 0.5
		price.ZIndex = Z + 7
		price.Parent = button

		local id = def.id
		button.MouseButton1Click:Connect(function()
			if button.Active then
				buyRemote:FireServer(id)
			end
		end)
		table.insert(cards, { def = def, button = button, price = price })
	end

	local function refresh()
		local owned: { [string]: boolean } = {}
		local raw = player:GetAttribute("GearOwned")
		if typeof(raw) == "string" then
			for id in string.gmatch(raw, "[^,]+") do
				owned[id] = true
			end
		end
		local cashValue = player:GetAttribute("Cash")
		local cash = if typeof(cashValue) == "number" then cashValue else 0
		for _, card in cards do
			local has = owned[card.def.id] == true
			card.button.Active = not has
			card.price.Text = if has then "OWNED" else "$" .. Config.FormatCash(card.def.price)
			local base = if has then UiKit.DIM else UiKit.CREW.GREEN:Lerp(UiKit.GOOD, 0.35)
			card.button.BackgroundColor3 = base
			card.button.BackgroundTransparency = if not has and cash < card.def.price then 0.35 else 0
			local grad = card.button:FindFirstChildOfClass("UIGradient")
			if grad then
				grad.Color = ColorSequence.new(base:Lerp(Color3.new(1, 1, 1), 0.22), base:Lerp(Color3.new(0, 0, 0), 0.18))
			end
		end
	end

	local ownedConn = player:GetAttributeChangedSignal("GearOwned"):Connect(refresh)
	local cashConn = player:GetAttributeChangedSignal("Cash"):Connect(function()
		if root.Visible then
			refresh()
		end
	end)

	close.Activated:Connect(function()
		root.Visible = false
	end)

	return {
		Open = function()
			root.Visible = true
			refresh()
		end,
		Destroy = function()
			ownedConn:Disconnect()
			cashConn:Disconnect()
			root:Destroy()
		end,
	}
end

return GearPanel
