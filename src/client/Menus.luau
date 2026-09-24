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

local UiKit = require(script.Parent.UiKit)

local Menus = {}

--[[
	Renkler ve parçalar UiKit'ten; bütün paneller aynı dili konuşuyor.

	Unvanlar mürettebat rütbesi, iksirler de laboratuvar işi. İkisi ayrı
	sekme ama aynı kutuda, o yüzden vurgu rengi sekmeye göre değişiyor:
	unvanlarda vizör camgöbeği, iksirlerde yeşil.
]]
local INK = UiKit.INK
local MUTED = UiKit.MUTED
local ACCENT = UiKit.VISOR
local GOOD = UiKit.GOOD
local ROW = UiKit.ROW

local POTION_ACCENT = Color3.fromRGB(150, 226, 160)

export type Menu = {
	Open: (tab: string) -> (),
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

--[[
	host verilirse (Envanter) sağ kenar düğmeleri kurulmuyor ve katman o
	çerçevenin içine sayfa olarak kuruluyor; İKSİR ve UNVAN sekmeleri aynı
	sayfayı paylaşıyor. Hangi sekmede olduğu kökün "InventoryTab"
	niteliğinde — Envanter doğru sekmeyi onunla seçiyor.

	onCount: sekmelerin sayaçları (iksir adedi, açık unvan) değişince
	çağrılıyor: (sekme, kısa metin, rozet sayısı).
]]
function Menus.Create(screen: ScreenGui, host: Frame?, onCount: ((tab: string, text: string, badge: number) -> ())?): Menu
	-- ─── Açma düğmeleri (yalnızca tek başına kullanımda) ─────────────────────

	local dock: Frame? = nil
	local titlesButton: TextButton? = nil
	local potionsButton: TextButton? = nil
	local potionsLabel: TextLabel? = nil
	local potionsSlot: Frame? = nil

	if not host then
		--[[
			Sağ kenar rayı: kare ikon düğmeleri, alt alta. Adı MenuDock:
			RebirthPanel düğmesini buraya adıyla takıyor, Topbar gizleme
			listesinde tutuyor. (Envanter varken bu ray orada kuruluyor.)
		]]
		local dockFrame = Instance.new("Frame")
		dockFrame.Name = "MenuDock"
		dockFrame.AnchorPoint = Vector2.new(1, 1)
		dockFrame.Position = UDim2.new(1, -22, 1, -22)
		dockFrame.Size = UDim2.new(0, 64, 0, 4 * 68 + 3 * 8)
		dockFrame.BackgroundTransparency = 1
		dockFrame.Parent = screen
		dock = dockFrame

		local dockLayout = Instance.new("UIListLayout")
		dockLayout.SortOrder = Enum.SortOrder.LayoutOrder
		dockLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
		-- Alta yaslı: düğme eklendikçe ray yukarı doğru uzuyor
		dockLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		dockLayout.Padding = UDim.new(0, 8)
		dockLayout.Parent = dockFrame

		local titlesHolder, titlesBtn, titlesSlot =
			UiKit.IconButton(dockFrame, "Titles", UiKit.CREW.PURPLE, "TITLES")
		titlesHolder.LayoutOrder = 1
		UiKit.Crown(titlesSlot, 30, Color3.fromRGB(255, 214, 90))
		titlesButton = titlesBtn

		local potionsHolder, potionsBtn, potionsIcon =
			UiKit.IconButton(dockFrame, "Potions", POTION_ACCENT, "POTIONS")
		potionsHolder.LayoutOrder = 2
		potionsButton = potionsBtn
		potionsSlot = potionsIcon
		potionsLabel = potionsBtn:FindFirstChild("Label") :: TextLabel
	end

	--[[
		İksir ikonu envanterdeki adede göre doluyor; düğme "kaç tane var"
		bilgisini paneli açmadan veriyor. Boşken şişe sönük kalıyor.
	]]
	local function drawPotionIcon(total: number)
		if not potionsSlot then
			return
		end
		UiKit.ClearSlot(potionsSlot)
		UiKit.Vial(
			potionsSlot, 32,
			Color3.fromRGB(170, 255, 120),
			total / math.max(1, Config.PotionStackLimit),
			total > 0
		)
	end
	drawPotionIcon(0)

	-- ─── Üst katman ─────────────────────────────────────────────────────────

	local overlay: Frame
	if host then
		overlay = UiKit.Page(host, "MenuOverlay")
	else
		overlay = UiKit.Window(screen, "MenuOverlay", ACCENT)
		overlay.AnchorPoint = Vector2.new(0.5, 0.5)
		overlay.Position = UDim2.new(0.5, 0, 0.5, 0)
		overlay.Size = UDim2.new(0, 440, 0, 420)
	end
	overlay.Visible = false
	overlay.ZIndex = 10

	-- Kenarlık sekmeye göre renk değiştiriyor; hangi sekmede olduğun
	-- panelin çerçevesinden de okunuyor (gömülüyken kenarlık Envanter'in)
	local overlayStroke = overlay:FindFirstChildOfClass("UIStroke")

	--[[
		Başlıkta mürettebat silueti. Unvan sekmesinde takılı unvanın
		rengini alıyor — oyuncu kendi rengini panelde de görüyor.
	]]
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.Position = UDim2.fromOffset(18, 14)
	badge.Size = UDim2.fromOffset(26, 26)
	badge.BackgroundTransparency = 1
	badge.ZIndex = 11
	badge.Parent = overlay
	local badgeBody = UiKit.Crewmate(badge, 24, ACCENT)
	badgeBody.ZIndex = 12

	local heading = Instance.new("TextLabel")
	heading.Position = UDim2.new(0, 52, 0, 14)
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
	hint.Position = UDim2.new(0, 52, 0, 38)
	hint.Size = UDim2.new(1, -40, 0, 18)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 12
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = MUTED
	hint.Text = ""
	hint.ZIndex = 11
	hint.Parent = overlay

	local close: TextButton? = nil
	if not host then
		close = UiKit.CloseButton(overlay)
		close.ZIndex = 11
	end

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
		slot: Frame,
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

		--[[
			Satırın solunda küçük bir figür yuvası.

			Unvanlarda mürettebat silueti (unvan rengiyle), iksirlerde
			şişe. İkisi de Frame'den; liste bir metin yığını olmaktan
			çıkıp bakışta taranabilir hale geliyor.
		]]
		local slot = Instance.new("Frame")
		slot.Name = "Slot"
		slot.Position = UDim2.fromOffset(12, 12)
		slot.Size = UDim2.fromOffset(28, 28)
		slot.BackgroundTransparency = 1
		slot.ZIndex = 12
		slot.Parent = frame

		local name = Instance.new("TextLabel")
		name.Position = UDim2.new(0, 50, 0, 8)
		name.Size = UDim2.new(1, -146, 0, 20)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextSize = 15
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = INK
		name.ZIndex = 12
		name.Parent = frame

		local detail = Instance.new("TextLabel")
		detail.Position = UDim2.new(0, 50, 0, 27)
		detail.Size = UDim2.new(1, -146, 0, 18)
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

		local row = { frame = frame, name = name, detail = detail, badge = badge, slot = slot }
		rows[index] = row
		return row
	end

	--[[
		Yuvayı boşaltıp yeniden çiziyoruz.

		Satırlar yeniden kullanılıyor (liste her çizimde baştan
		kurulmuyor), o yüzden içerik değişince eski figür kalmasın diye
		temizlik gerekiyor.
	]]
	local clearSlot = UiKit.ClearSlot

	--[[
		İksir şişesi. Gövdesi UiKit'te: aynı şişe sağ kenardaki düğmede de
		çiziliyordu ve iki kopya birbirinden ayrışmaya başlamıştı.
	]]
	local function drawVial(slot: Frame, tint: Color3, fillRatio: number, active: boolean)
		clearSlot(slot)
		UiKit.Vial(slot, 26, tint, fillRatio, active)
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

	local function applyAccent(tone: Color3)
		heading.TextColor3 = tone
		if overlayStroke then
			overlayStroke.Color = tone
		end
		badgeBody.BackgroundColor3 = tone
	end

	local function drawTitles()
		applyAccent(ACCENT)
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
		-- Otomatik seçim: nötr gri figür
		clearSlot(autoRow.slot)
		UiKit.Crewmate(autoRow.slot, 24, UiKit.MUTED).ZIndex = 13
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
			--[[
				Her unvanın kendi renginde bir mürettebat silueti.
				Kilitliyken sönük: hangi rütbeye ulaşılmadığı bakışta
				belli oluyor.
			]]
			local tone = if row.unlocked
				then colorForOrder(row.order, highest)
				else UiKit.DIM

			clearSlot(widget.slot)
			UiKit.Crewmate(widget.slot, 24, tone).ZIndex = 13

			widget.name.Text = row.name
			widget.name.TextColor3 = tone

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
				widget.detail.TextColor3 = UiKit.DIM
				widget.badge.Text = "LOCKED"
				widget.badge.TextColor3 = UiKit.DIM
				rowAction[index] = nil
			end
		end

		hideRowsFrom(index + 1)
	end

	-- ─── İksirler ───────────────────────────────────────────────────────────

	local function drawPotions()
		applyAccent(POTION_ACCENT)
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

			drawVial(
				widget.slot,
				POTION_ACCENT,
				row.count / math.max(1, Config.PotionStackLimit),
				has or remaining > 0
			)

			widget.name.Text = row.name
			widget.name.TextColor3 = if has or remaining > 0 then INK else UiKit.DIM

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
				widget.badge.TextColor3 = UiKit.DIM
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
		-- Envanter sekmesini bununla seçiyor (iki sekme aynı sayfada)
		overlay:SetAttribute("InventoryTab", tab)
		overlay.Visible = true
		redraw()
	end

	if titlesButton then
		titlesButton.Activated:Connect(function()
			open("titles")
		end)
	end
	if potionsButton then
		potionsButton.Activated:Connect(function()
			open("potions")
		end)
	end
	if close then
		close.Activated:Connect(function()
			overlay.Visible = false
		end)
	end

	-- ─── Veri ───────────────────────────────────────────────────────────────

	local titlesConnection = Net.Get("Titles").OnClientEvent:Connect(function(list, active)
		if typeof(list) == "table" then
			titleData = list
			activeTitle = if typeof(active) == "string" then active else ""
			if onCount then
				local unlocked = 0
				for _, row in titleData do
					if row.unlocked then
						unlocked += 1
					end
				end
				onCount("titles", string.format("%d / %d unlocked", unlocked, #titleData), 0)
			end
			redraw()
		end
	end)

	--[[
		Envanterde iksir varken düğme onu göstersin: oyuncu ödülü kazandığını
		bildirimde görüyor ama nereden içeceğini bilmiyor.

		Sayı etikete, doluluk da ikondaki sıvıya yazılıyor — düğmeye bakınca
		hem "var" hem "kaç tane" okunuyor.
	]]
	local function refreshPotionBadge()
		local total = 0
		for _, row in potionData do
			total += row.count or 0
		end

		drawPotionIcon(total)
		if potionsLabel then
			potionsLabel.Text = if total > 0 then string.format("POTIONS %d", total) else "POTIONS"
		end
		if onCount then
			local active = 0
			local now = os.time()
			for _, row in potionData do
				if (row.activeUntil or 0) > now then
					active += 1
				end
			end
			local text = if total > 0 then string.format("%d ready to drink", total) else "none in bag"
			if active > 0 then
				text ..= string.format(" · %d active", active)
			end
			onCount("potions", text, total)
		end
	end

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
		Open = open,
		Destroy = function()
			titlesConnection:Disconnect()
			potionsConnection:Disconnect()
			tick:Disconnect()
			overlay:Destroy()
			if dock then
				dock:Destroy()
			end
		end,
	}
end

return Menus
