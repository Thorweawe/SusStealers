--!strict
--[[
	Gezegen savunmasının 2B arayüzü (DefenseClient kuruyor ve besliyor).

	2026-10-01 ikinci sürüm (Batur): ayrı taktik ekran YOK. Oyuncu gezegende
	yürüyor; seçtiği crewmate'ler alet çubuğunda, tıklayıp alana bırakıyor.

	  DEFEND penceresi — bölüm, crewmate seçimi (role göre gruplu, en güçlüden
	                     zayıfa, hakkı kadar), gear seçimi → "prepare"
	  Yürüme ekranı    — üstte gezegen/bölüm/dalga/gövde/altın, sağda gelen
	                     dalga; altta DEFEND/TAKE OFF, hazırlıkta START WAVE/
	                     RETREAT, savaşta destekler
	  Dükkânlar        — Armory (kılıç, rol seviyesi), Command Shop (slot, gövde),
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
	local picked: { support: string? } = { support = nil }
	local ui: UI
	local renderPrep: () -> ()

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
				if level == 0 then "Fight with your crew! Pick it as your gear when you press DEFEND."
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

	-- ═══ DEFEND penceresi: bölüm → crewmate'ler → gear ══════════════════════
	--[[
		2026-10-01 (Batur): "DEFEND'e basınca hangi amongusları istediğimizi
		sorsun, elindekileri göstersin (shooter'lar şunlar, en iyiden en
		kötüye), hakkı kadar seçsin; sonra hangi gear'ı kullanacağımızı
		sorsun, o elimize gelsin". İki adım; DEFEND! ile sunucuya gidiyor.
	]]
	local prepRoot, prepBody = window("DefensePrepare", "DEFEND", {
		Color3.fromRGB(60, 200, 110), Color3.fromRGB(40, 150, 230), Color3.fromRGB(120, 230, 90),
	}, 820, 520)
	local prepStep = "crew"
	local chosen: { [number]: boolean } = {}
	local chosenGear = ""

	-- Üst satır: bölüm seçimi ve sayaç
	local topRow = Instance.new("Frame")
	topRow.Size = UDim2.new(1, 0, 0, 56)
	topRow.BackgroundTransparency = 1
	topRow.ZIndex = Z + 3
	topRow.Parent = prepBody
	local prevB = button(topRow, "◀", UDim2.fromOffset(46, 46), BLUE, Z + 4, 22)
	local sectorLabel = label(topRow, "", 24, WHITE, Z + 4)
	sectorLabel.Position = UDim2.fromOffset(52, 0)
	sectorLabel.Size = UDim2.fromOffset(170, 30)
	local sectorSub = label(topRow, "", 13, GOLD, Z + 4, 1.2)
	sectorSub.Position = UDim2.fromOffset(52, 28)
	sectorSub.Size = UDim2.fromOffset(170, 18)
	local nextSB = button(topRow, "▶", UDim2.fromOffset(46, 46), BLUE, Z + 4, 22)
	nextSB.holder.Position = UDim2.fromOffset(226, 0)
	local stepLabel = label(topRow, "", 20, Color3.fromRGB(150, 255, 180), Z + 4)
	stepLabel.Position = UDim2.fromOffset(290, 0)
	stepLabel.Size = UDim2.new(1, -290, 0, 26)
	stepLabel.TextXAlignment = Enum.TextXAlignment.Right
	local countLabel = label(topRow, "", 16, WHITE, Z + 4, 1.3)
	countLabel.Position = UDim2.fromOffset(290, 28)
	countLabel.Size = UDim2.new(1, -290, 0, 20)
	countLabel.TextXAlignment = Enum.TextXAlignment.Right

	local prepList = Instance.new("ScrollingFrame")
	prepList.Position = UDim2.fromOffset(0, 62)
	prepList.Size = UDim2.new(1, 0, 1, -128)
	prepList.BackgroundTransparency = 1
	prepList.BorderSizePixel = 0
	prepList.ScrollBarThickness = 6
	prepList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	prepList.CanvasSize = UDim2.new()
	prepList.ZIndex = Z + 3
	prepList.Parent = prepBody
	local prepLayout = Instance.new("UIListLayout")
	prepLayout.Padding = UDim.new(0, 6)
	prepLayout.SortOrder = Enum.SortOrder.LayoutOrder
	prepLayout.Parent = prepList

	local backB = button(prepBody, "◀ BACK", UDim2.fromOffset(150, 54), GREY, Z + 4, 18)
	backB.holder.AnchorPoint = Vector2.new(0, 1)
	backB.holder.Position = UDim2.new(0, 0, 1, 0)
	local autoB = button(prepBody, "⚡ BEST CREW", UDim2.fromOffset(180, 54), BLUE, Z + 4, 18)
	autoB.holder.AnchorPoint = Vector2.new(0, 1)
	autoB.holder.Position = UDim2.new(0, 0, 1, 0)
	local goPrepB = button(prepBody, "NEXT ▶", UDim2.fromOffset(220, 54), GREEN, Z + 4, 22)
	goPrepB.holder.AnchorPoint = Vector2.new(1, 1)
	goPrepB.holder.Position = UDim2.new(1, 0, 1, 0)

	local function maxSector(): number
		local p = data and data.planets and data.planets[currentPlanet]
		return (if p then p.best else 0) + 1
	end

	local function freeCrew(): { any }
		local list = {}
		for _, c in (if data then data.crew else nil) or {} do
			if not c.away then
				table.insert(list, c)
			end
		end
		return list
	end

	local function chosenCount(): number
		local n = 0
		for _ in chosen do
			n += 1
		end
		return n
	end

	local function crewCard(parent: Instance, c: any, order: number)
		local def = Config.GetUnit(c.unitId)
		local role = DefenseConfig.GetRole(c.unitId)
		local selected = chosen[c.slot] == true
		local card = Instance.new("TextButton")
		card.LayoutOrder = order
		card.Size = UDim2.fromOffset(112, 112)
		card.BackgroundColor3 = WHITE
		card.AutoButtonColor = false
		card.Text = ""
		card.ZIndex = Z + 5
		card.Parent = parent
		FancyKit.corner(card, 10)
		FancyKit.border(card, if selected then GOLD else OUTLINE, if selected then 4 else 2.5)
		local rarity = def and Config.Rarities[def.rarity]
		local tint = if rarity then rarity.color else GREY
		FancyKit.gradient(card, { tint:Lerp(WHITE, 0.15), tint:Lerp(Color3.new(0, 0, 0), 0.45) }, 90)
		local iconHolder = Instance.new("Frame")
		iconHolder.Size = UDim2.fromOffset(60, 60)
		iconHolder.Position = UDim2.fromOffset(26, 4)
		iconHolder.BackgroundTransparency = 1
		iconHolder.ZIndex = Z + 6
		iconHolder.Parent = card
		pcall(UiKit.UnitIcon, iconHolder, 60, c.unitId)
		local mutation = Config.GetMutation(c.mutationId)
		local name = label(card, (if mutation then mutation.name .. " " else "") .. (if def then def.name else c.unitId), 12, WHITE, Z + 7, 1.3)
		name.Position = UDim2.fromOffset(3, 66)
		name.Size = UDim2.new(1, -6, 0, 16)
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local pw = label(card, string.format("POWER %.2f", DefenseConfig.GetPower(c.unitId, c.mutationId)), 12, GOLD, Z + 7, 1.2)
		pw.Position = UDim2.fromOffset(3, 84)
		pw.Size = UDim2.new(1, -6, 0, 16)
		if selected then
			local tick = label(card, "✓", 26, Color3.fromRGB(120, 255, 140), Z + 8)
			tick.Position = UDim2.new(1, -30, 0, 2)
			tick.Size = UDim2.fromOffset(28, 28)
		end
		local _ = role
		card.Activated:Connect(function()
			if chosen[c.slot] then
				chosen[c.slot] = nil
			elseif data and chosenCount() < data.slots then
				chosen[c.slot] = true
			end
			renderPrep()
		end)
	end

	renderPrep = function()
		for _, ch in prepList:GetChildren() do
			if ch:IsA("GuiObject") then
				ch:Destroy()
			end
		end
		local maxS = maxSector()
		chosenSector = math.clamp(chosenSector, 1, maxS)
		local per = DefenseConfig.WavesPerSector
		sectorLabel.Text = "SECTOR " .. chosenSector
		sectorSub.Text = string.format("Waves %d-%d  %s%s", (chosenSector - 1) * per + 1, chosenSector * per,
			stars(sectorStars(data, currentPlanet, chosenSector)), if chosenSector == maxS then "  NEW!" else "")
		prevB.set("◀", if chosenSector > 1 then BLUE else nil)
		nextSB.set("▶", if chosenSector < maxS then BLUE else nil)
		local cap = if data then data.slots else DefenseConfig.BaseSlots
		countLabel.Text = string.format("CREW %d / %d", chosenCount(), cap)

		if prepStep == "crew" then
			stepLabel.Text = "1. PICK YOUR CREW"
			backB.holder.Visible = false
			autoB.holder.Visible = true
			goPrepB.set("NEXT ▶", if chosenCount() > 0 then GREEN else nil)
			local free = freeCrew()
			if #free == 0 then
				local none = label(prepList, "No crewmates at your base. Steal some in space first!", 18, Color3.fromRGB(220, 220, 240), Z + 5)
				none.Size = UDim2.new(1, 0, 0, 60)
				return
			end
			-- Role göre gruplar, her grupta en güçlüden zayıfa
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
					local header = label(prepList, string.format("%s %sS  ·  %s", role.icon, string.upper(role.name), role.desc),
						16, role.color, Z + 5, 1.4)
					header.LayoutOrder = r * 2 - 1
					header.Size = UDim2.new(1, -10, 0, 22)
					header.TextXAlignment = Enum.TextXAlignment.Left
					local row = Instance.new("Frame")
					row.LayoutOrder = r * 2
					row.Size = UDim2.new(1, -10, 0, 0)
					row.AutomaticSize = Enum.AutomaticSize.Y
					row.BackgroundTransparency = 1
					row.ZIndex = Z + 4
					row.Parent = prepList
					local grid = Instance.new("UIGridLayout")
					grid.CellSize = UDim2.fromOffset(112, 112)
					grid.CellPadding = UDim2.fromOffset(8, 8)
					grid.SortOrder = Enum.SortOrder.LayoutOrder
					grid.Parent = row
					for i, c in group do
						crewCard(row, c, i)
					end
				end
			end
		else
			stepLabel.Text = "2. PICK YOUR GEAR"
			backB.holder.Visible = true
			autoB.holder.Visible = false
			goPrepB.set("DEFEND! ▶", GREEN)
			local saber = if data then (data.saber or 0) else 0
			local options = {
				{ id = "", icon = "✋", title = "NO GEAR", sub = "Just command your crew.", owned = true },
				{ id = "Lightsaber", icon = "⚔", title = if saber > 0 then string.format("LIGHTSABER  Lv %d", saber) else "LIGHTSABER",
					sub = if saber > 0 then "Slash enemies yourself while your crew fights." else "Buy it at the ARMORY with gold.",
					owned = saber > 0 },
			}
			for i, o in options do
				local selected = chosenGear == o.id
				local card = Instance.new("TextButton")
				card.LayoutOrder = i
				card.Size = UDim2.new(1, -10, 0, 84)
				card.BackgroundColor3 = WHITE
				card.AutoButtonColor = false
				card.Text = ""
				card.ZIndex = Z + 5
				card.Parent = prepList
				FancyKit.corner(card, 12)
				FancyKit.border(card, if selected then GOLD else OUTLINE, if selected then 4 else 2.5)
				FancyKit.gradient(card, if o.owned then { Color3.fromRGB(60, 80, 120), Color3.fromRGB(30, 36, 60) }
					else { Color3.fromRGB(60, 60, 70), Color3.fromRGB(34, 34, 40) }, 90)
				local ic = label(card, o.icon, 40, WHITE, Z + 6, 0)
				ic.Size = UDim2.fromOffset(80, 84)
				local t = label(card, o.title .. (if o.owned then "" else "  🔒"), 22, WHITE, Z + 6)
				t.Position = UDim2.fromOffset(84, 12)
				t.Size = UDim2.new(1, -120, 0, 28)
				t.TextXAlignment = Enum.TextXAlignment.Left
				local sb = label(card, o.sub, 15, Color3.fromRGB(200, 210, 240), Z + 6, 1.3)
				sb.Position = UDim2.fromOffset(84, 44)
				sb.Size = UDim2.new(1, -120, 0, 26)
				sb.TextXAlignment = Enum.TextXAlignment.Left
				if selected then
					local tick = label(card, "✓", 32, Color3.fromRGB(120, 255, 140), Z + 7)
					tick.Position = UDim2.new(1, -50, 0, 22)
					tick.Size = UDim2.fromOffset(40, 40)
				end
				card.Activated:Connect(function()
					if o.owned then
						chosenGear = o.id
						renderPrep()
					end
				end)
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
		-- En güçlüler, ama her rolden en az biri (varsa) önce
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
	backB.button.Activated:Connect(function()
		prepStep = "crew"
		renderPrep()
	end)
	goPrepB.button.Activated:Connect(function()
		if prepStep == "crew" then
			if chosenCount() == 0 then
				return
			end
			prepStep = "gear"
			if chosenGear == "" and data and (data.saber or 0) > 0 then
				chosenGear = "Lightsaber"
			end
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

	-- ═══ Gezegende yürürken: durum, düğmeler, destekler ═════════════════════
	local hud = Instance.new("Frame")
	hud.Name = "DefensePlanetHud"
	hud.Size = UDim2.fromScale(1, 1)
	hud.BackgroundTransparency = 1
	hud.Visible = false
	hud.ZIndex = Z - 12
	hud.Parent = screen

	-- Üstte durum
	local top = panel(hud, UDim2.fromOffset(520, 70), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0), Z - 11)
	local topTitle = label(top, "", 20, WHITE, Z - 10)
	topTitle.Position = UDim2.fromOffset(14, 6)
	topTitle.Size = UDim2.new(1, -140, 0, 26)
	topTitle.TextXAlignment = Enum.TextXAlignment.Left
	local topGold = label(top, "", 20, GOLD, Z - 10)
	topGold.AnchorPoint = Vector2.new(1, 0)
	topGold.Position = UDim2.new(1, -14, 0, 6)
	topGold.Size = UDim2.fromOffset(120, 26)
	topGold.TextXAlignment = Enum.TextXAlignment.Right
	local hullBack = Instance.new("Frame")
	hullBack.Position = UDim2.fromOffset(14, 40)
	hullBack.Size = UDim2.new(1, -28, 0, 18)
	hullBack.BackgroundColor3 = Color3.fromRGB(16, 16, 24)
	hullBack.ZIndex = Z - 10
	hullBack.Parent = top
	FancyKit.corner(hullBack, 9)
	local hullFill = Instance.new("Frame")
	hullFill.Size = UDim2.fromScale(1, 1)
	hullFill.BackgroundColor3 = WHITE
	hullFill.ZIndex = Z - 9
	hullFill.Parent = hullBack
	FancyKit.corner(hullFill, 9)
	FancyKit.gradient(hullFill, { Color3.fromRGB(120, 230, 255), Color3.fromRGB(40, 140, 230) }, 90)
	local hullText = label(hullBack, "", 13, WHITE, Z - 8, 1.3)
	hullText.Size = UDim2.fromScale(1, 1)
	local hint = label(hud, "", 17, WHITE, Z - 10)
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 84)
	hint.Size = UDim2.fromOffset(760, 24)

	-- Sağda gelen dalga
	local incoming = panel(hud, UDim2.fromOffset(220, 150), UDim2.new(1, -12, 0, 200), Vector2.new(1, 0), Z - 11,
		Color3.fromRGB(70, 34, 40), Color3.fromRGB(34, 18, 26))
	local incTitle = label(incoming, "INCOMING", 18, Color3.fromRGB(255, 170, 60), Z - 10)
	incTitle.Position = UDim2.fromOffset(0, 6)
	incTitle.Size = UDim2.new(1, 0, 0, 22)
	local incBody = label(incoming, "", 15, WHITE, Z - 10, 1.3)
	incBody.Position = UDim2.fromOffset(12, 32)
	incBody.Size = UDim2.new(1, -24, 1, -38)
	incBody.TextWrapped = true
	incBody.TextYAlignment = Enum.TextYAlignment.Top
	incBody.TextXAlignment = Enum.TextXAlignment.Left
	incBody.RichText = true

	-- Altta (alet çubuğunun üstünde) düğmeler
	local bottom = Instance.new("Frame")
	bottom.AnchorPoint = Vector2.new(0.5, 1)
	bottom.Position = UDim2.new(0.5, 0, 1, -96)
	bottom.Size = UDim2.fromOffset(480, 70)
	bottom.BackgroundTransparency = 1
	bottom.ZIndex = Z - 11
	bottom.Parent = hud
	local mainB = button(bottom, "⚔ DEFEND", UDim2.fromOffset(250, 66), GREEN, Z - 10, 26)
	local sideB = button(bottom, "🚀 TAKE OFF", UDim2.fromOffset(200, 58), BLUE, Z - 10, 18)
	sideB.holder.Position = UDim2.fromOffset(264, 4)
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
	-- DEFEND / START hafifçe nabız atıyor
	task.spawn(function()
		while hud.Parent do
			if hud.Visible and mode ~= "fight" then
				local t = os.clock()
				mainB.holder.Size = UDim2.fromOffset(250 + math.sin(t * 4) * 6, 66 + math.sin(t * 4) * 2)
			end
			task.wait(0.05)
		end
	end)

	-- Savaşta destekler
	local supportBar = Instance.new("Frame")
	supportBar.AnchorPoint = Vector2.new(0.5, 1)
	supportBar.Position = UDim2.new(0.5, 0, 1, -96)
	supportBar.Size = UDim2.fromOffset(3 * 150 + 20, 64)
	supportBar.BackgroundTransparency = 1
	supportBar.ZIndex = Z - 11
	supportBar.Parent = hud
	local supportButtons: { [string]: FancyKit.Button } = {}
	for i, s in DefenseConfig.Supports do
		local b = button(supportBar, "", UDim2.fromOffset(140, 60), Color3.fromRGB(150, 90, 255), Z - 10, 16)
		b.holder.Position = UDim2.fromOffset((i - 1) * 160, 0)
		b.button.Activated:Connect(function()
			hooks.pickSupport(if picked.support == s.id then nil else s.id)
		end)
		supportButtons[s.id] = b
	end

	-- Sonuç bandı
	local banner = panel(screen, UDim2.fromOffset(520, 120), UDim2.fromScale(0.5, 0.36), Vector2.new(0.5, 0.5), Z + 20)
	banner.Visible = false
	local bannerTitle = label(banner, "", 34, WHITE, Z + 21)
	bannerTitle.Position = UDim2.fromOffset(0, 12)
	bannerTitle.Size = UDim2.new(1, 0, 0, 44)
	local bannerSub = label(banner, "", 19, GOLD, Z + 21)
	bannerSub.Position = UDim2.fromOffset(10, 62)
	bannerSub.Size = UDim2.new(1, -20, 0, 46)
	bannerSub.TextWrapped = true
	local bannerToken = 0

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
		local gold = if data then data.gold else 0
		topGold.Text = "🪙 " .. tostring(gold)
		local name = planetName(currentPlanet)
		mode = if run == nil then "idle" elseif run.phase == "fight" then "fight" else "prep"
		if run then
			topTitle.Text = string.format("%s · SECTOR %d · WAVE %d/%d", name, run.sector, run.waveInSector, DefenseConfig.WavesPerSector)
			hullFill.Size = UDim2.fromScale(math.clamp(run.hull / math.max(1, run.maxHull), 0, 1), 1)
			hullText.Text = string.format("SHIP HULL %d / %d", run.hull, run.maxHull)
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
			incBody.Text = table.concat(lines, "\n")
			incTitle.Text = if mode == "fight" then "FIGHTING" else "NEXT WAVE"
		else
			topTitle.Text = name .. " · DEFENSE"
			local hull = if data then data.hull else DefenseConfig.BaseHull
			hullFill.Size = UDim2.fromScale(1, 1)
			hullText.Text = string.format("SHIP HULL %d", hull)
		end
		incoming.Visible = run ~= nil
		bottom.Visible = mode ~= "fight"
		supportBar.Visible = mode == "fight"
		if mode == "idle" then
			mainB.set("⚔ DEFEND", GREEN)
			sideB.set("🚀 TAKE OFF", BLUE)
			hint.Text = "Press ⚔ DEFEND to pick your crew"
		elseif mode == "prep" then
			mainB.set("▶ START WAVE", if #run.units > 0 then GREEN else nil)
			sideB.set("↩ RETREAT", RED)
			hint.Text = if (run.carried or 0) > 0
				then "Pick a crewmate from your bar, walk on the field and CLICK to drop it (near the orange arrows)"
				else "Your crew is ready - press START WAVE!"
		else
			hint.Text = if run.gear == "Lightsaber" then "Defend the ship! Equip your Lightsaber and slash enemies"
				elseif (run.carried or 0) > 0 then "Defend the ship! You can still drop crewmates from your bar"
				else "Defend the ship!"
		end
		renderSupports()
	end

	-- ═══ Dışa açık ══════════════════════════════════════════════════════════
	ui = {} :: any

	function ui.OpenPrepare()
		if run then
			return
		end
		prepStep = "crew"
		table.clear(chosen)
		chosenSector = maxSector()
		shopRoot.Visible = false
		hooks.send("sync")
		renderPrep()
		prepRoot.Visible = true
	end

	function ui.OpenShop(kind: string)
		openShop = kind
		renderShop()
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

	return ui
end

return DefenseUI
