--!strict
--[[
	"Clear Asteroids" — Weapons odasındaki topçu konsolunun oyunu.

	Among Us'taki görevin aynısı: karanlık hedef ekranı, yeşil nişangâh,
	sağdan sola süzülen asteroitler. Tıklanan (dokunulan) asteroit patlıyor;
	köşedeki toptan hedefe lazer çiziliyor. 20 tanesi vurulunca görev
	tamam ve sunucuya "bitti" gidiyor — ödülü ve bütün kontrolleri sunucu
	yapıyor (MinigameService.TryComplete).

	Konsolun promptunu sunucu kuruyor ("AsteroidPrompt"); oyuncunun kendi
	tetiklemesini burada görüp pencereyi açıyoruz.
]]

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local UiKit = require(script.Parent.UiKit)

local AsteroidGame = {}

export type Game = {
	Open: () -> (),
	Close: () -> (),
	Destroy: () -> (),
}

local ACCENT = UiKit.CREW.RED
local SCOPE = Color3.fromRGB(90, 255, 140)
local SPACE = Color3.fromRGB(8, 14, 28)
local Z = 45

local ROCKS = {
	Color3.fromRGB(150, 132, 116), Color3.fromRGB(126, 112, 100),
	Color3.fromRGB(170, 150, 128), Color3.fromRGB(112, 104, 98),
}

type Rock = {
	button: TextButton,
	x: number, y: number,
	vx: number, vy: number,
	spin: number,
	size: number,
}

local function tween(obj: Instance, t: number, goal: { [string]: any })
	TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

local function frame(parent: Instance, color: Color3, z: number, round: boolean?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
	end
	return f
end

function AsteroidGame.Create(screen: ScreenGui): Game
	local rules = Config.AsteroidTask
	local doneRemote = Net.Get("AsteroidsDone")

	local root = UiKit.Window(screen, "AsteroidGame", ACCENT)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(600, 470)
	root.Visible = false
	root.ZIndex = Z

	-- ─── Başlık ─────────────────────────────────────────────────────────────
	local badge = Instance.new("Frame")
	badge.Position = UDim2.fromOffset(16, 12)
	badge.Size = UDim2.fromOffset(32, 32)
	badge.BackgroundTransparency = 1
	badge.ZIndex = Z + 2
	badge.Parent = root
	UiKit.Icon(badge, "bolt", 30, UiKit.CREW.YELLOW)

	local title = Instance.new("TextLabel")
	title.Position = UDim2.fromOffset(56, 10)
	title.Size = UDim2.new(1, -110, 0, 24)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 21
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.new(1, 1, 1)
	title.Text = "CLEAR ASTEROIDS"
	title.ZIndex = Z + 2
	title.Parent = root

	local hint = Instance.new("TextLabel")
	hint.Position = UDim2.fromOffset(56, 32)
	hint.Size = UDim2.new(1, -110, 0, 16)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = 12
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextColor3 = UiKit.MUTED
	hint.Text = string.format("Click the asteroids before they pass the ship. Destroy %d.", rules.goal)
	hint.ZIndex = Z + 2
	hint.Parent = root

	local close = UiKit.CloseButton(root)
	close.ZIndex = Z + 6

	-- ─── Hedef ekranı ───────────────────────────────────────────────────────
	local canvas = Instance.new("TextButton")
	canvas.Name = "Scope"
	canvas.AutoButtonColor = false
	canvas.Text = ""
	canvas.Position = UDim2.fromOffset(16, 58)
	canvas.Size = UDim2.new(1, -32, 1, -112)
	canvas.BackgroundColor3 = SPACE
	canvas.BorderSizePixel = 0
	canvas.ClipsDescendants = true
	canvas.ZIndex = Z + 1
	canvas.Parent = root
	UiKit.Corner(canvas, 12)
	UiKit.Stroke(canvas, SCOPE, 2, 0.35)

	-- Ekran ızgarası ve yıldızlar: boş bir siyah kutu değil, bir radar
	for i = 1, 5 do
		local v = frame(canvas, SCOPE, Z + 1)
		v.Position = UDim2.fromScale(i / 6, 0)
		v.Size = UDim2.new(0, 1, 1, 0)
		v.BackgroundTransparency = 0.9
	end
	for i = 1, 3 do
		local h = frame(canvas, SCOPE, Z + 1)
		h.Position = UDim2.fromScale(0, i / 4)
		h.Size = UDim2.new(1, 0, 0, 1)
		h.BackgroundTransparency = 0.9
	end
	local rng = Random.new()
	for _ = 1, 40 do
		local s = rng:NextNumber(1, 2.5)
		local star = frame(canvas, Color3.new(1, 1, 1), Z + 1, true)
		star.Size = UDim2.fromOffset(s, s)
		star.Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber())
		star.BackgroundTransparency = rng:NextNumber(0.2, 0.7)
	end

	-- Nişangâh: ekran boyu iki ince çizgi + halka + nokta
	local hLine = frame(canvas, SCOPE, Z + 5)
	hLine.Size = UDim2.new(1, 0, 0, 1)
	hLine.BackgroundTransparency = 0.45
	local vLine = frame(canvas, SCOPE, Z + 5)
	vLine.Size = UDim2.new(0, 1, 1, 0)
	vLine.BackgroundTransparency = 0.45
	local reticle = frame(canvas, SCOPE, Z + 5, true)
	reticle.AnchorPoint = Vector2.new(0.5, 0.5)
	reticle.Size = UDim2.fromOffset(38, 38)
	reticle.BackgroundTransparency = 1
	UiKit.Stroke(reticle, SCOPE, 2, 0.1)
	local dot = frame(reticle, SCOPE, Z + 6, true)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(5, 5)

	-- Lazer ekranın alt ortasından çıkıyor (ayrı bir top çizimi yok)

	-- Tamamlandı yazısı
	local banner = Instance.new("TextLabel")
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.5)
	banner.Size = UDim2.fromOffset(360, 70)
	banner.BackgroundColor3 = Color3.fromRGB(30, 140, 70)
	banner.BorderSizePixel = 0
	banner.Font = Enum.Font.FredokaOne
	banner.TextSize = 34
	banner.TextColor3 = Color3.new(1, 1, 1)
	banner.TextStrokeTransparency = 0.4
	banner.Text = "TASK COMPLETE"
	banner.Visible = false
	banner.ZIndex = Z + 8
	banner.Parent = canvas
	UiKit.Corner(banner, 14)
	UiKit.Stroke(banner, Color3.new(1, 1, 1), 3, 0)

	-- ─── Sayaç ──────────────────────────────────────────────────────────────
	local counter = Instance.new("TextLabel")
	counter.Position = UDim2.new(0, 18, 1, -46)
	counter.Size = UDim2.new(0, 200, 0, 20)
	counter.BackgroundTransparency = 1
	counter.Font = Enum.Font.GothamBlack
	counter.TextSize = 15
	counter.TextXAlignment = Enum.TextXAlignment.Left
	counter.TextColor3 = SCOPE
	counter.ZIndex = Z + 2
	counter.Parent = root

	local barHolder = Instance.new("Frame")
	barHolder.Position = UDim2.new(0, 220, 1, -40)
	barHolder.Size = UDim2.new(1, -238, 0, 10)
	barHolder.BackgroundTransparency = 1
	barHolder.ZIndex = Z + 2
	barHolder.Parent = root
	local track, fill = UiKit.Bar(barHolder, 10, SCOPE)
	track.ZIndex = Z + 2
	fill.ZIndex = Z + 3

	-- ─── Oyun durumu ────────────────────────────────────────────────────────
	local rocks: { Rock } = {}
	local destroyed = 0
	local running = false
	local finished = false
	local spawnIn = 0

	local function refresh()
		counter.Text = string.format("DESTROYED  %d / %d", destroyed, rules.goal)
		fill.Size = UDim2.fromScale(math.clamp(destroyed / rules.goal, 0, 1), 1)
	end

	local function clearRocks()
		for _, r in rocks do
			r.button:Destroy()
		end
		table.clear(rocks)
	end

	-- Toptan hedefe lazer: kısa süre görünüp sönüyor
	local function laser(target: Vector2)
		local size = canvas.AbsoluteSize
		local from = Vector2.new(size.X / 2, size.Y)
		local delta = target - from
		local beam = frame(canvas, UiKit.CREW.RED:Lerp(Color3.new(1, 1, 1), 0.3), Z + 3)
		beam.AnchorPoint = Vector2.new(0.5, 0.5)
		beam.Position = UDim2.fromOffset((from.X + target.X) / 2, (from.Y + target.Y) / 2)
		beam.Size = UDim2.fromOffset(delta.Magnitude, 4)
		beam.Rotation = math.deg(math.atan2(delta.Y, delta.X))
		tween(beam, 0.18, { BackgroundTransparency = 1, Size = UDim2.fromOffset(delta.Magnitude, 1) })
		task.delay(0.2, function()
			beam:Destroy()
		end)
	end

	local function explode(at: Vector2, size: number, color: Color3)
		local flash = frame(canvas, Color3.fromRGB(255, 230, 150), Z + 4, true)
		flash.AnchorPoint = Vector2.new(0.5, 0.5)
		flash.Position = UDim2.fromOffset(at.X, at.Y)
		flash.Size = UDim2.fromOffset(size * 0.6, size * 0.6)
		tween(flash, 0.25, { Size = UDim2.fromOffset(size * 1.6, size * 1.6), BackgroundTransparency = 1 })
		for i = 1, 6 do
			local a = (i / 6) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
			local bit = frame(canvas, color, Z + 3, true)
			bit.AnchorPoint = Vector2.new(0.5, 0.5)
			bit.Position = UDim2.fromOffset(at.X, at.Y)
			local s = size * rng:NextNumber(0.15, 0.3)
			bit.Size = UDim2.fromOffset(s, s)
			local d = size * rng:NextNumber(0.8, 1.4)
			tween(bit, 0.45, {
				Position = UDim2.fromOffset(at.X + math.cos(a) * d, at.Y + math.sin(a) * d),
				BackgroundTransparency = 1,
			})
		end
		task.delay(0.5, function()
			flash:Destroy()
		end)
	end

	local function complete()
		finished = true
		running = false
		banner.Visible = true
		banner.Size = UDim2.fromOffset(200, 40)
		tween(banner, 0.3, { Size = UDim2.fromOffset(360, 70) })
		doneRemote:FireServer()
		task.delay(1.8, function()
			if finished then
				root.Visible = false
			end
		end)
	end

	local function hit(rock: Rock)
		local index = table.find(rocks, rock)
		if not index or not running then
			return
		end
		table.remove(rocks, index)
		local at = Vector2.new(rock.x, rock.y)
		laser(at)
		explode(at, rock.size, rock.button.BackgroundColor3)
		rock.button:Destroy()
		destroyed += 1
		refresh()
		if destroyed >= rules.goal then
			complete()
		end
	end

	local function spawnRock()
		local size = canvas.AbsoluteSize
		local s = rng:NextNumber(34, 60)
		local button = Instance.new("TextButton")
		button.AutoButtonColor = false
		button.Text = ""
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Size = UDim2.fromOffset(s, s * rng:NextNumber(0.82, 1))
		button.BackgroundColor3 = ROCKS[rng:NextInteger(1, #ROCKS)]
		button.BorderSizePixel = 0
		button.ZIndex = Z + 2
		button.Parent = canvas
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.45, 0)
		c.Parent = button
		UiKit.Stroke(button, button.BackgroundColor3:Lerp(Color3.new(0, 0, 0), 0.45), 2, 0)
		-- Kraterler
		for k = 1, 3 do
			local crater = frame(button, button.BackgroundColor3:Lerp(Color3.new(0, 0, 0), 0.3), Z + 2, true)
			crater.AnchorPoint = Vector2.new(0.5, 0.5)
			crater.Position = UDim2.fromScale(({ 0.35, 0.65, 0.45 })[k], ({ 0.35, 0.5, 0.72 })[k])
			local cs = ({ 0.26, 0.2, 0.16 })[k]
			crater.Size = UDim2.fromScale(cs, cs)
		end

		local rock: Rock = {
			button = button,
			x = size.X + s,
			y = rng:NextNumber(s, math.max(s + 1, size.Y - s - 30)),
			vx = -rng:NextNumber(110, 200),
			vy = rng:NextNumber(-25, 25),
			spin = rng:NextNumber(-90, 90),
			size = s,
		}
		button.Position = UDim2.fromOffset(rock.x, rock.y)
		button.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				hit(rock)
			end
		end)
		table.insert(rocks, rock)
	end

	-- Boşa atış: yalnızca lazer
	canvas.InputBegan:Connect(function(input)
		if not running then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			local p = Vector2.new(input.Position.X, input.Position.Y) - canvas.AbsolutePosition
			laser(p)
		end
	end)

	local stepConnection = RunService.RenderStepped:Connect(function(dt: number)
		if not root.Visible then
			return
		end

		-- Nişangâh fareyi izliyor (dokunmatikte son dokunuşta kalıyor)
		local mouse = UserInputService:GetMouseLocation() - GuiService:GetGuiInset()
		local p = mouse - canvas.AbsolutePosition
		local size = canvas.AbsoluteSize
		local inside = p.X >= 0 and p.Y >= 0 and p.X <= size.X and p.Y <= size.Y
		reticle.Visible = inside
		hLine.Visible = inside
		vLine.Visible = inside
		if inside then
			reticle.Position = UDim2.fromOffset(p.X, p.Y)
			hLine.Position = UDim2.fromOffset(0, p.Y)
			vLine.Position = UDim2.fromOffset(p.X, 0)
		end

		if not running then
			return
		end

		spawnIn -= dt
		if spawnIn <= 0 and #rocks < 7 then
			spawnRock()
			spawnIn = rng:NextNumber(0.45, 0.85)
		end

		for i = #rocks, 1, -1 do
			local r = rocks[i]
			r.x += r.vx * dt
			r.y += r.vy * dt
			r.button.Position = UDim2.fromOffset(r.x, r.y)
			r.button.Rotation += r.spin * dt
			if r.x < -r.size or r.y < -r.size or r.y > size.Y + r.size then
				r.button:Destroy()
				table.remove(rocks, i)
			end
		end
	end)

	--[[
		Ödül 20 dakikada bir (sunucu AsteroidReadyAt niteliğini yazıyor).
		Beklerken oyun oynanabiliyor; alt başlık kalan süreyi söylüyor ki
		oyuncu ödülsüz bittiğine şaşırmasın.
	]]
	local localPlayer = game:GetService("Players").LocalPlayer
	local function rewardHint(): string
		local readyAt = localPlayer:GetAttribute("AsteroidReadyAt")
		local left = if typeof(readyAt) == "number" then readyAt - os.time() else 0
		if left > 0 then
			return string.format("Practice run — next reward in %d:%02d. Destroy %d.", left // 60, left % 60, rules.goal)
		end
		return string.format("Click the asteroids before they pass the ship. Destroy %d for a reward!", rules.goal)
	end

	local function open()
		hint.Text = rewardHint()
		clearRocks()
		destroyed = 0
		finished = false
		banner.Visible = false
		spawnIn = 0.2
		refresh()
		root.Visible = true
		running = true
	end

	local function stop()
		running = false
		finished = false
		clearRocks()
	end

	-- Başka bir pencere açılınca (tek pencere kuralı) oyun da duruyor
	root:GetPropertyChangedSignal("Visible"):Connect(function()
		if not root.Visible then
			stop()
		end
	end)

	close.MouseButton1Click:Connect(function()
		root.Visible = false
	end)

	return {
		Open = open,
		Close = function()
			root.Visible = false
		end,
		Destroy = function()
			stepConnection:Disconnect()
			root:Destroy()
		end,
	}
end

return AsteroidGame
