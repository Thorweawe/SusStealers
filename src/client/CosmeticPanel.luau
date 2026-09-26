--!strict
--[[
	Kozmetik mağazası: şapkalar ve izler (sunucu tarafı CosmeticService).

	Her kart: önizleme (şapkada dönen 3B model — başında göreceğinin aynısı,
	CosmeticModel), ad, nadirlik rengi ve durum düğmesi:
	  $fiyat   → satın al (sunucu parayı düşüp hemen takıyor)
	  EQUIP    → sahip olunanı tak
	  EQUIPPED → takılı; basınca çıkar

	Veriler oyuncu niteliklerinden: "CosmeticsOwned", "HatId", "TrailId".
	Düğme sağdaki menü dizisinde (STYLE).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local CosmeticModel = require(Shared.CosmeticModel)

local UiKit = require(script.Parent.UiKit)

local CosmeticPanel = {}

export type Panel = {
	Toggle: () -> (),
	Destroy: () -> (),
}

local Z = 30
local ACCENT = UiKit.CREW.PURPLE
local CARD_W, CARD_H = 150, 196

-- host verilirse Envanter'in STYLE sekmesine sayfa olarak kuruluyor (PetPanel ile aynı kalıp)
function CosmeticPanel.Create(screen: ScreenGui, host: Frame?): Panel
	local player = Players.LocalPlayer
	local remote = Net.Get("CosmeticAction")

	local root: Frame
	if host then
		root = UiKit.Page(host, "CosmeticPanel")
	else
		root = UiKit.Window(screen, "CosmeticPanel", ACCENT)
		root.AnchorPoint = Vector2.new(0.5, 0.5)
		root.Position = UDim2.fromScale(0.5, 0.5)
		root.Size = UDim2.fromOffset(560, 470)
	end
	root.Visible = false
	root.ZIndex = Z

	local title, sub = UiKit.Heading(root, "STYLE", ACCENT)
	title.ZIndex = Z + 2
	sub.ZIndex = Z + 2
	sub.Text = "Hats and trails for your crewmate. Everyone can see them."
	if not host then
		local close = UiKit.CloseButton(root)
		close.ZIndex = Z + 6
		close.MouseButton1Click:Connect(function()
			root.Visible = false
		end)
	end

	-- ─── Sekmeler ────────────────────────────────────────────────────────

	local kind = "hat"
	local tabs: { [string]: TextButton } = {}
	local function tabButton(name: string, text: string, x: number)
		local b = Instance.new("TextButton")
		b.AutoButtonColor = false
		b.Position = UDim2.fromOffset(x, 58)
		b.Size = UDim2.fromOffset(120, 32)
		b.BackgroundColor3 = UiKit.ROW
		b.BorderSizePixel = 0
		b.Font = Enum.Font.GothamBlack
		b.TextSize = 15
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = text
		b.ZIndex = Z + 2
		b.Parent = root
		UiKit.Corner(b, 10)
		tabs[name] = b
		return b
	end
	local hatTab = tabButton("hat", "HATS", 18)
	local trailTab = tabButton("trail", "TRAILS", 146)

	local list = Instance.new("ScrollingFrame")
	list.Name = "Grid"
	list.Position = UDim2.fromOffset(16, 100)
	list.Size = UDim2.new(1, -32, 1, -116)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = Z + 1
	list.Parent = root

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
	grid.CellPadding = UDim2.fromOffset(12, 12)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list

	-- Dönen önizlemeler: kart başına bir model, tek döngüden çevriliyor.
	-- Her model kendi merkezinin dikey ekseni etrafında dönüyor:
	-- center = sınır kutusunun ortası, offset = modelin merkeze göre ilk hali
	local spinning: { { model: Model, center: Vector3, offset: CFrame } } = {}
	local spinAngle = 0

	local function owned(): { [string]: boolean }
		local set = {}
		local raw = player:GetAttribute("CosmeticsOwned")
		if typeof(raw) == "string" then
			for id in string.gmatch(raw, "[^,]+") do
				set[id] = true
			end
		end
		return set
	end

	local function preview(card: Frame, def: Config.CosmeticDef)
		local vp = Instance.new("ViewportFrame")
		vp.Position = UDim2.fromOffset(8, 8)
		vp.Size = UDim2.new(1, -16, 0, 96)
		vp.BackgroundColor3 = UiKit.SHELL_DEEP
		vp.BorderSizePixel = 0
		vp.Ambient = Color3.fromRGB(180, 180, 190)
		vp.LightColor = Color3.new(1, 1, 1)
		vp.ZIndex = Z + 3
		vp.Parent = card
		UiKit.Corner(vp, 10)

		if def.kind == "hat" then
			local model = CosmeticModel.BuildHat(def.id, true)
			if model then
				model.Parent = vp
				local cf, size = model:GetBoundingBox()
				local cam = Instance.new("Camera")
				local dist = math.max(size.X, size.Y, size.Z) * 1.9 + 0.6
				cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0, dist * 0.35, dist), cf.Position)
				cam.FieldOfView = 40
				cam.Parent = vp
				vp.CurrentCamera = cam
				table.insert(spinning, { model = model, center = cf.Position, offset = CFrame.new(cf.Position):Inverse() * model:GetPivot() })
			end
		else
			-- İz: renk geçişli bir şerit
			local bar = Instance.new("Frame")
			bar.AnchorPoint = Vector2.new(0.5, 0.5)
			bar.Position = UDim2.fromScale(0.5, 0.5)
			bar.Size = UDim2.new(0.8, 0, 0, 18)
			bar.BackgroundColor3 = Color3.new(1, 1, 1)
			bar.BorderSizePixel = 0
			bar.ZIndex = Z + 4
			bar.Parent = vp
			UiKit.Corner(bar, 9)
			local grad = Instance.new("UIGradient")
			local colors = def.colors or { def.color, def.color }
			local keys = {}
			for i, c in colors do
				table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(1, #colors - 1), c))
			end
			if #keys == 1 then
				table.insert(keys, ColorSequenceKeypoint.new(1, colors[1]))
			end
			grad.Color = ColorSequence.new(keys)
			grad.Transparency = NumberSequence.new(0, 0.7)
			grad.Parent = bar
		end
	end

	local function redraw()
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		table.clear(spinning)
		for name, b in tabs do
			b.BackgroundColor3 = if name == kind then ACCENT else UiKit.ROW
		end

		local have = owned()
		local equipped = player:GetAttribute(if kind == "hat" then "HatId" else "TrailId")
		local cash = player:GetAttribute("Cash")
		cash = if typeof(cash) == "number" then cash else 0

		local order = 0
		for _, def in Config.Cosmetics do
			if def.kind ~= kind then
				continue
			end
			order += 1
			local rarity = Config.Rarities[def.rarity]
			local rarityColor = if rarity then rarity.color else UiKit.MUTED

			local card = Instance.new("Frame")
			card.Name = def.id
			card.LayoutOrder = order
			card.BackgroundColor3 = UiKit.ROW
			card.BorderSizePixel = 0
			card.ZIndex = Z + 2
			card.Parent = list
			UiKit.Corner(card, 12)
			UiKit.Stroke(card, rarityColor, 2, 0.2)

			preview(card, def)

			local name = Instance.new("TextLabel")
			name.Position = UDim2.fromOffset(8, 108)
			name.Size = UDim2.new(1, -16, 0, 20)
			name.BackgroundTransparency = 1
			name.Font = Enum.Font.GothamBlack
			name.TextSize = 14
			name.TextColor3 = Color3.new(1, 1, 1)
			name.TextScaled = false
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.Text = def.name
			name.ZIndex = Z + 3
			name.Parent = card

			local tag = Instance.new("TextLabel")
			tag.Position = UDim2.fromOffset(8, 127)
			tag.Size = UDim2.new(1, -16, 0, 14)
			tag.BackgroundTransparency = 1
			tag.Font = Enum.Font.GothamBold
			tag.TextSize = 12
			tag.TextColor3 = rarityColor
			tag.Text = string.upper(def.rarity)
			tag.ZIndex = Z + 3
			tag.Parent = card

			local isOwned = have[def.id] == true
			local isEquipped = equipped == def.id
			local color, text
			if isEquipped then
				color, text = UiKit.CREW.GREEN, "EQUIPPED"
			elseif isOwned then
				color, text = UiKit.CREW.BLUE, "EQUIP"
			else
				local affordable = cash >= def.price
				color = if affordable then UiKit.CREW.LIME:Lerp(Color3.new(0, 0, 0), 0.2) else Color3.fromRGB(90, 96, 108)
				text = "$" .. Config.FormatCash(def.price)
			end

			local button = Instance.new("TextButton")
			button.AnchorPoint = Vector2.new(0.5, 1)
			button.Position = UDim2.new(0.5, 0, 1, -8)
			button.Size = UDim2.new(1, -16, 0, 36)
			button.BackgroundColor3 = color
			button.BorderSizePixel = 0
			button.Font = Enum.Font.GothamBlack
			button.TextSize = 15
			button.TextColor3 = Color3.new(1, 1, 1)
			button.TextStrokeTransparency = 0.5
			button.Text = text
			button.ZIndex = Z + 4
			button.Parent = card
			UiKit.Corner(button, 10)

			button.MouseButton1Click:Connect(function()
				if isEquipped then
					remote:FireServer("unequip", def.kind)
				elseif isOwned then
					remote:FireServer("equip", def.id)
				else
					remote:FireServer("buy", def.id)
				end
			end)
		end
	end

	hatTab.MouseButton1Click:Connect(function()
		kind = "hat"
		redraw()
	end)
	trailTab.MouseButton1Click:Connect(function()
		kind = "trail"
		redraw()
	end)

	-- Sunucu nitelikleri değiştirince (alındı / takıldı) açıksa yeniden çiz
	local connections: { RBXScriptConnection } = {}
	for _, attr in { "CosmeticsOwned", "HatId", "TrailId" } do
		table.insert(connections, player:GetAttributeChangedSignal(attr):Connect(function()
			if root.Visible then
				redraw()
			end
		end))
	end

	table.insert(connections, RunService.RenderStepped:Connect(function(dt)
		if not root.Visible or #spinning == 0 then
			return
		end
		spinAngle += dt * 0.8
		for _, s in spinning do
			s.model:PivotTo(CFrame.new(s.center) * CFrame.Angles(0, spinAngle, 0) * s.offset)
		end
	end))

	return {
		Toggle = function()
			root.Visible = not root.Visible
			if root.Visible then
				redraw()
			end
		end,
		Destroy = function()
			for _, c in connections do
				c:Disconnect()
			end
			root:Destroy()
		end,
	}
end

return CosmeticPanel
