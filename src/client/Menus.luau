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

	GÖRÜNÜŞ mağaza dilinde (CardKit): her satır kendi renginde ışınlı kart
	(unvan kademe rengi, iksir mağazadaki rengi; kilitli/boş gri), solda
	ikon rozeti, sağda tıknaz durum düğmesi (WEAR / IN USE / DRINK / LOCKED).
	Eskiden düz gri satırlar ve ince yazılardı.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local CardKit = require(script.Parent.CardKit)
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

-- Kart renkleri: kilitli/boş satır ve mağazadaki iksir renkleri
local LOCKED_TINT = Color3.fromRGB(70, 78, 96)
local POTION_TINT: { [string]: Color3 } = {
	Income2x = Color3.fromRGB(56, 170, 70),
	Income3x = Color3.fromRGB(214, 150, 20),
	FastSteal = Color3.fromRGB(226, 84, 60),
	StrongLock = Color3.fromRGB(40, 140, 220),
}
local PILL_GREEN = Color3.fromRGB(88, 226, 60)
local PILL_YELLOW = Color3.fromRGB(255, 200, 40)

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

	local heading = CardKit.bold(overlay, "TITLES", 26, ACCENT, 11, 3)
	heading.Position = UDim2.new(0, 52, 0, 8)
	heading.Size = UDim2.new(1, -60, 0, 30)
	heading.TextXAlignment = Enum.TextXAlignment.Left

	local hint = CardKit.bold(overlay, "", 14, Color3.fromRGB(200, 210, 230), 11, 1.6)
	hint.Position = UDim2.new(0, 52, 0, 38)
	hint.Size = UDim2.new(1, -60, 0, 18)
	hint.TextXAlignment = Enum.TextXAlignment.Left
	CardKit.fit(hint, 14, 9)

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
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = list

	-- ─── Satır kalıbı ───────────────────────────────────────────────────────

	type Row = {
		frame: TextButton,
		card: Frame,
		name: TextLabel,
		detail: TextLabel,
		badge: TextLabel,
		pill: Frame,
		slot: Frame,
		scale: UIScale,
	}

	local rows: { Row } = {}

	local function rowAt(index: number): Row
		if rows[index] then
			return rows[index]
		end

		-- Tıklama bütün satırda: kart ve yazılar tıklamayı yutmuyor
		local frame = Instance.new("TextButton")
		frame.LayoutOrder = index
		frame.Size = UDim2.new(1, -10, 0, 66)
		frame.BackgroundTransparency = 1
		frame.AutoButtonColor = false
		frame.Text = ""
		frame.ZIndex = 11
		frame.Parent = list
		local scale = Instance.new("UIScale")
		scale.Parent = frame

		local card = CardKit.card(frame, LOCKED_TINT, UDim2.fromScale(1, 1), 11, UDim2.fromScale(0.1, 0.5), 240)

		--[[
			Solda ikon rozeti: unvanlarda mürettebat silueti (unvan
			rengiyle), iksirlerde şişe.
		]]
		local slotBadge = CardKit.badge(card, 50, LOCKED_TINT, 14)
		slotBadge.AnchorPoint = Vector2.new(0, 0.5)
		slotBadge.Position = UDim2.new(0, 8, 0.5, 0)
		local slot = slotBadge:FindFirstChild("Slot") :: Frame
		slot.Name = "Slot"

		local name = CardKit.bold(card, "", 20, CardKit.WHITE, 16, 2.5)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.new(0, 66, 0, 8)
		name.Size = UDim2.new(1, -186, 0, 24)
		CardKit.fit(name, 20, 11)

		local detail = CardKit.bold(card, "", 13, Color3.fromRGB(225, 232, 248), 16, 1.5)
		detail.TextXAlignment = Enum.TextXAlignment.Left
		detail.Position = UDim2.new(0, 66, 0, 34)
		detail.Size = UDim2.new(1, -186, 0, 18)
		CardKit.fit(detail, 13, 8)

		-- Sağda tıknaz durum düğmesi (görsel; tıklama satırın kendisinde)
		local pill = Instance.new("Frame")
		pill.AnchorPoint = Vector2.new(1, 0.5)
		pill.Position = UDim2.new(1, -10, 0.5, 0)
		pill.Size = UDim2.fromOffset(106, 38)
		pill.BackgroundColor3 = PILL_GREEN
		pill.BorderSizePixel = 0
		pill.ZIndex = 15
		pill.Parent = card
		CardKit.corner(pill, 10)
		CardKit.border(pill, CardKit.OUTLINE, 2.5)
		CardKit.gradient(pill, CardKit.WHITE, Color3.fromRGB(200, 200, 200))
		local badge = CardKit.bold(pill, "", 17, CardKit.WHITE, 16, 2)
		badge.Size = UDim2.new(1, -8, 1, 0)
		badge.Position = UDim2.fromOffset(4, 0)
		CardKit.fit(badge, 17, 9)

		local row = { frame = frame, card = card, name = name, detail = detail, badge = badge, pill = pill, slot = slot, scale = scale }
		rows[index] = row
		return row
	end

	--[[ Satırın rengi ve sağdaki düğmenin hâli (nil renk = gri, basılamaz görünümü). ]]
	local function paintRow(row: Row, tint: Color3, pillText: string, pillColor: Color3?)
		CardKit.tintCard(row.card, tint)
		local badgeFrame = row.slot.Parent :: Frame
		if badgeFrame then
			badgeFrame.BackgroundColor3 = tint:Lerp(Color3.new(0, 0, 0), 0.45)
			local g = badgeFrame:FindFirstChildOfClass("UIGradient")
			if g then
				g.Color = ColorSequence.new(tint:Lerp(Color3.new(0, 0, 0), 0.2), tint:Lerp(Color3.new(0, 0, 0), 0.6))
			end
		end
		row.badge.Text = pillText
		row.pill.Visible = pillText ~= ""
		row.pill.BackgroundColor3 = pillColor or CardKit.GREY
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
				row.scale.Scale = 1.02
			end
		end)
		row.frame.MouseLeave:Connect(function()
			row.scale.Scale = 1
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
		UiKit.Crewmate(autoRow.slot, 34, Color3.fromRGB(220, 226, 240)).ZIndex = 16
		autoRow.name.Text = "Automatic"
		autoRow.detail.Text = "Always wear your highest title"
		paintRow(autoRow, Color3.fromRGB(60, 110, 220), if activeTitle == "" then "IN USE" else "AUTO",
			if activeTitle == "" then PILL_YELLOW else PILL_GREEN)
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
			UiKit.Crewmate(widget.slot, 34, if row.unlocked then tone:Lerp(Color3.new(1, 1, 1), 0.3) else UiKit.DIM).ZIndex = 16

			widget.name.Text = row.name

			if row.unlocked then
				widget.detail.Text = "Unlocked"
				local wearing = row.id == activeTitle
				paintRow(widget, tone:Lerp(Color3.new(0, 0, 0), 0.25), if wearing then "IN USE" else "WEAR",
					if wearing then PILL_YELLOW else PILL_GREEN)

				local id = row.id
				rowAction[index] = function()
					equipRemote:FireServer(id)
				end
			else
				widget.detail.Text = describeCondition(row)
				paintRow(widget, LOCKED_TINT, "LOCKED", nil)
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

			local tint = POTION_TINT[row.id] or POTION_ACCENT
			clearSlot(widget.slot)
			UiKit.Vial(widget.slot, 34, tint:Lerp(Color3.new(1, 1, 1), 0.35),
				math.max(0.35, row.count / math.max(1, Config.PotionStackLimit)), has or remaining > 0)

			widget.name.Text = row.name

			if remaining > 0 then
				widget.detail.Text = string.format('%s  ·  <font color="#7CFF5B">active %s</font>',
					row.description, Config.FormatDuration(remaining))
			else
				widget.detail.Text = string.format("%s  ·  lasts %s",
					row.description, Config.FormatDuration(row.seconds))
			end

			if has then
				paintRow(widget, tint:Lerp(Color3.new(0, 0, 0), 0.2), string.format("DRINK x%d", row.count), PILL_GREEN)

				local id = row.id
				rowAction[index] = function()
					useRemote:FireServer(id)
				end
			else
				paintRow(widget, if remaining > 0 then tint:Lerp(Color3.new(0, 0, 0), 0.35) else LOCKED_TINT,
					if remaining > 0 then "ACTIVE" else "NONE", if remaining > 0 then PILL_YELLOW else nil)
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
