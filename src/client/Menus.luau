--!strict
--[[
	Unvan seçimi ve iksir envanteri.

	İkisi de sürekli açık durması gereken şeyler değil, o yüzden tek bir
	üst katmanda sekme olarak duruyorlar. Ayrı ayrı panel yapmak ekranı
	iki kat kalabalıklaştırırdı.

	Açma düğmeleri sağ kenarda, üs panelinin altında; birbirine değmeyen
	tek boş şerit orası.

	Karar sunucuda: unvanı TitleService, iksiri PotionService doğruluyor.
	Buradan giden tek şey bir kimlik; açılmamış unvan ya da envanterde
	olmayan iksir sunucuda reddediliyor.

	Kullanım (init.client.luau içinde, screen kurulduktan sonra):
		local Menus = require(script.Menus)
		local menus = Menus.Create(screen)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local Menus = {}

local INK = Color3.fromRGB(235, 240, 250)
local MUTED = Color3.fromRGB(150, 163, 184)
local ACCENT = Color3.fromRGB(255, 190, 90)
local GOOD = Color3.fromRGB(120, 255, 150)
local PANEL = Color3.fromRGB(18, 20, 28)
local ROW = Color3.fromRGB(28, 32, 42)

export type Menu = {
	Destroy: () -> (),
}

type TitleRow = {
	id: string,
	name: string,
	order: number,
	stat: string,
	threshold: number,
	unlocked: boolean,
	value: number,
}

type PotionRow = {
	id: string,
	name: string,
	description: string,
	kind: string,
	seconds: number,
	count: number,
	activeUntil: number,
}

--[[ Unvan renkleri ChatTitles ile aynı kademede: alt sönük, üst parlak. ]]
local TIER_COLORS = {
	Color3.fromRGB(170, 176, 186),
	Color3.fromRGB(120, 200, 255),
	Color3.fromRGB( 80, 220, 140),
	Color3.fromRGB(190, 130, 255),
	Color3.fromRGB(255, 175,  60),
}

local function colorForOrder(order: number, highest: number): Color3
	local ratio = (order - 1) / math.max(1, highest - 1)
	local index = math.clamp(math.floor(ratio * #TIER_COLORS) + 1, 1, #TIER_COLORS)
	return TIER_COLORS[index]
end

--[[ Kilitli unvanın koşulunu okunur yazar. ]]
local function describeCondition(row: TitleRow): string
	local labels = {
		steals = "steals",
		robbed = "times robbed",
		caught = "thieves caught",
		maxStreak = "steal streak",
		secrets = "secret units",
		rebirths = "rebirths",
		maxedUpgrades = "maxed upgrades",
	}
	return string.format("%d / %d %s",
		math.min(row.value, row.threshold), row.threshold,
		labels[row.stat] or row.stat)
end

function Menus.Create(screen: ScreenGui): Menu
	-- ─── Açma düğmeleri ─────────────────────────────────────────────────────

	local dock = Instance.new("Frame")
	dock.Name = "MenuDock"
	dock.AnchorPoint = Vector2.new(1, 0)
	dock.Position = UDim2.new(1, -24, 0, 136)
	dock.Size = UDim2.new(0, 120, 0, 72)
	dock.BackgroundTransparency = 1
	dock.Parent = screen

	local dockLayout = Instance.new("UIListLayout")
	dockLayout.SortOrder = Enum.SortOrder.LayoutOrder
	dockLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	dockLayout.Padding = UDim.new(0, 6)
	dockLayout.Parent = dock

	local function newDockButton(order: number, text: string): TextButton
		local button = Instance.new("TextButton")
		button.LayoutOrder = order
		button.Size = UDim2.new(0, 120, 0, 30)
		button.BackgroundColor3 = PANEL
		button.BackgroundTransparency = 0.15
		button.BorderSizePixel = 0
		button.Font = Enum.Font.GothamBold
		button.TextSize = 13
		button.TextColor3 = INK
		button.Text = text
		button.AutoButtonColor = false
		button.Parent = dock

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button

		button.MouseEnter:Connect(function()
			button.TextColor3 = ACCENT
		end)
		button.MouseLeave:Connect(function()
			button.TextColor3 = INK
		end)

		return button
	end

	local titlesButton = newDockButton(1, "TITLES")
	local potionsButton = newDockButton(2, "POTIONS")

	-- ─── Üst katman ─────────────────────────────────────────────────────────

	local overlay = Instance.new("Frame")
	overlay.Name = "MenuOverlay"
	overlay.AnchorPoint = Vector2.new(0.5, 0.5)
	overlay.Position = UDim2.new(0.5, 0, 0.5, 0)
	overlay.Size = UDim2.new(0, 460, 0, 420)
	overlay.BackgroundColor3 = PANEL
	overlay.BackgroundTransparency = 0.05
	overlay.BorderSizePixel = 0
	overlay.Visible = false
	overlay.ZIndex = 10
	overlay.Parent = screen

	local overlayCorner = Instance.new("UICorner")
	overlayCorner.CornerRadius = UDim.new(0, 12)
	overlayCorner.Parent = overlay

	local heading = Instance.new("TextLabel")
	heading.Position = UDim2.new(0, 20, 0, 14)
	heading.Size = UDim2.new(1, -60, 0, 26)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBold
	heading.TextSize = 19
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.TextColor3 = ACCENT
	heading.Text = "TITLES"
	heading.ZIndex = 11
	heading.Parent = overlay

	local hint = Instance.new("TextLabel")
	hint.Position = UDim2.new(0, 20, 0, 38)
	hint.Size = UDim2.new(1, -40, 0, 18)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 12
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = MUTED
	hint.Text = ""
	hint.ZIndex = 11
	hint.Parent = overlay

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 12)
	close.Size = UDim2.new(0, 30, 0, 30)
	close.BackgroundTransparency = 1
	close.Font = Enum.Font.GothamBold
	close.TextSize = 20
	close.TextColor3 = MUTED
	close.Text = "✕"
	close.AutoButtonColor = false
	close.ZIndex = 11
	close.Parent = overlay

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.new(0, 14, 0, 62)
	list.Size = UDim2.new(1, -28, 1, -76)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = MUTED
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ZIndex = 11
	list.Parent = overlay

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = list

	-- ─── Satır kalıbı ───────────────────────────────────────────────────────

	type Row = {
		frame: TextButton,
		name: TextLabel,
		detail: TextLabel,
		badge: TextLabel,
	}

	local rows: { Row } = {}

	local function rowAt(index: number): Row
		if rows[index] then
			return rows[index]
		end

		local frame = Instance.new("TextButton")
		frame.LayoutOrder = index
		frame.Size = UDim2.new(1, -6, 0, 52)
		frame.BackgroundColor3 = ROW
		frame.BorderSizePixel = 0
		frame.AutoButtonColor = false
		frame.Text = ""
		frame.ZIndex = 11
		frame.Parent = list

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = frame

		local name = Instance.new("TextLabel")
		name.Position = UDim2.new(0, 14, 0, 8)
		name.Size = UDim2.new(1, -110, 0, 20)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextSize = 15
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = INK
		name.ZIndex = 12
		name.Parent = frame

		local detail = Instance.new("TextLabel")
		detail.Position = UDim2.new(0, 14, 0, 27)
		detail.Size = UDim2.new(1, -110, 0, 18)
		detail.BackgroundTransparency = 1
		detail.Font = Enum.Font.GothamMedium
		detail.TextSize = 12
		detail.TextXAlignment = Enum.TextXAlignment.Left
		detail.TextColor3 = MUTED
		detail.ZIndex = 12
		detail.Parent = frame

		local badge = Instance.new("TextLabel")
		badge.AnchorPoint = Vector2.new(1, 0.5)
		badge.Position = UDim2.new(1, -14, 0.5, 0)
		badge.Size = UDim2.new(0, 88, 0, 24)
		badge.BackgroundTransparency = 1
		badge.Font = Enum.Font.GothamBold
		badge.TextSize = 12
		badge.TextXAlignment = Enum.TextXAlignment.Right
		badge.TextColor3 = MUTED
		badge.ZIndex = 12
		badge.Parent = frame

		local row = { frame = frame, name = name, detail = detail, badge = badge }
		rows[index] = row
		return row
	end

	local function hideRowsFrom(index: number)
		for i = index, #rows do
			rows[i].frame.Visible = false
		end
	end

	--[[
		Satır tıklamaları her çizimde yeniden bağlanmamalı; bir kez bağlanıp
		güncel işi tutan bir tablo üzerinden çalışıyor. Aksi halde menü her
		açılışta bir kat daha fazla olay tetikliyordu.
	]]
	local rowAction: { [number]: (() -> ())? } = {}

	local function bindRow(index: number)
		local row = rowAt(index)
		if row.frame:GetAttribute("Bound") then
			return row
		end
		row.frame:SetAttribute("Bound", true)

		row.frame.MouseEnter:Connect(function()
			if rowAction[index] then
				row.frame.BackgroundColor3 = Color3.fromRGB(38, 44, 56)
			end
		end)
		row.frame.MouseLeave:Connect(function()
			row.frame.BackgroundColor3 = ROW
		end)
		row.frame.Activated:Connect(function()
			local action = rowAction[index]
			if action then
				action()
			end
		end)

		return row
	end

	-- ─── Unvanlar ───────────────────────────────────────────────────────────

	local equipRemote = Net.Get("TitleEquip")
	local useRemote = Net.Get("PotionUse")

	local titleData: { TitleRow } = {}
	local activeTitle = ""
	local potionData: { PotionRow } = {}
	local currentTab = "titles"

	local function drawTitles()
		heading.Text = "TITLES"
		hint.Text = "Click an unlocked title to wear it in chat"

		local highest = 1
		for _, row in titleData do
			if row.order > highest then
				highest = row.order
			end
		end

		local sorted = table.clone(titleData)
		table.sort(sorted, function(a, b)
			return a.order < b.order
		end)

		local index = 0

		--[[
			İlk satır "otomatik": oyuncu seçimden vazgeçip en yükseğini
			takmaya dönebilsin. Boş kimlik göndermek sunucuda bu anlama
			geliyor.
		]]
		index += 1
		local autoRow = bindRow(index)
		autoRow.frame.Visible = true
		autoRow.name.Text = "Automatic"
		autoRow.name.TextColor3 = INK
		autoRow.detail.Text = "Always wear your highest title"
		autoRow.badge.Text = if activeTitle == "" then "IN USE" else ""
		autoRow.badge.TextColor3 = GOOD
		rowAction[index] = function()
			equipRemote:FireServer("")
		end

		for _, row in sorted do
			index += 1
			local widget = bindRow(index)
			widget.frame.Visible = true
			widget.name.Text = row.name
			widget.name.TextColor3 = if row.unlocked
				then colorForOrder(row.order, highest)
				else Color3.fromRGB(96, 104, 118)

			if row.unlocked then
				widget.detail.Text = "Unlocked"
				widget.detail.TextColor3 = MUTED
				widget.badge.Text = if row.id == activeTitle then "IN USE" else "WEAR"
				widget.badge.TextColor3 = if row.id == activeTitle then GOOD else ACCENT

				local id = row.id
				rowAction[index] = function()
					equipRemote:FireServer(id)
				end
			else
				widget.detail.Text = describeCondition(row)
				widget.detail.TextColor3 = Color3.fromRGB(96, 104, 118)
				widget.badge.Text = "LOCKED"
				widget.badge.TextColor3 = Color3.fromRGB(96, 104, 118)
				rowAction[index] = nil
			end
		end

		hideRowsFrom(index + 1)
	end

	-- ─── İksirler ───────────────────────────────────────────────────────────

	local function drawPotions()
		heading.Text = "POTIONS"
		hint.Text = "Earned by finishing all daily quests. Click to drink."

		local now = os.time()
		local index = 0

		for _, row in potionData do
			index += 1
			local widget = bindRow(index)
			widget.frame.Visible = true

			local remaining = math.max(0, row.activeUntil - now)
			local has = row.count > 0

			widget.name.Text = row.name
			widget.name.TextColor3 = if has or remaining > 0 then INK else Color3.fromRGB(96, 104, 118)

			if remaining > 0 then
				widget.detail.Text = string.format("%s  ·  active %s",
					row.description, Config.FormatDuration(remaining))
				widget.detail.TextColor3 = GOOD
			else
				widget.detail.Text = string.format("%s  ·  lasts %s",
					row.description, Config.FormatDuration(row.seconds))
				widget.detail.TextColor3 = MUTED
			end

			if has then
				widget.badge.Text = string.format("DRINK  x%d", row.count)
				widget.badge.TextColor3 = ACCENT

				local id = row.id
				rowAction[index] = function()
					useRemote:FireServer(id)
				end
			else
				widget.badge.Text = "NONE"
				widget.badge.TextColor3 = Color3.fromRGB(96, 104, 118)
				rowAction[index] = nil
			end
		end

		hideRowsFrom(index + 1)
	end

	local function redraw()
		if not overlay.Visible then
			return
		end
		if currentTab == "titles" then
			drawTitles()
		else
			drawPotions()
		end
	end

	local function open(tab: string)
		-- Aynı sekmeye ikinci kez basmak kapatıyor: düğme aç/kapa gibi
		if overlay.Visible and currentTab == tab then
			overlay.Visible = false
			return
		end
		currentTab = tab
		overlay.Visible = true
		redraw()
	end

	titlesButton.Activated:Connect(function()
		open("titles")
	end)
	potionsButton.Activated:Connect(function()
		open("potions")
	end)
	close.Activated:Connect(function()
		overlay.Visible = false
	end)

	-- ─── Veri ───────────────────────────────────────────────────────────────

	local titlesConnection = Net.Get("Titles").OnClientEvent:Connect(function(list, active)
		if typeof(list) == "table" then
			titleData = list
			activeTitle = if typeof(active) == "string" then active else ""
			redraw()
		end
	end)

	--[[
		Envanterde iksir varken düğme dikkat çeksin: oyuncu ödülü kazandığını
		bildirimde görüyor ama nereden içeceğini bilmiyor.

		Bayrak ayrı tutuluyor çünkü fare düğmeden çıkınca rengi geri yazıyor;
		bayrak olmasa vurgu her imleç hareketinde silinirdi.
	]]
	local hasPotions = false

	local function refreshPotionBadge()
		local total = 0
		for _, row in potionData do
			total += row.count or 0
		end

		hasPotions = total > 0
		potionsButton.Text = if hasPotions then string.format("POTIONS  %d", total) else "POTIONS"
		potionsButton.TextColor3 = if hasPotions then ACCENT else INK
	end

	potionsButton.MouseLeave:Connect(function()
		potionsButton.TextColor3 = if hasPotions then ACCENT else INK
	end)

	local potionsConnection = Net.Get("Potions").OnClientEvent:Connect(function(list)
		if typeof(list) == "table" then
			potionData = list
			refreshPotionBadge()
			redraw()
		end
	end)

	--[[
		Aktif iksirin geri sayımı. Yalnızca iksir sekmesi açıkken ve
		saniyede bir; kapalıyken hiçbir iş yapılmıyor.
	]]
	local elapsed = 0
	local tick = RunService.Heartbeat:Connect(function(delta)
		elapsed += delta
		if elapsed < 1 then
			return
		end
		elapsed = 0

		if overlay.Visible and currentTab == "potions" then
			drawPotions()
		end
	end)

	return {
		Destroy = function()
			titlesConnection:Disconnect()
			potionsConnection:Disconnect()
			tick:Disconnect()
			overlay:Destroy()
			dock:Destroy()
		end,
	}
end

return Menus
