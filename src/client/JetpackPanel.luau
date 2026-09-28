--!strict
--[[
	Jetpack dükkânı: Launch Bay'deki JETPACKS standının tezgâhında E'ye
	basınca açılıyor (prompt "JetpackPrompt", sunucu JetpackService kuruyor).

	Her jetpack bir kart (4×2): dönen 3B önizleme (ViewportFrame,
	shared/JetpackModel), ad, hız bonusu ve BUY / EQUIP / EQUIPPED. Robux
	jetpack'lerinde R$ fiyatı; pass kimliği henüz 0 ise "SOON". Fiyat ve
	sahiplik sunucuda; burası yalnızca "JetpackAction" gönderiyor ve
	"Jetpack" / "JetpacksOwned" niteliklerini okuyor.

	İkinci sekme FLAMES (2026-09-28): alev kozmetikleri (Config.JetFlames).
	Önizleme 3B değil: ViewportFrame parçacık çizmiyor, o yüzden alev
	arayüzde çiziliyor (degradeli damla katmanları, titreşen, ışıltılı;
	gökkuşağı renk değiştiriyor). Sahiplik "FlamesOwned", takılı "JetFlame".

	2026-09-28: mağazanın dilinde (FancyKit kabuğu, renkli ışınlı kartlar,
	tıknaz düğmeler, takılı olana sarı çerçeve). Mantık aynı.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local JetpackModel = require(Shared.JetpackModel)
local Net = require(Shared.Net)

local FancyKit = require(script.Parent.FancyKit)
local UiKit = require(script.Parent.UiKit)

local JetpackPanel = {}

local player = Players.LocalPlayer

local ACCENT = Color3.fromRGB(80, 170, 255)
local ROBUX = Color3.fromRGB(60, 200, 110)
local BUY = Color3.fromRGB(70, 200, 70)
local EQUIPPED = Color3.fromRGB(255, 226, 60)
local OUTLINE = Color3.fromRGB(22, 20, 34)
local Z = 45
local COLUMNS = 4

export type Panel = {
	Open: () -> (),
	Destroy: () -> (),
}

local function label(parent: Instance, text: string, size: number, color: Color3, z: number, stroke: number?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.ZIndex = z
	l.Parent = parent
	local s = Instance.new("UIStroke")
	s.Color = OUTLINE
	s.Thickness = stroke or math.max(1.6, size / 9)
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = l
	return l
end

-- Kartın sağ üstündeki etiket (ROBUX / SEASON / WEEKLY #1)
local function tag(card: Frame, text: string, color: Color3, z: number)
	local t = Instance.new("Frame")
	t.AnchorPoint = Vector2.new(1, 0)
	t.Position = UDim2.new(1, -8, 0, 8)
	t.Size = UDim2.fromOffset(if #text > 6 then 74 else 60, 22)
	t.BackgroundColor3 = Color3.new(1, 1, 1)
	t.ZIndex = z
	t.Parent = card
	FancyKit.corner(t, 8)
	FancyKit.border(t, OUTLINE, 2.5)
	FancyKit.gradient(t, { color:Lerp(Color3.new(1, 1, 1), 0.25), color:Lerp(Color3.new(0, 0, 0), 0.2) }, 90)
	local l = label(t, text, 13, Color3.new(1, 1, 1), z + 1, 1.8)
	l.Size = UDim2.fromScale(1, 1)
end

-- Takılı olanı gösteren sarı kalın çerçeve (kartın üstünde)
local function highlight(card: Frame, z: number): UIStroke
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.ZIndex = z
	f.Parent = card
	FancyKit.corner(f, 14)
	local s = Instance.new("UIStroke")
	s.Color = EQUIPPED
	s.Thickness = 4
	s.Transparency = 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	return s
end

function JetpackPanel.Create(screen: ScreenGui): Panel
	local HEADER = 66
	local rows = math.ceil(#Config.Jetpacks / COLUMNS)
	local root = UiKit.Window(screen, "JetpackPanel", ACCENT)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(32 + COLUMNS * 176, HEADER + 44 + rows * 262)
	root.Visible = false
	root.ZIndex = Z
	local driver = FancyKit.driver(root)
	local shell = FancyKit.shell(root, "JETPACKS", {
		Color3.fromRGB(40, 150, 255), Color3.fromRGB(120, 90, 255), Color3.fromRGB(40, 220, 230),
	}, HEADER, Z, driver, 44)
	local band = shell.header
	local close = shell.close

	local hint = label(root, "Faster on the way out to the planets. Carrying crew home, you fly at your own speed.",
		15, Color3.fromRGB(220, 228, 255), Z + 2, 1.8)
	hint.Position = UDim2.fromOffset(16, HEADER + 6)
	hint.Size = UDim2.new(1, -32, 0, 22)
	hint.TextTruncate = Enum.TextTruncate.AtEnd

	-- Sekmeler: başlık şeridinin sağında (X'in solu)
	type Tab = { button: TextButton, text: TextLabel }
	local tabs: { [string]: Tab } = {}
	local function makeTab(id: string, text: string, order: number)
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -76 - (order - 1) * 134, 0.5, 0)
		b.Size = UDim2.fromOffset(126, 40)
		b.BackgroundColor3 = Color3.new(1, 1, 1)
		b.AutoButtonColor = false
		b.Text = ""
		b.ZIndex = Z + 6
		b.Parent = band
		FancyKit.corner(b, 12)
		FancyKit.border(b, OUTLINE, 3)
		local t = label(b, text, 20, Color3.new(1, 1, 1), Z + 8, 2.2)
		t.Size = UDim2.fromScale(1, 1)
		FancyKit.juicy(b, b, 1.06, 2)
		tabs[id] = { button = b, text = t }
	end
	makeTab("flames", "FLAMES", 1)
	makeTab("packs", "PACKS", 2)

	local grid = Instance.new("Frame")
	grid.Name = "PackGrid"
	grid.Position = UDim2.fromOffset(16, HEADER + 34)
	grid.Size = UDim2.new(1, -32, 1, -(HEADER + 44))
	grid.BackgroundTransparency = 1
	grid.ZIndex = Z + 1
	grid.Parent = root
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / COLUMNS, -10, 1 / rows, -10)
	layout.CellPadding = UDim2.fromOffset(10, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local actionRemote = Net.Get("JetpackAction")

	type Card = { def: Config.JetpackDef, buy: FancyKit.Button, stroke: UIStroke }
	local cards: { Card } = {}
	type Spin = { camera: Camera, center: Vector3 }
	local spins: { Spin } = {}

	for index, def in Config.Jetpacks do
		local slot = Instance.new("Frame")
		slot.LayoutOrder = index
		slot.BackgroundTransparency = 1
		slot.ZIndex = Z + 2
		slot.Parent = grid
		local card = FancyKit.card(slot, def.tank, UDim2.fromScale(1, 1), Z + 2, driver, UDim2.new(0.5, 0, 0, 66))
		FancyKit.hover(slot, 1.03)
		local stroke = highlight(card, Z + 9)

		-- 3B önizleme (arkasında hale)
		local glowHolder = Instance.new("Frame")
		glowHolder.AnchorPoint = Vector2.new(0.5, 0)
		glowHolder.Position = UDim2.new(0.5, 0, 0, 6)
		glowHolder.Size = UDim2.new(1, -16, 0, 124)
		glowHolder.BackgroundTransparency = 1
		glowHolder.ZIndex = Z + 3
		glowHolder.Parent = card
		FancyKit.glow(glowHolder, def.flame:Lerp(Color3.new(1, 1, 1), 0.3), 1.1, 0.35, Z + 3)
		local view = Instance.new("ViewportFrame")
		view.Size = UDim2.fromScale(1, 1)
		view.BackgroundTransparency = 1
		view.Ambient = Color3.fromRGB(170, 175, 195)
		view.LightColor = Color3.new(1, 1, 1)
		view.LightDirection = Vector3.new(-0.5, -1, -0.6)
		view.ZIndex = Z + 4
		view.Parent = glowHolder
		local world = Instance.new("WorldModel")
		world.Parent = view
		local model = JetpackModel.Build(def, CFrame.new(), 1)
		model.Parent = world
		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		camera.Parent = view
		view.CurrentCamera = camera
		table.insert(spins, { camera = camera, center = Vector3.new(0, 0, 0.9) })

		if def.pass ~= nil then
			tag(card, "ROBUX", ROBUX, Z + 7)
		end

		local name = FancyKit.title(card, def.name, 21, Color3.new(1, 1, 1), Color3.fromRGB(255, 236, 190), Z + 5, driver)
		name.Position = UDim2.fromOffset(4, 132)
		name.Size = UDim2.new(1, -8, 0, 26)
		local boost = label(card, if def.boost > 1 then string.format("+%d%% flight speed", math.floor((def.boost - 1) * 100 + 0.5)) else "Standard issue",
			16, Color3.fromRGB(255, 236, 120), Z + 5, 2)
		boost.Position = UDim2.fromOffset(6, 162)
		boost.Size = UDim2.new(1, -12, 0, 20)
		local sub = label(card, "on the way out", 13, Color3.fromRGB(225, 232, 250), Z + 5, 1.6)
		sub.Position = UDim2.fromOffset(6, 182)
		sub.Size = UDim2.new(1, -12, 0, 16)
		sub.Visible = def.boost > 1

		local buy = FancyKit.button(card, UDim2.new(1, -16, 0, 46), BUY, 19, Z + 6, driver, index * 0.4)
		buy.holder.AnchorPoint = Vector2.new(0.5, 1)
		buy.holder.Position = UDim2.new(0.5, 0, 1, -8)

		local id = def.id
		buy.button.MouseButton1Click:Connect(function()
			if not buy.button.Active then
				return
			end
			local owned = string.find("," .. tostring(player:GetAttribute("JetpacksOwned") or "") .. ",", "," .. id .. ",", 1, true) ~= nil
			if owned then
				actionRemote:FireServer("equip", id)
			elseif def.pass ~= nil then
				if def.pass > 0 then
					MarketplaceService:PromptGamePassPurchase(player, def.pass)
				end
			else
				actionRemote:FireServer("buy", id)
			end
		end)
		table.insert(cards, { def = def, buy = buy, stroke = stroke })
	end

	-- ─── Alevler ─────────────────────────────────────────────────────────
	local FLAME_COLUMNS = 5
	local flameRows = math.ceil(#Config.JetFlames / FLAME_COLUMNS)
	local flameGrid = Instance.new("Frame")
	flameGrid.Name = "FlameGrid"
	flameGrid.Position = grid.Position
	flameGrid.Size = grid.Size
	flameGrid.BackgroundTransparency = 1
	flameGrid.Visible = false
	flameGrid.ZIndex = Z + 1
	flameGrid.Parent = root
	local flameLayout = Instance.new("UIGridLayout")
	flameLayout.CellSize = UDim2.new(1 / FLAME_COLUMNS, -10, 1 / flameRows, -10)
	flameLayout.CellPadding = UDim2.fromOffset(10, 10)
	flameLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	flameLayout.SortOrder = Enum.SortOrder.LayoutOrder
	flameLayout.Parent = flameGrid

	type FlameCard = { def: Config.JetFlameDef, buy: FancyKit.Button, stroke: UIStroke, layers: { Frame }, grads: { UIGradient }, dots: { Frame } }
	local flameCards: { FlameCard } = {}

	--[[ Arayüzde alev: üç iç içe damla (dış renk → iç beyaz), aşağı doğru. ]]
	local function drawFlame(parent: Frame, def: Config.JetFlameDef): ({ Frame }, { UIGradient }, { Frame })
		local layers: { Frame } = {}
		local grads: { UIGradient } = {}
		local shapes = {
			{ w = 0.46, h = 0.86, top = def.flame2, bottom = def.flame2:Lerp(Color3.new(0, 0, 0), 0.3), tr = 0.15 },
			{ w = 0.32, h = 0.66, top = def.flame, bottom = def.flame2, tr = 0.05 },
			{ w = 0.16, h = 0.4, top = def.core or Color3.new(1, 1, 1), bottom = def.flame, tr = 0 },
		}
		for i, sh in shapes do
			local f = Instance.new("Frame")
			f.AnchorPoint = Vector2.new(0.5, 0)
			f.Position = UDim2.fromScale(0.5, 0.06)
			f.Size = UDim2.fromScale(sh.w, sh.h)
			f.BackgroundColor3 = Color3.new(1, 1, 1)
			f.BorderSizePixel = 0
			f.ZIndex = Z + 4 + i
			f.Parent = parent
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = f
			local g = Instance.new("UIGradient")
			g.Rotation = 90
			g.Color = ColorSequence.new(sh.top, sh.bottom)
			g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, sh.tr), NumberSequenceKeypoint.new(0.7, sh.tr + 0.1), NumberSequenceKeypoint.new(1, 1) })
			g.Parent = f
			table.insert(layers, f)
			table.insert(grads, g)
		end
		-- Meme: alevin çıktığı koyu ağız
		local nozzle = Instance.new("Frame")
		nozzle.AnchorPoint = Vector2.new(0.5, 0)
		nozzle.Position = UDim2.fromScale(0.5, 0)
		nozzle.Size = UDim2.fromScale(0.36, 0.1)
		nozzle.BackgroundColor3 = Color3.fromRGB(60, 64, 78)
		nozzle.BorderSizePixel = 0
		nozzle.ZIndex = Z + 8
		nozzle.Parent = parent
		UiKit.Corner(nozzle, 4)
		UiKit.Stroke(nozzle, OUTLINE, 2, 0)
		-- Işıltı/kıvılcım noktaları
		local dots: { Frame } = {}
		if def.sparkle or def.embers then
			for k = 1, 6 do
				local d = Instance.new("Frame")
				d.AnchorPoint = Vector2.new(0.5, 0.5)
				d.Size = UDim2.fromOffset(4, 4)
				d.BackgroundColor3 = def.sparkle or def.flame
				d.BorderSizePixel = 0
				d.Rotation = 45
				d.ZIndex = Z + 9
				d:SetAttribute("Seed", k * 1.37)
				d.Parent = parent
				table.insert(dots, d)
			end
		end
		return layers, grads, dots
	end

	for index, def in Config.JetFlames do
		local slot = Instance.new("Frame")
		slot.LayoutOrder = index
		slot.BackgroundTransparency = 1
		slot.ZIndex = Z + 2
		slot.Parent = flameGrid
		local card = FancyKit.card(slot, def.flame2:Lerp(Color3.fromRGB(40, 44, 70), 0.35), UDim2.fromScale(1, 1), Z + 2, nil, UDim2.new(0.5, 0, 0, 60))
		FancyKit.hover(slot, 1.03)
		local stroke = highlight(card, Z + 11)

		local stage = Instance.new("Frame")
		stage.AnchorPoint = Vector2.new(0.5, 0)
		stage.Position = UDim2.new(0.5, 0, 0, 8)
		stage.Size = UDim2.new(1, -16, 0, 110)
		stage.BackgroundColor3 = Color3.fromRGB(10, 12, 26)
		stage.BackgroundTransparency = 0.25
		stage.ClipsDescendants = true
		stage.ZIndex = Z + 3
		stage.Parent = card
		UiKit.Corner(stage, 12)
		UiKit.Stroke(stage, OUTLINE, 2.5, 0)
		local layers, grads, dots = drawFlame(stage, def)

		local tagText = if def.pass ~= nil then "ROBUX" elseif def.source == "season" then "SEASON" elseif def.source == "weekly" then "WEEKLY #1" else nil
		if tagText then
			tag(card, tagText, if def.pass ~= nil then ROBUX elseif def.source == "season" then Color3.fromRGB(170, 90, 255) else Color3.fromRGB(230, 170, 30), Z + 10)
		end

		local name = FancyKit.title(card, def.name, 18, Color3.new(1, 1, 1), Color3.fromRGB(255, 236, 190), Z + 5)
		name.Position = UDim2.fromOffset(4, 122)
		name.Size = UDim2.new(1, -8, 0, 22)
		local blurb = label(card, def.blurb, 12, Color3.fromRGB(225, 232, 250), Z + 5, 1.4)
		blurb.Position = UDim2.fromOffset(8, 148)
		blurb.Size = UDim2.new(1, -16, 0, 32)
		blurb.TextWrapped = true
		blurb.TextYAlignment = Enum.TextYAlignment.Top

		local buy = FancyKit.button(card, UDim2.new(1, -16, 0, 40), BUY, 15, Z + 6, nil)
		buy.holder.AnchorPoint = Vector2.new(0.5, 1)
		buy.holder.Position = UDim2.new(0.5, 0, 1, -8)

		local id = def.id
		buy.button.MouseButton1Click:Connect(function()
			if not buy.button.Active then
				return
			end
			local owned = string.find("," .. tostring(player:GetAttribute("FlamesOwned") or "") .. ",", "," .. id .. ",", 1, true) ~= nil
			if owned then
				actionRemote:FireServer("flameequip", id)
			elseif def.pass ~= nil then
				if def.pass > 0 then
					MarketplaceService:PromptGamePassPurchase(player, def.pass)
				end
			elseif def.source == nil then
				actionRemote:FireServer("flamebuy", id)
			end
		end)
		table.insert(flameCards, { def = def, buy = buy, stroke = stroke, layers = layers, grads = grads, dots = dots })
	end

	-- Parası yetmiyorsa soluk yeşil (yine basılabilir; sunucu reddediyor)
	local function priceColor(cash: number, price: number): Color3
		return if cash >= price then BUY else BUY:Lerp(Color3.fromRGB(90, 96, 110), 0.55)
	end

	local function refresh()
		local owned: { [string]: boolean } = {}
		local raw = player:GetAttribute("JetpacksOwned")
		if typeof(raw) == "string" then
			for id in string.gmatch(raw, "[^,]+") do
				owned[id] = true
			end
		end
		local equippedRaw = player:GetAttribute("Jetpack")
		local equipped = if typeof(equippedRaw) == "string" then equippedRaw else "Starter"
		local cashValue = player:GetAttribute("Cash")
		local cash = if typeof(cashValue) == "number" then cashValue else 0
		for _, card in cards do
			local def = card.def
			local isOn = equipped == def.id
			card.stroke.Transparency = if isOn then 0 else 1
			if isOn then
				card.buy.set("EQUIPPED", nil)
			elseif owned[def.id] then
				card.buy.set("EQUIP", ACCENT)
			elseif def.pass ~= nil then
				if def.pass <= 0 then
					card.buy.set("SOON", nil)
				else
					card.buy.set(tostring(def.robux or "?"), ROBUX, true)
				end
			else
				card.buy.set("$" .. Config.FormatCash(def.price), priceColor(cash, def.price))
			end
		end

		local flamesOwned: { [string]: boolean } = {}
		local rawFlames = player:GetAttribute("FlamesOwned")
		if typeof(rawFlames) == "string" then
			for id in string.gmatch(rawFlames, "[^,]+") do
				flamesOwned[id] = true
			end
		end
		local flameRaw = player:GetAttribute("JetFlame")
		local flameOn = if typeof(flameRaw) == "string" then flameRaw else "Classic"
		for _, card in flameCards do
			local def = card.def
			local isOn = flameOn == def.id
			card.stroke.Transparency = if isOn then 0 else 1
			if isOn then
				card.buy.set("EQUIPPED", nil)
			elseif flamesOwned[def.id] then
				card.buy.set("EQUIP", ACCENT)
			elseif def.pass ~= nil then
				if def.pass <= 0 then
					card.buy.set("SOON", nil)
				else
					card.buy.set(tostring(def.robux or "?"), ROBUX, true)
				end
			elseif def.source == "season" then
				card.buy.set("SEASON PASS", nil)
			elseif def.source == "weekly" then
				card.buy.set("WIN A WEEK", nil)
			else
				card.buy.set("$" .. Config.FormatCash(def.price), priceColor(cash, def.price))
			end
		end
	end

	local current = "packs"
	local function showTab(id: string)
		current = id
		grid.Visible = id == "packs"
		flameGrid.Visible = id == "flames"
		for tabId, tab in tabs do
			local on = tabId == id
			local g = tab.button:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
			g.Rotation = 90
			g.Color = if on
				then ColorSequence.new(Color3.fromRGB(255, 226, 90), Color3.fromRGB(240, 150, 20))
				else ColorSequence.new(Color3.fromRGB(60, 66, 96), Color3.fromRGB(30, 34, 52))
			g.Parent = tab.button
			tab.text.TextColor3 = if on then Color3.new(1, 1, 1) else Color3.fromRGB(190, 198, 225)
		end
		hint.Text = if id == "packs" then "Faster on the way out to the planets. Carrying crew home, you fly at your own speed."
			else "Pure style: your flame and trail, on any jetpack. Everyone in space sees it."
	end
	for id, tab in tabs do
		tab.button.Activated:Connect(function()
			showTab(id)
		end)
	end
	showTab("packs")

	local conns: { RBXScriptConnection } = {}
	for _, attr in { "JetpacksOwned", "Jetpack", "FlamesOwned", "JetFlame" } do
		table.insert(conns, player:GetAttributeChangedSignal(attr):Connect(refresh))
	end
	table.insert(conns, player:GetAttributeChangedSignal("Cash"):Connect(function()
		if root.Visible then
			refresh()
		end
	end))

	-- Önizlemeler yalnızca pencere açıkken dönüyor
	local angle = 0
	table.insert(conns, RunService.RenderStepped:Connect(function(dt)
		if not root.Visible then
			return
		end
		angle += dt * 0.9
		if current == "packs" then
			for _, spin in spins do
				local offset = Vector3.new(math.sin(angle) * 5.2, 0.8, math.cos(angle) * 5.2)
				spin.camera.CFrame = CFrame.lookAt(spin.center + offset, spin.center)
			end
			return
		end
		-- Alevler titreşiyor; ışıltılar aşağı akıyor; gökkuşağı renk değiştiriyor
		local t = os.clock()
		for i, card in flameCards do
			for k, layer in card.layers do
				local wob = math.sin(t * (13 + k * 3) + i) * 0.04 + math.sin(t * 7.3 + k) * 0.025
				local base = ({ 0.86, 0.66, 0.4 })[k]
				layer.Size = UDim2.fromScale(layer.Size.X.Scale, base * (1 + wob))
			end
			if card.def.rainbow then
				local a = Config.RainbowColor(t, i * 0.1)
				local b = Config.RainbowColor(t, 0.33 + i * 0.1)
				card.grads[1].Color = ColorSequence.new(b, b:Lerp(Color3.new(0, 0, 0), 0.3))
				card.grads[2].Color = ColorSequence.new(a, b)
			end
			for _, d in card.dots do
				local seed = d:GetAttribute("Seed") :: number
				local u = (t * 0.7 + seed) % 1
				d.Position = UDim2.fromScale(0.5 + math.sin(seed * 7 + t * 2) * 0.22 * u, 0.15 + u * 0.85)
				d.BackgroundTransparency = u
			end
		end
	end))

	close.Activated:Connect(function()
		root.Visible = false
	end)

	return {
		Open = function()
			root.Visible = true
			refresh()
		end,
		Destroy = function()
			for _, c in conns do
				c:Disconnect()
			end
			driver.destroy()
			root:Destroy()
		end,
	}
end

return JetpackPanel
