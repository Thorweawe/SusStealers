--!strict
--[[
	ENVANTER: petler, iksirler, stil ve unvanlar TEK pencerede.

	NEDEN: sağ kenarda dört ayrı düğme (TITLES, POTIONS, PETS, STYLE) ve
	dört ayrı pencere vardı; her biri kendi boyutunda, kendi başlığıyla
	ekranın ortasında açılıyordu. Oyuncu "eşyalarım nerede" diye dört yere
	bakıyordu. Tür standardı sırt çantası: tek düğme, içinde sekmeler.

	═══ SEKME SIRASI ════════════════════════════════════════════════════════

	  1 PETS     en sık açılan ve oyunu en çok etkileyen (gelir, taşıma hızı);
	             yumurta açınca, pet takınca buraya geliniyor.
	  2 POTIONS  tüketilen şeyler: kazanılınca içmek için gelinir. Hazır
	             iksir sayısı hem sekmede hem ENVANTER düğmesinde rozet.
	  3 STYLE    kalıcı görünüş alımları (şapka, iz).
	  4 TITLES   yalnızca sohbette görünüyor, en seyrek değişen.

	Tuş: B (backpack) aç/kapa. Sekmeler arasında pencere açıkken 1-4 YOK:
	ekipman çubuğu rakam tuşlarını kullanıyor.

	═══ SAYFALAR ═══════════════════════════════════════════════════════════

	Sayfalar panellerin KENDİSİ: PetPanel, Menus (iksir + unvan) ve
	CosmeticPanel köklerini bu pencerenin içerik alanına kuruyor
	(UiKit.Page). Kodları değişmedi; yalnızca kabukları yok.

	Envanter sayfanın Visible'ını dinliyor: panel kendini açarsa (ör.
	birleştirme makinesi PetPanel.OpenFuse) pencere o sekmede açılıyor,
	panel kendini kapatırsa pencere kapanıyor. Pencere kapanınca da sayfa
	gizleniyor — paneller "açık mıyım" sorusunu kendi köklerine soruyor.

	═══ SAĞ KENAR ══════════════════════════════════════════════════════════

	MenuDock burada kuruluyor (adı sabit: RebirthPanel düğmesini buna
	takıyor, Topbar gizleme listesinde tutuyor). Ekranın sağ ortasında:
	ENVANTER ortada, REBIRTH hemen altında. Sağ alt köşe olay çizelgesinin
	(EventFX).

	═══ GÖRÜNÜŞ ════════════════════════════════════════════════════════════

	Mağazanın dili (CardKit): başlık şeridi SEÇİLİ SEKMENİN renginde,
	sekmeler ışınlı renkli kartlar (seçili olan parlak ve tam boy, diğerleri
	sönük ve biraz küçük), içerik alanı kalın koyu çerçeveli.
]]

local UserInputService = game:GetService("UserInputService")

local CardKit = require(script.Parent.CardKit)
local UiKit = require(script.Parent.UiKit)

local Inventory = {}

export type TabDef = {
	id: string,
	label: string,
	tint: Color3,
	order: number,
	icon: (slot: Frame, size: number, tint: Color3) -> (),
}

export type Inventory = {
	-- Sağ kenardaki düğme dizisi (REBIRTH buraya takılıyor)
	Dock: Frame,
	-- Sayfaların kurulacağı içerik alanı
	Content: Frame,
	--[[
		Sekme ekler. `page` panelin kökü (Content'in çocuğu), `open`
		panelin kendi açma işlevi (çizimini yapan). İki sekme aynı kökü
		paylaşabilir (iksir + unvan): hangisi olduğunu kökün
		"InventoryTab" niteliği söylüyor.
	]]
	AddTab: (def: TabDef, page: GuiObject, open: () -> ()) -> (),
	SetCount: (id: string, text: string) -> (),
	SetBadge: (id: string, count: number) -> (),
	Open: (id: string?) -> (),
	Toggle: () -> (),
	Close: () -> (),
	Destroy: () -> (),
}

local W, H = 800, 560
local HEADER = 66
local RAIL_W = 180
local PAD = 14
local TAB_H = 76
local Z = 40

local ACCENT = UiKit.VISOR
local DOCK_BUTTON = Vector2.new(72, 78)

type Tab = {
	def: TabDef,
	page: GuiObject,
	open: () -> (),
	button: TextButton,
	card: Frame,
	scale: UIScale,
	count: TextLabel,
	notch: Frame,
	badge: TextLabel,
}

function Inventory.Create(screen: ScreenGui): Inventory
	-- ─── Sağ kenar: ENVANTER + REBIRTH ──────────────────────────────────────

	local dock = Instance.new("Frame")
	dock.Name = "MenuDock"
	--[[
		Dikeyde ortanın biraz altına yaslı: ENVANTER düğmesi tam ortada,
		REBIRTH onun altında ("sağ ortanın yarım altı"). Sağ üst sıralama
		tablosunun, sağ alt olay çizelgesinin.
	]]
	dock.AnchorPoint = Vector2.new(1, 0.5)
	dock.Position = UDim2.new(1, -22, 0.5, DOCK_BUTTON.Y / 2 + 4)
	dock.Size = UDim2.fromOffset(DOCK_BUTTON.X, DOCK_BUTTON.Y * 2 + 8)
	dock.BackgroundTransparency = 1
	dock.Parent = screen

	local dockLayout = Instance.new("UIListLayout")
	dockLayout.SortOrder = Enum.SortOrder.LayoutOrder
	dockLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	dockLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	dockLayout.Padding = UDim.new(0, 8)
	dockLayout.Parent = dock

	local bagTint = Color3.fromRGB(64, 150, 214)
	local bagHolder, bagButton, bagSlot = UiKit.IconButton(dock, "Inventory", bagTint, "INVENTORY", DOCK_BUTTON)
	bagHolder.LayoutOrder = 1
	UiKit.Backpack(bagSlot, 36, Color3.fromRGB(236, 206, 150))
	local bagBadge = UiKit.Badge(bagButton)

	-- ─── Pencere ───────────────────────────────────────────────────────────

	local window = UiKit.Window(screen, "InventoryPanel", ACCENT)
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(W, H)
	window.Visible = false
	window.ZIndex = Z

	local skin = CardKit.skin(window, ACCENT, "Inventory", HEADER, Z)
	local headerGradient = skin.header:FindFirstChildOfClass("UIGradient")
	skin.title.Position = UDim2.fromOffset(84, 4)
	local sub = CardKit.bold(skin.header, "press B to open", 16, CardKit.WHITE, Z + 4, 2)
	sub.AnchorPoint = Vector2.new(1, 0.5)
	sub.Position = UDim2.new(1, -86, 0.5, 0)
	sub.Size = UDim2.fromOffset(160, 22)
	sub.TextXAlignment = Enum.TextXAlignment.Right
	sub.TextTransparency = 0.15

	local crest = CardKit.badge(skin.header, 50, bagTint, Z + 4)
	crest.AnchorPoint = Vector2.new(0, 0.5)
	crest.Position = UDim2.new(0, 20, 0.5, 0)
	UiKit.Backpack(crest:FindFirstChild("Slot") :: Frame, 34, Color3.fromRGB(236, 206, 150))

	skin.close.MouseButton1Click:Connect(function()
		window.Visible = false
	end)

	-- ─── Sekme rayı ─────────────────────────────────────────────────────────

	local rail = Instance.new("Frame")
	rail.Name = "Tabs"
	rail.Position = UDim2.fromOffset(PAD, HEADER + 12)
	rail.Size = UDim2.new(0, RAIL_W, 1, -(HEADER + 12 + PAD))
	rail.BackgroundTransparency = 1
	rail.ZIndex = Z + 1
	rail.Parent = window

	local railLayout = Instance.new("UIListLayout")
	railLayout.SortOrder = Enum.SortOrder.LayoutOrder
	railLayout.Padding = UDim.new(0, 10)
	railLayout.Parent = rail

	-- Rayın dibinde küçük mürettebat: boş kalan alanı dolduran imza
	local mascot = Instance.new("Frame")
	mascot.AnchorPoint = Vector2.new(0.5, 1)
	mascot.Position = UDim2.new(0, PAD + RAIL_W / 2, 1, -PAD - 4)
	mascot.Size = UDim2.fromOffset(64, 64)
	mascot.BackgroundTransparency = 1
	mascot.ZIndex = Z + 1
	mascot.Parent = window
	local mascotBody = UiKit.Crewmate(mascot, 50, ACCENT)

	-- ─── İçerik alanı ───────────────────────────────────────────────────────

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Position = UDim2.fromOffset(PAD * 2 + RAIL_W, HEADER + 12)
	content.Size = UDim2.new(1, -(PAD * 3 + RAIL_W), 1, -(HEADER + 12 + PAD))
	content.BackgroundColor3 = CardKit.BODY_DEEP
	content.BackgroundTransparency = 0.1
	content.BorderSizePixel = 0
	content.ClipsDescendants = true
	content.ZIndex = Z + 1
	content.Parent = window
	CardKit.corner(content, 14)
	CardKit.border(content, CardKit.OUTLINE, 3)
	-- İçte seçili sekmenin renginde ince çizgi
	local contentInner = Instance.new("Frame")
	contentInner.Position = UDim2.fromOffset(3, 3)
	contentInner.Size = UDim2.new(1, -6, 1, -6)
	contentInner.BackgroundTransparency = 1
	contentInner.ZIndex = Z + 1
	contentInner.Parent = content
	CardKit.corner(contentInner, 11)
	local contentStroke = Instance.new("UIStroke")
	contentStroke.Color = ACCENT
	contentStroke.Thickness = 2
	contentStroke.Transparency = 0.35
	contentStroke.Parent = contentInner

	-- ─── Sekmeler ───────────────────────────────────────────────────────────

	local tabs: { [string]: Tab } = {}
	local order: { string } = {}
	local watched: { [GuiObject]: boolean } = {}
	local connections: { RBXScriptConnection } = {}
	local active: string? = nil
	-- Envanterin kendi yazdığı Visible değişikliklerini dinleyici görmesin
	local syncing = false

	local DIMMED = Color3.fromRGB(70, 78, 96)

	local function paintTabs()
		local tone = if active and tabs[active] then tabs[active].def.tint else ACCENT
		-- Başlık şeridi seçili sekmenin renginde
		skin.header.BackgroundColor3 = tone
		if headerGradient then
			headerGradient.Color = ColorSequence.new(tone:Lerp(CardKit.WHITE, 0.2), tone:Lerp(Color3.new(0, 0, 0), 0.12))
		end
		local foot = skin.header:FindFirstChildWhichIsA("Frame")
		if foot then
			foot.BackgroundColor3 = tone:Lerp(Color3.new(0, 0, 0), 0.1)
		end
		contentStroke.Color = tone:Lerp(CardKit.WHITE, 0.2)
		mascotBody.BackgroundColor3 = tone

		for id, tab in tabs do
			local on = id == active
			local tint = tab.def.tint
			CardKit.tintCard(tab.card, if on then tint else tint:Lerp(DIMMED, 0.6))
			tab.scale.Scale = if on then 1 else 0.94
			tab.count.TextColor3 = if on then CardKit.WHITE else Color3.fromRGB(200, 206, 220)
			tab.notch.Visible = on
		end
	end

	--[[ Pencereyi verilen sekmede gösterir; diğer sayfaları gizler. ]]
	local function activate(id: string)
		local tab = tabs[id]
		if not tab then
			return
		end
		active = id
		syncing = true
		for _, other in tabs do
			if other.page ~= tab.page and other.page.Visible then
				other.page.Visible = false
			end
		end
		window.Visible = true
		syncing = false
		paintTabs()
	end

	local function openTab(id: string)
		local tab = tabs[id]
		if not tab then
			return
		end
		if window.Visible and active == id and tab.page.Visible then
			return
		end
		-- Önce paneli kendi işleviyle aç: kartlarını son veriyle o çiziyor
		if not tab.page.Visible or tab.page:GetAttribute("InventoryTab") ~= nil then
			tab.open()
		end
		activate(id)
	end

	local function watch(page: GuiObject, fallback: string)
		if watched[page] then
			return
		end
		watched[page] = true
		table.insert(connections, page:GetPropertyChangedSignal("Visible"):Connect(function()
			if syncing then
				return
			end
			if page.Visible then
				-- Panel kendini açtı (ör. makinede birleştirme): o sekmeye geç
				local tag = page:GetAttribute("InventoryTab")
				activate(if typeof(tag) == "string" and tabs[tag] then tag else fallback)
			elseif active and tabs[active] and tabs[active].page == page and window.Visible then
				-- Panel kendini kapattı: pencere de kapansın
				syncing = true
				window.Visible = false
				syncing = false
			end
		end))
	end

	local function addTab(def: TabDef, page: GuiObject, open: () -> ())
		local holder = Instance.new("Frame")
		holder.Name = "Tab_" .. def.id
		holder.LayoutOrder = def.order
		holder.Size = UDim2.new(1, 0, 0, TAB_H)
		holder.BackgroundTransparency = 1
		holder.ZIndex = Z + 2
		holder.Parent = rail

		local scale = Instance.new("UIScale")
		scale.Parent = holder

		local card = CardKit.card(holder, def.tint, UDim2.new(1, -10, 1, 0), Z + 2, UDim2.fromScale(0.2, 0.5), 240)

		local iconBack = CardKit.badge(card, 56, def.tint, Z + 4)
		iconBack.AnchorPoint = Vector2.new(0, 0.5)
		iconBack.Position = UDim2.new(0, 8, 0.5, 0)
		def.icon(iconBack:FindFirstChild("Slot") :: Frame, 38, def.tint:Lerp(Color3.new(1, 1, 1), 0.45))

		local label = CardKit.bold(card, def.label, 24, CardKit.WHITE, Z + 5, 3)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Position = UDim2.fromOffset(72, 10)
		label.Size = UDim2.new(1, -80, 0, 28)
		CardKit.fit(label, 24, 8)

		local count = CardKit.bold(card, "", 15, CardKit.WHITE, Z + 5, 2)
		count.TextXAlignment = Enum.TextXAlignment.Left
		count.Position = UDim2.fromOffset(72, 40)
		count.Size = UDim2.new(1, -84, 0, 20)
		-- Uzun satır ("17 pets · 3/3 equipped") sekmeye sığmıyor: sığmazsa küçülür
		CardKit.fit(count, 15, 6)

		-- Tıklama katmanı: kartın üstünde görünmez düğme
		local button = Instance.new("TextButton")
		button.Name = "Button"
		button.Size = UDim2.new(1, -10, 1, 0)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.ZIndex = Z + 8
		button.Parent = holder

		-- Etkin sekmenin sağında içerik alanına bakan çentik
		local notch = Instance.new("Frame")
		notch.AnchorPoint = Vector2.new(0.5, 0.5)
		notch.Position = UDim2.new(1, -6, 0.5, 0)
		notch.Size = UDim2.fromOffset(16, 16)
		notch.Rotation = 45
		notch.BackgroundColor3 = def.tint
		notch.BorderSizePixel = 0
		notch.Visible = false
		notch.ZIndex = Z + 1
		notch.Parent = holder
		CardKit.border(notch, CardKit.OUTLINE, 2.5)

		local badge = UiKit.Badge(button)
		badge.Position = UDim2.new(1, -8, 0, 8)

		button.MouseEnter:Connect(function()
			if active ~= def.id then
				scale.Scale = 0.98
			end
		end)
		button.MouseLeave:Connect(function()
			paintTabs()
		end)
		button.MouseButton1Down:Connect(function()
			card.Position = UDim2.fromOffset(0, 3)
		end)
		button.MouseButton1Up:Connect(function()
			card.Position = UDim2.fromOffset(0, 0)
		end)
		button.Activated:Connect(function()
			openTab(def.id)
		end)

		tabs[def.id] = {
			def = def,
			page = page,
			open = open,
			button = button,
			card = card,
			scale = scale,
			count = count,
			notch = notch,
			badge = badge,
		}
		table.insert(order, def.id)
		table.sort(order, function(a, b)
			return tabs[a].def.order < tabs[b].def.order
		end)
		watch(page, def.id)
		paintTabs()
	end

	local open: (id: string?) -> ()

	-- Pencere kapanınca sayfalar da gizlensin: paneller kendilerini kapalı bilsin
	table.insert(connections, window:GetPropertyChangedSignal("Visible"):Connect(function()
		if window.Visible then
			--[[
				Pencere dışarıdan yeniden görünür yapıldıysa (arayüzü gizle/göster
				düğmesi eski hâlini geri yüklüyor) sayfası boş kalmasın.
			]]
			local current = if active then tabs[active] else nil
			if not syncing and current and not current.page.Visible then
				task.defer(open, active)
			end
			return
		end
		syncing = true
		for _, tab in tabs do
			if tab.page.Visible then
				tab.page.Visible = false
			end
		end
		syncing = false
	end))

	function open(id: string?)
		local target = id or active or order[1]
		if target then
			openTab(target)
		end
	end

	local function toggle()
		if window.Visible then
			window.Visible = false
		else
			open(nil)
		end
	end

	bagButton.MouseButton1Click:Connect(toggle)

	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.B then
			return
		end
		toggle()
	end))

	local badges: { [string]: number } = {}

	return {
		Dock = dock,
		Content = content,
		AddTab = addTab,
		SetCount = function(id: string, text: string)
			local tab = tabs[id]
			if tab then
				tab.count.Text = text
			end
		end,
		SetBadge = function(id: string, count: number)
			badges[id] = count
			local tab = tabs[id]
			if tab then
				tab.badge.Text = tostring(count)
				tab.badge.Visible = count > 0
			end
			-- Düğmedeki rozet bütün sekmelerin toplamı
			local total = 0
			for _, n in badges do
				total += n
			end
			bagBadge.Text = tostring(total)
			bagBadge.Visible = total > 0
		end,
		Open = open,
		Toggle = toggle,
		Close = function()
			window.Visible = false
		end,
		Destroy = function()
			for _, c in connections do
				c:Disconnect()
			end
			window:Destroy()
			dock:Destroy()
		end,
	}
end

return Inventory
