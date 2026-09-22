--!strict
--[[
	Pet paneli: yumurtalar ve koleksiyon.

	İki sekme değil TEK ekran: üstte yumurtalar, altta sahip olunanlar.
	Ayrı sekme olsaydı oyuncu yumurtayı açıp ne çıktığını görmek için
	sekme değiştirmek zorunda kalırdı — kazanma anı ile koleksiyonu
	görmek arasına bir tık girerdi.

	Karar sunucuda: PetService hem fiyatı hem çekilişi hem de slot
	sayısını doğruluyor. Buradan giden tek şey bir kimlik.

	Sahip olunmayan petler de GÖRÜNÜYOR, sönük ve "???" olarak. Hedef
	listesi olmadan koleksiyon sadece bir envanter; neyin eksik olduğunu
	görmek onu koleksiyon yapıyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local UiKit = require(script.Parent.UiKit)

local PetPanel = {}

local player = Players.LocalPlayer

local INK = UiKit.INK
local MUTED = UiKit.MUTED
local ACCENT = UiKit.CREW.PINK
local GOOD = UiKit.GOOD

export type Panel = {
	Toggle: () -> (),
	Destroy: () -> (),
}

local COLS = 5
local CARD_W, CARD_H = 96, 108

--[[
	Kademe sırası. Config.Rarities sözlük, yani sırasız; koleksiyon her
	açılışta farklı dizilseydi oyuncu aradığını bulamazdı.
]]
local TIERS = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

function PetPanel.Create(screen: ScreenGui): Panel
	local overlay = UiKit.Shell(screen, "PetPanel", ACCENT)
	overlay.AnchorPoint = Vector2.new(0.5, 0.5)
	overlay.Position = UDim2.fromScale(0.5, 0.5)
	overlay.Size = UDim2.fromOffset(580, 520)
	overlay.Visible = false
	overlay.ZIndex = 40

	local badge = Instance.new("Frame")
	badge.Position = UDim2.fromOffset(18, 14)
	badge.Size = UDim2.fromOffset(30, 30)
	badge.BackgroundTransparency = 1
	badge.ZIndex = 41
	badge.Parent = overlay
	UiKit.Crewmate(badge, 24, ACCENT)

	local heading = Instance.new("TextLabel")
	heading.Position = UDim2.fromOffset(56, 12)
	heading.Size = UDim2.new(1, -100, 0, 24)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBlack
	heading.TextSize = 20
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.TextColor3 = ACCENT
	heading.Text = "PETS"
	heading.ZIndex = 41
	heading.Parent = overlay

	local hint = Instance.new("TextLabel")
	hint.Position = UDim2.fromOffset(56, 34)
	hint.Size = UDim2.new(1, -100, 0, 16)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 12
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = MUTED
	hint.Text = ""
	hint.ZIndex = 41
	hint.Parent = overlay

	local close = UiKit.CloseButton(overlay)
	close.ZIndex = 41

	local hatchRemote = Net.Get("PetHatch")
	local equipRemote = Net.Get("PetEquip")

	-- ─── Yumurtalar ─────────────────────────────────────────────────────────

	local eggRow = Instance.new("Frame")
	eggRow.Name = "Eggs"
	eggRow.Position = UDim2.fromOffset(14, 60)
	eggRow.Size = UDim2.new(1, -28, 0, 70)
	eggRow.BackgroundTransparency = 1
	eggRow.ZIndex = 41
	eggRow.Parent = overlay

	local eggLayout = Instance.new("UIListLayout")
	eggLayout.FillDirection = Enum.FillDirection.Horizontal
	eggLayout.SortOrder = Enum.SortOrder.LayoutOrder
	eggLayout.Padding = UDim.new(0, 8)
	eggLayout.Parent = eggRow

	--[[
		Yumurtanın rengi havuzunun EN İYİ kademesinden geliyor. Oyuncu dört
		kutudan hangisinin daha değerli olduğunu fiyatı okumadan görüyor.
	]]
	local function eggTint(egg: Config.EggDef): Color3
		local best, bestOrder = ACCENT, 0
		for rarity in egg.weights do
			local info = Config.Rarities[rarity]
			if info and info.order > bestOrder then
				best, bestOrder = info.color, info.order
			end
		end
		return best
	end

	type EggCard = { def: Config.EggDef, price: TextLabel, button: TextButton }
	local eggCards: { EggCard } = {}

	for index, egg in Config.Eggs do
		local tint = eggTint(egg)
		local holder, button = UiKit.Raised(eggRow, egg.id, tint, UDim2.fromOffset(130, 66), 12)
		holder.LayoutOrder = index
		holder.ZIndex = 41

		local slot = Instance.new("Frame")
		slot.AnchorPoint = Vector2.new(0, 0.5)
		slot.Position = UDim2.new(0, 8, 0.5, 0)
		slot.Size = UDim2.fromOffset(34, 34)
		slot.BackgroundTransparency = 1
		slot.ZIndex = 44
		slot.Parent = button
		-- Yumurtanın rengi havuzunun en iyi kademesinden; açık tonu
		-- kullanıyoruz ki düğmenin kendi dolgusunun içinde kaybolmasın
		UiKit.Egg(slot, 32, tint:Lerp(Color3.new(1, 1, 1), 0.55))

		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromOffset(46, 12)
		name.Size = UDim2.new(1, -52, 0, 18)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBlack
		name.TextSize = 13
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = Color3.new(1, 1, 1)
		name.TextStrokeTransparency = 0.5
		name.Text = string.upper(string.gsub(egg.name, " Egg", ""))
		name.ZIndex = 45
		name.Parent = button

		local price = Instance.new("TextLabel")
		price.Position = UDim2.fromOffset(46, 32)
		price.Size = UDim2.new(1, -52, 0, 18)
		price.BackgroundTransparency = 1
		price.Font = Enum.Font.GothamBold
		price.TextSize = 12
		price.TextXAlignment = Enum.TextXAlignment.Left
		price.TextColor3 = Color3.new(1, 1, 1)
		price.TextStrokeTransparency = 0.6
		price.Text = "$" .. Config.FormatCash(egg.price)
		price.ZIndex = 45
		price.Parent = button

		local id = egg.id
		button.MouseButton1Click:Connect(function()
			hatchRemote:FireServer(id)
		end)

		table.insert(eggCards, { def = egg, price = price, button = button })
	end

	-- ─── Koleksiyon ─────────────────────────────────────────────────────────

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(14, 138)
	list.Size = UDim2.new(1, -28, 1, -152)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = MUTED
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ZIndex = 41
	list.Parent = overlay

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = list

	type Card = {
		def: Config.PetDef,
		frame: TextButton,
		figure: Frame,
		name: TextLabel,
		stat: TextLabel,
		count: TextLabel,
		mark: Frame,
	}
	local cards: { [string]: Card } = {}
	local order = 0

	for _, tier in TIERS do
		local members = {}
		for _, def in Config.Pets do
			if def.rarity == tier then
				table.insert(members, def)
			end
		end
		if #members == 0 then
			continue
		end

		local info = Config.Rarities[tier]

		order += 1
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.Size = UDim2.new(1, -6, 0, 24)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextSize = 12
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = info.color
		label.Text = string.upper(tier)
		label.ZIndex = 42
		label.Parent = list

		order += 1
		local row = Instance.new("Frame")
		row.LayoutOrder = order
		row.Size = UDim2.new(1, -6, 0, math.ceil(#members / COLS) * (CARD_H + 6))
		row.BackgroundTransparency = 1
		row.ZIndex = 42
		row.Parent = list

		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
		grid.CellPadding = UDim2.fromOffset(6, 6)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = row

		for cellIndex, def in members do
			local card = Instance.new("TextButton")
			card.Name = def.id
			card.LayoutOrder = cellIndex
			card.BackgroundColor3 = UiKit.ROW
			card.BorderSizePixel = 0
			card.AutoButtonColor = false
			card.Text = ""
			card.ZIndex = 43
			card.Parent = row
			UiKit.Corner(card, 10)
			local stroke = UiKit.Stroke(card, info.color, 1.4, 0.75)

			--[[
				Figür: petin kendi renginde mürettebat silueti. 3B modelin
				biçimini (orb, bot, crab...) arayüzde tekrarlamak yirmi ayrı
				çizim demekti; siluet + RENK zaten hangi pet olduğunu
				söylüyor ve panel tek bir dilde kalıyor.
			]]
			local figure = Instance.new("Frame")
			figure.Name = "Figure"
			figure.AnchorPoint = Vector2.new(0.5, 0)
			figure.Position = UDim2.new(0.5, 0, 0, 10)
			figure.Size = UDim2.fromOffset(34, 34)
			figure.BackgroundTransparency = 1
			figure.ZIndex = 44
			figure.Parent = card

			local name = Instance.new("TextLabel")
			name.Position = UDim2.new(0, 4, 0, 48)
			name.Size = UDim2.new(1, -8, 0, 16)
			name.BackgroundTransparency = 1
			name.Font = Enum.Font.GothamBold
			name.TextSize = 11
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.TextColor3 = INK
			name.Text = def.name
			name.ZIndex = 44
			name.Parent = card

			local stat = Instance.new("TextLabel")
			stat.Position = UDim2.new(0, 4, 0, 64)
			stat.Size = UDim2.new(1, -8, 0, 28)
			stat.BackgroundTransparency = 1
			stat.Font = Enum.Font.GothamMedium
			stat.TextSize = 10
			stat.TextColor3 = MUTED
			stat.RichText = true
			stat.Text = string.format(
				"+%d%% cash\n+%.2f speed", math.floor(def.incomeBonus * 100), def.speedBonus)
			stat.ZIndex = 44
			stat.Parent = card

			-- Adet rozeti: sağ üstte, yalnızca birden fazlası varken
			local count = Instance.new("TextLabel")
			count.AnchorPoint = Vector2.new(1, 0)
			count.Position = UDim2.new(1, -6, 0, 6)
			count.Size = UDim2.fromOffset(28, 14)
			count.BackgroundTransparency = 1
			count.Font = Enum.Font.GothamBlack
			count.TextSize = 11
			count.TextXAlignment = Enum.TextXAlignment.Right
			count.TextColor3 = MUTED
			count.Text = ""
			count.ZIndex = 45
			count.Parent = card

			-- Takılı işareti: alt kenarda kademe renginde şerit
			local mark = Instance.new("Frame")
			mark.AnchorPoint = Vector2.new(0.5, 1)
			mark.Position = UDim2.new(0.5, 0, 1, -4)
			mark.Size = UDim2.new(1, -16, 0, 3)
			mark.BackgroundColor3 = GOOD
			mark.BorderSizePixel = 0
			mark.Visible = false
			mark.ZIndex = 45
			mark.Parent = card
			UiKit.Corner(mark, 2)

			cards[def.id] = {
				def = def, frame = card, figure = figure,
				name = name, stat = stat, count = count, mark = mark,
			}

			local id = def.id
			card.MouseButton1Click:Connect(function()
				-- Takılıysa çıkar, değilse tak: tek düğme, iki yön
				equipRemote:FireServer(id, cards[id].mark.Visible == false)
			end)

			card.MouseEnter:Connect(function()
				stroke.Transparency = 0.2
			end)
			card.MouseLeave:Connect(function()
				stroke.Transparency = 0.75
			end)
		end
	end

	-- ─── Veri ───────────────────────────────────────────────────────────────

	local owned: { [string]: number } = {}
	local equipped: { string } = {}

	local function redraw()
		local slotsUsed = #equipped
		hint.Text = string.format(
			"%d / %d equipped  ·  click a pet to equip or remove",
			slotsUsed, Config.PetEquipSlots)

		local income, speed = Config.GetPetBonus(equipped)
		if slotsUsed > 0 then
			hint.Text ..= string.format("  ·  +%d%% cash, +%.2f speed",
				math.floor(income * 100), speed)
		end

		for id, card in cards do
			local have = owned[id] or 0
			local isOn = table.find(equipped, id) ~= nil

			UiKit.ClearSlot(card.figure)

			if have > 0 then
				UiKit.Crewmate(card.figure, 30, card.def.color)
				card.name.Text = card.def.name
				card.name.TextColor3 = INK
				card.stat.TextColor3 = MUTED
				card.frame.BackgroundTransparency = 0
				card.count.Text = if have > 1 then "x" .. have else ""
			else
				--[[
					Sahip olunmayan pet: sönük siluet ve gizli ad. İstatistik
					GÖRÜNÜYOR — neyi kaçırdığını bilmeden hedef olmuyor.
				]]
				UiKit.Crewmate(card.figure, 30, UiKit.DIM)
				card.name.Text = "???"
				card.name.TextColor3 = UiKit.DIM
				card.stat.TextColor3 = UiKit.DIM
				card.frame.BackgroundTransparency = 0.45
				card.count.Text = ""
			end

			card.mark.Visible = isOn
			card.count.TextColor3 = if isOn then GOOD else MUTED
		end
	end

	--[[
		Yumurta düğmeleri parası yetmeyende sönük. Tıklama yine gidiyor ve
		sunucu reddediyor — istemcide engellemek yanlış bir güven olurdu,
		bu yalnızca görsel bir uyarı.
	]]
	local function refreshEggs()
		local cash = player:GetAttribute("Cash") :: number?
		for _, card in eggCards do
			local afford = (cash or 0) >= card.def.price
			card.button.BackgroundTransparency = if afford then 0 else 0.45
			card.price.TextTransparency = if afford then 0 else 0.35
		end
	end

	local petsConnection = Net.Get("Pets").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		owned = if typeof(payload.owned) == "table" then payload.owned else {}
		equipped = if typeof(payload.equipped) == "table" then payload.equipped else {}
		redraw()
	end)

	local cashConnection = player:GetAttributeChangedSignal("Cash"):Connect(refreshEggs)

	redraw()
	refreshEggs()

	close.Activated:Connect(function()
		overlay.Visible = false
	end)

	return {
		Toggle = function()
			overlay.Visible = not overlay.Visible
			if overlay.Visible then
				refreshEggs()
			end
		end,
		Destroy = function()
			petsConnection:Disconnect()
			cashConnection:Disconnect()
			overlay:Destroy()
		end,
	}
end

return PetPanel
