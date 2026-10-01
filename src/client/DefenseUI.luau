--!strict
--[[
	Gezegen savunmasının 2B arayüzü (DefenseClient kuruyor ve besliyor).

	  Pilot penceresi  — gezegen listesi: en iyi bölüm, yıldızlar, kilit, LAND
	  Komuta ekranı    — taktik görünümde: üstte gezegen/bölüm/dalga/gövde/altın;
	                     koşu yoksa bölüm seçimi; hazırlıkta alttaki ekip şeridi,
	                     gelen dalga kartı, START / RETREAT; savaşta destekler
	  Dükkânlar        — Armory (rol seviyesi), Command Shop (slot, gövde),
	                     Market (destekler), Hospital (revive / let go)
	  Sonuç bantları   — dalga / bölüm / yenilgi

	Mantık sunucuda; buradan yalnızca hooks.send(...) ile istek gidiyor.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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
local GREY = Color3.fromRGB(120, 128, 146)
local Z = 50

export type Hooks = {
	send: (...any) -> (),
	pickCrew: (slot: number?) -> (),
	pickSupport: (id: string?) -> (),
	moveSelected: () -> (),
	recallSelected: () -> (),
	deselect: () -> (),
	exitView: () -> (),
	openCommand: () -> (),
	takeoff: () -> (),
}

export type UI = {
	OpenPilot: () -> (),
	OpenShop: (kind: string) -> (),
	CloseAll: () -> (),
	SetData: (data: any) -> (),
	SetRun: (run: any?, planet: number?) -> (),
	SetCommand: (visible: boolean) -> (),
	SetSelected: (info: any?) -> (),
	SetPicked: (slot: number?, support: string?) -> (),
	SetTick: (snap: any) -> (),
	Banner: (title: string, sub: string, color: Color3) -> (),
	Hint: (text: string?) -> (),
	SetPlanetHud: (visible: boolean) -> (),
}

-- ─── Küçük yardımcılar ──────────────────────────────────────────────────────

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
	local s = Instance.new("UIStroke")
	s.Color = OUTLINE
	s.Thickness = stroke or math.max(1.5, size / 9)
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = l
	return l
end

local function panel(parent: Instance, size: UDim2, pos: UDim2, anchor: Vector2, z: number, top: Color3?, bottom: Color3?): Frame
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = pos
	f.AnchorPoint = anchor
	f.BackgroundColor3 = WHITE
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	FancyKit.corner(f, 14)
	FancyKit.border(f, OUTLINE, 3)
	FancyKit.gradient(f, { top or Color3.fromRGB(40, 46, 70), bottom or Color3.fromRGB(22, 24, 40) }, 90)
	return f
end

local function button(parent: Instance, text: string, size: UDim2, color: Color3, z: number, textSize: number?): FancyKit.Button
	local b = FancyKit.button(parent, size, color, textSize or 20, z)
	b.set(text, color)
	return b
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

-- ─── Kurulum ────────────────────────────────────────────────────────────────

function DefenseUI.Create(screen: ScreenGui, hooks: Hooks): UI
	local data: any = nil
	local run: any = nil
	local currentPlanet = 1
	local chosenSector = 1
	local openShop: string? = nil
	local picked: { slot: number?, support: string? } = { slot = nil, support = nil }

	-- ═══ Pencere iskeleti ═══════════════════════════════════════════════════
	local function window(name: string, title: string, colors: { Color3 }, w: number, h: number): (Frame, Frame)
		local root = UiKit.Window(screen, name, colors[1])
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = UDim2.fromScale(0.5, 0.5)
		root.Size = UDim2.fromOffset(w, h)
		root.Visible = false
		root.ZIndex = Z
		local driver = FancyKit.driver(root)
		local shell = FancyKit.shell(root, title, colors, 62, Z, driver, 40)
		shell.close.Activated:Connect(function()
			root.Visible = false
		end)
		local body = Instance.new("Frame")
		body.Position = UDim2.fromOffset(14, 72)
		body.Size = UDim2.new(1, -28, 1, -86)
		body.BackgroundTransparency = 1
		body.ZIndex = Z + 2
		body.Parent = root
		return root, body
	end

	-- ═══ Pilot penceresi ════════════════════════════════════════════════════
	local pilotRoot, pilotBody = window("DefensePilot", "PLANETS", {
		Color3.fromRGB(60, 120, 255), Color3.fromRGB(150, 80, 255), Color3.fromRGB(40, 200, 220),
	}, 760, 470)
	local pilotHint = label(pilotBody, "Land on a planet and defend it with your crew. Clear sectors for ★ and gold.",
		15, Color3.fromRGB(210, 220, 255), Z + 3)
	pilotHint.Size = UDim2.new(1, 0, 0, 20)
	local pilotList = Instance.new("ScrollingFrame")
	pilotList.Position = UDim2.fromOffset(0, 26)
	pilotList.Size = UDim2.new(1, 0, 1, -26)
	pilotList.BackgroundTransparency = 1
	pilotList.BorderSizePixel = 0
	pilotList.ScrollBarThickness = 6
	pilotList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	pilotList.CanvasSize = UDim2.new()
	pilotList.ZIndex = Z + 3
	pilotList.Parent = pilotBody
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(170, 176)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = pilotList

	local function renderPilot()
		for _, c in pilotList:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		for i, def in Config.SpaceMonsters do
			local info = data and data.planets and data.planets[i]
			local unlocked = info and info.unlocked
			local card = panel(pilotList, UDim2.fromOffset(170, 176), UDim2.new(), Vector2.zero, Z + 4,
				def.planetColor:Lerp(Color3.new(0, 0, 0), 0.35), def.planetColor2:Lerp(Color3.new(0, 0, 0), 0.6))
			card.LayoutOrder = i
			local disc = Instance.new("Frame")
			disc.AnchorPoint = Vector2.new(0.5, 0)
			disc.Position = UDim2.new(0.5, 0, 0, 10)
			disc.Size = UDim2.fromOffset(58, 58)
			disc.BackgroundColor3 = WHITE
			disc.ZIndex = Z + 5
			disc.Parent = card
			FancyKit.corner(disc, 29)
			FancyKit.border(disc, OUTLINE, 3)
			FancyKit.gradient(disc, { def.planetColor:Lerp(WHITE, 0.2), def.planetColor2 }, 45)
			local name = label(card, string.upper(def.planet), 18, WHITE, Z + 5)
			name.Position = UDim2.fromOffset(0, 72)
			name.Size = UDim2.new(1, 0, 0, 22)
			local total = 0
			if info and info.stars then
				for _, n in info.stars do
					total += n
				end
			end
			local best = label(card, if info and info.best > 0
				then string.format("Sector %d  ★%d", info.best, total) else "New planet",
				14, GOLD, Z + 5)
			best.Position = UDim2.fromOffset(0, 96)
			best.Size = UDim2.new(1, 0, 0, 18)
			if unlocked then
				local land = button(card, "LAND", UDim2.new(1, -24, 0, 44), GREEN, Z + 5, 20)
				land.holder.Position = UDim2.new(0, 12, 1, -54)
				land.button.Activated:Connect(function()
					pilotRoot.Visible = false
					hooks.send("land", i)
				end)
			else
				local why = label(card, "🔒 " .. tostring(info and info.why or "Locked"), 12, Color3.fromRGB(255, 170, 170), Z + 5, 1.4)
				why.Position = UDim2.new(0, 8, 1, -58)
				why.Size = UDim2.new(1, -16, 0, 48)
				why.TextWrapped = true
			end
		end
	end

	-- ═══ Dükkân penceresi (dört dükkân aynı pencerede) ═════════════════════
	local shopRoot, shopBody = window("DefenseShop", "SHOP", {
		Color3.fromRGB(255, 150, 40), Color3.fromRGB(255, 80, 120), Color3.fromRGB(255, 200, 60),
	}, 700, 460)
	local shopGold = label(shopRoot, "", 22, GOLD, Z + 6)
	shopGold.AnchorPoint = Vector2.new(1, 0.5)
	shopGold.Position = UDim2.new(1, -70, 0, 31)
	shopGold.Size = UDim2.fromOffset(200, 30)
	shopGold.TextXAlignment = Enum.TextXAlignment.Right
	local shopList = Instance.new("ScrollingFrame")
	shopList.Size = UDim2.fromScale(1, 1)
	shopList.BackgroundTransparency = 1
	shopList.BorderSizePixel = 0
	shopList.ScrollBarThickness = 6
	shopList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	shopList.CanvasSize = UDim2.new()
	shopList.ZIndex = Z + 3
	shopList.Parent = shopBody
	local shopLayout = Instance.new("UIListLayout")
	shopLayout.Padding = UDim.new(0, 8)
	shopLayout.SortOrder = Enum.SortOrder.LayoutOrder
	shopLayout.Parent = shopList

	local SHOP_TITLE = { armory = "ARMORY", shop = "COMMAND SHOP", market = "MARKET", hospital = "HOSPITAL" }

	local function shopRow(order: number, icon: string, title: string, sub: string, actionText: string?, color: Color3?,
		onClick: (() -> ())?, secondText: string?, onSecond: (() -> ())?)
		local row = panel(shopList, UDim2.new(1, -10, 0, 78), UDim2.new(), Vector2.zero, Z + 4)
		row.LayoutOrder = order
		local ic = label(row, icon, 36, WHITE, Z + 5, 0)
		ic.Position = UDim2.fromOffset(10, 0)
		ic.Size = UDim2.fromOffset(56, 78)
		local t = label(row, title, 21, WHITE, Z + 5)
		t.Position = UDim2.fromOffset(72, 10)
		t.Size = UDim2.new(1, -330, 0, 26)
		t.TextXAlignment = Enum.TextXAlignment.Left
		local s = label(row, sub, 14, Color3.fromRGB(200, 210, 240), Z + 5, 1.3)
		s.Position = UDim2.fromOffset(72, 38)
		s.Size = UDim2.new(1, -330, 0, 32)
		s.TextXAlignment = Enum.TextXAlignment.Left
		s.TextWrapped = true
		if actionText then
			local b = button(row, actionText, UDim2.fromOffset(150, 52), color or GREY, Z + 5, 18)
			b.holder.AnchorPoint = Vector2.new(1, 0.5)
			b.holder.Position = UDim2.new(1, if secondText then -176 else -12, 0.5, 0)
			if onClick then
				b.button.Activated:Connect(onClick)
			end
		end
		if secondText then
			local b2 = button(row, secondText, UDim2.fromOffset(150, 52), RED, Z + 5, 16)
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
		shopGold.Text = "🪙 " .. tostring(gold)
		local header = shopRoot:FindFirstChild("Header")
		if header then
			for _, d in header:GetDescendants() do
				if d:IsA("TextLabel") and (d.Text == "SHOP" or d.Text == "ARMORY" or d.Text == "COMMAND SHOP"
					or d.Text == "MARKET" or d.Text == "HOSPITAL") then
					d.Text = SHOP_TITLE[kind] or "SHOP"
				end
			end
		end
		if not data then
			return
		end
		if kind == "armory" then
			local S = DefenseConfig.Saber
			local level = data.saber or 0
			local saberCost = if level == 0 then S.price else S.upgradeCosts[level]
			shopRow(0, "⚔", if level == 0 then "LIGHTSABER" else string.format("LIGHTSABER  Lv %d/%d", level, #S.upgradeCosts + 1),
				if level == 0 then "Fight with your crew! During a wave press EXIT VIEW and slash enemies yourself."
					else "Hits every enemy in front of you. Higher level = more damage.",
				if saberCost then "🪙 " .. saberCost else "MAX", if saberCost and gold >= saberCost then GREEN else GREY,
				function()
					hooks.send("buy", "saber")
				end)
			for i, id in DefenseConfig.RoleOrder do
				local role = DefenseConfig.Roles[id]
				local level = data.roles[id] or 0
				local cost = DefenseConfig.RoleUpgradeCost(level)
				local bonus = math.floor(DefenseConfig.RoleLevelBonus * level * 100 + 0.5)
				shopRow(i, role.icon, string.format("%s  Lv %d/%d", string.upper(role.name), level, DefenseConfig.RoleMaxLevel),
					string.format("%s  (+%d%% health & power)", role.desc, bonus),
					if cost then "🪙 " .. cost else "MAX", if cost and gold >= cost then GREEN else GREY,
					function()
						hooks.send("buy", "role", id)
					end)
			end
		elseif kind == "shop" then
			local slotCost = DefenseConfig.SlotCosts[data.slotLevel + 1]
			shopRow(1, "👥", string.format("CREW SLOTS  %d", data.slots),
				"How many crewmates you can put on the field at once.",
				if slotCost then "🪙 " .. slotCost else "MAX", if slotCost and gold >= slotCost then GREEN else GREY,
				function()
					hooks.send("buy", "slot")
				end)
			local hullCost = DefenseConfig.HullCosts[data.hullLevel + 1]
			shopRow(2, "🛡", string.format("SHIP HULL  %d", data.hull),
				"Enemies that reach the ship damage the hull. At 0 the wave is lost.",
				if hullCost then "🪙 " .. hullCost else "MAX", if hullCost and gold >= hullCost then GREEN else GREY,
				function()
					hooks.send("buy", "hull")
				end)
		elseif kind == "market" then
			for i, s in DefenseConfig.Supports do
				local have = data.supports[s.id] or 0
				shopRow(i, s.icon, string.format("%s  ×%d", string.upper(s.name), have),
					s.desc .. " One use per wave.",
					"🪙 " .. s.price, if gold >= s.price and have < DefenseConfig.SupportStack then GREEN else GREY,
					function()
						hooks.send("buy", "support", s.id)
					end)
			end
		elseif kind == "hospital" then
			if #data.hospital == 0 then
				shopRow(1, "✚", "NOBODY HERE", "Crewmates that fall in battle come here. Revive them for 15 minutes of their earnings.")
			end
			for i, h in data.hospital do
				local def = Config.GetUnit(h.unitId)
				local mutation = Config.GetMutation(h.mutationId)
				local name = (if mutation then mutation.name .. " " else "") .. (if def then def.name else h.unitId)
				shopRow(i, "🤕", string.upper(name), "Fell in battle. Pay 15 minutes of its earnings to bring it back.",
					"$" .. Config.FormatCash(h.cost), GREEN, function()
						hooks.send("revive", h.slot)
					end, "LET GO", function()
						hooks.send("release", h.slot)
					end)
			end
		end
	end

	-- ═══ Komuta ekranı ══════════════════════════════════════════════════════
	local hud = Instance.new("Frame")
	hud.Name = "DefenseHud"
	hud.Size = UDim2.fromScale(1, 1)
	hud.BackgroundTransparency = 1
	hud.Visible = false
	hud.ZIndex = Z - 10
	hud.Parent = screen

	-- Üst şerit
	local top = panel(hud, UDim2.fromOffset(560, 74), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0), Z - 9)
	local topTitle = label(top, "", 22, WHITE, Z - 8)
	topTitle.Position = UDim2.fromOffset(14, 6)
	topTitle.Size = UDim2.new(1, -150, 0, 28)
	topTitle.TextXAlignment = Enum.TextXAlignment.Left
	local topGold = label(top, "", 22, GOLD, Z - 8)
	topGold.AnchorPoint = Vector2.new(1, 0)
	topGold.Position = UDim2.new(1, -14, 0, 6)
	topGold.Size = UDim2.fromOffset(130, 28)
	topGold.TextXAlignment = Enum.TextXAlignment.Right
	local hullBack = Instance.new("Frame")
	hullBack.Position = UDim2.fromOffset(14, 42)
	hullBack.Size = UDim2.new(1, -28, 0, 20)
	hullBack.BackgroundColor3 = Color3.fromRGB(16, 16, 24)
	hullBack.ZIndex = Z - 8
	hullBack.Parent = top
	FancyKit.corner(hullBack, 10)
	local hullFill = Instance.new("Frame")
	hullFill.Size = UDim2.fromScale(1, 1)
	hullFill.BackgroundColor3 = WHITE
	hullFill.ZIndex = Z - 7
	hullFill.Parent = hullBack
	FancyKit.corner(hullFill, 10)
	FancyKit.gradient(hullFill, { Color3.fromRGB(120, 230, 255), Color3.fromRGB(40, 140, 230) }, 90)
	local hullText = label(hullBack, "", 14, WHITE, Z - 6, 1.4)
	hullText.Size = UDim2.fromScale(1, 1)

	-- Bölüm seçimi (koşu yokken)
	local start = panel(hud, UDim2.fromOffset(420, 250), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5), Z - 9)
	local startTitle = label(start, "CHOOSE SECTOR", 26, GOLD, Z - 8)
	startTitle.Position = UDim2.fromOffset(0, 10)
	startTitle.Size = UDim2.new(1, 0, 0, 32)
	local sectorText = label(start, "", 40, WHITE, Z - 8)
	sectorText.Position = UDim2.fromOffset(70, 48)
	sectorText.Size = UDim2.new(1, -140, 0, 46)
	local sectorSub = label(start, "", 16, Color3.fromRGB(200, 210, 240), Z - 8, 1.4)
	sectorSub.Position = UDim2.fromOffset(20, 96)
	sectorSub.Size = UDim2.new(1, -40, 0, 40)
	sectorSub.TextWrapped = true
	local prev = button(start, "◀", UDim2.fromOffset(52, 52), BLUE, Z - 8, 24)
	prev.holder.Position = UDim2.fromOffset(14, 48)
	local nextB = button(start, "▶", UDim2.fromOffset(52, 52), BLUE, Z - 8, 24)
	nextB.holder.AnchorPoint = Vector2.new(1, 0)
	nextB.holder.Position = UDim2.new(1, -14, 0, 48)
	local beginB = button(start, "BEGIN", UDim2.fromOffset(180, 58), GREEN, Z - 8, 24)
	beginB.holder.Position = UDim2.new(0.5, 6, 1, -74)
	local leaveB = button(start, "EXIT", UDim2.fromOffset(140, 58), GREY, Z - 8, 20)
	leaveB.holder.AnchorPoint = Vector2.new(1, 0)
	leaveB.holder.Position = UDim2.new(0.5, -6, 1, -74)

	local function maxSector(): number
		local p = data and data.planets and data.planets[currentPlanet]
		return (if p then p.best else 0) + 1
	end

	local function renderStart()
		local maxS = maxSector()
		chosenSector = math.clamp(chosenSector, 1, maxS)
		sectorText.Text = "SECTOR " .. chosenSector
		local per = DefenseConfig.WavesPerSector
		local got = sectorStars(data, currentPlanet, chosenSector)
		sectorSub.Text = string.format("Waves %d-%d   %s   %s", (chosenSector - 1) * per + 1, chosenSector * per,
			stars(got), if chosenSector == maxS then "NEW!" else "")
		prev.set("◀", if chosenSector > 1 then BLUE else nil)
		nextB.set("▶", if chosenSector < maxS then BLUE else nil)
	end
	prev.button.Activated:Connect(function()
		chosenSector = math.max(1, chosenSector - 1)
		renderStart()
	end)
	nextB.button.Activated:Connect(function()
		chosenSector = math.min(maxSector(), chosenSector + 1)
		renderStart()
	end)
	beginB.button.Activated:Connect(function()
		hooks.send("begin", chosenSector)
	end)
	leaveB.button.Activated:Connect(function()
		hooks.exitView()
	end)

	-- Nasıl oynanır (bölüm seçimi açıkken, solda)
	local howTo = panel(hud, UDim2.fromOffset(330, 250), UDim2.new(0.5, -230, 0.5, 0), Vector2.new(1, 0.5), Z - 9,
		Color3.fromRGB(30, 60, 50), Color3.fromRGB(18, 30, 28))
	local howTitle = label(howTo, "HOW TO DEFEND", 22, Color3.fromRGB(120, 255, 160), Z - 8)
	howTitle.Position = UDim2.fromOffset(0, 8)
	howTitle.Size = UDim2.new(1, 0, 0, 26)
	local howBody = label(howTo, table.concat({
		"1. Pick a sector and press BEGIN",
		"2. Tap a crewmate card below, then tap the field to place it near the orange arrows",
		"3. Press START WAVE: your crew fights on its own",
		"4. Got a Lightsaber? Press EXIT VIEW in a wave and slash enemies yourself",
		"5. 5 waves = 1 sector: ★ and gold. Fallen crew go to the Hospital",
	}, "\n"), 14, WHITE, Z - 8, 1.3)
	howBody.Position = UDim2.fromOffset(14, 38)
	howBody.Size = UDim2.new(1, -28, 1, -46)
	howBody.TextWrapped = true
	howBody.TextXAlignment = Enum.TextXAlignment.Left
	howBody.TextYAlignment = Enum.TextYAlignment.Top

	-- Gelen dalga kartı (sağda)
	local incoming = panel(hud, UDim2.fromOffset(230, 210), UDim2.new(1, -12, 0, 96), Vector2.new(1, 0), Z - 9,
		Color3.fromRGB(70, 34, 40), Color3.fromRGB(34, 18, 26))
	local incTitle = label(incoming, "INCOMING", 20, Color3.fromRGB(255, 170, 60), Z - 8)
	incTitle.Position = UDim2.fromOffset(0, 8)
	incTitle.Size = UDim2.new(1, 0, 0, 24)
	local incBody = label(incoming, "", 16, WHITE, Z - 8, 1.4)
	incBody.Position = UDim2.fromOffset(12, 36)
	incBody.Size = UDim2.new(1, -24, 1, -44)
	incBody.TextWrapped = true
	incBody.TextYAlignment = Enum.TextYAlignment.Top
	incBody.TextXAlignment = Enum.TextXAlignment.Left
	incBody.RichText = true

	-- Ekip şeridi (altta)
	local crewBar = panel(hud, UDim2.new(1, -380, 0, 132), UDim2.new(0, 12, 1, -12), Vector2.new(0, 1), Z - 9)
	local crewTitle = label(crewBar, "", 17, WHITE, Z - 8)
	crewTitle.Position = UDim2.fromOffset(12, 4)
	crewTitle.Size = UDim2.new(1, -24, 0, 22)
	crewTitle.TextXAlignment = Enum.TextXAlignment.Left
	local crewList = Instance.new("ScrollingFrame")
	crewList.Position = UDim2.fromOffset(8, 28)
	crewList.Size = UDim2.new(1, -16, 1, -34)
	crewList.BackgroundTransparency = 1
	crewList.BorderSizePixel = 0
	crewList.ScrollBarThickness = 5
	crewList.ScrollingDirection = Enum.ScrollingDirection.X
	crewList.AutomaticCanvasSize = Enum.AutomaticSize.X
	crewList.CanvasSize = UDim2.new()
	crewList.ZIndex = Z - 8
	crewList.Parent = crewBar
	local crewLayout = Instance.new("UIListLayout")
	crewLayout.FillDirection = Enum.FillDirection.Horizontal
	crewLayout.Padding = UDim.new(0, 8)
	crewLayout.SortOrder = Enum.SortOrder.LayoutOrder
	crewLayout.Parent = crewList

	-- Sağ alt: düğmeler
	local actions = Instance.new("Frame")
	actions.AnchorPoint = Vector2.new(1, 1)
	actions.Position = UDim2.new(1, -12, 1, -12)
	actions.Size = UDim2.fromOffset(350, 132)
	actions.BackgroundTransparency = 1
	actions.ZIndex = Z - 9
	actions.Parent = hud
	local goB = button(actions, "START WAVE ▶", UDim2.fromOffset(350, 64), GREEN, Z - 8, 24)
	local retreatB = button(actions, "RETREAT", UDim2.fromOffset(170, 56), RED, Z - 8, 18)
	retreatB.holder.Position = UDim2.fromOffset(0, 72)
	local exitB = button(actions, "EXIT VIEW", UDim2.fromOffset(170, 56), GREY, Z - 8, 18)
	exitB.holder.Position = UDim2.fromOffset(180, 72)
	goB.button.Activated:Connect(function()
		hooks.send("go")
	end)
	retreatB.button.Activated:Connect(function()
		hooks.send("retreat")
	end)
	exitB.button.Activated:Connect(function()
		hooks.exitView()
	end)

	-- Savaşta: destek düğmeleri
	local supportBar = Instance.new("Frame")
	supportBar.AnchorPoint = Vector2.new(0.5, 1)
	supportBar.Position = UDim2.new(0.5, 0, 1, -12)
	supportBar.Size = UDim2.fromOffset(3 * 150 + 20, 70)
	supportBar.BackgroundTransparency = 1
	supportBar.ZIndex = Z - 9
	supportBar.Parent = hud
	local supportButtons: { [string]: FancyKit.Button } = {}
	for i, s in DefenseConfig.Supports do
		local b = button(supportBar, "", UDim2.fromOffset(140, 64), Color3.fromRGB(150, 90, 255), Z - 8, 17)
		b.holder.Position = UDim2.fromOffset((i - 1) * 160, 0)
		b.button.Activated:Connect(function()
			hooks.pickSupport(if picked.support == s.id then nil else s.id)
		end)
		supportButtons[s.id] = b
	end

	-- Seçili crewmate şeridi
	local selBar = panel(hud, UDim2.fromOffset(470, 58), UDim2.new(0.5, 0, 1, -152), Vector2.new(0.5, 1), Z - 9)
	selBar.Visible = false
	local selText = label(selBar, "", 17, WHITE, Z - 8)
	selText.Position = UDim2.fromOffset(12, 0)
	selText.Size = UDim2.new(1, -250, 1, 0)
	selText.TextXAlignment = Enum.TextXAlignment.Left
	selText.TextTruncate = Enum.TextTruncate.AtEnd
	local moveB = button(selBar, "MOVE", UDim2.fromOffset(100, 44), BLUE, Z - 8, 16)
	moveB.holder.AnchorPoint = Vector2.new(1, 0.5)
	moveB.holder.Position = UDim2.new(1, -124, 0.5, 2)
	local recallB = button(selBar, "RECALL", UDim2.fromOffset(104, 44), RED, Z - 8, 16)
	recallB.holder.AnchorPoint = Vector2.new(1, 0.5)
	recallB.holder.Position = UDim2.new(1, -12, 0.5, 2)
	moveB.button.Activated:Connect(function()
		hooks.moveSelected()
	end)
	recallB.button.Activated:Connect(function()
		hooks.recallSelected()
	end)

	-- İpucu satırı
	local hint = label(hud, "", 17, WHITE, Z - 8)
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 88)
	hint.Size = UDim2.fromOffset(700, 24)

	-- Sonuç bandı
	local banner = panel(hud, UDim2.fromOffset(520, 120), UDim2.fromScale(0.5, 0.36), Vector2.new(0.5, 0.5), Z + 20)
	banner.Visible = false
	local bannerTitle = label(banner, "", 34, WHITE, Z + 21)
	bannerTitle.Position = UDim2.fromOffset(0, 12)
	bannerTitle.Size = UDim2.new(1, 0, 0, 44)
	local bannerSub = label(banner, "", 19, GOLD, Z + 21)
	bannerSub.Position = UDim2.fromOffset(10, 62)
	bannerSub.Size = UDim2.new(1, -20, 0, 46)
	bannerSub.TextWrapped = true
	local bannerToken = 0

	-- ═══ Gezegende yürürken: DEFEND / TAKE OFF ve koşu durumu ════════════════
	local planetHud = Instance.new("Frame")
	planetHud.Name = "DefensePlanetHud"
	planetHud.AnchorPoint = Vector2.new(0.5, 1)
	planetHud.Position = UDim2.new(0.5, 0, 1, -96)
	planetHud.Size = UDim2.fromOffset(420, 120)
	planetHud.BackgroundTransparency = 1
	planetHud.Visible = false
	planetHud.ZIndex = Z - 12
	planetHud.Parent = screen
	local status = label(planetHud, "", 17, WHITE, Z - 11)
	status.Size = UDim2.new(1, 0, 0, 24)
	local defendB = button(planetHud, "⚔ DEFEND", UDim2.fromOffset(240, 66), GREEN, Z - 11, 28)
	defendB.holder.Position = UDim2.fromOffset(0, 32)
	local offB = button(planetHud, "🚀 TAKE OFF", UDim2.fromOffset(170, 58), BLUE, Z - 11, 18)
	offB.holder.Position = UDim2.fromOffset(250, 36)
	defendB.button.Activated:Connect(function()
		hooks.openCommand()
	end)
	offB.button.Activated:Connect(function()
		hooks.takeoff()
	end)
	-- DEFEND hafifçe nabız atıyor (ilk bakışta fark edilsin)
	task.spawn(function()
		while planetHud.Parent do
			if planetHud.Visible then
				local t = os.clock()
				defendB.holder.Size = UDim2.fromOffset(240 + math.sin(t * 4) * 6, 66 + math.sin(t * 4) * 2)
			end
			task.wait(0.05)
		end
	end)

	local function renderPlanetHud()
		if run then
			local fight = run.phase == "fight"
			status.Text = string.format("SECTOR %d · WAVE %d/%d · HULL %d/%d%s", run.sector, run.waveInSector,
				DefenseConfig.WavesPerSector, run.hull, run.maxHull,
				if fight and data and (data.saber or 0) > 0 then "  ·  SLASH WITH YOUR LIGHTSABER!" elseif fight then "  ·  FIGHTING" else "")
			defendB.set(if fight then "🎯 COMMAND" else "⚔ DEFEND", GREEN)
		else
			status.Text = ""
			defendB.set("⚔ DEFEND", GREEN)
		end
	end

	-- ═══ Çizim ══════════════════════════════════════════════════════════════
	local function deployedSlots(): { [number]: boolean }
		local set = {}
		if run then
			for _, u in run.units do
				set[u.slot] = true
			end
		end
		return set
	end

	local function renderCrew()
		for _, c in crewList:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		if not (data and run) then
			return
		end
		local used = deployedSlots()
		local list = {}
		for _, c in data.crew or {} do
			if not c.away and not used[c.slot] then
				table.insert(list, c)
			end
		end
		table.sort(list, function(a, b)
			return DefenseConfig.GetPower(a.unitId, a.mutationId) > DefenseConfig.GetPower(b.unitId, b.mutationId)
		end)
		crewTitle.Text = string.format("YOUR CREW   %d / %d on the field", #run.units, data.slots)
		if #list == 0 then
			local none = label(crewList, "No crewmates left at your base. Steal more in space!", 15, Color3.fromRGB(200, 210, 240), Z - 7, 1.3)
			none.Size = UDim2.fromOffset(420, 90)
			return
		end
		for i, c in list do
			local def = Config.GetUnit(c.unitId)
			local role = DefenseConfig.GetRole(c.unitId)
			local selected = picked.slot == c.slot
			local card = Instance.new("TextButton")
			card.LayoutOrder = i
			card.Size = UDim2.fromOffset(104, 92)
			card.BackgroundColor3 = WHITE
			card.AutoButtonColor = false
			card.Text = ""
			card.ZIndex = Z - 7
			card.Parent = crewList
			FancyKit.corner(card, 10)
			FancyKit.border(card, if selected then GOLD else OUTLINE, if selected then 4 else 2.5)
			local rarity = def and Config.Rarities[def.rarity]
			local tint = if rarity then rarity.color else GREY
			FancyKit.gradient(card, { tint:Lerp(WHITE, 0.15), tint:Lerp(Color3.new(0, 0, 0), 0.45) }, 90)
			local iconHolder = Instance.new("Frame")
			iconHolder.Size = UDim2.fromOffset(52, 52)
			iconHolder.Position = UDim2.fromOffset(26, 2)
			iconHolder.BackgroundTransparency = 1
			iconHolder.ZIndex = Z - 6
			iconHolder.Parent = card
			pcall(UiKit.UnitIcon, iconHolder, 52, c.unitId)
			local badge = label(card, role.icon, 16, WHITE, Z - 5, 0)
			badge.Position = UDim2.fromOffset(4, 2)
			badge.Size = UDim2.fromOffset(22, 22)
			local name = label(card, if def then def.name else c.unitId, 12, WHITE, Z - 5, 1.3)
			name.Position = UDim2.fromOffset(3, 54)
			name.Size = UDim2.new(1, -6, 0, 16)
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local pw = label(card, string.format("%s · %.2f", role.name, DefenseConfig.GetPower(c.unitId, c.mutationId)), 11, GOLD, Z - 5, 1.2)
			pw.Position = UDim2.fromOffset(3, 72)
			pw.Size = UDim2.new(1, -6, 0, 14)
			card.Activated:Connect(function()
				hooks.pickCrew(if picked.slot == c.slot then nil else c.slot)
			end)
		end
	end

	local function renderSupports()
		for _, s in DefenseConfig.Supports do
			local b = supportButtons[s.id]
			local have = if data then (data.supports[s.id] or 0) else 0
			local active = picked.support == s.id
			b.set(string.format("%s %s ×%d", s.icon, if active then "AIM" else string.upper(s.name), have),
				if have > 0 then (if active then GOLD else Color3.fromRGB(150, 90, 255)) else nil)
		end
	end

	local function renderHud()
		local planetLabel = planetName(currentPlanet)
		local gold = if data then data.gold else 0
		topGold.Text = "🪙 " .. tostring(gold)
		if run then
			topTitle.Text = string.format("%s · SECTOR %d · WAVE %d/%d", planetLabel, run.sector, run.waveInSector,
				DefenseConfig.WavesPerSector)
			hullFill.Size = UDim2.fromScale(math.clamp(run.hull / math.max(1, run.maxHull), 0, 1), 1)
			hullText.Text = string.format("SHIP HULL %d / %d", run.hull, run.maxHull)
		else
			topTitle.Text = planetLabel .. " · DEFENSE"
			local hull = if data then data.hull else DefenseConfig.BaseHull
			hullFill.Size = UDim2.fromScale(1, 1)
			hullText.Text = string.format("SHIP HULL %d", hull)
		end
		local prep = run ~= nil and run.phase == "prep"
		local fight = run ~= nil and run.phase == "fight"
		start.Visible = run == nil
		howTo.Visible = run == nil
		incoming.Visible = run ~= nil
		crewBar.Visible = prep
		actions.Visible = prep
		supportBar.Visible = fight
		if run then
			local lines = { string.format("<b>%s</b>", run.plan.name) }
			for _, id in { "Grub", "Skitter", "Spitter", "Brute", "Boss" } do
				local n = run.plan.counts[id]
				if n then
					table.insert(lines, string.format("%s × %d", id, n))
				end
			end
			if run.plan.boss then
				table.insert(lines, "<font color=\"#ff6060\">⚠ BOSS WAVE</font>")
			end
			table.insert(lines, string.format("Losses this sector: %d", run.sectorLosses))
			incBody.Text = table.concat(lines, "\n")
			incTitle.Text = if fight then "FIGHTING" else "INCOMING"
			goB.set("START WAVE ▶", if #run.units > 0 then GREEN else nil)
		else
			renderStart()
		end
		renderCrew()
		renderSupports()
		renderPlanetHud()
	end

	-- ═══ Dışa açık ══════════════════════════════════════════════════════════
	local ui: UI = {} :: any

	function ui.OpenPilot()
		renderPilot()
		pilotRoot.Visible = true
	end

	function ui.OpenShop(kind: string)
		openShop = kind
		renderShop()
		shopRoot.Visible = true
	end

	function ui.CloseAll()
		pilotRoot.Visible = false
		shopRoot.Visible = false
	end

	function ui.SetData(d: any)
		data = d
		if pilotRoot.Visible then
			renderPilot()
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
		if not r then
			chosenSector = maxSector()
		end
		renderHud()
	end

	function ui.SetPlanetHud(visible: boolean)
		planetHud:SetAttribute("Wanted", visible)
		planetHud.Visible = visible and not hud.Visible
		renderPlanetHud()
	end

	function ui.SetCommand(visible: boolean)
		hud.Visible = visible
		planetHud.Visible = not visible and planetHud:GetAttribute("Wanted") == true
		if visible then
			pilotRoot.Visible = false
			shopRoot.Visible = false
			if not run then
				chosenSector = maxSector()
			end
			renderHud()
		end
	end

	function ui.SetSelected(info: any?)
		if not info then
			selBar.Visible = false
			return
		end
		local def = Config.GetUnit(info.unitId)
		local role = DefenseConfig.GetRole(info.unitId)
		selText.Text = string.format("%s %s · %s", role.icon, if def then def.name else info.unitId, role.name)
		selBar.Visible = run ~= nil and run.phase == "prep"
	end

	function ui.SetPicked(slot: number?, support: string?)
		picked.slot = slot
		picked.support = support
		renderCrew()
		renderSupports()
	end

	function ui.SetTick(snap: any)
		if run then
			run.hull = snap.hull
			if planetHud.Visible then
				renderPlanetHud()
			end
			hullFill.Size = UDim2.fromScale(math.clamp(snap.hull / math.max(1, run.maxHull), 0, 1), 1)
			hullText.Text = string.format("SHIP HULL %d / %d   ·   enemies %d", snap.hull, run.maxHull, #(snap.e or {}))
		end
	end

	function ui.Banner(title: string, sub: string, color: Color3)
		bannerToken += 1
		local token = bannerToken
		bannerTitle.Text = title
		bannerTitle.TextColor3 = color
		bannerSub.Text = sub
		banner.Visible = true
		banner.Size = UDim2.fromOffset(420, 96)
		TweenService:Create(banner, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(520, 120) }):Play()
		task.delay(3.2, function()
			if bannerToken == token then
				banner.Visible = false
			end
		end)
	end

	function ui.Hint(text: string?)
		hint.Text = text or ""
	end

	return ui
end

return DefenseUI
