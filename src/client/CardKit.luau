--!strict
--[[
	Mağaza (ShopPanel) görsel dili, öbür pencereler için ortak parçalar:
	kalın renkli başlık şeridi + kırmızı X, koyu noktalı gövde, "-- BÖLÜM --"
	başlıkları, rengin açık-koyu gradyanı ve ışınlı kartlar, çizgi roman
	yazısı (kalın koyu kontur), tıknaz basılan düğmeler.

	Neden ayrı modül: mağaza yeniden tasarlanınca Upgrade, Quest ve envanter
	eski (düz, sade) görünüşte kaldı. Hepsi aynı parçalardan kurulunca oyun
	tek elden çıkmış gibi duruyor; renk ya da kontur değişirse tek yerde.

	ShopPanel kendi kopyasını kullanmaya devam ediyor (Yusuf'un dosyası);
	değerler birebir aynı.

	2026-09-28 (mağazanın yeni dili, FancyKit): kabukta nokta dokusu +
	yükselen parıltılar, başlıkta kayan şeritler + parıltı + sarı-turuncu
	3B yazı, X'te parıltı; kartlar rengin daha doygun gradyanı + noktalar;
	düğmeler üstüne gelince şişiyor. Çağrı imzaları aynı.
]]


local FancyKit = require(script.Parent.FancyKit)
local UiArt = require(script.Parent.UiArt)

local CardKit = {}

CardKit.WHITE = Color3.new(1, 1, 1)
CardKit.OUTLINE = Color3.fromRGB(22, 20, 34)
CardKit.BODY = Color3.fromRGB(34, 38, 56)
CardKit.BODY_DEEP = Color3.fromRGB(22, 25, 38)
CardKit.GREEN = Color3.fromRGB(88, 226, 60)
CardKit.YELLOW = Color3.fromRGB(255, 222, 60)
CardKit.GREY = Color3.fromRGB(120, 128, 146)
CardKit.FONT = Enum.Font.FredokaOne
-- Mağazanın ışın görseli (shop_art/rays.png)
CardKit.RAYS = "rbxassetid://121213630524182"

local WHITE, OUTLINE = CardKit.WHITE, CardKit.OUTLINE
local BLACK = Color3.new(0, 0, 0)

function CardKit.corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

function CardKit.border(parent: Instance, color: Color3, thickness: number, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

function CardKit.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Rotation = rotation or 90
	g.Color = ColorSequence.new(top, bottom)
	g.Parent = parent
	return g
end

--[[ Çizgi roman yazısı: dolgu + kalın koyu kontur (UIStroke, Contextual). ]]
function CardKit.bold(parent: Instance, text: string, size: number, color: Color3, z: number, outline: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = CardKit.FONT
	t.TextSize = size
	t.TextColor3 = color
	t.Text = text
	t.RichText = true
	t.ZIndex = z
	t.Parent = parent
	local s = Instance.new("UIStroke")
	s.Color = OUTLINE
	s.Thickness = outline or math.max(2, size / 11)
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = t
	return t
end

--[[ Sığmazsa küçülen kalın yazı (en fazla `size`). ]]
function CardKit.fit(label: TextLabel, maxSize: number, minSize: number?)
	label.TextScaled = true
	-- Satır kırma yok: TextScaled kırmaya izin verince "SABOTAGE" iki satıra
	-- bölünüyordu; tek satırda küçülsün
	label.TextWrapped = false
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.MinTextSize = minSize or 10
	c.Parent = label
end

--[[
	═══ TEK GÖRSEL DİL (2026-09-28) ════════════════════════════════════════

	Yusuf: "her şey aynı derecede parlak ve renkli, hiçbir şey öne çıkmıyor;
	iki arayüz stili yan yana duruyor". Eskiden her kart kendi renginde tam
	doygun + ışınlıydı; pencereler (UiKit.Window) ise lacivert. Şimdi:

	  card  — SIRADAN yüzey: lacivert gövde (renge çok hafif çalan), üstte
	          ince renkli şerit ve renkli iç kenar. Renk yalnızca VURGU;
	          pencerelerle aynı gövde. Ekrandakilerin %90'ı bu.
	  hero  — ÖNE ÇIKAN tek şey: tam renk + ışın (hedef kartı, süren olay,
	          büyük ödül). Az kullanıldığı için göz önce ona gidiyor.

	İmzalar aynı: eski çağrılar değişmeden yeni görünüşü alıyor.
]]
local function paintCard(card: Frame, tint: Color3)
	card.BackgroundColor3 = Color3.new(1, 1, 1)
	local g = card:FindFirstChild("Body")
	if g and g:IsA("UIGradient") then
		g.Color = ColorSequence.new(CardKit.BODY:Lerp(tint, 0.42), CardKit.BODY_DEEP:Lerp(tint, 0.16))
	end
	local strip = card:FindFirstChild("Accent")
	if strip and strip:IsA("Frame") then
		strip.BackgroundColor3 = tint
	end
	-- 2026-10-03: parlak kart görseli (beyaz) lacivert-renk karışımıyla çarpılıyor
	local art = card:FindFirstChild("Kit_card")
	if art and art:IsA("ImageLabel") then
		art.ImageColor3 = CardKit.BODY:Lerp(tint, 0.5):Lerp(WHITE, 0.12)
	end
	local inner = card:FindFirstChild("Inner")
	local stroke = inner and inner:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = tint:Lerp(WHITE, 0.25)
	end
end

function CardKit.card(parent: Instance, tint: Color3, size: UDim2, z: number, raysAt: UDim2?, raysSize: number?): Frame
	local _ = raysAt
	local _2 = raysSize
	local card = Instance.new("Frame")
	card.Size = size
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.ZIndex = z
	card.Parent = parent
	card:SetAttribute("CardStyle", "surface")
	CardKit.corner(card, 14)
	local g = CardKit.gradient(card, CardKit.BODY, CardKit.BODY_DEEP)
	g.Name = "Body"
	UiArt.kit(card, "card", -1) -- zemin: kart içeriğinin altında
	card.BackgroundTransparency = 1
	FancyKit.halftone(card, WHITE, 0.9, z, true)

	-- Üstte ince vurgu şeridi
	local strip = Instance.new("Frame")
	strip.Name = "Accent"
	strip.Size = UDim2.new(1, 0, 0, 4)
	strip.BorderSizePixel = 0
	strip.ZIndex = z
	strip.Parent = card

	local frame = Instance.new("Frame")
	frame.Name = "Frame"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.ZIndex = z + 1
	frame.Parent = card
	CardKit.corner(frame, 14)
	CardKit.border(frame, OUTLINE, 3)
	-- Görselin kendi konturu var: çizgi kenar ve üst şerit gizli
	frame.Visible = false
	strip.Visible = false
	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.Position = UDim2.fromOffset(3, 3)
	inner.Size = UDim2.new(1, -6, 1, -6)
	inner.BackgroundTransparency = 1
	inner.ZIndex = z + 1
	inner.Parent = card
	CardKit.corner(inner, 11)
	CardKit.border(inner, tint, 1.5, 0.55)
	inner.Visible = false
	paintCard(card, tint)
	return card
end

--[[ Öne çıkan kart: tam renk gradyan + ışınlar (eski kart). Az kullan. ]]
function CardKit.hero(parent: Instance, tint: Color3, size: UDim2, z: number, raysAt: UDim2?, raysSize: number?): Frame
	local card = Instance.new("Frame")
	card.Size = size
	card.BackgroundColor3 = tint
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.ZIndex = z
	card.Parent = parent
	card:SetAttribute("CardStyle", "hero")
	CardKit.corner(card, 14)
	CardKit.gradient(card, tint:Lerp(WHITE, 0.28), tint:Lerp(BLACK, 0.25))
	FancyKit.halftone(card, WHITE, 0.8, z, true)

	local rays = Instance.new("ImageLabel")
	rays.Name = "Rays"
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = raysAt or UDim2.fromScale(0.5, 0.45)
	rays.Size = UDim2.fromOffset(raysSize or 420, raysSize or 420)
	rays.BackgroundTransparency = 1
	rays.Image = CardKit.RAYS
	rays.ImageColor3 = tint:Lerp(WHITE, 0.75)
	rays.ImageTransparency = 0.4
	rays.ZIndex = z
	rays.Parent = card

	local frame = Instance.new("Frame")
	frame.Name = "Frame"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.ZIndex = z + 1
	frame.Parent = card
	CardKit.corner(frame, 14)
	CardKit.border(frame, OUTLINE, 3)
	local inner = Instance.new("Frame")
	inner.Position = UDim2.fromOffset(3, 3)
	inner.Size = UDim2.new(1, -6, 1, -6)
	inner.BackgroundTransparency = 1
	inner.ZIndex = z + 1
	inner.Parent = card
	CardKit.corner(inner, 11)
	CardKit.border(inner, tint:Lerp(WHITE, 0.55), 2, 0.3)
	return card
end

--[[ Kartın rengini sonradan değiştirir (tamamlanan görev, kilitli satır). ]]
function CardKit.tintCard(card: Frame, tint: Color3)
	if card:GetAttribute("CardStyle") == "surface" then
		paintCard(card, tint)
		return
	end
	card.BackgroundColor3 = tint
	local g = card:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(tint:Lerp(WHITE, 0.28), tint:Lerp(BLACK, 0.25))
	end
	local rays = card:FindFirstChild("Rays")
	if rays and rays:IsA("ImageLabel") then
		rays.ImageColor3 = tint:Lerp(WHITE, 0.75)
	end
end

--[[ İkon yuvası: koyu daire, kalın kenar; içine UiKit ikonu konuyor. ]]
function CardKit.badge(parent: Instance, size: number, tint: Color3, z: number): Frame
	local b = Instance.new("Frame")
	b.Size = UDim2.fromOffset(size, size)
	b.BackgroundColor3 = tint:Lerp(BLACK, 0.45)
	b.BorderSizePixel = 0
	b.ZIndex = z
	b.Parent = parent
	CardKit.corner(b, math.floor(size / 2))
	CardKit.border(b, OUTLINE, 3)
	CardKit.gradient(b, tint:Lerp(BLACK, 0.2), tint:Lerp(BLACK, 0.6))
	local slot = Instance.new("Frame")
	slot.Name = "Slot"
	slot.AnchorPoint = Vector2.new(0.5, 0.5)
	slot.Position = UDim2.fromScale(0.5, 0.5)
	slot.Size = UDim2.fromOffset(math.floor(size * 0.7), math.floor(size * 0.7))
	slot.BackgroundTransparency = 1
	slot.ZIndex = z + 1
	slot.Parent = b
	return b
end

export type Button = {
	holder: Frame,
	button: TextButton,
	label: TextLabel,
	--[[ color nil = gri, basılamaz. ]]
	set: (text: string, color: Color3?) -> (),
}

--[[ Tıknaz düğme: parlak renk, alt gölge, üstte parlak şerit, basınca iner. ]]
function CardKit.button(parent: Instance, size: UDim2, z: number, textSize: number, color: Color3?): Button
	local holder = Instance.new("Frame")
	holder.Size = size
	holder.BackgroundTransparency = 1
	holder.ZIndex = z
	holder.Parent = parent

	local shadow = Instance.new("Frame")
	shadow.Position = UDim2.fromOffset(0, 5)
	shadow.Size = UDim2.new(1, 0, 1, -5)
	shadow.BorderSizePixel = 0
	shadow.ZIndex = z
	shadow.Parent = holder
	CardKit.corner(shadow, 10)

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 1, -5)
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = z + 1
	button.Parent = holder
	CardKit.corner(button, 10)
	CardKit.border(button, OUTLINE, 2.5)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Parent = button

	local gloss = Instance.new("Frame")
	gloss.Position = UDim2.fromOffset(5, 4)
	gloss.Size = UDim2.new(1, -10, 0.36, 0)
	gloss.BackgroundColor3 = WHITE
	gloss.BackgroundTransparency = 0.72
	gloss.BorderSizePixel = 0
	gloss.ZIndex = z + 2
	gloss.Parent = button
	CardKit.corner(gloss, 6)

	-- 2026-10-03: ChatGPT düğme yüzü (beyaz, renge boyanıyor)
	UiArt.plain(button)
	gloss.Visible = false
	shadow.Visible = false
	local face = UiArt.kit(button, "button", z + 1)
	face.Size = UDim2.new(1, 6, 1, 8)
	face.Position = UDim2.new(0.5, 0, 0.5, 2)

	local label = CardKit.bold(button, "", textSize, WHITE, z + 3)
	label.Size = UDim2.new(1, -10, 1, 0)
	label.Position = UDim2.fromOffset(5, 0)
	CardKit.fit(label, textSize, 10)

	local function set(text: string, tone: Color3?)
		local c = tone or CardKit.GREY
		button.BackgroundColor3 = c
		shadow.BackgroundColor3 = c:Lerp(BLACK, 0.55)
		grad.Color = ColorSequence.new(c:Lerp(WHITE, 0.25), c:Lerp(BLACK, 0.12))
		face.ImageColor3 = c:Lerp(WHITE, 0.08)
		label.Text = text
		button.Active = tone ~= nil
	end
	set("", color or CardKit.GREEN)

	button.MouseButton1Down:Connect(function()
		button.Position = UDim2.fromOffset(0, 4)
	end)
	local function release()
		button.Position = UDim2.fromOffset(0, 0)
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	FancyKit.juicy(holder, button, 1.05, 2)

	return { holder = holder, button = button, label = label, set = set }
end

--[[ İlerleme çubuğu: koyu oluk, renkli dolgu, üstünde kalın yazı. ]]
export type Bar = { frame: Frame, fill: Frame, label: TextLabel, set: (ratio: number, text: string) -> () }

function CardKit.bar(parent: Instance, size: UDim2, color: Color3, z: number, textSize: number?): Bar
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.BackgroundColor3 = Color3.fromRGB(16, 18, 28)
	frame.BorderSizePixel = 0
	frame.ZIndex = z
	frame.Parent = parent
	CardKit.corner(frame, 8)
	CardKit.border(frame, OUTLINE, 2.5)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.ZIndex = z + 1
	fill.Parent = frame
	CardKit.corner(fill, 8)
	CardKit.gradient(fill, color:Lerp(WHITE, 0.3), color:Lerp(BLACK, 0.15))
	local shine = Instance.new("Frame")
	shine.Position = UDim2.new(0, 4, 0, 3)
	shine.Size = UDim2.new(1, -8, 0.3, 0)
	shine.BackgroundColor3 = WHITE
	shine.BackgroundTransparency = 0.65
	shine.BorderSizePixel = 0
	shine.ZIndex = z + 1
	shine.Parent = fill
	CardKit.corner(shine, 4)
	local label = CardKit.bold(frame, "", textSize or 16, WHITE, z + 2, 2)
	label.Size = UDim2.fromScale(1, 1)
	local function set(ratio: number, text: string)
		fill.Size = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
		fill.Visible = ratio > 0.001
		label.Text = text
	end
	return { frame = frame, fill = fill, label = label, set = set }
end

export type Skin = { header: Frame, close: TextButton, title: TextLabel, body: Frame }

--[[
	Pencere kabuğunu mağaza görünüşüne çevirir: koyu gradyan gövde, noktalı
	desen, renkli eğik parlamalı başlık şeridi, kırmızı kare X.
	`root` UiKit.Window'dan gelen kabuk; boyutu zaten verilmiş olmalı.
]]
function CardKit.skin(root: Frame, color: Color3, titleText: string, headerH: number, z: number): Skin
	for _, child in root:GetChildren() do
		-- UiKit.Modernize'ın iç kenarı da: başlık şeridinin üstüne binmesin
		if child:IsA("UIGradient") or child:IsA("UIStroke") or child.Name == "ModernRim" then
			child:Destroy()
		end
	end
	root.BackgroundColor3 = CardKit.BODY
	CardKit.gradient(root, CardKit.BODY, CardKit.BODY_DEEP)
	CardKit.border(root, OUTLINE, 5)
	-- 2026-10-03: ChatGPT nebula gövdesi (UiArt.Kit)
	UiArt.plain(root)
	UiArt.kit(root, "window", -1) -- her şeyin altında

	local size = root.Size
	local w, h = size.X.Offset, size.Y.Offset

	local driver = FancyKit.driver(root)
	local dots = Instance.new("Frame")
	dots.Name = "Dots"
	dots.Position = UDim2.fromOffset(0, headerH)
	dots.Size = UDim2.new(1, 0, 1, -headerH)
	dots.BackgroundTransparency = 1
	dots.ClipsDescendants = true
	dots.ZIndex = z
	dots.Parent = root
	FancyKit.halftone(dots, Color3.fromRGB(120, 140, 220), 0.9, z)
	FancyKit.particles(dots, driver, 12, Color3.fromRGB(255, 230, 150), z)
	local _ = w
	local _2 = h

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, headerH)
	header.BackgroundColor3 = color
	header.BorderSizePixel = 0
	header.ClipsDescendants = true
	header.ZIndex = z + 1
	header.Parent = root
	CardKit.corner(header, 16)
	CardKit.gradient(header, color:Lerp(WHITE, 0.2), color:Lerp(BLACK, 0.12))
	local foot = Instance.new("Frame")
	foot.Position = UDim2.new(0, 0, 1, -16)
	foot.Size = UDim2.new(1, 0, 0, 16)
	foot.BackgroundColor3 = color:Lerp(BLACK, 0.1)
	foot.BorderSizePixel = 0
	foot.ZIndex = z + 1
	foot.Parent = header
	-- Parlak beyaz başlık görseli pencere rengine boyanıyor
	UiArt.plain(header)
	header.ClipsDescendants = false
	foot.Visible = false
	UiArt.kit(header, "header", z + 1, color:Lerp(WHITE, 0.1))
	-- Kayan çapraz şeritler, noktalar ve periyodik parıltı (mağaza başlığı)
	local stripes = Instance.new("ImageLabel")
	stripes.Name = "Stripes"
	stripes.BackgroundTransparency = 1
	stripes.Size = UDim2.new(1, 64, 1, 0)
	stripes.Image = "rbxassetid://127645580329632"
	stripes.ScaleType = Enum.ScaleType.Tile
	stripes.TileSize = UDim2.fromOffset(64, 64)
	stripes.ImageTransparency = 0.86
	stripes.ZIndex = z + 2
	stripes.Parent = header
	driver.add(function(t)
		stripes.Position = UDim2.fromOffset(-((t * 18) % 64), 0)
	end)
	FancyKit.halftone(header, WHITE, 0.86, z + 2, true)
	FancyKit.gleam(header, driver, 5, 1, 0.3)
	local rule = Instance.new("Frame")
	rule.Position = UDim2.new(0, 0, 0, headerH - 2)
	rule.Size = UDim2.new(1, 0, 0, 4)
	rule.BackgroundColor3 = OUTLINE
	rule.BorderSizePixel = 0
	rule.ZIndex = z + 3
	rule.Parent = root

	local title = CardKit.bold(header, titleText, math.floor(headerH * 0.62), WHITE, z + 4, 5)
	title.TextXAlignment = Enum.TextXAlignment.Left
	-- Sarı → turuncu 3B başlık (FancyKit.title gibi; burada tek katman çünkü
	-- çağıranlar title.Text'i değiştiriyor)
	local tg = Instance.new("UIGradient")
	tg.Rotation = 90
	tg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 244, 170)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(255, 226, 60)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 140, 20)),
	})
	tg.Parent = title
	title.Position = UDim2.fromOffset(22, 4)
	title.Size = UDim2.new(1, -110, 1, -8)

	local closeSize = math.floor(headerH * 0.76)
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -12, 0, headerH / 2)
	close.Size = UDim2.fromOffset(closeSize, closeSize)
	close.BackgroundColor3 = Color3.fromRGB(226, 30, 40)
	close.BorderSizePixel = 0
	close.AutoButtonColor = false
	close.Text = ""
	close.ZIndex = z + 5
	close.Parent = root
	CardKit.corner(close, 8)
	CardKit.border(close, OUTLINE, 3)
	CardKit.gradient(close, Color3.fromRGB(250, 70, 70), Color3.fromRGB(190, 20, 30))
	UiArt.plain(close)
	UiArt.kit(close, "close", z + 5).Size = UDim2.fromScale(1.2, 1.2)
	local x = CardKit.bold(close, "X", math.floor(closeSize * 0.72), WHITE, z + 6, 4)
	x.Size = UDim2.fromScale(1, 1)
	x.Visible = false -- görselde X var
	FancyKit.gleam(close, driver, 4.2, 2, 0.4)
	FancyKit.juicy(close, close, 1.1, -8)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, headerH + 2)
	body.Size = UDim2.new(1, 0, 1, -headerH - 2)
	body.BackgroundTransparency = 1
	body.ZIndex = z + 1
	body.Parent = root

	return { header = header, close = close, title = title, body = body }
end

--[[ "-- BÖLÜM --" başlığı (liste içinde). ]]
function CardKit.section(parent: Instance, text: string, color: Color3, width: number, z: number, order: number): TextLabel
	local t = CardKit.bold(parent, "-- " .. text .. " --", 30, color, z, 3.5)
	t.LayoutOrder = order
	t.Size = UDim2.fromOffset(width, 38)
	return t
end

return CardKit
