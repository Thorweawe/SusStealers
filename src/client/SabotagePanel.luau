--!strict
--[[
	Sabotaj sayfası (Envanter → SABOTAGE; sunucu tarafı SabotageService).

	Üstte eşyalar: her satırda ad, açıklama, elde kaç tane olduğu ve
	satın alma düğmesi. Satıra basınca o eşya SEÇİLİYOR.
	Altta hedefler: sunucudaki diğer oyuncular. Seçili eşya bir hedefin
	USE düğmesiyle ona kullanılıyor.

	Doğrulamaların hepsi sunucuda; burası yalnızca durumu gösteriyor:
	  "Sabotages"           — adetler ("Blackout=2,LockJam=0,...")
	  "SabotageReadyAt"     — kullanan için bekleme bitişi (sunucu saati)
	  hedefte "SabotageShieldUntil" — o üsse şimdilik sabotaj yok
	Fiyat "Income" niteliğinden, sunucuyla aynı formülle (Config).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local UiKit = require(script.Parent.UiKit)

local SabotagePanel = {}

export type Panel = {
	Toggle: () -> (),
	Destroy: () -> (),
}

local Z = 30
local ACCENT = UiKit.CREW.RED
local ITEM_H = 64
local TARGET_H = 44

local function icon(slot: Frame, id: string, size: number, tint: Color3)
	if id == "Blackout" then
		UiKit.Bolt(slot, size, tint)
	elseif id == "LockJam" then
		UiKit.Lock(slot, size, tint)
	else
		UiKit.EyeIcon(slot, size, true)
	end
end
SabotagePanel.Icon = icon

local function label(parent: Instance, text: string, font: Enum.Font, size: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Text = text
	l.ZIndex = Z + 3
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 14
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextStrokeTransparency = 0.5
	b.Text = text
	b.ZIndex = Z + 4
	b.Parent = parent
	UiKit.Corner(b, 10)
	return b
end

function SabotagePanel.Create(screen: ScreenGui, host: Frame, onCount: ((string) -> ())?): Panel
	local player = Players.LocalPlayer
	local remote = Net.Get("SabotageAction")

	local root = UiKit.Page(host, "SabotagePanel")
	root.ZIndex = Z

	local title, sub = UiKit.Heading(root, "SABOTAGE", ACCENT)
	title.ZIndex = Z + 2
	sub.ZIndex = Z + 2

	local items = Instance.new("Frame")
	items.Name = "Items"
	items.Position = UDim2.fromOffset(16, 60)
	items.Size = UDim2.new(1, -32, 0, #Config.Sabotages * (ITEM_H + 8))
	items.BackgroundTransparency = 1
	items.ZIndex = Z + 1
	items.Parent = root

	local header = label(root, "CHOOSE A TARGET", Enum.Font.GothamBlack, 13, UiKit.MUTED)
	header.Position = UDim2.fromOffset(18, 66 + #Config.Sabotages * (ITEM_H + 8))
	header.Size = UDim2.new(1, -36, 0, 16)

	local targetsTop = 86 + #Config.Sabotages * (ITEM_H + 8)
	local targets = Instance.new("ScrollingFrame")
	targets.Name = "Targets"
	targets.Position = UDim2.fromOffset(16, targetsTop)
	targets.Size = UDim2.new(1, -32, 1, -(targetsTop + 12))
	targets.BackgroundTransparency = 1
	targets.BorderSizePixel = 0
	targets.ScrollBarThickness = 6
	targets.AutomaticCanvasSize = Enum.AutomaticSize.Y
	targets.CanvasSize = UDim2.new()
	targets.ZIndex = Z + 1
	targets.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = targets

	local selected = Config.Sabotages[1].id
	local refresh: () -> ()

	local function counts(): { [string]: number }
		local out = {}
		local raw = player:GetAttribute("Sabotages")
		if typeof(raw) == "string" then
			for id, n in string.gmatch(raw, "(%w+)=(%d+)") do
				out[id] = tonumber(n) or 0
			end
		end
		return out
	end

	local function waitLeft(): number
		local readyAt = player:GetAttribute("SabotageReadyAt")
		if typeof(readyAt) ~= "number" then
			return 0
		end
		return math.max(0, readyAt - workspace:GetServerTimeNow())
	end

	-- ─── Eşyalar ─────────────────────────────────────────────────────────

	type ItemRow = { frame: GuiObject, stroke: UIStroke, count: TextLabel, buy: TextButton }
	local rows: { [string]: ItemRow } = {}

	for i, def in Config.Sabotages do
		local row = Instance.new("TextButton")
		row.Name = def.id
		row.AutoButtonColor = false
		row.Text = ""
		row.Position = UDim2.fromOffset(0, (i - 1) * (ITEM_H + 8))
		row.Size = UDim2.new(1, 0, 0, ITEM_H)
		row.BackgroundColor3 = UiKit.ROW
		row.BorderSizePixel = 0
		row.ZIndex = Z + 2
		row.Parent = items
		UiKit.Corner(row, 12)
		local stroke = UiKit.Stroke(row, def.color, 2, 1)

		local slot = Instance.new("Frame")
		slot.AnchorPoint = Vector2.new(0, 0.5)
		slot.Position = UDim2.new(0, 10, 0.5, 0)
		slot.Size = UDim2.fromOffset(44, 44)
		slot.BackgroundColor3 = def.color:Lerp(Color3.new(0, 0, 0), 0.55)
		slot.BorderSizePixel = 0
		slot.ZIndex = Z + 3
		slot.Parent = row
		UiKit.Corner(slot, 10)
		icon(slot, def.id, 44, def.color)

		local name = label(row, string.format("%s  ·  %ds", def.name, def.duration), Enum.Font.GothamBlack, 16, Color3.new(1, 1, 1))
		name.Position = UDim2.fromOffset(64, 10)
		name.Size = UDim2.new(1, -230, 0, 20)
		local desc = label(row, def.desc, Enum.Font.GothamMedium, 12, UiKit.MUTED)
		desc.Position = UDim2.fromOffset(64, 32)
		desc.Size = UDim2.new(1, -230, 0, 18)

		local count = label(row, "x0", Enum.Font.GothamBlack, 18, def.color)
		count.AnchorPoint = Vector2.new(1, 0.5)
		count.Position = UDim2.new(1, -128, 0.5, 0)
		count.Size = UDim2.fromOffset(44, 24)
		count.TextXAlignment = Enum.TextXAlignment.Right

		local buy = button(row, "$0", UiKit.CREW.LIME:Lerp(Color3.new(0, 0, 0), 0.2))
		buy.Position = UDim2.new(1, -10, 0.5, 0)
		buy.Size = UDim2.fromOffset(108, 38)
		buy.MouseButton1Click:Connect(function()
			remote:FireServer("buy", def.id)
		end)

		row.MouseButton1Click:Connect(function()
			selected = def.id
			for id, r in rows do
				r.stroke.Transparency = if id == selected then 0 else 1
			end
			refresh()
		end)

		rows[def.id] = { frame = row, stroke = stroke, count = count, buy = buy }
	end
	rows[selected].stroke.Transparency = 0

	-- ─── Hedefler ────────────────────────────────────────────────────────

	type TargetRow = { frame: Frame, status: TextLabel, use: TextButton, target: Player }
	local targetRows: { [Player]: TargetRow } = {}

	local function addTarget(other: Player)
		if other == player or targetRows[other] then
			return
		end
		local frame = Instance.new("Frame")
		frame.Name = other.Name
		frame.Size = UDim2.new(1, -8, 0, TARGET_H)
		frame.BackgroundColor3 = UiKit.ROW
		frame.BorderSizePixel = 0
		frame.ZIndex = Z + 2
		frame.Parent = targets
		UiKit.Corner(frame, 10)

		local name = label(frame, other.DisplayName, Enum.Font.GothamBlack, 15, Color3.new(1, 1, 1))
		name.Position = UDim2.fromOffset(14, 0)
		name.Size = UDim2.new(0.45, 0, 1, 0)
		local status = label(frame, "", Enum.Font.GothamBold, 12, UiKit.MUTED)
		status.Position = UDim2.new(0.45, 8, 0, 0)
		status.Size = UDim2.new(0.55, -120, 1, 0)

		local use = button(frame, "USE", ACCENT)
		use.Position = UDim2.new(1, -8, 0.5, 0)
		use.Size = UDim2.fromOffset(92, 32)
		use.MouseButton1Click:Connect(function()
			remote:FireServer("use", selected, other.UserId)
		end)

		targetRows[other] = { frame = frame, status = status, use = use, target = other }
	end

	local function removeTarget(other: Player)
		local row = targetRows[other]
		if row then
			row.frame:Destroy()
			targetRows[other] = nil
		end
	end

	local empty = label(targets, "No other players on this server yet.", Enum.Font.GothamMedium, 13, UiKit.MUTED)
	empty.Size = UDim2.new(1, 0, 0, 30)
	empty.LayoutOrder = 99

	-- ─── Durum ───────────────────────────────────────────────────────────

	function refresh()
		local have = counts()
		local income = player:GetAttribute("Income")
		income = if typeof(income) == "number" then income else 0
		local cash = player:GetAttribute("Cash")
		cash = if typeof(cash) == "number" then cash else 0

		local total = 0
		for _, def in Config.Sabotages do
			local n = have[def.id] or 0
			total += n
			local row = rows[def.id]
			row.count.Text = "x" .. n
			local full = n >= Config.SabotageMaxStack
			local price = Config.GetSabotagePrice(def, income)
			row.buy.Text = if full then "MAX" else "$" .. Config.FormatCash(price)
			row.buy.BackgroundColor3 = if full or cash < price
				then Color3.fromRGB(90, 96, 108)
				else UiKit.CREW.LIME:Lerp(Color3.new(0, 0, 0), 0.2)
		end
		if onCount then
			onCount(string.format("%d item%s", total, if total == 1 then "" else "s"))
		end

		local left = waitLeft()
		local selDef = Config.GetSabotage(selected)
		local canUse = left <= 0 and (have[selected] or 0) > 0
		if left > 0 then
			sub.Text = string.format("Recharging: %s until your next sabotage.", Config.FormatDuration(left))
		elseif (have[selected] or 0) <= 0 then
			sub.Text = string.format("Buy a %s first, then pick a target.", if selDef then selDef.name else "sabotage")
		else
			sub.Text = string.format("Ready! %s selected - one sabotage every %d min.",
				if selDef then selDef.name else "", Config.SabotageUserCooldown // 60)
		end

		local now = workspace:GetServerTimeNow()
		local any = false
		for other, row in targetRows do
			any = true
			local shield = other:GetAttribute("SabotageShieldUntil")
			local shieldLeft = if typeof(shield) == "number" then shield - now else 0
			local ok = canUse and shieldLeft <= 0
			if shieldLeft > 0 then
				row.status.Text = "Shielded " .. Config.FormatDuration(shieldLeft)
			elseif other:GetAttribute("CommsJam") then
				row.status.Text = "Comms jammed"
			else
				row.status.Text = ""
			end
			row.use.Active = ok
			row.use.AutoButtonColor = ok
			row.use.BackgroundColor3 = if ok then ACCENT else Color3.fromRGB(90, 96, 108)
		end
		empty.Visible = not any
	end

	local connections: { RBXScriptConnection } = {}
	for _, other in Players:GetPlayers() do
		addTarget(other)
	end
	table.insert(connections, Players.PlayerAdded:Connect(function(other)
		addTarget(other)
		refresh()
	end))
	table.insert(connections, Players.PlayerRemoving:Connect(function(other)
		removeTarget(other)
		refresh()
	end))
	for _, attr in { "Sabotages", "SabotageReadyAt" } do
		table.insert(connections, player:GetAttributeChangedSignal(attr):Connect(refresh))
	end

	-- Geri sayımlar için: açıkken saniyede bir
	local alive = true
	task.spawn(function()
		while alive do
			if root.Visible then
				refresh()
			end
			task.wait(1)
		end
	end)
	refresh()

	return {
		Toggle = function()
			root.Visible = not root.Visible
			if root.Visible then
				refresh()
			end
		end,
		Destroy = function()
			alive = false
			for _, c in connections do
				c:Disconnect()
			end
			root:Destroy()
		end,
	}
end

return SabotagePanel
