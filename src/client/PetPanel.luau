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

	--[[
		═══ KOLEKSİYON ═════════════════════════════════════════════════════

		Her kademe bir satır. Satırda önce SAHİP OLUNAN anahtarlar (düz ve
		mutasyonlu kopyalar ayrı kart), sonra henüz bulunmamış petler "???"
		olarak.

		Kartlar her güncellemede yeniden kuruluyor. Mutasyon gelince kart
		sayısı sabit değil (bir petin düzü ve Golden'ı iki kart) ve en kötü
		durumda birkaç düzine kart: yeniden kullanım tablosu tutmaya
		değmeyecek kadar ucuz.
	]]
	local fuseRemote = Net.Get("PetFuse")

	local owned: { [string]: number } = {}
	local equipped: { string } = {}

	-- Kart sırası: düz önce, sonra sıktan nadire (Golden, Crystal, Cosmic)
	local MUTATION_ORDER: { [string]: number } = { [""] = 0 }
	for index = #Config.PetMutations, 1, -1 do
		MUTATION_ORDER[Config.PetMutations[index].id] = #Config.PetMutations - index + 1
	end

	local rows: { Instance } = {}

	local function makeCard(parent: Instance, orderIndex: number, def: Config.PetDef, key: string?, count: number)
		local info = Config.Rarities[def.rarity]
		local isOn = key ~= nil and table.find(equipped, key) ~= nil

		--[[
			Açık if bloğu, if-ifadesi DEĞİL: `if k then f(k) else nil, nil`
			f'in yalnızca İLK dönüşünü alıyor ve mutasyon hep nil kalıyordu.
		]]
		local mutation: Config.PetMutationDef? = nil
		local income, speed = def.incomeBonus, def.speedBonus
		if key then
			local _, m = Config.ParsePetKey(key)
			mutation = m
			income, speed = Config.GetPetKeyBonus(key)
		end

		local card = Instance.new("TextButton")
		card.Name = key or def.id
		card.LayoutOrder = orderIndex
		card.BackgroundColor3 = UiKit.ROW
		card.BackgroundTransparency = if key then 0 else 0.45
		card.BorderSizePixel = 0
		card.AutoButtonColor = false
		card.Text = ""
		card.ZIndex = 43
		card.Parent = parent
		UiKit.Corner(card, 10)
		local stroke = UiKit.Stroke(card,
			if mutation then mutation.tint else info.color,
			if mutation then 2 else 1.4,
			if mutation then 0.2 else 0.75)

		--[[
			Figür: petin rengindeki mürettebat silueti. Mutasyonlu kopyada
			mutasyon rengi — Golden'ı düzünden ayıran ilk şey bu olmalı.
		]]
		local figure = Instance.new("Frame")
		figure.AnchorPoint = Vector2.new(0.5, 0)
		figure.Position = UDim2.new(0.5, 0, 0, 10)
		figure.Size = UDim2.fromOffset(34, 34)
		figure.BackgroundTransparency = 1
		figure.ZIndex = 44
		figure.Parent = card
		UiKit.Crewmate(figure, 30,
			if not key then UiKit.DIM elseif mutation then mutation.tint else def.color)

		local name = Instance.new("TextLabel")
		name.Position = UDim2.new(0, 4, 0, 46)
		name.Size = UDim2.new(1, -8, 0, 15)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.GothamBold
		name.TextSize = 11
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextColor3 = if key then UiKit.INK else UiKit.DIM
		name.Text = if key then def.name else "???"
		name.ZIndex = 44
		name.Parent = card

		-- Mutasyon adı ismin altında, kendi renginde
		local tag = Instance.new("TextLabel")
		tag.Position = UDim2.new(0, 4, 0, 60)
		tag.Size = UDim2.new(1, -8, 0, 12)
		tag.BackgroundTransparency = 1
		tag.Font = Enum.Font.GothamBlack
		tag.TextSize = 10
		tag.TextColor3 = if mutation then mutation.tint else UiKit.DIM
		tag.Text = if mutation then string.upper(mutation.name) .. string.format(" x%.1f", mutation.multiplier) else ""
		tag.ZIndex = 44
		tag.Parent = card

		--[[
			İstatistik sahip olunmasa da GÖRÜNÜYOR: neyi kaçırdığını
			bilmeden hedef olmuyor.
		]]
		local stat = Instance.new("TextLabel")
		stat.Position = UDim2.new(0, 4, 0, 72)
		stat.Size = UDim2.new(1, -8, 0, 26)
		stat.BackgroundTransparency = 1
		stat.Font = Enum.Font.GothamMedium
		stat.TextSize = 10
		stat.TextColor3 = if key then UiKit.MUTED else UiKit.DIM
		stat.Text = string.format("+%d%% cash\n+%.2f speed", math.floor(income * 100 + 0.5), speed)
		stat.ZIndex = 44
		stat.Parent = card

		if not key then
			return
		end

		-- Adet rozeti: sağ üstte, birden fazlası varken
		local countLabel = Instance.new("TextLabel")
		countLabel.AnchorPoint = Vector2.new(1, 0)
		countLabel.Position = UDim2.new(1, -6, 0, 6)
		countLabel.Size = UDim2.fromOffset(28, 14)
		countLabel.BackgroundTransparency = 1
		countLabel.Font = Enum.Font.GothamBlack
		countLabel.TextSize = 11
		countLabel.TextXAlignment = Enum.TextXAlignment.Right
		countLabel.TextColor3 = if isOn then GOOD else MUTED
		countLabel.Text = if count > 1 then "x" .. count else ""
		countLabel.ZIndex = 45
		countLabel.Parent = card

		-- Takılı işareti: alt kenarda yeşil şerit
		local mark = Instance.new("Frame")
		mark.AnchorPoint = Vector2.new(0.5, 1)
		mark.Position = UDim2.new(0.5, 0, 1, -4)
		mark.Size = UDim2.new(1, -16, 0, 3)
		mark.BackgroundColor3 = GOOD
		mark.BorderSizePixel = 0
		mark.Visible = isOn
		mark.ZIndex = 45
		mark.Parent = card
		UiKit.Corner(mark, 2)

		local k = key
		card.MouseButton1Click:Connect(function()
			-- Takılıysa çıkar, değilse tak: tek düğme, iki yön
			equipRemote:FireServer(k, not isOn)
		end)
		card.MouseEnter:Connect(function()
			stroke.Transparency = 0.1
		end)
		card.MouseLeave:Connect(function()
			stroke.Transparency = if mutation then 0.2 else 0.75
		end)

		--[[
			FUSE düğmesi yalnızca üç kopya varken ve üstünde bir kademe
			varken çıkıyor. Kartın sol üstünde, adet rozetinin karşısında:
			"x3" ile "FUSE" aynı bakışta okunsun.

			Ayrı bir düğme, kartın kendisi değil — kart tıklaması takıp
			çıkarıyor ve iki işi tek tıklamaya bağlamak kopyaları kazayla
			yakmak demekti.
		]]
		if count >= Config.PetFuseCount and Config.GetNextRarity(def.rarity) then
			local nextInfo = Config.Rarities[Config.GetNextRarity(def.rarity) :: string]
			local fuseHolder, fuse = UiKit.Raised(card, "Fuse", nextInfo.color, UDim2.fromOffset(40, 20), 6)
			fuseHolder.Position = UDim2.fromOffset(5, 5)
			fuseHolder.ZIndex = 46
			fuse.ZIndex = 47
			local fuseText = Instance.new("TextLabel")
			fuseText.Size = UDim2.fromScale(1, 1)
			fuseText.BackgroundTransparency = 1
			fuseText.Font = Enum.Font.GothamBlack
			fuseText.TextSize = 10
			fuseText.TextColor3 = Color3.new(1, 1, 1)
			fuseText.TextStrokeTransparency = 0.5
			fuseText.Text = "FUSE"
			fuseText.ZIndex = 48
			fuseText.Parent = fuse
			fuse.MouseButton1Click:Connect(function()
				fuseRemote:FireServer(k)
			end)
		end
	end

	local function redraw()
		for _, row in rows do
			row:Destroy()
		end
		table.clear(rows)

		local slotsUsed = #equipped
		local income, speed = Config.GetPetBonus(equipped)
		hint.Text = string.format("%d / %d equipped  ·  click to equip  ·  3 copies = FUSE", slotsUsed, Config.PetEquipSlots)
		if slotsUsed > 0 then
			hint.Text ..= string.format("  ·  +%d%% cash, +%.2f speed", math.floor(income * 100 + 0.5), speed)
		end

		local order = 0
		for _, tier in TIERS do
			local info = Config.Rarities[tier]

			-- Bu kademenin sahip olunan anahtarları ve hiç bulunmamış petleri
			type Slot = { def: Config.PetDef, key: string?, count: number }
			local slots: { Slot } = {}
			local found: { [string]: boolean } = {}

			for key, count in owned do
				local def = Config.ParsePetKey(key)
				if def and def.rarity == tier and count > 0 then
					table.insert(slots, { def = def, key = key, count = count })
					found[def.id] = true
				end
			end
			table.sort(slots, function(a, b)
				if a.def.id ~= b.def.id then
					return a.def.name < b.def.name
				end
				local _, ma = Config.ParsePetKey(a.key :: string)
				local _, mb = Config.ParsePetKey(b.key :: string)
				return (MUTATION_ORDER[if ma then ma.id else ""] or 0) < (MUTATION_ORDER[if mb then mb.id else ""] or 0)
			end)
			for _, def in Config.Pets do
				if def.rarity == tier and not found[def.id] then
					table.insert(slots, { def = def, key = nil, count = 0 })
				end
			end

			if #slots == 0 then
				continue
			end

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
			table.insert(rows, label)

			order += 1
			local row = Instance.new("Frame")
			row.LayoutOrder = order
			row.Size = UDim2.new(1, -6, 0, math.ceil(#slots / COLS) * (CARD_H + 6))
			row.BackgroundTransparency = 1
			row.ZIndex = 42
			row.Parent = list
			table.insert(rows, row)

			local grid = Instance.new("UIGridLayout")
			grid.CellSize = UDim2.fromOffset(CARD_W, CARD_H)
			grid.CellPadding = UDim2.fromOffset(6, 6)
			grid.SortOrder = Enum.SortOrder.LayoutOrder
			grid.Parent = row

			for index, slot in slots do
				makeCard(row, index, slot.def, slot.key, slot.count)
			end
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
		if overlay.Visible then
			redraw()
		end
	end)

	local cashConnection = player:GetAttributeChangedSignal("Cash"):Connect(refreshEggs)

	refreshEggs()

	close.Activated:Connect(function()
		overlay.Visible = false
	end)

	return {
		Toggle = function()
			overlay.Visible = not overlay.Visible
			-- Kapalıyken çizilmiyor (kartlar her seferinde yeniden kuruluyor);
			-- açılırken son veriyle çiz
			if overlay.Visible then
				refreshEggs()
				redraw()
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
