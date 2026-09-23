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
	UiKit.Stroke(root, accent, 1.4, 0.45)
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
function UiKit.CloseButton(parent: Frame): TextButton
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(28, 28)
	close.BackgroundColor3 = UiKit.SHELL_DEEP
	close.BorderSizePixel = 0
	close.Font = Enum.Font.GothamBold
	close.TextSize = 15
	close.TextColor3 = UiKit.MUTED
	close.Text = "X"
	close.AutoButtonColor = false
	close.Parent = parent
	UiKit.Corner(close, 8)

	close.MouseEnter:Connect(function()
		close.TextColor3 = UiKit.INK
	end)
	close.MouseLeave:Connect(function()
		close.TextColor3 = UiKit.MUTED
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
	İksir şişesi: boyun, gövde, içinde sıvı.

	Sıvı seviyesi adede göre doluyor — "kaç tane var" bilgisi sayı
	okunmadan veriliyor. Boşken şişe sönük.
]]
function UiKit.Vial(parent: Instance, size: number, tint: Color3, fill: number, active: boolean): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Vial"
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.ZIndex = baseZ(parent)
	holder.Parent = parent

	local tone = if active then tint else UiKit.DIM

	local neck = Instance.new("Frame")
	neck.AnchorPoint = Vector2.new(0.5, 0)
	neck.Position = UDim2.fromScale(0.5, 0.02)
	neck.Size = UDim2.fromOffset(size * 0.3, size * 0.24)
	neck.BackgroundColor3 = tone
	neck.BorderSizePixel = 0
	neck.ZIndex = holder.ZIndex + 2
	neck.Parent = holder
	UiKit.Corner(neck, math.max(2, math.floor(size * 0.08)))

	local body = Instance.new("Frame")
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.fromScale(0.5, 1)
	body.Size = UDim2.fromOffset(size * 0.74, size * 0.74)
	body.BackgroundColor3 = UiKit.SHELL_DEEP
	body.BorderSizePixel = 0
	body.ClipsDescendants = true
	body.ZIndex = holder.ZIndex + 1
	body.Parent = holder
	UiKit.Corner(body, math.floor(size * 0.33))
	UiKit.Stroke(body, tone, 1.4, 0.25)

	local liquid = Instance.new("Frame")
	liquid.AnchorPoint = Vector2.new(0.5, 1)
	liquid.Position = UDim2.fromScale(0.5, 1)
	liquid.Size = UDim2.new(1, 0, math.clamp(fill, 0, 1), 0)
	liquid.BackgroundColor3 = tone
	liquid.BackgroundTransparency = if active then 0.12 else 0.6
	liquid.BorderSizePixel = 0
	liquid.ZIndex = holder.ZIndex + 2
	liquid.Parent = body

	return holder
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
	local z = baseZ(parent)

	local egg = Instance.new("Frame")
	egg.Name = "Egg"
	egg.AnchorPoint = Vector2.new(0.5, 0.5)
	egg.Position = UDim2.fromScale(0.5, 0.5)
	egg.Size = UDim2.fromOffset(size * 0.78, size)
	egg.BackgroundColor3 = tint
	egg.BorderSizePixel = 0
	egg.ZIndex = z + 1
	egg.Parent = parent

	-- Üstü dar, altı geniş: tek yarıçap veremiyoruz, iki katman gerekiyor
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = egg

	local belly = Instance.new("Frame")
	belly.AnchorPoint = Vector2.new(0.5, 1)
	belly.Position = UDim2.fromScale(0.5, 1)
	belly.Size = UDim2.fromScale(1, 0.62)
	belly.BackgroundColor3 = tint
	belly.BorderSizePixel = 0
	belly.ZIndex = z + 1
	belly.Parent = egg
	UiKit.Corner(belly, math.floor(size * 0.34))

	local crack = Instance.new("Frame")
	crack.AnchorPoint = Vector2.new(0.5, 0.5)
	crack.Position = UDim2.fromScale(0.5, 0.46)
	crack.Size = UDim2.new(0.78, 0, 0, 2)
	crack.BackgroundColor3 = tint:Lerp(Color3.new(0, 0, 0), 0.5)
	crack.BorderSizePixel = 0
	crack.Rotation = -8
	crack.ZIndex = z + 2
	crack.Parent = egg

	return egg
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
	Bot: çalma hızının ikonu.

	Ayakkabı iki dikdörtgenden — bilek ve taban. Basit ama silueti
	tanınıyor ve "hareket" dışında bir şey okunmuyor.
]]
function UiKit.Boot(parent: Instance, size: number, tint: Color3): Frame
	local boot = Instance.new("Frame")
	boot.Name = "Boot"
	boot.AnchorPoint = Vector2.new(0.5, 0.5)
	boot.Position = UDim2.fromScale(0.5, 0.42)
	boot.Size = UDim2.fromOffset(size * 0.42, size * 0.62)
	boot.BackgroundColor3 = tint
	boot.BorderSizePixel = 0
	boot.ZIndex = baseZ(parent) + 1
	boot.Parent = parent
	UiKit.Corner(boot, math.max(2, math.floor(size * 0.12)))

	local sole = Instance.new("Frame")
	sole.AnchorPoint = Vector2.new(0, 1)
	sole.Position = UDim2.new(0, 0, 1, math.floor(size * 0.3))
	sole.Size = UDim2.fromOffset(size * 0.78, size * 0.26)
	sole.BackgroundColor3 = tint:Lerp(Color3.new(1, 1, 1), 0.25)
	sole.BorderSizePixel = 0
	sole.ZIndex = boot.ZIndex + 1
	sole.Parent = boot
	UiKit.Corner(sole, math.max(2, math.floor(size * 0.1)))

	return boot
end

--[[ Alev: rebirth ikonu. İç içe iki damla, dıştan içe açılan renk. ]]
function UiKit.Flame(parent: Instance, size: number, tint: Color3): Frame
	local outer = Instance.new("Frame")
	outer.Name = "Flame"
	outer.AnchorPoint = Vector2.new(0.5, 0.5)
	outer.Position = UDim2.fromScale(0.5, 0.5)
	outer.Size = UDim2.fromOffset(size * 0.62, size * 0.9)
	outer.BackgroundColor3 = tint
	outer.BorderSizePixel = 0
	outer.Rotation = 45
	outer.ZIndex = baseZ(parent) + 1
	outer.Parent = parent

	local outerCorner = Instance.new("UICorner")
	-- Üç köşe yuvarlak, biri sivri: alev damlasının silueti
	outerCorner.CornerRadius = UDim.new(0.5, 0)
	outerCorner.Parent = outer

	local inner = Instance.new("Frame")
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.58)
	inner.Size = UDim2.fromScale(0.52, 0.52)
	inner.BackgroundColor3 = tint:Lerp(Color3.new(1, 1, 1), 0.55)
	inner.BorderSizePixel = 0
	inner.ZIndex = outer.ZIndex + 1
	inner.Parent = outer
	UiKit.Corner(inner, math.floor(size * 0.25))

	return outer
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
