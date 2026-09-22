--!strict
-- Karakter indeksi: bütün karakterler, fiyatları, gelirleri, nadirlikleri.
--
-- Oyuncunun hedef listesi. Konveyörde ne çıkacağını bilmeden oynamak
-- "bakalım ne gelecek" oluyor; indeks "şunu istiyorum" yapıyor. Sahip
-- olduklarını işaretliyor, böylece koleksiyon hissi doğuyor.
--
-- Kalıcı "görüldü" kaydı sunucu işi olurdu; burada sahiplik anlık okunuyor
-- ve oturum boyunca görülenler hatırlanıyor. Kalıcılık gelirse burası
-- değişmeden çalışmaya devam eder.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local Index = {}

local player = Players.LocalPlayer

local PANEL = Color3.fromRGB(16, 18, 26)
local CARD = Color3.fromRGB(26, 30, 40)
local INK = Color3.fromRGB(235, 240, 250)
local MUTED = Color3.fromRGB(150, 163, 184)
local GOOD = Color3.fromRGB(120, 255, 150)

local COLS = 4
local CARD_W, CARD_H = 168, 92
local GAP = 10

export type Catalog = {
	Update: () -> (),
	--[[
		Sol kenardaki INDEX düğmesi bunu çağırıyor. C tuşu kaldı ama artık
		tek yol değil: dokunmatikte klavye yok ve panelin varlığı hiçbir
		yerde görünmüyordu.
	]]
	Toggle: () -> (),
}

type Card = {
	frame: Frame,
	owned: TextLabel,
	unitId: string,
}

function Index.Create(screen: ScreenGui): Catalog
	local holder = Instance.new("Frame")
	holder.Name = "UnitIndex"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(
		COLS * CARD_W + (COLS + 1) * GAP,
		math.ceil(#Config.Units / COLS) * (CARD_H + GAP) + GAP + 54
	)
	holder.BackgroundColor3 = PANEL
	holder.BackgroundTransparency = 0.06
	holder.BorderSizePixel = 0
	holder.Visible = false
	holder.ZIndex = 50
	holder.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = holder

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(GAP + 8, 12)
	title.Size = UDim2.new(1, -40, 0, 22)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 17
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = INK
	title.Text = "CREW INDEX"
	title.ZIndex = 51
	title.Parent = holder

	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(1, 0)
	hint.Position = UDim2.new(1, -GAP - 8, 0, 14)
	hint.Size = UDim2.fromOffset(160, 18)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 12
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.TextColor3 = MUTED
	hint.Text = "C to close"
	hint.ZIndex = 51
	hint.Parent = holder

	--[[
		Kartlar nadirlik sırasına göre diziliyor; Config.Units zaten o sırada
		ama sıralamayı burada garantiye alıyoruz ki Config'de sıra bozulursa
		indeks karışmasın.
	]]
	local sorted = table.clone(Config.Units)
	table.sort(sorted, function(a, b)
		local ra = Config.Rarities[a.rarity]
		local rb = Config.Rarities[b.rarity]
		if ra.order ~= rb.order then
			return ra.order < rb.order
		end
		return a.price < b.price
	end)

	local cards: { Card } = {}

	for i, def in sorted do
		local col = (i - 1) % COLS
		local row = math.floor((i - 1) / COLS)
		local rarity = Config.Rarities[def.rarity]

		local card = Instance.new("Frame")
		card.Name = def.id
		card.Position = UDim2.fromOffset(
			GAP + col * (CARD_W + GAP),
			54 + row * (CARD_H + GAP)
		)
		card.Size = UDim2.fromOffset(CARD_W, CARD_H)
		card.BackgroundColor3 = CARD
		card.BorderSizePixel = 0
		card.ZIndex = 51
		card.Parent = holder

		local cardCorner = Instance.new("UICorner")
		cardCorner.CornerRadius = UDim.new(0, 8)
		cardCorner.Parent = card

		-- Sol kenarda nadirlik şeridi: kartları taramadan kademeyi görürsün
		local stripe = Instance.new("Frame")
		stripe.Size = UDim2.new(0, 4, 1, 0)
		stripe.BackgroundColor3 = rarity.color
		stripe.BorderSizePixel = 0
		stripe.ZIndex = 52
		stripe.Parent = card

		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromOffset(14, 8)
		name.Size = UDim2.new(1, -24, 0, 18)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextSize = 13
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextColor3 = INK
		name.Text = def.name
		name.ZIndex = 52
		name.Parent = card

		local tier = Instance.new("TextLabel")
		tier.Position = UDim2.fromOffset(14, 26)
		tier.Size = UDim2.new(1, -24, 0, 14)
		tier.BackgroundTransparency = 1
		tier.Font = Enum.Font.GothamMedium
		tier.TextSize = 10
		tier.TextXAlignment = Enum.TextXAlignment.Left
		tier.TextColor3 = rarity.color
		tier.Text = string.upper(def.rarity)
		tier.ZIndex = 52
		tier.Parent = card

		local price = Instance.new("TextLabel")
		price.Position = UDim2.fromOffset(14, 46)
		price.Size = UDim2.new(1, -24, 0, 16)
		price.BackgroundTransparency = 1
		price.Font = Enum.Font.GothamMedium
		price.TextSize = 12
		price.TextXAlignment = Enum.TextXAlignment.Left
		price.TextColor3 = MUTED
		price.Text = "Cost  $" .. Config.FormatCash(def.price)
		price.ZIndex = 52
		price.Parent = card

		local income = Instance.new("TextLabel")
		income.Position = UDim2.fromOffset(14, 62)
		income.Size = UDim2.new(1, -24, 0, 16)
		income.BackgroundTransparency = 1
		income.Font = Enum.Font.GothamBold
		income.TextSize = 12
		income.TextXAlignment = Enum.TextXAlignment.Left
		income.TextColor3 = GOOD
		income.Text = "+$" .. Config.FormatCash(def.income) .. "/s"
		income.ZIndex = 52
		income.Parent = card

		-- Sahiplik işareti
		local owned = Instance.new("TextLabel")
		owned.AnchorPoint = Vector2.new(1, 1)
		owned.Position = UDim2.new(1, -8, 1, -8)
		owned.Size = UDim2.fromOffset(46, 18)
		owned.BackgroundTransparency = 1
		owned.Font = Enum.Font.GothamBold
		owned.TextSize = 12
		owned.TextXAlignment = Enum.TextXAlignment.Right
		owned.TextColor3 = MUTED
		owned.Text = ""
		owned.ZIndex = 52
		owned.Parent = card

		table.insert(cards, { frame = card, owned = owned, unitId = def.id })
	end

	-- ─── Açma / kapama ──────────────────────────────────────────────────────

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.C then
			return
		end
		holder.Visible = not holder.Visible
	end)

	-- ─── Güncelleme ─────────────────────────────────────────────────────────

	--[[ Oturum boyunca görülenler: konveyörde çıkan da sayılıyor, sadece
	     satın aldıkların değil. "Bunu gördüm ama alamadım" da bir hedef. ]]
	local seen: { [string]: boolean } = {}

	local function myPlot(): Model?
		local plots = workspace:FindFirstChild("Plots")
		if not plots then
			return nil
		end
		local wanted = string.upper(player.DisplayName)
		for _, plot in plots:GetChildren() do
			if plot:IsA("Model") then
				local sign = plot:FindFirstChild("Sign")
				local gui = sign and sign:FindFirstChild("OwnerLabel")
				local label = gui and gui:FindFirstChild("Text")
				if label and label:IsA("TextLabel") and label.Text == wanted then
					return plot
				end
			end
		end
		return nil
	end

	local function update()
		-- Konveyörde görünen her karakter "görüldü" sayılıyor
		local plots = workspace:FindFirstChild("Plots")
		if plots then
			for _, plot in plots:GetChildren() do
				local items = plot:FindFirstChild("Items")
				if items then
					for _, model in items:GetChildren() do
						local tag = model:FindFirstChild("UnitId")
						if tag and tag:IsA("StringValue") and tag.Value ~= "" then
							seen[tag.Value] = true
						end
					end
				end
			end
		end

		-- Kendi kaidelerimizde ne var
		local counts: { [string]: number } = {}
		local plot = myPlot()
		if plot then
			for _, podium in plot:GetDescendants() do
				if podium:IsA("BasePart") and podium.Name == "Podium" then
					local unitId = podium:GetAttribute("UnitId")
					if typeof(unitId) == "string" and unitId ~= "" then
						counts[unitId] = (counts[unitId] or 0) + 1
						seen[unitId] = true
					end
				end
			end
		end

		for _, card in cards do
			local n = counts[card.unitId]
			if n and n > 0 then
				card.owned.Text = "x" .. n
				card.owned.TextColor3 = GOOD
				card.frame.BackgroundTransparency = 0
			elseif seen[card.unitId] then
				card.owned.Text = "seen"
				card.owned.TextColor3 = MUTED
				card.frame.BackgroundTransparency = 0.25
			else
				card.owned.Text = ""
				card.frame.BackgroundTransparency = 0.5
			end
		end
	end

	return {
		Update = update,
		Toggle = function()
			holder.Visible = not holder.Visible
		end,
	}
end

return Index
