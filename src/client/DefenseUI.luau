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

local FancyKit = require(script.Parent.FancyKit)
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
	local function window(name: string, title: string, colors: { Color3 }, w: number, h: number): (Frame, Frame, Frame)
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
		return root, body, shell.header
	end

	-- ═══ DEFEND penceresi ═══════════════════════════════════════════════════
	local prepRoot, prepBody = window("DefensePrepare", "DEFEND", {
		Color3.fromRGB(60, 200, 110), Color3.fromRGB(40, 150, 230), Color3.fromRGB(120, 230, 90),
	}, 840, 560)
	local chosen: { [number]: boolean } = {}
	local chosenGear = ""

	-- Sol: crewmate seçimi
	local leftCol = Instance.new("Frame")
	leftCol.Size = UDim2.new(1, -290, 1, 0)
	leftCol.BackgroundTransparency = 1
	leftCol.ZIndex = Z + 3
	leftCol.Parent = prepBody
	local crewHeader = label(leftCol, "1 · PICK YOUR CREW", 20, Color3.fromRGB(150, 255, 180), Z + 4)
	crewHeader.Size = UDim2.new(1, -170, 0, 28)
	crewHeader.TextXAlignment = Enum.TextXAlignment.Left
	local autoB = button(leftCol, "⚡ BEST CREW", UDim2.fromOffset(160, 38), BLUE, Z + 4, 16)
	autoB.holder.AnchorPoint = Vector2.new(1, 0)
	autoB.holder.Position = UDim2.new(1, -6, 0, -4)
	local crewList = scroller(leftCol, Z + 3)
	crewList.Position = UDim2.fromOffset(0, 40)
	crewList.Size = UDim2.new(1, 0, 1, -40)
	list(crewList, false, 6)

	-- Sağ: bölüm, gear, özet
	local rightCol = panel(prepBody, UDim2.new(0, 276, 1, 0), UDim2.new(1, 0, 0, 0), Vector2.new(1, 0), Z + 3,
		Color3.fromRGB(36, 44, 72), Color3.fromRGB(20, 24, 40), 12)
	local secTitle = label(rightCol, "2 · SECTOR", 18, Color3.fromRGB(150, 255, 180), Z + 4)
	secTitle.Position = UDim2.fromOffset(12, 8)
	secTitle.Size = UDim2.new(1, -24, 0, 22)
	secTitle.TextXAlignment = Enum.TextXAlignment.Left
	local prevB = button(rightCol, "◀", UDim2.fromOffset(42, 42), BLUE, Z + 4, 20)
	prevB.holder.Position = UDim2.fromOffset(12, 36)
	local sectorLabel = label(rightCol, "", 24, WHITE, Z + 4)
	sectorLabel.Position = UDim2.fromOffset(58, 34)
	sectorLabel.Size = UDim2.new(1, -116, 0, 28)
	local sectorSub = label(rightCol, "", 13, GOLD, Z + 4, 1.2)
	sectorSub.Position = UDim2.fromOffset(58, 62)
	sectorSub.Size = UDim2.new(1, -116, 0, 16)
	local nextSB = button(rightCol, "▶", UDim2.fromOffset(42, 42), BLUE, Z + 4, 20)
	nextSB.holder.AnchorPoint = Vector2.new(1, 0)
	nextSB.holder.Position = UDim2.new(1, -12, 0, 36)

	local gearTitle = label(rightCol, "3 · GEAR", 18, Color3.fromRGB(150, 255, 180), Z + 4)
	gearTitle.Position = UDim2.fromOffset(12, 92)
	gearTitle.Size = UDim2.new(1, -24, 0, 22)
	gearTitle.TextXAlignment = Enum.TextXAlignment.Left
	local gearList = Instance.new("Frame")
	gearList.Position = UDim2.fromOffset(10, 118)
	gearList.Size = UDim2.new(1, -20, 0, 210)
	gearList.BackgroundTransparency = 1
	gearList.ZIndex = Z + 4
	gearList.Parent = rightCol
	list(gearList, false, 6)

	local countLabel = label(rightCol, "", 18, WHITE, Z + 4)
	countLabel.AnchorPoint = Vector2.new(0, 1)
	countLabel.Position = UDim2.new(0, 12, 1, -76)
	countLabel.Size = UDim2.new(1, -24, 0, 24)
	local goPrepB = button(rightCol, "DEFEND! ▶", UDim2.new(1, -24, 0, 58), GREEN, Z + 4, 24)
	goPrepB.holder.AnchorPoint = Vector2.new(0, 1)
	goPrepB.holder.Position = UDim2.new(0, 12, 1, -10)

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

	local function crewCard(parent: Instance, c: any, order: number)
		local def = Config.GetUnit(c.unitId)
		local selected = chosen[c.slot] == true
		local card = Instance.new("TextButton")
		card.LayoutOrder = order
		card.Size = UDim2.fromOffset(104, 122)
		card.BackgroundColor3 = WHITE
		card.AutoButtonColor = false
		card.Text = ""
		card.ZIndex = Z + 5
		card.Parent = parent
		FancyKit.corner(card, 10)
		FancyKit.border(card, if selected then GOLD else OUTLINE, if selected then 4 else 2.5)
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
		if selected then
			local tick, _ = chip(card, "✓", GREEN, Z + 8, 26)
			tick.Position = UDim2.new(1, -30, 0, 4)
		end
		card.Activated:Connect(function()
			if chosen[c.slot] then
				chosen[c.slot] = nil
			elseif data and chosenCount() < data.slots then
				chosen[c.slot] = true
			end
			renderPrep()
		end)
	end

	local function gearCard(order: number, id: string, icon: string, title: string, sub: string, owned: boolean)
		local selected = chosenGear == id
		local card = Instance.new("TextButton")
		card.LayoutOrder = order
		card.Size = UDim2.new(1, 0, 0, 62)
		card.BackgroundColor3 = WHITE
		card.AutoButtonColor = false
		card.Text = ""
		card.ZIndex = Z + 5
		card.Parent = gearList
		FancyKit.corner(card, 10)
		FancyKit.border(card, if selected then GOLD else OUTLINE, if selected then 4 else 2.5)
		FancyKit.gradient(card, if owned then { Color3.fromRGB(70, 92, 140), Color3.fromRGB(36, 44, 74) }
			else { Color3.fromRGB(64, 64, 74), Color3.fromRGB(36, 36, 44) }, 90)
		local ic = label(card, icon, 30, WHITE, Z + 6, 0)
		ic.Size = UDim2.fromOffset(52, 62)
		local t = label(card, title .. (if owned then "" else "  🔒"), 17, WHITE, Z + 6)
		t.Position = UDim2.fromOffset(52, 8)
		t.Size = UDim2.new(1, -60, 0, 22)
		t.TextXAlignment = Enum.TextXAlignment.Left
		local s = label(card, sub, 12, SOFT, Z + 6, 1.1)
		s.Position = UDim2.fromOffset(52, 32)
		s.Size = UDim2.new(1, -60, 0, 24)
		s.TextXAlignment = Enum.TextXAlignment.Left
		s.TextWrapped = true
		card.Activated:Connect(function()
			if owned then
				chosenGear = id
				renderPrep()
			end
		end)
	end

	renderPrep = function()
		for _, ch in crewList:GetChildren() do
			if ch:IsA("GuiObject") then
				ch:Destroy()
			end
		end
		for _, ch in gearList:GetChildren() do
			if ch:IsA("GuiObject") then
				ch:Destroy()
			end
		end
		-- Bölüm
		local maxS = maxSector()
		chosenSector = math.clamp(chosenSector, 1, maxS)
		local per = DefenseConfig.WavesPerSector
		sectorLabel.Text = "SECTOR " .. chosenSector
		sectorSub.Text = string.format("Waves %d-%d  %s%s", (chosenSector - 1) * per + 1, chosenSector * per,
			stars(sectorStars(data, currentPlanet, chosenSector)), if chosenSector == maxS then "  NEW" else "")
		prevB.set("◀", if chosenSector > 1 then BLUE else nil)
		nextSB.set("▶", if chosenSector < maxS then BLUE else nil)
		local cap = if data then data.slots else DefenseConfig.BaseSlots
		local count = chosenCount()
		countLabel.Text = string.format("CREW  %d / %d", count, cap)
		goPrepB.set(if count > 0 then "DEFEND! ▶" else "PICK YOUR CREW", if count > 0 then GREEN else nil)

		-- Gear: hep görünür
		gearCard(1, "", "✋", "NO GEAR", "Just command your crew", true)
		for i, g in DefenseConfig.Gears do
			local level = if data then (data[g.field] or 0) else 0
			gearCard(i + 1, g.id, g.icon, if level > 0 then string.format("%s  Lv %d", string.upper(g.name), level) else string.upper(g.name),
				if level > 0 then g.desc else "Buy it at the ARMORY with gold", level > 0)
		end

		-- Crewmate'ler: role göre, her grupta en güçlüden zayıfa
		local free = freeCrew()
		if #free == 0 then
			local none = label(crewList, "No crewmates at your base. Steal some in space first!", 18, SOFT, Z + 5)
			none.Size = UDim2.new(1, 0, 0, 60)
			return
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
				head.Size = UDim2.new(1, -10, 0, 28)
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
				local row = Instance.new("Frame")
				row.LayoutOrder = r * 2
				row.Size = UDim2.new(1, -10, 0, 0)
				row.AutomaticSize = Enum.AutomaticSize.Y
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
		renderPrep()
	end)
	goPrepB.button.Activated:Connect(function()
		if chosenCount() == 0 then
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
	local shopRoot, shopBody, shopHeader = window("DefenseShop", "SHOP", {
		Color3.fromRGB(255, 150, 40), Color3.fromRGB(255, 80, 120), Color3.fromRGB(255, 200, 60),
	}, 720, 500)
	local shopGold, shopGoldText = chip(shopRoot, "", Color3.fromRGB(220, 160, 30), Z + 6, 120)
	shopGold.AnchorPoint = Vector2.new(1, 0.5)
	shopGold.Position = UDim2.new(1, -70, 0, 31)
	shopGold.Size = UDim2.fromOffset(120, 32)
	shopGoldText.TextSize = 18
	local shopIntro = label(shopBody, "", 15, SOFT, Z + 3, 1.2)
	shopIntro.Size = UDim2.new(1, 0, 0, 22)
	shopIntro.TextXAlignment = Enum.TextXAlignment.Left
	local shopList = scroller(shopBody, Z + 3)
	shopList.Position = UDim2.fromOffset(0, 28)
	shopList.Size = UDim2.new(1, 0, 1, -28)
	list(shopList, false, 8)

	local SHOP_TITLE = { armory = "ARMORY", shop = "COMMAND SHOP", market = "MARKET", hospital = "HOSPITAL" }
	local SHOP_INTRO = {
		armory = "Gear for you and upgrades for every crew role. Paid with gold from stars.",
		shop = "Bigger crew and a tougher ship hull.",
		market = "One-use boosts you can fire during a wave.",
		hospital = "Crewmates that fell in battle wait here.",
	}

	local function shopRow(order: number, icon: string, iconColor: Color3, title: string, sub: string, levelText: string?,
		actionText: string?, color: Color3?, onClick: (() -> ())?, secondText: string?, onSecond: (() -> ())?)
		local row = panel(shopList, UDim2.new(1, -10, 0, 82), UDim2.new(), Vector2.zero, Z + 4, nil, nil, 12)
		row.LayoutOrder = order
		local badge = Instance.new("Frame")
		badge.Position = UDim2.fromOffset(10, 10)
		badge.Size = UDim2.fromOffset(62, 62)
		badge.BackgroundColor3 = WHITE
		badge.ZIndex = Z + 5
		badge.Parent = row
		FancyKit.corner(badge, 31)
		FancyKit.border(badge, OUTLINE, 3)
		FancyKit.gradient(badge, { iconColor:Lerp(WHITE, 0.25), iconColor:Lerp(Color3.new(0, 0, 0), 0.3) }, 90)
		local ic = label(badge, icon, 30, WHITE, Z + 6, 0)
		ic.Size = UDim2.fromScale(1, 1)
		local t = label(row, title, 20, WHITE, Z + 5)
		t.Position = UDim2.fromOffset(84, 8)
		t.Size = UDim2.new(1, -260, 0, 24)
		t.TextXAlignment = Enum.TextXAlignment.Left
		if levelText then
			local lv = label(row, levelText, 14, GOLD, Z + 5, 1.2)
			lv.Position = UDim2.fromOffset(84, 32)
			lv.Size = UDim2.new(1, -260, 0, 16)
			lv.TextXAlignment = Enum.TextXAlignment.Left
		end
		local s = label(row, sub, 13, SOFT, Z + 5, 1.1)
		s.Position = UDim2.fromOffset(84, if levelText then 50 else 36)
		s.Size = UDim2.new(1, -260, 0, if levelText then 26 else 38)
		s.TextXAlignment = Enum.TextXAlignment.Left
		s.TextYAlignment = Enum.TextYAlignment.Top
		s.TextWrapped = true
		if actionText then
			local b = button(row, actionText, UDim2.fromOffset(150, 50), color or GREY, Z + 5, 18)
			if not color then
				b.set(actionText, nil)
			end
			b.holder.AnchorPoint = Vector2.new(1, 0.5)
			b.holder.Position = UDim2.new(1, if secondText then -170 else -12, 0.5, 0)
			if onClick then
				b.button.Activated:Connect(onClick)
			end
		end
		if secondText then
			local b2 = button(row, secondText, UDim2.fromOffset(150, 50), RED, Z + 5, 16)
			b2.holder.AnchorPoint = Vector2.new(1, 0.5)
			b2.holder.Position = UDim2.new(1, -12, 0.5, 0)
			if onSecond then
				b2.button.Activated:Connect(onSecond)
			end
		end
	end

	local function renderShop()
		local kind = openShop
		if not kind then
			return
		end
		for _, c in shopList:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local gold = if data then data.gold else 0
		shopGoldText.Text = "🪙 " .. tostring(gold)
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
				return "MAX", nil
			end
			return (if buyWord then "BUY 🪙 " else "🪙 ") .. cost, if gold >= cost then GREEN else nil
		end
		if kind == "armory" then
			-- Gear'lar
			local saber = data.saber or 0
			local S = DefenseConfig.Saber
			local t1, c1 = price(if saber == 0 then S.price else S.upgradeCosts[saber], saber == 0)
			shopRow(1, "⚔", Color3.fromRGB(80, 170, 255), "LIGHTSABER",
				"Gear: slash every enemy in front of you. Pick it when you press DEFEND.",
				if saber > 0 then "Lv " .. pips(saber, #S.upgradeCosts + 1) else "NEW GEAR", t1, c1,
				function()
					hooks.send("buy", "saber")
				end)
			local ray = data.raygun or 0
			local R = DefenseConfig.RayGun
			local t2, c2 = price(if ray == 0 then R.price else R.upgradeCosts[ray], ray == 0)
			shopRow(2, "🔫", Color3.fromRGB(255, 90, 140), "RAY GUN",
				"Gear: laser the closest enemy you aim at, from far away.",
				if ray > 0 then "Lv " .. pips(ray, #R.upgradeCosts + 1) else "NEW GEAR", t2, c2,
				function()
					hooks.send("buy", "raygun")
				end)
			-- Rol yükseltmeleri
			for i, id in DefenseConfig.RoleOrder do
				local role = DefenseConfig.Roles[id]
				local level = data.roles[id] or 0
				local bonus = math.floor(DefenseConfig.RoleLevelBonus * level * 100 + 0.5)
				local t, c = price(DefenseConfig.RoleUpgradeCost(level))
				shopRow(10 + i, role.icon, role.color, string.upper(role.name) .. "S",
					string.format("%s  (+%d%% health & power)", role.desc, bonus),
					"Lv " .. pips(level, DefenseConfig.RoleMaxLevel), t, c,
					function()
						hooks.send("buy", "role", id)
					end)
			end
		elseif kind == "shop" then
			local t1, c1 = price(DefenseConfig.SlotCosts[data.slotLevel + 1])
			shopRow(1, "👥", BLUE, string.format("CREW SLOTS · %d", data.slots),
				"How many crewmates you can take into battle.",
				"Lv " .. pips(data.slotLevel, #DefenseConfig.SlotCosts), t1, c1,
				function()
					hooks.send("buy", "slot")
				end)
			local t2, c2 = price(DefenseConfig.HullCosts[data.hullLevel + 1])
			shopRow(2, "🛡", Color3.fromRGB(90, 200, 255), string.format("SHIP HULL · %d", data.hull),
				"Enemies that reach the ship damage it. At 0 the wave is lost.",
				"Lv " .. pips(data.hullLevel, #DefenseConfig.HullCosts), t2, c2,
				function()
					hooks.send("buy", "hull")
				end)
		elseif kind == "market" then
			for i, s in DefenseConfig.Supports do
				local have = data.supports[s.id] or 0
				shopRow(i, s.icon, PURPLE, string.format("%s  ×%d", string.upper(s.name), have),
					s.desc .. " One use per wave.", nil,
					"🪙 " .. s.price, if gold >= s.price and have < DefenseConfig.SupportStack then GREEN else nil,
					function()
						hooks.send("buy", "support", s.id)
					end)
			end
		elseif kind == "hospital" then
			if #data.hospital == 0 then
				shopRow(1, "✚", RED, "NOBODY HERE", "Crewmates that fall in battle come here. Revive them for 15 minutes of their earnings.")
			end
			for i, h in data.hospital do
				local def = Config.GetUnit(h.unitId)
				local mutation = Config.GetMutation(h.mutationId)
				local name = (if mutation then mutation.name .. " " else "") .. (if def then def.name else h.unitId)
				shopRow(i, "🤕", RED, string.upper(name), "Fell in battle. Pay 15 minutes of its earnings to bring it back.", nil,
					"$" .. Config.FormatCash(h.cost), GREEN, function()
						hooks.send("revive", h.slot)
					end, "LET GO", function()
						hooks.send("release", h.slot)
					end)
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

	-- Üstte durum: oyunun üst çubuğunun altında, ortada
	local top = panel(hud, UDim2.fromOffset(if TOUCH then 440 else 470, 86), UDim2.new(0.5, 0, 0, 62), Vector2.new(0.5, 0), Z - 11)
	local planetTitle = label(top, "", 20, WHITE, Z - 10)
	planetTitle.Position = UDim2.fromOffset(14, 6)
	planetTitle.Size = UDim2.new(0.5, 0, 0, 26)
	planetTitle.TextXAlignment = Enum.TextXAlignment.Left
	local chipRow = Instance.new("Frame")
	chipRow.AnchorPoint = Vector2.new(1, 0)
	chipRow.Position = UDim2.new(1, -12, 0, 8)
	chipRow.Size = UDim2.fromOffset(300, 24)
	chipRow.BackgroundTransparency = 1
	chipRow.ZIndex = Z - 10
	chipRow.Parent = top
	local rowLayout = list(chipRow, true, 6)
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local sectorChip, sectorChipText = chip(chipRow, "", BLUE, Z - 9, 96)
	sectorChip.LayoutOrder = 1
	local waveChip, waveChipText = chip(chipRow, "", ORANGE, Z - 9, 86)
	waveChip.LayoutOrder = 2
	local goldChip, goldChipText = chip(chipRow, "", Color3.fromRGB(220, 160, 30), Z - 9, 90)
	goldChip.LayoutOrder = 3
	local hullBack = Instance.new("Frame")
	hullBack.Position = UDim2.fromOffset(14, 42)
	hullBack.Size = UDim2.new(1, -28, 0, 26)
	hullBack.BackgroundColor3 = Color3.fromRGB(14, 14, 22)
	hullBack.ZIndex = Z - 10
	hullBack.Parent = top
	FancyKit.corner(hullBack, 13)
	FancyKit.border(hullBack, OUTLINE, 2)
	local hullFill = Instance.new("Frame")
	hullFill.Size = UDim2.fromScale(1, 1)
	hullFill.BackgroundColor3 = WHITE
	hullFill.ZIndex = Z - 9
	hullFill.Parent = hullBack
	FancyKit.corner(hullFill, 13)
	local hullGrad = FancyKit.gradient(hullFill, { Color3.fromRGB(120, 230, 255), Color3.fromRGB(40, 140, 230) }, 90)
	local hullText = label(hullBack, "", 14, WHITE, Z - 8, 1.4)
	hullText.Size = UDim2.fromScale(1, 1)

	-- İpucu şeridi (üst kartın altında)
	local hintBox = panel(hud, UDim2.fromOffset(if TOUCH then 460 else 560, 32), UDim2.new(0.5, 0, 0, 156), Vector2.new(0.5, 0), Z - 11,
		Color3.fromRGB(30, 36, 58), Color3.fromRGB(20, 24, 40), 16)
	local hint = label(hintBox, "", 15, WHITE, Z - 10, 1.3)
	hint.Size = UDim2.new(1, -16, 1, 0)
	hint.Position = UDim2.fromOffset(8, 0)
	hint.TextTruncate = Enum.TextTruncate.AtEnd

	-- Sağda: gelen dalga (sıralamanın altında) ve hız
	local incoming = if TOUCH
		then panel(hud, UDim2.fromOffset(210, 150), UDim2.fromOffset(12, 72), Vector2.zero, Z - 11,
			Color3.fromRGB(78, 38, 46), Color3.fromRGB(36, 18, 26))
		else panel(hud, UDim2.fromOffset(230, 180), UDim2.new(1, -12, 0.36, 0), Vector2.new(1, 0), Z - 11,
			Color3.fromRGB(78, 38, 46), Color3.fromRGB(36, 18, 26))
	local incTitle = label(incoming, "NEXT WAVE", 18, Color3.fromRGB(255, 180, 70), Z - 10)
	incTitle.Position = UDim2.fromOffset(0, 8)
	incTitle.Size = UDim2.new(1, 0, 0, 22)
	local incPattern = label(incoming, "", 15, WHITE, Z - 10, 1.3)
	incPattern.Position = UDim2.fromOffset(0, 30)
	incPattern.Size = UDim2.new(1, 0, 0, 18)
	local incList = Instance.new("Frame")
	incList.Position = UDim2.fromOffset(12, 54)
	incList.Size = UDim2.new(1, -24, 1, -60)
	incList.BackgroundTransparency = 1
	incList.ZIndex = Z - 10
	incList.Parent = incoming
	list(incList, false, 2)
	-- Hız: alttaki düğme sırasının sağında (hazırlıkta da savaşta da aynı yer)
	local speedB = button(hud, "▶ 1x", UDim2.fromOffset(104, 54), GREY, Z - 10, 20)
	speedB.holder.AnchorPoint = Vector2.new(0, 1)
	speedB.holder.Position = UDim2.new(0.5, 246, 1, -104)
	speedB.button.Activated:Connect(function()
		hooks.send("speed")
	end)

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

	-- Savaşta destekler (aynı yerde)
	local supportBar = Instance.new("Frame")
	supportBar.AnchorPoint = Vector2.new(0.5, 1)
	supportBar.Position = UDim2.new(0.5, 0, 1, -100)
	supportBar.Size = UDim2.fromOffset(3 * 156, 58)
	supportBar.BackgroundTransparency = 1
	supportBar.ZIndex = Z - 11
	supportBar.Parent = hud
	local supportButtons: { [string]: FancyKit.Button } = {}
	for i, s in DefenseConfig.Supports do
		local b = button(supportBar, "", UDim2.fromOffset(148, 54), PURPLE, Z - 10, 15)
		b.holder.Position = UDim2.fromOffset((i - 1) * 156, 0)
		b.button.Activated:Connect(function()
			hooks.pickSupport(if picked.support == s.id then nil else s.id)
		end)
		supportButtons[s.id] = b
	end

	-- Sonuç bandı: üstten kayarak
	local banner = panel(screen, UDim2.fromOffset(520, 110), UDim2.new(0.5, 0, 0, -140), Vector2.new(0.5, 0), Z + 20)
	banner.Visible = false
	local bannerStrip = Instance.new("Frame")
	bannerStrip.Size = UDim2.new(1, 0, 0, 8)
	bannerStrip.BackgroundColor3 = GOLD
	bannerStrip.BorderSizePixel = 0
	bannerStrip.ZIndex = Z + 21
	bannerStrip.Parent = banner
	FancyKit.corner(bannerStrip, 4)
	local bannerTitle = label(banner, "", 32, WHITE, Z + 21)
	bannerTitle.Position = UDim2.fromOffset(0, 14)
	bannerTitle.Size = UDim2.new(1, 0, 0, 40)
	local bannerSub = label(banner, "", 18, GOLD, Z + 21)
	bannerSub.Position = UDim2.fromOffset(12, 58)
	bannerSub.Size = UDim2.new(1, -24, 0, 42)
	bannerSub.TextWrapped = true
	local bannerToken = 0

	local function renderSupports()
		for _, s in DefenseConfig.Supports do
			local b = supportButtons[s.id]
			local have = if data then (data.supports[s.id] or 0) else 0
			local active = picked.support == s.id
			b.set(string.format("%s %s ×%d", s.icon, if active then "TAP GROUND" else string.upper(s.name), have),
				if have > 0 then (if active then GOLD else PURPLE) else nil)
		end
	end

	local function setHull(hull: number, maxHull: number, enemies: number?)
		local frac = math.clamp(hull / math.max(1, maxHull), 0, 1)
		hullFill.Size = UDim2.fromScale(frac, 1)
		local low = frac < 0.35
		hullGrad.Color = if low then ColorSequence.new(Color3.fromRGB(255, 140, 120), Color3.fromRGB(220, 50, 50))
			else ColorSequence.new(Color3.fromRGB(120, 230, 255), Color3.fromRGB(40, 140, 230))
		hullText.Text = string.format("🛡 SHIP HULL  %d / %d%s", hull, maxHull,
			if enemies then string.format("     👾 %d", enemies) else "")
	end

	local function renderIncoming()
		for _, c in incList:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		if not run then
			return
		end
		incPattern.Text = "Route: " .. run.plan.name
		incTitle.Text = if mode == "fight" then "⚔ FIGHTING" else "NEXT WAVE"
		local order = 0
		for _, id in { "Grub", "Skitter", "Spitter", "Brute", "Boss" } do
			local n = run.plan.counts[id]
			local def = DefenseConfig.Enemies[id]
			if n and def then
				order += 1
				local line = label(incList, string.format("%s  × %d", def.name, n), 15,
					if id == "Boss" then Color3.fromRGB(255, 110, 110) else WHITE, Z - 9, 1.2)
				line.LayoutOrder = order
				line.Size = UDim2.new(1, 0, 0, 20)
				line.TextXAlignment = Enum.TextXAlignment.Left
			end
		end
		if run.plan.boss then
			local warn = label(incList, "⚠ BOSS WAVE", 16, Color3.fromRGB(255, 90, 90), Z - 9)
			warn.LayoutOrder = 99
			warn.Size = UDim2.new(1, 0, 0, 22)
		end
	end

	local function renderHud()
		local gold = if data then data.gold else 0
		goldChipText.Text = "🪙 " .. tostring(gold)
		planetTitle.Text = "🪐 " .. planetName(currentPlanet)
		mode = if run == nil then "idle" elseif run.phase == "fight" then "fight" else "prep"
		if run then
			sectorChipText.Text = "SECTOR " .. run.sector
			waveChipText.Text = string.format("WAVE %d/%d", run.waveInSector, DefenseConfig.WavesPerSector)
			sectorChip.Visible = true
			waveChip.Visible = true
			setHull(run.hull, run.maxHull, nil)
			local fast = (run.speed or 1) >= 2
			speedB.set(if fast then "⏩ 2x" else "▶ 1x", if fast then ORANGE else GREY)
		else
			sectorChip.Visible = false
			waveChip.Visible = false
			local hull = if data then data.hull else DefenseConfig.BaseHull
			setHull(hull, hull, nil)
		end
		incoming.Visible = run ~= nil
		speedB.holder.Visible = run ~= nil
		bottom.Visible = mode ~= "fight"
		supportBar.Visible = mode == "fight"
		if mode == "idle" then
			mainB.set("⚔ DEFEND", GREEN)
			sideB.set("🚀 TAKE OFF", BLUE)
			hint.Text = "Press ⚔ DEFEND to pick your crew and gear"
		elseif mode == "prep" then
			mainB.set("▶ START WAVE", if #run.units > 0 then GREEN else nil)
			sideB.set("↩ RETREAT", RED)
			hint.Text = if (run.carried or 0) > 0
				then (if TOUCH then "Pick a crewmate from your bar, walk onto the field and TAP to drop it"
					else "Pick a crewmate from your bar, walk onto the field and CLICK to drop it")
				else "Your crew is ready. Press ▶ START WAVE!"
		else
			hint.Text = if run.gear == "Lightsaber" then "Defend the ship! Equip your Lightsaber and slash enemies"
				elseif run.gear == "RayGun" then "Defend the ship! Equip your Ray Gun and aim at enemies"
				elseif (run.carried or 0) > 0 then "Defend the ship! You can still drop crewmates from your bar"
				else "Defend the ship!"
		end
		renderIncoming()
		renderSupports()
	end

	-- ═══ Dışa açık ══════════════════════════════════════════════════════════
	ui = {} :: any

	function ui.OpenPrepare()
		if run then
			return
		end
		table.clear(chosen)
		chosenSector = maxSector()
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
			{ Position = UDim2.new(0.5, 0, 0, 200) }):Play()
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
