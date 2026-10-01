--!strict
--[[
	Sunucu yeniden başlatma geri sayımı (2026-10-01): eski düz Roblox
	"Message" kutusunun yerine oyunun uzay temasında bant.

	Sunucu workspace niteliklerini yazıyor (AdminService "restart",
	SoftShutdown kapanışı):
	  RestartAt    — sayımın bittiği an (workspace:GetServerTimeNow saati)
	  RestartTitle — başlık ("UPDATE", "BUG FIX UPDATE" ...)
	Sayım sürerken: başlık, kocaman sayı (her saniye zıplıyor, son 3'te
	kırmızı), azalan çubuk, "ilerlemen kayıtlı" güvencesi. Sıfırdan sonra
	30 sn "REJOINING NOW". Nitelik yoksa ya da süre geçtiyse görünmüyor.
]]

local TweenService = game:GetService("TweenService")

local SoundFX = require(script.Parent.SoundFX)

local RestartScreen = {}

local Z = 200
local YELLOW = Color3.fromRGB(255, 222, 60)
local CYAN = Color3.fromRGB(90, 220, 255)
local RED = Color3.fromRGB(255, 70, 80)
local OUTLINE = Color3.fromRGB(10, 12, 24)

local function stroke(parent: Instance, thickness: number, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or OUTLINE
	s.Parent = parent
	return s
end

local function text(parent: Instance, value: string, size: number, color: Color3, pos: UDim2, height: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextSize = size
	l.TextColor3 = color
	l.Text = value
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = pos
	l.Size = UDim2.new(1, -40, 0, height)
	l.TextScaled = false
	l.ZIndex = Z + 3
	stroke(l, math.max(2, size * 0.08))
	l.Parent = parent
	return l
end

function RestartScreen.Start(_screen: Instance?)
	-- Kendi ekranı, her şeyin üstünde (başlık ekranı / menüler açıkken de görünsün)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RestartScreenGui"
	gui.DisplayOrder = 1000
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	local screen = gui
	local root = Instance.new("Frame")
	root.Name = "RestartScreen"
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, 90)
	root.Size = UDim2.fromOffset(560, 230)
	root.BackgroundColor3 = Color3.fromRGB(16, 18, 38)
	root.BorderSizePixel = 0
	root.Visible = false
	root.ZIndex = Z
	root.Parent = screen
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 22)
	corner.Parent = root
	local edge = stroke(root, 4, CYAN)
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(60, 50, 140), Color3.fromRGB(14, 16, 34))
	grad.Parent = root
	local scale = Instance.new("UIScale")
	scale.Parent = root

	-- Yıldız benekleri (uzay)
	local rng = Random.new(3)
	for _ = 1, 26 do
		local s = Instance.new("Frame")
		local r = rng:NextInteger(2, 4)
		s.Size = UDim2.fromOffset(r, r)
		s.Position = UDim2.fromScale(rng:NextNumber(0.03, 0.97), rng:NextNumber(0.05, 0.95))
		s.BackgroundColor3 = Color3.new(1, 1, 1)
		s.BackgroundTransparency = rng:NextNumber(0.2, 0.7)
		s.BorderSizePixel = 0
		s.ZIndex = Z + 1
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = s
		s.Parent = root
	end

	local title = text(root, "", 30, YELLOW, UDim2.new(0.5, 0, 0, 14), 34)
	local number = text(root, "", 76, Color3.new(1, 1, 1), UDim2.new(0.5, 0, 0, 50), 80)
	local numScale = Instance.new("UIScale")
	numScale.Parent = number
	local sub = text(root, "Your progress is saved  ·  you'll rejoin automatically", 18, Color3.fromRGB(215, 225, 250), UDim2.new(0.5, 0, 0, 138), 22)

	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0)
	bar.Position = UDim2.new(0.5, 0, 0, 180)
	bar.Size = UDim2.new(1, -60, 0, 16)
	bar.BackgroundColor3 = Color3.fromRGB(8, 10, 22)
	bar.BorderSizePixel = 0
	bar.ZIndex = Z + 2
	bar.Parent = root
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(1, 0)
	bc.Parent = bar
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = CYAN
	fill.BorderSizePixel = 0
	fill.ZIndex = Z + 3
	fill.Parent = bar
	bc:Clone().Parent = fill

	local shownLeft = -1
	local total = 10
	local function update()
		local at = workspace:GetAttribute("RestartAt")
		local now = workspace:GetServerTimeNow()
		if typeof(at) ~= "number" or now > at + 30 then
			if root.Visible then
				root.Visible = false
				shownLeft = -1
			end
			return
		end
		if not root.Visible then
			root.Visible = true
			total = math.max(1, math.ceil(at - now))
			scale.Scale = 0.4
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			SoundFX.Event("event", false)
		end
		local t = workspace:GetAttribute("RestartTitle")
		local left = math.max(0, math.ceil(at - now))
		if left > 0 then
			title.Text = string.format("🚀 %s INCOMING!", string.upper(if typeof(t) == "string" and t ~= "" then t else "UPDATE"))
			number.Text = tostring(left)
			sub.Text = "Your progress is saved  ·  you'll rejoin automatically"
			fill.Size = UDim2.fromScale(math.clamp((at - now) / total, 0, 1), 1)
			local urgent = left <= 3
			number.TextColor3 = if urgent then RED else Color3.new(1, 1, 1)
			fill.BackgroundColor3 = if urgent then RED else CYAN
			edge.Color = if urgent then RED else CYAN
		else
			title.Text = "🚀 REJOINING NOW..."
			number.Text = "GO!"
			number.TextColor3 = Color3.fromRGB(120, 255, 140)
			sub.Text = "Hang tight, the new version is loading"
			fill.Size = UDim2.fromScale(0, 1)
		end
		if left ~= shownLeft then
			shownLeft = left
			numScale.Scale = 1.35
			TweenService:Create(numScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			if left > 0 and left <= 5 then
				SoundFX.Event("tutorial", false)
			end
		end
	end

	workspace:GetAttributeChangedSignal("RestartAt"):Connect(update)
	task.spawn(function()
		while true do
			task.wait(0.1)
			update()
		end
	end)
	update()
end

return RestartScreen
