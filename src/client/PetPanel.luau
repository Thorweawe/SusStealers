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

	İkinci hâli: BİRLEŞTİRME MAKİNESİ (OpenFuse). Kuluçkahanedeki makinede
	E'ye basınca aynı pencere açılıyor ama yalnızca üç kopyası olan petler
	ve büyük FUSE düğmeleriyle.
]]

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PetModel = require(Shared.PetModel)

local UiArt = require(script.Parent.UiArt)
local UiKit = require(script.Parent.UiKit)
local AutoHatch = require(script.Parent.AutoHatch)

local PetPanel = {}

local player = Players.LocalPlayer

local INK = UiKit.INK
local MUTED = UiKit.MUTED
local ACCENT = UiKit.CREW.PINK
local GOOD = UiKit.GOOD
local OUTLINE = Color3.fromRGB(22, 20, 34)
local GOLD_EDGE = Color3.fromRGB(255, 214, 60)

export type Panel = {
	Toggle: () -> (),
	--[[
		Birleştirme makinesinde E'ye basınca açılıyor: yumurtalar gizli,
		yalnızca üç kopyası olan petler ve büyük FUSE düğmeleri. Birleştirme
		sadece makinenin yanında yapılabiliyor (sunucu mesafeyi doğruluyor),
		o yüzden normal pet ekranında FUSE düğmesi yok.
	]]
	OpenFuse: () -> (),
	-- Birleştirme animasyonu makinede oynarken pencere önünü kapatmasın
	IsFuseOpen: () -> boolean,
	Hide: () -> (),
	Destroy: () -> (),
}

--[[
	Kartlar dört sütun ve büyük: beş sütunlu 96 piksellik kartta yazılar
	10-11 punto kalıyor, istatistik satırı okunmuyordu.
]]
local COLS = 4
local CARD_W, CARD_H = 126, 150

--[[
	host verilirse panel kendi penceresini açmıyor, o çerçevenin içine
	sayfa olarak kuruluyor (Envanter'in PETS sekmesi). Kapatma düğmesi de
	yok; pencereyi sahibi kapatıyor. İçerik konumları kökün içine göre,
	yani iki hâlde de aynı kod çalışıyor.
]]
function PetPanel.Create(screen: ScreenGui, auto: AutoHatch.Handle?, host: Frame?, onCount: ((text: string) -> ())?): Panel
	local overlay: Frame
	if host then
		overlay = UiKit.Page(host, "PetPanel")
	else
		overlay = UiKit.Window(screen, "PetPanel", ACCENT)
		overlay.AnchorPoint = Vector2.new(0.5, 0.5)
		overlay.Position = UDim2.fromScale(0.5, 0.5)
		overlay.Size = UDim2.fromOffset(580, 520)
	end
	overlay.Visible = false
	overlay.ZIndex = 40

	local badge = Instance.new("Frame")
	badge.Position = UDim2.fromOffset(18, 14)
	badge.Size = UDim2.fromOffset(30, 30)
	badge.BackgroundTransparency = 1
	badge.ZIndex = 41
	badge.Parent = overlay
	UiKit.Paw(badge, 26, ACCENT)

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
	hint.TextSize = 13
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = MUTED
	hint.Text = ""
	hint.ZIndex = 41
	hint.Parent = overlay

	local close: TextButton? = nil
	if not host then
		close = UiKit.CloseButton(overlay)
		close.ZIndex = 41
	end

	local equipRemote = Net.Get("PetEquip")

	--[[
		EQUIP BEST / UNEQUIP ALL: başlığın sağında. En iyiler sunucuda
		seçiliyor (PetService.EquipBest: gelir bonusu en yüksek kopyalar,
		aynı petten birden fazla olabilir).
	]]
	local quick = Instance.new("Frame")
	quick.Name = "QuickEquip"
	quick.AnchorPoint = Vector2.new(1, 0)
	quick.Position = UDim2.new(1, if host then -14 else -50, 0, 12)
	quick.Size = UDim2.fromOffset(210, 28)
	quick.BackgroundTransparency = 1
	quick.ZIndex = 41
	quick.Parent = overlay
	local ql = Instance.new("UIListLayout")
	ql.FillDirection = Enum.FillDirection.Horizontal
	ql.HorizontalAlignment = Enum.HorizontalAlignment.Right
	ql.Padding = UDim.new(0, 6)
	ql.Parent = quick
	local function quickButton(text: string, tint: Color3, order: number, fire: () -> ()): TextButton
		local b = Instance.new("TextButton")
		b.LayoutOrder = order
		b.Size = UDim2.fromOffset(0, 26)
		b.AutomaticSize = Enum.AutomaticSize.X
		b.BackgroundColor3 = tint
		b.AutoButtonColor = true
		b.Font = Enum.Font.GothamBlack
		b.TextSize = 12
		b.TextColor3 = Color3.new(1, 1, 1)
		b.TextStrokeTransparency = 0.5
		b.Text = text
		b.ZIndex = 42
		b.Parent = quick
		UiKit.Corner(b, 8)
		UiKit.Stroke(b, tint:Lerp(Color3.new(0, 0, 0), 0.5), 1.4, 0)
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = b
		b.MouseButton1Click:Connect(fire)
		return b
	end
	quickButton("EQUIP BEST", Color3.fromRGB(60, 180, 90), 1, function()
		equipRemote:FireServer("@best", true)
	end)
	quickButton("UNEQUIP ALL", Color3.fromRGB(190, 60, 70), 2, function()
		equipRemote:FireServer("@all", false)
	end)
	-- İpucu satırı düğmelerin altına taşmasın
	hint.Size = UDim2.new(1, -290, 0, 16)
	hint.TextTruncate = Enum.TextTruncate.AtEnd

	--[[
		Yumurta açma burada YOK: envanterde yalnızca eldeki petler. Yumurtalar
		MedBay'deki kuluçkada açılıyor (EggPanel: petler, şanslar, E/R/T).
	]]

	--[[
		Yumurtanın rengi Config'te (en iyi kademesinin rengi). Oyuncu dört
		kutudan hangisinin daha değerli olduğunu fiyatı okumadan görüyor.
		Çok koyu (Void, Secret siyahı) arayüzde okunmuyor: mora çekiliyor.
	]]
	local function eggTint(egg: Config.EggDef): Color3
		local t = egg.tint
		if t.R + t.G + t.B < 0.5 then
			return Color3.fromRGB(170, 120, 255)
		end
		return t
	end

	-- ─── Koleksiyon ─────────────────────────────────────────────────────────

	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.fromOffset(14, 60)
	list.Size = UDim2.new(1, -28, 1, -74)
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

	-- "pets": yumurtalar + koleksiyon; "fuse": makinede, yalnızca birleşebilenler
	local mode = "pets"

	-- Kart sırası: düz önce, sonra sıktan nadire (Golden, Crystal, Cosmic)
	local MUTATION_ORDER: { [string]: number } = { [""] = 0 }
	for index = #Config.PetMutations, 1, -1 do
		MUTATION_ORDER[Config.PetMutations[index].id] = #Config.PetMutations - index + 1
	end

	local rows: { Instance } = {}

	-- Çizgi roman yazısı: koyu kalın kontur
	local function ink(label: TextLabel, thickness: number)
		local st = Instance.new("UIStroke")
		st.Color = OUTLINE
		st.Thickness = thickness
		st.LineJoinMode = Enum.LineJoinMode.Round
		st.Parent = label
	end

	local function makeCard(parent: Instance, orderIndex: number, def: Config.PetDef, key: string?, count: number)
		local info = Config.Rarities[def.rarity]
		-- Aynı petten birkaç kopya takılı olabilir (PetService.TryEquip)
		local onCount = 0
		if key then
			for _, k in equipped do
				if k == key then
					onCount += 1
				end
			end
		end
		local isOn = onCount > 0

		--[[
			Açık if bloğu, if-ifadesi DEĞİL: `if k then f(k) else nil, nil`
			f'in yalnızca İLK dönüşünü alıyor ve mutasyon hep nil kalıyordu.
		]]
		local mutation: Config.PetMutationDef? = nil
		local size: Config.PetSizeDef? = nil
		local income, speed = def.incomeBonus, def.speedBonus
		if key then
			local _, m, s = Config.ParsePetKey(key)
			mutation = m
			size = s
			income, speed = Config.GetPetKeyBonus(key)
		end

		local card = Instance.new("TextButton")
		card.Name = key or def.id
		card.LayoutOrder = orderIndex
		-- Sahip olunan kart kademe rengine hafifçe boyanıyor: panel renkli
		-- bir koleksiyon gibi okunuyor, gri bir tablo gibi değil
		-- 2026-09-28 mağaza dili: kademe renginin doygun gradyanı + noktalar,
		-- kalın koyu kenar; takılı olan altın, mutasyonlu kendi renginde
		card.BackgroundColor3 = Color3.new(1, 1, 1)
		card.BackgroundTransparency = if key then 0 else 0.4
		card.BorderSizePixel = 0
		card.AutoButtonColor = false
		card.Text = ""
		card.ZIndex = 43
		card.Parent = parent
		UiKit.Corner(card, 12)
		local tone = if key then info.color else Color3.fromRGB(90, 96, 120)
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(tone:Lerp(Color3.new(1, 1, 1), 0.06), tone:Lerp(Color3.new(0, 0, 0), 0.6))
		grad.Parent = card
		local dots = Instance.new("ImageLabel")
		dots.BackgroundTransparency = 1
		dots.Size = UDim2.fromScale(1, 1)
		dots.Image = UiArt.Image("Texture", "halftone_fade")
		dots.ScaleType = Enum.ScaleType.Crop
		dots.ImageTransparency = 0.84
		dots.ZIndex = 43
		dots.Parent = card
		UiKit.Corner(dots, 12)
		local restColor = if isOn then GOLD_EDGE elseif mutation then mutation.tint else OUTLINE
		local restThick = if isOn then 4 elseif mutation then 3 else 2.5
		local stroke = UiKit.Stroke(card, restColor, restThick, 0)

		--[[
			Figür: petin sahadaki biçimi (küre, robot, yengeç...) kendi
			renginde. Mutasyonlu kopyada mutasyon rengi — Golden'ı düzünden
			ayıran ilk şey bu olmalı. Sahip olunmayan pet sönük siluet.
		]]
		local figure = Instance.new("Frame")
		figure.AnchorPoint = Vector2.new(0.5, 0)
		figure.Position = UDim2.new(0.5, 0, 0, 6)
		figure.Size = UDim2.fromOffset(62, 62)
		figure.BackgroundTransparency = 1
		figure.ZIndex = 44
		figure.Parent = card
		-- Gerçek model (mutasyon rengi ve boyut anahtarda); sahip olunmayan sönük siluet
		UiKit.PetIcon(figure, 62, key or def.id, if not key then UiKit.DIM else nil)

		local name = Instance.new("TextLabel")
		name.Position = UDim2.new(0, 4, 0, 70)
		name.Size = UDim2.new(1, -8, 0, 18)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.FredokaOne
		name.TextSize = 16
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextColor3 = if key then Color3.new(1, 1, 1) else UiKit.DIM
		ink(name, 2)
		name.Text = if key then def.name else "???"
		name.ZIndex = 44
		name.Parent = card

		-- Mutasyon adı ismin altında, kendi renginde
		local tag = Instance.new("TextLabel")
		tag.Position = UDim2.new(0, 4, 0, 89)
		tag.Size = UDim2.new(1, -8, 0, 14)
		tag.BackgroundTransparency = 1
		tag.Font = Enum.Font.FredokaOne
		tag.TextSize = 13
		ink(tag, 1.6)
		--[[
			Mutasyonsuz kartta KADEME yazıyor: koleksiyon artık yumurtaya
			göre gruplu, kademe başlıktan okunmuyor. Secret'ın rengi siyah;
			koyu kartta mora çekiliyor.
		]]
		local rarityTone = if def.rarity == "Secret" then Color3.fromRGB(190, 150, 255) else info.color:Lerp(Color3.new(1, 1, 1), 0.35)
		tag.TextColor3 = if mutation then mutation.tint elseif key then rarityTone else UiKit.DIM
		tag.Text = if mutation then string.upper(mutation.name) .. string.format(" x%.1f", mutation.multiplier) else string.upper(def.rarity)
		tag.ZIndex = 44
		tag.Parent = card

		--[[
			Boyut rozeti (BIG / HUGE / TITAN): sol üstte, altın zemin. Pet
			simülatörlerindeki "Huge" etiketinin karşılığı; büyüklük ekranda
			da bakışta okunsun.
		]]
		if size then
			local sizeChip = Instance.new("TextLabel")
			sizeChip.Position = UDim2.fromOffset(5, 5)
			sizeChip.Size = UDim2.fromOffset(0, 16)
			sizeChip.AutomaticSize = Enum.AutomaticSize.X
			sizeChip.BackgroundColor3 = Color3.fromRGB(255, 196, 60)
			sizeChip.BorderSizePixel = 0
			sizeChip.Font = Enum.Font.GothamBlack
			sizeChip.TextSize = 11
			sizeChip.TextColor3 = Color3.fromRGB(40, 30, 10)
			sizeChip.Text = " " .. string.upper(size.name) .. " "
			sizeChip.ZIndex = 46
			sizeChip.Parent = card
			UiKit.Corner(sizeChip, 4)
		end

		--[[
			İstatistik sahip olunmasa da GÖRÜNÜYOR: neyi kaçırdığını
			bilmeden hedef olmuyor.
		]]
		local stat = Instance.new("TextLabel")
		stat.Position = UDim2.new(0, 4, 0, 105)
		stat.Size = UDim2.new(1, -8, 0, 32)
		stat.BackgroundTransparency = 1
		stat.Font = Enum.Font.FredokaOne
		stat.TextSize = 14
		-- Soluk gri koyu kartta okunmuyordu: açık ton
		stat.TextColor3 = if key then Color3.fromRGB(150, 255, 120) else UiKit.DIM
		ink(stat, 1.6)
		--[[
			İkinci satır: rebirth petlerinde yeteneği (kaçış / şans), diğerlerinde
			uçuş hızı. Eskiden yalnızca "+%X cash" yazıyordu ve pet "sadece
			para veriyor" sanılıyordu.
		]]
		local escape, luck = def.escape or 0, def.luck or 0
		if key then
			escape, luck = Config.GetPetKeyPerks(key)
		end
		-- Petler uçuş hızı VERMİYOR (Config.PetFlightMul = 0): yeteneksiz pette ikinci satır yok
		local second = if escape > 0 then string.format('<font color="#8FD8FF">-%d%% chase</font>', math.floor(escape * 100 + 0.5))
			elseif luck > 0 then string.format('<font color="#FFE36B">+%.1f%% lucky</font>', luck * 100)
			else ""
		stat.RichText = true
		stat.TextSize = 13
		stat.LineHeight = 0.95
		stat.Text = string.format("+%d%% cash\n%s", math.floor(income * 100 + 0.5), if key then second else second:gsub("<[^>]+>", ""))
		stat.ZIndex = 44
		stat.Parent = card

		if not key then
			return
		end

		-- Adet rozeti: sağ üstte, birden fazlası varken
		local countLabel = Instance.new("TextLabel")
		countLabel.AnchorPoint = Vector2.new(1, 0)
		countLabel.Position = UDim2.new(1, -6, 0, 6)
		countLabel.Size = UDim2.fromOffset(36, 16)
		countLabel.BackgroundTransparency = 1
		countLabel.Font = Enum.Font.FredokaOne
		countLabel.TextSize = 15
		ink(countLabel, 1.8)
		countLabel.TextXAlignment = Enum.TextXAlignment.Right
		countLabel.TextColor3 = if isOn then GOOD else MUTED
		-- Takılıysa "takılı/adet" (2/3), değilse adet (x3)
		countLabel.Text = if isOn and count > 1 then string.format("%d/%d", onCount, count)
			elseif count > 1 then "x" .. count
			else ""
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

		--[[
			Birleştirme modunda kartın alt yarısı FUSE düğmesi: üstünde
			hangi kademeye çıkacağı yazıyor ("→ RARE"). Kart tıklaması bu
			modda pet takmıyor — iki işi aynı ekranda karıştırmak kopyaları
			kazayla yakmak demekti.
		]]
		if mode == "fuse" then
			local nextSize = Config.GetNextPetSize(size) :: Config.PetSizeDef
			stat.Visible = false
			local fuseHolder, fuse = UiKit.Raised(card, "Fuse", Color3.fromRGB(236, 176, 50), UDim2.new(1, -10, 0, 34), 8)
			fuseHolder.AnchorPoint = Vector2.new(0.5, 1)
			fuseHolder.Position = UDim2.new(0.5, 0, 1, -6)
			fuseHolder.ZIndex = 46
			fuse.ZIndex = 47
			local fuseText = Instance.new("TextLabel")
			fuseText.Size = UDim2.fromScale(1, 1)
			fuseText.BackgroundTransparency = 1
			fuseText.Font = Enum.Font.GothamBlack
			fuseText.TextSize = 13
			fuseText.TextColor3 = Color3.new(1, 1, 1)
			fuseText.TextStrokeTransparency = 0.5
			fuseText.Text = "FUSE → " .. string.upper(nextSize.name)
			fuseText.TextScaled = true
			fuseText.ZIndex = 48
			fuseText.Parent = fuse
			local limit = Instance.new("UITextSizeConstraint")
			limit.MaxTextSize = 13
			limit.Parent = fuseText
			fuse.MouseButton1Click:Connect(function()
				fuseRemote:FireServer(k)
			end)
			return
		end

		--[[
			Kart tıklaması: takılı değilse bir kopya tak, takılıysa bir kopya
			çıkar. Aynı petin başka kopyasını eklemek için sağ alttaki "+"
			(yalnızca elde takılmamış kopya ve boş slot varken görünüyor).
		]]
		card.MouseButton1Click:Connect(function()
			equipRemote:FireServer(k, not isOn)
		end)
		local canAdd = isOn and onCount < count and #equipped < Config.PetEquipSlots
		if canAdd then
			local plus = Instance.new("TextButton")
			plus.Name = "AddCopy"
			-- Sağ üstte adedin altında: alttaki istatistik satırının üstüne binmesin
			plus.AnchorPoint = Vector2.new(1, 0)
			plus.Position = UDim2.new(1, -6, 0, 26)
			plus.Size = UDim2.fromOffset(24, 24)
			plus.BackgroundColor3 = GOOD
			plus.AutoButtonColor = true
			plus.Font = Enum.Font.GothamBlack
			plus.TextSize = 18
			plus.TextColor3 = Color3.fromRGB(16, 40, 20)
			plus.Text = "+"
			plus.ZIndex = 47
			plus.Parent = card
			UiKit.Corner(plus, 11)
			plus.MouseButton1Click:Connect(function()
				equipRemote:FireServer(k, true)
			end)
		end
		card.MouseEnter:Connect(function()
			stroke.Color = Color3.new(1, 1, 1)
		end)
		card.MouseLeave:Connect(function()
			stroke.Color = restColor
		end)
	end

	local function redraw()
		for _, row in rows do
			row:Destroy()
		end
		table.clear(rows)

		local fusing = mode == "fuse"
		quick.Visible = not fusing
		heading.Text = if fusing then "FUSE MACHINE" else "PETS"

		local slotsUsed = #equipped
		local income, speed = Config.GetPetBonus(equipped)
		if fusing then
			hint.Text = string.format("Fuse %d of the same pet into a bigger one: Big → Huge → Titan → Colossal → Galactic.", Config.PetFuseCount)
		else
			-- Kısa: sağda EQUIP BEST / UNEQUIP ALL var; "+" aynı petin bir kopyasını daha takar
			hint.Text = string.format("%d / %d equipped", slotsUsed, Config.PetEquipSlots)
			if slotsUsed > 0 then
				hint.Text ..= string.format("  ·  +%d%% cash", math.floor(income * 100 + 0.5))
				local escape, luck = Config.GetPetPerks(equipped)
				if escape > 0 then
					hint.Text ..= string.format("  ·  monsters -%d%%", math.floor(escape * 100 + 0.5))
				end
				if luck > 0 then
					hint.Text ..= string.format("  ·  +%d%% lucky", math.floor(luck * 100 + 0.5))
				end
			else
				hint.Text ..= if (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled) then "  ·  tap a pet to equip" else "  ·  click a pet to equip"
			end
		end

		local order = 0
		local anyFusable = false
		--[[
			Koleksiyon YUMURTALARA göre: her yumurtanın kendi pet takımı var
			(Config.Pets.egg), oyuncu "Skeld yumurtasında neler var, hangisi
			eksik" sorusunu tek bakışta cevaplasın. Yumurta içinde kademe
			sırası (Common önce); kademe kartın alt satırında yazıyor.
		]]
		for _, egg in Config.Eggs do
			local tint = eggTint(egg)

			-- Bu yumurtanın sahip olunan anahtarları ve hiç bulunmamış petleri
			type Slot = { def: Config.PetDef, key: string?, count: number }
			local slots: { Slot } = {}

			for key, count in owned do
				local def, _, size = Config.ParsePetKey(key)
				if def and def.egg == egg.id and count > 0 then
					-- Birleştirme modunda yalnızca üç kopyası olan ve daha büyüyebilen
					local fusable = count >= Config.PetFuseCount and Config.GetNextPetSize(size) ~= nil
					if not fusing or fusable then
						table.insert(slots, { def = def, key = key, count = count })
						anyFusable = anyFusable or fusable
					end
				end
			end
			table.sort(slots, function(a, b)
				if a.def.id ~= b.def.id then
					local oa = Config.Rarities[a.def.rarity].order
					local ob = Config.Rarities[b.def.rarity].order
					if oa ~= ob then
						return oa < ob
					end
					return a.def.name < b.def.name
				end
				-- Aynı pet: önce boyut (düz → Titan), sonra mutasyon
				local _, ma, sa = Config.ParsePetKey(a.key :: string)
				local _, mb, sb = Config.ParsePetKey(b.key :: string)
				local ia = if sa then table.find(Config.PetSizes, sa) or 0 else 0
				local ib = if sb then table.find(Config.PetSizes, sb) or 0 else 0
				if ia ~= ib then
					return ia < ib
				end
				return (MUTATION_ORDER[if ma then ma.id else ""] or 0) < (MUTATION_ORDER[if mb then mb.id else ""] or 0)
			end)
			--[[
				Yalnızca ELDE OLAN petler. Hiç bulunmamış petler ("???") artık
				burada değil, INDEX penceresinin PETS sekmesinde: envanter
				"neyim var", indeks "neler var" sorusu.
			]]
			if #slots == 0 then
				continue
			end

			order += 1
			local label = Instance.new("TextLabel")
			label.LayoutOrder = order
			label.Size = UDim2.new(1, -6, 0, 24)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamBlack
			label.TextSize = 15
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextColor3 = tint
			label.TextStrokeTransparency = 0.6
			local have = 0
			for _, slot in slots do
				have += slot.count
			end
			label.Text = string.format("%s  ·  %d PET%s", string.upper(egg.name), have, if have == 1 then "" else "S")
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

		-- Hiç pet yoksa boş liste değil, nereden bulunacağı
		if not fusing and order == 0 then
			local empty = Instance.new("TextLabel")
			empty.LayoutOrder = 1
			empty.Size = UDim2.new(1, -6, 0, 80)
			empty.BackgroundTransparency = 1
			empty.Font = Enum.Font.GothamBold
			empty.TextSize = 15
			empty.TextWrapped = true
			empty.TextColor3 = MUTED
			empty.Text = "No pets yet.\nHatch an egg at the MedBay! Every pet is listed in the INDEX."
			empty.ZIndex = 42
			empty.Parent = list
			table.insert(rows, empty)
		end

		-- Makinede birleştirilecek bir şey yoksa boş ekran değil, ne gerektiği
		if fusing and not anyFusable then
			local empty = Instance.new("TextLabel")
			empty.LayoutOrder = 1
			empty.Size = UDim2.new(1, -6, 0, 80)
			empty.BackgroundTransparency = 1
			empty.Font = Enum.Font.GothamBold
			empty.TextSize = 15
			empty.TextWrapped = true
			empty.TextColor3 = MUTED
			empty.Text = string.format("You need %d copies of the same pet to fuse.\nHatch more eggs and come back!", Config.PetFuseCount)
			empty.ZIndex = 42
			empty.Parent = list
			table.insert(rows, empty)
		end
	end

	local petsConnection = Net.Get("Pets").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		owned = if typeof(payload.owned) == "table" then payload.owned else {}
		equipped = if typeof(payload.equipped) == "table" then payload.equipped else {}
		-- Envanter sekmesindeki sayaç: kaç pet, kaçı takılı
		if onCount then
			local total = 0
			for _, n in owned do
				if typeof(n) == "number" then
					total += n
				end
			end
			onCount(string.format("%d pets · %d/%d equipped", total, #equipped, Config.PetEquipSlots))
		end
		if overlay.Visible then
			redraw()
		end
	end)

	if close then
		close.Activated:Connect(function()
			overlay.Visible = false
		end)
	end

	return {
		Toggle = function()
			-- Makinede açıkken PETS düğmesine basılırsa normal ekrana geç
			if overlay.Visible and mode == "fuse" then
				mode = "pets"
				redraw()
				return
			end
			mode = "pets"
			overlay.Visible = not overlay.Visible
			-- Kapalıyken çizilmiyor (kartlar her seferinde yeniden kuruluyor);
			-- açılırken son veriyle çiz
			if overlay.Visible then
				redraw()
			end
		end,
		OpenFuse = function()
			mode = "fuse"
			overlay.Visible = true
			redraw()
		end,
		IsFuseOpen = function(): boolean
			return overlay.Visible and mode == "fuse"
		end,
		Hide = function()
			overlay.Visible = false
		end,
		Destroy = function()
			petsConnection:Disconnect()
			overlay:Destroy()
		end,
	}
end

return PetPanel
