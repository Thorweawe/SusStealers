--!strict
--[[
	İndeks: iki sekme. CREW — bütün karakterler, nadirliğe göre; PETS —
	bütün petler, yumurtalarına göre (aşağıda "PETS: pet indeksi").
	Keşfedilenler açık, keşfedilmeyenler "???".

	═══ DÜZEN ══════════════════════════════════════════════════════════════

	Solda koleksiyon, sağda seçilen karakterin ayrıntısı. Eskisi dört
	sütunlu bir metin ızgarasıydı: her kartta beş satır yazı, ekranın
	tamamını kaplıyordu ve hiçbir şey öne çıkmıyordu.

	  Üst:  "Discovered 12 / 25" + tamamlanma çubuğu — koleksiyonun hedefi
	  Sekme: ALL + her nadirlik, kendi renginde. Sığmazsa yana kayıyor.
	  Liste: her nadirlik bir SATIR, satır yana kayıyor. Kartta yalnızca
	         figür, numara ve ad; sayılar sağdaki ayrıntıda.
	  Sağ:  büyük figür, nadirlik, fiyat, gelir, amorti süresi, sahiplik.

	═══ KEŞİF ══════════════════════════════════════════════════════════════

	Sunucuda tutuluyor (DataService.discovered) ve "Discovered" niteliğiyle
	geliyor. Kendi bandında gördüğün ya da kaidene konan her karakter
	giriyor ve kalıcı. Eskiden oturum boyunca istemcide tutuluyordu, her
	girişte sıfırlanıyordu.

	Keşfedilmemiş kartın NADİRLİĞİ görünüyor, adı ve figürü görünmüyor:
	"bu satırda bir şey eksik" bilgisi hedef veriyor, neyin eksik olduğu
	sürpriz kalıyor.

	2026-09-28: mağazanın dilinde (FancyKit kabuğu + jöle başlık, renkli
	kalın kenarlı kartlar, ayrıntıda dönen ışınlar ve hale, renkli
	sekmeler). Düzen ve mantık aynı.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PetModel = require(Shared.PetModel)

local FancyKit = require(script.Parent.FancyKit)
local UiArt = require(script.Parent.UiArt)
local UiKit = require(script.Parent.UiKit)
local OwnPlot = require(script.Parent.OwnPlot)

local Index = {}

local player = Players.LocalPlayer

export type Catalog = {
	Update: () -> (),
	--[[
		Sol kenardaki INDEX düğmesi bunu çağırıyor. C tuşu kaldı ama artık
		tek yol değil: dokunmatikte klavye yok.
	]]
	Toggle: () -> (),
	ShowPets: () -> (),
}

local Z = 50
local ACCENT = UiKit.CREW.CYAN
local SELECTED = Color3.fromRGB(255, 226, 60)
local TIERS = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret", "Celestial" }

local CARD_W, CARD_H = 100, 124
local ROW_H = CARD_H + 30

--[[
	Nadirlik rengi yazı/şerit için. Secret'ın kendi rengi neredeyse siyah
	(Config'te 30,30,40) ve koyu panelde görünmüyor; arayüzde onun yerine
	mor bir vurgu kullanılıyor.
]]
local function tierColor(rarity: string): Color3
	if rarity == "Secret" then
		return Color3.fromRGB(190, 150, 255)
	end
	local info = Config.Rarities[rarity]
	return if info then info.color else UiKit.MUTED
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = UiKit.INK
	text.TextXAlignment = Enum.TextXAlignment.Left
	for key, value in props do
		(text :: any)[key] = value
	end
	text.Parent = parent
	return text
end

--[[
	2026-09-28 (Yusuf): "index UI'ını değiştir, yazıları güzelleştir".
	Başlıklar ve adlar tombul yazı (FredokaOne) + koyu kontur; kademe
	başlıkları kendi renginde hap; kartların zemini kademe renginden
	aşağı koyulaşan degrade (keşfedilmemişte sönük).
]]
local OUTLINE = Color3.fromRGB(14, 16, 28)

local function pop(text: TextLabel, size: number, thickness: number?): TextLabel
	text.Font = Enum.Font.FredokaOne
	text.TextSize = size
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 1.6
	stroke.Color = OUTLINE
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = text
	return text
end

--[[ Kademe / yumurta başlığı: renkli hap, içinde beyaz tombul yazı. ]]
local function header(row: Frame, text: string, tone: Color3, z: number): TextLabel
	local pill = Instance.new("Frame")
	pill.Size = UDim2.fromOffset(0, 22)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundColor3 = tone:Lerp(Color3.new(0, 0, 0), 0.25)
	pill.BorderSizePixel = 0
	pill.ZIndex = z
	pill.Parent = row
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 11)
	c.Parent = pill
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(tone:Lerp(Color3.new(1, 1, 1), 0.15), tone:Lerp(Color3.new(0, 0, 0), 0.35))
	g.Rotation = 90
	g.Parent = pill
	local st = Instance.new("UIStroke")
	st.Thickness = 2
	st.Color = OUTLINE
	st.Parent = pill
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = pill
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(0, 1)
	l.AutomaticSize = Enum.AutomaticSize.X
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Text = text
	l.ZIndex = z + 1
	l.Parent = pill
	pop(l, 15, 1.8)
	return l
end

--[[ Kart zemini: kademe renginden koyuya degrade. ]]
local function tint(button: GuiObject, tone: Color3)
	button.BackgroundColor3 = Color3.new(1, 1, 1)
	local g = Instance.new("UIGradient")
	g.Name = "Tint"
	g.Color = ColorSequence.new(tone:Lerp(Color3.new(1, 1, 1), 0.08), tone:Lerp(Color3.new(0, 0, 0), 0.55))
	g.Rotation = 90
	g.Parent = button
	FancyKit.halftone(button, Color3.new(1, 1, 1), 0.82, button.ZIndex, true)
end

function Index.Create(screen: ScreenGui): Catalog
	local root = UiKit.Window(screen, "UnitIndex", ACCENT)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(820, 540)
	root.Visible = false
	root.ZIndex = Z

	-- ─── Başlık şeridi (FancyKit) ───────────────────────────────────────────

	local HEADER = 66
	local driver = FancyKit.driver(root)
	local shell = FancyKit.shell(root, "INDEX", {
		Color3.fromRGB(40, 200, 200), Color3.fromRGB(60, 150, 255), Color3.fromRGB(120, 230, 120),
	}, HEADER, Z, driver, 46)
	local band = shell.header
	local close = shell.close

	-- ─── Sol: ilerleme, sekmeler, liste ─────────────────────────────────────

	local LEFT_W = 520

	local left = Instance.new("Frame")
	left.Position = UDim2.fromOffset(16, HEADER + 12)
	left.Size = UDim2.new(0, LEFT_W, 1, -(HEADER + 26))
	left.BackgroundTransparency = 1
	left.ZIndex = Z + 1
	left.Parent = root

	local discovered = label(left, {
		Size = UDim2.new(0.6, 0, 0, 20), TextSize = 15, Font = Enum.Font.GothamBlack,
		Text = "Discovered 0 / " .. #Config.Units, TextColor3 = UiKit.CREW.LIME, ZIndex = Z + 2,
	})
	pop(discovered, 20, 2.2)
	local percent = label(left, {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.4, 0, 0, 20), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = UiKit.MUTED, Text = "0% complete", ZIndex = Z + 2,
	})
	pop(percent, 16, 1.8)

	local barHolder = Instance.new("Frame")
	barHolder.Position = UDim2.fromOffset(0, 24)
	barHolder.Size = UDim2.new(1, 0, 0, 8)
	barHolder.BackgroundTransparency = 1
	barHolder.ZIndex = Z + 2
	barHolder.Parent = left
	local track, fill = UiKit.Bar(barHolder, 8, UiKit.CREW.LIME)
	track.ZIndex = Z + 2
	fill.ZIndex = Z + 3

	--[[
		Nadirlik sekmeleri. Yedi kademe + ALL sekize çıkıyor ve dar ekranda
		sığmıyor; şerit YANA kayıyor.
	]]
	local tabStrip = Instance.new("ScrollingFrame")
	tabStrip.Position = UDim2.fromOffset(0, 40)
	tabStrip.Size = UDim2.new(1, 0, 0, 34)
	tabStrip.BackgroundTransparency = 1
	tabStrip.BorderSizePixel = 0
	tabStrip.ScrollBarThickness = 3
	tabStrip.ScrollBarImageColor3 = UiKit.MUTED
	tabStrip.ScrollingDirection = Enum.ScrollingDirection.X
	tabStrip.CanvasSize = UDim2.new()
	tabStrip.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabStrip.ZIndex = Z + 2
	tabStrip.Parent = left

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 6)
	tabLayout.Parent = tabStrip

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(0, 82)
	list.Size = UDim2.new(1, 0, 1, -82)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = UiKit.MUTED
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ZIndex = Z + 2
	list.Parent = left

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 6)
	listLayout.Parent = list

	-- ─── Sağ: ayrıntı ───────────────────────────────────────────────────────

	local detail = Instance.new("Frame")
	detail.AnchorPoint = Vector2.new(1, 0)
	detail.Position = UDim2.new(1, -16, 0, HEADER + 12)
	detail.Size = UDim2.new(1, -LEFT_W - 46, 1, -(HEADER + 26))
	detail.BackgroundColor3 = Color3.new(1, 1, 1)
	detail.BorderSizePixel = 0
	detail.ClipsDescendants = true
	detail.ZIndex = Z + 1
	detail.Parent = root
	UiKit.Corner(detail, 14)
	local detailGrad = FancyKit.gradient(detail, { Color3.fromRGB(40, 46, 72), Color3.fromRGB(18, 20, 34) }, 90)
	local detailStroke = UiKit.Stroke(detail, OUTLINE, 3, 0)
	-- Figürün arkasında ağır dönen ışınlar (nadirlik renginde)
	local detailRays = Instance.new("ImageLabel")
	detailRays.AnchorPoint = Vector2.new(0.5, 0.5)
	detailRays.Position = UDim2.new(0.5, 0, 0, 112)
	detailRays.Size = UDim2.fromOffset(360, 360)
	detailRays.BackgroundTransparency = 1
	detailRays.Image = UiArt.Image("Texture", "rays")
	detailRays.ImageTransparency = 0.55
	detailRays.ZIndex = Z + 1
	detailRays.Parent = detail
	FancyKit.spin(detailRays, driver, 9)
	FancyKit.halftone(detail, Color3.new(1, 1, 1), 0.88, Z + 1, true)

	local detailName = label(detail, {
		Position = UDim2.fromOffset(6, 8), Size = UDim2.new(1, -12, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Center, Font = Enum.Font.GothamBlack, TextSize = 18,
		TextScaled = false, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 2,
	})
	pop(detailName, 26, 2.6)

	local stage = Instance.new("Frame")
	stage.AnchorPoint = Vector2.new(0.5, 0)
	stage.Position = UDim2.new(0.5, 0, 0, 44)
	stage.Size = UDim2.fromOffset(136, 136)
	stage.BackgroundTransparency = 1
	stage.BorderSizePixel = 0
	stage.ZIndex = Z + 2
	stage.Parent = detail
	local stageGlow = FancyKit.glow(stage, ACCENT, 1.5, 0.25, Z + 2)
	-- Seçilenin nadirlik rengi: figürün arkasındaki hâle ve ışınlar
	local function paintStage(tone: Color3)
		stageGlow.ImageColor3 = tone
		detailRays.ImageColor3 = tone:Lerp(Color3.new(1, 1, 1), 0.4)
	end
	paintStage(ACCENT)

	local figureSlot = Instance.new("Frame")
	figureSlot.AnchorPoint = Vector2.new(0.5, 0.5)
	figureSlot.Position = UDim2.fromScale(0.5, 0.5)
	figureSlot.Size = UDim2.fromOffset(100, 100)
	figureSlot.BackgroundTransparency = 1
	figureSlot.ZIndex = Z + 3
	figureSlot.Parent = stage

	local statRows: { { key: TextLabel, value: TextLabel } } = {}
	for i = 1, 5 do
		local y = 196 + (i - 1) * 30
		local bg = Instance.new("Frame")
		bg.Position = UDim2.fromOffset(8, y - 1)
		bg.Size = UDim2.new(1, -16, 0, 26)
		bg.BackgroundColor3 = Color3.new(0, 0, 0)
		bg.BackgroundTransparency = if i % 2 == 1 then 0.45 else 0.65
		bg.BorderSizePixel = 0
		bg.ZIndex = Z + 1
		bg.Parent = detail
		UiKit.Corner(bg, 8)
		local key = label(detail, {
			Position = UDim2.fromOffset(16, y), Size = UDim2.new(0.5, -16, 0, 24),
			TextColor3 = Color3.fromRGB(200, 208, 235), ZIndex = Z + 2,
		})
		pop(key, 15, 1.6)
		local value = label(detail, {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, y),
			Size = UDim2.new(0.5, 0, 0, 24),
			TextXAlignment = Enum.TextXAlignment.Right, ZIndex = Z + 2,
		})
		pop(value, 16, 1.8)
		table.insert(statRows, { key = key, value = value })
	end

	local hint = label(detail, {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -10),
		Size = UDim2.new(1, -28, 0, 40), TextColor3 = UiKit.DIM, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = Z + 2,
	})
	pop(hint, 14, 1.6)

	-- ─── Kartlar ────────────────────────────────────────────────────────────

	--[[
		Numara sırası: nadirlik, sonra fiyat. Config.Units zaten böyle ama
		burada garanti ediyoruz ki Config'te sıra bozulursa numaralar
		karışmasın.
	]]
	local sorted = table.clone(Config.Units)
	table.sort(sorted, function(a, b)
		local ra, rb = Config.Rarities[a.rarity], Config.Rarities[b.rarity]
		if ra.order ~= rb.order then
			return ra.order < rb.order
		end
		return a.price < b.price
	end)

	type Card = {
		def: Config.UnitDef,
		number: number,
		button: TextButton,
		figure: Frame,
		name: TextLabel,
		count: TextLabel,
		stroke: UIStroke,
		known: boolean?,
	}
	local cards: { Card } = {}
	local rowsByTier: { [string]: Frame } = {}

	-- İndeks ödülü denetimleri (satır başına) ve toplama isteği
	type TierReward = { text: TextLabel, button: TextButton, bonus: number }
	local tierRewards: { [string]: TierReward } = {}

	local known: { [string]: boolean } = {}
	local owned: { [string]: number } = {}
	local selected: Card? = nil
	local filter = "ALL"

	local function drawFigure(slot: Frame, def: Config.UnitDef, isKnown: boolean, size: number)
		UiKit.ClearSlot(slot)
		-- Gerçek 3B model: rengi, şapkası ve kendine özel aksesuarı (UnitModel)
		if isKnown then
			UiKit.UnitIcon(slot, math.floor(size * 1.25), def.id)
		else
			-- Siluet: kademe renginin koyusu, üstünde soru işareti
			UiKit.UnitIcon(slot, math.floor(size * 1.25), def.id, tierColor(def.rarity):Lerp(Color3.new(0, 0, 0), 0.72))
			local q = Instance.new("TextLabel")
			q.Size = UDim2.fromScale(1, 1)
			q.BackgroundTransparency = 1
			q.Font = Enum.Font.GothamBlack
			q.TextSize = math.floor(size * 0.6)
			q.TextColor3 = tierColor(def.rarity)
			q.Text = "?"
			q.ZIndex = slot.ZIndex + 4
			q.Parent = slot
		end
	end

	-- Ayrıntı en son hangi hâlde çizildi; aynıysa yeniden çizilmiyor
	local shownState = ""

	local function showDetail(card: Card)
		selected = card
		local def = card.def
		local isKnown = known[def.id] == true
		local state = string.format("%s|%s|%d", def.id, tostring(isKnown), owned[def.id] or 0)
		if state == shownState then
			return
		end
		shownState = state
		local tone = tierColor(def.rarity)

		detailStroke.Color = tone
		paintStage(tone)
		detailName.Text = if isKnown then def.name else "???"
		detailName.TextColor3 = if isKnown then UiKit.INK else UiKit.DIM
		drawFigure(figureSlot, def, isKnown, 80)

		-- Konveyör yok: "Cost / Pays back" yerine değeri ve nereden çalınacağı
		-- (bu nadirliği veren ilk canavar: Steal an Egg tarzı "hangi yaratık")
		local source = "Events & wheel"
		for _, monster in Config.SpaceMonsters do
			-- Celestial: yalnızca kendi canavarı
			if (def.monster and monster.id == def.monster) or (not def.monster and monster.odds[def.rarity]) then
				source = monster.name
				break
			end
		end
		local values = {
			{ "Rarity", string.upper(def.rarity), tone },
			{ "Number", string.format("#%03d", card.number), UiKit.MUTED },
			{ "Value", if isKnown then "$" .. Config.FormatCash(def.price) else "???", UiKit.INK },
			{ "Income", if isKnown then "+$" .. Config.FormatCash(def.income) .. "/s" else "???", UiKit.CREW.LIME },
			{ "Steal from", source, UiKit.MUTED },
		}
		for i, row in statRows do
			local v = values[i]
			row.key.Text = v[1]
			row.value.Text = v[2]
			row.value.TextColor3 = v[3]
		end

		local have = owned[def.id] or 0
		hint.Text = if not isKnown then "Not discovered yet. Fly out and steal one from a space monster!"
			elseif have > 0 then string.format("You have %d on your podiums.", have)
			else "Discovered. Steal one from a space monster to own it."
		hint.TextColor3 = if have > 0 then UiKit.GOOD else UiKit.DIM

		for _, other in cards do
			other.stroke.Color = if other == card then SELECTED else OUTLINE
			other.stroke.Thickness = if other == card then 4 else 2.5
		end
	end

	local order = 0
	for _, tier in TIERS do
		local members = {}
		for i, def in sorted do
			if def.rarity == tier then
				table.insert(members, { def = def, number = i })
			end
		end
		if #members == 0 then
			continue
		end

		local tone = tierColor(tier)

		order += 1
		local row = Instance.new("Frame")
		row.Name = tier
		row.LayoutOrder = order
		row.Size = UDim2.new(1, -8, 0, ROW_H)
		row.BackgroundTransparency = 1
		row.ZIndex = Z + 2
		row.Parent = list
		rowsByTier[tier] = row

		header(row, string.upper(tier), tone, Z + 3)

		--[[
			İndeks ödülü: satırın sağında. Satır eksikse "3 / 4 · +2%",
			tamamsa CLAIM düğmesi, alındıysa yeşil tik. Kalıcı gelir
			bonusunu sunucu veriyor (RewardService.ClaimIndex).
		]]
		local reward = Config.IndexRewards[tier] or 0
		local progressText = label(row, {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0),
			Size = UDim2.fromOffset(160, 20), TextSize = 11, Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UiKit.MUTED, ZIndex = Z + 3,
		})
		local claimButton = Instance.new("TextButton")
		claimButton.AnchorPoint = Vector2.new(1, 0)
		claimButton.Position = UDim2.new(1, -6, 0, -1)
		claimButton.Size = UDim2.fromOffset(110, 20)
		claimButton.BackgroundColor3 = UiKit.CREW.GREEN:Lerp(UiKit.GOOD, 0.35)
		claimButton.BorderSizePixel = 0
		claimButton.AutoButtonColor = true
		claimButton.Font = Enum.Font.GothamBlack
		claimButton.TextSize = 11
		claimButton.TextColor3 = Color3.new(1, 1, 1)
		claimButton.Text = string.format("CLAIM +%d%%", math.floor(reward * 100 + 0.5))
		claimButton.Visible = false
		claimButton.ZIndex = Z + 4
		claimButton.Parent = row
		UiKit.Corner(claimButton, 6)
		local rewardTier = tier
		claimButton.MouseButton1Click:Connect(function()
			-- Remote tıklama anında alınıyor: indeks ana HUD akışında
			-- kuruluyor ve orada beklemek (WaitForChild) HUD'u durdururdu
			Net.Get("RewardClaim"):FireServer("index", rewardTier)
		end)
		tierRewards[tier] = { text = progressText, button = claimButton, bonus = reward }

		--[[ Satır yana kayıyor: kademeye ileride pet eklense de satır
		     taşmıyor, kaydırılıyor. ]]
		local strip = Instance.new("ScrollingFrame")
		strip.Position = UDim2.fromOffset(0, 22)
		strip.Size = UDim2.new(1, 0, 0, CARD_H + 8)
		strip.BackgroundTransparency = 1
		strip.BorderSizePixel = 0
		strip.ScrollBarThickness = 3
		strip.ScrollBarImageColor3 = tone
		strip.ScrollingDirection = Enum.ScrollingDirection.X
		strip.CanvasSize = UDim2.new()
		strip.AutomaticCanvasSize = Enum.AutomaticSize.X
		strip.ZIndex = Z + 3
		strip.Parent = row

		local stripLayout = Instance.new("UIListLayout")
		stripLayout.FillDirection = Enum.FillDirection.Horizontal
		stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
		stripLayout.Padding = UDim.new(0, 8)
		stripLayout.Parent = strip

		for position, member in members do
			local def = member.def

			local button = Instance.new("TextButton")
			button.LayoutOrder = position
			button.Size = UDim2.fromOffset(CARD_W, CARD_H)
			button.BackgroundColor3 = UiKit.ROW
			button.BorderSizePixel = 0
			button.AutoButtonColor = false
			button.Text = ""
			button.ZIndex = Z + 4
			button.Parent = strip
			UiKit.Corner(button, 10)
			tint(button, tone)
			local stroke = UiKit.Stroke(button, OUTLINE, 2.5, 0)

			-- Üstte nadirlik rengi şerit: satırı taramadan kademe okunuyor
			local cap = Instance.new("Frame")
			cap.Size = UDim2.new(1, 0, 0, 6)
			cap.BackgroundColor3 = tone
			cap.BorderSizePixel = 0
			cap.ZIndex = Z + 5
			cap.Parent = button
			UiKit.Corner(cap, 3)

			local figure = Instance.new("Frame")
			figure.AnchorPoint = Vector2.new(0.5, 0)
			figure.Position = UDim2.new(0.5, 0, 0, 14)
			figure.Size = UDim2.fromOffset(56, 56)
			figure.BackgroundTransparency = 1
			figure.ZIndex = Z + 5
			figure.Parent = button

			local name = label(button, {
				Position = UDim2.fromOffset(4, 74), Size = UDim2.new(1, -8, 0, 18),
				TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 5,
			})
			pop(name, 15, 1.8)

			label(button, {
				Position = UDim2.fromOffset(8, 94), Size = UDim2.new(0.5, 0, 0, 16),
				TextSize = 10, Font = Enum.Font.GothamBlack, TextColor3 = UiKit.DIM,
				Text = string.format("#%03d", member.number), ZIndex = Z + 5,
			})

			local count = label(button, {
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 94),
				Size = UDim2.new(0.5, 0, 0, 16), TextSize = 11, Font = Enum.Font.GothamBlack,
				TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UiKit.GOOD, ZIndex = Z + 5,
			})

			local card: Card = {
				def = def, number = member.number, button = button, figure = figure,
				name = name, count = count, stroke = stroke, known = nil,
			}
			table.insert(cards, card)

			button.MouseButton1Click:Connect(function()
				showDetail(card)
			end)
		end
	end

	-- ─── Sekmeler ───────────────────────────────────────────────────────────

	type Tab = { button: TextButton, stroke: UIStroke, tone: Color3, text: TextLabel }
	local tabs: { [string]: Tab } = {}

	local function applyFilter()
		for tier, row in rowsByTier do
			row.Visible = filter == "ALL" or filter == tier
		end
		for id, tab in tabs do
			local on = id == filter
			tab.button.BackgroundColor3 = if on then tab.tone else tab.tone:Lerp(Color3.fromRGB(30, 34, 52), 0.72)
			tab.stroke.Color = if on then Color3.new(1, 1, 1) else OUTLINE
			tab.stroke.Thickness = if on then 2.5 else 2
			tab.text.TextColor3 = Color3.new(1, 1, 1)
		end
		list.CanvasPosition = Vector2.zero
	end

	local tabIds = { "ALL" }
	for _, tier in TIERS do
		table.insert(tabIds, tier)
	end
	for i, id in tabIds do
		local tone = if id == "ALL" then ACCENT else tierColor(id)
		local button = Instance.new("TextButton")
		button.LayoutOrder = i
		button.Size = UDim2.fromOffset(0, 28)
		button.AutomaticSize = Enum.AutomaticSize.X
		button.BackgroundColor3 = UiKit.ROW
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Text = ""
		button.ZIndex = Z + 3
		button.Parent = tabStrip
		UiKit.Corner(button, 8)
		local stroke = UiKit.Stroke(button, OUTLINE, 2, 0)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = button
		local text = label(button, {
			Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X,
			TextColor3 = Color3.new(1, 1, 1), Text = string.upper(id), ZIndex = Z + 4,
		})
		pop(text, 14, 1.8)
		tabs[id] = { button = button, stroke = stroke, tone = tone, text = text }
		button.MouseButton1Click:Connect(function()
			filter = id
			applyFilter()
		end)
	end
	applyFilter()

	-- ─── Veri ───────────────────────────────────────────────────────────────

	local function readKnown()
		table.clear(known)
		local raw = player:GetAttribute("Discovered")
		if typeof(raw) == "string" then
			for id in string.gmatch(raw, "[^,]+") do
				known[id] = true
			end
		end
	end

	local function readOwned()
		table.clear(owned)
		local plot = OwnPlot.Get()
		if not plot then
			return
		end
		for _, podium in plot:GetDescendants() do
			if podium:IsA("BasePart") and podium.Name == "Podium" then
				local unitId = podium:GetAttribute("UnitId")
				if typeof(unitId) == "string" and unitId ~= "" then
					owned[unitId] = (owned[unitId] or 0) + 1
					-- Kaidedeki karakter keşfedilmiş sayılır (nitelik gecikse de)
					known[unitId] = true
				end
			end
		end
	end

	local function refresh()
		readKnown()
		readOwned()

		local found = 0
		for _, card in cards do
			local isKnown = known[card.def.id] == true
			if isKnown then
				found += 1
			end
			-- Figür yalnızca durum değişince yeniden çiziliyor
			if card.known ~= isKnown then
				card.known = isKnown
				drawFigure(card.figure, card.def, isKnown, 44)
				card.name.Text = if isKnown then card.def.name else "???"
				card.name.TextColor3 = if isKnown then UiKit.INK else UiKit.DIM
				card.button.BackgroundTransparency = if isKnown then 0 else 0.45
			end
			local have = owned[card.def.id] or 0
			card.count.Text = if have > 0 then "x" .. have else ""
		end

		local total = #cards
		discovered.Text = string.format("Discovered %d / %d", found, total)
		percent.Text = string.format("%d%% complete", math.floor(found / math.max(1, total) * 100 + 0.5))
		fill.Size = UDim2.new(found / math.max(1, total), 0, 1, 0)

		-- Satır ödülleri: toplananlar "IndexClaimed" niteliğinde (RewardService)
		local claimedSet: { [string]: boolean } = {}
		local rawClaimed = player:GetAttribute("IndexClaimed")
		if typeof(rawClaimed) == "string" then
			for id in string.gmatch(rawClaimed, "[^,]+") do
				claimedSet[id] = true
			end
		end
		for tier, reward in tierRewards do
			local have, need = 0, 0
			for _, card in cards do
				if card.def.rarity == tier then
					need += 1
					if known[card.def.id] then
						have += 1
					end
				end
			end
			local pct = math.floor(reward.bonus * 100 + 0.5)
			if claimedSet[tier] then
				reward.button.Visible = false
				reward.text.Text = string.format("✓ +%d%% income", pct)
				reward.text.TextColor3 = UiKit.GOOD
			elseif have >= need and need > 0 then
				reward.button.Visible = true
				reward.text.Text = ""
			else
				reward.button.Visible = false
				reward.text.Text = string.format("%d / %d  ·  +%d%% income", have, need, pct)
				reward.text.TextColor3 = UiKit.MUTED
			end
		end

		if selected then
			showDetail(selected)
		end
	end

	-- ─── PETS: pet indeksi ──────────────────────────────────────────────────
	--[[
		Bütün petler, yumurtalarına göre satır satır. Bir kez bile elde
		edilen (ya da otomatik silinen) pet açık, hiç bulunmayan "???"
		siluet. Veri sunucudan: Pets remote'unun `found` listesi (profildeki
		petsFound) ve `owned` sayıları. Envanterin PETS sayfası artık yalnızca
		eldeki petleri gösteriyor; "neler var" sorusunun cevabı burası.
	]]
	local mode = "crew"
	local petsFound: { [string]: boolean } = {}
	local petsOwned: { [string]: number } = {}

	local petLeft = Instance.new("Frame")
	petLeft.Position = left.Position
	petLeft.Size = left.Size
	petLeft.BackgroundTransparency = 1
	petLeft.Visible = false
	petLeft.ZIndex = Z + 1
	petLeft.Parent = root

	local petDiscovered = label(petLeft, {
		Size = UDim2.new(0.6, 0, 0, 20), TextSize = 15, Font = Enum.Font.GothamBlack,
		Text = "Discovered 0 / " .. #Config.Pets, TextColor3 = UiKit.CREW.PINK, ZIndex = Z + 2,
	})
	pop(petDiscovered, 20, 2.2)
	local petPercent = label(petLeft, {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0.4, 0, 0, 20), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = UiKit.MUTED, Text = "0% complete", ZIndex = Z + 2,
	})
	pop(petPercent, 16, 1.8)
	local petBarHolder = Instance.new("Frame")
	petBarHolder.Position = UDim2.fromOffset(0, 24)
	petBarHolder.Size = UDim2.new(1, 0, 0, 8)
	petBarHolder.BackgroundTransparency = 1
	petBarHolder.ZIndex = Z + 2
	petBarHolder.Parent = petLeft
	local petTrack, petFill = UiKit.Bar(petBarHolder, 8, UiKit.CREW.PINK)
	petTrack.ZIndex = Z + 2
	petFill.ZIndex = Z + 3

	local petList = Instance.new("ScrollingFrame")
	petList.Position = UDim2.fromOffset(0, 42)
	petList.Size = UDim2.new(1, 0, 1, -42)
	petList.BackgroundTransparency = 1
	petList.BorderSizePixel = 0
	petList.ScrollBarThickness = 4
	petList.ScrollBarImageColor3 = UiKit.MUTED
	petList.CanvasSize = UDim2.new()
	petList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	petList.ZIndex = Z + 2
	petList.Parent = petLeft
	local petLayout = Instance.new("UIListLayout")
	petLayout.SortOrder = Enum.SortOrder.LayoutOrder
	petLayout.Padding = UDim.new(0, 6)
	petLayout.Parent = petList

	local function eggTone(egg: Config.EggDef): Color3
		local t = egg.tint
		return if t.R + t.G + t.B < 0.5 then Color3.fromRGB(170, 120, 255) else t
	end

	type PetCard = { def: Config.PetDef, egg: Config.EggDef, number: number, button: TextButton, figure: Frame, name: TextLabel, count: TextLabel, stroke: UIStroke, known: boolean? }
	local petCards: { PetCard } = {}
	local selectedPet: PetCard? = nil

	local function drawPetFigure(slot: Frame, def: Config.PetDef, isKnown: boolean, size: number)
		UiKit.ClearSlot(slot)
		if isKnown then
			UiKit.PetIcon(slot, size, def.id)
		else
			UiKit.PetIcon(slot, size, def.id, tierColor(def.rarity):Lerp(Color3.new(0, 0, 0), 0.72))
			local q = Instance.new("TextLabel")
			q.Size = UDim2.fromScale(1, 1)
			q.BackgroundTransparency = 1
			q.Font = Enum.Font.GothamBlack
			q.TextSize = math.floor(size * 0.6)
			q.TextColor3 = tierColor(def.rarity)
			q.Text = "?"
			q.ZIndex = slot.ZIndex + 6
			q.Parent = slot
		end
	end


	local function showPetDetail(card: PetCard)
		selectedPet = card
		local def = card.def
		local isKnown = petsFound[def.id] == true
		local tone = tierColor(def.rarity)
		detailStroke.Color = tone
		paintStage(tone)
		detailName.Text = if isKnown then def.name else "???"
		detailName.TextColor3 = if isKnown then UiKit.INK else UiKit.DIM
		drawPetFigure(figureSlot, def, isKnown, 80)
		shownState = "" -- ekip ayrıntısına dönünce yeniden çizilsin

		-- Petin KENDİ şansı: kademede birden fazla pet var, kademe şansı bölünüyor
		local pct = Config.GetPetChance(card.egg.id, def.id)
		local values = {
			{ "Egg", string.upper(card.egg.name), eggTone(card.egg) },
			{ "Rarity", string.upper(def.rarity), tone },
			{ "Chance", if pct >= 1 then string.format("%.1f%%", pct) else string.format("%.2f%%", pct), UiKit.INK },
			{ "Cash bonus", if isKnown then string.format("+%.1f%%", def.incomeBonus * 100) else "???", UiKit.CREW.LIME },
			-- Rebirth petleri: son satırda yetenek (kaçış / şans), diğerlerinde uçuş hızı
			if def.escape then { "Monster slow", if isKnown then string.format("-%d%%", math.floor(def.escape * 100 + 0.5)) else "???", UiKit.CREW.CYAN }
			elseif def.luck then { "Lucky steal", if isKnown then string.format("+%.1f%%", def.luck * 100) else "???", UiKit.CREW.YELLOW }
			else { "Ability", if isKnown then "-" else "???", UiKit.CREW.CYAN },
		}
		for i, row in statRows do
			local v = values[i]
			row.key.Text = v[1]
			row.value.Text = v[2]
			row.value.TextColor3 = v[3]
		end
		local have = petsOwned[def.id] or 0
		hint.Text = if not isKnown then string.format("Not found yet. Hatch it from the %s!", card.egg.name)
			elseif have > 0 then string.format("You have %d in your inventory.", have)
			else "Found before. Hatch another to own it."
		hint.TextColor3 = if have > 0 then UiKit.GOOD else UiKit.DIM
		for _, other in petCards do
			other.stroke.Color = if other == card then SELECTED else OUTLINE
			other.stroke.Thickness = if other == card then 4 else 2.5
		end
	end

	do
		local number = 0
		for eggIndex, egg in Config.AllEggs() do
			local tone = eggTone(egg)
			local pets = Config.GetEggPets(egg.id)
			local row = Instance.new("Frame")
			row.Name = egg.id
			row.LayoutOrder = eggIndex
			row.Size = UDim2.new(1, -8, 0, ROW_H)
			row.BackgroundTransparency = 1
			row.ZIndex = Z + 2
			row.Parent = petList
			-- Sınırlı yumurta: fiyat etkinlik parasıyla ve "LIMITED" damgası
			local price = if egg.currency == "event"
				then string.format("LIMITED  ·  %s %d", Config.LimitedEvent.icon, egg.price)
				else "$" .. Config.FormatCash(egg.price)
			header(row, string.format("%s  ·  %s%s", string.upper(egg.name), price,
				if egg.rebirths then string.format("  ·  REBIRTH %d", egg.rebirths) else ""), tone, Z + 3)
			local strip = Instance.new("ScrollingFrame")
			strip.Position = UDim2.fromOffset(0, 22)
			strip.Size = UDim2.new(1, 0, 0, CARD_H + 8)
			strip.BackgroundTransparency = 1
			strip.BorderSizePixel = 0
			strip.ScrollBarThickness = 3
			strip.ScrollBarImageColor3 = tone
			strip.ScrollingDirection = Enum.ScrollingDirection.X
			strip.CanvasSize = UDim2.new()
			strip.AutomaticCanvasSize = Enum.AutomaticSize.X
			strip.ZIndex = Z + 3
			strip.Parent = row
			local sl = Instance.new("UIListLayout")
			sl.FillDirection = Enum.FillDirection.Horizontal
			sl.SortOrder = Enum.SortOrder.LayoutOrder
			sl.Padding = UDim.new(0, 8)
			sl.Parent = strip

			for position, def in pets do
				number += 1
				local rtone = tierColor(def.rarity)
				local button = Instance.new("TextButton")
				button.LayoutOrder = position
				button.Size = UDim2.fromOffset(CARD_W, CARD_H)
				button.BackgroundColor3 = UiKit.ROW
				button.BorderSizePixel = 0
				button.AutoButtonColor = false
				button.Text = ""
				button.ZIndex = Z + 4
				button.Parent = strip
				UiKit.Corner(button, 10)
				tint(button, rtone)
				local cstroke = UiKit.Stroke(button, OUTLINE, 2.5, 0)
				local cap = Instance.new("Frame")
				cap.Size = UDim2.new(1, 0, 0, 6)
				cap.BackgroundColor3 = rtone
				cap.BorderSizePixel = 0
				cap.ZIndex = Z + 5
				cap.Parent = button
				UiKit.Corner(cap, 3)
				local figure = Instance.new("Frame")
				figure.AnchorPoint = Vector2.new(0.5, 0)
				figure.Position = UDim2.new(0.5, 0, 0, 14)
				figure.Size = UDim2.fromOffset(56, 56)
				figure.BackgroundTransparency = 1
				figure.ZIndex = Z + 5
				figure.Parent = button
				local name = label(button, {
					Position = UDim2.fromOffset(4, 74), Size = UDim2.new(1, -8, 0, 18),
					TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center,
					TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = Z + 5,
				})
				pop(name, 15, 1.8)
				label(button, {
					Position = UDim2.fromOffset(8, 94), Size = UDim2.new(0.5, 0, 0, 16),
					TextSize = 10, Font = Enum.Font.GothamBlack, TextColor3 = rtone,
					Text = string.upper(string.sub(def.rarity, 1, 3)), ZIndex = Z + 5,
				})
				local count = label(button, {
					AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 94),
					Size = UDim2.new(0.5, 0, 0, 16), TextSize = 11, Font = Enum.Font.GothamBlack,
					TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = UiKit.GOOD, ZIndex = Z + 5,
				})
				local card: PetCard = { def = def, egg = egg, number = number, button = button, figure = figure, name = name, count = count, stroke = cstroke, known = nil }
				table.insert(petCards, card)
				button.MouseButton1Click:Connect(function()
					showPetDetail(card)
				end)
			end
		end
	end

	local function refreshPets()
		local foundCount = 0
		for _, card in petCards do
			local isKnown = petsFound[card.def.id] == true
			if isKnown then
				foundCount += 1
			end
			if card.known ~= isKnown then
				card.known = isKnown
				drawPetFigure(card.figure, card.def, isKnown, 44)
				card.name.Text = if isKnown then card.def.name else "???"
				card.name.TextColor3 = if isKnown then UiKit.INK else UiKit.DIM
				card.button.BackgroundTransparency = if isKnown then 0 else 0.45
			end
			local have = petsOwned[card.def.id] or 0
			card.count.Text = if have > 0 then "x" .. have else ""
		end
		local total = #petCards
		petDiscovered.Text = string.format("Discovered %d / %d", foundCount, total)
		petPercent.Text = string.format("%d%% complete", math.floor(foundCount / math.max(1, total) * 100 + 0.5))
		petFill.Size = UDim2.new(foundCount / math.max(1, total), 0, 1, 0)
		if mode == "pets" and selectedPet then
			showPetDetail(selectedPet)
		end
	end

	-- Arka planda: indeks ana HUD akışında kuruluyor, remote'u beklemek HUD'u durdurmasın
	task.spawn(function()
	Net.Get("Pets").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		table.clear(petsFound)
		table.clear(petsOwned)
		if typeof(payload.found) == "table" then
			for _, id in payload.found do
				if typeof(id) == "string" then
					petsFound[id] = true
				end
			end
		end
		if typeof(payload.owned) == "table" then
			for key, n in payload.owned do
				local def = typeof(key) == "string" and Config.ParsePetKey(key) or nil
				if def and typeof(n) == "number" then
					petsOwned[def.id] = (petsOwned[def.id] or 0) + n
					petsFound[def.id] = true
				end
			end
		end
		refreshPets()
	end)
	end)

	-- Başlık bandında CREW / PETS anahtarı
	local switch = Instance.new("Frame")
	switch.AnchorPoint = Vector2.new(1, 0.5)
	switch.Position = UDim2.new(1, -74, 0.5, 0)
	switch.Size = UDim2.fromOffset(220, 42)
	switch.BackgroundColor3 = Color3.fromRGB(16, 18, 30)
	switch.BackgroundTransparency = 0.25
	switch.ZIndex = Z + 6
	switch.Parent = band
	UiKit.Corner(switch, 21)
	UiKit.Stroke(switch, OUTLINE, 3, 0)
	local modeButtons: { [string]: TextButton } = {}
	local function setMode(m: string)
		mode = m
		left.Visible = m == "crew"
		petLeft.Visible = m == "pets"
		for id, b in modeButtons do
			local on = id == m
			b.BackgroundColor3 = if on then (if id == "crew" then Color3.fromRGB(60, 200, 90) else UiKit.CREW.PINK) else Color3.fromRGB(16, 18, 30)
			b.BackgroundTransparency = if on then 0 else 1
			b.TextColor3 = if on then Color3.new(1, 1, 1) else UiKit.MUTED
		end
		if m == "pets" then
			refreshPets()
			if selectedPet or petCards[1] then
				showPetDetail((selectedPet or petCards[1]) :: PetCard)
			end
		else
			refresh()
			if selected then
				shownState = ""
				showDetail(selected)
			elseif cards[1] then
				showDetail(cards[1])
			end
		end
	end
	for i, id in { "crew", "pets" } do
		local b = Instance.new("TextButton")
		b.Position = UDim2.new((i - 1) * 0.5, 3, 0, 3)
		b.Size = UDim2.new(0.5, -6, 1, -6)
		b.AutoButtonColor = false
		b.Font = Enum.Font.FredokaOne
		b.TextSize = 20
		b.Text = string.upper(id)
		b.ZIndex = Z + 7
		b.Parent = switch
		UiKit.Corner(b, 18)
		local bs = Instance.new("UIStroke")
		bs.Color = OUTLINE
		bs.Thickness = 2
		bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		bs.Parent = b
		modeButtons[id] = b
		b.MouseButton1Click:Connect(function()
			setMode(id)
		end)
	end

	-- ─── Açma / kapama ──────────────────────────────────────────────────────

	local function toggle()
		root.Visible = not root.Visible
		if root.Visible then
			setMode(mode)
		end
	end

	close.Activated:Connect(function()
		root.Visible = false
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.KeyCode ~= Enum.KeyCode.C then
			return
		end
		toggle()
	end)

	return {
		-- Ana döngü 0.2 sn'de bir çağırıyor; kapalıyken iş yapmıyor
		Update = function()
			-- PETS sekmesi Pets remote'uyla tazeleniyor; ekip ayrıntısını üstüne yazmasın
			if root.Visible and mode == "crew" then
				refresh()
			end
		end,
		Toggle = toggle,
		-- Pencereyi PETS sekmesinde açar (Studio önizlemesi, ileride kısayol)
		ShowPets = function()
			root.Visible = true
			setMode("pets")
		end,
	}
end

return Index
