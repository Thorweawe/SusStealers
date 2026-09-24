--!strict
--[[
	Arayüzün ortak görsel dili.

	NEDEN VAR: paneller ayrı ayrı yazıldı ve her biri kendi köşe yarıçapını,
	kendi kenarlığını, kendi başlık düzenini kurdu. Aynı oyunda beş farklı
	kutu tasarımı oldu. Rebirth paneli doğru dili kurdu; burası o dili
	herkesin kullanabileceği yere taşıyor.

	═══ KURAL: HAZIR GÖRSEL YOK ═══════════════════════════════════════════

	Her şey Frame'den kuruluyor. Mağazadan ikon indirmek daha kolay olurdu
	ama oyunun geri kalanı — karakterler, üsler, istasyon — tamamen koddan
	üretilmiş geometri. Araya yapıştırılan hazır resimler o dille çelişir
	ve arayüz oyunun değil, başka bir şeyin parçası gibi durur.

	Ayrıca denendi: mağaza görselleri bu yerde YÜKLENMİYOR (yirmi aday
	denendi, sıfırı çalıştı). Yani bu kural hem estetik hem pratik.

	═══ MÜRETTEBAT SİLUETİ ════════════════════════════════════════════════

	Oyunun her yerinde aynı üç parça: kapsül gövde, sırt çantası, vizör.
	UnitModel 3B'de bunu kuruyor, burası arayüzde aynısını kuruyor. Oyuncu
	arayüzdeki figürle sahadaki karakteri aynı şey olarak okuyor.

	Among Us'tan HAZIR VARLIK KOPYALANMIYOR — kullanılan şey siluetin
	kendisi: kapsül + vizör oranı. Oyun zaten baştan sona bu dilde.
]]

local UiKit = {}

-- ─── Palet ──────────────────────────────────────────────────────────────────
-- Panel kabuğu her yerde aynı; vurgu rengi panele göre değişiyor.

UiKit.SHELL = Color3.fromRGB(26, 30, 38)
UiKit.SHELL_DEEP = Color3.fromRGB(18, 21, 27)
UiKit.ROW = Color3.fromRGB(33, 38, 48)
UiKit.INK = Color3.fromRGB(236, 241, 248)
UiKit.MUTED = Color3.fromRGB(150, 163, 180)
UiKit.DIM = Color3.fromRGB(88, 98, 114)
UiKit.GOOD = Color3.fromRGB(128, 224, 150)
UiKit.WARN = Color3.fromRGB(240, 180, 80)
UiKit.BAD = Color3.fromRGB(226, 108, 96)

-- Vizör camgöbeği: Among Us tulumunun tek sabit rengi, temanın imzası
UiKit.VISOR = Color3.fromRGB(150, 222, 236)

--[[
	Mürettebat tulumu renkleri. build_decor.luau'daki CREW tablosuyla aynı
	değerler: heykellerle arayüz aynı paletten konuşsun diye.

	HUD düğmeleri buradan renk alıyor. Rastgele seçilmiyorlar — her düğme
	işine yakın düşen tulumu giyiyor (mağaza yeşil, indeks camgöbeği,
	iksir açık yeşil, unvan mor, rebirth turuncu).
]]
UiKit.CREW = {
	RED    = Color3.fromRGB(198,  53,  62),
	BLUE   = Color3.fromRGB( 19,  46, 209),
	GREEN  = Color3.fromRGB( 17, 128,  45),
	PINK   = Color3.fromRGB(238, 132, 195),
	ORANGE = Color3.fromRGB(240, 125,  13),
	YELLOW = Color3.fromRGB(245, 245,  87),
	BLACK  = Color3.fromRGB( 63,  71,  78),
	WHITE  = Color3.fromRGB(215, 224, 223),
	PURPLE = Color3.fromRGB(107,  47, 188),
	BROWN  = Color3.fromRGB(113,  73,  30),
	CYAN   = Color3.fromRGB( 56, 254, 220),
	LIME   = Color3.fromRGB( 80, 239,  57),
}

-- ─── Temel parçalar ─────────────────────────────────────────────────────────

--[[
	Kapsayıcının katman numarası.

	NEDEN GEREKLİ: ScreenGui'ler Sibling davranışında, yani ZIndex GLOBAL
	sıralıyor — çocuk olmak üste çıkarmıyor. Bir düğmenin (ZIndex 3) içine
	varsayılan ZIndex 1 ile ikon çizersen ikon düğmenin ALTINDA kalıyor ve
	hiç görünmüyor. Bu yüzden her ikon kendi katmanını kapsayıcısından
	türetiyor.
]]
local function baseZ(parent: Instance): number
	if parent:IsA("GuiObject") then
		return parent.ZIndex
	end
	return 1
end

function UiKit.Corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

function UiKit.Stroke(parent: Instance, color: Color3, thickness: number, transparency: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency
	s.Parent = parent
	return s
end

--[[
	═══ TEK PENCERE KURALI ═══════════════════════════════════════════════

	Ekranın ortasında açılan pencereler (mağaza, indeks, görevler, petler,
	yükseltme...) aynı anda yalnızca BİR tane açık olabilir. Eskiden SHOP
	açıkken INDEX'e basınca ikisi üst üste açık kalıyor, INDEX kapanınca
	altında SHOP duruyordu.

	Her pencere kaydını kendisi yaptırıyor; bir tanesi görünür olduğu an
	diğerleri kapanıyor. Pencereler birbirini tanımak zorunda değil — kural
	tek yerde, Visible değişimine bağlı.
]]
local exclusive: { GuiObject } = {}

--[[
	Pencere açılınca haber alınacak dinleyiciler. DeviceLayout gamepad
	seçimini pencerenin içine taşımak için kullanıyor; pencereler bunu
	bilmek zorunda değil.
]]
local openedListeners: { (GuiObject) -> () } = {}

function UiKit.OnWindowOpened(listener: (GuiObject) -> ())
	table.insert(openedListeners, listener)
end

function UiKit.Exclusive(frame: GuiObject)
	table.insert(exclusive, frame)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not frame.Visible then
			return
		end
		for _, other in exclusive do
			if other ~= frame and other.Visible then
				other.Visible = false
			end
		end
		for _, listener in openedListeners do
			task.spawn(listener, frame)
		end
	end)
	frame.Destroying:Connect(function()
		local index = table.find(exclusive, frame)
		if index then
			table.remove(exclusive, index)
		end
	end)
end

--[[
	Panel kabuğu: köşeleri yuvarlak, vurgu renginde ince kenarlıklı kutu.
	Bütün paneller bundan başlıyor, böylece hepsi aynı ağırlıkta duruyor.
]]
function UiKit.Shell(parent: Instance, name: string, accent: Color3): Frame
	local root = Instance.new("Frame")
	root.Name = name
	root.BackgroundColor3 = UiKit.SHELL
	root.BorderSizePixel = 0
	root.Parent = parent
	UiKit.Corner(root, 14)
	--[[
		Kenarlık kalın ve belirgin: Among Us menüleri koyu zemin üstüne
		kalın açık çerçeveyle okunuyor. 1.4 kalınlık ve yarı saydamken panel
		sahnenin içinde eriyordu.
	]]
	UiKit.Stroke(root, accent:Lerp(Color3.new(1, 1, 1), 0.15), 2.6, 0.08)
	-- Üstten aşağı hafif açılan zemin: düz tek renk kutu yerine hacim
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(
		UiKit.SHELL:Lerp(accent, 0.07):Lerp(Color3.new(1, 1, 1), 0.03),
		UiKit.SHELL_DEEP
	)
	grad.Parent = root
	return root
end

--[[
	Ortada açılan pencere: Shell + tek pencere kuralı. Pencere panelleri
	bunu kullanıyor; HUD'da sürekli duran kutular (sıralama tablosu gibi)
	düz Shell kullanıyor.
]]
function UiKit.Window(parent: Instance, name: string, accent: Color3): Frame
	local root = UiKit.Shell(parent, name, accent)
	UiKit.Exclusive(root)
	return root
end

--[[
	Panel başlığı: solda kalın ad, altında sönük alt başlık.

	Ad GothamBlack çünkü panel başlıkları oyunun en üst düzey işaretleri;
	satır içi metinle aynı ağırlıkta olurlarsa hiyerarşi kayboluyor.
]]
function UiKit.Heading(parent: Frame, text: string, accent: Color3): (TextLabel, TextLabel)
	local title = Instance.new("TextLabel")
	title.Name = "Heading"
	title.Position = UDim2.fromOffset(18, 12)
	title.Size = UDim2.new(1, -60, 0, 24)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 19
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = accent
	title.Text = text
	title.Parent = parent

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Position = UDim2.fromOffset(18, 34)
	sub.Size = UDim2.new(1, -60, 0, 15)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextSize = 12
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextColor3 = UiKit.MUTED
	sub.Text = ""
	sub.Parent = parent

	return title, sub
end

--[[
	Mürettebat silueti.

	Üç parça, oyunun her yerindekiyle aynı: kapsül gövde, sırt çantası,
	vizör. `size` gövdenin yüksekliği; kalan ölçüler ondan türetiliyor ki
	her boyutta aynı oranda dursun.

	Vizör gövdenin üst yarısında ve sola kaymış — figüre yön veriyor,
	karşıya bakan bir yüz olmaktan çıkarıp "birine bakıyor" hâline
	getiriyor.
]]
function UiKit.Crewmate(parent: Instance, size: number, color: Color3): Frame
	local z = baseZ(parent)

	local body = Instance.new("Frame")
	body.Name = "Crewmate"
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromOffset(size * 0.78, size)
	body.BackgroundColor3 = color
	body.BorderSizePixel = 0
	body.ZIndex = z + 1
	body.Parent = parent
	UiKit.Corner(body, math.floor(size * 0.36))

	local pack = Instance.new("Frame")
	pack.Name = "Pack"
	pack.AnchorPoint = Vector2.new(0.5, 0.5)
	pack.Position = UDim2.fromScale(1.0, 0.54)
	pack.Size = UDim2.fromOffset(size * 0.24, size * 0.50)
	pack.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.22)
	pack.BorderSizePixel = 0
	pack.ZIndex = z
	pack.Parent = body
	UiKit.Corner(pack, math.floor(size * 0.11))

	local visor = Instance.new("Frame")
	visor.Name = "Visor"
	visor.AnchorPoint = Vector2.new(0.5, 0.5)
	visor.Position = UDim2.fromScale(0.42, 0.33)
	visor.Size = UDim2.fromOffset(size * 0.50, size * 0.26)
	visor.BackgroundColor3 = UiKit.VISOR
	visor.BorderSizePixel = 0
	visor.ZIndex = z + 2
	visor.Parent = body
	UiKit.Corner(visor, math.floor(size * 0.12))

	return body
end

--[[
	Kapatma düğmesi: panelin sağ üstünde, hep aynı yerde ve aynı boyutta.
	Oyuncu bir panelde öğrendiği yeri diğerinde de bulmalı.
]]
--[[
	Among Us'ın kapatma düğmesi gibi: kırmızı daire, beyaz kontur, beyaz X.
	Koyu kare bir "X" panelin içinde kayboluyordu; kırmızı daire her
	pencerede ilk bakışta bulunuyor.
]]
function UiKit.CloseButton(parent: Frame): TextButton
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 10)
	close.Size = UDim2.fromOffset(30, 30)
	close.BackgroundColor3 = UiKit.CREW.RED
	close.BorderSizePixel = 0
	close.Font = Enum.Font.FredokaOne
	close.TextSize = 17
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "X"
	close.AutoButtonColor = false
	close.ZIndex = parent.ZIndex + 6
	close.Parent = parent
	UiKit.Corner(close, 15)
	UiKit.Stroke(close, Color3.new(1, 1, 1), 2, 0.1)

	local base = UiKit.CREW.RED
	close.MouseEnter:Connect(function()
		close.BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.18)
	end)
	close.MouseLeave:Connect(function()
		close.BackgroundColor3 = base
	end)

	return close
end

--[[
	Tehlike şeridi: sarı-siyah eğik bantlar.

	Among Us'un görev panellerindeki en tanınır dokusu ve oyunun 3B
	dünyasında da var (HazardStrip). Arayüzde de kullanmak ikisini aynı
	yere bağlıyor. Süs değil: "burada dikkat et" diyen bir işaret, o
	yüzden yalnızca uyarı ve bekleme durumlarında.
]]
function UiKit.HazardBar(parent: Instance, height: number): Frame
	local bar = Instance.new("Frame")
	bar.Name = "Hazard"
	bar.Size = UDim2.new(1, 0, 0, height)
	bar.BackgroundColor3 = Color3.fromRGB(28, 26, 18)
	bar.BorderSizePixel = 0
	bar.ClipsDescendants = true
	bar.Parent = parent

	for i = 0, 11 do
		local stripe = Instance.new("Frame")
		stripe.AnchorPoint = Vector2.new(0, 0.5)
		stripe.Position = UDim2.new(i / 12, -height, 0.5, 0)
		stripe.Size = UDim2.fromOffset(height * 0.9, height * 3)
		stripe.Rotation = 24
		stripe.BackgroundColor3 = UiKit.WARN
		stripe.BackgroundTransparency = 0.25
		stripe.BorderSizePixel = 0
		stripe.Parent = bar
	end

	return bar
end

-- ─── Kabartma düğmeler ──────────────────────────────────────────────────────
--[[
	HUD düğmelerinin ortak gövdesi.

	NEDEN: eskiden hepsi düz, koyu, saydam dikdörtgenlerdi ve sahnenin
	üstünde kayboluyordu. Bu tür (tycoon) oyunlarda düğme BASILACAK bir
	nesne gibi duruyor: renkli dolgu, üstten aşağı degrade, üst kenarda
	ışık, altında gölge. Oyuncu ekrana bakınca nereye dokunacağını
	aramıyor.

	Üç katman gerekiyor çünkü UIStroke tek renk veriyor; kabartma hissi
	altta koyu + üstte açık ikilisinden çıkıyor.

	`holder` düzen yuvasını tutuyor (UIListLayout onu sayıyor), düğme
	onun içinde 4 piksel yukarıda duruyor — gölge o boşlukta görünüyor.
]]
function UiKit.Raised(parent: Instance, name: string, tint: Color3, size: UDim2, radius: number): (Frame, TextButton)
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.Size = size
	holder.BackgroundTransparency = 1
	holder.Parent = parent

	local shadow = Instance.new("Frame")
	shadow.Name = "Shadow"
	shadow.Size = UDim2.new(1, 0, 1, 0)
	shadow.BackgroundColor3 = tint:Lerp(Color3.new(0, 0, 0), 0.78)
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 2
	shadow.Parent = holder
	UiKit.Corner(shadow, radius)

	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.Size = UDim2.new(1, 0, 1, -4)
	button.BackgroundColor3 = tint
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = 3
	button.Parent = holder
	UiKit.Corner(button, radius)
	UiKit.Stroke(button, tint:Lerp(Color3.new(0, 0, 0), 0.55), 2, 0)

	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(
		tint:Lerp(Color3.new(1, 1, 1), 0.22),
		tint:Lerp(Color3.new(0, 0, 0), 0.18)
	)
	grad.Parent = button

	-- Üst kenardaki ince ışık: yüzeyin dışbükey okunmasını sağlayan tek şey
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.Position = UDim2.fromOffset(4, 3)
	gloss.Size = UDim2.new(1, -8, 0, 3)
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.68
	gloss.BorderSizePixel = 0
	gloss.ZIndex = 4
	gloss.Parent = button
	UiKit.Corner(gloss, 2)

	--[[
		Basma geri bildirimi: düğme gölgesinin üstüne oturuyor. AutoButtonColor
		rengi soldurup kabartmayı düzleştiriyordu, o yüzden kapalı.
	]]
	button.MouseButton1Down:Connect(function()
		button.Position = UDim2.fromOffset(0, 4)
	end)
	local function release()
		button.Position = UDim2.fromOffset(0, 0)
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)

	return holder, button
end

--[[
	Sol kenardaki geniş düğme: solda ikon yuvası, yanında kalın etiket.
	Dönen üçüncü değer ikon yuvası — çağıran içine istediği figürü çiziyor.
]]
function UiKit.WideButton(parent: Instance, name: string, tint: Color3, label: string): (Frame, TextButton, Frame)
	local holder, button = UiKit.Raised(parent, name, tint, UDim2.fromOffset(196, 60), 14)

	local slot = Instance.new("Frame")
	slot.Name = "Icon"
	slot.AnchorPoint = Vector2.new(0, 0.5)
	slot.Position = UDim2.new(0, 10, 0.5, 0)
	slot.Size = UDim2.fromOffset(40, 40)
	slot.BackgroundColor3 = tint:Lerp(Color3.new(0, 0, 0), 0.42)
	slot.BorderSizePixel = 0
	slot.ZIndex = 4
	slot.Parent = button
	UiKit.Corner(slot, 10)

	local text = Instance.new("TextLabel")
	text.Name = "Label"
	text.Position = UDim2.new(0, 58, 0, 0)
	text.Size = UDim2.new(1, -66, 1, 0)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextSize = 22
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.45
	text.Text = label
	text.ZIndex = 5
	text.Parent = button

	return holder, button, slot
end

--[[
	Sağ kenardaki kare ikon düğmesi. Etiket ikonun altında küçük; ikon
	tek başına ne olduğunu söylemiyorsa yazı kurtarıyor ama yer kaplamıyor.
]]
function UiKit.IconButton(parent: Instance, name: string, tint: Color3, label: string): (Frame, TextButton, Frame)
	local holder, button = UiKit.Raised(parent, name, tint, UDim2.fromOffset(64, 68), 14)

	local slot = Instance.new("Frame")
	slot.Name = "Icon"
	slot.AnchorPoint = Vector2.new(0.5, 0)
	slot.Position = UDim2.new(0.5, 0, 0, 8)
	slot.Size = UDim2.fromOffset(34, 34)
	slot.BackgroundTransparency = 1
	slot.ZIndex = 4
	slot.Parent = button

	local text = Instance.new("TextLabel")
	text.Name = "Label"
	text.AnchorPoint = Vector2.new(0.5, 1)
	text.Position = UDim2.new(0.5, 0, 1, -4)
	text.Size = UDim2.new(1, -4, 0, 14)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextSize = 11
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.5
	text.Text = label
	text.ZIndex = 5
	text.Parent = button

	return holder, button, slot
end

--[[
	Sol alttaki sayaç hapı: solda yuvarlak ikon, yanında kalın sayı ve
	altında küçük alt satır.

	Nakit ve çalma hızı aynı kalıpta çünkü ikisi de "şu an neyim var"
	bilgisi; farklı kutularda dursalar göz ikisini ayrı ayrı arardı.
]]
function UiKit.StatPill(parent: Instance, name: string, tint: Color3): (Frame, Frame, TextLabel, TextLabel)
	local pill = Instance.new("Frame")
	pill.Name = name
	pill.Size = UDim2.fromOffset(232, 50)
	pill.BackgroundColor3 = UiKit.SHELL_DEEP
	pill.BackgroundTransparency = 0.12
	pill.BorderSizePixel = 0
	pill.ZIndex = 2
	pill.Parent = parent
	UiKit.Corner(pill, 25)
	UiKit.Stroke(pill, tint, 1.6, 0.55)

	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0, 0.5)
	disc.Position = UDim2.new(0, 5, 0.5, 0)
	disc.Size = UDim2.fromOffset(40, 40)
	disc.BackgroundColor3 = tint:Lerp(Color3.new(0, 0, 0), 0.62)
	disc.BorderSizePixel = 0
	disc.ZIndex = 3
	disc.Parent = pill
	UiKit.Corner(disc, 20)

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.Position = UDim2.new(0, 54, 0, 5)
	value.Size = UDim2.new(1, -64, 0, 26)
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.GothamBlack
	value.TextSize = 22
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextColor3 = tint
	value.TextStrokeTransparency = 0.5
	value.Text = "—"
	value.ZIndex = 3
	value.Parent = pill

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Position = UDim2.new(0, 54, 0, 29)
	sub.Size = UDim2.new(1, -64, 0, 15)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextSize = 12
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextColor3 = UiKit.MUTED
	sub.Text = ""
	sub.ZIndex = 3
	sub.Parent = pill

	return pill, disc, value, sub
end

-- ─── İkonlar ────────────────────────────────────────────────────────────────
-- Hepsi Frame'den; dosyanın başındaki "hazır görsel yok" kuralı geçerli.

--[[ Yuvadaki her şeyi siler. İkon değişen yerlerde gerekiyor. ]]
function UiKit.ClearSlot(slot: Instance)
	for _, child in slot:GetChildren() do
		child:Destroy()
	end
end

--[[
	İkon çizim yardımcısı: kare bir tuval (holder) ve üstüne oranla
	yerleşen yuvarlak köşeli şekiller. Bütün ikonlar aynı dilde çiziliyor:
	dolgun gövde, koyu kontur yerine koyu ikinci ton, sol üstte beyaz
	parlama. Oranlar tuvale göre (0..1), yani her boyutta aynı duruyor.
]]
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)

local function canvas(parent: Instance, name: string, size: number): Frame
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.ZIndex = baseZ(parent)
	holder.Parent = parent
	return holder
end

-- Tuvalde şekil: konum/boyut oranla, `round` 0..0.5 köşe oranı
local function shape(holder: Frame, x: number, y: number, w: number, h: number, color: Color3, zOff: number, round: number?, rot: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Rotation = rot or 0
	f.ZIndex = holder.ZIndex + zOff
	f.Parent = holder
	if round and round > 0 then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(round, 0)
		c.Parent = f
	end
	return f
end

-- Halka (içi boş daire). `gap` verilirse halkanın bir kısmı saydam kalıyor.
local function ring(holder: Frame, x: number, y: number, w: number, h: number, color: Color3, thick: number, zOff: number, gap: number?, gapRot: number?): Frame
	local f = shape(holder, x, y, w, h, color, zOff, 0.5)
	f.BackgroundTransparency = 1
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thick
	s.Parent = f
	if gap then
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1 - gap - 0.001, 0),
			NumberSequenceKeypoint.new(1 - gap, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Rotation = gapRot or 0
		g.Parent = s
	end
	return f
end

--[[
	İksir şişesi: yuvarlak dipli laboratuvar şişesi, mantar tıpa, içinde
	kabarcıklı sıvı.

	Önceki çizimin gövdesi koyu doluydu ve dikdörtgen sıvı yuvarlak
	gövdeden taşıyordu; düğmede siyah bir bomba gibi duruyordu. Şimdi cam
	açık, sıvı gövdenin içinde ikinci bir daire. Sıvı miktarı adede göre;
	boşken şişe soluk ve boş.
]]
function UiKit.Vial(parent: Instance, size: number, tint: Color3, fill: number, active: boolean): Frame
	local h = canvas(parent, "Vial", size)
	local glass = Color3.fromRGB(214, 236, 246)
	local amount = if active then math.clamp(fill, 0.35, 1) else 0

	shape(h, 0.5, 0.1, 0.24, 0.12, Color3.fromRGB(168, 118, 78), 3, 0.3)          -- tıpa
	local neck = shape(h, 0.5, 0.27, 0.26, 0.26, glass, 1, 0.2)
	neck.BackgroundTransparency = if active then 0.25 else 0.55
	local body = shape(h, 0.5, 0.64, 0.74, 0.66, glass, 1, 0.5)
	body.BackgroundTransparency = if active then 0.25 else 0.55
	if amount > 0 then
		local d = 0.66 * (0.55 + 0.45 * amount)
		shape(h, 0.5, 0.97 - d / 2 - 0.02, d * 1.08, d, tint, 2, 0.5)
		shape(h, 0.42, 0.72, 0.1, 0.1, WHITE, 3, 0.5).BackgroundTransparency = 0.25
		shape(h, 0.58, 0.8, 0.07, 0.07, WHITE, 3, 0.5).BackgroundTransparency = 0.35
	end
	shape(h, 0.34, 0.5, 0.12, 0.16, WHITE, 3, 0.5, -20).BackgroundTransparency = 0.3 -- parlama
	return h
end

--[[
	İkmal sandığı: mağazanın ikonu.

	Alışveriş arabası yerine sandık, çünkü Skeld'de araba yok — üsse gelen
	her şey kargo sandığında geliyor ve oyunun 3B dünyasında da o sandıklar
	duruyor (koridordaki Crate).
]]
function UiKit.Crate(parent: Instance, size: number, tint: Color3): Frame
	local box = Instance.new("Frame")
	box.Name = "Crate"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.fromOffset(size, size * 0.84)
	box.BackgroundColor3 = tint
	box.BorderSizePixel = 0
	box.ZIndex = baseZ(parent) + 1
	box.Parent = parent
	UiKit.Corner(box, math.max(2, math.floor(size * 0.12)))

	-- Kapak şeridi: sandığı düz kareden ayıran tek işaret
	local lid = Instance.new("Frame")
	lid.Size = UDim2.new(1, 0, 0, math.max(3, size * 0.22))
	lid.BackgroundColor3 = tint:Lerp(Color3.new(0, 0, 0), 0.4)
	lid.BorderSizePixel = 0
	lid.ZIndex = box.ZIndex + 1
	lid.Parent = box

	for _, dir in { -1, 1 } do
		local strap = Instance.new("Frame")
		strap.AnchorPoint = Vector2.new(0.5, 0.5)
		strap.Position = UDim2.fromScale(0.5, 0.58)
		strap.Size = UDim2.fromOffset(size * 1.05, math.max(2, size * 0.13))
		strap.Rotation = dir * 34
		strap.BackgroundColor3 = tint:Lerp(Color3.new(0, 0, 0), 0.4)
		strap.BorderSizePixel = 0
		strap.ZIndex = box.ZIndex + 1
		strap.Parent = box
	end

	return box
end

--[[
	Yumurta: pet yumurtalarının ikonu.

	Daire değil OVAL — daire madeni parayla karışıyordu ve iki şey aynı
	panelde yan yana duruyor. Üstteki çatlak çizgisi ikinci işaret:
	"bu açılacak bir şey" diyor.
]]
function UiKit.Egg(parent: Instance, size: number, tint: Color3): Frame
	--[[
		Yumurta: dar üst + geniş alt iki elipsten; üstünde üç benek ve
		parlama. Eskiden tek oval + yatay çatlak çizgisiydi ve küçük
		boyutta bir hap gibi okunuyordu.
	]]
	local h = canvas(parent, "Egg", size)
	local shade = tint:Lerp(BLACK, 0.18)
	shape(h, 0.5, 0.62, 0.78, 0.7, shade, 1, 0.5)                -- alt gölge
	shape(h, 0.5, 0.6, 0.74, 0.68, tint, 2, 0.5)                 -- geniş alt
	shape(h, 0.5, 0.36, 0.56, 0.62, tint, 2, 0.5)                -- dar üst
	local spot = tint:Lerp(WHITE, 0.5)
	shape(h, 0.62, 0.36, 0.16, 0.13, spot, 3, 0.5, 20)
	shape(h, 0.38, 0.62, 0.2, 0.15, spot, 3, 0.5, -15)
	shape(h, 0.64, 0.72, 0.12, 0.1, spot, 3, 0.5)
	shape(h, 0.38, 0.28, 0.1, 0.18, WHITE, 3, 0.5, 20).BackgroundTransparency = 0.25
	return h
end

--[[
	Pet figürü: 3B modelin biçimini (PetModel.FormOf) 2B'de çiziyor.

	Önceden her pet arayüzde aynı mürettebat siluetiydi ve yalnızca
	rengi farklıydı; panelde yirmi pet yirmi aynı fasulye gibi duruyordu.
	Artık sahada gördüğün şekil arayüzde de o şekil.

	Beş biçim, hepsi aynı ölçü kutusunda:
	  blob  — mürettebat (Crewmate)
	  orb   — küre + çapraz halka + vizör
	  bot   — köşeli kutu + anten + vizör
	  crab  — basık gövde + altı bacak + vizör
	  shard — elmas + içinde parlak çekirdek
]]
function UiKit.PetFigure(parent: Instance, size: number, form: string, color: Color3): Frame
	local z = baseZ(parent)

	if form == "blob" then
		return UiKit.Crewmate(parent, size, color)
	end

	local holder = Instance.new("Frame")
	holder.Name = "PetFigure"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.ZIndex = z
	holder.Parent = parent

	local function box(name: string, pos: UDim2, sz: UDim2, tint: Color3, zOff: number, radius: number?): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = pos
		f.Size = sz
		f.BackgroundColor3 = tint
		f.BorderSizePixel = 0
		f.ZIndex = z + zOff
		f.Parent = holder
		if radius then
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(radius, 0)
			c.Parent = f
		end
		return f
	end

	local dark = color:Lerp(Color3.new(0, 0, 0), 0.45)
	local metal = Color3.fromRGB(198, 206, 214)

	local function visor(y: number, w: number, h: number)
		box("Visor", UDim2.fromScale(0.5, y), UDim2.fromScale(w, h), UiKit.VISOR, 3, 0.4)
		box("Glint", UDim2.fromScale(0.5 + w * 0.22, y - h * 0.18), UDim2.fromScale(w * 0.2, h * 0.28), Color3.new(1, 1, 1), 4, 0.5)
	end

	if form == "orb" then
		box("Body", UDim2.fromScale(0.5, 0.52), UDim2.fromScale(0.78, 0.78), color, 1, 0.5)
		local ring = box("Ring", UDim2.fromScale(0.5, 0.56), UDim2.fromScale(1.02, 0.1), metal, 2, 0.5)
		ring.Rotation = -14
		visor(0.46, 0.48, 0.2)

	elseif form == "bot" then
		box("Antenna", UDim2.fromScale(0.5, 0.14), UDim2.fromScale(0.06, 0.22), metal, 1)
		box("Tip", UDim2.fromScale(0.5, 0.05), UDim2.fromScale(0.14, 0.14), UiKit.VISOR, 2, 0.5)
		box("Body", UDim2.fromScale(0.5, 0.56), UDim2.fromScale(0.78, 0.64), color, 1, 0.18)
		box("Tread", UDim2.fromScale(0.5, 0.9), UDim2.fromScale(0.84, 0.1), dark, 2, 0.4)
		visor(0.5, 0.56, 0.18)

	elseif form == "crab" then
		for i = 0, 2 do
			for _, side in { -1, 1 } do
				local leg = box("Leg", UDim2.fromScale(0.5 + side * 0.42, 0.62 + i * 0.1), UDim2.fromScale(0.26, 0.06), dark, 0)
				leg.Rotation = side * (18 + i * 10)
			end
		end
		box("Body", UDim2.fromScale(0.5, 0.6), UDim2.fromScale(0.86, 0.46), color, 1, 0.45)
		visor(0.56, 0.5, 0.16)

	else -- shard
		local gem = box("Body", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.6, 0.6), color, 1, 0.08)
		gem.Rotation = 45
		local core = box("Core", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.26, 0.26), color:Lerp(Color3.new(1, 1, 1), 0.6), 2, 0.08)
		core.Rotation = 45
	end

	return holder
end

--[[
	Görev panosu: görevlerin ikonu. Among Us'ta görev listesi bir
	panoda (clipboard) duruyor; üstteki kıskaç ve satır çizgileri onu
	düz bir kareden ayırıyor.
]]
function UiKit.Clipboard(parent: Instance, size: number, tint: Color3): Frame
	local z = baseZ(parent)

	local board = Instance.new("Frame")
	board.Name = "Clipboard"
	board.AnchorPoint = Vector2.new(0.5, 0.5)
	board.Position = UDim2.fromScale(0.5, 0.55)
	board.Size = UDim2.fromOffset(size * 0.74, size * 0.86)
	board.BackgroundColor3 = tint
	board.BorderSizePixel = 0
	board.ZIndex = z + 1
	board.Parent = parent
	UiKit.Corner(board, math.max(2, math.floor(size * 0.1)))

	local clip = Instance.new("Frame")
	clip.AnchorPoint = Vector2.new(0.5, 0.5)
	clip.Position = UDim2.fromScale(0.5, 0)
	clip.Size = UDim2.fromOffset(size * 0.38, size * 0.16)
	clip.BackgroundColor3 = tint:Lerp(Color3.new(0, 0, 0), 0.45)
	clip.BorderSizePixel = 0
	clip.ZIndex = z + 2
	clip.Parent = board
	UiKit.Corner(clip, math.max(1, math.floor(size * 0.05)))

	for index = 1, 3 do
		local line = Instance.new("Frame")
		line.Position = UDim2.new(0.2, 0, 0.18 + index * 0.2, 0)
		line.Size = UDim2.new(if index == 3 then 0.4 else 0.6, 0, 0, math.max(2, size * 0.07))
		line.BackgroundColor3 = tint:Lerp(Color3.new(0, 0, 0), 0.45)
		line.BorderSizePixel = 0
		line.ZIndex = z + 2
		line.Parent = board
	end

	return board
end

--[[
	Bildirim rozeti: düğmenin köşesinde kırmızı daire ve sayı. Sıfırken
	gizli. Hazır görev ödülü gibi "sana bekleyen bir şey var" durumları
	için; renk mürettebatın kırmızısı.
]]
function UiKit.Badge(parent: GuiObject): TextLabel
	local dot = Instance.new("TextLabel")
	dot.Name = "Badge"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.new(1, -4, 0, 4)
	dot.Size = UDim2.fromOffset(24, 24)
	dot.BackgroundColor3 = UiKit.CREW.RED
	dot.BorderSizePixel = 0
	dot.Font = Enum.Font.GothamBlack
	dot.TextSize = 13
	dot.TextColor3 = Color3.new(1, 1, 1)
	dot.Text = ""
	dot.Visible = false
	dot.ZIndex = parent.ZIndex + 5
	dot.Parent = parent
	UiKit.Corner(dot, 12)
	UiKit.Stroke(dot, Color3.new(1, 1, 1), 2, 0)
	return dot
end

--[[
	Hediye kutusu: ödüllerin ikonu. Gövde + daha geniş kapak + dikey kurdele
	+ tepede iki yapraklı fiyonk. Fiyonk olmadan düz bir sandıkla
	karışıyordu (mağazanın ikonu sandık).
]]
function UiKit.Gift(parent: Instance, size: number, tint: Color3, ribbon: Color3?): Frame
	local z = baseZ(parent)
	local band = ribbon or Color3.fromRGB(255, 230, 120)

	local holder = Instance.new("Frame")
	holder.Name = "Gift"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.ZIndex = z
	holder.Parent = parent

	local function box(pos: UDim2, sz: UDim2, color: Color3, zOff: number, radius: number?, rot: number?): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = pos
		f.Size = sz
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Rotation = rot or 0
		f.ZIndex = z + zOff
		f.Parent = holder
		if radius then
			UiKit.Corner(f, radius)
		end
		return f
	end

	box(UDim2.fromScale(0.5, 0.64), UDim2.fromScale(0.72, 0.5), tint, 1, math.max(2, math.floor(size * 0.06)))
	box(UDim2.fromScale(0.5, 0.38), UDim2.fromScale(0.86, 0.2), tint:Lerp(Color3.new(1, 1, 1), 0.15), 2, math.max(2, math.floor(size * 0.05)))
	box(UDim2.fromScale(0.5, 0.58), UDim2.fromScale(0.16, 0.62), band, 3)
	box(UDim2.fromScale(0.36, 0.2), UDim2.fromScale(0.26, 0.18), band, 3, math.max(2, math.floor(size * 0.08)), -28)
	box(UDim2.fromScale(0.64, 0.2), UDim2.fromScale(0.26, 0.18), band, 3, math.max(2, math.floor(size * 0.08)), 28)
	box(UDim2.fromScale(0.5, 0.26), UDim2.fromScale(0.14, 0.14), band:Lerp(Color3.new(0, 0, 0), 0.15), 4, math.max(2, math.floor(size * 0.07)))
	return holder
end

--[[
	Göz: arayüzü gizle/göster düğmesinin ikonu. Emoji yerine çizim, çünkü
	emoji her cihazda farklı çıkıyor (bazılarında kutu). Gizliyken üstünde
	çapraz çizgi.
]]
function UiKit.EyeIcon(parent: Instance, size: number, crossed: boolean): Frame
	local z = baseZ(parent)

	local holder = Instance.new("Frame")
	holder.Name = "Eye"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.ZIndex = z
	holder.Parent = parent

	local white = Instance.new("Frame")
	white.AnchorPoint = Vector2.new(0.5, 0.5)
	white.Position = UDim2.fromScale(0.5, 0.5)
	white.Size = UDim2.fromScale(0.92, 0.56)
	white.BackgroundColor3 = Color3.new(1, 1, 1)
	white.BorderSizePixel = 0
	white.ZIndex = z + 1
	white.Parent = holder
	local c1 = Instance.new("UICorner")
	c1.CornerRadius = UDim.new(0.5, 0)
	c1.Parent = white

	local iris = Instance.new("Frame")
	iris.AnchorPoint = Vector2.new(0.5, 0.5)
	iris.Position = UDim2.fromScale(0.5, 0.5)
	iris.Size = UDim2.fromOffset(size * 0.42, size * 0.42)
	iris.BackgroundColor3 = UiKit.VISOR:Lerp(Color3.new(0, 0, 0), 0.35)
	iris.BorderSizePixel = 0
	iris.ZIndex = z + 2
	iris.Parent = holder
	UiKit.Corner(iris, math.floor(size * 0.21))

	local pupil = Instance.new("Frame")
	pupil.AnchorPoint = Vector2.new(0.5, 0.5)
	pupil.Position = UDim2.fromScale(0.5, 0.5)
	pupil.Size = UDim2.fromOffset(size * 0.2, size * 0.2)
	pupil.BackgroundColor3 = Color3.fromRGB(16, 18, 24)
	pupil.BorderSizePixel = 0
	pupil.ZIndex = z + 3
	pupil.Parent = holder
	UiKit.Corner(pupil, math.floor(size * 0.1))

	if crossed then
		local slash = Instance.new("Frame")
		slash.AnchorPoint = Vector2.new(0.5, 0.5)
		slash.Position = UDim2.fromScale(0.5, 0.5)
		slash.Size = UDim2.new(1.05, 0, 0, math.max(2, size * 0.1))
		slash.Rotation = -40
		slash.BackgroundColor3 = UiKit.CREW.RED
		slash.BorderSizePixel = 0
		slash.ZIndex = z + 4
		slash.Parent = holder
		UiKit.Stroke(slash, Color3.new(0, 0, 0), 1, 0.5)
	end

	return holder
end

--[[
	Ekipman ikonu: Gear Shop'taki aletin 2B hâli (GearModel ile aynı renkler).
	  SlapGlove   — kırmızı el: avuç + dört parmak + başparmak
	  GravityCoil — mor yay, SpeedCoil — kırmızı-mavi yay
]]
function UiKit.GearIcon(parent: Instance, size: number, id: string): Frame
	local z = baseZ(parent)
	local holder = Instance.new("Frame")
	holder.Name = "GearIcon"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.ZIndex = z
	holder.Parent = parent

	local function blob(pos: UDim2, sz: UDim2, color: Color3, zOff: number, rot: number?): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = pos
		f.Size = sz
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Rotation = rot or 0
		f.ZIndex = z + zOff
		f.Parent = holder
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
		return f
	end

	if id == "SlapGlove" then
		local red = Color3.fromRGB(220, 50, 60)
		blob(UDim2.fromScale(0.5, 0.62), UDim2.fromScale(0.58, 0.46), red, 1)
		for i = 0, 3 do
			blob(UDim2.fromScale(0.3 + i * 0.13, 0.3), UDim2.fromScale(0.13, 0.36), red, 2)
		end
		blob(UDim2.fromScale(0.2, 0.62), UDim2.fromScale(0.14, 0.3), red, 2, 35)
		blob(UDim2.fromScale(0.5, 0.9), UDim2.fromScale(0.4, 0.14), Color3.fromRGB(240, 240, 245), 1)
	else
		local tint = if id == "SpeedCoil" then Color3.fromRGB(220, 50, 60) else Color3.fromRGB(150, 80, 240)
		local accent = if id == "SpeedCoil" then Color3.fromRGB(50, 120, 245) else Color3.fromRGB(230, 205, 255)
		local rings = if id == "SpeedCoil" then 6 else 5
		for i = 1, rings do
			local y = 0.8 - (i - 1) * (0.62 / (rings - 1))
			blob(UDim2.fromScale(0.5, y), UDim2.fromScale(0.7, 0.13), if i % 2 == 0 then accent else tint, 1)
		end
		blob(UDim2.fromScale(0.5, 0.1), UDim2.fromScale(0.2, 0.2), accent, 2)
	end
	return holder
end

--[[ Madeni para: nakit hapının ikonu. ]]
function UiKit.Coin(parent: Instance, size: number, tint: Color3): Frame
	local coin = Instance.new("Frame")
	coin.Name = "Coin"
	coin.AnchorPoint = Vector2.new(0.5, 0.5)
	coin.Position = UDim2.fromScale(0.5, 0.5)
	coin.Size = UDim2.fromOffset(size, size)
	coin.BackgroundColor3 = tint
	coin.BorderSizePixel = 0
	coin.ZIndex = baseZ(parent) + 1
	coin.Parent = parent
	UiKit.Corner(coin, math.floor(size / 2))
	UiKit.Stroke(coin, tint:Lerp(Color3.new(0, 0, 0), 0.45), 2, 0)

	local mark = Instance.new("TextLabel")
	mark.Size = UDim2.fromScale(1, 1)
	mark.BackgroundTransparency = 1
	mark.Font = Enum.Font.GothamBlack
	mark.TextSize = math.floor(size * 0.66)
	mark.TextColor3 = tint:Lerp(Color3.new(0, 0, 0), 0.55)
	mark.Text = "$"
	mark.ZIndex = coin.ZIndex + 1
	mark.Parent = coin

	return coin
end

--[[
	Koşan mürettebat: çalma hızının ikonu. Öne eğik fasulye + arkasında üç
	hız çizgisi. Eski çizim (bot) küçük boyutta "L" harfi gibi okunuyordu.
]]
function UiKit.Boot(parent: Instance, size: number, tint: Color3): Frame
	local h = canvas(parent, "Runner", size)
	for k, y in { 0.34, 0.52, 0.7 } do
		local line = shape(h, 0.2 - (k % 2) * 0.04, y, 0.3, 0.09, tint, 1, 0.5)
		line.BackgroundTransparency = 0.15 + k * 0.12
	end
	local host = shape(h, 0.6, 0.52, 0.72, 0.72, tint, 1)
	host.BackgroundTransparency = 1
	local body = UiKit.Crewmate(host, size * 0.64, tint)
	body.Rotation = 14
	return h
end
UiKit.Runner = UiKit.Boot

--[[
	Rebirth: dönen ok (yeniden başla). Halka + ok ucu + ortada küçük yıldız
	parıltısı. Eski alev çizimi bir hapa benziyordu.
]]
function UiKit.Flame(parent: Instance, size: number, tint: Color3): Frame
	local h = canvas(parent, "Rebirth", size)
	local thick = math.max(2, size * 0.13)
	ring(h, 0.5, 0.52, 0.72, 0.72, tint, thick, 1, 0.24, 35)
	-- Ok ucu: halkanın kesik ucunda eşkenar dörtgen
	local r = 0.36
	local a = math.rad(-27)
	shape(h, 0.5 + math.cos(a) * r, 0.52 + math.sin(a) * r, 0.3, 0.3, tint, 2, 0.08, 45)
	shape(h, 0.5, 0.52, 0.2, 0.2, tint:Lerp(WHITE, 0.4), 2, 0.1, 45)
	return h
end
UiKit.Rebirth = UiKit.Flame

--[[ Alışveriş çantası: mağazanın ikonu. Sap halkası gövdenin arkasında. ]]
function UiKit.Bag(parent: Instance, size: number, tint: Color3): Frame
	local h = canvas(parent, "Bag", size)
	ring(h, 0.5, 0.3, 0.42, 0.42, tint:Lerp(BLACK, 0.3), math.max(2, size * 0.09), 1)
	shape(h, 0.5, 0.64, 0.8, 0.62, tint, 2, 0.18)
	shape(h, 0.5, 0.4, 0.8, 0.14, tint:Lerp(BLACK, 0.22), 3, 0.3)
	-- Göğüste vizör: Among Us dokunuşu
	shape(h, 0.5, 0.66, 0.4, 0.2, UiKit.VISOR, 3, 0.5)
	shape(h, 0.58, 0.62, 0.1, 0.06, WHITE, 4, 0.5)
	return h
end

--[[ Kitap: indeksin ikonu. Kapakta mürettebat, sağda sayfa kenarı. ]]
function UiKit.Book(parent: Instance, size: number, tint: Color3): Frame
	local h = canvas(parent, "Book", size)
	shape(h, 0.56, 0.52, 0.66, 0.82, WHITE:Lerp(tint, 0.15), 1, 0.12)   -- sayfalar
	shape(h, 0.48, 0.5, 0.7, 0.84, tint, 2, 0.14)                       -- kapak
	shape(h, 0.2, 0.5, 0.12, 0.84, tint:Lerp(BLACK, 0.3), 3, 0.3)        -- sırt
	local host = shape(h, 0.52, 0.5, 0.5, 0.5, tint, 3)
	host.BackgroundTransparency = 1
	UiKit.Crewmate(host, size * 0.4, tint:Lerp(WHITE, 0.75))
	return h
end

--[[ Taç: unvanların ikonu. ]]
function UiKit.Crown(parent: Instance, size: number, tint: Color3): Frame
	local h = canvas(parent, "Crown", size)
	for _, p in { { 0.2, 0.5 }, { 0.5, 0.42 }, { 0.8, 0.5 } } do
		shape(h, p[1], p[2], 0.3, 0.3, tint, 1, 0.12, 45)
	end
	shape(h, 0.5, 0.72, 0.84, 0.3, tint, 2, 0.2)
	shape(h, 0.5, 0.83, 0.84, 0.08, tint:Lerp(BLACK, 0.25), 3, 0.5)
	for _, p in { { 0.2, 0.32 }, { 0.5, 0.22 }, { 0.8, 0.32 } } do
		shape(h, p[1], p[2], 0.13, 0.13, WHITE, 3, 0.5)
	end
	shape(h, 0.5, 0.68, 0.16, 0.16, UiKit.CREW.RED, 4, 0.5)
	return h
end

--[[ Pati izi: petlerin ikonu. ]]
function UiKit.Paw(parent: Instance, size: number, tint: Color3): Frame
	local h = canvas(parent, "Paw", size)
	shape(h, 0.5, 0.66, 0.52, 0.44, tint, 1, 0.5)
	for _, p in { { 0.2, 0.42, -25 }, { 0.38, 0.22, -10 }, { 0.62, 0.22, 10 }, { 0.8, 0.42, 25 } } do
		shape(h, p[1], p[2], 0.2, 0.25, tint, 1, 0.5, p[3])
	end
	shape(h, 0.42, 0.6, 0.12, 0.1, WHITE, 2, 0.5).BackgroundTransparency = 0.45
	return h
end

--[[ Asma kilit: kilit ile ilgili her şeyin ikonu. ]]
function UiKit.Lock(parent: Instance, size: number, tint: Color3): Frame
	local h = canvas(parent, "Lock", size)
	ring(h, 0.5, 0.36, 0.46, 0.5, tint:Lerp(WHITE, 0.25), math.max(2, size * 0.1), 1)
	shape(h, 0.5, 0.68, 0.74, 0.54, tint, 2, 0.18)
	local hole = tint:Lerp(BLACK, 0.55)
	shape(h, 0.5, 0.63, 0.16, 0.16, hole, 3, 0.5)
	shape(h, 0.5, 0.74, 0.08, 0.18, hole, 3, 0.3)
	return h
end

--[[ Şimşek: hız/anında etkilerin ikonu. İki paralelkenar + bağlantı. ]]
function UiKit.Bolt(parent: Instance, size: number, tint: Color3): Frame
	local h = canvas(parent, "Bolt", size)
	-- Kalın çizgiler: küçük boyutta ince çapraz bir çizgi gibi kalıyordu
	shape(h, 0.6, 0.28, 0.32, 0.52, tint, 1, 0.1, 22)
	shape(h, 0.5, 0.52, 0.62, 0.18, tint, 1, 0.25, -10)
	shape(h, 0.4, 0.76, 0.32, 0.52, tint, 1, 0.1, 22)
	shape(h, 0.56, 0.28, 0.09, 0.32, WHITE, 2, 0.5, 22).BackgroundTransparency = 0.35
	return h
end

--[[ Kürsü: kaide/üs yuvası ikonu, üstünde küçük mürettebat. ]]
function UiKit.Podium(parent: Instance, size: number, tint: Color3): Frame
	local h = canvas(parent, "Podium", size)
	shape(h, 0.5, 0.88, 0.86, 0.14, tint:Lerp(BLACK, 0.25), 1, 0.4)
	shape(h, 0.5, 0.7, 0.54, 0.3, tint, 1, 0.1)
	shape(h, 0.5, 0.54, 0.72, 0.1, tint:Lerp(WHITE, 0.3), 2, 0.4)
	local host = shape(h, 0.5, 0.28, 0.4, 0.4, tint, 2)
	host.BackgroundTransparency = 1
	UiKit.Crewmate(host, size * 0.38, WHITE)
	return h
end

--[[ Şans çarkı: çark ile ilgili ikon. Dört renkli dilim + göbek + dil. ]]
function UiKit.Wheel(parent: Instance, size: number, tint: Color3): Frame
	local h = canvas(parent, "Wheel", size)
	shape(h, 0.5, 0.54, 0.84, 0.84, tint, 1, 0.5)
	for k, rot in { 0, 45, 90, 135 } do
		shape(h, 0.5, 0.54, 0.78, 0.06, WHITE, 2, 0.5, rot).BackgroundTransparency = 0.2 + (k % 2) * 0.2
	end
	shape(h, 0.5, 0.54, 0.22, 0.22, WHITE, 3, 0.5)
	shape(h, 0.5, 0.08, 0.18, 0.18, UiKit.CREW.RED, 3, 0.1, 45)
	return h
end

--[[
	Tek giriş: ikon adından çizim. Düğmeler, mağaza satırları ve ödül
	kutucukları aynı adları kullanıyor, böylece aynı şey her yerde aynı
	resimle gösteriliyor.
]]
function UiKit.Icon(parent: Instance, kind: string, size: number, tint: Color3): Frame
	if kind == "crate" then
		return UiKit.Crate(parent, size, tint)
	elseif kind == "crewmate" then
		return UiKit.Crewmate(parent, size, tint)
	elseif kind == "coin" then
		return UiKit.Coin(parent, size, tint)
	elseif kind == "vial" or kind == "potion" then
		return UiKit.Vial(parent, size, tint, 0.8, true)
	elseif kind == "boot" or kind == "runner" then
		return UiKit.Boot(parent, size, tint)
	elseif kind == "egg" then
		return UiKit.Egg(parent, size, tint)
	elseif kind == "clipboard" then
		return UiKit.Clipboard(parent, size, tint)
	elseif kind == "bag" then
		return UiKit.Bag(parent, size, tint)
	elseif kind == "book" then
		return UiKit.Book(parent, size, tint)
	elseif kind == "crown" then
		return UiKit.Crown(parent, size, tint)
	elseif kind == "paw" then
		return UiKit.Paw(parent, size, tint)
	elseif kind == "lock" then
		return UiKit.Lock(parent, size, tint)
	elseif kind == "bolt" then
		return UiKit.Bolt(parent, size, tint)
	elseif kind == "podium" then
		return UiKit.Podium(parent, size, tint)
	elseif kind == "wheel" then
		return UiKit.Wheel(parent, size, tint)
	elseif kind == "gift" then
		return UiKit.Gift(parent, size, tint)
	end
	return UiKit.Flame(parent, size, tint)
end

--[[
	İlerleme çubuğu. Dolu kısım ayrı bir Frame; oranı çağıran ayarlıyor.
	Köşeleri tam yuvarlak çünkü kare uçlu çubuk panelin yumuşak diliyle
	çelişiyor.
]]
function UiKit.Bar(parent: Instance, height: number, fillColor: Color3): (Frame, Frame)
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, height)
	track.BackgroundColor3 = UiKit.SHELL_DEEP
	track.BorderSizePixel = 0
	track.Parent = parent
	UiKit.Corner(track, math.floor(height / 2))

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = fillColor
	fill.BorderSizePixel = 0
	fill.Parent = track
	UiKit.Corner(fill, math.floor(height / 2))

	return track, fill
end

return UiKit
