--!strict
--[[
	"Pahalı" arayüz dili (2026-09-28; referans: animasyonlu Roblox mağaza
	videosu). Pencerelerin ortak parçaları ve canlandırmaları:

	  driver(root)          canlandırma sürücüsü (pencere kapalıyken durur)
	  halftone(parent)      noktalı doku katmanı
	  title(parent, text)   kalın 3B başlık: derinlik katmanları + gradyan
	                        dolgu + kontur + üstünden geçen parıltı
	  jelly(parent, text)   harf harf zıplayan başlık ("SHOP")
	  gleam(object)         üstünden periyodik geçen beyaz parıltı şeridi
	  bob(object)           süzülme (ikonlar)
	  spin(image)           dönme (ışınlar)
	  glow(parent)          ikon arkası yumuşak hale
	  particles(frame)      yükselen parıltılar (gövde arkası)
	  juicy(target, hit)    üstüne gelince şişme + eğilme, basınca ezilme
]]

local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local UiArt = require(script.Parent.UiArt)

local FancyKit = {}

local OUTLINE = Color3.fromRGB(22, 20, 34)
local WHITE = Color3.new(1, 1, 1)
local FONT = Enum.Font.FredokaOne

export type Driver = {
	add: (fn: (t: number, dt: number) -> ()) -> (),
	destroy: () -> (),
}

--[[
	Canlandırma sürücüsü: `root` görünürken her karede kayıtlı işlevleri
	çağırıyor (t = açık kalınan toplam süre). Kapalıyken hiç çalışmıyor.
]]
function FancyKit.driver(root: GuiObject): Driver
	local fns: { (number, number) -> () } = {}
	local t = 0
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		if not root.Parent then
			-- Pencere yok edildi (Destroy çağrılmadan): sürücü de dursun
			conn:Disconnect()
			return
		end
		if not root.Visible then
			return
		end
		t += dt
		for _, fn in fns do
			fn(t, dt)
		end
	end)
	return {
		add = function(fn)
			table.insert(fns, fn)
		end,
		destroy = function()
			conn:Disconnect()
			table.clear(fns)
		end,
	}
end

local function copyCorner(from: Instance, to: Instance)
	local c = from:FindFirstChildOfClass("UICorner")
	if c then
		c:Clone().Parent = to
	end
end

--[[ Noktalı doku: `fade` üstte büyük altta küçülen noktalar, yoksa döşeme. ]]
function FancyKit.halftone(parent: GuiObject, color: Color3?, transparency: number?, z: number?, fade: boolean?): ImageLabel
	local img = Instance.new("ImageLabel")
	img.Name = "Halftone"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.ImageColor3 = color or WHITE
	img.ImageTransparency = transparency or 0.82
	img.ZIndex = z or parent.ZIndex
	img.Active = false
	if fade then
		img.Image = UiArt.Image("Texture", "halftone_fade")
		img.ScaleType = Enum.ScaleType.Crop
	else
		img.Image = UiArt.Image("Texture", "halftone")
		img.ScaleType = Enum.ScaleType.Tile
		img.TileSize = UDim2.fromOffset(44, 44)
	end
	img.Parent = parent
	copyCorner(parent, img)
	return img
end

--[[
	Parıltı: nesnenin üstüne beyaz katman; UIGradient saydamlığı dar çapraz
	bant, ofseti soldan sağa kayıyor. `period` sn'de bir geçiyor, `delay`
	faz kaydırması (kartlar aynı anda parlamasın).
]]
function FancyKit.gleam(target: GuiObject, driver: Driver, period: number?, delay: number?, strength: number?): Frame
	local layer = Instance.new("Frame")
	layer.Name = "Gleam"
	layer.BackgroundColor3 = WHITE
	layer.BackgroundTransparency = 1 - (strength or 0.5)
	layer.BorderSizePixel = 0
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = target.ZIndex + 1
	layer.Active = false
	layer.Parent = target
	copyCorner(target, layer)
	local g = Instance.new("UIGradient")
	g.Rotation = 20
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(0.58, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Offset = Vector2.new(-1, 0)
	g.Parent = layer
	local p = period or 3.2
	local d = delay or 0
	driver.add(function(t)
		local k = ((t - d) % p) / 0.7
		g.Offset = Vector2.new(if k <= 1 then -1 + 2 * k else 1, 0)
	end)
	return layer
end

--[[
	Kalın 3B başlık: arkada koyu derinlik kopyaları (aşağı kaydırılmış), önde
	gradyan dolgulu yazı + kalın kontur, en önde (sürücü verilirse) kayan
	parıltı kopyası. Döner: katmanları taşıyan çerçeve (boyut/konum ona).
]]
function FancyKit.title(parent: GuiObject, text: string, size: number, top: Color3, bottom: Color3, z: number, driver: Driver?, outline: number?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "FancyTitle"
	holder.BackgroundTransparency = 1
	holder.ZIndex = z
	holder.Parent = parent
	local stroke = outline or math.max(3, size / 9)
	local function label(dy: number, color: Color3, zz: number, withStroke: boolean): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Position = UDim2.fromOffset(0, dy)
		l.Font = FONT
		l.Text = text
		l.TextSize = size
		l.TextColor3 = color
		l.ZIndex = zz
		l.Parent = holder
		if withStroke then
			local s = Instance.new("UIStroke")
			s.Color = OUTLINE
			s.Thickness = stroke
			s.LineJoinMode = Enum.LineJoinMode.Round
			s.Parent = l
		end
		return l
	end
	local depth = math.max(1.5, size / 22)
	for i = 3, 1, -1 do
		label(i * depth, OUTLINE, z, true)
	end
	local main = label(0, WHITE, z + 1, true)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, top:Lerp(WHITE, 0.35)),
		ColorSequenceKeypoint.new(0.45, top),
		ColorSequenceKeypoint.new(1, bottom),
	})
	g.Parent = main
	if driver then
		local shine = label(0, WHITE, z + 2, false)
		local sg = Instance.new("UIGradient")
		sg.Rotation = 20
		sg.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, 0.15),
			NumberSequenceKeypoint.new(0.6, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		sg.Parent = shine
		local p = 3.6 + (#text % 4) * 0.45
		driver.add(function(t)
			local k = (t % p) / 0.8
			sg.Offset = Vector2.new(if k <= 1 then -1 + 2 * k else 1, 0)
		end)
	end
	return holder
end

--[[ Başlığın bütün katmanlarında yazıyı / hizayı / boyutu değiştir. ]]
function FancyKit.setTitle(holder: Frame, text: string?, align: Enum.TextXAlignment?)
	for _, l in holder:GetChildren() do
		if l:IsA("TextLabel") then
			if text then
				l.Text = text
			end
			if align then
				l.TextXAlignment = align
			end
		end
	end
end

--[[ Jöle başlık: her harf ayrı 3B başlık, sırayla zıplayıp hafifçe dönüyor. ]]
function FancyKit.jelly(parent: GuiObject, text: string, size: number, top: Color3, bottom: Color3, z: number, driver: Driver): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Jelly"
	holder.BackgroundTransparency = 1
	holder.ZIndex = z
	holder.Parent = parent
	local x = 0
	type Cell = { frame: Frame, x: number }
	local cells: { Cell } = {}
	-- 2026-10-01: harf harf UTF-8 (eskiden bayt bayt: "🌠" dört "?" kutusu oluyordu)
	for _, code in utf8.codes(text) do
		local ch = utf8.char(code)
		if ch == " " then
			x += math.floor(size * 0.32)
			continue
		end
		local w = TextService:GetTextSize(ch, size, FONT, Vector2.new(1000, 1000)).X
		local cell: Frame
		if code >= 0x2000 then
			-- Emoji: renkli kalsın (gradyan / koyu gölge katmanı emojiyi boyuyor)
			cell = Instance.new("Frame")
			cell.BackgroundTransparency = 1
			cell.ZIndex = z
			cell.Parent = holder
			local e = Instance.new("TextLabel")
			e.BackgroundTransparency = 1
			e.Size = UDim2.fromScale(1, 1)
			e.Font = FONT
			e.Text = ch
			e.TextSize = size
			e.ZIndex = z + 1
			e.Parent = cell
		else
			cell = FancyKit.title(holder, ch, size, top, bottom, z, driver)
		end
		cell.Size = UDim2.new(0, w + 8, 1, 0)
		cell.Position = UDim2.fromOffset(x, 0)
		table.insert(cells, { frame = cell, x = x })
		x += w + 1
	end
	holder.Size = UDim2.new(0, x + 8, 0, size + 14)
	driver.add(function(t)
		for i, c in cells do
			local ph = t * 3.6 - i * 0.6
			local bump = math.max(0, math.sin(ph))
			c.frame.Position = UDim2.fromOffset(c.x, -bump * size * 0.14)
			c.frame.Rotation = math.sin(ph + 0.9) * 5
		end
	end)
	return holder
end

--[[ Süzülme: dikey salınım + hafif dönme (taban = şimdiki konum). ]]
function FancyKit.bob(target: GuiObject, driver: Driver, amplitude: number?, period: number?, phase: number?, tilt: number?)
	local base = target.Position
	local a = amplitude or 5
	local p = period or 2.4
	local ph = phase or 0
	local r = tilt or 3
	driver.add(function(t)
		local w = (t / p) * math.pi * 2 + ph
		target.Position = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset + math.sin(w) * a)
		target.Rotation = math.sin(w + 1.2) * r
	end)
end

function FancyKit.spin(target: GuiObject, driver: Driver, degreesPerSecond: number?)
	local speed = degreesPerSecond or 12
	driver.add(function(_, dt)
		target.Rotation = (target.Rotation + speed * dt) % 360
	end)
end

--[[ İkonun arkasına yumuşak renkli hale. ]]
function FancyKit.glow(parent: GuiObject, color: Color3, scale: number?, transparency: number?, z: number?): ImageLabel
	local g = Instance.new("ImageLabel")
	g.Name = "Glow"
	g.BackgroundTransparency = 1
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.fromScale(0.5, 0.5)
	g.Size = UDim2.fromScale(scale or 1.3, scale or 1.3)
	g.Image = UiArt.Image("Texture", "glow")
	g.ImageColor3 = color
	g.ImageTransparency = transparency or 0.3
	g.ZIndex = z or parent.ZIndex
	g.Parent = parent
	return g
end

--[[ Yükselen parıltılar: `frame` içinde aşağıdan yukarı süzülen, dönen, sönen yıldızlar. ]]
function FancyKit.particles(frame: GuiObject, driver: Driver, count: number, color: Color3?, z: number?)
	local rng = Random.new(11)
	type P = { img: ImageLabel, x: number, speed: number, spin: number, phase: number }
	local list: { P } = {}
	for _ = 1, count do
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Image = UiArt.Image("Texture", "sparkle")
		img.ImageColor3 = color or Color3.fromRGB(255, 240, 180)
		img.ZIndex = z or frame.ZIndex
		img.Parent = frame
		local size = rng:NextNumber(10, 26)
		img.Size = UDim2.fromOffset(size, size)
		table.insert(list, { img = img, x = rng:NextNumber(0.02, 0.98), speed = rng:NextNumber(0.04, 0.1),
			spin = rng:NextNumber(-60, 60), phase = rng:NextNumber(0, 1) })
	end
	driver.add(function(t)
		for _, p in list do
			local y = 1.05 - ((t * p.speed + p.phase) % 1) * 1.15
			p.img.Position = UDim2.fromScale(p.x + math.sin(t * 0.8 + p.phase * 6) * 0.015, y)
			p.img.Rotation = t * p.spin
			p.img.ImageTransparency = 0.35 + math.min(1, math.abs(y - 0.5) * 2) * 0.6
		end
	end)
end

--[[
	Tepki: `hit` üstüne gelince `target` biraz büyüyüp eğiliyor (Back
	yumuşaması), basınca eziliyor.
]]
function FancyKit.juicy(target: GuiObject, hit: GuiButton, grow: number?, lean: number?)
	local scale = target:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = target
	local g = grow or 1.05
	local l = lean or 2
	local function to(s: number, r: number, time: number)
		local info = TweenInfo.new(time, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(scale, info, { Scale = s }):Play()
		TweenService:Create(target, info, { Rotation = r }):Play()
	end
	hit.MouseEnter:Connect(function()
		to(g, -l, 0.18)
	end)
	hit.MouseLeave:Connect(function()
		to(1, 0, 0.2)
	end)
	hit.MouseButton1Down:Connect(function()
		to(0.94, 0, 0.08)
	end)
	hit.MouseButton1Up:Connect(function()
		to(g, -l, 0.22)
	end)
end

-- ─── Pencere parçaları (mağazanın dili; bütün pencereler) ────────────────────

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

local function gradient(parent: Instance, colors: { Color3 }, rotation: number): UIGradient
	local g = Instance.new("UIGradient")
	g.Rotation = rotation
	local keys = {}
	for i, c in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(1, #colors - 1), c))
	end
	g.Color = ColorSequence.new(keys)
	g.Parent = parent
	return g
end
FancyKit.corner = corner
FancyKit.border = border
FancyKit.gradient = gradient

--[[
	Pencere kabuğu: koyu lacivert gövde (gradyan + kalın kenar), soluk nokta
	dokusu, yükselen parıltılar; üstte renkli başlık şeridi (yatay gradyan,
	kayan çapraz şeritler, noktalar, parıltı), harf harf zıplayan başlık ve
	kırmızı kare X. Döner: header, close, body (başlığın altındaki alan).
]]
export type Shell = { header: Frame, close: TextButton, body: Frame }
function FancyKit.shell(root: Frame, title: string, colors: { Color3 }, headerH: number, z: number, driver: Driver, titleSize: number?): Shell
	for _, child in root:GetChildren() do
		if child:IsA("UIGradient") or child:IsA("UIStroke") or child.Name == "ModernRim" or child.Name == "Kit_window" then
			child:Destroy()
		end
	end
	root.BackgroundColor3 = WHITE
	gradient(root, { Color3.fromRGB(34, 38, 56), Color3.fromRGB(20, 22, 36) }, 90)
	border(root, OUTLINE, 5)
	if not root:FindFirstChildOfClass("UICorner") then
		corner(root, 16)
	end
	-- 2026-10-03: ChatGPT nebula gövdesi (UiArt.Kit); düz gradyan + kenar kapanıyor
	UiArt.plain(root)
	UiArt.kit(root, "window", -1) -- her şeyin altında

	local body = Instance.new("Frame")
	body.Name = "FancyBody"
	body.Position = UDim2.fromOffset(0, headerH)
	body.Size = UDim2.new(1, 0, 1, -headerH)
	body.BackgroundTransparency = 1
	body.ClipsDescendants = true
	body.ZIndex = z
	body.Parent = root
	FancyKit.halftone(body, Color3.fromRGB(120, 140, 220), 0.9, z)
	FancyKit.particles(body, driver, 12, Color3.fromRGB(255, 230, 150), z)

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, headerH)
	header.BackgroundColor3 = WHITE
	header.BorderSizePixel = 0
	header.ClipsDescendants = true
	header.ZIndex = z + 1
	header.Parent = root
	corner(header, 16)
	local hg = gradient(header, colors, 0)
	local foot = Instance.new("Frame")
	foot.Position = UDim2.new(0, 0, 1, -16)
	foot.Size = UDim2.new(1, 0, 0, 16)
	foot.BackgroundColor3 = WHITE
	foot.BorderSizePixel = 0
	foot.ZIndex = z + 1
	foot.Parent = header
	hg:Clone().Parent = foot
	-- Parlak beyaz başlık görseli pencerenin renk gradyanıyla boyanıyor
	header.BackgroundTransparency = 1
	foot.Visible = false
	header.ClipsDescendants = false
	hg:Clone().Parent = UiArt.kit(header, "header", z + 1)
	hg.Enabled = false
	local stripes = Instance.new("ImageLabel")
	stripes.BackgroundTransparency = 1
	stripes.Size = UDim2.new(1, 64, 1, 0)
	stripes.Image = UiArt.Image("Texture", "stripes")
	stripes.ScaleType = Enum.ScaleType.Tile
	stripes.TileSize = UDim2.fromOffset(64, 64)
	stripes.ImageTransparency = 0.88
	stripes.ZIndex = z + 2
	stripes.Parent = header
	driver.add(function(t)
		stripes.Position = UDim2.fromOffset(-((t * 18) % 64), 0)
	end)
	FancyKit.halftone(header, WHITE, 0.86, z + 2, true)
	FancyKit.gleam(header, driver, 5, 1, 0.35)
	local rule = Instance.new("Frame")
	rule.Position = UDim2.new(0, 0, 0, headerH - 2)
	rule.Size = UDim2.new(1, 0, 0, 4)
	rule.BackgroundColor3 = OUTLINE
	rule.BorderSizePixel = 0
	rule.ZIndex = z + 3
	rule.Parent = root

	local size = titleSize or math.floor(headerH * 0.7)
	local jelly = FancyKit.jelly(header, title, size, Color3.fromRGB(255, 226, 60), Color3.fromRGB(255, 140, 20), z + 4, driver)
	jelly.Position = UDim2.fromOffset(22, math.floor((headerH - size - 14) / 2))

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position = UDim2.new(1, -10, 0, headerH / 2)
	close.Size = UDim2.fromOffset(headerH - 16, headerH - 16)
	close.BackgroundColor3 = WHITE
	close.BorderSizePixel = 0
	close.AutoButtonColor = false
	close.Text = ""
	close.ZIndex = z + 5
	close.Parent = root
	corner(close, 8)
	border(close, OUTLINE, 3)
	gradient(close, { Color3.fromRGB(250, 70, 70), Color3.fromRGB(190, 20, 30) }, 90)
	UiArt.plain(close)
	UiArt.kit(close, "close", z + 5).Size = UDim2.fromScale(1.2, 1.2)
	local x = Instance.new("TextLabel")
	x.BackgroundTransparency = 1
	x.Size = UDim2.fromScale(1, 1)
	x.Font = FONT
	x.Text = "X"
	x.TextSize = math.floor((headerH - 16) * 0.72)
	x.TextColor3 = WHITE
	x.ZIndex = z + 6
	x.Visible = false -- görselde X var
	x.Parent = close
	local xs = Instance.new("UIStroke")
	xs.Color = OUTLINE
	xs.Thickness = 4
	xs.Parent = x
	FancyKit.gleam(close, driver, 4.2, 2, 0.4)
	FancyKit.juicy(close, close, 1.1, -8)
	return { header = header, close = close, body = body }
end

--[[
	Tıknaz düğme (mağazanın satın alma düğmesi): alt gölge, gradyan, üst
	parlak şerit, kalın kenar, isteğe bağlı Robux simgesi, parıltı ve tepki.
	set(text, color?, robux?): color nil ise gri ve pasif.
]]
export type Button = {
	holder: Frame,
	button: TextButton,
	label: TextLabel,
	set: (text: string, color: Color3?, robux: boolean?) -> (),
}
local ROBUX_ICON = "rbxasset://textures/ui/common/robux@3x.png"
function FancyKit.button(parent: Instance, size: UDim2, color: Color3, textSize: number, z: number, driver: Driver?, gleamDelay: number?): Button
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
	corner(shadow, 12)
	local button = Instance.new("TextButton")
	button.Size = UDim2.new(1, 0, 1, -5)
	button.BackgroundColor3 = WHITE
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = z + 1
	button.Parent = holder
	corner(button, 12)
	border(button, OUTLINE, 3)
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
	corner(gloss, 8)
	-- ChatGPT düğme yüzü (beyaz, renge boyanıyor); kendi gölgesi ve parlaması var
	UiArt.plain(button)
	gloss.Visible = false
	shadow.Visible = false
	local face = UiArt.kit(button, "button", z + 1)
	face.Size = UDim2.new(1, 6, 1, 8)
	face.Position = UDim2.new(0.5, 0, 0.5, 2)
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
	icon.ZIndex = z + 4
	icon.Visible = false
	icon.Parent = row
	local label = Instance.new("TextLabel")
	label.LayoutOrder = 2
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromOffset(0, textSize + 4)
	label.Font = FONT
	label.TextSize = textSize
	label.TextColor3 = WHITE
	label.RichText = true
	label.ZIndex = z + 4
	label.Parent = row
	local ls = Instance.new("UIStroke")
	ls.Color = OUTLINE
	ls.Thickness = math.max(2, textSize / 10)
	ls.LineJoinMode = Enum.LineJoinMode.Round
	ls.Parent = label
	local GREY = Color3.fromRGB(120, 128, 146)
	local function set(text: string, tone: Color3?, robux: boolean?)
		local c = tone or GREY
		shadow.BackgroundColor3 = c:Lerp(Color3.new(0, 0, 0), 0.55)
		grad.Color = ColorSequence.new(c:Lerp(WHITE, 0.25), c:Lerp(Color3.new(0, 0, 0), 0.12))
		face.ImageColor3 = c:Lerp(WHITE, 0.08)
		label.Text = text
		icon.Visible = robux == true
		button.Active = tone ~= nil
	end
	set("", color)
	button.MouseButton1Down:Connect(function()
		button.Position = UDim2.fromOffset(0, 4)
	end)
	local function release()
		button.Position = UDim2.fromOffset(0, 0)
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	if driver then
		FancyKit.gleam(button, driver, 3.4, gleamDelay or 0, 0.55)
		FancyKit.juicy(holder, button, 1.05, 2)
	end
	return { holder = holder, button = button, label = label, set = set }
end

--[[
	Renkli kart zemini (mağaza kartları): rengin gradyanı, dönen ışınlar,
	üstte büyük aşağı küçülen noktalar, kalın kenar + içte açık kenar.
]]
function FancyKit.card(parent: Instance, tint: Color3, size: UDim2, z: number, driver: Driver?, raysAt: UDim2?): Frame
	local card = Instance.new("Frame")
	card.Size = size
	card.BackgroundColor3 = WHITE
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.ZIndex = z
	card.Parent = parent
	corner(card, 14)
	gradient(card, { tint:Lerp(WHITE, 0.28), tint:Lerp(Color3.new(0, 0, 0), 0.25) }, 90)
	local rays = Instance.new("ImageLabel")
	rays.Name = "Rays"
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = raysAt or UDim2.fromScale(0.5, 0.45)
	rays.Size = UDim2.fromOffset(460, 460)
	rays.BackgroundTransparency = 1
	rays.Image = UiArt.Image("Texture", "rays")
	rays.ImageColor3 = tint:Lerp(WHITE, 0.75)
	rays.ImageTransparency = 0.35
	rays.ZIndex = z
	rays.Parent = card
	if driver then
		FancyKit.spin(rays, driver, 10)
	end
	FancyKit.halftone(card, WHITE, 0.8, z, true)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.ZIndex = z + 1
	frame.Parent = card
	corner(frame, 14)
	border(frame, OUTLINE, 4)
	local inner = Instance.new("Frame")
	inner.Position = UDim2.fromOffset(3, 3)
	inner.Size = UDim2.new(1, -6, 1, -6)
	inner.BackgroundTransparency = 1
	inner.ZIndex = z + 1
	inner.Parent = card
	corner(inner, 11)
	local is = Instance.new("UIStroke")
	is.Color = tint:Lerp(WHITE, 0.55)
	is.Thickness = 2
	is.Transparency = 0.3
	is.Parent = inner
	return card
end

--[[ Yalnızca üstüne gelince büyüme (tıklanmayan kartlar için; düğmeyi örtmüyor). ]]
function FancyKit.hover(target: GuiObject, grow: number?)
	local scale = target:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = target
	local info = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	target.MouseEnter:Connect(function()
		TweenService:Create(scale, info, { Scale = grow or 1.03 }):Play()
	end)
	target.MouseLeave:Connect(function()
		TweenService:Create(scale, info, { Scale = 1 }):Play()
	end)
end

return FancyKit
