--!strict
--[[
	Hikâye girişi — yeni oyuncunun ilk 20 saniyesi (PLAY'e basınca, bir kez).

	2026-09-28 (Yusuf: "ilk 5 dakika merak uyandırsın, belki bir hikâyesi
	olur, animasyonla giriş"). Oyuncu hiçbir şey bilmeden koridora
	düşüyordu. Şimdi sinema şeritleri inip kamera dört planla hikâyeyi
	anlatıyor, sonunda oyuncunun ilk görevi büyük yazıyla beliriyor:

	  1. İstasyon uzaktan      "The Skeld drifts through deep space..."
	  2. Canavar gezegenleri   "...until space monsters stole its crew"
	  3. Oyuncunun üssü        "Your podiums are empty. Every crewmate earns cash."
	  4. Launch Bay kapısı     "Grab a jetpack, fly out and steal them back!"
	  →  "MISSION 1: RESCUE A CREWMATE FROM GLORP"

	Kim görüyor: öğretici hiç başlamamış oyuncu ("TutorialStep" 0). Oyun
	boyunca bir kez (oturumda); SKIP ile her an geçiliyor. Kamera sonunda
	karaktere dönüyor, kontroller açılıyor. Konumlar haritadan okunuyor
	(sabit koordinat yok): harita değişse de çalışıyor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SpaceField = require(Shared.SpaceField)

local OwnPlot = require(script.Parent.OwnPlot)

local Intro = {}

local player = Players.LocalPlayer
local played = false

type Shot = { from: CFrame, to: CFrame, text: string, seconds: number }

local OUTLINE = Color3.fromRGB(10, 10, 20)

local function look(position: Vector3, target: Vector3): CFrame
	return CFrame.lookAt(position, target)
end

--[[ Planları haritadan kurar; bulunamayanı atlar. ]]
local function buildShots(): { Shot }
	local shots: { Shot } = {}

	-- 1. İstasyon: uzaktan, yavaşça yaklaşan (merkez = üslerin ortası)
	local plots = workspace:FindFirstChild("Plots")
	if plots and #plots:GetChildren() > 0 then
		local sum = Vector3.zero
		local count = 0
		local mn, mx = Vector3.one * math.huge, -Vector3.one * math.huge
		for _, plot in plots:GetChildren() do
			if plot:IsA("Model") then
				local p = plot:GetPivot().Position
				sum += p
				count += 1
				mn = mn:Min(p)
				mx = mx:Max(p)
			end
		end
		if count > 0 then
			local center = sum / count
			local span = math.max(200, (mx - mn).Magnitude)
			local far = center + Vector3.new(-span * 0.5, span * 0.55 + 80, span * 0.7)
			local near = center + Vector3.new(-span * 0.3, span * 0.35 + 50, span * 0.45)
			table.insert(shots, { from = look(far, center), to = look(near, center), seconds = 4.5,
				text = "The Skeld drifts through deep space..." })
		end
	end

	-- 2. Canavar gezegenleri: ilk canavar (Glorp), sonra en büyüğü
	local first = Config.SpaceMonsters[1]
	local last = Config.SpaceMonsters[#Config.SpaceMonsters]
	if first and last then
		local c1 = SpaceField.PlanetCenter(first)
		local cLast = SpaceField.PlanetCenter(last)
		local r = last.radius
		table.insert(shots, {
			from = look(cLast + Vector3.new(r * 2.6, r * 1.2, r * 2.2), last.position),
			to = look(cLast + Vector3.new(r * 1.6, r * 0.9, r * 1.4), last.position),
			seconds = 4,
			text = "...until space monsters stole its crew and hid them on their planets.",
		})
		table.insert(shots, {
			from = look(c1 + Vector3.new(first.radius * 2.4, first.radius * 1.1, first.radius * 2), first.position),
			to = look(c1 + Vector3.new(first.radius * 1.5, first.radius * 0.8, first.radius * 1.2), first.position),
			seconds = 3.5,
			text = "Glorp is guarding the easiest ones. For now.",
		})
	end

	-- 3. Oyuncunun üssü
	local plot = OwnPlot.Get()
	if plot then
		local pivot = plot:GetPivot().Position
		table.insert(shots, {
			from = look(pivot + Vector3.new(0, 70, 70), pivot),
			to = look(pivot + Vector3.new(0, 42, 44), pivot),
			seconds = 4,
			text = "This is YOUR base. The podiums are empty - every crewmate on one earns cash.",
		})
	end

	-- 4. Launch Bay: güverteden uzaya bakış
	local deck = SpaceField.DeckCenter()
	table.insert(shots, {
		from = look(deck + Vector3.new(0, 18, 40), deck + Vector3.new(0, 10, -120)),
		to = look(deck + Vector3.new(0, 12, 10), deck + Vector3.new(0, 8, -160)),
		seconds = 4,
		text = "Grab a jetpack at the Launch Bay, fly out... and steal them back!",
	})
	return shots
end

function Intro.Play()
	if played then
		return
	end
	played = true
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local shots = buildShots()
	if #shots == 0 then
		return
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "Intro"
	gui.IgnoreGuiInset = true
	-- Tam ekran: telefonun çentik / alt çubuk bölgesi de kaplansın
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = 50
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Sinema şeritleri
	local top = Instance.new("Frame")
	top.BackgroundColor3 = Color3.new(0, 0, 0)
	top.BorderSizePixel = 0
	top.Size = UDim2.new(1, 0, 0, 0)
	top.Parent = gui
	local bottom = Instance.new("Frame")
	bottom.BackgroundColor3 = Color3.new(0, 0, 0)
	bottom.BorderSizePixel = 0
	bottom.AnchorPoint = Vector2.new(0, 1)
	bottom.Position = UDim2.fromScale(0, 1)
	bottom.Size = UDim2.new(1, 0, 0, 0)
	bottom.Parent = gui
	TweenService:Create(top, TweenInfo.new(0.6), { Size = UDim2.new(1, 0, 0.12, 0) }):Play()
	TweenService:Create(bottom, TweenInfo.new(0.6), { Size = UDim2.new(1, 0, 0.16, 0) }):Play()

	local caption = Instance.new("TextLabel")
	caption.AnchorPoint = Vector2.new(0.5, 0.5)
	caption.Position = UDim2.fromScale(0.5, 0.92)
	caption.Size = UDim2.fromScale(0.8, 0.07)
	caption.BackgroundTransparency = 1
	caption.Font = Enum.Font.FredokaOne
	caption.TextScaled = true
	caption.TextColor3 = Color3.new(1, 1, 1)
	caption.Text = ""
	caption.ZIndex = 3
	caption.Parent = gui
	local capStroke = Instance.new("UIStroke")
	capStroke.Thickness = 2.5
	capStroke.Color = OUTLINE
	capStroke.Parent = caption
	local capSize = Instance.new("UITextSizeConstraint")
	capSize.MaxTextSize = 34
	capSize.MinTextSize = 14
	capSize.Parent = caption

	local skip = Instance.new("TextButton")
	skip.AnchorPoint = Vector2.new(1, 0.5)
	skip.Position = UDim2.new(1, -24, 0.06, 0)
	skip.Size = UDim2.fromOffset(120, 40)
	skip.BackgroundColor3 = Color3.fromRGB(40, 46, 68)
	skip.Font = Enum.Font.FredokaOne
	skip.TextSize = 20
	skip.TextColor3 = Color3.new(1, 1, 1)
	skip.Text = "SKIP ▶▶"
	skip.ZIndex = 5
	skip.Parent = gui
	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 12)
	skipCorner.Parent = skip

	local skipped = false
	skip.Activated:Connect(function()
		skipped = true
	end)
	local keyConn = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			skipped = true
		end
	end)

	local oldType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable
	-- Arayüz sinema boyunca kapalı (öğretici kartı, tablo, üst şerit, hedef oku)
	player:SetAttribute("Cinematic", true)
	local pg = player:WaitForChild("PlayerGui")
	local hidden: { ScreenGui } = {}
	for _, name in { "SusStealersHud", "SusStealersTopbar" } do
		local g = pg:FindFirstChild(name)
		if g and g:IsA("ScreenGui") and g.Enabled then
			g.Enabled = false
			table.insert(hidden, g)
		end
	end

	-- Yazı harf harf (daktilo)
	local function typeText(text: string)
		caption.Text = ""
		task.spawn(function()
			for i = 1, #text do
				if skipped or caption.Parent == nil then
					return
				end
				if caption.Text ~= string.sub(text, 1, i - 1) then
					return
				end
				caption.Text = string.sub(text, 1, i)
				task.wait(0.025)
			end
		end)
	end

	for _, shot in shots do
		if skipped then
			break
		end
		camera.CFrame = shot.from
		TweenService:Create(camera, TweenInfo.new(shot.seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = shot.to }):Play()
		typeText(shot.text)
		local t0 = os.clock()
		while os.clock() - t0 < shot.seconds and not skipped do
			task.wait()
		end
	end

	-- Görev kartı
	caption.Text = ""
	local mission = Instance.new("TextLabel")
	mission.AnchorPoint = Vector2.new(0.5, 0.5)
	mission.Position = UDim2.fromScale(0.5, 0.45)
	mission.Size = UDim2.fromScale(0.8, 0.14)
	mission.BackgroundTransparency = 1
	mission.Font = Enum.Font.FredokaOne
	mission.TextScaled = true
	mission.TextColor3 = Color3.fromRGB(255, 214, 70)
	mission.RichText = true
	mission.Text = string.format('MISSION 1<br/><font color="#FFFFFF">Rescue a crewmate from %s</font>',
		string.upper(Config.SpaceMonsters[1].name))
	mission.TextTransparency = 1
	mission.ZIndex = 4
	mission.Parent = gui
	local mStroke = Instance.new("UIStroke")
	mStroke.Thickness = 4
	mStroke.Color = OUTLINE
	mStroke.Transparency = 1
	mStroke.Parent = mission

	camera.CameraType = if oldType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else oldType
	for _, g in hidden do
		g.Enabled = true
	end
	player:SetAttribute("Cinematic", nil)
	TweenService:Create(mission, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
	TweenService:Create(mStroke, TweenInfo.new(0.4), { Transparency = 0 }):Play()
	skip.Visible = false
	TweenService:Create(top, TweenInfo.new(0.6), { Size = UDim2.new(1, 0, 0, 0) }):Play()
	TweenService:Create(bottom, TweenInfo.new(0.6), { Size = UDim2.new(1, 0, 0, 0) }):Play()
	task.wait(2.2)
	TweenService:Create(mission, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
	TweenService:Create(mStroke, TweenInfo.new(0.6), { Transparency = 1 }):Play()
	task.wait(0.7)
	keyConn:Disconnect()
	gui:Destroy()
end

--[[ Öğretici hiç başlamamışsa oynatır (nitelik birkaç saniye içinde gelir). ]]
function Intro.PlayIfNew()
	task.spawn(function()
		local t0 = os.clock()
		while player:GetAttribute("TutorialStep") == nil and os.clock() - t0 < 6 do
			task.wait(0.2)
		end
		if player:GetAttribute("TutorialStep") == 0 then
			Intro.Play()
		end
	end)
end

return Intro
