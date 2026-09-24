--!strict
--[[
	Ek odalardaki Among Us görevlerinin penceresi (sunucu tarafı TaskService):

	  Fuel Engines — HOLD'a basılı tut, tank dolsun. Bırakınca durur, sıfırlanmaz
	                 (Among Us'taki gibi).
	  Fix Wiring   — kabloyu tut, sürükle, sağdaki aynı renkli sokete bırak
	                 (Among Us'taki gibi metal pano, soket lambaları, kıvılcım sesi).
	  Swipe Card   — cüzdandan kartı çıkar, okuyucudan sürükleyerek geçir;
	                 hız okunuyor: Too fast / Too slow / Bad read / Accepted.

	Konsolun promptunu sunucu kuruyor ve başlangıç zamanını orada yazıyor;
	burası oyuncunun kendi tetiklemesini görüp pencereyi açıyor, bitince
	TaskDone gönderiyor. Ödülü sunucu veriyor.

	Konsolların üstünde sarı "!" var: görev hazırsa (bekleme bitmişse)
	görünüyor, oyuncu uzaktan hangi görevin yapılabileceğini görüyor.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local SoundFX = require(script.Parent.SoundFX)
local UiKit = require(script.Parent.UiKit)

local TaskGames = {}

export type Handle = {
	Open: (taskId: string) -> (),
	Destroy: () -> (),
}

local Z = 40
local W, H = 480, 380
local CONTENT_W, CONTENT_H = W - 32, H - 120
local ACCENT = UiKit.CREW.YELLOW

local HINTS: { [string]: string } = {
	Fuel = "Hold the button until the tank is full.",
	Wiring = "Drag each wire to the socket of the same color.",
	Card = "Take the card from the wallet and swipe it through the reader.",
}

local function frame(parent: Instance, color: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function label(parent: Instance, text: string, size: number, color: Color3, z: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextSize = size
	l.TextColor3 = color
	l.Text = text
	l.ZIndex = z
	l.Parent = parent
	return l
end

local function bigButton(parent: Instance, text: string, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 22
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextStrokeTransparency = 0.5
	b.Text = text
	b.ZIndex = Z + 4
	b.Parent = parent
	UiKit.Corner(b, 12)
	UiKit.Stroke(b, color:Lerp(Color3.new(0, 0, 0), 0.5), 2, 0)
	return b
end

-- "Basma" girdisi mi: fare, dokunma, gamepad A, boşluk
local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonA
		or input.KeyCode == Enum.KeyCode.Space
end

function TaskGames.Create(screen: ScreenGui): Handle
	local player = Players.LocalPlayer
	local doneRemote = Net.Get("TaskDone")

	local root = UiKit.Window(screen, "TaskGame", ACCENT)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(W, H)
	root.Visible = false
	root.ZIndex = Z

	local title = label(root, "", 21, Color3.new(1, 1, 1), Z + 2)
	title.Position = UDim2.fromOffset(18, 10)
	title.Size = UDim2.new(1, -70, 0, 24)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local hint = label(root, "", 12, UiKit.MUTED, Z + 2)
	hint.Font = Enum.Font.GothamMedium
	hint.Position = UDim2.fromOffset(18, 34)
	hint.Size = UDim2.new(1, -70, 0, 16)
	hint.TextXAlignment = Enum.TextXAlignment.Left

	local close = UiKit.CloseButton(root)
	close.ZIndex = Z + 6

	local content = frame(root, UiKit.SHELL_DEEP, Z + 1)
	content.Name = "Content"
	content.Position = UDim2.fromOffset(16, 58)
	content.Size = UDim2.fromOffset(CONTENT_W, CONTENT_H)
	UiKit.Corner(content, 12)

	local status = label(root, "", 15, UiKit.MUTED, Z + 2)
	status.Font = Enum.Font.GothamBold
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.new(0.5, 0, 1, -14)
	status.Size = UDim2.new(1, -32, 0, 22)

	-- Açık görevin temizliği: bağlantılar ve içerik
	local cleanup: { () -> () } = {}
	local currentTask: string? = nil
	local finished = false
	local openedAt = 0

	local function clearContent()
		for _, fn in cleanup do
			fn()
		end
		table.clear(cleanup)
		for _, c in content:GetChildren() do
			if not c:IsA("UICorner") then
				c:Destroy()
			end
		end
	end

	local function hide()
		root.Visible = false
		clearContent()
		currentTask = nil
	end
	close.MouseButton1Click:Connect(hide)
	root:GetPropertyChangedSignal("Visible"):Connect(function()
		if not root.Visible and currentTask then
			clearContent()
			currentTask = nil
		end
	end)

	local function complete(taskId: string)
		if finished then
			return
		end
		finished = true
		status.Text = "TASK COMPLETE!"
		status.TextColor3 = UiKit.GOOD
		SoundFX.Success()
		--[[
			Sunucu görevin en az minSeconds sürmesini istiyor (sahte istek
			koruması). Hızlı bir oyuncu kartı ilk saniyede geçirebiliyor;
			o zaman bildirim o süre dolana kadar bekliyor, yoksa "tamam"
			yazısını görüp ödül alamazdı.
		]]
		local def = Config.GetTask(taskId)
		local wait = if def then math.max(0, def.minSeconds + 0.25 - (os.clock() - openedAt)) else 0
		task.delay(wait, function()
			doneRemote:FireServer(taskId)
		end)
		task.delay(math.max(1.3, wait + 0.3), function()
			if currentTask == taskId then
				hide()
			end
		end)
	end

	-- ─── Fuel Engines ────────────────────────────────────────────────────

	local FILL_TIME = 3.3 -- sunucunun en kısa süresinden (3) biraz uzun

	local function buildFuel()
		local tank = frame(content, Color3.fromRGB(40, 46, 58), Z + 2)
		tank.AnchorPoint = Vector2.new(0.5, 0.5)
		tank.Position = UDim2.fromOffset(CONTENT_W * 0.32, CONTENT_H / 2)
		tank.Size = UDim2.fromOffset(110, CONTENT_H - 40)
		UiKit.Corner(tank, 14)
		UiKit.Stroke(tank, UiKit.CREW.ORANGE, 2.5, 0)
		local fill = frame(tank, UiKit.CREW.ORANGE, Z + 3)
		fill.AnchorPoint = Vector2.new(0, 1)
		fill.Position = UDim2.fromScale(0, 1)
		fill.Size = UDim2.fromScale(1, 0)
		UiKit.Corner(fill, 14)
		local pct = label(tank, "0%", 22, Color3.new(1, 1, 1), Z + 5)
		pct.Size = UDim2.fromScale(1, 1)
		pct.TextStrokeTransparency = 0.4

		local button = bigButton(content, "HOLD", UiKit.CREW.GREEN)
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.fromOffset(CONTENT_W * 0.72, CONTENT_H / 2)
		button.Size = UDim2.fromOffset(150, 80)

		local holding = false
		local progress = 0
		local began = button.InputBegan:Connect(function(input)
			if isPress(input) then
				holding = true
			end
		end)
		local ended = button.InputEnded:Connect(function(input)
			if isPress(input) then
				holding = false
			end
		end)
		local left = button.MouseLeave:Connect(function()
			holding = false
		end)
		local step = RunService.RenderStepped:Connect(function(dt)
			if not holding or finished then
				return
			end
			progress = math.min(1, progress + dt / FILL_TIME)
			fill.Size = UDim2.fromScale(1, progress)
			pct.Text = string.format("%d%%", math.floor(progress * 100))
			if progress >= 1 then
				complete("Fuel")
			end
		end)
		table.insert(cleanup, function()
			began:Disconnect()
			ended:Disconnect()
			left:Disconnect()
			step:Disconnect()
		end)
	end

	-- ─── Ortak: işaretçi ─────────────────────────────────────────────────

	--[[
		Sürükleme için işaretçinin tuvaldeki (content) yeri, ÖLÇEKSİZ birimle.
		InputObject.Position ekran pikseli (topbar hariç) ve HUD'un ScreenGui'si
		de topbar'ı hariç tutuyor, ikisi aynı düzlemde; arayüz ölçeğine
		(DeviceLayout) bölünce tuvalin içindeki konum çıkıyor.
	]]
	local function uiScale(): number
		local value = screen:GetAttribute("Scale")
		return if typeof(value) == "number" and value > 0 then value else 1
	end
	local function toContent(p: Vector3): Vector2
		local v = Vector2.new(p.X, p.Y)
		return (v - content.AbsolutePosition) / uiScale()
	end
	local function isPointerMove(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
	end
	local function isPointerPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	-- İki nokta arasında kalın çizgi (kablo)
	local function segment(parent: Instance, a: Vector2, b: Vector2, color: Color3, thick: number, z: number): Frame
		local delta = b - a
		local line = frame(parent, color, z)
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
		line.Size = UDim2.fromOffset(math.max(1, delta.Magnitude), thick)
		line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
		UiKit.Corner(line, math.floor(thick / 2))
		return line
	end
	local function moveSegment(line: Frame, a: Vector2, b: Vector2)
		local delta = b - a
		line.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
		line.Size = UDim2.fromOffset(math.max(1, delta.Magnitude), line.Size.Y.Offset)
		line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	end

	-- ─── Fix Wiring ──────────────────────────────────────────────────────

	--[[
		Among Us'taki gibi: metal pano, solda dört renkli kablo ucu, sağda
		karışık sırada dört soket ve yanlarında lamba. Kabloyu TUT, sürükle,
		aynı renkteki sokete BIRAK. Doğruysa kıvılcım sesiyle bağlanıyor ve
		soketin lambası yanıyor; yanlışsa kablo geri çekiliyor.

		Gamepad'de sürükleme yok: kablo ucuna A (seç), sokete A (bağla).
	]]
	local WIRE_COLORS = {
		Color3.fromRGB(222, 40, 40),
		Color3.fromRGB(40, 90, 235),
		Color3.fromRGB(245, 215, 40),
		Color3.fromRGB(225, 70, 200),
	}
	local PANEL = Color3.fromRGB(58, 64, 74)
	local PANEL_DARK = Color3.fromRGB(38, 42, 50)

	local function buildWiring()
		local rows = #WIRE_COLORS
		local top, bottom = 34, CONTENT_H - 20
		local gap = (bottom - top) / rows
		local leftX, rightX = 58, CONTENT_W - 58

		-- Pano: metal zemin, üst ve altta sarı-siyah şerit, köşelerde vida
		local board = frame(content, PANEL, Z + 2)
		board.Size = UDim2.fromScale(1, 1)
		UiKit.Corner(board, 12)
		for _, y in { 0, CONTENT_H - 12 } do
			local hz = frame(board, Color3.fromRGB(245, 200, 40), Z + 3)
			hz.Position = UDim2.fromOffset(12, y + 3)
			hz.Size = UDim2.new(1, -24, 0, 6)
			hz.ClipsDescendants = true
			for k = 0, 22 do
				local stripe = frame(hz, Color3.fromRGB(30, 30, 36), Z + 4)
				stripe.Position = UDim2.fromOffset(k * 19, 0)
				stripe.Size = UDim2.fromOffset(8, 6)
			end
		end
		for _, p in { Vector2.new(10, 20), Vector2.new(CONTENT_W - 18, 20), Vector2.new(10, CONTENT_H - 28), Vector2.new(CONTENT_W - 18, CONTENT_H - 28) } do
			local screw = frame(board, Color3.fromRGB(150, 158, 170), Z + 3)
			screw.Position = UDim2.fromOffset(p.X, p.Y)
			screw.Size = UDim2.fromOffset(8, 8)
			UiKit.Corner(screw, 4)
		end
		-- Kablo kanalları: iki yandaki koyu şeritler
		for _, x in { 0, CONTENT_W - 46 } do
			local duct = frame(board, PANEL_DARK, Z + 3)
			duct.Position = UDim2.fromOffset(x, top - 8)
			duct.Size = UDim2.fromOffset(46, bottom - top + 16)
		end

		-- Sağ sıra karışık; aynı sırada çıkarsa görev bir anlam taşımazdı
		local order = { 1, 2, 3, 4 }
		local rng = Random.new()
		repeat
			for i = #order, 2, -1 do
				local j = rng:NextInteger(1, i)
				order[i], order[j] = order[j], order[i]
			end
		until order[1] ~= 1 or order[2] ~= 2 or order[3] ~= 3

		local leftTip: { Vector2 } = {}
		local rightTip: { [number]: Vector2 } = {} -- renk -> soket ucu
		local lights: { [number]: Frame } = {}
		local done: { [number]: boolean } = {}
		local leftButtons: { TextButton } = {}

		for i, color in WIRE_COLORS do
			local y = top + gap * (i - 0.5)
			-- Kanaldan çıkan kablo gövdesi + bakır uç
			local body = frame(board, color, Z + 4)
			body.AnchorPoint = Vector2.new(0, 0.5)
			body.Position = UDim2.fromOffset(0, y)
			body.Size = UDim2.fromOffset(leftX - 6, 16)
			local tip = Instance.new("TextButton")
			tip.AutoButtonColor = false
			tip.Text = ""
			tip.AnchorPoint = Vector2.new(0.5, 0.5)
			tip.Position = UDim2.fromOffset(leftX, y)
			tip.Size = UDim2.fromOffset(26, 26)
			tip.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.15)
			tip.BorderSizePixel = 0
			tip.ZIndex = Z + 6
			tip.Parent = board
			UiKit.Corner(tip, 6)
			UiKit.Stroke(tip, Color3.fromRGB(200, 130, 60), 3, 0)
			leftButtons[i] = tip
			leftTip[i] = Vector2.new(leftX + 12, y)
		end
		for slotIndex, colorIndex in order do
			local y = top + gap * (slotIndex - 0.5)
			local color = WIRE_COLORS[colorIndex]
			local body = frame(board, color, Z + 4)
			body.AnchorPoint = Vector2.new(1, 0.5)
			body.Position = UDim2.new(1, 0, 0, y)
			body.Size = UDim2.fromOffset(CONTENT_W - rightX - 6, 16)
			local socket = frame(board, color:Lerp(Color3.new(0, 0, 0), 0.25), Z + 5)
			socket.AnchorPoint = Vector2.new(0.5, 0.5)
			socket.Position = UDim2.fromOffset(rightX, y)
			socket.Size = UDim2.fromOffset(26, 26)
			UiKit.Corner(socket, 6)
			UiKit.Stroke(socket, Color3.fromRGB(20, 20, 24), 3, 0)
			-- Soketin yanında lamba: bağlanınca yanıyor
			local lamp = frame(board, Color3.fromRGB(70, 70, 60), Z + 5)
			lamp.AnchorPoint = Vector2.new(0.5, 1)
			lamp.Position = UDim2.fromOffset(rightX + 26, y - 6)
			lamp.Size = UDim2.fromOffset(12, 12)
			UiKit.Corner(lamp, 6)
			lights[colorIndex] = lamp
			rightTip[colorIndex] = Vector2.new(rightX - 12, y)
		end

		local function nearestSocket(p: Vector2): number?
			for colorIndex, at in rightTip do
				if (p - at).Magnitude <= 30 then
					return colorIndex
				end
			end
			return nil
		end

		local function connect(i: number)
			done[i] = true
			segment(board, leftTip[i], rightTip[i], WIRE_COLORS[i], 12, Z + 5)
			lights[i].BackgroundColor3 = Color3.fromRGB(255, 230, 90)
			SoundFX.TaskSound("wireConnect")
			for k = 1, rows do
				if not done[k] then
					return
				end
			end
			complete("Wiring")
		end

		local function wrong()
			status.Text = "Wrong wire!"
			status.TextColor3 = UiKit.BAD
			SoundFX.Deny()
		end

		-- Sürükleme
		local dragging: number? = nil
		local dragLine: Frame? = nil
		local selected: number? = nil -- gamepad seçimi

		local function stopDrag()
			if dragLine then
				dragLine:Destroy()
				dragLine = nil
			end
			dragging = nil
		end

		for i, tip in leftButtons do
			tip.InputBegan:Connect(function(input)
				if finished or done[i] or not isPointerPress(input) then
					return
				end
				dragging = i
				selected = nil
				SoundFX.TaskSound("wireGrab")
				dragLine = segment(board, leftTip[i], toContent(input.Position), WIRE_COLORS[i], 12, Z + 7)
			end)
			-- Gamepad: A ile seç (sürüklemeden)
			tip.InputBegan:Connect(function(input)
				if finished or done[i] or input.KeyCode ~= Enum.KeyCode.ButtonA then
					return
				end
				selected = i
				SoundFX.TaskSound("wireGrab")
				status.Text = "Now pick the matching socket"
				status.TextColor3 = UiKit.MUTED
			end)
		end
		-- Gamepad için soketler de seçilebilir düğme
		for colorIndex, at in rightTip do
			local hit = Instance.new("TextButton")
			hit.Text = ""
			hit.BackgroundTransparency = 1
			hit.AnchorPoint = Vector2.new(0.5, 0.5)
			hit.Position = UDim2.fromOffset(at.X + 12, at.Y)
			hit.Size = UDim2.fromOffset(34, 34)
			hit.ZIndex = Z + 8
			hit.Parent = board
			hit.InputBegan:Connect(function(input)
				local s = selected
				if finished or input.KeyCode ~= Enum.KeyCode.ButtonA or not s or done[s] then
					return
				end
				selected = nil
				if s == colorIndex then
					status.Text = ""
					connect(s)
				else
					wrong()
				end
			end)
		end

		local moved = UserInputService.InputChanged:Connect(function(input)
			local i = dragging
			if i and dragLine and isPointerMove(input) then
				moveSegment(dragLine, leftTip[i], toContent(input.Position))
			end
		end)
		local released = UserInputService.InputEnded:Connect(function(input)
			local i = dragging
			if not i or not isPointerPress(input) then
				return
			end
			local target = nearestSocket(toContent(input.Position))
			stopDrag()
			if target == i then
				status.Text = ""
				connect(i)
			elseif target then
				wrong()
			end
		end)
		table.insert(cleanup, function()
			moved:Disconnect()
			released:Disconnect()
			stopDrag()
		end)
	end

	-- ─── Swipe Card ──────────────────────────────────────────────────────

	--[[
		Among Us'taki gibi: üstte yeşil yazılı ekran, ortada kart okuyucu
		yuvası, altta cüzdan. Cüzdana bas → kart yuvanın başına çıkar. Kartı
		TUT ve yuva boyunca sağa SÜRÜKLE. Hız okunuyor:
		  sona gelmeden bırakırsan  → BAD READ. TRY AGAIN.
		  SWIPE_MIN'den hızlı        → TOO FAST. TRY AGAIN.
		  SWIPE_MAX'tan yavaş        → TOO SLOW. TRY AGAIN.
		  aradaysa                    → ACCEPTED. THANK YOU.

		Gamepad'de sürükleme yok: karta A → doğru hızda kendisi kayıyor.
	]]
	local SWIPE_MIN, SWIPE_MAX = 0.5, 1.3
	local LCD_GREEN = Color3.fromRGB(110, 255, 140)

	local function buildCard()
		local body = frame(content, Color3.fromRGB(60, 66, 78), Z + 2)
		body.Size = UDim2.fromScale(1, 1)
		UiKit.Corner(body, 12)

		-- Ekran
		local lcd = frame(body, Color3.fromRGB(12, 28, 18), Z + 3)
		lcd.Position = UDim2.fromOffset(40, 14)
		lcd.Size = UDim2.new(1, -80, 0, 40)
		UiKit.Corner(lcd, 6)
		UiKit.Stroke(lcd, Color3.fromRGB(30, 34, 40), 3, 0)
		local lcdText = label(lcd, "PLEASE INSERT CARD", 18, LCD_GREEN, Z + 4)
		lcdText.Font = Enum.Font.Code
		lcdText.Size = UDim2.fromScale(1, 1)

		-- Okuyucu yuvası ve iki lamba
		local SLOT_Y, SLOT_X0, SLOT_X1 = 104, 50, CONTENT_W - 50
		local slot = frame(body, Color3.fromRGB(28, 30, 36), Z + 3)
		slot.AnchorPoint = Vector2.new(0, 0.5)
		slot.Position = UDim2.fromOffset(SLOT_X0 - 20, SLOT_Y)
		slot.Size = UDim2.fromOffset(SLOT_X1 - SLOT_X0 + 40, 70)
		UiKit.Corner(slot, 8)
		local groove = frame(slot, Color3.fromRGB(10, 10, 14), Z + 4)
		groove.AnchorPoint = Vector2.new(0, 0.5)
		groove.Position = UDim2.new(0, 8, 0.5, 0)
		groove.Size = UDim2.new(1, -16, 0, 6)
		local redLamp = frame(body, Color3.fromRGB(90, 30, 30), Z + 4)
		redLamp.Position = UDim2.fromOffset(CONTENT_W - 64, 142)
		redLamp.Size = UDim2.fromOffset(14, 14)
		UiKit.Corner(redLamp, 7)
		local greenLamp = frame(body, Color3.fromRGB(30, 80, 40), Z + 4)
		greenLamp.Position = UDim2.fromOffset(CONTENT_W - 44, 142)
		greenLamp.Size = UDim2.fromOffset(14, 14)
		UiKit.Corner(greenLamp, 7)

		-- Cüzdan (altta) ve kart
		local wallet = Instance.new("TextButton")
		wallet.AutoButtonColor = true
		wallet.Text = ""
		wallet.AnchorPoint = Vector2.new(0.5, 1)
		wallet.Position = UDim2.new(0.5, 0, 1, -8)
		wallet.Size = UDim2.fromOffset(170, 62)
		wallet.BackgroundColor3 = Color3.fromRGB(120, 78, 44)
		wallet.BorderSizePixel = 0
		wallet.ZIndex = Z + 5
		wallet.Parent = body
		UiKit.Corner(wallet, 10)
		UiKit.Stroke(wallet, Color3.fromRGB(70, 44, 24), 3, 0)
		local stitch = frame(wallet, Color3.fromRGB(220, 190, 140), Z + 6)
		stitch.Position = UDim2.new(0, 10, 0, 10)
		stitch.Size = UDim2.new(1, -20, 0, 2)
		local walletHint = label(wallet, "TAP WALLET", 12, Color3.fromRGB(240, 220, 180), Z + 6)
		walletHint.Size = UDim2.fromScale(1, 1)

		local CARD_W, CARD_H = 84, 54
		local card = Instance.new("TextButton")
		card.AutoButtonColor = false
		card.Text = ""
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Size = UDim2.fromOffset(CARD_W, CARD_H)
		card.BackgroundColor3 = Color3.fromRGB(236, 241, 248)
		card.BorderSizePixel = 0
		card.ZIndex = Z + 6
		card.Parent = body
		UiKit.Corner(card, 6)
		local band = frame(card, UiKit.CREW.CYAN, Z + 7)
		band.Position = UDim2.fromOffset(0, 8)
		band.Size = UDim2.new(1, 0, 0, 10)
		local photo = frame(card, UiKit.CREW.RED, Z + 7)
		photo.Position = UDim2.fromOffset(8, 24)
		photo.Size = UDim2.fromOffset(18, 22)
		UiKit.Corner(photo, 6)
		local lineA = frame(card, Color3.fromRGB(150, 160, 175), Z + 7)
		lineA.Position = UDim2.fromOffset(32, 28)
		lineA.Size = UDim2.fromOffset(42, 4)
		local lineB = frame(card, Color3.fromRGB(150, 160, 175), Z + 7)
		lineB.Position = UDim2.fromOffset(32, 38)
		lineB.Size = UDim2.fromOffset(30, 4)

		local walletPos = Vector2.new(CONTENT_W / 2, CONTENT_H - 44)
		local startPos = Vector2.new(SLOT_X0 + CARD_W / 2 - 20, SLOT_Y)
		local endX = SLOT_X1 - CARD_W / 2 + 20
		card.Position = UDim2.fromOffset(walletPos.X, walletPos.Y)
		card.Visible = false

		local inserted = false
		local swiping = false
		local swipeStart = 0
		local grabOffset = 0

		local function setLamps(ok: boolean?)
			redLamp.BackgroundColor3 = if ok == false then Color3.fromRGB(255, 60, 60) else Color3.fromRGB(90, 30, 30)
			greenLamp.BackgroundColor3 = if ok == true then Color3.fromRGB(90, 255, 120) else Color3.fromRGB(30, 80, 40)
		end

		local function resetCard(message: string)
			swiping = false
			lcdText.Text = message
			card.Position = UDim2.fromOffset(startPos.X, startPos.Y)
		end

		local function judge(elapsed: number)
			if elapsed < SWIPE_MIN then
				setLamps(false)
				SoundFX.Deny()
				resetCard("TOO FAST. TRY AGAIN.")
			elseif elapsed > SWIPE_MAX then
				setLamps(false)
				SoundFX.Deny()
				resetCard("TOO SLOW. TRY AGAIN.")
			else
				swiping = false
				setLamps(true)
				lcdText.Text = "ACCEPTED. THANK YOU."
				SoundFX.TaskSound("cardAccept")
				complete("Card")
			end
		end

		wallet.Activated:Connect(function()
			if inserted or finished then
				return
			end
			inserted = true
			card.Visible = true
			walletHint.Text = ""
			SoundFX.TaskSound("wireGrab")
			TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = UDim2.fromOffset(startPos.X, startPos.Y) }):Play()
			lcdText.Text = "PLEASE SWIPE CARD"
		end)

		card.InputBegan:Connect(function(input)
			if finished or not inserted or swiping then
				return
			end
			if isPointerPress(input) then
				swiping = true
				swipeStart = os.clock()
				grabOffset = toContent(input.Position).X - card.Position.X.Offset
				setLamps(nil)
				SoundFX.TaskSound("cardSwipe")
			elseif input.KeyCode == Enum.KeyCode.ButtonA then
				-- Gamepad: kart doğru hızda kendisi kayıyor
				swiping = true
				SoundFX.TaskSound("cardSwipe")
				local t = TweenService:Create(card, TweenInfo.new(0.9, Enum.EasingStyle.Linear),
					{ Position = UDim2.fromOffset(endX, startPos.Y) })
				t:Play()
				t.Completed:Once(function()
					judge(0.9)
				end)
			end
		end)

		local moved = UserInputService.InputChanged:Connect(function(input)
			if not swiping or not isPointerMove(input) then
				return
			end
			local x = math.clamp(toContent(input.Position).X - grabOffset, startPos.X, endX)
			card.Position = UDim2.fromOffset(x, startPos.Y)
			if x >= endX - 1 then
				judge(os.clock() - swipeStart)
			end
		end)
		local released = UserInputService.InputEnded:Connect(function(input)
			if not swiping or not isPointerPress(input) then
				return
			end
			-- Sona varmadan bırakıldı
			setLamps(false)
			SoundFX.Deny()
			resetCard("BAD READ. TRY AGAIN.")
		end)
		table.insert(cleanup, function()
			moved:Disconnect()
			released:Disconnect()
		end)
	end

	local BUILD: { [string]: () -> () } = {
		Fuel = buildFuel,
		Wiring = buildWiring,
		Card = buildCard,
	}

	local function open(taskId: string)
		local def = Config.GetTask(taskId)
		local build = BUILD[taskId]
		if not (def and build) then
			return
		end
		clearContent()
		currentTask = taskId
		finished = false
		openedAt = os.clock()
		title.Text = string.upper(def.name)
		hint.Text = HINTS[taskId] or ""
		status.TextColor3 = UiKit.MUTED
		local readyAt = player:GetAttribute("TaskReady_" .. taskId)
		if typeof(readyAt) == "number" and readyAt > os.time() then
			local left = readyAt - os.time()
			status.Text = string.format("No reward for %d:%02d - you can still practice", left // 60, left % 60)
		else
			status.Text = ""
		end
		build()
		root.Visible = true
	end

	local triggered = ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who ~= player or prompt.Name ~= "TaskPrompt" then
			return
		end
		local taskId = prompt:GetAttribute("TaskId")
		if typeof(taskId) == "string" then
			open(taskId)
		end
	end)

	-- ─── Sarı "!" işaretleri ─────────────────────────────────────────────

	--[[
		Görev konsollarının üstünde sarı "!" (Among Us'taki görev işareti):
		görev hazırsa (bekleme bitmişse) görünüyor. Oda görevleri "TaskId"
		niteliğinden, Weapons'taki asteroit görevi AsteroidConsole'dan bulunuyor;
		hazır olma zamanları oyuncu niteliklerinde (TaskReady_<id>, AsteroidReadyAt).
	]]
	type Marker = { gui: BillboardGui, readyAttr: string }
	local markers: { [string]: Marker } = {}

	local function addMarker(key: string, part: BasePart, readyAttr: string)
		if markers[key] then
			return
		end
		local gui = Instance.new("BillboardGui")
		gui.Name = "TaskMarker"
		gui.Size = UDim2.fromOffset(40, 50)
		gui.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 3, 0)
		gui.MaxDistance = 140
		gui.Adornee = part
		local mark = label(gui, "!", 44, ACCENT, 1)
		mark.Font = Enum.Font.FredokaOne
		mark.Size = UDim2.fromScale(1, 1)
		mark.TextStrokeTransparency = 0.2
		gui.Parent = player:WaitForChild("PlayerGui")
		markers[key] = { gui = gui, readyAttr = readyAttr }
	end

	local function attachMarkers()
		local decor = workspace:FindFirstChild("Decor")
		if not decor then
			return
		end
		for _, part in decor:GetDescendants() do
			if not part:IsA("BasePart") then
				continue
			end
			local taskId = part:GetAttribute("TaskId")
			if typeof(taskId) == "string" then
				addMarker(taskId, part, "TaskReady_" .. taskId)
			elseif part.Name == "AsteroidConsole" then
				addMarker("Asteroids", part, "AsteroidReadyAt")
			end
		end
	end

	local markerLoop = task.spawn(function()
		while true do
			attachMarkers()
			local now = os.time()
			for _, m in markers do
				local readyAt = player:GetAttribute(m.readyAttr)
				m.gui.Enabled = not (typeof(readyAt) == "number" and readyAt > now)
			end
			task.wait(1)
		end
	end)

	return {
		Open = open,
		Destroy = function()
			triggered:Disconnect()
			task.cancel(markerLoop)
			for _, m in markers do
				m.gui:Destroy()
			end
			root:Destroy()
		end,
	}
end

return TaskGames
