--!strict
--[[
	Şans çarkı penceresi. Salondaki çarkın promptuna ("SpinPrompt") basınca
	açılıyor; Yusuf'un attığı referans gibi: ortada renkli dilimli çark,
	tepede işaretçi, altta büyük SPIN düğmesi, "+1 spin in 05:59" geri
	sayımı ve Robux'la ekstra çevirme.

	Akış: SPIN → "SpinRequest" (sunucu SpinService.TrySpin) → sunucu ödülü
	seçip "SpinResult" (rewardId, ad, süre, dilim, sapma) gönderiyor → çark
	o dilimde yavaşlayarak duruyor → ödül kartı. Ödülü sunucu tam o anda
	veriyor. Robux'la alınan çevirmede de aynı sonuç geliyor; pencere
	kapalıysa açılıyor.

	Çizim: dilimler UI'da kama olmadığı için dönük ince çubuklardan
	(merkezden dışa), daire kırpması CanvasGroup + UICorner. Dönüş
	CanvasGroup'un Rotation'ı (saat yönü).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local SoundFX = require(script.Parent.SoundFX)
local UiKit = require(script.Parent.UiKit)

local SpinPanel = {}

local player = Players.LocalPlayer

local ACCENT = Color3.fromRGB(255, 196, 40)
local Z = 50
local R = 165              -- çark yarıçapı (piksel)
local BAR_STEP = 3         -- dilimi dolduran çubuklar arası açı (derece)

export type Panel = {
	Open: () -> (),
	Destroy: () -> (),
}

local function text(parent: Instance, value: string, font: Enum.Font, size: number, color: Color3, z: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextSize = size
	l.TextColor3 = color
	l.Text = value
	l.ZIndex = z
	l.Parent = parent
	return l
end

local function outline(obj: Instance, thickness: number, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness
	s.Color = color or Color3.fromRGB(20, 16, 30)
	s.Parent = obj
end

--[[ Merkezden `angle` (tepeden saat yönünde, derece) yönüne uzanan çubuk. ]]
local function ray(parent: Instance, angle: number, length: number, thickness: number, color: Color3, z: number, from: number?)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(length * 2, thickness)
	holder.Rotation = angle - 90
	holder.BackgroundTransparency = 1
	holder.ZIndex = z
	holder.Parent = parent
	local bar = Instance.new("Frame")
	local start = from or 0
	bar.Position = UDim2.new(0.5, start, 0, 0)
	bar.Size = UDim2.new(0.5, -start, 1, 0)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.ZIndex = z
	bar.Parent = holder
end

function SpinPanel.Create(screen: ScreenGui): Panel
	local slices = Config.SpinWheelSlices
	local n = #slices
	local width = 360 / n

	local root = UiKit.Window(screen, "SpinPanel", ACCENT)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(470, 590)
	root.Visible = false
	root.ZIndex = Z

	local title = text(root, "SPIN THE WHEEL", Enum.Font.FredokaOne, 34, ACCENT, Z + 3)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, 8)
	title.Size = UDim2.new(1, -80, 0, 44)
	outline(title, 3.5)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 150, 30))
	grad.Rotation = 90
	grad.Parent = title

	local close = UiKit.CloseButton(root)
	close.ZIndex = Z + 5

	-- ─── Çark ────────────────────────────────────────────────────────────
	local stage = Instance.new("Frame")
	stage.AnchorPoint = Vector2.new(0.5, 0)
	stage.Position = UDim2.new(0.5, 0, 0, 62)
	stage.Size = UDim2.fromOffset(R * 2 + 40, R * 2 + 40)
	stage.BackgroundTransparency = 1
	stage.ZIndex = Z + 1
	stage.Parent = root

	-- Altın çember ve ampuller
	local rim = Instance.new("Frame")
	rim.AnchorPoint = Vector2.new(0.5, 0.5)
	rim.Position = UDim2.fromScale(0.5, 0.5)
	rim.Size = UDim2.fromOffset(R * 2 + 28, R * 2 + 28)
	rim.BackgroundColor3 = Color3.fromRGB(255, 190, 40)
	rim.ZIndex = Z + 1
	rim.Parent = stage
	UiKit.Corner(rim, R + 14)
	outline(rim, 4)
	local rimGrad = Instance.new("UIGradient")
	rimGrad.Color = ColorSequence.new(Color3.fromRGB(255, 236, 140), Color3.fromRGB(214, 120, 20))
	rimGrad.Rotation = 90
	rimGrad.Parent = rim
	local bulbs: { Frame } = {}
	for i = 1, 24 do
		local a = math.rad((i - 1) * 15)
		local b = Instance.new("Frame")
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.new(0.5, math.sin(a) * (R + 7), 0.5, -math.cos(a) * (R + 7))
		b.Size = UDim2.fromOffset(8, 8)
		b.BackgroundColor3 = Color3.new(1, 1, 1)
		b.BorderSizePixel = 0
		b.ZIndex = Z + 2
		b.Parent = stage
		UiKit.Corner(b, 4)
		table.insert(bulbs, b)
	end

	local disc = Instance.new("CanvasGroup")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromOffset(R * 2, R * 2)
	disc.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	disc.ZIndex = Z + 3
	disc.Parent = stage
	UiKit.Corner(disc, R)

	for i, id in slices do
		local look = Config.SpinSliceLook[id]
		local color = if look then look.color else Color3.fromRGB(120, 120, 140)
		local a0 = (i - 1) * width
		--[[ Dilimin içi: dilim içinde BAR_STEP arayla çubuklar; her çubuk
		     halkalara bölünmüş, içteki halkalar ince (komşu dilime taşmasın).
		     Dış halka biraz koyu: iki tonlu görünüş. ]]
		local dark = color:Lerp(Color3.new(0, 0, 0), 0.2)
		local rings = { { 0, R * 0.35, color }, { R * 0.35, R * 0.7, color }, { R * 0.7, R * 0.8, color }, { R * 0.8, R + 4, dark } }
		local a = a0 + BAR_STEP / 2
		while a < a0 + width do
			for _, ring in rings do
				local outer = ring[2] :: number
				local thick = math.ceil(outer * math.rad(BAR_STEP) * 1.2) + 1
				ray(disc, a, outer, thick, ring[3] :: Color3, Z + 3, ring[1] :: number)
			end
			a += BAR_STEP
		end
		-- Dilim yazısı ve ikonu (merkezden dışa doğru okunuyor)
		local mid = math.rad(a0 + width / 2)
		local label = text(disc, if look then look.text else id, Enum.Font.FredokaOne, 15, Color3.new(1, 1, 1), Z + 5)
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.new(0.5, math.sin(mid) * R * 0.56, 0.5, -math.cos(mid) * R * 0.56)
		label.Size = UDim2.fromOffset(96, 20)
		label.Rotation = a0 + width / 2 - 90
		outline(label, 2)
		local icon = text(disc, if look then look.icon else "?", Enum.Font.GothamBlack, 22, Color3.new(1, 1, 1), Z + 5)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.new(0.5, math.sin(mid) * R * 0.86, 0.5, -math.cos(mid) * R * 0.86)
		icon.Size = UDim2.fromOffset(30, 30)
		icon.Rotation = a0 + width / 2
	end
	-- Dilim ayırıcıları
	for i = 1, n do
		ray(disc, (i - 1) * width, R + 4, 3, Color3.fromRGB(255, 244, 210), Z + 4)
	end

	-- Göbek
	local hub = Instance.new("Frame")
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(62, 62)
	hub.BackgroundColor3 = Color3.fromRGB(255, 206, 60)
	hub.ZIndex = Z + 6
	hub.Parent = stage
	UiKit.Corner(hub, 31)
	outline(hub, 4)
	local hubText = text(hub, "SPIN", Enum.Font.FredokaOne, 17, Color3.new(1, 1, 1), Z + 7)
	hubText.Size = UDim2.fromScale(1, 1)
	outline(hubText, 2)

	-- İşaretçi (tepede, aşağı bakan)
	local pointer = text(stage, "▼", Enum.Font.GothamBlack, 46, Color3.fromRGB(235, 50, 60), Z + 8)
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Position = UDim2.new(0.5, 0, 0, 10)
	pointer.Size = UDim2.fromOffset(50, 50)
	outline(pointer, 3)

	-- ─── Alt kısım ───────────────────────────────────────────────────────
	local spinHolder, spinButton = UiKit.Raised(root, "Spin", UiKit.CREW.GREEN:Lerp(UiKit.GOOD, 0.3), UDim2.fromOffset(200, 58), 14)
	spinHolder.AnchorPoint = Vector2.new(0.5, 1)
	spinHolder.Position = UDim2.new(0.5, 0, 1, -44)
	spinHolder.ZIndex = Z + 3
	local spinLabel = text(spinButton, "SPIN!", Enum.Font.FredokaOne, 30, Color3.new(1, 1, 1), Z + 8)
	spinLabel.Size = UDim2.fromScale(1, 1)
	outline(spinLabel, 2.5)

	local buyHolder, buyButton = UiKit.Raised(root, "BuySpin", Color3.fromRGB(40, 150, 230), UDim2.fromOffset(110, 46), 12)
	buyHolder.AnchorPoint = Vector2.new(1, 1)
	buyHolder.Position = UDim2.new(1, -18, 1, -50)
	buyHolder.ZIndex = Z + 3
	local buyLabel = text(buyButton, "+1 SPIN\nR$", Enum.Font.FredokaOne, 15, Color3.new(1, 1, 1), Z + 8)
	buyLabel.Size = UDim2.fromScale(1, 1)
	outline(buyLabel, 2)

	local timer = text(root, "", Enum.Font.GothamBlack, 15, Color3.new(1, 1, 1), Z + 3)
	timer.AnchorPoint = Vector2.new(0.5, 1)
	timer.Position = UDim2.new(0.5, 0, 1, -14)
	timer.Size = UDim2.new(1, -40, 0, 22)
	outline(timer, 2)

	-- Ödül kartı
	local prize = Instance.new("Frame")
	prize.AnchorPoint = Vector2.new(0.5, 0.5)
	prize.Position = UDim2.new(0.5, 0, 0, 62 + R + 20)
	prize.Size = UDim2.fromOffset(300, 120)
	prize.BackgroundColor3 = Color3.fromRGB(28, 22, 50)
	prize.Visible = false
	prize.ZIndex = Z + 20
	prize.Parent = root
	UiKit.Corner(prize, 18)
	UiKit.Stroke(prize, ACCENT, 4, 0)
	local prizeTop = text(prize, "YOU WON", Enum.Font.FredokaOne, 20, ACCENT, Z + 21)
	prizeTop.Position = UDim2.fromOffset(0, 8)
	prizeTop.Size = UDim2.new(1, 0, 0, 24)
	outline(prizeTop, 2)
	local prizeName = text(prize, "", Enum.Font.FredokaOne, 30, Color3.new(1, 1, 1), Z + 21)
	prizeName.Position = UDim2.fromOffset(10, 36)
	prizeName.Size = UDim2.new(1, -20, 0, 70)
	prizeName.TextWrapped = true
	outline(prizeName, 3)

	-- ─── Durum ───────────────────────────────────────────────────────────
	local requestRemote = Net.Get("SpinRequest")
	local resultRemote = Net.Get("SpinResult")
	local spinning = false
	local angle = 0          -- çarkın dönüşü (derece, saat yönü)
	local idle = true

	local function readyIn(): number
		local at = player:GetAttribute("SpinReadyAt")
		if typeof(at) ~= "number" then
			return 0
		end
		return math.max(0, at - workspace:GetServerTimeNow())
	end

	local function clockText(seconds: number): string
		local t = math.ceil(seconds)
		return string.format("%02d:%02d:%02d", t // 3600, (t % 3600) // 60, t % 60)
	end

	local function paintButton()
		local left = readyIn()
		local ready = left <= 0 and not spinning
		spinButton.Active = ready
		local base = if ready then UiKit.CREW.GREEN:Lerp(UiKit.GOOD, 0.3) else UiKit.DIM
		spinButton.BackgroundColor3 = base
		local g = spinButton:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = ColorSequence.new(base:Lerp(Color3.new(1, 1, 1), 0.22), base:Lerp(Color3.new(0, 0, 0), 0.18))
		end
		spinLabel.Text = if spinning then "SPINNING..." elseif ready then "FREE SPIN!" else "SPIN!"
		timer.Text = if left <= 0 then "Free spin ready!" else "+1 free spin in " .. clockText(left)
	end

	local function showPrize(rewardId: string, name: string)
		local look = Config.SpinSliceLook[rewardId]
		prizeName.Text = (if look then look.icon .. " " else "") .. name
		prize.Visible = true
		prize.Size = UDim2.fromOffset(150, 60)
		TweenService:Create(prize, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(300, 120) }):Play()
		SoundFX.Success()
		task.delay(2.6, function()
			prize.Visible = false
		end)
	end

	--[[ Sunucunun seçtiği dilime, en az 5 tur dönüp yavaşlayarak. ]]
	local function spinTo(rewardId: string, name: string, duration: number, index: number, jitter: number)
		spinning = true
		idle = false
		prize.Visible = false
		paintButton()
		local center = (index - 0.5) * width + jitter * width
		local target = (-center) % 360
		local from = angle
		local base = from + 360 * 5
		local to = base + ((target - base) % 360)
		local started = os.clock()
		local lastSlice = -1
		local conn: RBXScriptConnection? = nil
		conn = RunService.RenderStepped:Connect(function()
			local u = math.clamp((os.clock() - started) / math.max(0.5, duration), 0, 1)
			local v = 1 - u
			angle = from + (to - from) * (1 - v * v * v)
			disc.Rotation = angle
			-- İşaretçi dilim sınırından geçerken sekiyor
			local under = math.floor(((-angle) % 360) / width)
			if under ~= lastSlice then
				lastSlice = under
				pointer.Rotation = -18
				TweenService:Create(pointer, TweenInfo.new(0.12), { Rotation = 0 }):Play()
			end
			if u >= 1 and conn then
				conn:Disconnect()
				spinning = false
				paintButton()
				showPrize(rewardId, name)
				task.delay(3, function()
					if not spinning then
						idle = true
					end
				end)
			end
		end)
	end

	local conns: { RBXScriptConnection } = {}
	table.insert(conns, resultRemote.OnClientEvent:Connect(function(rewardId, name, duration, index, jitter)
		if typeof(rewardId) ~= "string" or typeof(index) ~= "number" then
			return
		end
		root.Visible = true
		spinTo(rewardId, tostring(name), if typeof(duration) == "number" then duration else Config.SpinDuration, index,
			if typeof(jitter) == "number" then jitter else 0)
	end))

	spinButton.MouseButton1Click:Connect(function()
		if spinning or readyIn() > 0 then
			return
		end
		requestRemote:FireServer()
	end)
	buyButton.MouseButton1Click:Connect(function()
		local product = Config.Products.ExtraSpin
		if product and product.id > 0 and not spinning then
			MarketplaceService:PromptProductPurchase(player, product.id)
		end
	end)
	close.Activated:Connect(function()
		root.Visible = false
	end)

	table.insert(conns, ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt.Name == "SpinPrompt" then
			root.Visible = true
			paintButton()
		end
	end))

	-- Boştayken ağır dönüş, ampuller sırayla yanıyor, geri sayım saniyede bir
	local clock = 0
	local lastPaint = 0
	table.insert(conns, RunService.RenderStepped:Connect(function(dt)
		if not root.Visible then
			return
		end
		clock += dt
		if idle then
			angle += dt * 12
			disc.Rotation = angle
		end
		for i, b in bulbs do
			local on = (math.floor(clock * (if spinning then 14 else 3)) + i) % 2 == 0
			b.BackgroundColor3 = if on then Color3.fromRGB(255, 255, 220) else Color3.fromRGB(255, 120, 40)
		end
		if clock - lastPaint > 0.5 then
			lastPaint = clock
			paintButton()
		end
	end))

	return {
		Open = function()
			root.Visible = true
			paintButton()
		end,
		Destroy = function()
			for _, c in conns do
				c:Disconnect()
			end
			root:Destroy()
		end,
	}
end

return SpinPanel
