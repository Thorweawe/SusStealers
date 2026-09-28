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
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local JetpackModel = require(Shared.JetpackModel)
local Net = require(Shared.Net)

local UiKit = require(script.Parent.UiKit)

local JetpackPanel = {}

local player = Players.LocalPlayer

local ACCENT = Color3.fromRGB(80, 170, 255)
local ROBUX = Color3.fromRGB(60, 200, 110)
local Z = 45
local COLUMNS = 4

export type Panel = {
	Open: () -> (),
	Destroy: () -> (),
}

local function label(parent: Instance, text: string, font: Enum.Font, size: number, color: Color3, z: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.ZIndex = z
	l.Parent = parent
	return l
end

function JetpackPanel.Create(screen: ScreenGui): Panel
	local rows = math.ceil(#Config.Jetpacks / COLUMNS)
	local root = UiKit.Window(screen, "JetpackPanel", ACCENT)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(28 + COLUMNS * 168, 76 + rows * 250)
	root.Visible = false
	root.ZIndex = Z

	local band = Instance.new("Frame")
	band.Size = UDim2.new(1, 0, 0, 52)
	band.BackgroundColor3 = ACCENT:Lerp(Color3.new(0, 0, 0), 0.6)
	band.BorderSizePixel = 0
	band.ZIndex = Z + 1
	band.Parent = root
	UiKit.Corner(band, 14)
	local bandFoot = Instance.new("Frame")
	bandFoot.Position = UDim2.new(0, 0, 1, -14)
	bandFoot.Size = UDim2.new(1, 0, 0, 14)
	bandFoot.BackgroundColor3 = band.BackgroundColor3
	bandFoot.BorderSizePixel = 0
	bandFoot.ZIndex = Z + 1
	bandFoot.Parent = band

	local title = label(band, "🚀 JETPACKS", Enum.Font.GothamBlack, 22, Color3.new(1, 1, 1), Z + 2)
	title.Position = UDim2.fromOffset(16, 6)
	title.Size = UDim2.new(1, -320, 0, 26)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextStrokeTransparency = 0.5
	local hint = label(band, "Faster on the way out to the planets. Carrying crew home, you fly at your own speed.",
		Enum.Font.GothamMedium, 12, UiKit.MUTED, Z + 2)
	hint.Position = UDim2.fromOffset(16, 30)
	hint.Size = UDim2.new(1, -320, 0, 16)
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	hint.TextXAlignment = Enum.TextXAlignment.Left

	local close = UiKit.CloseButton(root)
	close.ZIndex = Z + 3

	-- Sekmeler: bandın sağında (kapatma düğmesinin solu)
	type Tab = { button: TextButton, text: TextLabel }
	local tabs: { [string]: Tab } = {}
	local function makeTab(id: string, text: string, order: number)
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -60 - (order - 1) * 118, 0.5, 0)
		b.Size = UDim2.fromOffset(110, 32)
		b.AutoButtonColor = false
		b.Text = ""
		b.ZIndex = Z + 3
		b.Parent = band
		UiKit.Corner(b, 10)
		UiKit.Stroke(b, Color3.fromRGB(12, 16, 28), 2, 0)
		local t = label(b, text, Enum.Font.GothamBlack, 14, Color3.new(1, 1, 1), Z + 4)
		t.Size = UDim2.fromScale(1, 1)
		tabs[id] = { button = b, text = t }
	end
	makeTab("flames", "🔥 FLAMES", 1)
	makeTab("packs", "🚀 PACKS", 2)

	local grid = Instance.new("Frame")
	grid.Name = "PackGrid"
	grid.Position = UDim2.fromOffset(14, 64)
	grid.Size = UDim2.new(1, -28, 1, -76)
	grid.BackgroundTransparency = 1
	grid.ZIndex = Z + 1
	grid.Parent = root
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / COLUMNS, -8, 1 / rows, -8)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	local actionRemote = Net.Get("JetpackAction")

	type Card = { def: Config.JetpackDef, button: TextButton, price: TextLabel, frame: Frame, stroke: UIStroke }
	local cards: { Card } = {}
	type Spin = { camera: Camera, center: Vector3 }
	local spins: { Spin } = {}

	for index, def in Config.Jetpacks do
		local card = Instance.new("Frame")
		card.LayoutOrder = index
		card.BackgroundColor3 = def.flame:Lerp(UiKit.ROW, 0.86)
		card.BorderSizePixel = 0
		card.ZIndex = Z + 2
		card.Parent = grid
		UiKit.Corner(card, 12)
		local stroke = UiKit.Stroke(card, def.flame, 1.4, 0.55)

		-- 3B önizleme
		local view = Instance.new("ViewportFrame")
		view.AnchorPoint = Vector2.new(0.5, 0)
		view.Position = UDim2.new(0.5, 0, 0, 8)
		view.Size = UDim2.new(1, -16, 0, 112)
		view.BackgroundColor3 = UiKit.SHELL_DEEP
		view.BackgroundTransparency = 0.1
		view.Ambient = Color3.fromRGB(170, 175, 195)
		view.LightColor = Color3.new(1, 1, 1)
		view.LightDirection = Vector3.new(-0.5, -1, -0.6)
		view.ZIndex = Z + 3
		view.Parent = card
		UiKit.Corner(view, 10)
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
			local tag = label(card, "ROBUX", Enum.Font.GothamBlack, 11, Color3.new(1, 1, 1), Z + 5)
			tag.AnchorPoint = Vector2.new(1, 0)
			tag.Position = UDim2.new(1, -12, 0, 12)
			tag.Size = UDim2.fromOffset(52, 18)
			tag.BackgroundTransparency = 0
			tag.BackgroundColor3 = ROBUX
			UiKit.Corner(tag, 6)
		end

		local name = label(card, def.name, Enum.Font.GothamBlack, 15, UiKit.INK, Z + 3)
		name.Position = UDim2.fromOffset(6, 124)
		name.Size = UDim2.new(1, -12, 0, 20)
		local boost = label(card, if def.boost > 1 then string.format("+%d%% flight speed", math.floor((def.boost - 1) * 100 + 0.5)) else "Standard issue",
			Enum.Font.GothamBold, 13, def.flame:Lerp(Color3.new(1, 1, 1), 0.3), Z + 3)
		boost.Position = UDim2.fromOffset(6, 146)
		boost.Size = UDim2.new(1, -12, 0, 18)
		local sub = label(card, "on the way out", Enum.Font.GothamMedium, 11, UiKit.MUTED, Z + 3)
		sub.Position = UDim2.fromOffset(6, 164)
		sub.Size = UDim2.new(1, -12, 0, 14)
		sub.Visible = def.boost > 1

		local holder, button = UiKit.Raised(card, "Buy", UiKit.CREW.GREEN:Lerp(UiKit.GOOD, 0.35), UDim2.new(1, -16, 0, 40), 10)
		holder.AnchorPoint = Vector2.new(0.5, 1)
		holder.Position = UDim2.new(0.5, 0, 1, -8)
		holder.ZIndex = Z + 3
		local price = label(button, "", Enum.Font.GothamBlack, 15, Color3.new(1, 1, 1), Z + 7)
		price.Size = UDim2.fromScale(1, 1)
		price.TextStrokeTransparency = 0.5

		local id = def.id
		button.MouseButton1Click:Connect(function()
			if not button.Active then
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
		table.insert(cards, { def = def, button = button, price = price, frame = card, stroke = stroke })
	end

	-- ─── Alevler ─────────────────────────────────────────────────────────
	local FLAME_COLUMNS = 5
	local flameRows = math.ceil(#Config.JetFlames / FLAME_COLUMNS)
	local flameGrid = Instance.new("Frame")
	flameGrid.Name = "FlameGrid"
	flameGrid.Position = UDim2.fromOffset(14, 64)
	flameGrid.Size = UDim2.new(1, -28, 1, -76)
	flameGrid.BackgroundTransparency = 1
	flameGrid.Visible = false
	flameGrid.ZIndex = Z + 1
	flameGrid.Parent = root
	local flameLayout = Instance.new("UIGridLayout")
	flameLayout.CellSize = UDim2.new(1 / FLAME_COLUMNS, -8, 1 / flameRows, -8)
	flameLayout.CellPadding = UDim2.fromOffset(8, 8)
	flameLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	flameLayout.SortOrder = Enum.SortOrder.LayoutOrder
	flameLayout.Parent = flameGrid

	type FlameCard = { def: Config.JetFlameDef, button: TextButton, price: TextLabel, stroke: UIStroke, layers: { Frame }, grads: { UIGradient }, dots: { Frame } }
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
		local card = Instance.new("Frame")
		card.LayoutOrder = index
		card.BackgroundColor3 = def.flame:Lerp(UiKit.ROW, 0.86)
		card.BorderSizePixel = 0
		card.ZIndex = Z + 2
		card.Parent = flameGrid
		UiKit.Corner(card, 12)
		local stroke = UiKit.Stroke(card, def.flame, 1.4, 0.55)

		local stage = Instance.new("Frame")
		stage.AnchorPoint = Vector2.new(0.5, 0)
		stage.Position = UDim2.new(0.5, 0, 0, 8)
		stage.Size = UDim2.new(1, -16, 0, 104)
		stage.BackgroundColor3 = Color3.fromRGB(10, 12, 26)
		stage.ClipsDescendants = true
		stage.ZIndex = Z + 3
		stage.Parent = card
		UiKit.Corner(stage, 10)
		local layers, grads, dots = drawFlame(stage, def)

		local tagText = if def.pass ~= nil then "ROBUX" elseif def.source == "season" then "SEASON" elseif def.source == "weekly" then "WEEKLY #1" else nil
		if tagText then
			local tag = label(card, tagText, Enum.Font.GothamBlack, 10, Color3.new(1, 1, 1), Z + 6)
			tag.AnchorPoint = Vector2.new(1, 0)
			tag.Position = UDim2.new(1, -12, 0, 12)
			tag.Size = UDim2.fromOffset(if tagText == "WEEKLY #1" then 64 else 52, 16)
			tag.BackgroundTransparency = 0
			tag.BackgroundColor3 = if def.pass ~= nil then ROBUX elseif def.source == "season" then Color3.fromRGB(170, 90, 255) else Color3.fromRGB(230, 170, 30)
			UiKit.Corner(tag, 6)
		end

		local name = label(card, def.name, Enum.Font.GothamBlack, 14, UiKit.INK, Z + 3)
		name.Position = UDim2.fromOffset(6, 114)
		name.Size = UDim2.new(1, -12, 0, 18)
		local blurb = label(card, def.blurb, Enum.Font.GothamMedium, 10, UiKit.MUTED, Z + 3)
		blurb.Position = UDim2.fromOffset(8, 134)
		blurb.Size = UDim2.new(1, -16, 0, 30)
		blurb.TextWrapped = true
		blurb.TextYAlignment = Enum.TextYAlignment.Top

		local holder, button = UiKit.Raised(card, "Buy", UiKit.CREW.GREEN:Lerp(UiKit.GOOD, 0.35), UDim2.new(1, -16, 0, 36), 10)
		holder.AnchorPoint = Vector2.new(0.5, 1)
		holder.Position = UDim2.new(0.5, 0, 1, -8)
		holder.ZIndex = Z + 3
		local price = label(button, "", Enum.Font.GothamBlack, 13, Color3.new(1, 1, 1), Z + 7)
		price.Size = UDim2.fromScale(1, 1)
		price.TextStrokeTransparency = 0.5

		local id = def.id
		button.MouseButton1Click:Connect(function()
			if not button.Active then
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
		table.insert(flameCards, { def = def, button = button, price = price, stroke = stroke, layers = layers, grads = grads, dots = dots })
	end

	local function paint(button: TextButton, base: Color3, dim: boolean)
		button.BackgroundColor3 = base
		button.BackgroundTransparency = if dim then 0.35 else 0
		local grad = button:FindFirstChildOfClass("UIGradient")
		if grad then
			grad.Color = ColorSequence.new(base:Lerp(Color3.new(1, 1, 1), 0.22), base:Lerp(Color3.new(0, 0, 0), 0.18))
		end
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
			card.stroke.Thickness = if isOn then 3 else 1.4
			card.stroke.Transparency = if isOn then 0 else 0.55
			if isOn then
				card.button.Active = false
				card.price.Text = "EQUIPPED"
				paint(card.button, UiKit.DIM, false)
			elseif owned[def.id] then
				card.button.Active = true
				card.price.Text = "EQUIP"
				paint(card.button, ACCENT, false)
			elseif def.pass ~= nil then
				local soon = def.pass <= 0
				card.button.Active = not soon
				card.price.Text = if soon then "SOON" else "R$ " .. tostring(def.robux or "?")
				paint(card.button, if soon then UiKit.DIM else ROBUX, soon)
			else
				card.button.Active = true
				card.price.Text = "$" .. Config.FormatCash(def.price)
				paint(card.button, UiKit.CREW.GREEN:Lerp(UiKit.GOOD, 0.35), cash < def.price)
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
			card.stroke.Thickness = if isOn then 3 else 1.4
			card.stroke.Transparency = if isOn then 0 else 0.55
			if isOn then
				card.button.Active = false
				card.price.Text = "EQUIPPED"
				paint(card.button, UiKit.DIM, false)
			elseif flamesOwned[def.id] then
				card.button.Active = true
				card.price.Text = "EQUIP"
				paint(card.button, ACCENT, false)
			elseif def.pass ~= nil then
				local soon = def.pass <= 0
				card.button.Active = not soon
				card.price.Text = if soon then "SOON" else "R$ " .. tostring(def.robux or "?")
				paint(card.button, if soon then UiKit.DIM else ROBUX, soon)
			elseif def.source == "season" then
				card.button.Active = false
				card.price.Text = "SEASON PASS"
				paint(card.button, Color3.fromRGB(120, 70, 200), true)
			elseif def.source == "weekly" then
				card.button.Active = false
				card.price.Text = "WIN A WEEK"
				paint(card.button, Color3.fromRGB(200, 150, 30), true)
			else
				card.button.Active = true
				card.price.Text = "$" .. Config.FormatCash(def.price)
				paint(card.button, UiKit.CREW.GREEN:Lerp(UiKit.GOOD, 0.35), cash < def.price)
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
			tab.button.BackgroundColor3 = if on then ACCENT else UiKit.ROW
			tab.text.TextColor3 = if on then Color3.new(1, 1, 1) else UiKit.MUTED
		end
		title.Text = if id == "packs" then "🚀 JETPACKS" else "🔥 JETPACK FLAMES"
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
				card.stroke.Color = a
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
			root:Destroy()
		end,
	}
end

return JetpackPanel
