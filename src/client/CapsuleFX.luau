--!strict
--[[
	Uzay kapsülünde antrenman (sunucusu CapsuleService).

	Oyuncu kendi kapsülüne girince ("InCapsule" niteliği):

	  Uçuş pozu   — içeride karakter tüpün ortasında süzülüyor, mini
	                oyundaki roketle birlikte yatıp yükseliyor (yürümüyor).
	                Çıkış: EXIT düğmesi ya da Space → kapının dışına iner.
	  Mini oyun   — ASTEROID RUN: WASD / joystick'le roketi sür, zig-zag
	                inen taş sıralarındaki boşluklardan geç. Çarpmadan
	                uçtukça mesafe çubuğu dolar; dolunca "CapsuleCatch":
	                kapsülün birkaç saniyelik kazancı bir anda gelir
	                (sunucu sınırlıyor). Training Console kolaylaştırıyor.
	  Kart        — üst ortada uzay hızı, saniyelik artış, sıradaki canavar.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local CardKit = require(script.Parent.CardKit)
local FlyPose = require(script.Parent.FlyPose)
local SoundFX = require(script.Parent.SoundFX)

local CapsuleFX = {}

export type Handle = {
	Destroy: () -> (),
}

local player = Players.LocalPlayer
local Z = 28

local function speed(): number
	local v = player:GetAttribute("SpaceSpeed")
	return if typeof(v) == "number" then v else Config.Space.BaseSpeed
end

local function capsuleLevel(): number
	local v = player:GetAttribute("Upg_SpaceCapsule")
	return if typeof(v) == "number" then v else 0
end

--[[ Hızın yetmediği ilk AÇIK canavar (hepsi yetiyorsa nil). Rebirth kilidi olan canavar yalnızca açıksa. ]]
local function nextMonster(value: number): Config.SpaceMonsterDef?
	local rb = player:GetAttribute("Rebirths")
	local rebirths = if typeof(rb) == "number" then rb else 0
	for _, def in Config.SpaceMonsters do
		if value < def.need and Config.MonsterUnlocked(def, rebirths) then
			return def
		end
	end
	return nil
end

local function myCapsule(): Model?
	local plots = workspace:FindFirstChild("Plots")
	local name = player:GetAttribute("Plot")
	local plot = plots and typeof(name) == "string" and plots:FindFirstChild(name)
	local capsule = plot and plot:FindFirstChild("Capsule")
	return if capsule and capsule:IsA("Model") then capsule else nil
end

function CapsuleFX.Start(screen: Instance): Handle
	local connections: { RBXScriptConnection } = {}
	local catchRemote = Net.Get("CapsuleCatch")

	local controls: any = nil
	task.spawn(function()
		local ok, result = pcall(function()
			local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
			return (require :: any)(module):GetControls()
		end)
		if ok then
			controls = result
		end
	end)

	-- ─── Üst kart ───────────────────────────────────────────────────────
	local holder = Instance.new("Frame")
	holder.Name = "CapsuleHud"
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 72)
	holder.Size = UDim2.fromOffset(400, 118)
	holder.BackgroundTransparency = 1
	holder.Visible = false
	holder.Parent = screen
	local scale = Instance.new("UIScale")
	scale.Parent = holder

	local card = CardKit.card(holder, Color3.fromRGB(40, 110, 220), UDim2.fromScale(1, 1), Z, UDim2.fromScale(0.5, 0.4), 460)
	local title = CardKit.bold(card, "SPACE TRAINING", 16, Color3.fromRGB(180, 235, 255), Z + 3, 2)
	title.Position = UDim2.fromOffset(0, 6)
	title.Size = UDim2.new(1, 0, 0, 20)
	local value = CardKit.bold(card, "16.0", 40, CardKit.YELLOW, Z + 3, 3.5)
	value.Position = UDim2.fromOffset(0, 24)
	value.Size = UDim2.new(1, 0, 0, 42)
	local gain = CardKit.bold(card, "+0.00 / s", 15, CardKit.GREEN, Z + 3, 2)
	gain.AnchorPoint = Vector2.new(1, 0)
	gain.Position = UDim2.new(1, -14, 0, 34)
	gain.Size = UDim2.fromOffset(110, 18)
	gain.TextXAlignment = Enum.TextXAlignment.Right
	local unit = CardKit.bold(card, "SPACE SPEED", 12, CardKit.WHITE, Z + 3, 2)
	unit.Position = UDim2.fromOffset(14, 38)
	unit.Size = UDim2.fromOffset(110, 16)
	unit.TextXAlignment = Enum.TextXAlignment.Left
	local bar = CardKit.bar(card, UDim2.new(1, -28, 0, 26), CardKit.GREEN, Z + 3, 14)
	bar.frame.Position = UDim2.fromOffset(14, 78)

	local function popup(parent: Instance, text: string, color: Color3, size: number, at: UDim2)
		local t = CardKit.bold(parent, text, size, color, Z + 8, 2.5)
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = at
		t.Size = UDim2.fromOffset(220, size + 6)
		TweenService:Create(t, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = at - UDim2.fromOffset(0, 50), TextTransparency = 1 }):Play()
		local stroke = t:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, TweenInfo.new(1), { Transparency = 1 }):Play()
		end
		task.delay(1.05, function()
			t:Destroy()
		end)
	end

	local function refresh()
		local v = speed()
		value.Text = string.format("%.1f", v)
		local rate = player:GetAttribute("CapsuleGain")
		gain.Text = string.format("+%.3f / s", if typeof(rate) == "number" then rate else 0)
		local nxt = nextMonster(v)
		if nxt then
			local prev = Config.Space.BaseSpeed
			for _, def in Config.SpaceMonsters do
				if def.need <= v then
					prev = def.need
				end
			end
			bar.set((v - prev) / math.max(0.001, nxt.need - prev), string.format("%s at %d", string.upper(nxt.name), nxt.need))
		else
			bar.set(1, "EVERY MONSTER IN REACH!")
		end
	end

	-- ─── Mini oyun paneli: ASTEROID RUN ─────────────────────────────────
	--[[
		2026-09-28 (Yusuf): "WASD ile roketi yönetip taşlardan kaçsın, araba
		sürer gibi zig-zag". Yukarıdan sıra sıra taş iniyor, her sırada bir
		boşluk var ve boşluk sıradan sıraya sağa-sola kayıyor (zig-zag).
		WASD / oklar / joystick roketi sürüyor (karakter tüpün ortasında
		sabit süzülüyor, yürümüyor). Taşa çarpmadan uçtukça sağdaki mesafe
		çubuğu doluyor, çarpınca geri gidiyor; yıldızlar ileri atıyor. Dolunca
		"CapsuleCatch" (sunucu CatchCooldown / CatchWarmup ile sınırlıyor).
		Çıkış: EXIT düğmesi ya da Space — karakter kapının dışına iniyor.
	]]
	local TRACK_W, TRACK_H = 232, 310
	local PANEL_W = TRACK_W + 70
	local gameFrame = Instance.new("Frame")
	gameFrame.Name = "CapsuleGame"
	gameFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	gameFrame.Position = UDim2.fromScale(0.72, 0.55)
	gameFrame.Size = UDim2.fromOffset(PANEL_W, TRACK_H + 104)
	gameFrame.BackgroundTransparency = 1
	gameFrame.Visible = false
	gameFrame.Parent = screen
	local gameScale = Instance.new("UIScale")
	gameScale.Parent = gameFrame

	local panel = CardKit.card(gameFrame, Color3.fromRGB(34, 60, 150), UDim2.fromScale(1, 1), Z, UDim2.fromScale(0.5, 0.2), 380)
	local head = CardKit.bold(panel, "ASTEROID RUN", 18, CardKit.YELLOW, Z + 3, 2)
	head.Position = UDim2.fromOffset(0, 8)
	head.Size = UDim2.new(1, 0, 0, 22)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local sub = CardKit.bold(panel, if touch then "Drag on the track to steer. Dodge the rocks!" else "Steer with WASD. Dodge the rocks!", 11, CardKit.WHITE, Z + 3, 1.5)
	sub.Position = UDim2.fromOffset(8, 30)
	sub.Size = UDim2.new(1, -16, 0, 16)

	local TRACK_Y = 52
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(14, TRACK_Y)
	track.Size = UDim2.fromOffset(TRACK_W, TRACK_H)
	track.BackgroundColor3 = Color3.fromRGB(8, 10, 30)
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.ZIndex = Z + 3
	track.Parent = panel
	CardKit.corner(track, 10)
	CardKit.border(track, CardKit.OUTLINE, 3)
	CardKit.gradient(track, Color3.fromRGB(26, 20, 70), Color3.fromRGB(6, 10, 30))
	-- Kayan yıldızlar (üç katman, farklı hız)
	local stars: { Frame } = {}
	for i = 1, 22 do
		local st = Instance.new("Frame")
		local big = i % 3
		st.Size = UDim2.fromOffset(1 + big, 2 + big * 3)
		st.Position = UDim2.fromScale((i * 0.371) % 1, (i * 0.237) % 1)
		st.BackgroundColor3 = Color3.fromRGB(200, 230, 255)
		st.BackgroundTransparency = 0.55 - big * 0.2
		st.BorderSizePixel = 0
		st.ZIndex = Z + 3
		st.Parent = track
		table.insert(stars, st)
	end

	local rocket = CardKit.bold(track, "🚀", 30, CardKit.WHITE, Z + 7, 0)
	rocket.AnchorPoint = Vector2.new(0.5, 0.5)
	rocket.Size = UDim2.fromOffset(40, 40)
	local flame = Instance.new("Frame")
	flame.AnchorPoint = Vector2.new(0.5, 0)
	flame.BackgroundColor3 = Color3.fromRGB(255, 170, 60)
	flame.BorderSizePixel = 0
	flame.ZIndex = Z + 6
	flame.Parent = track
	CardKit.corner(flame, 5)
	CardKit.gradient(flame, Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 90, 30), 90)

	-- Mesafe çubuğu (dikey)
	local prog = Instance.new("Frame")
	prog.Name = "Progress"
	prog.Position = UDim2.fromOffset(TRACK_W + 26, TRACK_Y)
	prog.Size = UDim2.fromOffset(28, TRACK_H)
	prog.BackgroundColor3 = Color3.fromRGB(16, 18, 28)
	prog.BorderSizePixel = 0
	prog.ZIndex = Z + 3
	prog.Parent = panel
	CardKit.corner(prog, 8)
	CardKit.border(prog, CardKit.OUTLINE, 3)
	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = CardKit.YELLOW
	fill.BorderSizePixel = 0
	fill.ZIndex = Z + 4
	fill.Parent = prog
	CardKit.corner(fill, 8)
	CardKit.gradient(fill, Color3.fromRGB(255, 240, 140), Color3.fromRGB(255, 160, 30))
	local goal = CardKit.bold(prog, "🏁", 16, CardKit.WHITE, Z + 5, 0)
	goal.AnchorPoint = Vector2.new(0.5, 1)
	goal.Position = UDim2.new(0.5, 0, 0, -2)
	goal.Size = UDim2.fromOffset(24, 20)

	-- Çıkış düğmesi
	local exitButton = Instance.new("TextButton")
	exitButton.Name = "Exit"
	exitButton.AnchorPoint = Vector2.new(0.5, 1)
	exitButton.Position = UDim2.new(0.5, 0, 1, -10)
	exitButton.Size = UDim2.fromOffset(170, 34)
	exitButton.BackgroundColor3 = Color3.fromRGB(210, 70, 80)
	exitButton.AutoButtonColor = false
	exitButton.Text = ""
	exitButton.ZIndex = Z + 3
	exitButton.Parent = panel
	CardKit.corner(exitButton, 10)
	CardKit.border(exitButton, CardKit.OUTLINE, 3)
	CardKit.gradient(exitButton, Color3.fromRGB(255, 120, 120), Color3.fromRGB(170, 40, 60))
	local exitLabel = CardKit.bold(exitButton, if touch then "EXIT CAPSULE" else "EXIT CAPSULE [SPACE]", 14, CardKit.WHITE, Z + 4, 2)
	exitLabel.Size = UDim2.fromScale(1, 1)

	-- Tur arası yazısı
	local banner = CardKit.bold(track, "", 24, CardKit.WHITE, Z + 9, 3)
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.4)
	banner.Size = UDim2.new(1, -10, 0, 70)
	banner.TextWrapped = true

	--[[
		Ayarlar. Taban hızlı ve dar; Training Console (Config.GetTrainingAssist
		0..1) taşları yavaşlatıyor, boşluğu genişletiyor, çarpma cezasını
		azaltıyor. Kapsül seviyesi taşları biraz hızlandırıyor.
	]]
	--[[
		2026-09-28: "mini oyun bir tık geliştirilsin, çok hızlı kazanılıyorsa
		ayar çek". Tur uzadı (~12 sn, Training Console ile ~9.5) ve içinde
		zorlaşıyor: çubuk doldukça taşlar hızlanıyor, sıralar sıklaşıyor,
		boşluk daralıyor, yarıdan sonra bazı taşlar yana kayıyor. Çarpmadan
		biten tur "PERFECT" (sunucuda PerfectCatchMul).
	]]
	type Tuning = { fall: number, rowEvery: number, gap: number, penalty: number, fill: number }
	local function tuning(progress: number): Tuning
		local level = player:GetAttribute("Upg_TrainingConsole")
		local a = Config.GetTrainingAssist(if typeof(level) == "number" then level else 0)
		local ramp = math.clamp(progress, 0, 1)
		return {
			fall = (145 + math.min(45, capsuleLevel() * 0.6)) * (1 - 0.3 * a) * (1 + 0.45 * ramp),
			rowEvery = (1.05 + 0.35 * a) * (1 - 0.25 * ramp),
			gap = (78 + 38 * a) * (1 - 0.18 * ramp),
			penalty = 0.22 - 0.1 * a,
			fill = 1 / (12 - 2.5 * a),
		}
	end

	type Rock = { x: number, y: number, r: number, spin: number, frame: GuiObject, star: boolean, dx: number, dy: number }
	local rocks: { Rock } = {}

	local function addRock(x: number, y: number, r: number, dx: number?)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(r * 2, r * 2)
		f.BackgroundColor3 = Color3.fromRGB(150, 120, 100)
		f.BorderSizePixel = 0
		f.ZIndex = Z + 5
		f.Parent = track
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.42, 0)
		c.Parent = f
		CardKit.gradient(f, Color3.fromRGB(185, 160, 140), Color3.fromRGB(90, 70, 62), 45)
		CardKit.border(f, Color3.fromRGB(40, 28, 26), 2)
		for k = 1, 2 do
			local crater = Instance.new("Frame")
			crater.AnchorPoint = Vector2.new(0.5, 0.5)
			crater.Size = UDim2.fromScale(0.26 + k * 0.04, 0.26 + k * 0.04)
			crater.Position = UDim2.fromScale(if k == 1 then 0.34 else 0.64, if k == 1 then 0.4 else 0.66)
			crater.BackgroundColor3 = Color3.fromRGB(80, 60, 56)
			crater.BackgroundTransparency = 0.25
			crater.BorderSizePixel = 0
			crater.ZIndex = Z + 5
			crater.Parent = f
			CardKit.corner(crater, 20)
		end
		table.insert(rocks, { x = x, y = y, r = r, spin = (math.random() - 0.5) * 160, frame = f, star = false, dx = dx or 0, dy = 0 })
	end

	local function addStar(x: number, y: number)
		local s = CardKit.bold(track, "⭐", 22, CardKit.WHITE, Z + 6, 0)
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Size = UDim2.fromOffset(26, 26)
		table.insert(rocks, { x = x, y = y, r = 11, spin = 90, frame = s, star = true, dx = 0, dy = 0 })
	end

	--[[
		2026-09-28: "asteroitler üstümüze doğru da gelsin". Göktaşı: kızgın
		kırmızı, kuyruklu; doğduğu anda roketin olduğu yere NİŞAN alıp çapraz
		iniyor (sıradaki taşlardan hızlı). Önünde küçük uyarı "!" yanıp sönüyor.
	]]
	local function addMeteor(x: number, targetX: number, targetY: number, speed: number)
		local r = 13
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(r * 2, r * 2)
		f.BackgroundColor3 = Color3.fromRGB(255, 120, 60)
		f.BorderSizePixel = 0
		f.ZIndex = Z + 5
		f.Parent = track
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
		CardKit.gradient(f, Color3.fromRGB(255, 220, 120), Color3.fromRGB(200, 40, 30), 45)
		CardKit.border(f, Color3.fromRGB(60, 10, 10), 2)
		local tail = Instance.new("Frame")
		tail.AnchorPoint = Vector2.new(0.5, 1)
		tail.Position = UDim2.fromScale(0.5, 0.2)
		tail.Size = UDim2.fromOffset(r * 1.2, r * 2.6)
		tail.BackgroundColor3 = Color3.fromRGB(255, 170, 60)
		tail.BackgroundTransparency = 0.35
		tail.BorderSizePixel = 0
		tail.ZIndex = Z + 4
		tail.Parent = f
		CardKit.corner(tail, 8)
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new(1, 0.2)
		g.Parent = tail
		local y0 = -30
		local dir = Vector2.new(targetX - x, targetY - y0)
		dir = if dir.Magnitude > 1 then dir.Unit else Vector2.new(0, 1)
		-- Kuyruk gidişin tersine baksın
		f.Rotation = math.deg(math.atan2(dir.Y, dir.X)) - 90
		table.insert(rocks, { x = x, y = y0, r = r - 2, spin = 0, frame = f, star = false, dx = dir.X * speed, dy = dir.Y * speed })
	end

	local function clearRocks()
		for _, rock in rocks do
			rock.frame:Destroy()
		end
		table.clear(rocks)
	end

	-- Zig-zag: boşluk her sırada bir yöne kayıyor, kenara varınca dönüyor
	local gapX = TRACK_W / 2
	local gapDir = 1
	local function spawnRow(t: Tuning, progress: number)
		local half = t.gap / 2
		local step = 36 + math.random() * 56
		if math.random() < 0.2 then
			gapDir = -gapDir
		end
		gapX += gapDir * step
		local lo, hi = half + 6, TRACK_W - half - 6
		if gapX < lo or gapX > hi then
			gapX = math.clamp(gapX, lo, hi)
			gapDir = -gapDir
		end
		local x = 12 + math.random() * 8
		while x < TRACK_W - 8 do
			local r = 11 + math.random() * 5
			if math.abs(x - gapX) > half + r and math.random() > 0.12 then
				-- Yarıdan sonra bazı taşlar boşluğa doğru kayıyor
				local drift = if progress > 0.45 and math.random() < 0.3 then (if x < gapX then 1 else -1) * (14 + progress * 26) else 0
				addRock(x, -24 - math.random() * 10, r, drift)
			end
			x += r * 2 + 8 + math.random() * 8
		end
		if math.random() < 0.35 then
			addStar(gapX, -26)
		end
	end

	-- ─── Girdi ──────────────────────────────────────────────────────────
	--[[
		Dokunmatik: pistin üstünde parmağı sürükle, roket parmağa gider
		(2026-09-28, Batur: "mobilde minigame oynanmıyor, WASD'ye göre").
		Joystick kapsülde PlatformStand yüzünden güvenilir değildi. Hedef
		pistin kendi biriminde (ölçekli ekranda da doğru).
	]]
	local dragInput: InputObject? = nil
	local dragTarget: Vector2? = nil
	track.Active = true
	local function toTrack(screenPos: Vector3): Vector2
		local k = TRACK_W / math.max(1, track.AbsoluteSize.X)
		return Vector2.new((screenPos.X - track.AbsolutePosition.X) * k, (screenPos.Y - track.AbsolutePosition.Y) * k)
	end
	table.insert(connections, track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
			dragTarget = toTrack(input.Position)
		end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if input == dragInput then
			dragTarget = toTrack(input.Position)
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input == dragInput then
			dragInput = nil
			dragTarget = nil
		end
	end))

	--[[ Ham yön girdisi (ekrana göre): X sağ, Y yukarı. Joystick/gamepad dahil. ]]
	local function steerInput(): Vector2
		local move = Vector3.zero
		if controls then
			local ok, mv = pcall(function()
				return controls:GetMoveVector()
			end)
			if ok and typeof(mv) == "Vector3" then
				move = mv
			end
		end
		if move.Magnitude < 0.1 and not UserInputService:GetFocusedTextBox() then
			local function key(a: Enum.KeyCode, b: Enum.KeyCode): number
				return if UserInputService:IsKeyDown(a) or UserInputService:IsKeyDown(b) then 1 else 0
			end
			move = Vector3.new(key(Enum.KeyCode.D, Enum.KeyCode.Right) - key(Enum.KeyCode.A, Enum.KeyCode.Left), 0,
				key(Enum.KeyCode.S, Enum.KeyCode.Down) - key(Enum.KeyCode.W, Enum.KeyCode.Up))
		end
		local v = Vector2.new(move.X, -move.Z)
		return if v.Magnitude > 1 then v.Unit else v
	end

	-- ─── Uçuş pozu (tüpün ortasında sabit) ──────────────────────────────
	local floatAtt: Attachment? = nil
	local floatPos: AlignPosition? = nil
	local floatRot: AlignOrientation? = nil
	local floating = false
	local floatPose: FlyPose.Handle? = nil

	local function setFloating(on: boolean)
		if on == floating then
			return
		end
		floating = on
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if on and humanoid and root and root:IsA("BasePart") then
			local att = Instance.new("Attachment")
			att.Name = "CapsuleFloatAtt"
			att.Parent = root
			local ap = Instance.new("AlignPosition")
			ap.Name = "CapsuleFloat"
			ap.Mode = Enum.PositionAlignmentMode.OneAttachment
			ap.Attachment0 = att
			ap.MaxForce = math.huge
			ap.Responsiveness = 12
			ap.Position = root.Position
			ap.Parent = root
			local ao = Instance.new("AlignOrientation")
			ao.Name = "CapsuleFloatRot"
			ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
			ao.Attachment0 = att
			ao.MaxTorque = math.huge
			ao.Responsiveness = 10
			ao.CFrame = root.CFrame.Rotation
			ao.Parent = root
			floatAtt, floatPos, floatRot = att, ap, ao
			humanoid.PlatformStand = true
			if floatPose then
				floatPose:Destroy()
			end
			floatPose = FlyPose.Start(character :: Model)
			floatPose:SetBlend(0.7)
		else
			if floatPos then
				floatPos:Destroy()
			end
			if floatRot then
				floatRot:Destroy()
			end
			if floatAtt then
				floatAtt:Destroy()
			end
			floatAtt, floatPos, floatRot = nil, nil, nil
			if floatPose then
				floatPose:Destroy()
				floatPose = nil
			end
			if humanoid then
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
	end

	-- ─── Durum ──────────────────────────────────────────────────────────
	local inside = false
	local exiting = false
	local lastSpeed = speed()
	local rx, ry = TRACK_W / 2, TRACK_H - 50
	local vx, vy = 0, 0
	local progress = 0
	local roundAt = 0          -- bu andan önce tur başlamadı (hazırlık)
	local nextRowAt = 0
	local invulnUntil = 0
	local lastCatchAt = -math.huge
	local crashedThisRound = false
	local perfectStreak = 0
	-- Yıldız sesi serisi (SoundFX.StarPickup)
	local starCombo = 0
	local lastStarAt = -math.huge
	local nextMeteorAt = 0
	local clock = 0

	local camera = workspace.CurrentCamera
	local baseFov = if camera then camera.FieldOfView else 70

	local function newRound(delay: number)
		progress = 0
		crashedThisRound = false
		nextMeteorAt = os.clock() + delay + 2.5
		roundAt = os.clock() + delay
		nextRowAt = roundAt
		clearRocks()
		rx, ry, vx, vy = TRACK_W / 2, TRACK_H - 50, 0, 0
		gapX = TRACK_W / 2
	end

	--[[ Tüpün geometrisi: ped merkezi, yarıçap, kapı yönü. ]]
	local function capsuleFrame(): (Vector3?, number, Vector3)
		local capsule = myCapsule()
		local pad = capsule and capsule:FindFirstChild("Pad")
		if not (capsule and pad and pad:IsA("BasePart")) then
			return nil, 0, Vector3.new(0, 0, -1)
		end
		local zonePart = capsule:FindFirstChild("Zone")
		local limit = math.max(2, ((zonePart and zonePart:GetAttribute("Radius") :: number?) or 7) - 1.6)
		local doorDir = -(capsule :: Model):GetPivot().LookVector
		local door = capsule:FindFirstChild("Screen")
		if door and door:IsA("BasePart") then
			local toDoor = Vector3.new(door.Position.X - pad.Position.X, 0, door.Position.Z - pad.Position.Z)
			if toDoor.Magnitude > 0.1 then
				doorDir = toDoor.Unit
			end
		end
		doorDir = Vector3.new(doorDir.X, 0, doorDir.Z)
		doorDir = if doorDir.Magnitude > 0.01 then doorDir.Unit else Vector3.new(0, 0, -1)
		return pad.Position, limit, doorDir
	end

	--[[ Çıkış: uçuşu bırak, kapının dışına in (sunucu InCapsule'ü kendisi kaldırıyor). ]]
	local function exitCapsule()
		if not inside or exiting then
			return
		end
		local base, limit, doorDir = capsuleFrame()
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not (base and root and root:IsA("BasePart")) then
			return
		end
		exiting = true
		setFloating(false)
		local spot = base + doorDir * (limit + 4.5) + Vector3.new(0, 3.2, 0)
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = CFrame.lookAt(spot, spot + doorDir)
		gameFrame.Visible = false
	end
	table.insert(connections, exitButton.Activated:Connect(exitCapsule))
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if inside and not processed and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonB) then
			exitCapsule()
		end
	end))

	local function setInside(on: boolean)
		if on == inside then
			return
		end
		inside = on
		exiting = false
		refresh()
		local cam = workspace.CurrentCamera
		if on then
			holder.Visible = true
			gameFrame.Visible = true
			scale.Scale = 0.6
			gameScale.Scale = 0.6
			TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			TweenService:Create(gameScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			newRound(Config.Capsule.CatchWarmup + 0.2)
			if cam then
				baseFov = cam.FieldOfView
				TweenService:Create(cam, TweenInfo.new(0.6), { FieldOfView = baseFov + 8 }):Play()
			end
		else
			holder.Visible = false
			gameFrame.Visible = false
			setFloating(false)
			clearRocks()
			if cam then
				TweenService:Create(cam, TweenInfo.new(0.4), { FieldOfView = baseFov }):Play()
			end
		end
	end

	table.insert(connections, player:GetAttributeChangedSignal("InCapsule"):Connect(function()
		setInside(player:GetAttribute("InCapsule") == true)
	end))
	table.insert(connections, player:GetAttributeChangedSignal("SpaceSpeed"):Connect(function()
		local v = speed()
		if inside and v > lastSpeed and v - lastSpeed < 5 then
			popup(holder, string.format("+%.2f", v - lastSpeed), CardKit.GREEN, 20, UDim2.new(0.5 + (math.random() - 0.5) * 0.5, 0, 0, 40))
		end
		lastSpeed = v
		if inside then
			refresh()
		end
	end))
	table.insert(connections, player.CharacterAdded:Connect(function()
		floating = false
		floatAtt, floatPos, floatRot = nil, nil, nil
	end))
	setInside(player:GetAttribute("InCapsule") == true)

	-- ─── Her kare ───────────────────────────────────────────────────────
	table.insert(connections, RunService.RenderStepped:Connect(function(dt)
		clock += dt
		-- Kendi kapsülümün pedi nabız atıyor (başkalarınınki yavaş)
		local plots = workspace:FindFirstChild("Plots")
		if plots then
			for _, plot in plots:GetChildren() do
				local capsule = plot:FindFirstChild("Capsule")
				local pad = capsule and capsule:FindFirstChild("Pad")
				if pad and pad:IsA("BasePart") then
					local mine = plot.Name == player:GetAttribute("Plot")
					local rate = if mine and inside then 9 else 2
					pad.LocalTransparencyModifier = 0.15 + 0.3 * (0.5 + 0.5 * math.sin(clock * rate))
				end
			end
		end
		if not inside or exiting then
			return
		end
		local now = os.clock()
		local t = tuning(progress)

		-- Roket: yumuşak ivmeyle yön; alt yarıda serbest
		local steer = steerInput()
		if dragTarget then
			-- Parmağa doğru: uzaklık büyüdükçe tam hız, yakında yavaşlıyor
			local d = Vector2.new(dragTarget.X - rx, -(dragTarget.Y - 40 - ry)) / 40
			steer = if d.Magnitude > 1 then d.Unit else d
		end
		vx += (steer.X * 250 - vx) * math.min(1, dt * 9)
		vy += (-steer.Y * 170 - vy) * math.min(1, dt * 9)
		rx = math.clamp(rx + vx * dt, 16, TRACK_W - 16)
		ry = math.clamp(ry + vy * dt, TRACK_H * 0.42, TRACK_H - 24)

		local live = now >= roundAt
		local scroll = if live then t.fall else 60
		if live then
			banner.Text = ""
			if now >= nextRowAt then
				nextRowAt = now + t.rowEvery * (0.85 + math.random() * 0.3)
				spawnRow(t, progress)
			end
			-- Göktaşı: roketin üstünden nişan alarak (tur ilerledikçe sıklaşıyor)
			if now >= nextMeteorAt then
				local level = player:GetAttribute("Upg_TrainingConsole")
				local a = Config.GetTrainingAssist(if typeof(level) == "number" then level else 0)
				nextMeteorAt = now + (2.6 - 1.1 * progress) * (1 + 0.6 * a) * (0.8 + math.random() * 0.4)
				local fromX = math.clamp(rx + (math.random() - 0.5) * 160, 20, TRACK_W - 20)
				addMeteor(fromX, rx, ry, (t.fall + 70) * (1 - 0.25 * a))
			end
			progress = math.min(1, progress + t.fill * dt)
		else
			local left = math.ceil(roundAt - now)
			banner.Text = if left <= 1 then "GO!" else string.format("GET READY\n%d", left)
		end

		-- Taşlar ve yıldızlar
		local hurt = now < invulnUntil
		for i = #rocks, 1, -1 do
			local rock = rocks[i]
			rock.y += if rock.dy ~= 0 then rock.dy * dt else scroll * dt
			if rock.dx ~= 0 then
				rock.x = math.clamp(rock.x + rock.dx * dt, rock.r, TRACK_W - rock.r)
			end
			rock.frame.Position = UDim2.fromOffset(rock.x, rock.y)
			rock.frame.Rotation += rock.spin * dt
			local hit = (Vector2.new(rock.x, rock.y) - Vector2.new(rx, ry)).Magnitude < rock.r + 10
			if hit and rock.star then
				progress = math.min(1, progress + 0.05)
				-- Art arda yıldız: ses her seferinde biraz tizleşiyor (1.5 sn içinde)
				starCombo = if now - lastStarAt < 1.5 then starCombo + 1 else 1
				lastStarAt = now
				SoundFX.StarPickup(starCombo)
				popup(gameFrame, "+BOOST", CardKit.YELLOW, 18, UDim2.fromOffset(14 + rx, TRACK_Y + ry - 20))
				rock.frame:Destroy()
				table.remove(rocks, i)
			elseif hit and not hurt and live then
				hurt = true
				crashedThisRound = true
				perfectStreak = 0
				invulnUntil = now + 1.1
				progress = math.max(0, progress - t.penalty)
				SoundFX.ShipCrash()
				popup(gameFrame, "CRASH!", Color3.fromRGB(255, 110, 110), 20, UDim2.fromOffset(14 + rx, TRACK_Y + ry - 24))
				vx = (if rx < rock.x then -1 else 1) * 260
				rock.frame:Destroy()
				table.remove(rocks, i)
			elseif rock.y > TRACK_H + 30 then
				rock.frame:Destroy()
				table.remove(rocks, i)
			end
		end

		-- Bitiş: sunucunun beklemesi dolmadan çubuk son çizgide bekliyor
		if live and progress >= 1 then
			if now - lastCatchAt >= Config.Capsule.CatchCooldown + 0.15 then
				lastCatchAt = now
				local perfect = not crashedThisRound
				local rb = player:GetAttribute("Rebirths")
				local bonus = Config.GetCapsuleGain(capsuleLevel(), speed()) * Config.GetRebirthTrainingMul(if typeof(rb) == "number" then rb else 0)
					* Config.Capsule.CatchBonusSeconds
					* (if perfect then Config.Capsule.PerfectCatchMul else 1)
				catchRemote:FireServer(perfect)
				SoundFX.Success()
				if perfect then
					perfectStreak += 1
					popup(gameFrame, if perfectStreak > 1 then string.format("PERFECT x%d!", perfectStreak) else "PERFECT!",
						Color3.fromRGB(120, 255, 170), 24, UDim2.new(0.5, 0, 0, TRACK_Y + TRACK_H / 2 - 36))
				end
				popup(gameFrame, string.format("+%.2f SPEED!", bonus), CardKit.YELLOW, 26, UDim2.new(0.5, 0, 0, TRACK_Y + TRACK_H / 2))
				newRound(1.6)
			else
				progress = 0.995
			end
		end

		rocket.Position = UDim2.fromOffset(rx, ry)
		rocket.Rotation = -45 + math.clamp(vx / 250, -1, 1) * 18
		rocket.TextTransparency = if hurt and math.floor(now * 12) % 2 == 0 then 0.7 else 0
		flame.Position = UDim2.fromOffset(rx - 2, ry + 12)
		flame.Size = UDim2.fromOffset(9, 10 + math.abs(math.sin(clock * 30)) * 9 + math.max(0, -vy) / 20)
		fill.Size = UDim2.fromScale(1, progress)
		for i, st in stars do
			local y = (st.Position.Y.Scale + dt * (scroll / TRACK_H) * (0.4 + (i % 3) * 0.35)) % 1
			st.Position = UDim2.fromScale(st.Position.X.Scale, y)
		end

		-- Karakter: tüpün ortasında süzülüyor; roketle birlikte yatıyor
		local base, _, doorDir = capsuleFrame()
		if not base then
			return
		end
		setFloating(true)
		if floatPos and floatRot then
			local right = doorDir:Cross(Vector3.yAxis)
			local side = (rx / TRACK_W - 0.5) * 3
			local height = 4.2 + (1 - ry / TRACK_H) * 3 + math.sin(clock * 2.2) * 0.35
			floatPos.Position = base - right * side + Vector3.new(0, height, 0)
			local roll = -math.clamp(vx / 250, -1, 1) * math.rad(28) + math.sin(clock * 1.6) * math.rad(5)
			floatRot.CFrame = CFrame.lookAt(Vector3.zero, doorDir) * CFrame.Angles(math.rad(-30), 0, roll)
		end
	end))

	return {
		Destroy = function()
			for _, conn in connections do
				conn:Disconnect()
			end
			setInside(false)
			holder:Destroy()
			gameFrame:Destroy()
		end,
	}
end

return CapsuleFX
