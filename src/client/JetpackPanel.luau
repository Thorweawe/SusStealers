--!strict
--[[
	Jetpack dükkânı: Launch Bay'deki JETPACKS standının tezgâhında E'ye
	basınca açılıyor (prompt "JetpackPrompt", sunucu JetpackService kuruyor).

	Her jetpack bir kart (4×2): dönen 3B önizleme (ViewportFrame,
	shared/JetpackModel), ad, hız bonusu ve BUY / EQUIP / EQUIPPED. Robux
	jetpack'lerinde R$ fiyatı; pass kimliği henüz 0 ise "SOON". Fiyat ve
	sahiplik sunucuda; burası yalnızca "JetpackAction" gönderiyor ve
	"Jetpack" / "JetpacksOwned" niteliklerini okuyor.
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
	title.Size = UDim2.new(1, -100, 0, 26)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextStrokeTransparency = 0.5
	local hint = label(band, "Faster on the way out to the planets. Carrying crew home, you fly at your own speed.",
		Enum.Font.GothamMedium, 12, UiKit.MUTED, Z + 2)
	hint.Position = UDim2.fromOffset(16, 30)
	hint.Size = UDim2.new(1, -100, 0, 16)
	hint.TextXAlignment = Enum.TextXAlignment.Left

	local close = UiKit.CloseButton(root)
	close.ZIndex = Z + 3

	local grid = Instance.new("Frame")
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
	end

	local conns: { RBXScriptConnection } = {}
	for _, attr in { "JetpacksOwned", "Jetpack" } do
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
		for _, spin in spins do
			local offset = Vector3.new(math.sin(angle) * 5.2, 0.8, math.cos(angle) * 5.2)
			spin.camera.CFrame = CFrame.lookAt(spin.center + offset, spin.center)
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
