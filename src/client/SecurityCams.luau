--!strict
--[[
	Security odasındaki kamera ekranı (Among Us'taki gibi).

	Konsoldaki "SecurityPrompt" tetiklenince oyuncunun kamerası haritadaki
	güvenlik kameralarının (tools/map/kit.luau K.securityCamera: gövdesinde
	"CamName"/"CamOrder" niteliği olan parçalar) gözüne geçiyor. Ekranda
	kamera kaydı görünümü: tarama çizgileri, kenar kararması, yeşilimsi
	renk, yanıp sönen REC, kameranın adı ve saat. Oklarla (Q/E, ←/→,
	gamepad LB/RB) kameralar arasında geçiliyor, X / ESC / B ile çıkılıyor.

	Hepsi istemcide: kamera görüntüsü kimseye bir şey vermiyor, sunucunun
	bilmesi gerekmiyor. İzlerken karakter yürümüyor ve HUD gizli.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UiKit = require(script.Parent.UiKit)

local SecurityCams = {}

local GREEN = Color3.fromRGB(120, 255, 150)
local RED = Color3.fromRGB(255, 60, 60)
local WHITE = Color3.new(1, 1, 1)

type Cam = { name: string, order: number, part: BasePart }

local function findCameras(): { Cam }
	local out: { Cam } = {}
	local decor = workspace:FindFirstChild("Decor")
	if not decor then
		return out
	end
	for _, d in decor:GetDescendants() do
		if d:IsA("BasePart") then
			local name = d:GetAttribute("CamName")
			if typeof(name) == "string" then
				local order = d:GetAttribute("CamOrder")
				table.insert(out, { name = name, order = if typeof(order) == "number" then order else 99, part = d })
			end
		end
	end
	table.sort(out, function(a, b)
		return a.order < b.order
	end)
	return out
end

local function corner(parent: Instance, r: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = r
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: number, color: Color3, z: number): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextSize = size
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.3
	t.Text = text
	t.ZIndex = z
	t.Parent = parent
	return t
end

function SecurityCams.Start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local open = false
	local cams: { Cam } = {}
	local index = 1
	local session: { cleanup: () -> (), show: (number) -> () }? = nil

	local function viewCFrame(cam: Cam): CFrame
		-- Lensin önünden, gövdenin baktığı yöne
		return cam.part.CFrame * CFrame.new(0, -0.2, -2.6)
	end

	local function close()
		if not open then
			return
		end
		open = false
		if session then
			session.cleanup()
			session = nil
		end
	end

	local function openView()
		if open then
			return
		end
		cams = findCameras()
		if #cams == 0 then
			return
		end
		open = true
		index = 1

		local camera = workspace.CurrentCamera
		local oldType = camera.CameraType
		local oldFov = camera.FieldOfView
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = 78

		-- Kayıt görünümü: soluk, yeşilimsi, biraz kontrastlı
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "SecurityGrade"
		grade.Saturation = -0.45
		grade.Contrast = 0.12
		grade.TintColor = Color3.fromRGB(215, 255, 225)
		grade.Parent = Lighting

		-- HUD gizli, karakter duruyor
		local hud = playerGui:FindFirstChild("SusStealersHud")
		local hudWasEnabled = hud and hud:IsA("ScreenGui") and hud.Enabled
		if hud and hud:IsA("ScreenGui") then
			hud.Enabled = false
		end
		local controls: any = nil
		pcall(function()
			local pm = player:FindFirstChild("PlayerScripts") and (player :: any).PlayerScripts:FindFirstChild("PlayerModule")
			if pm then
				controls = (require(pm) :: any):GetControls()
				controls:Disable()
			end
		end)

		-- ── Arayüz ─────────────────────────────────────────────────────────
		local gui = Instance.new("ScreenGui")
		gui.Name = "SecurityCams"
		gui.IgnoreGuiInset = true
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 150
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = playerGui

		-- Kenar kararması: dört kenarda içe doğru solan bant
		for _, spec in { { 0, 1, 90 }, { 1, 1, -90 }, { 0, 0, 0 }, { 1, 0, 180 } } do
			local band = Instance.new("Frame")
			band.BorderSizePixel = 0
			band.BackgroundColor3 = Color3.new(0, 0, 0)
			band.ZIndex = 2
			if spec[2] == 1 then
				band.Size = UDim2.new(1, 0, 0.22, 0)
				band.Position = UDim2.fromScale(0, if spec[1] == 0 then 0 else 0.78)
			else
				band.Size = UDim2.new(0.18, 0, 1, 0)
				band.Position = UDim2.fromScale(if spec[1] == 0 then 0 else 0.82, 0)
			end
			local g = Instance.new("UIGradient")
			g.Rotation = spec[3]
			g.Transparency = NumberSequence.new(0.25, 1)
			g.Parent = band
			band.Parent = gui
		end

		-- Tarama çizgileri: yavaşça aşağı kayıyor
		local lines = Instance.new("Frame")
		lines.Name = "Scanlines"
		lines.Size = UDim2.fromScale(1, 1)
		lines.BackgroundTransparency = 1
		lines.ClipsDescendants = true
		lines.ZIndex = 3
		lines.Parent = gui
		local LINES = 48
		for i = 0, LINES * 2 - 1 do
			local l = Instance.new("Frame")
			l.BorderSizePixel = 0
			l.BackgroundColor3 = Color3.new(0, 0, 0)
			l.BackgroundTransparency = 0.86
			l.Size = UDim2.new(1, 0, 0, 2)
			l.Position = UDim2.fromScale(0, i / LINES)
			l.ZIndex = 3
			l.Parent = lines
		end

		-- Kamera değişiminde kısa gri parazit
		local static = Instance.new("Frame")
		static.Size = UDim2.fromScale(1, 1)
		static.BackgroundColor3 = Color3.fromRGB(120, 130, 125)
		static.BackgroundTransparency = 1
		static.BorderSizePixel = 0
		static.ZIndex = 4
		static.Parent = gui

		-- Üst sol: REC ve kamera adı
		local rec = Instance.new("Frame")
		rec.Position = UDim2.fromOffset(34, 30)
		rec.Size = UDim2.fromOffset(18, 18)
		rec.BackgroundColor3 = RED
		rec.BorderSizePixel = 0
		rec.ZIndex = 6
		rec.Parent = gui
		corner(rec, UDim.new(0.5, 0))
		local recText = label(gui, "REC", 24, RED, 6)
		recText.Position = UDim2.fromOffset(60, 24)
		recText.Size = UDim2.fromOffset(60, 30)
		recText.TextXAlignment = Enum.TextXAlignment.Left

		local camTitle = label(gui, "", 30, WHITE, 6)
		camTitle.Position = UDim2.fromOffset(34, 58)
		camTitle.Size = UDim2.fromOffset(600, 36)
		camTitle.TextXAlignment = Enum.TextXAlignment.Left

		-- Üst sağ: saat
		local clock = label(gui, "", 24, GREEN, 6)
		clock.AnchorPoint = Vector2.new(1, 0)
		clock.Position = UDim2.new(1, -90, 0, 26)
		clock.Size = UDim2.fromOffset(200, 30)
		clock.TextXAlignment = Enum.TextXAlignment.Right

		local closeButton = Instance.new("TextButton")
		closeButton.AnchorPoint = Vector2.new(1, 0)
		closeButton.Position = UDim2.new(1, -28, 0, 22)
		closeButton.Size = UDim2.fromOffset(44, 44)
		closeButton.BackgroundColor3 = UiKit.CREW.RED
		closeButton.AutoButtonColor = false
		closeButton.Font = Enum.Font.FredokaOne
		closeButton.TextSize = 24
		closeButton.TextColor3 = WHITE
		closeButton.Text = "X"
		closeButton.ZIndex = 7
		closeButton.Parent = gui
		corner(closeButton, UDim.new(0.5, 0))
		local cs = Instance.new("UIStroke")
		cs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		cs.Color = WHITE
		cs.Thickness = 2
		cs.Parent = closeButton

		-- Alt: önceki / sonraki ve kamera noktaları
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.new(0.5, 0, 1, -30)
		bar.Size = UDim2.fromOffset(520, 64)
		bar.BackgroundColor3 = Color3.fromRGB(10, 14, 12)
		bar.BackgroundTransparency = 0.25
		bar.ZIndex = 6
		bar.Parent = gui
		corner(bar, UDim.new(0, 14))
		local bs = Instance.new("UIStroke")
		bs.Color = GREEN
		bs.Transparency = 0.4
		bs.Thickness = 2
		bs.Parent = bar

		local function arrow(text: string, x: number): TextButton
			local b = Instance.new("TextButton")
			b.AnchorPoint = Vector2.new(0.5, 0.5)
			b.Position = UDim2.new(x, 0, 0.5, 0)
			b.Size = UDim2.fromOffset(52, 44)
			b.BackgroundColor3 = Color3.fromRGB(30, 60, 42)
			b.AutoButtonColor = true
			b.Font = Enum.Font.FredokaOne
			b.TextSize = 28
			b.TextColor3 = GREEN
			b.Text = text
			b.ZIndex = 7
			b.Parent = bar
			corner(b, UDim.new(0, 10))
			return b
		end
		local prev = arrow("<", 0.08)
		local nextButton = arrow(">", 0.92)

		local dots = Instance.new("Frame")
		dots.AnchorPoint = Vector2.new(0.5, 0.5)
		dots.Position = UDim2.fromScale(0.5, 0.36)
		dots.Size = UDim2.fromOffset(340, 14)
		dots.BackgroundTransparency = 1
		dots.ZIndex = 7
		dots.Parent = bar
		local dl = Instance.new("UIListLayout")
		dl.FillDirection = Enum.FillDirection.Horizontal
		dl.HorizontalAlignment = Enum.HorizontalAlignment.Center
		dl.Padding = UDim.new(0, 8)
		dl.Parent = dots
		local dotFrames: { Frame } = {}
		for i = 1, #cams do
			local d = Instance.new("Frame")
			d.Size = UDim2.fromOffset(12, 12)
			d.BackgroundColor3 = GREEN
			d.BorderSizePixel = 0
			d.LayoutOrder = i
			d.ZIndex = 7
			d.Parent = dots
			corner(d, UDim.new(0.5, 0))
			table.insert(dotFrames, d)
		end
		local hint = label(bar, "Q / E  switch camera     ESC  close", 14, Color3.fromRGB(170, 210, 180), 7)
		hint.Font = Enum.Font.GothamBold
		hint.AnchorPoint = Vector2.new(0.5, 0)
		hint.Position = UDim2.fromScale(0.5, 0.58)
		hint.Size = UDim2.fromOffset(340, 18)
		if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			hint.Text = "Tap the arrows to switch camera"
		end

		local function show(i: number)
			index = (i - 1) % #cams + 1
			local cam = cams[index]
			camera.CFrame = viewCFrame(cam)
			camTitle.Text = string.format("CAM %d  ·  %s", index, string.upper(cam.name))
			for k, d in dotFrames do
				d.BackgroundTransparency = if k == index then 0 else 0.7
			end
			static.BackgroundTransparency = 0.15
			TweenService:Create(static, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		end

		local connections: { RBXScriptConnection } = {}
		table.insert(connections, prev.Activated:Connect(function()
			show(index - 1)
		end))
		table.insert(connections, nextButton.Activated:Connect(function()
			show(index + 1)
		end))
		table.insert(connections, closeButton.Activated:Connect(close))
		table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
			local k = input.KeyCode
			if k == Enum.KeyCode.Escape or k == Enum.KeyCode.Backspace or k == Enum.KeyCode.ButtonB then
				close()
			elseif processed then
				return
			elseif k == Enum.KeyCode.Q or k == Enum.KeyCode.Left or k == Enum.KeyCode.ButtonL1 or k == Enum.KeyCode.DPadLeft then
				show(index - 1)
			elseif k == Enum.KeyCode.E or k == Enum.KeyCode.Right or k == Enum.KeyCode.ButtonR1 or k == Enum.KeyCode.DPadRight then
				show(index + 1)
			end
		end))

		-- Canlı: REC yanıp sönüyor, çizgiler kayıyor, saat işliyor, kamera
		-- her karede yeniden yazılıyor (başka bir şey kamerayı oynatmasın)
		local started = os.clock()
		table.insert(connections, RunService.RenderStepped:Connect(function()
			local t = os.clock() - started
			local on = (t % 1.2) < 0.7
			rec.BackgroundTransparency = if on then 0 else 1
			recText.TextTransparency = if on then 0 else 0.6
			lines.Position = UDim2.fromScale(0, -((t * 0.03) % (1 / LINES * 2)))
			clock.Text = os.date("%H:%M:%S") :: string
			local cam = cams[index]
			if cam and cam.part.Parent then
				camera.CFrame = viewCFrame(cam)
			end
		end))

		-- Karakter ölürse ya da değişirse çık
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			table.insert(connections, humanoid.Died:Connect(close))
		end
		table.insert(connections, player.CharacterAdded:Connect(close))

		session = {
			show = show,
			cleanup = function()
				for _, c in connections do
					c:Disconnect()
				end
				gui:Destroy()
				grade:Destroy()
				camera.FieldOfView = oldFov
				camera.CameraType = if oldType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else oldType
				if hud and hud:IsA("ScreenGui") then
					hud.Enabled = hudWasEnabled ~= false
				end
				if controls then
					controls:Enable()
				end
			end,
		}
		show(1)
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt.Name == "SecurityPrompt" then
			openView()
		end
	end)

	-- Dışarıdan (gamepad kısayolu, Studio önizlemesi) kullanmak için
	SecurityCams.Open = openView
	SecurityCams.Close = close
	SecurityCams.Step = function(delta: number)
		if session and open then
			local s = session :: any
			if s.show then
				s.show(index + delta)
			end
		end
	end
end

SecurityCams.Open = function() end
SecurityCams.Close = function() end
SecurityCams.Step = function(_: number) end

return SecurityCams
