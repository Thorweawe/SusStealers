--!strict
--[[
	Başlangıç ekranı: oyuna her girişte açılıyor, PLAY'e basınca oyun
	başlıyor.

	Among Us'ın ana menüsünden esinlenildi: kapkara uzay, kayan yıldızlar,
	boşlukta dönerek süzülen mürettebat, ortada büyük logo ve altında beyaz
	çerçeveli düğmeler. Hazır varlık kullanılmıyor; her şey Frame'lerden.

	Ekranda:
	  PLAY          — büyük yeşil düğme (Enter / gamepad A da çalışıyor)
	  SETTINGS      — müzik, efekt sesi, ekran sarsıntısı (hesaba kaydedilir)
	  HOW TO PLAY   — oyunun beş temel fikri
	  sol altta oyuncu kartı (avatar, ad, para, rebirth)
	  sağ altta sunucudaki mürettebat sayısı

	Menü açıkken karakter yürümüyor, sohbet ve oyuncu listesi gizli; arka
	plan opak olduğu için HUD ve harita görünmüyor (harita bu sırada
	yükleniyor). PLAY'e basınca yıldızlar "ışık hızına" geçiyor, ekran
	açılıyor ve her şey geri geliyor.

	Ayarlar sunucuda profilde (SettingsService). Kaydırırken ses anında
	değişsin diye nitelik yerelde de yazılıyor; sunucuya yalnızca oyuncu
	bıraktıktan sonra son değer gidiyor.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local UiKit = require(script.Parent.UiKit)

local TitleScreen = {}

export type Options = {
	onPlay: (() -> ())?,
}

local TITLE_TOP = "STEAL AN"
local TITLE_MAIN = "AMONG US"
local TAGLINE = "Steal crewmates. Build your crew. Trust no one."

local SPACE = Color3.fromRGB(6, 8, 16)
local WHITE = Color3.new(1, 1, 1)
local PLAY_GREEN = Color3.fromRGB(64, 200, 96)
local ACCENT = UiKit.CREW.CYAN

-- Tasarım alanı: içerik bu boyda çiziliyor, ekrana UIScale ile uyuyor
local REF = Vector2.new(1280, 720)

local CREW_COLORS = {
	UiKit.CREW.RED, UiKit.CREW.BLUE, UiKit.CREW.GREEN, UiKit.CREW.PINK,
	UiKit.CREW.ORANGE, UiKit.CREW.YELLOW, UiKit.CREW.PURPLE, UiKit.CREW.CYAN,
	UiKit.CREW.LIME, UiKit.CREW.WHITE,
}

local function tween(object: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(object, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function frame(parent: Instance, name: string, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function label(parent: Instance, text: string, font: Enum.Font, size: number, color: Color3, z: number): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = font
	t.TextSize = size
	t.TextColor3 = color
	t.Text = text
	t.ZIndex = z
	t.Parent = parent
	return t
end

--[[
	Mürettebat figürü. UiKit.Crewmate'ten farkı: sırt çantası gövdenin
	ARKASINDA (kardeş, alt katman) ve bacakları var — menüde büyük
	çizildiği için bacaksız kapsül yarım duruyordu.
]]
local function crewmate(parent: Instance, height: number, color: Color3, z: number): Frame
	local holder = frame(parent, "Crewmate", z)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Size = UDim2.fromOffset(height * 0.95, height)
	holder.BackgroundTransparency = 1

	local dark = color:Lerp(Color3.new(0, 0, 0), 0.3)
	local outline = Color3.fromRGB(12, 12, 18)
	local stroke = math.max(2, height * 0.035)

	local function part(name: string, pos: UDim2, size: UDim2, col: Color3, radius: number, zz: number): Frame
		local p = frame(holder, name, zz)
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Position = pos
		p.Size = size
		p.BackgroundColor3 = col
		corner(p, UDim.new(radius, 0))
		local s = Instance.new("UIStroke")
		s.Color = outline
		s.Thickness = stroke
		s.Parent = p
		return p
	end

	part("Pack", UDim2.fromScale(0.8, 0.5), UDim2.fromScale(0.26, 0.42), dark, 0.35, z)
	part("LegL", UDim2.fromScale(0.36, 0.86), UDim2.fromScale(0.25, 0.26), dark, 0.4, z)
	part("LegR", UDim2.fromScale(0.62, 0.86), UDim2.fromScale(0.25, 0.26), color, 0.4, z)
	local body = part("Body", UDim2.fromScale(0.48, 0.44), UDim2.fromScale(0.66, 0.78), color, 0.5, z + 1)
	local visor = part("Visor", UDim2.fromScale(0.36, 0.3), UDim2.fromScale(0.66, 0.28), UiKit.VISOR, 0.5, z + 2)
	visor.Parent = body
	visor.ZIndex = z + 2
	-- Vizör parlaması
	local shine = frame(visor, "Shine", z + 3)
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.fromScale(0.62, 0.34)
	shine.Size = UDim2.fromScale(0.42, 0.24)
	shine.BackgroundColor3 = WHITE
	shine.BackgroundTransparency = 0.25
	corner(shine, UDim.new(0.5, 0))
	return holder
end

-- ─── Düğmeler ───────────────────────────────────────────────────────────────

--[[
	Üstüne gelince büyüme. UIScale sol üst köşeden büyüttüğü için düğme
	sağa-aşağı kayıyordu; boyut çapa noktasından (ortadan) büyütülüyor.
]]
local function hoverScale(button: GuiButton, target: GuiObject)
	local base = target.Size
	local function to(k: number, seconds: number)
		tween(target, seconds, { Size = UDim2.new(base.X.Scale * k, base.X.Offset * k, base.Y.Scale * k, base.Y.Offset * k) })
	end
	button.MouseEnter:Connect(function()
		to(1.05, 0.12)
	end)
	button.MouseLeave:Connect(function()
		to(1, 0.12)
	end)
	button.SelectionGained:Connect(function()
		to(1.05, 0.12)
	end)
	button.SelectionLost:Connect(function()
		to(1, 0.12)
	end)
	button.MouseButton1Down:Connect(function()
		to(0.96, 0.06)
	end)
	button.MouseButton1Up:Connect(function()
		to(1.05, 0.1)
	end)
end

--[[ Among Us menüsündeki beyaz çerçeveli düğme: koyu dolgu, kalın beyaz çerçeve. ]]
local function outlinedButton(parent: Instance, text: string, size: Vector2, z: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = text
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Size = UDim2.fromOffset(size.X, size.Y)
	b.BackgroundColor3 = Color3.fromRGB(14, 16, 26)
	b.BackgroundTransparency = 0.15
	b.AutoButtonColor = false
	b.Font = Enum.Font.FredokaOne
	b.TextSize = 24
	b.TextColor3 = WHITE
	b.Text = text
	b.ZIndex = z
	b.Parent = parent
	corner(b, UDim.new(0, 10))
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = WHITE
	s.Thickness = 3
	s.Parent = b
	b.MouseEnter:Connect(function()
		tween(b, 0.12, { BackgroundColor3 = Color3.fromRGB(40, 46, 70) })
	end)
	b.MouseLeave:Connect(function()
		tween(b, 0.12, { BackgroundColor3 = Color3.fromRGB(14, 16, 26) })
	end)
	hoverScale(b, b)
	return b
end

-- ─── Pencereler (ayarlar, nasıl oynanır) ────────────────────────────────────

local function modal(parent: Instance, title: string, size: Vector2, z: number): (Frame, Frame, TextButton)
	-- Arkayı karartan perde: tıklamayı yutar
	local veil = Instance.new("TextButton")
	veil.Name = title .. "Veil"
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = Color3.new(0, 0, 0)
	veil.BackgroundTransparency = 0.45
	veil.AutoButtonColor = false
	veil.Text = ""
	veil.Selectable = false
	veil.ZIndex = z
	veil.Visible = false
	veil.Parent = parent

	local panel = frame(veil, "Panel", z + 1)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.52)
	panel.Size = UDim2.fromOffset(size.X, size.Y)
	panel.BackgroundColor3 = UiKit.SHELL
	panel.Active = true
	corner(panel, UDim.new(0, 16))
	local stroke = Instance.new("UIStroke")
	stroke.Color = WHITE
	stroke.Thickness = 3
	stroke.Parent = panel
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(UiKit.SHELL:Lerp(ACCENT, 0.08), UiKit.SHELL_DEEP)
	grad.Parent = panel

	local heading = label(panel, title, Enum.Font.FredokaOne, 30, WHITE, z + 2)
	heading.Position = UDim2.fromOffset(0, 14)
	heading.Size = UDim2.new(1, 0, 0, 36)
	local hs = Instance.new("UIStroke")
	hs.Thickness = 2
	hs.Color = Color3.fromRGB(10, 10, 16)
	hs.Parent = heading

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(38, 38)
	close.BackgroundColor3 = UiKit.CREW.RED
	close.AutoButtonColor = false
	close.Font = Enum.Font.FredokaOne
	close.TextSize = 22
	close.TextColor3 = WHITE
	close.Text = "X"
	close.ZIndex = z + 3
	close.Parent = panel
	corner(close, UDim.new(0.5, 0))
	local cs = Instance.new("UIStroke")
	cs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cs.Color = WHITE
	cs.Thickness = 2
	cs.Parent = close
	hoverScale(close, close)

	return veil, panel, close
end

local function openModal(veil: GuiObject, panel: GuiObject)
	veil.Visible = true
	veil.BackgroundTransparency = 1
	tween(veil, 0.2, { BackgroundTransparency = 0.45 })
	-- Aşağıdan yerine oturuyor
	panel.Position = UDim2.new(0.5, 0, 0.5, 40)
	tween(panel, 0.3, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Back)
end

-- ─── Kurulum ────────────────────────────────────────────────────────────────

export type Handle = {
	IsOpen: () -> boolean,
	-- PLAY'e basmakla aynı (gamepad/klavye kısayolları ve testler)
	Play: () -> (),
}

-- Açık olan ekran (yoksa nil)
TitleScreen.Current = nil :: Handle?

function TitleScreen.Show(options: Options?): Handle
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "TitleScreen"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 200
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local open = true
	local connections: { RBXScriptConnection } = {}

	-- ── Oyuncu kontrolleri, sohbet, oyuncu listesi: menü boyunca kapalı ──
	local hiddenCore: { Enum.CoreGuiType } = {}
	for _, kind in { Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList } do
		local ok, enabled = pcall(function()
			return StarterGui:GetCoreGuiEnabled(kind)
		end)
		if ok and enabled then
			pcall(function()
				StarterGui:SetCoreGuiEnabled(kind, false)
			end)
			table.insert(hiddenCore, kind)
		end
	end

	local controls: any = nil
	task.spawn(function()
		local ok, module = pcall(function()
			local scripts = player:WaitForChild("PlayerScripts", 10)
			local pm = scripts and scripts:WaitForChild("PlayerModule", 10)
			return pm and (require(pm :: ModuleScript) :: any):GetControls()
		end)
		if ok and module then
			controls = module
			if open then
				module:Disable()
			end
		end
	end)

	-- ── Arka plan: uzay ───────────────────────────────────────────────────
	local bg = frame(gui, "Space", 1)
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = SPACE
	bg.Active = true
	local bgGrad = Instance.new("UIGradient")
	bgGrad.Rotation = 90
	bgGrad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(4, 5, 12)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(14, 14, 34)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(26, 12, 38)),
	})
	bgGrad.Parent = bg

	-- Gezegen ve uydusu: derinlik veriyor, yıldızların altında değil üstünde
	local planet = frame(bg, "Planet", 2)
	planet.AnchorPoint = Vector2.new(0.5, 0.5)
	planet.Position = UDim2.fromScale(0.92, 1.02)
	planet.Size = UDim2.fromScale(0.42, 0.42)
	planet.SizeConstraint = Enum.SizeConstraint.RelativeXX
	planet.BackgroundColor3 = WHITE
	corner(planet, UDim.new(0.5, 0))
	local pg = Instance.new("UIGradient")
	pg.Rotation = 35
	pg.Color = ColorSequence.new(Color3.fromRGB(150, 90, 210), Color3.fromRGB(28, 16, 54))
	pg.Parent = planet
	local ring = frame(planet, "Ring", 3)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1.6, 0.22)
	ring.Rotation = -14
	ring.BackgroundTransparency = 1
	corner(ring, UDim.new(0.5, 0))
	local rs = Instance.new("UIStroke")
	rs.Color = Color3.fromRGB(200, 170, 255)
	rs.Transparency = 0.55
	rs.Thickness = 5
	rs.Parent = ring

	local moon = frame(bg, "Moon", 2)
	moon.AnchorPoint = Vector2.new(0.5, 0.5)
	moon.Position = UDim2.fromScale(0.1, 0.16)
	moon.Size = UDim2.fromScale(0.06, 0.06)
	moon.SizeConstraint = Enum.SizeConstraint.RelativeXX
	moon.BackgroundColor3 = WHITE
	corner(moon, UDim.new(0.5, 0))
	local mg = Instance.new("UIGradient")
	mg.Rotation = 45
	mg.Color = ColorSequence.new(Color3.fromRGB(210, 220, 235), Color3.fromRGB(70, 80, 100))
	mg.Parent = moon

	-- Yıldızlar: üç katman, uzaktaki yavaş ve sönük (paralaks)
	type Star = { f: Frame, x: number, y: number, speed: number, base: number, phase: number }
	local stars: { Star } = {}
	local rng = Random.new()
	for layer = 1, 3 do
		local count = ({ 90, 50, 22 })[layer]
		for _ = 1, count do
			local size = ({ 1.5, 2.5, 3.5 })[layer]
			local f = frame(bg, "Star", 2)
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Size = UDim2.fromOffset(size, size)
			f.BackgroundColor3 = WHITE
			corner(f, UDim.new(0.5, 0))
			local s: Star = {
				f = f,
				x = rng:NextNumber(),
				y = rng:NextNumber(),
				speed = ({ 0.004, 0.009, 0.018 })[layer],
				base = ({ 0.55, 0.3, 0.05 })[layer],
				phase = rng:NextNumber(0, math.pi * 2),
			}
			table.insert(stars, s)
		end
	end

	-- Kayan yıldız: ara sıra çapraz bir çizgi
	local comet = frame(bg, "Comet", 2)
	comet.AnchorPoint = Vector2.new(1, 0.5)
	comet.Size = UDim2.fromOffset(160, 2)
	comet.Rotation = 18
	comet.BackgroundColor3 = WHITE
	comet.BackgroundTransparency = 1
	local cg = Instance.new("UIGradient")
	cg.Transparency = NumberSequence.new(1, 0)
	cg.Parent = comet

	-- Süzülen mürettebat: boşlukta dönerek soldan sağa geçiyor
	type Drifter = { f: Frame, x: number, y: number, speed: number, spin: number, bob: number }
	local drifters: { Drifter } = {}
	local drifterLayer = frame(bg, "Drifters", 3)
	drifterLayer.Size = UDim2.fromScale(1, 1)
	drifterLayer.BackgroundTransparency = 1
	local function spawnDrifter(x: number)
		local h = rng:NextNumber(34, 78)
		local color = CREW_COLORS[rng:NextInteger(1, #CREW_COLORS)]
		local f = crewmate(drifterLayer, h, color, 3)
		table.insert(drifters, {
			f = f,
			x = x,
			y = rng:NextNumber(0.12, 0.92),
			speed = rng:NextNumber(0.012, 0.03) * (h / 60),
			spin = rng:NextNumber(-40, 40),
			bob = rng:NextNumber(0, math.pi * 2),
		})
	end
	for i = 1, 5 do
		spawnDrifter((i - 1) / 5 + rng:NextNumber(0, 0.1))
	end

	-- ── İçerik katmanı: tasarım alanı, ekrana ölçekli ──────────────────────
	--[[
		UIScale nesneyi SOL ÜST köşesinden küçültüyor; ortalı çapa ile
		içerik sola kayıyordu (oyuncu kartı ekrandan taşıyordu). Konum her
		ölçekte elle ortalanıyor.
	]]
	local content = frame(gui, "Content", 10)
	content.Size = UDim2.fromOffset(REF.X, REF.Y)
	content.BackgroundTransparency = 1
	local contentScale = Instance.new("UIScale")
	contentScale.Parent = content
	local function fitScale(): number
		local v = gui.AbsoluteSize
		if v.X <= 0 or v.Y <= 0 then
			return 1
		end
		return math.clamp(math.min(v.X / REF.X, v.Y / REF.Y), 0.45, 1.25)
	end
	local function rescale()
		local s = fitScale()
		contentScale.Scale = s
		content.Position = UDim2.new(0.5, -REF.X * s / 2, 0.5, -REF.Y * s / 2)
	end
	table.insert(connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale))
	rescale()

	-- Logo
	local logo = frame(content, "Logo", 11)
	logo.AnchorPoint = Vector2.new(0.5, 0)
	logo.Position = UDim2.fromOffset(REF.X / 2, 70)
	logo.Size = UDim2.fromOffset(760, 220)
	logo.BackgroundTransparency = 1

	local top = label(logo, TITLE_TOP, Enum.Font.FredokaOne, 34, WHITE, 13)
	top.AnchorPoint = Vector2.new(0.5, 0)
	top.Position = UDim2.fromScale(0.5, 0)
	top.Size = UDim2.fromOffset(260, 46)
	top.BackgroundTransparency = 0
	top.BackgroundColor3 = UiKit.CREW.RED
	top.Rotation = -3
	corner(top, UDim.new(0, 10))
	local ts = Instance.new("UIStroke")
	ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ts.Color = WHITE
	ts.Thickness = 3
	ts.Parent = top

	local main = label(logo, TITLE_MAIN, Enum.Font.FredokaOne, 124, WHITE, 12)
	main.AnchorPoint = Vector2.new(0.5, 0)
	main.Position = UDim2.fromOffset(380, 44)
	main.Size = UDim2.fromOffset(760, 130)
	local ms = Instance.new("UIStroke")
	ms.Color = Color3.fromRGB(8, 8, 14)
	ms.Thickness = 6
	ms.Parent = main
	local mgr = Instance.new("UIGradient")
	mgr.Rotation = 90
	mgr.Color = ColorSequence.new(WHITE, Color3.fromRGB(190, 214, 240))
	mgr.Parent = main

	-- Logonun yanında para çantalı kırmızı mürettebat: oyunun ne olduğu tek bakışta
	local mascot = crewmate(logo, 110, UiKit.CREW.RED, 12)
	mascot.Position = UDim2.fromOffset(-10, 118)
	mascot.Rotation = -12
	local bagHolder = frame(mascot, "BagHolder", 16)
	bagHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	bagHolder.Position = UDim2.fromScale(0.05, 0.62)
	bagHolder.Size = UDim2.fromOffset(52, 52)
	bagHolder.BackgroundTransparency = 1
	UiKit.Coin(bagHolder, 46, UiKit.CREW.LIME)

	local tagline = label(logo, TAGLINE, Enum.Font.GothamBold, 20, Color3.fromRGB(190, 200, 222), 12)
	tagline.AnchorPoint = Vector2.new(0.5, 0)
	tagline.Position = UDim2.fromOffset(380, 182)
	tagline.Size = UDim2.fromOffset(760, 26)

	-- Düğmeler
	local buttons = frame(content, "Buttons", 11)
	buttons.AnchorPoint = Vector2.new(0.5, 0)
	buttons.Position = UDim2.fromOffset(REF.X / 2, 330)
	buttons.Size = UDim2.fromOffset(420, 220)
	buttons.BackgroundTransparency = 1

	-- PLAY: tek dolgulu düğme; gözün ilk gittiği yer
	local play = Instance.new("TextButton")
	play.Name = "Play"
	play.AnchorPoint = Vector2.new(0.5, 0.5)
	play.Position = UDim2.new(0.5, 0, 0, 48)
	play.Size = UDim2.fromOffset(400, 96)
	play.BackgroundColor3 = PLAY_GREEN
	play.AutoButtonColor = false
	play.Text = ""
	play.ZIndex = 12
	play.Parent = buttons
	corner(play, UDim.new(0, 18))
	local pst = Instance.new("UIStroke")
	pst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	pst.Color = WHITE
	pst.Thickness = 4
	pst.Parent = play
	local pgr = Instance.new("UIGradient")
	pgr.Rotation = 90
	pgr.Color = ColorSequence.new(PLAY_GREEN:Lerp(WHITE, 0.25), PLAY_GREEN:Lerp(Color3.new(0, 0, 0), 0.2))
	pgr.Parent = play
	-- Oynat üçgeni: kare döndürülüp yarısı kırpılarak
	local tri = frame(play, "Triangle", 13)
	tri.AnchorPoint = Vector2.new(0.5, 0.5)
	tri.Position = UDim2.new(0, 84, 0.5, 0)
	tri.Size = UDim2.fromOffset(34, 40)
	tri.BackgroundTransparency = 1
	tri.ClipsDescendants = true
	local sq = frame(tri, "Square", 14)
	sq.AnchorPoint = Vector2.new(0.5, 0.5)
	sq.Position = UDim2.new(0, 0, 0.5, 0)
	sq.Size = UDim2.fromOffset(40, 40)
	sq.Rotation = 45
	sq.BackgroundColor3 = WHITE
	corner(sq, UDim.new(0, 4))
	local playText = label(play, "PLAY", Enum.Font.FredokaOne, 58, WHITE, 13)
	playText.Position = UDim2.fromOffset(40, 0)
	playText.Size = UDim2.new(1, -40, 1, 0)
	local pts = Instance.new("UIStroke")
	pts.Color = Color3.fromRGB(16, 70, 30)
	pts.Thickness = 3
	pts.Parent = playText
	hoverScale(play, play)

	-- Parlayan hale: PLAY nefes alıyor
	local glow = frame(buttons, "Glow", 11)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.new(0.5, 0, 0, 48)
	glow.Size = UDim2.fromOffset(430, 124)
	glow.BackgroundColor3 = PLAY_GREEN
	glow.BackgroundTransparency = 0.75
	corner(glow, UDim.new(0, 26))

	local settingsButton = outlinedButton(buttons, "SETTINGS", Vector2.new(196, 60), 12)
	settingsButton.Position = UDim2.new(0.5, -102, 0, 142)
	local helpButton = outlinedButton(buttons, "HOW TO PLAY", Vector2.new(196, 60), 12)
	helpButton.Position = UDim2.new(0.5, 102, 0, 142)

	local hint = label(content, "Press ENTER to play", Enum.Font.GothamMedium, 14, Color3.fromRGB(130, 140, 164), 11)
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.fromOffset(REF.X / 2, 560)
	hint.Size = UDim2.fromOffset(300, 20)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		hint.Visible = false
	end

	-- ── Oyuncu kartı (sol alt) ────────────────────────────────────────────
	local card = frame(content, "PlayerCard", 11)
	card.AnchorPoint = Vector2.new(0, 1)
	card.Position = UDim2.fromOffset(28, REF.Y - 28)
	card.Size = UDim2.fromOffset(330, 84)
	card.BackgroundColor3 = Color3.fromRGB(14, 16, 26)
	card.BackgroundTransparency = 0.2
	corner(card, UDim.new(0, 14))
	local cst = Instance.new("UIStroke")
	cst.Color = WHITE
	cst.Transparency = 0.6
	cst.Thickness = 2
	cst.Parent = card

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.AnchorPoint = Vector2.new(0, 0.5)
	avatar.Position = UDim2.new(0, 12, 0.5, 0)
	avatar.Size = UDim2.fromOffset(62, 62)
	avatar.BackgroundColor3 = Color3.fromRGB(40, 46, 70)
	avatar.ZIndex = 12
	avatar.Parent = card
	corner(avatar, UDim.new(0.5, 0))
	task.spawn(function()
		local ok, image = pcall(function()
			return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and avatar.Parent then
			avatar.Image = image
		end
	end)

	local nameLabel = label(card, player.DisplayName, Enum.Font.FredokaOne, 22, WHITE, 12)
	nameLabel.Position = UDim2.fromOffset(88, 12)
	nameLabel.Size = UDim2.new(1, -100, 0, 28)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

	local statsLabel = label(card, "", Enum.Font.GothamBold, 15, UiKit.CREW.LIME, 12)
	statsLabel.Position = UDim2.fromOffset(88, 44)
	statsLabel.Size = UDim2.new(1, -100, 0, 22)
	statsLabel.TextXAlignment = Enum.TextXAlignment.Left
	local function refreshStats()
		local cash = player:GetAttribute("Cash")
		local rebirths = player:GetAttribute("Rebirths")
		local parts = {}
		if typeof(cash) == "number" then
			table.insert(parts, "$" .. Config.FormatCash(cash))
		end
		if typeof(rebirths) == "number" and rebirths > 0 then
			table.insert(parts, "Rebirth " .. rebirths)
		end
		statsLabel.Text = if #parts > 0 then table.concat(parts, "   ·   ") else "Welcome aboard, crewmate!"
	end
	table.insert(connections, player:GetAttributeChangedSignal("Cash"):Connect(refreshStats))
	table.insert(connections, player:GetAttributeChangedSignal("Rebirths"):Connect(refreshStats))
	refreshStats()

	-- ── Sunucu bilgisi (sağ alt) ──────────────────────────────────────────
	local server = label(content, "", Enum.Font.GothamBold, 16, Color3.fromRGB(190, 200, 222), 11)
	server.AnchorPoint = Vector2.new(1, 1)
	server.Position = UDim2.fromOffset(REF.X - 32, REF.Y - 36)
	server.Size = UDim2.fromOffset(300, 22)
	server.TextXAlignment = Enum.TextXAlignment.Right
	local dot = frame(content, "OnlineDot", 11)
	dot.AnchorPoint = Vector2.new(1, 0.5)
	dot.Size = UDim2.fromOffset(12, 12)
	dot.BackgroundColor3 = UiKit.CREW.LIME
	corner(dot, UDim.new(0.5, 0))
	local function refreshServer()
		local count = #Players:GetPlayers()
		server.Text = string.format("%d / %d crewmates on this ship", count, Players.MaxPlayers)
		dot.Position = UDim2.fromOffset(REF.X - 32 - server.TextBounds.X - 10, REF.Y - 47)
	end
	table.insert(connections, Players.PlayerAdded:Connect(refreshServer))
	table.insert(connections, Players.PlayerRemoving:Connect(function()
		task.defer(refreshServer)
	end))
	table.insert(connections, server:GetPropertyChangedSignal("TextBounds"):Connect(refreshServer))
	refreshServer()

	-- ── Ayarlar ───────────────────────────────────────────────────────────
	local settingsVeil, settingsPanel, settingsClose = modal(gui, "SETTINGS", Vector2.new(520, 400), 40)
	local rows = frame(settingsPanel, "Rows", 42)
	rows.Position = UDim2.fromOffset(34, 76)
	rows.Size = UDim2.new(1, -68, 1, -120)
	rows.BackgroundTransparency = 1
	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.Padding = UDim.new(0, 14)
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Parent = rows

	local current = {
		music = 1,
		sfx = 1,
		shake = true,
	}
	local function readSetting(key: string, attr: string)
		local v = player:GetAttribute(attr)
		if key == "shake" then
			if typeof(v) == "boolean" then
				current.shake = v
			end
		elseif typeof(v) == "number" then
			(current :: any)[key] = math.clamp(v, 0, 1)
		end
	end
	readSetting("music", "SettingMusic")
	readSetting("sfx", "SettingSfx")
	readSetting("shake", "SettingShake")

	-- Sunucuya: oyuncu durduktan kısa süre sonra, tek istek
	local saveToken = 0
	local saveRemote = Net.Get("SettingsSave")
	local function queueSave()
		saveToken += 1
		local token = saveToken
		task.delay(0.5, function()
			if token == saveToken then
				saveRemote:FireServer({ music = current.music, sfx = current.sfx, shake = current.shake })
			end
		end)
	end

	local function row(order: number, title: string): Frame
		local r = frame(rows, title, 43)
		r.LayoutOrder = order
		r.Size = UDim2.new(1, 0, 0, 72)
		r.BackgroundColor3 = Color3.fromRGB(34, 40, 58)
		r.BackgroundTransparency = 0.2
		corner(r, UDim.new(0, 12))
		local t = label(r, title, Enum.Font.FredokaOne, 22, WHITE, 44)
		t.Position = UDim2.fromOffset(18, 0)
		t.Size = UDim2.new(0, 170, 1, 0)
		t.TextXAlignment = Enum.TextXAlignment.Left
		return r
	end

	--[[
		Kaydırıcı: fareyle/parmakla sürükleniyor, gamepad'de seçiliyken
		sağ/sol ile %10 adım. Değer 0..1.
	]]
	local function slider(order: number, title: string, key: string, attr: string)
		local r = row(order, title)
		local track = Instance.new("TextButton")
		track.Name = "Track"
		track.AnchorPoint = Vector2.new(0, 0.5)
		track.Position = UDim2.new(0, 190, 0.5, 0)
		track.Size = UDim2.new(1, -290, 0, 14)
		track.BackgroundColor3 = Color3.fromRGB(16, 18, 28)
		track.AutoButtonColor = false
		track.Text = ""
		track.ZIndex = 44
		track.Parent = r
		corner(track, UDim.new(0.5, 0))
		local fill = frame(track, "Fill", 45)
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = ACCENT
		corner(fill, UDim.new(0.5, 0))
		local knob = frame(track, "Knob", 46)
		knob.AnchorPoint = Vector2.new(0.5, 0.5)
		knob.Size = UDim2.fromOffset(28, 28)
		knob.BackgroundColor3 = WHITE
		corner(knob, UDim.new(0.5, 0))
		local ks = Instance.new("UIStroke")
		ks.Color = ACCENT
		ks.Thickness = 3
		ks.Parent = knob
		local value = label(r, "", Enum.Font.FredokaOne, 20, WHITE, 44)
		value.AnchorPoint = Vector2.new(1, 0.5)
		value.Position = UDim2.new(1, -16, 0.5, 0)
		value.Size = UDim2.fromOffset(64, 30)
		value.TextXAlignment = Enum.TextXAlignment.Right

		local function draw()
			local v = (current :: any)[key] :: number
			fill.Size = UDim2.fromScale(v, 1)
			knob.Position = UDim2.fromScale(v, 0.5)
			value.Text = if v <= 0 then "OFF" else string.format("%d%%", math.floor(v * 100 + 0.5))
		end
		local function set(v: number)
			v = math.clamp(math.floor(v * 20 + 0.5) / 20, 0, 1)
			if v == (current :: any)[key] then
				return
			end
			(current :: any)[key] = v
			-- Yerelde de yaz: ses anında değişsin (sunucu aynısını geri yazacak)
			player:SetAttribute(attr, v)
			draw()
			queueSave()
		end
		local function fromX(x: number)
			local abs = track.AbsolutePosition.X
			local width = math.max(track.AbsoluteSize.X, 1)
			set((x - abs) / width)
		end

		local dragging = false
		track.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				fromX(input.Position.X)
			end
		end)
		table.insert(connections, UserInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				fromX(input.Position.X)
			end
		end))
		table.insert(connections, UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end))
		table.insert(connections, UserInputService.InputBegan:Connect(function(input)
			if GuiService.SelectedObject ~= track then
				return
			end
			if input.KeyCode == Enum.KeyCode.DPadRight or input.KeyCode == Enum.KeyCode.Right then
				set(((current :: any)[key] :: number) + 0.1)
			elseif input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.Left then
				set(((current :: any)[key] :: number) - 0.1)
			end
		end))
		-- Sunucudan gelen değer (ilk yükleme) göstergeyi de güncellesin
		table.insert(connections, player:GetAttributeChangedSignal(attr):Connect(function()
			if dragging then
				return
			end
			readSetting(key, attr)
			draw()
		end))
		draw()
	end

	local function toggle(order: number, title: string)
		local r = row(order, title)
		local switch = Instance.new("TextButton")
		switch.Name = "Switch"
		switch.AnchorPoint = Vector2.new(1, 0.5)
		switch.Position = UDim2.new(1, -16, 0.5, 0)
		switch.Size = UDim2.fromOffset(92, 40)
		switch.AutoButtonColor = false
		switch.Text = ""
		switch.ZIndex = 44
		switch.Parent = r
		corner(switch, UDim.new(0.5, 0))
		local ss = Instance.new("UIStroke")
		ss.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ss.Color = WHITE
		ss.Thickness = 2
		ss.Parent = switch
		local thumb = frame(switch, "Thumb", 46)
		thumb.AnchorPoint = Vector2.new(0.5, 0.5)
		thumb.Size = UDim2.fromOffset(30, 30)
		thumb.BackgroundColor3 = WHITE
		corner(thumb, UDim.new(0.5, 0))
		local text = label(switch, "", Enum.Font.FredokaOne, 16, WHITE, 45)
		text.Size = UDim2.fromScale(1, 1)

		local function draw(animate: boolean)
			local on = current.shake
			local goal = { Position = UDim2.new(if on then 1 else 0, if on then -22 else 22, 0.5, 0) }
			if animate then
				tween(thumb, 0.15, goal)
				tween(switch, 0.15, { BackgroundColor3 = if on then PLAY_GREEN else Color3.fromRGB(70, 76, 96) })
			else
				thumb.Position = goal.Position
				switch.BackgroundColor3 = if on then PLAY_GREEN else Color3.fromRGB(70, 76, 96)
			end
			text.Text = if on then "ON   " else "   OFF"
			text.TextXAlignment = Enum.TextXAlignment.Center
		end
		switch.Activated:Connect(function()
			current.shake = not current.shake
			player:SetAttribute("SettingShake", current.shake)
			draw(true)
			queueSave()
		end)
		table.insert(connections, player:GetAttributeChangedSignal("SettingShake"):Connect(function()
			readSetting("shake", "SettingShake")
			draw(false)
		end))
		draw(false)
	end

	slider(1, "Music", "music", "SettingMusic")
	slider(2, "Sound Effects", "sfx", "SettingSfx")
	toggle(3, "Screen Shake")

	local saved = label(settingsPanel, "Settings are saved to your account.", Enum.Font.GothamMedium, 14, UiKit.MUTED, 42)
	saved.AnchorPoint = Vector2.new(0.5, 1)
	saved.Position = UDim2.new(0.5, 0, 1, -16)
	saved.Size = UDim2.new(1, -40, 0, 20)

	-- ── Nasıl oynanır ─────────────────────────────────────────────────────
	local helpVeil, helpPanel, helpClose = modal(gui, "HOW TO PLAY", Vector2.new(640, 520), 40)
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.Position = UDim2.fromOffset(24, 70)
	list.Size = UDim2.new(1, -48, 1, -90)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = WHITE
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ZIndex = 42
	list.Parent = helpPanel
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 10)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local tips = {
		{ icon = "crew", color = UiKit.CREW.CYAN, title = "Buy crewmates", text = "Crewmates ride the conveyor into your base. Buy them and place them on your podiums: every crewmate earns cash every second." },
		{ icon = "bag", color = UiKit.CREW.RED, title = "Steal from other bases", text = "Sneak into another base, grab a crewmate and carry it back to yours. Lock your base with the button inside to keep thieves out!" },
		{ icon = "flame", color = UiKit.CREW.ORANGE, title = "Grow your crew", text = "Spend cash on upgrades and new floors. Rebirth when you are rich enough: you start over, but earn more forever." },
		{ icon = "egg", color = UiKit.CREW.PINK, title = "Hatch pets", text = "Open eggs in the MedBay for pets that boost your cash and speed. Fuse 3 of the same pet into a bigger one at the scanner." },
		{ icon = "bolt", color = UiKit.CREW.YELLOW, title = "Tasks & events", text = "Do tasks around the ship for rewards. Watch the event timer: sabotages, meetings and impostors shake things up!" },
	}
	for i, tip in tips do
		local c = frame(list, "Tip" .. i, 43)
		c.LayoutOrder = i
		c.Size = UDim2.new(1, -12, 0, 92)
		c.BackgroundColor3 = Color3.fromRGB(34, 40, 58)
		c.BackgroundTransparency = 0.2
		corner(c, UDim.new(0, 12))
		local disc = frame(c, "Icon", 44)
		disc.AnchorPoint = Vector2.new(0, 0.5)
		disc.Position = UDim2.new(0, 14, 0.5, 0)
		disc.Size = UDim2.fromOffset(64, 64)
		disc.BackgroundColor3 = tip.color:Lerp(Color3.new(0, 0, 0), 0.55)
		corner(disc, UDim.new(0.5, 0))
		local ds = Instance.new("UIStroke")
		ds.Color = tip.color
		ds.Thickness = 2
		ds.Parent = disc
		if tip.icon == "crew" then
			local f = crewmate(disc, 44, tip.color, 45)
			f.Position = UDim2.fromScale(0.5, 0.5)
		else
			UiKit.Icon(disc, tip.icon, 40, tip.color)
		end
		local t = label(c, tip.title, Enum.Font.FredokaOne, 22, WHITE, 44)
		t.Position = UDim2.fromOffset(92, 10)
		t.Size = UDim2.new(1, -104, 0, 26)
		t.TextXAlignment = Enum.TextXAlignment.Left
		local body = label(c, tip.text, Enum.Font.GothamMedium, 14, Color3.fromRGB(200, 208, 226), 44)
		body.Position = UDim2.fromOffset(92, 38)
		body.Size = UDim2.new(1, -104, 0, 48)
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.TextWrapped = true
	end

	--[[
		Pencereler de tasarım alanıyla aynı ölçekte. Açılış animasyonu
		panelin kendi UIScale'ini kullanıyor, ekran ölçeği bu yüzden panelin
		içine alındığı sarmalayıcıda.
	]]
	for _, panel in { settingsPanel, helpPanel } do
		local wrap = frame(panel.Parent :: Instance, "Wrap", panel.ZIndex)
		wrap.Size = panel.Size
		wrap.BackgroundTransparency = 1
		panel.Position = UDim2.fromScale(0.5, 0.5)
		panel.Parent = wrap
		local fit = Instance.new("UIScale")
		fit.Name = "Fit"
		fit.Parent = wrap
	end
	local function refit()
		local s = fitScale()
		for _, panel in { settingsPanel, helpPanel } do
			local wrap = panel.Parent :: Frame
			local fit = wrap:FindFirstChild("Fit") :: UIScale
			fit.Scale = s
			-- Sol üstten ölçekleniyor: ortayı elle koru
			wrap.Position = UDim2.new(0.5, -wrap.Size.X.Offset * s / 2, 0.5, -wrap.Size.Y.Offset * s / 2)
		end
	end
	table.insert(connections, gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit))
	refit()

	local function closeModal(veil: GuiObject)
		veil.Visible = false
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = play
		end
	end
	settingsButton.Activated:Connect(function()
		openModal(settingsVeil, settingsPanel)
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = rows:FindFirstChild("Music") and (rows :: any).Music:FindFirstChild("Track")
		end
	end)
	helpButton.Activated:Connect(function()
		openModal(helpVeil, helpPanel)
	end)
	settingsClose.Activated:Connect(function()
		closeModal(settingsVeil)
	end)
	helpClose.Activated:Connect(function()
		closeModal(helpVeil)
	end)
	settingsVeil.Activated:Connect(function()
		closeModal(settingsVeil)
	end)
	helpVeil.Activated:Connect(function()
		closeModal(helpVeil)
	end)

	-- ── Canlandırma ───────────────────────────────────────────────────────
	local warp = 0 -- PLAY'e basınca 0 -> 1: yıldızlar çizgiye dönüyor
	local introOffset = -40 -- logo yukarıdan yerine süzülüyor
	local cometAt = os.clock() + 3
	local cometT = -1
	local started = os.clock()
	table.insert(connections, RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - started
		local speedMul = 1 + warp * 40
		for _, s in stars do
			s.x -= s.speed * dt * speedMul
			if s.x < -0.02 then
				s.x += 1.04
				s.y = rng:NextNumber()
			end
			s.f.Position = UDim2.fromScale(s.x, s.y)
			s.f.BackgroundTransparency = math.clamp(s.base + math.sin(t * 2 + s.phase) * 0.25, 0, 0.95)
			if warp > 0 then
				local base = s.f.Size.Y.Offset
				s.f.Size = UDim2.fromOffset(base + warp * 60, base)
			end
		end

		for i = #drifters, 1, -1 do
			local d = drifters[i]
			d.x += d.speed * dt * (1 + warp * 10)
			d.f.Position = UDim2.fromScale(d.x, d.y + math.sin(t * 0.8 + d.bob) * 0.015)
			d.f.Rotation += d.spin * dt
			if d.x > 1.12 then
				d.f:Destroy()
				table.remove(drifters, i)
				spawnDrifter(-0.1)
			end
		end

		-- Kayan yıldız
		if cometT < 0 and os.clock() > cometAt then
			cometT = 0
			comet.Position = UDim2.fromScale(rng:NextNumber(0.2, 0.9), rng:NextNumber(0.05, 0.35))
		end
		if cometT >= 0 then
			cometT += dt
			local a = cometT / 0.8
			comet.Position += UDim2.fromOffset(700 * dt, 230 * dt)
			comet.BackgroundTransparency = if a < 0.2 then 1 - a * 5 else math.clamp((a - 0.2) / 0.8, 0, 1)
			if a >= 1 then
				cometT = -1
				comet.BackgroundTransparency = 1
				cometAt = os.clock() + rng:NextNumber(4, 9)
			end
		end

		-- PLAY nefes alıyor, logo hafifçe süzülüyor
		glow.BackgroundTransparency = 0.72 + math.sin(t * 3) * 0.12
		glow.Size = UDim2.fromOffset(430 + math.sin(t * 3) * 10, 124 + math.sin(t * 3) * 6)
		if content.Visible then
			introOffset += (0 - introOffset) * math.min(1, dt * 6)
		end
		logo.Position = UDim2.fromOffset(REF.X / 2, 70 + math.sin(t * 1.2) * 5 + introOffset)
		mascot.Rotation = -12 + math.sin(t * 1.6) * 5
	end))

	--[[
		Açılış: yazı tipi yüklenmeden içerik görünmüyor (ilk karelerde logo
		ince varsayılan yazıyla çıkıyordu), sonra logo yukarıdan süzülüyor.
		Yükleme takılırsa 2 sn sonra yine açılıyor.
	]]
	content.Visible = false
	task.spawn(function()
		local done = false
		task.delay(2, function()
			done = true
		end)
		task.spawn(function()
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync({ main, playText, top, tagline })
			end)
			done = true
		end)
		while not done do
			task.wait()
		end
		content.Visible = true
	end)
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = play
	end

	-- ── PLAY ──────────────────────────────────────────────────────────────
	local function start()
		if not open then
			return
		end
		open = false
		settingsVeil.Visible = false
		helpVeil.Visible = false
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end

		-- Işık hızı: yıldızlar çizgiye, içerik büyüyüp kayboluyor
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 0.55 do
				warp = (os.clock() - t0) / 0.55
				RunService.RenderStepped:Wait()
			end
			warp = 1
		end)
		for _, d in content:GetDescendants() do
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				tween(d, 0.35, { TextTransparency = 1, BackgroundTransparency = 1 })
			elseif d:IsA("Frame") or d:IsA("ImageLabel") then
				tween(d, 0.35, { BackgroundTransparency = 1 })
				if d:IsA("ImageLabel") then
					tween(d, 0.35, { ImageTransparency = 1 })
				end
			elseif d:IsA("UIStroke") then
				tween(d, 0.35, { Transparency = 1 })
			end
		end

		task.delay(0.45, function()
			-- Beyaz parlama ve perde açılıyor
			local flash = frame(gui, "Flash", 100)
			flash.Size = UDim2.fromScale(1, 1)
			flash.BackgroundColor3 = WHITE
			flash.BackgroundTransparency = 1
			tween(flash, 0.12, { BackgroundTransparency = 0.2 }).Completed:Wait()

			-- Oyun geri geliyor
			for _, kind in hiddenCore do
				pcall(function()
					StarterGui:SetCoreGuiEnabled(kind, true)
				end)
			end
			if controls then
				controls:Enable()
			end
			if options and options.onPlay then
				task.spawn(options.onPlay)
			end

			bg.Visible = false
			tween(flash, 0.45, { BackgroundTransparency = 1 }).Completed:Wait()
			for _, c in connections do
				c:Disconnect()
			end
			gui:Destroy()
		end)
	end

	play.Activated:Connect(start)
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if settingsVeil.Visible or helpVeil.Visible then
			return
		end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			start()
		elseif input.KeyCode == Enum.KeyCode.ButtonA and not processed then
			start()
		end
	end))

	local handle = {
		IsOpen = function(): boolean
			return open
		end,
		Play = start,
	}
	TitleScreen.Current = handle
	return handle
end

return TitleScreen
