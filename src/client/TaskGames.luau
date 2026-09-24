--!strict
--[[
	Ek odalardaki Among Us görevlerinin penceresi (sunucu tarafı TaskService):

	  Fuel Engines — HOLD'a basılı tut, tank dolsun. Bırakınca durur, sıfırlanmaz
	                 (Among Us'taki gibi).
	  Fix Wiring   — soldaki kabloyu, sağdaki aynı renkle birleştir. Sağ sıra
	                 her açılışta karışık.
	  Swipe Card   — kart ray boyunca gidip geliyor; yeşil bölgedeyken SWIPE.
	                 Erken/geç basınca "Too fast / Too slow".

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
	Wiring = "Connect each wire to the same color.",
	Card = "Swipe when the card is in the green zone.",
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

	-- ─── Fix Wiring ──────────────────────────────────────────────────────

	local WIRE_COLORS = {
		Color3.fromRGB(222, 52, 52),
		Color3.fromRGB(60, 110, 240),
		Color3.fromRGB(245, 205, 50),
		Color3.fromRGB(240, 90, 200),
	}

	local function buildWiring()
		local rows = #WIRE_COLORS
		local gap = CONTENT_H / (rows + 1)
		local leftX, rightX = 50, CONTENT_W - 50

		-- Sağ sıra karışık; aynı sırada çıkarsa görev bir anlam taşımazdı
		local order = { 1, 2, 3, 4 }
		local rng = Random.new()
		repeat
			for i = #order, 2, -1 do
				local j = rng:NextInteger(1, i)
				order[i], order[j] = order[j], order[i]
			end
		until order[1] ~= 1 or order[2] ~= 2 or order[3] ~= 3

		local selected: number? = nil
		local done: { [number]: boolean } = {}
		local leftButtons: { TextButton } = {}

		-- Seçili kablonun kenarı beyaz ve kalın; seçim değişince eskisi geri döner
		local function highlight(b: TextButton, on: boolean)
			local stroke = b:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if on then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
				stroke.Thickness = if on then 3 else 2
				stroke.Transparency = if on then 0 else 0.3
			end
		end

		local function node(x: number, y: number, color: Color3): TextButton
			local b = Instance.new("TextButton")
			b.AutoButtonColor = false
			b.Text = ""
			b.AnchorPoint = Vector2.new(0.5, 0.5)
			b.Position = UDim2.fromOffset(x, y)
			b.Size = UDim2.fromOffset(46, 30)
			b.BackgroundColor3 = color
			b.BorderSizePixel = 0
			b.ZIndex = Z + 4
			b.Parent = content
			UiKit.Corner(b, 8)
			UiKit.Stroke(b, Color3.new(0, 0, 0), 2, 0.3)
			return b
		end

		local function wire(a: Vector2, b: Vector2, color: Color3)
			local delta = b - a
			local line = frame(content, color, Z + 3)
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
			line.Size = UDim2.fromOffset(delta.Magnitude, 9)
			line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
			UiKit.Corner(line, 4)
		end

		for i, color in WIRE_COLORS do
			local y = gap * i
			local b = node(leftX, y, color)
			leftButtons[i] = b
			b.MouseButton1Click:Connect(function()
				if done[i] or finished then
					return
				end
				if selected and leftButtons[selected] then
					highlight(leftButtons[selected], false)
				end
				selected = i
				highlight(b, true)
			end)
		end
		for slot, colorIndex in order do
			local y = gap * slot
			local b = node(rightX, y, WIRE_COLORS[colorIndex])
			b.MouseButton1Click:Connect(function()
				if finished or not selected or done[selected] then
					return
				end
				if selected ~= colorIndex then
					status.Text = "Wrong wire!"
					status.TextColor3 = UiKit.BAD
					SoundFX.Deny()
					return
				end
				done[colorIndex] = true
				highlight(leftButtons[colorIndex], false)
				wire(Vector2.new(leftX + 23, gap * colorIndex), Vector2.new(rightX - 23, y), WIRE_COLORS[colorIndex])
				selected = nil
				status.Text = ""
				local all = true
				for k = 1, rows do
					if not done[k] then
						all = false
					end
				end
				if all then
					complete("Wiring")
				end
			end)
		end
	end

	-- ─── Swipe Card ──────────────────────────────────────────────────────

	local function buildCard()
		local trackW = CONTENT_W - 60
		local track = frame(content, Color3.fromRGB(40, 46, 58), Z + 2)
		track.AnchorPoint = Vector2.new(0.5, 0.5)
		track.Position = UDim2.fromOffset(CONTENT_W / 2, CONTENT_H * 0.4)
		track.Size = UDim2.fromOffset(trackW, 70)
		UiKit.Corner(track, 12)

		-- Yeşil bölge: rayın ortasındaki %30
		local zone = frame(track, UiKit.GOOD, Z + 3)
		zone.AnchorPoint = Vector2.new(0.5, 0)
		zone.Position = UDim2.fromScale(0.5, 0)
		zone.Size = UDim2.fromScale(0.3, 1)
		zone.BackgroundTransparency = 0.6

		local card = frame(track, Color3.fromRGB(236, 241, 248), Z + 4)
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.fromScale(0, 0.5)
		card.Size = UDim2.fromOffset(46, 60)
		UiKit.Corner(card, 6)
		local stripe = frame(card, UiKit.CREW.CYAN, Z + 5)
		stripe.Position = UDim2.fromScale(0, 0.18)
		stripe.Size = UDim2.new(1, 0, 0, 8)

		local button = bigButton(content, "SWIPE", UiKit.CREW.BLUE)
		button.AnchorPoint = Vector2.new(0.5, 0.5)
		button.Position = UDim2.fromOffset(CONTENT_W / 2, CONTENT_H * 0.78)
		button.Size = UDim2.fromOffset(170, 56)

		local t = 0
		local x = 0
		local step = RunService.RenderStepped:Connect(function(dt)
			if finished then
				return
			end
			t += dt
			-- Gidip gelen hareket; hız hafifçe değişiyor ki ezber tutmasın
			x = (math.sin(t * 2.4) + 1) / 2
			card.Position = UDim2.fromScale(x, 0.5)
		end)
		table.insert(cleanup, function()
			step:Disconnect()
		end)

		button.MouseButton1Click:Connect(function()
			if finished then
				return
			end
			if math.abs(x - 0.5) <= 0.15 then
				status.Text = "Accepted. Thank you."
				status.TextColor3 = UiKit.GOOD
				complete("Card")
			else
				status.Text = if x < 0.5 then "Too slow. Try again." else "Too fast. Try again."
				status.TextColor3 = UiKit.BAD
				SoundFX.Deny()
			end
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

	local markers: { [string]: BillboardGui } = {}
	local function attachMarkers()
		local decor = workspace:FindFirstChild("Decor")
		if not decor then
			return
		end
		for _, part in decor:GetDescendants() do
			local taskId = part:GetAttribute("TaskId")
			if part:IsA("BasePart") and typeof(taskId) == "string" and not markers[taskId] then
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
				markers[taskId] = gui
			end
		end
	end

	local markerLoop = task.spawn(function()
		while true do
			attachMarkers()
			local now = os.time()
			for taskId, gui in markers do
				local readyAt = player:GetAttribute("TaskReady_" .. taskId)
				gui.Enabled = not (typeof(readyAt) == "number" and readyAt > now)
			end
			task.wait(1)
		end
	end)

	return {
		Open = open,
		Destroy = function()
			triggered:Disconnect()
			task.cancel(markerLoop)
			for _, gui in markers do
				gui:Destroy()
			end
			root:Destroy()
		end,
	}
end

return TaskGames
