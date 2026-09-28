--!strict
--[[
	Gear Shop penceresi: lobideki dükkânın tezgâhında E'ye basınca açılıyor
	(prompt "GearPrompt"; istemci kendi tetiklemesini görüyor).

	Her alet bir kart: ikon, ad, ne yaptığı, sayısı (hız / zıplama /
	bekleme), fiyat ve BUY ya da OWNED. 2026-09-28'den beri mağazanın
	dilinde (FancyKit: renkli kart, dönen ışın, süzülen 3B ikon). Satın alma GearBuy remote'uyla;
	fiyat ve sahiplik sunucuda (GearService). Sahip olunanlar "GearOwned"
	niteliğinden okunuyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local FancyKit = require(script.Parent.FancyKit)
local UiKit = require(script.Parent.UiKit)

local GearPanel = {}

local player = Players.LocalPlayer

local ACCENT = UiKit.CREW.ORANGE
local Z = 45
local OUTLINE = Color3.fromRGB(22, 20, 34)
local GREEN = Color3.fromRGB(70, 200, 70)
-- Kart rengi (2026-09-28 mağaza dili)
local TINT: { [string]: Color3 } = {
	SlapGlove = Color3.fromRGB(230, 70, 80),
	SpeedCoil = Color3.fromRGB(50, 140, 240),
	StunGun = Color3.fromRGB(240, 180, 30),
	EmergencyButton = Color3.fromRGB(160, 80, 235),
}

export type Panel = {
	Open: () -> (),
	Destroy: () -> (),
}

--[[ Kartın sayı satırı: aletin ölçülebilir etkisi. ]]
local function fmt(n: number): string
	return if n == math.floor(n) then tostring(n) else string.format("%.1f", n)
end

local function statLine(def: Config.GearDef): string
	if def.kind == "speed" then
		return string.format("Speed %d · Shift %d  (run %d)", def.walkSpeed or 0, def.sprintSpeed or 0, Config.SprintWalkSpeed)
	elseif def.kind == "slap" then
		return string.format("Range %d · cooldown %ss", def.range or 0, fmt(def.cooldown or 0))
	elseif def.kind == "stun" then
		return string.format("Range %d · freeze %ss · cooldown %ss", def.range or 0, fmt(def.stun or 0), fmt(def.cooldown or 0))
	elseif def.kind == "cloak" then
		return string.format("Invisible %ss · cooldown %ss", fmt(def.duration or 0), fmt(def.cooldown or 0))
	elseif def.kind == "blast" then
		return string.format("Radius %d · cooldown %ss", def.range or 0, fmt(def.cooldown or 0))
	end
	return ""
end

function GearPanel.Create(screen: ScreenGui): Panel
	local W, H, HEADER = 40 + #Config.Gear * 172, 450, 66
	local root = UiKit.Window(screen, "GearPanel", ACCENT)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(W, H)
	root.Visible = false
	root.ZIndex = Z
	local driver = FancyKit.driver(root)
	local shell = FancyKit.shell(root, "GEAR SHOP", {
		Color3.fromRGB(255, 120, 40), Color3.fromRGB(240, 60, 70), Color3.fromRGB(255, 190, 40),
	}, HEADER, Z, driver, 46)
	local close = shell.close

	local hint = Instance.new("TextLabel")
	hint.Position = UDim2.fromOffset(0, HEADER + 6)
	hint.Size = UDim2.new(1, 0, 0, 22)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.FredokaOne
	hint.TextSize = 16
	hint.TextColor3 = Color3.fromRGB(220, 228, 255)
	hint.Text = string.format("Bought once, yours forever. Equip from your hotbar (1-%d), click to use.", #Config.Gear)
	hint.ZIndex = Z + 2
	hint.Parent = root
	local hs = Instance.new("UIStroke")
	hs.Color = OUTLINE
	hs.Thickness = 2
	hs.Parent = hint

	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(16, HEADER + 36)
	row.Size = UDim2.new(1, -32, 1, -(HEADER + 50))
	row.BackgroundTransparency = 1
	row.ZIndex = Z + 1
	row.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row

	local buyRemote = Net.Get("GearBuy")

	type Card = { def: Config.GearDef, buy: FancyKit.Button, tint: Color3 }
	local cards: { Card } = {}

	for index, def in Config.Gear do
		local tint = TINT[def.id] or ACCENT
		local slot = Instance.new("Frame")
		slot.LayoutOrder = index
		slot.Size = UDim2.new(1 / #Config.Gear, -9, 1, 0)
		slot.BackgroundTransparency = 1
		slot.ZIndex = Z + 2
		slot.Parent = row
		local card = FancyKit.card(slot, tint, UDim2.fromScale(1, 1), Z + 2, driver, UDim2.new(0.5, 0, 0, 74))
		FancyKit.hover(slot, 1.03)

		local stage = Instance.new("Frame")
		stage.AnchorPoint = Vector2.new(0.5, 0)
		stage.Position = UDim2.new(0.5, 0, 0, 12)
		stage.Size = UDim2.fromOffset(120, 120)
		stage.BackgroundTransparency = 1
		stage.ZIndex = Z + 4
		stage.Parent = card
		FancyKit.glow(stage, tint:Lerp(Color3.new(1, 1, 1), 0.5), 1.25, 0.35, Z + 3)
		local icon = UiKit.GearIcon(stage, 100, def.id)
		FancyKit.bob(icon, driver, 4, 2.4, index * 1.1, 5)

		local name = FancyKit.title(card, def.name, 22, Color3.new(1, 1, 1), Color3.fromRGB(255, 236, 190), Z + 5, driver)
		name.Position = UDim2.fromOffset(4, 138)
		name.Size = UDim2.new(1, -8, 0, 28)

		local blurb = Instance.new("TextLabel")
		blurb.Position = UDim2.fromOffset(10, 172)
		blurb.Size = UDim2.new(1, -20, 0, 64)
		blurb.BackgroundTransparency = 1
		blurb.Font = Enum.Font.FredokaOne
		blurb.TextSize = 14
		blurb.TextWrapped = true
		blurb.TextYAlignment = Enum.TextYAlignment.Top
		blurb.TextColor3 = Color3.new(1, 1, 1)
		blurb.Text = def.blurb
		blurb.ZIndex = Z + 5
		blurb.Parent = card
		local bs = Instance.new("UIStroke")
		bs.Color = OUTLINE
		bs.Thickness = 1.6
		bs.Parent = blurb

		local chip = Instance.new("Frame")
		chip.AnchorPoint = Vector2.new(0.5, 0)
		chip.Position = UDim2.new(0.5, 0, 0, 240)
		chip.Size = UDim2.new(1, -18, 0, 36)
		chip.BackgroundColor3 = Color3.new(0, 0, 0)
		chip.BackgroundTransparency = 0.55
		chip.ZIndex = Z + 5
		chip.Parent = card
		FancyKit.corner(chip, 10)
		local stat = Instance.new("TextLabel")
		stat.Position = UDim2.fromOffset(6, 0)
		stat.Size = UDim2.new(1, -12, 1, 0)
		stat.BackgroundTransparency = 1
		stat.Font = Enum.Font.FredokaOne
		stat.TextSize = 13
		stat.TextWrapped = true
		stat.TextColor3 = Color3.fromRGB(255, 236, 150)
		stat.Text = statLine(def)
		stat.ZIndex = Z + 6
		stat.Parent = chip

		local buy = FancyKit.button(card, UDim2.new(1, -18, 0, 50), GREEN, 22, Z + 6, driver, index * 0.6)
		buy.holder.AnchorPoint = Vector2.new(0.5, 1)
		buy.holder.Position = UDim2.new(0.5, 0, 1, -10)

		local id = def.id
		buy.button.MouseButton1Click:Connect(function()
			if buy.button.Active then
				buyRemote:FireServer(id)
			end
		end)
		table.insert(cards, { def = def, buy = buy, tint = tint })
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
			if has then
				card.buy.set("OWNED", nil)
			else
				-- Parası yetmiyorsa soluk yeşil ama yine basılabilir (sunucu reddediyor)
				card.buy.set("$" .. Config.FormatCash(card.def.price), if cash >= card.def.price then GREEN else GREEN:Lerp(Color3.fromRGB(90, 96, 110), 0.55))
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
