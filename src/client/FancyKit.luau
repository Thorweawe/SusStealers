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
	local conn = RunService.RenderStepped:Connect(function(dt)
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
	for i = 1, #text do
		local ch = string.sub(text, i, i)
		local w = TextService:GetTextSize(ch, size, FONT, Vector2.new(1000, 1000)).X
		local cell = FancyKit.title(holder, ch, size, top, bottom, z, driver)
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
