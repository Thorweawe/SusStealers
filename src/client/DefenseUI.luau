--!strict
--[[
	Gezegen savunmasının 2B arayüzü (DefenseClient kuruyor ve besliyor).

	Üçüncü sürüm (2026-10-01, Batur: "o moddaki çoğu UI çok kötü,
	düzgünleştir; silah seçim ekranı gelmedi"):
	  - Tek tip görünüm: koyu lacivert kart, kalın çerçeve, Fredoka yazı;
	    oyunun kendi arayüzüyle çakışmayan yerleşim (sol menü, sağ üstteki
	    sıralama, alttaki alet çubuğu boş kalıyor)
	  - DEFEND penceresi TEK SAYFA: solda crewmate'ler (role göre gruplu, en
	    güçlüden zayıfa, slot kadar), sağda bölüm + gear + DEFEND! (gear
	    seçimi eskiden ikinci adımdaydı, görünmeyebiliyordu)
	  - Yürürken: üstte durum (bölüm / dalga / gövde / altın), sağda gelen
	    dalga ve hız düğmesi, altta DEFEND / START WAVE / destekler
	  - Dükkânlar: seviye noktaları, altın fiyatlı düğmeler
	  - Sonuç bandı üstten kayarak geliyor

	Mantık sunucuda; buradan yalnızca hooks.send(...) ile istek gidiyor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DefenseConfig = require(Shared.DefenseConfig)

local EnemyModel = require(Shared.EnemyModel)

local FancyKit = require(script.Parent.FancyKit)
local UiArt = require(script.Parent.UiArt)
local UiKit = require(script.Parent.UiKit)

local DefenseUI = {}

local WHITE = Color3.new(1, 1, 1)
local OUTLINE = Color3.fromRGB(22, 20, 34)
local GOLD = Color3.fromRGB(255, 205, 60)
local GREEN = Color3.fromRGB(70, 200, 90)
local RED = Color3.fromRGB(230, 70, 70)
local BLUE = Color3.fromRGB(70, 150, 255)
local ORANGE = Color3.fromRGB(255, 150, 40)
local PURPLE = Color3.fromRGB(150, 90, 255)
local GREY = Color3.fromRGB(120, 128, 146)
local SOFT = Color3.fromRGB(200, 210, 240)
local PANEL_TOP = Color3.fromRGB(44, 52, 82)
local PANEL_BOTTOM = Color3.fromRGB(22, 26, 44)
local Z = 50

--[[
	Telefon (Batur: "mobil için dikkat et"). Bütün arayüz DeviceLayout'un
	ölçeğiyle küçülüyor; pencereler 840x600'e sığmalı. Telefonda sağ üstte
	para + CREW tablosu, sol altta menü, köşelerde joystick / zıplama var:
	gelen dalga kartı sol üste (üst çubuğun altı) küçülerek geçiyor, hız
	düğmesi her cihazda alttaki düğme sırasında.
]]
local TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

export type Hooks = {
	send: (...any) -> (),
	pickSupport: (id: string?) -> (),
	takeoff: () -> (),
}

export type UI = {
	OpenPrepare: () -> (),
	OpenShop: (kind: string) -> (),
	CloseAll: () -> (),
	SetData: (data: any) -> (),
	SetRun: (run: any?, planet: number?) -> (),
	SetPicked: (support: string?) -> (),
	SetTick: (snap: any) -> (),
	Banner: (title: string, sub: string, color: Color3) -> (),
	Celebrate: (sector: number, stars: number, gold: number) -> (),
	SetPlanetHud: (visible: boolean) -> (),
}

-- ─── Yapı taşları ───────────────────────────────────────────────────────────

local function label(parent: Instance, text: string, size: number, color: Color3, z: number, stroke: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.ZIndex = z
	l.AutoLocalize = false
	l.Parent = parent
	if (stroke or 1) > 0 then
		local s = Instance.new("UIStroke")
		s.Color = OUTLINE
		s.Thickness = stroke or math.max(1.5, size / 9)
		s.LineJoinMode = Enum.LineJoinMode.Round
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.Parent = l
	end
	return l
end

local function panel(parent: Instance, size: UDim2, pos: UDim2, anchor: Vector2, z: number, top: Color3?, bottom: Color3?, radius: number?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = pos
	f.AnchorPoint = anchor
	f.BackgroundColor3 = WHITE
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	FancyKit.corner(f, radius or 14)
	FancyKit.border(f, OUTLINE, 3)
	FancyKit.gradient(f, { top or PANEL_TOP, bottom or PANEL_BOTTOM }, 90)
	return f
end

local function button(parent: Instance, text: string, size: UDim2, color: Color3, z: number, textSize: number?): FancyKit.Button
	local b = FancyKit.button(parent, size, color, textSize or 20, z)
	b.set(text, color)
	return b
end

-- Küçük renkli rozet (bölüm, dalga, rol)
local function chip(parent: Instance, text: string, color: Color3, z: number, width: number?): (Frame, TextLabel)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(width or 90, 24)
	f.BackgroundColor3 = WHITE
	f.ZIndex = z
	f.Parent = parent
	FancyKit.corner(f, 12)
	FancyKit.border(f, OUTLINE, 2)
	FancyKit.gradient(f, { color:Lerp(WHITE, 0.2), color:Lerp(Color3.new(0, 0, 0), 0.25) }, 90)
	local l = label(f, text, 14, WHITE, z + 1, 1.4)
	l.Size = UDim2.fromScale(1, 1)
	return f, l
end

-- Seviye noktaları (●●●○○)
local function pips(level: number, max: number): string
	return string.rep("●", math.clamp(level, 0, max)) .. string.rep("○", math.max(0, max - level))
end

local function stars(n: number): string
	return string.rep("★", n) .. string.rep("☆", 3 - n)
end

local function planetName(i: number): string
	local def = Config.SpaceMonsters[i]
	return if def then string.upper(def.planet) else "PLANET " .. i
end

local function sectorStars(data: any, planet: number, sector: number): number
	local p = data and data.planets and data.planets[planet]
	return if p and p.stars then (p.stars[tostring(sector)] or 0) else 0
end

local function list(parent: Instance, horizontal: boolean, padding: number): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, padding)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

local function scroller(parent: Instance, z: number): ScrollingFrame
	local s = Instance.new("ScrollingFrame")
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 6
	s.ScrollBarImageColor3 = SOFT
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.CanvasSize = UDim2.new()
	s.ZIndex = z
	s.Parent = parent
	return s
end

-- ─── Kurulum ────────────────────────────────────────────────────────────────

function DefenseUI.Create(screen: ScreenGui, hooks: Hooks): UI
	local data: any = nil
	local run: any = nil
	local currentPlanet = 1
	local chosenSector = 1
	local openShop: string? = nil
	local picked: { support: string? } = { support = nil }
	local ui: UI

	-- ═══ Pencere iskeleti ═══════════════════════════════════════════════════
	local function window(name: string, title: string, colors: { Color3 }, w: number, h: number): (Frame, Frame, Frame, FancyKit.Driver)
		local root = UiKit.Window(screen, name, colors[1])
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = UDim2.fromScale(0.5, 0.52)
		root.Size = UDim2.fromOffset(w, h)
		root.Visible = false
		root.ZIndex = Z
		local driver = FancyKit.driver(root)
		local shell = FancyKit.shell(root, title, colors, 62, Z, driver, 40)
		shell.close.Activated:Connect(function()
			root.Visible = false
		end)
		local body = Instance.new("Frame")
		body.Position = UDim2.fromOffset(14, 74)
		body.Size = UDim2.new(1, -28, 1, -88)
		body.BackgroundTransparency = 1
		body.ZIndex = Z + 2
		body.Parent = root
		return root, body, shell.header, driver
	end

	-- ═══ DEFEND penceresi ═══════════════════════════════════════════════════
	--[[
		İki sayfa (Batur: "crewmate seçtikten sonra NEXT deyince silahımızı
		seçelim"): 1) crewmate'ler (role göre gruplu, en güçlüden zayıfa,
		slot kadar), 2) bölüm + gear + DEFEND!.

		Kaydırma ("aşağı inemiyorum"): seçince liste YENİDEN ÇİZİLMİYOR,
		yalnızca o kartın çerçevesi değişiyor (eskiden her tıklama listeyi
		baştan kurup en üste atıyordu). Veri gelince yeniden çizilse de
		kaydırma yeri korunuyor.
	]]
	local prepRoot, prepBody = window("DefensePrepare", "DEFEND", {
		Color3.fromRGB(60, 200, 110), Color3.fromRGB(40, 150, 230), Color3.fromRGB(120, 230, 90),
	}, 840, 560)
	local chosen: { [number]: boolean } = {}
	local chosenGear = ""
	local page = "crew"

	-- ── Sayfa 1: crewmate'ler ──
	local crewPage = Instance.new("Frame")
	crewPage.Size = UDim2.fromScale(1, 1)
	crewPage.BackgroundTransparency = 1
	crewPage.ZIndex = Z + 3
	crewPage.Parent = prepBody
	local crewHeader = label(crewPage, "1 · PICK YOUR CREW", 20, Color3.fromRGB(150, 255, 180), Z + 4)
	crewHeader.Size = UDim2.new(1, -340, 0, 30)
	crewHeader.TextXAlignment = Enum.TextXAlignment.Left
	local countChip, countText = chip(crewPage, "", Color3.fromRGB(60, 70, 110), Z + 4, 120)
	countChip.AnchorPoint = Vector2.new(1, 0)
	countChip.Position = UDim2.new(1, -176, 0, 2)
	countChip.Size = UDim2.fromOffset(120, 28)
	countText.TextSize = 16
	local autoB = button(crewPage, "⚡ BEST CREW", UDim2.fromOffset(160, 38), BLUE, Z + 4, 16)
	autoB.holder.AnchorPoint = Vector2.new(1, 0)
	autoB.holder.Position = UDim2.new(1, -6, 0, -4)
	local crewList = scroller(crewPage, Z + 3)
	crewList.Position = UDim2.fromOffset(0, 40)
	crewList.Size = UDim2.new(1, 0, 1, -110)
	crewList.ScrollingDirection = Enum.ScrollingDirection.Y
	crewList.ScrollBarThickness = 10
	list(crewList, false, 6)
	local nextB = button(crewPage, "NEXT ▶", UDim2.fromOffset(240, 58), GREEN, Z + 4, 24)
	nextB.holder.AnchorPoint = Vector2.new(1, 1)
	nextB.holder.Position = UDim2.new(1, 0, 1, 0)
	local crewNote = label(crewPage, "Tap crewmates to take them. Stronger ones earn more, but they can fall!", 14, SOFT, Z + 4, 1.2)
	crewNote.AnchorPoint = Vector2.new(0, 1)
	crewNote.Position = UDim2.new(0, 0, 1, -16)
	crewNote.Size = UDim2.new(1, -260, 0, 24)
	crewNote.TextXAlignment = Enum.TextXAlignment.Left
	crewNote.TextWrapped = true

	-- ── Sayfa 2: bölüm + gear ──
	local gearPage = Instance.new("Frame")
	gearPage.Size = UDim2.fromScale(1, 1)
	gearPage.BackgroundTransparency = 1
	gearPage.ZIndex = Z + 3
	gearPage.Visible = false
	gearPage.Parent = prepBody
	local secTitle = label(gearPage, "2 · SECTOR", 20, Color3.fromRGB(150, 255, 180), Z + 4)
	secTitle.Size = UDim2.new(1, 0, 0, 28)
	secTitle.TextXAlignment = Enum.TextXAlignment.Left
	local secCard = panel(gearPage, UDim2.new(1, 0, 0, 74), UDim2.fromOffset(0, 32), Vector2.zero, Z + 4,
		Color3.fromRGB(36, 44, 72), Color3.fromRGB(20, 24, 40), 12)
	local prevB = button(secCard, "◀", UDim2.fromOffset(50, 50), BLUE, Z + 5, 22)
	prevB.holder.AnchorPoint = Vector2.new(0, 0.5)
	prevB.holder.Position = UDim2.new(0, 12, 0.5, 2)
	local sectorLabel = label(secCard, "", 28, WHITE, Z + 5)
	sectorLabel.Position = UDim2.fromOffset(70, 6)
	sectorLabel.Size = UDim2.new(1, -140, 0, 34)
	local sectorSub = label(secCard, "", 15, GOLD, Z + 5, 1.3)
	sectorSub.Position = UDim2.fromOffset(70, 42)
	sectorSub.Size = UDim2.new(1, -140, 0, 20)
	local nextSB = button(secCard, "▶", UDim2.fromOffset(50, 50), BLUE, Z + 5, 22)
	nextSB.holder.AnchorPoint = Vector2.new(1, 0.5)
	nextSB.holder.Position = UDim2.new(1, -12, 0.5, 2)

	local gearTitle = label(gearPage, "3 · PICK YOUR GEAR", 20, Color3.fromRGB(150, 255, 180), Z + 4)
	gearTitle.Position = UDim2.fromOffset(0, 118)
	gearTitle.Size = UDim2.new(1, 0, 0, 28)
	gearTitle.TextXAlignment = Enum.TextXAlignment.Left
	local gearList = Instance.new("Frame")
	gearList.Position = UDim2.fromOffset(0, 150)
	gearList.Size = UDim2.new(1, 0, 0, 200)
	gearList.BackgroundTransparency = 1
	gearList.ZIndex = Z + 4
	gearList.Parent = gearPage
	local gearGrid = Instance.new("UIGridLayout")
	gearGrid.CellSize = UDim2.new(1 / 3, -8, 1, 0)
	gearGrid.CellPadding = UDim2.fromOffset(12, 0)
	gearGrid.SortOrder = Enum.SortOrder.LayoutOrder
	gearGrid.Parent = gearList
	local backB = button(gearPage, "◀ BACK", UDim2.fromOffset(170, 58), GREY, Z + 4, 20)
	backB.holder.AnchorPoint = Vector2.new(0, 1)
	backB.holder.Position = UDim2.new(0, 0, 1, 0)
	local goPrepB = button(gearPage, "DEFEND! ▶", UDim2.fromOffset(260, 58), GREEN, Z + 4, 26)
	goPrepB.holder.AnchorPoint = Vector2.new(1, 1)
	goPrepB.holder.Position = UDim2.new(1, 0, 1, 0)

	local function maxSector(): number
		local p = data and data.planets and data.planets[currentPlanet]
		return (if p then p.best else 0) + 1
	end

	local function freeCrew(): { any }
		local out = {}
		for _, c in (if data then data.crew else nil) or {} do
			if not c.away then
				table.insert(out, c)
			end
		end
		return out
	end

	local function chosenCount(): number
		local n = 0
		for _ in chosen do
			n += 1
		end
		return n
	end

	local renderPrep: () -> ()
	-- Seçimde yalnızca kartın görünüşü değişiyor (liste yeniden çizilmiyor)
	local cardViews: { [number]: { stroke: UIStroke, tick: Frame } } = {}

	local function refreshCounts()
		local cap = if data then data.slots else DefenseConfig.BaseSlots
		local count = chosenCount()
		countText.Text = string.format("CREW %d / %d", count, cap)
		nextB.set(if count > 0 then "NEXT ▶" else "PICK CREW", if count > 0 then GREEN else nil)
		for slot, v in cardViews do
			local on = chosen[slot] == true
			v.stroke.Color = if on then GOLD else OUTLINE
			v.stroke.Thickness = if on then 4 else 2.5
			v.tick.Visible = on
		end
	end

	local function crewCard(parent: Instance, c: any, order: number)
		local def = Config.GetUnit(c.unitId)
		local card = Instance.new("TextButton")
		card.LayoutOrder = order
		card.Size = UDim2.fromOffset(104, 122)
		card.BackgroundColor3 = WHITE
		card.AutoButtonColor = false
		card.Text = ""
		card.ZIndex = Z + 5
		card.Parent = parent
		FancyKit.corner(card, 10)
		local stroke = Instance.new("UIStroke")
		stroke.Color = OUTLINE
		stroke.Thickness = 2.5
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = card
		local rarity = def and Config.Rarities[def.rarity]
		local tint = if rarity then rarity.color else GREY
		FancyKit.gradient(card, { tint:Lerp(WHITE, 0.15), tint:Lerp(Color3.new(0, 0, 0), 0.5) }, 90)
		local iconHolder = Instance.new("Frame")
		iconHolder.Size = UDim2.fromOffset(64, 64)
		iconHolder.Position = UDim2.fromOffset(20, 6)
		iconHolder.BackgroundTransparency = 1
		iconHolder.ZIndex = Z + 6
		iconHolder.Parent = card
		pcall(UiKit.UnitIcon, iconHolder, 64, c.unitId)
		local mutation = Config.GetMutation(c.mutationId)
		local name = label(card, (if mutation then mutation.name .. " " else "") .. (if def then def.name else c.unitId), 12, WHITE, Z + 7, 1.3)
		name.Position = UDim2.fromOffset(3, 72)
		name.Size = UDim2.new(1, -6, 0, 16)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local power = DefenseConfig.GetPower(c.unitId, c.mutationId)
		local pw = label(card, string.format("⚡ %.2f", power), 13, GOLD, Z + 7, 1.2)
		pw.Position = UDim2.fromOffset(3, 92)
		pw.Size = UDim2.new(1, -6, 0, 16)
		local tick, _ = chip(card, "✓", GREEN, Z + 8, 26)
		tick.Position = UDim2.new(1, -30, 0, 4)
		tick.Visible = false
		cardViews[c.slot] = { stroke = stroke, tick = tick }
		card.Activated:Connect(function()
			if chosen[c.slot] then
				chosen[c.slot] = nil
			elseif data and chosenCount() < data.slots then
				chosen[c.slot] = true
			end
			refreshCounts()
		end)
	end

	local function gearCard(order: number, id: string, icon: string, title: string, sub: string, owned: boolean)
		local selected = chosenGear == id
		local card = Instance.new("TextButton")
		card.LayoutOrder = order
		card.BackgroundColor3 = WHITE
		card.AutoButtonColor = false
		card.Text = ""
		card.ZIndex = Z + 5
		card.Parent = gearList
		FancyKit.corner(card, 14)
		FancyKit.border(card, if selected then GOLD else OUTLINE, if selected then 5 else 3)
		FancyKit.gradient(card, if owned then { Color3.fromRGB(70, 92, 140), Color3.fromRGB(36, 44, 74) }
			else { Color3.fromRGB(64, 64, 74), Color3.fromRGB(36, 36, 44) }, 90)
		local ic = label(card, icon, 56, WHITE, Z + 6, 0)
		ic.Position = UDim2.fromOffset(0, 12)
		ic.Size = UDim2.new(1, 0, 0, 70)
		local t = label(card, title, 19, WHITE, Z + 6)
		t.Position = UDim2.fromOffset(8, 88)
		t.Size = UDim2.new(1, -16, 0, 24)
		local s = label(card, sub, 13, SOFT, Z + 6, 1.1)
		s.Position = UDim2.fromOffset(10, 116)
		s.Size = UDim2.new(1, -20, 0, 44)
		s.TextWrapped = true
		s.TextYAlignment = Enum.TextYAlignment.Top
		if selected then
			local tick, _ = chip(card, "✓ SELECTED", GREEN, Z + 8, 110)
			tick.AnchorPoint = Vector2.new(0.5, 1)
			tick.Position = UDim2.new(0.5, 0, 1, -8)
		elseif not owned then
			local lock, _ = chip(card, "🔒 ARMORY", GREY, Z + 8, 110)
			lock.AnchorPoint = Vector2.new(0.5, 1)
			lock.Position = UDim2.new(0.5, 0, 1, -8)
		end
		card.Activated:Connect(function()
			if owned then
				chosenGear = id
				renderPrep()
			end
		end)
	end

	renderPrep = function()
		crewPage.Visible = page == "crew"
		gearPage.Visible = page == "gear"
		-- Sayfa 2
		for _, ch in gearList:GetChildren() do
			if ch:IsA("GuiObject") then
				ch:Destroy()
			end
		end
		local maxS = maxSector()
		chosenSector = math.clamp(chosenSector, 1, maxS)
		local per = DefenseConfig.WavesPerSector
		sectorLabel.Text = "SECTOR " .. chosenSector
		sectorSub.Text = string.format("Waves %d-%d   %s%s", (chosenSector - 1) * per + 1, chosenSector * per,
			stars(sectorStars(data, currentPlanet, chosenSector)), if chosenSector == maxS then "   NEW!" else "")
		prevB.set("◀", if chosenSector > 1 then BLUE else nil)
		nextSB.set("▶", if chosenSector < maxS then BLUE else nil)
		gearCard(1, "", "✋", "NO GEAR", "Just command your crew.", true)
		for i, g in DefenseConfig.Gears do
			local level = if data then (data[g.field] or 0) else 0
			gearCard(i + 1, g.id, g.icon, if level > 0 then string.format("%s  Lv %d", string.upper(g.name), level) else string.upper(g.name),
				if level > 0 then g.desc else "Buy it at the ARMORY with gold.", level > 0)
		end

		-- Sayfa 1 (kaydırma yeri korunuyor)
		local keep = crewList.CanvasPosition
		table.clear(cardViews)
		for _, ch in crewList:GetChildren() do
			if ch:IsA("GuiObject") then
				ch:Destroy()
			end
		end
		local free = freeCrew()
		if #free == 0 then
			local none = label(crewList, "No crewmates at your base. Steal some in space first!", 18, SOFT, Z + 5)
			none.Size = UDim2.new(1, 0, 0, 60)
		end
		for r, roleId in DefenseConfig.RoleOrder do
			local role = DefenseConfig.Roles[roleId]
			local group = {}
			for _, c in free do
				if DefenseConfig.GetRole(c.unitId).id == roleId then
					table.insert(group, c)
				end
			end
			if #group > 0 then
				table.sort(group, function(a, b)
					return DefenseConfig.GetPower(a.unitId, a.mutationId) > DefenseConfig.GetPower(b.unitId, b.mutationId)
				end)
				local head = Instance.new("Frame")
				head.LayoutOrder = r * 2 - 1
				head.Size = UDim2.new(1, -16, 0, 28)
				head.BackgroundTransparency = 1
				head.ZIndex = Z + 4
				head.Parent = crewList
				local c1, _ = chip(head, role.icon .. " " .. string.upper(role.name) .. "S", role.color, Z + 5, 130)
				c1.Position = UDim2.fromOffset(0, 2)
				local d = label(head, role.desc, 13, SOFT, Z + 5, 1.1)
				d.Position = UDim2.fromOffset(140, 0)
				d.Size = UDim2.new(1, -140, 1, 0)
				d.TextXAlignment = Enum.TextXAlignment.Left
				d.TextTruncate = Enum.TextTruncate.AtEnd
				-- Satır yüksekliği elle (AutomaticSize + grid kaydırmayı şaşırtıyordu)
				local perRow = 6
				local rows = math.ceil(#group / perRow)
				local row = Instance.new("Frame")
				row.LayoutOrder = r * 2
				row.Size = UDim2.new(1, -16, 0, rows * 130)
				row.BackgroundTransparency = 1
				row.ZIndex = Z + 4
				row.Parent = crewList
				local grid = Instance.new("UIGridLayout")
				grid.CellSize = UDim2.fromOffset(104, 122)
				grid.CellPadding = UDim2.fromOffset(8, 8)
				grid.SortOrder = Enum.SortOrder.LayoutOrder
				grid.Parent = row
				for i, c in group do
					crewCard(row, c, i)
				end
			end
		end
		refreshCounts()
		task.defer(function()
			crewList.CanvasPosition = keep
		end)
	end

	prevB.button.Activated:Connect(function()
		chosenSector = math.max(1, chosenSector - 1)
		renderPrep()
	end)
	nextSB.button.Activated:Connect(function()
		chosenSector = math.min(maxSector(), chosenSector + 1)
		renderPrep()
	end)
	autoB.button.Activated:Connect(function()
		-- Her rolden en güçlüsü önce, sonra kalan en güçlüler
		table.clear(chosen)
		local free = freeCrew()
		table.sort(free, function(a, b)
			return DefenseConfig.GetPower(a.unitId, a.mutationId) > DefenseConfig.GetPower(b.unitId, b.mutationId)
		end)
		local cap = if data then data.slots else DefenseConfig.BaseSlots
		local seenRole: { [string]: boolean } = {}
		for _, c in free do
			local r = DefenseConfig.GetRole(c.unitId).id
			if not seenRole[r] and chosenCount() < cap then
				seenRole[r] = true
				chosen[c.slot] = true
			end
		end
		for _, c in free do
			if chosenCount() >= cap then
				break
			end
			chosen[c.slot] = true
		end
		refreshCounts()
	end)
	nextB.button.Activated:Connect(function()
		if chosenCount() == 0 then
			return
		end
		page = "gear"
		renderPrep()
	end)
	backB.button.Activated:Connect(function()
		page = "crew"
		renderPrep()
	end)
	goPrepB.button.Activated:Connect(function()
		if chosenCount() == 0 then
			page = "crew"
			renderPrep()
			return
		end
		local slots = {}
		for slot in chosen do
			table.insert(slots, slot)
		end
		prepRoot.Visible = false
		hooks.send("prepare", chosenSector, slots, chosenGear)
	end)

	-- ═══ Dükkân penceresi (dört dükkân aynı pencerede) ═════════════════════
	--[[
		2026-10-02 (Batur: "shopların içindeki UI çok kötü, hepsini elden
		geçir"): oyunun mağazasındaki gibi renkli ışınlı kartlar
		(FancyKit.card) ızgarası: büyük simge, ad, seviye noktaları,
		"şimdi → sonra" etkisi, altta fiyat düğmesi. Hastanede crewmate'in
		kendi simgesi, REVIVE ve LET GO.
	]]
	local shopRoot, shopBody, shopHeader, shopDriver = window("DefenseShop", "SHOP", {
		Color3.fromRGB(255, 150, 40), Color3.fromRGB(255, 80, 120), Color3.fromRGB(255, 200, 60),
	}, 840, 540)
	local shopGold, shopGoldText = chip(shopRoot, "", Color3.fromRGB(220, 160, 30), Z + 6, 130)
	shopGold.AnchorPoint = Vector2.new(1, 0.5)
	shopGold.Position = UDim2.new(1, -70, 0, 31)
	shopGold.Size = UDim2.fromOffset(130, 34)
	shopGoldText.TextSize = 19
	local shopIntro = label(shopBody, "", 15, SOFT, Z + 3, 1.4)
	shopIntro.Size = UDim2.new(1, 0, 0, 22)
	shopIntro.TextXAlignment = Enum.TextXAlignment.Left
	local shopList = scroller(shopBody, Z + 3)
	shopList.Position = UDim2.fromOffset(0, 30)
	shopList.Size = UDim2.new(1, 0, 1, -30)
	shopList.ScrollBarImageColor3 = Color3.fromRGB(255, 226, 90)
	local shopGrid = Instance.new("UIGridLayout")
	shopGrid.CellSize = UDim2.fromOffset(190, 262)
	shopGrid.CellPadding = UDim2.fromOffset(10, 10)
	shopGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	shopGrid.SortOrder = Enum.SortOrder.LayoutOrder
	shopGrid.Parent = shopList

	local SHOP_TITLE = { armory = "ARMORY", shop = "COMMAND SHOP", market = "MARKET", hospital = "HOSPITAL" }
	local SHOP_INTRO = {
		armory = "Gear for you and stronger crew roles. Paid with 💰 gold from stars.",
		shop = "Take more crewmates into battle and toughen the ship.",
		market = "One-use boosts. Fire them during a wave from the bottom bar.",
		hospital = "Crewmates that fell in battle. Revive them or let them go.",
	}

	type ShopCard = {
		order: number,
		tint: Color3,
		icon: string?,
		unitId: string?,
		title: string,
		level: string?,
		effect: string?,
		sub: string?,
		buyText: string,
		buyColor: Color3?,
		onBuy: (() -> ())?,
		altText: string?,
		onAlt: (() -> ())?,
	}

	local function shopCard(c: ShopCard)
		local slot = Instance.new("Frame")
		slot.LayoutOrder = c.order
		slot.BackgroundTransparency = 1
		slot.ZIndex = Z + 2
		slot.Parent = shopList
		local card = FancyKit.card(slot, c.tint, UDim2.fromScale(1, 1), Z + 2, shopDriver, UDim2.new(0.5, 0, 0, 58))
		FancyKit.hover(slot, 1.03)
		-- Simge
		local iconHolder = Instance.new("Frame")
		iconHolder.AnchorPoint = Vector2.new(0.5, 0)
		iconHolder.Position = UDim2.new(0.5, 0, 0, 8)
		iconHolder.Size = UDim2.fromOffset(100, 100)
		iconHolder.BackgroundTransparency = 1
		iconHolder.ZIndex = Z + 4
		iconHolder.Parent = card
		FancyKit.glow(iconHolder, c.tint:Lerp(WHITE, 0.4), 1.1, 0.4, Z + 4)
		if c.unitId then
			pcall(UiKit.UnitIcon, iconHolder, 96, c.unitId)
		else
			local ic = label(iconHolder, c.icon or "?", 62, WHITE, Z + 5, 0)
			ic.Size = UDim2.fromScale(1, 1)
		end
		-- Ad
		local t = label(card, c.title, 18, WHITE, Z + 6, 2.2)
		t.Position = UDim2.fromOffset(8, 110)
		t.Size = UDim2.new(1, -16, 0, 22)
		t.TextScaled = true
		local fit = Instance.new("UITextSizeConstraint")
		fit.MaxTextSize = 18
		fit.MinTextSize = 11
		fit.Parent = t
		local y = 134
		if c.level then
			local lv = label(card, c.level, 15, GOLD, Z + 6, 1.6)
			lv.Position = UDim2.fromOffset(8, y)
			lv.Size = UDim2.new(1, -16, 0, 18)
			y += 20
		end
		if c.effect then
			local ef = label(card, c.effect, 14, Color3.fromRGB(150, 255, 170), Z + 6, 1.6)
			ef.Position = UDim2.fromOffset(8, y)
			ef.Size = UDim2.new(1, -16, 0, 18)
			y += 20
		end
		if c.sub then
			local s = label(card, c.sub, 12, Color3.fromRGB(230, 236, 255), Z + 6, 1.4)
			s.Position = UDim2.fromOffset(10, y)
			s.Size = UDim2.new(1, -20, 0, 54 - (y - 134))
			s.TextWrapped = true
			s.TextYAlignment = Enum.TextYAlignment.Top
		end
		-- Düğmeler
		if c.altText then
			local buy = FancyKit.button(card, UDim2.new(0.6, -9, 0, 44), c.buyColor or GREY, 15, Z + 6, shopDriver)
			buy.set(c.buyText, c.buyColor)
			buy.holder.AnchorPoint = Vector2.new(0, 1)
			buy.holder.Position = UDim2.new(0, 6, 1, -6)
			if c.onBuy then
				buy.button.Activated:Connect(c.onBuy)
			end
			local alt = FancyKit.button(card, UDim2.new(0.4, -9, 0, 44), RED, 13, Z + 6, shopDriver)
			alt.set(c.altText, RED)
			alt.holder.AnchorPoint = Vector2.new(1, 1)
			alt.holder.Position = UDim2.new(1, -6, 1, -6)
			if c.onAlt then
				alt.button.Activated:Connect(c.onAlt)
			end
		else
			local buy = FancyKit.button(card, UDim2.new(1, -16, 0, 46), c.buyColor or GREY, 18, Z + 6, shopDriver)
			buy.set(c.buyText, c.buyColor)
			buy.holder.AnchorPoint = Vector2.new(0.5, 1)
			buy.holder.Position = UDim2.new(0.5, 0, 1, -6)
			if c.onBuy then
				buy.button.Activated:Connect(c.onBuy)
			end
		end
	end

	local function renderShop()
		local kind = openShop
		if not kind then
			return
		end
		for _, c in shopList:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local gold = if data then data.gold else 0
		shopGoldText.Text = "💰 " .. tostring(gold)
		shopIntro.Text = SHOP_INTRO[kind] or ""
		for _, d in shopHeader:GetDescendants() do
			if d:IsA("TextLabel") and (d.Text == "SHOP" or SHOP_TITLE.armory == d.Text or SHOP_TITLE.shop == d.Text
				or SHOP_TITLE.market == d.Text or SHOP_TITLE.hospital == d.Text) then
				d.Text = SHOP_TITLE[kind] or "SHOP"
			end
		end
		if not data then
			return
		end
		local function price(cost: number?, buyWord: boolean?): (string, Color3?)
			if not cost then
				return "MAXED", nil
			end
			return (if buyWord then "BUY  💰 " else "💰 ") .. cost, if gold >= cost then GREEN else nil
		end
		if kind == "armory" then
			local saber = data.saber or 0
			local S = DefenseConfig.Saber
			local t1, c1 = price(if saber == 0 then S.price else S.upgradeCosts[saber], saber == 0)
			shopCard({
				order = 1, tint = Color3.fromRGB(60, 140, 255), icon = "⚔", title = "LIGHTSABER",
				level = if saber > 0 then pips(saber, #S.upgradeCosts + 1) else "NEW GEAR",
				effect = if saber > 0 and saber <= #S.upgradeCosts then string.format("DMG +%d%% → +%d%%",
					math.floor(S.perLevel * (saber - 1) * 100), math.floor(S.perLevel * saber * 100)) else nil,
				sub = "Slash every enemy in front of you.", buyText = t1, buyColor = c1,
				onBuy = function()
					hooks.send("buy", "saber")
				end,
			})
			local ray = data.raygun or 0
			local R = DefenseConfig.RayGun
			local t2, c2 = price(if ray == 0 then R.price else R.upgradeCosts[ray], ray == 0)
			shopCard({
				order = 2, tint = Color3.fromRGB(255, 70, 140), icon = "🔫", title = "RAY GUN",
				level = if ray > 0 then pips(ray, #R.upgradeCosts + 1) else "NEW GEAR",
				effect = if ray > 0 and ray <= #R.upgradeCosts then string.format("DMG +%d%% → +%d%%",
					math.floor(R.perLevel * (ray - 1) * 100), math.floor(R.perLevel * ray * 100)) else nil,
				sub = "Laser the closest enemy you aim at.", buyText = t2, buyColor = c2,
				onBuy = function()
					hooks.send("buy", "raygun")
				end,
			})
			for i, id in DefenseConfig.RoleOrder do
				local role = DefenseConfig.Roles[id]
				local level = data.roles[id] or 0
				local now = math.floor(DefenseConfig.RoleLevelBonus * level * 100 + 0.5)
				local nxt = math.floor(DefenseConfig.RoleLevelBonus * (level + 1) * 100 + 0.5)
				local t, c = price(DefenseConfig.RoleUpgradeCost(level))
				shopCard({
					order = 10 + i, tint = role.color, icon = role.icon, title = string.upper(role.name) .. "S",
					level = pips(level, DefenseConfig.RoleMaxLevel),
					effect = if level < DefenseConfig.RoleMaxLevel then string.format("POWER +%d%% → +%d%%", now, nxt) else "POWER +" .. now .. "%",
					sub = role.desc, buyText = t, buyColor = c,
					onBuy = function()
						hooks.send("buy", "role", id)
					end,
				})
			end
		elseif kind == "shop" then
			local t1, c1 = price(DefenseConfig.SlotCosts[data.slotLevel + 1])
			shopCard({
				order = 1, tint = Color3.fromRGB(70, 140, 255), icon = "👥", title = "CREW SLOTS",
				level = pips(data.slotLevel, #DefenseConfig.SlotCosts),
				effect = if DefenseConfig.SlotCosts[data.slotLevel + 1] then string.format("%d → %d CREW", data.slots, data.slots + 1)
					else string.format("%d CREW", data.slots),
				sub = "Crewmates you can take into one battle.", buyText = t1, buyColor = c1,
				onBuy = function()
					hooks.send("buy", "slot")
				end,
			})
			local t2, c2 = price(DefenseConfig.HullCosts[data.hullLevel + 1])
			shopCard({
				order = 2, tint = Color3.fromRGB(60, 190, 230), icon = "🛡", title = "SHIP HULL",
				level = pips(data.hullLevel, #DefenseConfig.HullCosts),
				effect = if DefenseConfig.HullCosts[data.hullLevel + 1]
					then string.format("%d → %d HULL", data.hull, data.hull + DefenseConfig.HullPerLevel) else string.format("%d HULL", data.hull),
				sub = "Enemies that reach the ship damage it.", buyText = t2, buyColor = c2,
				onBuy = function()
					hooks.send("buy", "hull")
				end,
			})
		elseif kind == "market" then
			for i, s in DefenseConfig.Supports do
				local have = data.supports[s.id] or 0
				local full = have >= DefenseConfig.SupportStack
				shopCard({
					order = i, tint = PURPLE:Lerp(Color3.fromRGB(255, 120, 200), (i - 1) * 0.3), icon = s.icon,
					title = string.upper(s.name),
					level = string.format("OWNED %d / %d", have, DefenseConfig.SupportStack),
					sub = s.desc .. " One use per wave.",
					buyText = if full then "FULL" else "💰 " .. s.price,
					buyColor = if not full and gold >= s.price then GREEN else nil,
					onBuy = function()
						hooks.send("buy", "support", s.id)
					end,
				})
			end
		elseif kind == "hospital" then
			if #data.hospital == 0 then
				shopCard({
					order = 1, tint = Color3.fromRGB(80, 200, 120), icon = "✚", title = "ALL HEALTHY",
					sub = "Crewmates that fall in battle come here. Revive them for 15 minutes of their earnings.",
					buyText = "NOBODY HERE", buyColor = nil,
				})
			end
			for i, h in data.hospital do
				local def = Config.GetUnit(h.unitId)
				local mutation = Config.GetMutation(h.mutationId)
				local name = (if mutation then mutation.name .. " " else "") .. (if def then def.name else h.unitId)
				shopCard({
					order = i, tint = Color3.fromRGB(230, 70, 90), unitId = h.unitId, title = string.upper(name),
					level = DefenseConfig.GetRole(h.unitId).icon .. " " .. DefenseConfig.GetRole(h.unitId).name,
					sub = "Revive = 15 min of its earnings.",
					buyText = "$" .. Config.FormatCash(h.cost), buyColor = GREEN,
					onBuy = function()
						hooks.send("revive", h.slot)
					end,
					altText = "LET GO",
					onAlt = function()
						hooks.send("release", h.slot)
					end,
				})
			end
		end
	end

	-- ═══ Gezegende yürürken ═════════════════════════════════════════════════
	local hud = Instance.new("Frame")
	hud.Name = "DefensePlanetHud"
	hud.Size = UDim2.fromScale(1, 1)
	hud.BackgroundTransparency = 1
	hud.Visible = false
	hud.ZIndex = Z - 12
	hud.Parent = screen

	--[[
		Durum (Batur: "uzay gemisindeki UI'lere benzesin"): oyunun sol
		alttaki uzay hızı / para haplarıyla AYNI bileşen (UiKit.StatPill).
		2026-10-02 (Batur: "ekranın ortasındaki UI'ler saçma, ortada
		durmasın; gold'a gerek yok, markette görünsün yeter"): ortadan
		kalktı, SAĞ SÜTUNDA dalga kartının üstünde. Altın yalnızca dükkânda.
	]]
	local side = Instance.new("Frame")
	side.Name = "DefenseSide"
	side.AnchorPoint = if TOUCH then Vector2.zero else Vector2.new(1, 0)
	side.Position = if TOUCH then UDim2.fromOffset(12, 72) else UDim2.new(1, -12, 0, 170)
	side.Size = UDim2.fromOffset(236, 0)
	side.AutomaticSize = Enum.AutomaticSize.Y
	side.BackgroundTransparency = 1
	side.ZIndex = Z - 11
	side.Parent = hud
	local sideLayout = list(side, false, 8)
	sideLayout.HorizontalAlignment = if TOUCH then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right
	if TOUCH then
		local s = Instance.new("UIScale")
		s.Scale = 0.8
		s.Parent = side
	end
	local function pill(name: string, tint: Color3, icon: string, order: number, width: number): (Frame, TextLabel, TextLabel)
		local p, disc, value, sub = UiKit.StatPill(side, name, tint)
		p.LayoutOrder = order
		p.Size = UDim2.fromOffset(width, 46)
		UiKit.ArtIcon(disc, 44, icon, 1.25)
		value.TextSize = 20
		value.TextScaled = false
		return p, value, sub
	end
	local planetPill, planetValue, planetSub = pill("DefensePlanetPill", UiKit.CREW.CYAN, "Crewmate", 1, 214)
	local hullPill, hullValue, hullSub = pill("DefenseHullPill", Color3.fromRGB(90, 170, 255), "StrongLock", 2, 214)
	hullSub.Text = "SHIP HULL"
	local _ = planetPill
	-- Gövde çubuğu: hapın içinde, altta ince
	local hullBack = Instance.new("Frame")
	hullBack.AnchorPoint = Vector2.new(0, 1)
	hullBack.Position = UDim2.new(0, 54, 1, -5)
	hullBack.Size = UDim2.new(1, -70, 0, 6)
	hullBack.BackgroundColor3 = Color3.fromRGB(14, 14, 22)
	hullBack.BorderSizePixel = 0
	hullBack.ZIndex = 5
	hullBack.Parent = hullPill
	FancyKit.corner(hullBack, 3)
	local hullFill = Instance.new("Frame")
	hullFill.Size = UDim2.fromScale(1, 1)
	hullFill.BackgroundColor3 = WHITE
	hullFill.BorderSizePixel = 0
	hullFill.ZIndex = 6
	hullFill.Parent = hullBack
	FancyKit.corner(hullFill, 3)
	local hullGrad = FancyKit.gradient(hullFill, { Color3.fromRGB(120, 230, 255), Color3.fromRGB(40, 140, 230) }, 0)
	hullSub.Position = UDim2.new(0, 55, 0, 27)

	-- Yönlendirme: yalnızca hazırlıkta, alttaki düğmelerin üstünde, kutusuz
	local hint = label(hud, "", 15, WHITE, Z - 10, 2)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -172)
	hint.Size = UDim2.fromOffset(560, 20)

	--[[
		Gelen dalga kartı (2026-10-02, Batur: "temaya uymuyor, güzel
		durmuyor"): haplarla aynı dil — rengin koyu gradyanı, kalın koyu
		kenar, nokta dokusu, Fredoka yazı. Her yaratık kendi küçük 3B
		görüntüsüyle (ViewportFrame) ve büyük adet yazısıyla.
	]]
	local incoming = Instance.new("Frame")
	incoming.Name = "DefenseWaveCard"
	incoming.LayoutOrder = 3
	incoming.Size = UDim2.fromOffset(214, 0)
	incoming.AutomaticSize = Enum.AutomaticSize.Y
	incoming.BackgroundColor3 = WHITE
	incoming.BorderSizePixel = 0
	incoming.ZIndex = Z - 11
	incoming.Parent = side
	UiKit.Corner(incoming, 22)
	UiKit.Stroke(incoming, OUTLINE, 3, 0)
	local incGrad = Instance.new("UIGradient")
	incGrad.Rotation = 90
	incGrad.Parent = incoming
	local function tintCard(tint: Color3)
		incGrad.Color = ColorSequence.new(tint:Lerp(Color3.fromRGB(34, 38, 56), 0.62), tint:Lerp(Color3.fromRGB(22, 25, 38), 0.85))
	end
	local incDots = Instance.new("ImageLabel")
	incDots.Name = "Halftone"
	incDots.BackgroundTransparency = 1
	incDots.Size = UDim2.fromScale(1, 1)
	incDots.Image = UiArt.Image("Texture", "halftone_fade")
	incDots.ScaleType = Enum.ScaleType.Crop
	incDots.ImageTransparency = 0.86
	incDots.ZIndex = Z - 11
	incDots.Parent = incoming
	UiKit.Corner(incDots, 22)
	local incBody = Instance.new("Frame")
	incBody.Size = UDim2.new(1, 0, 0, 0)
	incBody.AutomaticSize = Enum.AutomaticSize.Y
	incBody.BackgroundTransparency = 1
	incBody.ZIndex = Z - 10
	incBody.Parent = incoming
	local incPad = Instance.new("UIPadding")
	incPad.PaddingTop = UDim.new(0, 6)
	incPad.PaddingBottom = UDim.new(0, 10)
	incPad.PaddingLeft = UDim.new(0, 10)
	incPad.PaddingRight = UDim.new(0, 10)
	incPad.Parent = incBody
	list(incBody, false, 5)
	local incHead = Instance.new("Frame")
	incHead.LayoutOrder = 0
	incHead.Size = UDim2.new(1, 0, 0, 40)
	incHead.BackgroundTransparency = 1
	incHead.ZIndex = Z - 10
	incHead.Parent = incBody
	local incTitle = label(incHead, "NEXT WAVE", 21, WHITE, Z - 9, 2.5)
	incTitle.Size = UDim2.new(1, 0, 0, 24)
	incTitle.TextXAlignment = Enum.TextXAlignment.Left
	local routeText = label(incHead, "", 13, Color3.fromRGB(215, 222, 245), Z - 9, 1.6)
	routeText.Position = UDim2.fromOffset(1, 23)
	routeText.Size = UDim2.new(1, 0, 0, 15)
	routeText.TextXAlignment = Enum.TextXAlignment.Left
	local incList = Instance.new("Frame")
	incList.LayoutOrder = 1
	incList.Size = UDim2.new(1, 0, 0, 0)
	incList.AutomaticSize = Enum.AutomaticSize.Y
	incList.BackgroundTransparency = 1
	incList.ZIndex = Z - 10
	incList.Parent = incBody
	list(incList, false, 5)
	local lastIncoming = ""

	-- Yaratığın küçük 3B görüntüsü (gezegenin renklerinde, sahadakinin aynısı)
	local function enemyIcon(parent: GuiObject, kind: string, size: number)
		local def = Config.SpaceMonsters[currentPlanet]
		local body = if def then def.planetColor:Lerp(def.glow, 0.25) else Color3.fromRGB(120, 220, 110)
		local dark = if def then def.planetColor2:Lerp(Color3.new(0, 0, 0), 0.35) else Color3.fromRGB(40, 90, 40)
		local glow = if def then def.glow else Color3.fromRGB(180, 255, 120)
		local ok, model = pcall(EnemyModel.Build, kind, body, dark, glow)
		if not (ok and model) then
			return
		end
		for _, d in model:GetDescendants() do
			if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("BillboardGui") then
				d:Destroy()
			end
		end
		local vp = Instance.new("ViewportFrame")
		vp.AnchorPoint = Vector2.new(0, 0.5)
		vp.Position = UDim2.new(0, -6, 0.5, 0)
		vp.Size = UDim2.fromOffset(size, size)
		vp.BackgroundTransparency = 1
		vp.Ambient = Color3.fromRGB(190, 190, 200)
		vp.LightColor = WHITE
		vp.LightDirection = Vector3.new(-0.5, -1, -0.6)
		vp.ZIndex = parent.ZIndex + 1
		vp.Parent = parent
		model:PivotTo(CFrame.new())
		model.Parent = vp
		local cf, sz = model:GetBoundingBox()
		local extent = math.max(sz.X, sz.Y, sz.Z)
		local cam = Instance.new("Camera")
		cam.FieldOfView = 30
		local dist = extent * 0.5 / math.tan(math.rad(15)) * 1.15
		-- Yaratık -Z'ye bakıyor: önden, biraz yandan ve yukarıdan
		cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(dist * 0.5, dist * 0.3, -dist * 0.8), cf.Position)
		cam.Parent = vp
		vp.CurrentCamera = cam
	end

	--[[
		Sağ altta kontrol kümesi (ortada durmasın): üst sırada hız + AUTO,
		alt sırada yalnızca ELDE OLAN destekler. Telefonda zıplama düğmesinin
		üstünde.
	]]
	local controls = Instance.new("Frame")
	controls.Name = "DefenseControls"
	controls.AnchorPoint = Vector2.new(1, 1)
	controls.Position = if TOUCH then UDim2.new(1, -12, 1, -170) else UDim2.new(1, -12, 1, -18)
	controls.Size = UDim2.fromOffset(340, 0)
	controls.AutomaticSize = Enum.AutomaticSize.Y
	controls.BackgroundTransparency = 1
	controls.ZIndex = Z - 11
	controls.Parent = hud
	local ctrlLayout = list(controls, false, 6)
	ctrlLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	if TOUCH then
		local s = Instance.new("UIScale")
		s.Scale = 0.85
		s.Parent = controls
	end
	local function row(order: number): Frame
		local r = Instance.new("Frame")
		r.LayoutOrder = order
		r.Size = UDim2.fromOffset(340, 50)
		r.BackgroundTransparency = 1
		r.ZIndex = Z - 11
		r.Parent = controls
		local l = list(r, true, 6)
		l.HorizontalAlignment = Enum.HorizontalAlignment.Right
		return r
	end
	local topRow = row(1)
	local supportBar = row(2)
	-- Hız
	local speedB = button(topRow, "▶ 1x", UDim2.fromOffset(96, 48), GREY, Z - 10, 18)
	speedB.holder.LayoutOrder = 1
	speedB.button.Activated:Connect(function()
		hooks.send("speed")
	end)
	-- AUTO: dalga bitince sonrakini kendiliğinden başlatır (sonsuz dalgalarda)
	local autoB = button(topRow, "AUTO", UDim2.fromOffset(110, 48), GREY, Z - 10, 17)
	autoB.holder.LayoutOrder = 2
	autoB.button.Activated:Connect(function()
		hooks.send("auto")
	end)
	local autoDeadline: number? = nil

	-- Altta, alet çubuğunun üstünde
	local bottom = Instance.new("Frame")
	bottom.AnchorPoint = Vector2.new(0.5, 1)
	bottom.Position = UDim2.new(0.5, 0, 1, -100)
	bottom.Size = UDim2.fromOffset(470, 66)
	bottom.BackgroundTransparency = 1
	bottom.ZIndex = Z - 11
	bottom.Parent = hud
	local mainB = button(bottom, "⚔ DEFEND", UDim2.fromOffset(260, 62), GREEN, Z - 10, 26)
	local sideB = button(bottom, "🚀 TAKE OFF", UDim2.fromOffset(196, 54), BLUE, Z - 10, 18)
	sideB.holder.AnchorPoint = Vector2.new(1, 0)
	sideB.holder.Position = UDim2.new(1, 0, 0, 4)
	local mode = "idle"
	mainB.button.Activated:Connect(function()
		if mode == "idle" then
			ui.OpenPrepare()
		elseif mode == "prep" then
			hooks.send("go")
		end
	end)
	sideB.button.Activated:Connect(function()
		if mode == "idle" then
			hooks.takeoff()
		elseif mode == "prep" then
			hooks.send("retreat")
		end
	end)

	-- Savaşta destekler (sağ alttaki kümenin alt satırı; yalnızca elde olanlar)
	local supportButtons: { [string]: FancyKit.Button } = {}
	for i, s in DefenseConfig.Supports do
		local b = button(supportBar, "", UDim2.fromOffset(108, 48), PURPLE, Z - 10, 13)
		b.holder.LayoutOrder = i
		b.button.Activated:Connect(function()
			hooks.pickSupport(if picked.support == s.id then nil else s.id)
		end)
		supportButtons[s.id] = b
	end

	-- Sonuç bandı: üstten kayarak
	local banner = panel(screen, UDim2.fromOffset(420, 92), UDim2.new(0.5, 0, 0, -140), Vector2.new(0.5, 0), Z + 20)
	banner.Visible = false
	local bannerStrip = Instance.new("Frame")
	bannerStrip.Size = UDim2.new(1, 0, 0, 8)
	bannerStrip.BackgroundColor3 = GOLD
	bannerStrip.BorderSizePixel = 0
	bannerStrip.ZIndex = Z + 21
	bannerStrip.Parent = banner
	FancyKit.corner(bannerStrip, 4)
	local bannerTitle = label(banner, "", 26, WHITE, Z + 21)
	bannerTitle.Position = UDim2.fromOffset(0, 12)
	bannerTitle.Size = UDim2.new(1, 0, 0, 34)
	local bannerSub = label(banner, "", 16, GOLD, Z + 21)
	bannerSub.Position = UDim2.fromOffset(12, 50)
	bannerSub.Size = UDim2.new(1, -24, 0, 34)
	bannerSub.TextWrapped = true
	local bannerToken = 0

	local function renderSupports()
		local any = false
		for _, s in DefenseConfig.Supports do
			local b = supportButtons[s.id]
			local have = if data then (data.supports[s.id] or 0) else 0
			local active = picked.support == s.id
			-- Elde olmayan destek gösterilmiyor (×0 düğmeleri gereksizdi)
			b.holder.Visible = have > 0
			any = any or have > 0
			b.set(if active then "🎯 TAP" else string.format("%s ×%d", s.icon, have),
				if active then GOLD else PURPLE)
		end
		supportBar.Visible = mode == "fight" and any
	end

	local function setHull(hull: number, maxHull: number, enemies: number?)
		local frac = math.clamp(hull / math.max(1, maxHull), 0, 1)
		hullFill.Size = UDim2.fromScale(frac, 1)
		local low = frac < 0.35
		hullGrad.Color = if low then ColorSequence.new(Color3.fromRGB(255, 140, 120), Color3.fromRGB(220, 50, 50))
			else ColorSequence.new(Color3.fromRGB(120, 230, 255), Color3.fromRGB(40, 140, 230))
		hullValue.Text = string.format("%d/%d", hull, maxHull)
		hullValue.TextColor3 = if low then Color3.fromRGB(255, 130, 120) else Color3.fromRGB(150, 210, 255)
		hullSub.Text = if enemies then string.format("SHIP HULL  ·  👾 %d", enemies) else "SHIP HULL"
	end

	local function renderIncoming()
		if not run then
			lastIncoming = ""
			return
		end
		local fighting = mode == "fight"
		local boss = run.plan.boss
		incTitle.Text = if fighting then "⚔ FIGHTING" elseif boss then "⚠ BOSS WAVE" else "NEXT WAVE"
		-- Oyunun mor-lacivert tonu; savaşta ve boss'ta kırmızıya dönüyor
		local tint = if boss then Color3.fromRGB(255, 60, 90) elseif fighting then Color3.fromRGB(255, 90, 130) else Color3.fromRGB(130, 110, 255)
		incTitle.TextColor3 = if fighting or boss then Color3.fromRGB(255, 170, 170) else Color3.fromRGB(200, 190, 255)
		tintCard(tint)
		routeText.Text = "ROUTE: " .. run.plan.name
		-- Satırlar yalnızca dalga değişince yeniden kuruluyor (3B görüntüler pahalı)
		local key = run.plan.name .. "|" .. currentPlanet
		for _, id in { "Boss", "Brute", "Spitter", "Grub", "Skitter" } do
			key ..= "|" .. tostring(run.plan.counts[id] or 0)
		end
		if key == lastIncoming then
			return
		end
		lastIncoming = key
		for _, c in incList:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local order = 0
		for _, id in { "Boss", "Brute", "Spitter", "Grub", "Skitter" } do
			local n = run.plan.counts[id]
			local def = DefenseConfig.Enemies[id]
			if n and def then
				order += 1
				local row = Instance.new("Frame")
				row.LayoutOrder = order
				row.Size = UDim2.new(1, 0, 0, 36)
				row.BackgroundColor3 = if id == "Boss" then Color3.fromRGB(110, 40, 60) else Color3.fromRGB(48, 54, 78)
				row.BackgroundTransparency = 0.15
				row.ZIndex = Z - 9
				row.Parent = incList
				UiKit.Corner(row, 14)
				UiKit.Stroke(row, OUTLINE, 2, 0)
				enemyIcon(row, id, 42)
				local name = label(row, def.name, 14, if id == "Boss" then Color3.fromRGB(255, 150, 150) else WHITE, Z - 8, 1.6)
				name.Position = UDim2.fromOffset(40, 0)
				name.Size = UDim2.new(1, -86, 1, 0)
				name.TextXAlignment = Enum.TextXAlignment.Left
				name.TextTruncate = Enum.TextTruncate.AtEnd
				local count = label(row, "×" .. n, 20, GOLD, Z - 8, 2.2)
				count.AnchorPoint = Vector2.new(1, 0)
				count.Position = UDim2.new(1, -8, 0, 0)
				count.Size = UDim2.new(0, 44, 1, 0)
				count.TextXAlignment = Enum.TextXAlignment.Right
			end
		end
	end

	local function renderHud()
		mode = if run == nil then "idle" elseif run.phase == "fight" then "fight" else "prep"
		if run then
			planetValue.Text = string.format("SECTOR %d · %d/%d", run.sector, run.waveInSector, DefenseConfig.WavesPerSector)
			planetSub.Text = planetName(currentPlanet) .. "  ·  WAVE " .. run.wave
			setHull(run.hull, run.maxHull, nil)
			local fast = (run.speed or 1) >= 2
			speedB.set(if fast then "⏩ 2x" else "▶ 1x", if fast then ORANGE else GREY)
		else
			planetValue.Text = planetName(currentPlanet)
			planetSub.Text = "PLANET DEFENSE"
			local hull = if data then data.hull else DefenseConfig.BaseHull
			setHull(hull, hull, nil)
		end
		incoming.Visible = run ~= nil
		topRow.Visible = run ~= nil
		if run then
			autoB.set(if run.auto then "🔁 AUTO" else "AUTO", if run.auto then GREEN else GREY)
			autoDeadline = if run.autoIn and run.phase == "prep" then os.clock() + run.autoIn else nil
		else
			autoDeadline = nil
		end
		bottom.Visible = mode ~= "fight"
		if mode == "idle" then
			mainB.set("⚔ DEFEND", GREEN)
			sideB.set("🚀 TAKE OFF", BLUE)
			hint.Text = ""
		elseif mode == "prep" then
			mainB.set("▶ START WAVE", if #run.units > 0 then GREEN else nil)
			sideB.set("↩ RETREAT", RED)
			hint.Text = if (run.carried or 0) > 0
				then (if TOUCH then "Pick a crewmate from your bar, walk onto the field and TAP to drop it"
					else "Pick a crewmate from your bar, walk onto the field and CLICK to drop it")
				else "Your crew is ready. Press ▶ START WAVE!"
		else
			-- Savaşta ortada yazı yok
			hint.Text = ""
		end
		renderIncoming()
		renderSupports()
	end

	-- AUTO geri sayımı yönlendirme yazısında
	task.spawn(function()
		while hud.Parent do
			local deadline = autoDeadline
			if deadline and mode == "prep" and hud.Visible then
				local left = math.max(0, math.ceil(deadline - os.clock()))
				autoB.set(string.format("🔁 AUTO %d", left), GREEN)
			end
			task.wait(0.2)
		end
	end)

	-- ═══ Bölüm kutlaması: yıldızlar tek tek ═════════════════════════════════
	local celebrate = panel(screen, UDim2.fromOffset(460, 220), UDim2.fromScale(0.5, 0.4), Vector2.new(0.5, 0.5), Z + 25,
		Color3.fromRGB(70, 60, 140), Color3.fromRGB(30, 26, 70), 18)
	celebrate.Visible = false
	local celebTitle = label(celebrate, "", 34, GOLD, Z + 26, 3)
	celebTitle.Position = UDim2.fromOffset(0, 14)
	celebTitle.Size = UDim2.new(1, 0, 0, 40)
	local starRow = Instance.new("Frame")
	starRow.AnchorPoint = Vector2.new(0.5, 0)
	starRow.Position = UDim2.new(0.5, 0, 0, 62)
	starRow.Size = UDim2.fromOffset(300, 90)
	starRow.BackgroundTransparency = 1
	starRow.ZIndex = Z + 26
	starRow.Parent = celebrate
	local starLabels: { TextLabel } = {}
	for i = 1, 3 do
		local st = label(starRow, "★", 76, Color3.fromRGB(70, 70, 100), Z + 27, 4)
		st.AnchorPoint = Vector2.new(0.5, 0.5)
		st.Position = UDim2.new((i - 0.5) / 3, 0, 0.5, if i == 2 then -6 else 6)
		st.Size = UDim2.fromOffset(90, 90)
		starLabels[i] = st
	end
	local celebSub = label(celebrate, "", 22, WHITE, Z + 26, 2.4)
	celebSub.Position = UDim2.fromOffset(0, 160)
	celebSub.Size = UDim2.new(1, 0, 0, 30)
	local celebToken = 0

	-- ═══ Dışa açık ══════════════════════════════════════════════════════════
	ui = {} :: any

	function ui.Celebrate(sector: number, got: number, gold: number)
		celebToken += 1
		local token = celebToken
		celebTitle.Text = string.format("SECTOR %d CLEAR!", sector)
		celebSub.Text = if gold > 0 then string.format("+%d 💰 GOLD", gold) else "No new stars - try with fewer losses!"
		celebSub.TextColor3 = if gold > 0 then GOLD else SOFT
		for _, st in starLabels do
			st.TextColor3 = Color3.fromRGB(70, 70, 100)
			st.Size = UDim2.fromOffset(90, 90)
		end
		celebrate.Visible = true
		celebrate.Size = UDim2.fromOffset(380, 180)
		TweenService:Create(celebrate, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(460, 220) }):Play()
		for i = 1, got do
			task.delay(0.35 + i * 0.35, function()
				if celebToken ~= token then
					return
				end
				local st = starLabels[i]
				st.TextColor3 = GOLD
				st.Size = UDim2.fromOffset(140, 140)
				TweenService:Create(st, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Size = UDim2.fromOffset(90, 90) }):Play()
			end)
		end
		task.delay(3.8, function()
			if celebToken == token then
				celebrate.Visible = false
			end
		end)
	end

	function ui.OpenPrepare()
		if run then
			return
		end
		table.clear(chosen)
		chosenSector = maxSector()
		page = "crew"
		-- Varsa gear'ı öne seç
		chosenGear = ""
		if data then
			for _, g in DefenseConfig.Gears do
				if (data[g.field] or 0) > 0 and chosenGear == "" then
					chosenGear = g.id
				end
			end
		end
		shopRoot.Visible = false
		hooks.send("sync")
		renderPrep()
		prepRoot.Visible = true
	end

	function ui.OpenShop(kind: string)
		openShop = kind
		renderShop()
		prepRoot.Visible = false
		shopRoot.Visible = true
	end

	function ui.CloseAll()
		prepRoot.Visible = false
		shopRoot.Visible = false
	end

	function ui.SetData(d: any)
		data = d
		if prepRoot.Visible then
			-- Seçili olup artık evde olmayanları düş
			local free: { [number]: boolean } = {}
			for _, c in freeCrew() do
				free[c.slot] = true
			end
			for slot in chosen do
				if not free[slot] then
					chosen[slot] = nil
				end
			end
			renderPrep()
		end
		if shopRoot.Visible then
			renderShop()
		end
		renderHud()
	end

	function ui.SetRun(r: any?, planet: number?)
		run = r
		if planet then
			currentPlanet = planet
		end
		if r then
			prepRoot.Visible = false
		end
		renderHud()
	end

	function ui.SetPlanetHud(visible: boolean)
		hud.Visible = visible
		if not visible then
			ui.CloseAll()
		end
		renderHud()
	end

	function ui.SetPicked(support: string?)
		picked.support = support
		renderSupports()
	end

	function ui.SetTick(snap: any)
		if run then
			run.hull = snap.hull
			setHull(snap.hull, run.maxHull, #(snap.e or {}))
		end
	end

	function ui.Banner(title: string, sub: string, color: Color3)
		bannerToken += 1
		local token = bannerToken
		bannerTitle.Text = title
		bannerTitle.TextColor3 = color
		bannerStrip.BackgroundColor3 = color
		bannerSub.Text = sub
		banner.Visible = true
		banner.Position = UDim2.new(0.5, 0, 0, -140)
		TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0, 86) }):Play()
		task.delay(3.2, function()
			if bannerToken ~= token then
				return
			end
			TweenService:Create(banner, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.new(0.5, 0, 0, -140) }):Play()
			task.delay(0.3, function()
				if bannerToken == token then
					banner.Visible = false
				end
			end)
		end)
	end

	return ui
end

return DefenseUI
