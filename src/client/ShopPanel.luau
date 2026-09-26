--!strict
--[[
	Mağaza: gamepass'ler, para paketleri, iksirler ve tek seferlik takviyeler.

	═══ GÖRÜNÜŞ ═══════════════════════════════════════════════════════════

	Pet/simülatör oyunlarının mağaza dili: kalın yeşil başlık şeridi, koyu
	gövde, "-- BÖLÜM --" başlıkları, renkli ve ışınlı kartlar, büyük
	resimler, tıknaz yeşil Robux düğmeleri. Sağda pencerenin dışında bölüm
	düğmeleri (FEATURED, PASSES, MONEY, POTIONS, BOOSTS): basınca liste o
	bölüme kayıyor.

	═══ RESİMLER ══════════════════════════════════════════════════════════

	Kart resimleri tools/shop_art.py'nin ürettiği saydam PNG'ler
	(shop_art/). Studio'nun Import Queue'suyla yüklendi, kimlikleri aşağıda
	(ART). Resmi değiştirmek: PNG'yi yeniden üret, yükle, kimliği güncelle.
	Resim yüklenmezse (moderasyonda bekliyor, silindi) yerine UiKit'in
	çizim ikonu görünüyor; resim gelince çizim gizleniyor.

	Not: Import Queue, yolunda Türkçe karakter olan klasörden
	(OneDrive\Masaüstü) yükleyemiyor; dosyaları önce ASCII bir yola kopyala.

	Kart zeminindeki ışınlar tek bir beyaz görsel (rays): ImageColor3 ile
	her kartın rengine boyanıyor.

	═══ SUNUCUYA REMOTE YOK ═══════════════════════════════════════════════

	Satın alma istemini MarketplaceService istemciden açabiliyor ve parayı
	Roblox tahsil ediyor; ödülü de sunucu ProcessReceipt / pass önbelleği
	üzerinden veriyor. Yani buradan giden bir "bana şunu ver" isteği YOK —
	yeni bir saldırı yüzeyi açılmıyor.

	═══ ID'SİZ ÜRÜN ═══════════════════════════════════════════════════════

	Config'deki id = 0 olan ürünler henüz Creator Dashboard'da
	oluşturulmadı. Gizlenmiyor, "SOON" olarak gösteriliyor.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local UiKit = require(script.Parent.UiKit)

local ShopPanel = {}

local player = Players.LocalPlayer

export type Panel = {
	Toggle: () -> (),
	Open: (section: string?) -> (),
	Close: () -> (),
	Destroy: () -> (),
}

-- ─── Görsel dil ─────────────────────────────────────────────────────────────

local W, H = 880, 600
local HEADER = 74
local Z = 40

local WHITE = Color3.new(1, 1, 1)
local OUTLINE = Color3.fromRGB(22, 20, 34)
local HEADER_GREEN = Color3.fromRGB(96, 214, 60)
local BODY = Color3.fromRGB(34, 38, 56)
local BODY_DEEP = Color3.fromRGB(22, 25, 38)
local BUY_GREEN = Color3.fromRGB(88, 226, 60)
local TITLE_YELLOW = Color3.fromRGB(255, 222, 60)
local ROBUX_ICON = "rbxasset://textures/ui/common/robux@3x.png"

-- shop_art/<ad>.png -> yüklenen görselin kimliği (Asset Manager > Uploads)
local ART: { [string]: number } = {
	DoubleIncome = 89104943455922,
	ExtraPodiums = 103152933222775,
	TripleHatch = 93098279041698,
	FastSteal = 96955344867927,
	StrongLock = 101130632421848,
	ExtraSpin = 125026616828140,
	LuckyRoll = 122458606912739,
	InstantRebirth = 115679159690279,
	Cash100K = 110535372035270,
	Cash1M = 122164985012940,
	Cash10M = 92953397512544,
	Potion_Income2x = 114178961482041,
	Potion_Income3x = 115441758345056,
	Potion_FastSteal = 111091874847579,
	Potion_StrongLock = 125597935999025,
	rays = 121213630524182,
}

local function artImage(name: string): string
	local id = ART[name]
	return if id then "rbxassetid://" .. id else ""
end

local FONT = Enum.Font.FredokaOne

-- ─── Katalog ────────────────────────────────────────────────────────────────

type Entry = {
	key: string,          -- Config.GamePasses / Config.Products anahtarı
	kind: string,         -- pass | product
	title: string,        -- kartta kocaman yazan ad
	blurb: string,        -- RichText: vurgulu kelime renkli
	art: string,          -- shop_art/<art>.png
	tint: Color3,         -- kart rengi
	icon: string,         -- resim yokken UiKit çizimi
}

--[[
	Sıra ve metinler burada, Config'de değil: Config sözlükleri sırasız,
	ad ("2x Income") ne yaptığını söylüyor ama neye değdiğini söylemiyor.
]]
local function hi(text: string, color: string): string
	return string.format('<font color="%s">%s</font>', color, text)
end

local PASSES: { Entry } = {
	{ key = "DoubleIncome", kind = "pass", title = "x2 Income", art = "DoubleIncome", icon = "coin",
		tint = Color3.fromRGB(242, 178, 30), blurb = "Every podium earns " .. hi("x2", "#7CFF5B") .. " cash, forever!" },
	{ key = "TripleHatch", kind = "pass", title = "Triple Hatch", art = "TripleHatch", icon = "egg",
		tint = Color3.fromRGB(160, 80, 235), blurb = "Hatch " .. hi("3 eggs", "#FFE13C") .. " at once, same wait!" },
	{ key = "FastSteal", kind = "pass", title = "Fast Steal", art = "FastSteal", icon = "bolt",
		tint = Color3.fromRGB(240, 110, 40), blurb = "Steal " .. hi("40% faster", "#FFE13C") .. " from every base!" },
	{ key = "ExtraPodiums", kind = "pass", title = "+2 Podiums", art = "ExtraPodiums", icon = "podium",
		tint = Color3.fromRGB(50, 130, 235), blurb = hi("2 extra", "#7CFF5B") .. " podiums on every floor!" },
	{ key = "StrongLock", kind = "pass", title = "Strong Lock", art = "StrongLock", icon = "lock",
		tint = Color3.fromRGB(30, 170, 190), blurb = "Your lock holds " .. hi("longer", "#FFE13C") .. " and recharges faster!" },
}

local MONEY: { Entry } = {
	{ key = "Cash100K", kind = "product", title = "$100K", art = "Cash100K", icon = "coin",
		tint = Color3.fromRGB(58, 178, 62), blurb = "" },
	{ key = "Cash1M", kind = "product", title = "$1M", art = "Cash1M", icon = "coin",
		tint = Color3.fromRGB(58, 178, 62), blurb = "" },
	{ key = "Cash10M", kind = "product", title = "$10M", art = "Cash10M", icon = "coin",
		tint = Color3.fromRGB(58, 178, 62), blurb = "" },
}

local POTIONS: { Entry } = {
	{ key = "PotionIncome2x", kind = "product", title = "x2 Income", art = "Potion_Income2x", icon = "vial",
		tint = Color3.fromRGB(56, 170, 70), blurb = "" },
	{ key = "PotionIncome3x", kind = "product", title = "x3 Income", art = "Potion_Income3x", icon = "vial",
		tint = Color3.fromRGB(214, 150, 20), blurb = "" },
	{ key = "PotionFastSteal", kind = "product", title = "Fast Hands", art = "Potion_FastSteal", icon = "vial",
		tint = Color3.fromRGB(226, 84, 60), blurb = "" },
	{ key = "PotionStrongLock", kind = "product", title = "Strong Lock", art = "Potion_StrongLock", icon = "vial",
		tint = Color3.fromRGB(40, 140, 220), blurb = "" },
}

local BOOSTS: { Entry } = {
	{ key = "LuckyRoll", kind = "product", title = "Mutation", art = "LuckyRoll", icon = "vial",
		tint = Color3.fromRGB(150, 70, 220), blurb = "Next spawn is " .. hi("mutated", "#7CFF5B") },
	{ key = "ExtraSpin", kind = "product", title = "Extra Spin", art = "ExtraSpin", icon = "wheel",
		tint = Color3.fromRGB(226, 70, 150), blurb = hi("+1", "#FFE13C") .. " wheel spin" },
	{ key = "InstantRebirth", kind = "product", title = "Rebirth", art = "InstantRebirth", icon = "crewmate",
		tint = Color3.fromRGB(236, 120, 30), blurb = "Rebirth " .. hi("now", "#FFE13C") .. ", skip the cost" },
}

local function defOf(entry: Entry): { id: number, name: string }?
	if entry.kind == "pass" then
		return Config.GamePasses[entry.key]
	end
	return Config.Products[entry.key]
end

-- ─── Küçük yapı taşları ─────────────────────────────────────────────────────

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function border(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
end

local function gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?)
	local g = Instance.new("UIGradient")
	g.Rotation = rotation or 90
	g.Color = ColorSequence.new(top, bottom)
	g.Parent = parent
end

--[[
	Çizgi roman yazısı: beyaz (ya da renkli) dolgu, kalın koyu kontur.
	Kontur UIStroke (Contextual = harflerin çevresi) — TextStroke 1 piksel
	kalıyor ve büyük yazıda incecik görünüyordu.
]]
local function bold(parent: Instance, text: string, size: number, color: Color3, z: number, outline: number?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = FONT
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

--[[
	Kart resmi: önce UiKit çizimi (yedek), üstünde shop_art görseli. Görsel
	yüklenince yedek gizleniyor; yüklenmediyse çizim kalıyor ve kart boş
	görünmüyor.
]]
local function art(parent: Instance, entry: Entry, size: number, z: number): Frame
	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.ZIndex = z
	holder.Parent = parent

	local fallback = Instance.new("Frame")
	fallback.AnchorPoint = Vector2.new(0.5, 0.5)
	fallback.Position = UDim2.fromScale(0.5, 0.5)
	fallback.Size = UDim2.fromOffset(size * 0.6, size * 0.6)
	fallback.BackgroundTransparency = 1
	fallback.ZIndex = z
	fallback.Parent = holder
	UiKit.Icon(fallback, entry.icon, math.floor(size * 0.55), entry.tint:Lerp(WHITE, 0.35))

	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Image = artImage(entry.art)
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = z + 1
	img.Parent = holder
	local function check()
		if img.IsLoaded then
			fallback.Visible = false
		end
	end
	img:GetPropertyChangedSignal("IsLoaded"):Connect(check)
	check()
	return holder
end

--[[ Kart zemini: rengin açık-koyu gradyanı + ortada boyanmış ışınlar. ]]
local function cardBase(parent: Instance, tint: Color3, size: UDim2, z: number, raysAt: UDim2?): Frame
	local card = Instance.new("Frame")
	card.Size = size
	card.BackgroundColor3 = tint
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.ZIndex = z
	card.Parent = parent
	corner(card, 14)
	gradient(card, tint:Lerp(WHITE, 0.28), tint:Lerp(Color3.new(0, 0, 0), 0.25))

	local rays = Instance.new("ImageLabel")
	rays.Name = "Rays"
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = raysAt or UDim2.fromScale(0.5, 0.45)
	rays.Size = UDim2.fromOffset(460, 460)
	rays.BackgroundTransparency = 1
	rays.Image = artImage("rays")
	rays.ImageColor3 = tint:Lerp(WHITE, 0.75)
	rays.ImageTransparency = 0.35
	rays.ZIndex = z
	rays.Parent = card

	-- Dış çerçeve: koyu kalın kenar + içte ince açık kenar (kabartma)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.ZIndex = z + 1
	frame.Parent = card
	corner(frame, 14)
	border(frame, OUTLINE, 3)
	local inner = Instance.new("Frame")
	inner.Position = UDim2.fromOffset(3, 3)
	inner.Size = UDim2.new(1, -6, 1, -6)
	inner.BackgroundTransparency = 1
	inner.ZIndex = z + 1
	inner.Parent = card
	corner(inner, 11)
	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = tint:Lerp(WHITE, 0.55)
	innerStroke.Thickness = 2
	innerStroke.Transparency = 0.3
	innerStroke.Parent = inner
	return card
end

type BuyButton = { holder: Frame, button: TextButton, label: TextLabel, icon: ImageLabel, setState: (string, string?) -> () }

--[[
	Tıknaz Robux düğmesi: parlak yeşil, alt gölge, Robux simgesi + fiyat.
	Durumlar: "price" (fiyat), "owned" (gri, OWNED), "soon" (gri, SOON).
]]
local function buyButton(parent: Instance, size: UDim2, z: number, textSize: number): BuyButton
	local holder = Instance.new("Frame")
	holder.Size = size
	holder.BackgroundTransparency = 1
	holder.ZIndex = z
	holder.Parent = parent

	local shadow = Instance.new("Frame")
	shadow.Position = UDim2.fromOffset(0, 5)
	shadow.Size = UDim2.new(1, 0, 1, -5)
	shadow.BackgroundColor3 = BUY_GREEN:Lerp(Color3.new(0, 0, 0), 0.55)
	shadow.BorderSizePixel = 0
	shadow.ZIndex = z
	shadow.Parent = holder
	corner(shadow, 10)

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 1, -5)
	button.BackgroundColor3 = BUY_GREEN
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = z + 1
	button.Parent = holder
	corner(button, 10)
	border(button, OUTLINE, 2.5)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Parent = button

	-- Üst yarıda parlak şerit
	local gloss = Instance.new("Frame")
	gloss.Position = UDim2.fromOffset(5, 4)
	gloss.Size = UDim2.new(1, -10, 0.36, 0)
	gloss.BackgroundColor3 = WHITE
	gloss.BackgroundTransparency = 0.72
	gloss.BorderSizePixel = 0
	gloss.ZIndex = z + 2
	gloss.Parent = button
	corner(gloss, 6)

	local row = Instance.new("Frame")
	row.Size = UDim2.fromScale(1, 1)
	row.BackgroundTransparency = 1
	row.ZIndex = z + 3
	row.Parent = button
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 6)
	list.Parent = row

	local icon = Instance.new("ImageLabel")
	icon.LayoutOrder = 1
	icon.Size = UDim2.fromOffset(textSize, textSize)
	icon.BackgroundTransparency = 1
	icon.Image = ROBUX_ICON
	icon.ImageColor3 = WHITE
	icon.ZIndex = z + 4
	icon.Parent = row

	local label = bold(row, "...", textSize, WHITE, z + 4)
	label.LayoutOrder = 2
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, textSize + 4)

	local function setState(state: string, text: string?)
		local tone = if state == "price" then BUY_GREEN else Color3.fromRGB(120, 128, 146)
		button.BackgroundColor3 = tone
		shadow.BackgroundColor3 = tone:Lerp(Color3.new(0, 0, 0), 0.55)
		grad.Color = ColorSequence.new(tone:Lerp(WHITE, 0.25), tone:Lerp(Color3.new(0, 0, 0), 0.12))
		icon.Visible = state == "price"
		label.Text = text or ""
		button.Active = state == "price"
	end
	setState("price", "...")

	button.MouseButton1Down:Connect(function()
		button.Position = UDim2.fromOffset(0, 4)
	end)
	local function release()
		button.Position = UDim2.fromOffset(0, 0)
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.MouseEnter:Connect(function()
		if button.Active then
			TweenService:Create(holder, TweenInfo.new(0.08), { Rotation = -2 }):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(holder, TweenInfo.new(0.1), { Rotation = 0 }):Play()
	end)

	return { holder = holder, button = button, label = label, icon = icon, setState = setState }
end

-- ─── Pencere ────────────────────────────────────────────────────────────────

function ShopPanel.Create(screen: ScreenGui): Panel
	local root = UiKit.Window(screen, "ShopPanel", HEADER_GREEN)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.new(0.5, -40, 0.5, 0)
	root.Size = UDim2.fromOffset(W, H)
	root.BackgroundColor3 = BODY
	root.Visible = false
	root.ZIndex = Z
	-- Kabuğun kendi gradyanı ve çerçevesi yerine mağazanınki
	for _, child in root:GetChildren() do
		if child:IsA("UIGradient") or child:IsA("UIStroke") then
			child:Destroy()
		end
	end
	gradient(root, BODY, BODY_DEEP)
	border(root, OUTLINE, 4)
	corner(root, 16)

	-- Gövdede nokta deseni: düz koyu yerine perçinli metal panel hissi
	local dots = Instance.new("Frame")
	dots.Name = "Dots"
	dots.Position = UDim2.fromOffset(0, HEADER)
	dots.Size = UDim2.new(1, 0, 1, -HEADER)
	dots.BackgroundTransparency = 1
	dots.ClipsDescendants = true
	dots.ZIndex = Z
	dots.Parent = root
	for y = 0, math.floor((H - HEADER) / 28) do
		for x = 0, math.floor(W / 28) do
			local d = Instance.new("Frame")
			d.Position = UDim2.fromOffset(x * 28 + (y % 2) * 14 + 8, y * 28 + 10)
			d.Size = UDim2.fromOffset(4, 4)
			d.BackgroundColor3 = Color3.new(0, 0, 0)
			d.BackgroundTransparency = 0.72
			d.BorderSizePixel = 0
			d.ZIndex = Z
			d.Parent = dots
			corner(d, 2)
		end
	end

	-- ── Başlık şeridi ──────────────────────────────────────────────────────
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, HEADER)
	header.BackgroundColor3 = HEADER_GREEN
	header.BorderSizePixel = 0
	header.ClipsDescendants = true
	header.ZIndex = Z + 1
	header.Parent = root
	corner(header, 16)
	gradient(header, HEADER_GREEN:Lerp(WHITE, 0.2), HEADER_GREEN:Lerp(Color3.new(0, 0, 0), 0.12))
	-- Alt köşeler düz kalsın: şeridin alt yarısına düz bir örtü
	local foot = Instance.new("Frame")
	foot.Position = UDim2.new(0, 0, 1, -16)
	foot.Size = UDim2.new(1, 0, 0, 16)
	foot.BackgroundColor3 = HEADER_GREEN:Lerp(Color3.new(0, 0, 0), 0.1)
	foot.BorderSizePixel = 0
	foot.ZIndex = Z + 1
	foot.Parent = header
	-- Eğik parlak şeritler
	for i, x in { 0.52, 0.6, 0.66 } do
		local stripe = Instance.new("Frame")
		stripe.AnchorPoint = Vector2.new(0.5, 0.5)
		stripe.Position = UDim2.fromScale(x, 0.5)
		stripe.Size = UDim2.fromOffset(if i == 1 then 46 else 18, 180)
		stripe.Rotation = 30
		stripe.BackgroundColor3 = WHITE
		stripe.BackgroundTransparency = 0.8
		stripe.BorderSizePixel = 0
		stripe.ZIndex = Z + 2
		stripe.Parent = header
	end
	-- Başlığın altında koyu çizgi
	local rule = Instance.new("Frame")
	rule.Position = UDim2.new(0, 0, 0, HEADER - 2)
	rule.Size = UDim2.new(1, 0, 0, 4)
	rule.BackgroundColor3 = OUTLINE
	rule.BorderSizePixel = 0
	rule.ZIndex = Z + 3
	rule.Parent = root

	local title = bold(header, "Shop", 50, WHITE, Z + 4, 5)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Position = UDim2.fromOffset(26, 6)
	title.Size = UDim2.fromOffset(300, 60)

	-- Kırmızı kare X (başlığın sağında)
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -12, 0, HEADER / 2)
	close.Size = UDim2.fromOffset(58, 58)
	close.BackgroundColor3 = Color3.fromRGB(226, 30, 40)
	close.BorderSizePixel = 0
	close.AutoButtonColor = false
	close.Text = ""
	close.ZIndex = Z + 5
	close.Parent = root
	corner(close, 8)
	border(close, OUTLINE, 3)
	gradient(close, Color3.fromRGB(250, 70, 70), Color3.fromRGB(190, 20, 30))
	local x = bold(close, "X", 42, WHITE, Z + 6, 4)
	x.Size = UDim2.fromScale(1, 1)
	close.MouseEnter:Connect(function()
		TweenService:Create(close, TweenInfo.new(0.08), { Rotation = 8 }):Play()
	end)
	close.MouseLeave:Connect(function()
		TweenService:Create(close, TweenInfo.new(0.1), { Rotation = 0 }):Play()
	end)

	-- ── Liste ──────────────────────────────────────────────────────────────
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(18, HEADER + 10)
	list.Size = UDim2.new(1, -30, 1, -HEADER - 18)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = Color3.fromRGB(200, 210, 230)
	list.ScrollBarImageTransparency = 0.3
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ZIndex = Z + 1
	list.Parent = root
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = list
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = list

	local CONTENT_W = W - 30 - 10 - 8
	local order = 0
	local sectionAt: { [string]: GuiObject } = {}

	local function sectionTitle(id: string, text: string, color: Color3)
		order += 1
		local t = bold(list, "-- " .. text .. " --", 40, color, Z + 2, 4)
		t.LayoutOrder = order
		t.Size = UDim2.fromOffset(CONTENT_W, 50)
		sectionAt[id] = t
	end

	local function grid(cellW: number, cellH: number, count: number, cols: number): Frame
		order += 1
		local rows = math.ceil(count / cols)
		local g = Instance.new("Frame")
		g.LayoutOrder = order
		g.Size = UDim2.fromOffset(CONTENT_W, rows * cellH + (rows - 1) * 12)
		g.BackgroundTransparency = 1
		g.ZIndex = Z + 1
		g.Parent = list
		local gl = Instance.new("UIGridLayout")
		gl.CellSize = UDim2.fromOffset(cellW, cellH)
		gl.CellPadding = UDim2.fromOffset(12, 12)
		gl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.Parent = g
		return g
	end

	type Card = { entry: Entry, buy: BuyButton }
	local cards: { Card } = {}

	local function wireBuy(entry: Entry, buy: BuyButton)
		buy.button.MouseButton1Click:Connect(function()
			local def = defOf(entry)
			if not (def and def.id ~= 0 and buy.button.Active) then
				return
			end
			if entry.kind == "pass" then
				MarketplaceService:PromptGamePassPurchase(player, def.id)
			else
				MarketplaceService:PromptProductPurchase(player, def.id)
			end
		end)
		table.insert(cards, { entry = entry, buy = buy })
	end

	-- ── FEATURED: en değerli pass için büyük afiş ──────────────────────────
	sectionTitle("featured", "FEATURED", TITLE_YELLOW)
	do
		local entry = PASSES[1]
		order += 1
		local banner = cardBase(list, Color3.fromRGB(70, 60, 200), UDim2.fromOffset(CONTENT_W, 250), Z + 2, UDim2.fromScale(0.78, 0.5))
		banner.LayoutOrder = order
		-- Mor-maviden altına geçen afiş zemini
		local g = banner:FindFirstChildOfClass("UIGradient") :: UIGradient
		g.Rotation = 0
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 70, 190)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(110, 60, 210)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 170, 40)),
		})
		local rays = banner:FindFirstChild("Rays") :: ImageLabel
		rays.ImageColor3 = Color3.fromRGB(255, 240, 180)
		rays.Size = UDim2.fromOffset(620, 620)

		local ribbon = bold(banner, "BEST VALUE!", 26, WHITE, Z + 5, 3)
		ribbon.Position = UDim2.fromOffset(18, 16)
		ribbon.Size = UDim2.fromOffset(170, 40)
		ribbon.BackgroundTransparency = 0
		ribbon.BackgroundColor3 = Color3.fromRGB(226, 30, 40)
		corner(ribbon, 6)
		border(ribbon, OUTLINE, 3)

		local name = bold(banner, "x2 INCOME PASS", 46, TITLE_YELLOW, Z + 5, 5)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Position = UDim2.fromOffset(200, 12)
		name.Size = UDim2.fromOffset(420, 50)

		local lines = {
			"Every crewmate on your podiums earns " .. hi("DOUBLE", "#7CFF5B") .. " cash",
			"Works on " .. hi("every floor", "#FFE13C") .. " and after rebirth",
			hi("Forever", "#7CFF5B") .. " — buy once, keep it!",
		}
		for i, line in lines do
			local l = bold(banner, "•  " .. line, 22, WHITE, Z + 5, 2.5)
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.Position = UDim2.fromOffset(24, 68 + (i - 1) * 34)
			l.Size = UDim2.fromOffset(560, 30)
		end

		local big = art(banner, entry, 230, Z + 4)
		big.AnchorPoint = Vector2.new(1, 0.5)
		big.Position = UDim2.new(1, -18, 0.5, -8)

		local buy = buyButton(banner, UDim2.fromOffset(250, 62), Z + 5, 34)
		buy.holder.Position = UDim2.fromOffset(24, 172)
		wireBuy(entry, buy)
	end

	-- ── PASSES: iki sütun ──────────────────────────────────────────────────
	sectionTitle("passes", "PASSES", TITLE_YELLOW)
	do
		local cellW = math.floor((CONTENT_W - 12) / 2)
		local g = grid(cellW, 196, #PASSES, 2)
		for i, entry in PASSES do
			local card = cardBase(g, entry.tint, UDim2.fromOffset(cellW, 196), Z + 2, UDim2.fromScale(0.2, 0.5))
			card.LayoutOrder = i
			local a = art(card, entry, 150, Z + 4)
			a.AnchorPoint = Vector2.new(0, 0.5)
			a.Position = UDim2.new(0, 10, 0.5, 0)

			local name = bold(card, entry.title, 34, WHITE, Z + 5, 4)
			name.Position = UDim2.fromOffset(165, 12)
			name.Size = UDim2.new(1, -175, 0, 42)
			name.TextScaled = true
			local nlimit = Instance.new("UITextSizeConstraint")
			nlimit.MaxTextSize = 34
			nlimit.Parent = name

			local blurb = bold(card, entry.blurb, 22, WHITE, Z + 5, 2.5)
			blurb.Position = UDim2.fromOffset(165, 58)
			blurb.Size = UDim2.new(1, -178, 0, 58)
			blurb.TextWrapped = true
			blurb.TextScaled = true
			local blimit = Instance.new("UITextSizeConstraint")
			blimit.MaxTextSize = 22
			blimit.Parent = blurb

			local buy = buyButton(card, UDim2.new(1, -182, 0, 56), Z + 5, 30)
			buy.holder.Position = UDim2.new(0, 165, 1, -70)
			wireBuy(entry, buy)
		end
	end

	-- ── MONEY: üç sütun ────────────────────────────────────────────────────
	sectionTitle("money", "MONEY", Color3.fromRGB(110, 240, 90))
	do
		local cellW = math.floor((CONTENT_W - 24) / 3)
		local g = grid(cellW, 250, #MONEY, 3)
		for i, entry in MONEY do
			local card = cardBase(g, entry.tint, UDim2.fromOffset(cellW, 250), Z + 2, UDim2.fromScale(0.5, 0.36))
			card.LayoutOrder = i
			local a = art(card, entry, 150, Z + 4)
			a.AnchorPoint = Vector2.new(0.5, 0)
			a.Position = UDim2.new(0.5, 0, 0, 6)
			local amount = bold(card, entry.title, 40, WHITE, Z + 5, 4)
			amount.AnchorPoint = Vector2.new(0.5, 0)
			amount.Position = UDim2.new(0.5, 0, 0, 142)
			amount.Size = UDim2.new(1, -20, 0, 44)
			local buy = buyButton(card, UDim2.new(1, -36, 0, 54), Z + 5, 30)
			buy.holder.AnchorPoint = Vector2.new(0.5, 1)
			buy.holder.Position = UDim2.new(0.5, 0, 1, -10)
			wireBuy(entry, buy)
		end
	end

	-- ── POTIONS: dört sütun ────────────────────────────────────────────────
	sectionTitle("potions", "POTIONS", Color3.fromRGB(120, 255, 200))
	do
		local cellW = math.floor((CONTENT_W - 36) / 4)
		local g = grid(cellW, 262, #POTIONS, 4)
		for i, entry in POTIONS do
			local card = cardBase(g, entry.tint, UDim2.fromOffset(cellW, 262), Z + 2, UDim2.fromScale(0.5, 0.34))
			card.LayoutOrder = i
			local a = art(card, entry, 130, Z + 4)
			a.AnchorPoint = Vector2.new(0.5, 0)
			a.Position = UDim2.new(0.5, 0, 0, 8)
			local name = bold(card, entry.title, 26, WHITE, Z + 5, 3)
			name.AnchorPoint = Vector2.new(0.5, 0)
			name.Position = UDim2.new(0.5, 0, 0, 136)
			name.Size = UDim2.new(1, -12, 0, 30)
			-- Süre ve etki Config'ten: iksir değişirse kart kendiliğinden doğru kalır
			local product = Config.Products[entry.key]
			local potion = product and product.potion and Config.GetPotion(product.potion)
			local minutes = if potion then math.floor(potion.seconds / 60 + 0.5) else 0
			local info = bold(card, if potion then string.format("%d MIN", minutes) else "", 20, TITLE_YELLOW, Z + 5, 2.5)
			info.AnchorPoint = Vector2.new(0.5, 0)
			info.Position = UDim2.new(0.5, 0, 0, 166)
			info.Size = UDim2.new(1, -12, 0, 24)
			local buy = buyButton(card, UDim2.new(1, -24, 0, 52), Z + 5, 28)
			buy.holder.AnchorPoint = Vector2.new(0.5, 1)
			buy.holder.Position = UDim2.new(0.5, 0, 1, -10)
			wireBuy(entry, buy)
		end
	end

	-- ── BOOSTS: üç sütun ───────────────────────────────────────────────────
	sectionTitle("boosts", "BOOSTS", Color3.fromRGB(120, 200, 255))
	do
		local cellW = math.floor((CONTENT_W - 24) / 3)
		local g = grid(cellW, 262, #BOOSTS, 3)
		for i, entry in BOOSTS do
			local card = cardBase(g, entry.tint, UDim2.fromOffset(cellW, 262), Z + 2, UDim2.fromScale(0.5, 0.34))
			card.LayoutOrder = i
			local a = art(card, entry, 124, Z + 4)
			a.AnchorPoint = Vector2.new(0.5, 0)
			a.Position = UDim2.new(0.5, 0, 0, 8)
			local name = bold(card, entry.title, 26, WHITE, Z + 5, 3)
			name.AnchorPoint = Vector2.new(0.5, 0)
			name.Position = UDim2.new(0.5, 0, 0, 130)
			name.Size = UDim2.new(1, -12, 0, 30)
			local blurb = bold(card, entry.blurb, 17, WHITE, Z + 5, 2)
			blurb.AnchorPoint = Vector2.new(0.5, 0)
			blurb.Position = UDim2.new(0.5, 0, 0, 160)
			blurb.Size = UDim2.new(1, -16, 0, 38)
			blurb.TextWrapped = true
			local buy = buyButton(card, UDim2.new(1, -24, 0, 52), Z + 5, 28)
			buy.holder.AnchorPoint = Vector2.new(0.5, 1)
			buy.holder.Position = UDim2.new(0.5, 0, 1, -10)
			wireBuy(entry, buy)
		end
	end

	-- ── Sağdaki bölüm düğmeleri (pencerenin dışında) ───────────────────────
	local rail = Instance.new("Frame")
	rail.Name = "Sections"
	rail.AnchorPoint = Vector2.new(0, 0)
	rail.Position = UDim2.new(1, 14, 0, 6)
	rail.Size = UDim2.fromOffset(130, H - 12)
	rail.BackgroundTransparency = 1
	rail.ZIndex = Z
	rail.Parent = root
	local railList = Instance.new("UIListLayout")
	railList.Padding = UDim.new(0, 6)
	railList.SortOrder = Enum.SortOrder.LayoutOrder
	railList.Parent = rail

	local function scrollTo(id: string)
		local target = sectionAt[id]
		if not target then
			return
		end
		--[[
			AbsolutePosition ekran pikselinde (DeviceScale ve açılış ölçeği
			dahil), CanvasPosition ise listenin kendi biriminde: fark ölçeğe
			bölünüyor, yoksa küçük ekranda bölümün altına kayıyordu.
		]]
		local scale = math.max(0.1, root.AbsoluteSize.X / W)
		local y = (target.AbsolutePosition.Y - list.AbsolutePosition.Y) / scale + list.CanvasPosition.Y
		TweenService:Create(list, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CanvasPosition = Vector2.new(0, math.max(0, y - 4)) }):Play()
	end

	local RAIL: { { id: string, text: string, entry: Entry, color: Color3 } } = {
		{ id = "featured", text = "Featured", entry = PASSES[1], color = TITLE_YELLOW },
		{ id = "passes", text = "Passes", entry = PASSES[2], color = Color3.fromRGB(220, 170, 255) },
		{ id = "money", text = "Money", entry = MONEY[2], color = Color3.fromRGB(120, 240, 100) },
		{ id = "potions", text = "Potions", entry = POTIONS[1], color = Color3.fromRGB(120, 255, 200) },
		{ id = "boosts", text = "Boosts", entry = BOOSTS[2], color = Color3.fromRGB(120, 200, 255) },
	}
	for i, spec in RAIL do
		local b = Instance.new("TextButton")
		b.LayoutOrder = i
		b.Size = UDim2.fromOffset(130, 104)
		b.BackgroundTransparency = 1
		b.Text = ""
		b.ZIndex = Z + 1
		b.Parent = rail
		local a = art(b, spec.entry, 84, Z + 2)
		a.AnchorPoint = Vector2.new(0.5, 0)
		a.Position = UDim2.new(0.5, 0, 0, 0)
		local l = bold(b, spec.text, 26, spec.color, Z + 4, 3.5)
		l.AnchorPoint = Vector2.new(0.5, 1)
		l.Position = UDim2.new(0.5, 0, 1, -2)
		l.Size = UDim2.new(1, 0, 0, 30)
		b.MouseEnter:Connect(function()
			TweenService:Create(a, TweenInfo.new(0.1), { Rotation = -8 }):Play()
		end)
		b.MouseLeave:Connect(function()
			TweenService:Create(a, TweenInfo.new(0.12), { Rotation = 0 }):Play()
		end)
		b.MouseButton1Click:Connect(function()
			scrollTo(spec.id)
		end)
	end

	-- ─── Fiyat ve sahiplik ──────────────────────────────────────────────────

	--[[
		Fiyatlar Roblox'tan geliyor ve ağ çağrısı: panel her açıldığında
		sorulsa kota yenirdi. Bir kez çekilip saklanıyor.
	]]
	local priceCache: { [string]: string } = {}
	local ownedCache: { [string]: boolean } = {}

	local function infoType(kind: string): Enum.InfoType
		return if kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product
	end

	local function refreshCard(card: Card)
		local def = defOf(card.entry)
		if not def then
			return
		end
		if def.id == 0 then
			card.buy.setState("soon", "SOON")
		elseif ownedCache[card.entry.key] then
			card.buy.setState("owned", "OWNED")
		else
			card.buy.setState("price", priceCache[card.entry.key] or "...")
		end
	end

	for _, card in cards do
		refreshCard(card)
	end

	--[[
		Hepsi tek görevde, sırayla; aynı ürün iki kartta olabilir (FEATURED
		ve PASSES), o yüzden anahtar başına bir kez soruluyor.
	]]
	task.spawn(function()
		local asked: { [string]: boolean } = {}
		for _, card in cards do
			local key = card.entry.key
			local def = defOf(card.entry)
			if def and def.id ~= 0 and not asked[key] then
				asked[key] = true
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(def.id, infoType(card.entry.kind))
				end)
				priceCache[key] = if ok and typeof(info) == "table" and info.PriceInRobux
					then tostring(info.PriceInRobux)
					else "BUY"
				if card.entry.kind == "pass" then
					local owns = false
					pcall(function()
						owns = MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.id)
					end)
					ownedCache[key] = owns
				end
			end
			for _, other in cards do
				if other.entry.key == key then
					refreshCard(other)
				end
			end
		end
	end)

	-- Oyun içinde pass alınırsa kart hemen OWNED'a dönsün
	local finished = MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(who: Player, passId: number, purchased: boolean)
			if who ~= player or not purchased then
				return
			end
			for _, card in cards do
				local def = defOf(card.entry)
				if def and def.id == passId then
					ownedCache[card.entry.key] = true
					refreshCard(card)
				end
			end
		end
	)

	-- ─── Aç / kapa ──────────────────────────────────────────────────────────

	--[[ Açılış: hafif büyüyerek gelsin (UIScale, DeviceScale'e dokunmadan). ]]
	local pop = Instance.new("UIScale")
	pop.Parent = root
	local function open(section: string?)
		root.Visible = true
		pop.Scale = 0.9
		TweenService:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if section then
			task.defer(scrollTo, section)
		end
	end

	close.MouseButton1Click:Connect(function()
		root.Visible = false
	end)

	return {
		Toggle = function()
			if root.Visible then
				root.Visible = false
			else
				open(nil)
			end
		end,
		Open = open,
		Close = function()
			root.Visible = false
		end,
		Destroy = function()
			finished:Disconnect()
			root:Destroy()
		end,
	}
end

return ShopPanel
