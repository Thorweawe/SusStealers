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

-- ─── Temel parçalar ─────────────────────────────────────────────────────────

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
	local body = Instance.new("Frame")
	body.Name = "Crewmate"
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromOffset(size * 0.78, size)
	body.BackgroundColor3 = color
	body.BorderSizePixel = 0
	body.Parent = parent
	UiKit.Corner(body, math.floor(size * 0.36))

	local pack = Instance.new("Frame")
	pack.Name = "Pack"
	pack.AnchorPoint = Vector2.new(0.5, 0.5)
	pack.Position = UDim2.fromScale(1.0, 0.54)
	pack.Size = UDim2.fromOffset(size * 0.24, size * 0.50)
	pack.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.22)
	pack.BorderSizePixel = 0
	pack.ZIndex = (body.ZIndex or 1) - 1
	pack.Parent = body
	UiKit.Corner(pack, math.floor(size * 0.11))

	local visor = Instance.new("Frame")
	visor.Name = "Visor"
	visor.AnchorPoint = Vector2.new(0.5, 0.5)
	visor.Position = UDim2.fromScale(0.42, 0.33)
	visor.Size = UDim2.fromOffset(size * 0.50, size * 0.26)
	visor.BackgroundColor3 = UiKit.VISOR
	visor.BorderSizePixel = 0
	visor.ZIndex = (body.ZIndex or 1) + 1
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
