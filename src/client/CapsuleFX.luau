--!strict
--[[
	Uzay kapsülünde antrenman (sunucusu CapsuleService).

	Oyuncu kendi kapsülüne girince ("InCapsule" niteliği):

	  Uçuş pozu   — durduğu an karakter tüpün ortasında süzülüyor, yatay
	                "uçan" pozda, hafifçe sallanarak. Yüksekliği mini
	                oyundaki roketle birlikte iniyor-çıkıyor. Yürüme tuşuna
	                basınca poz bırakılıyor, kapıdan yürüyüp çıkılıyor.
	  Mini oyun   — Stardew'deki balık tutma gibi: sağda dikey bir hat,
	                içinde gezinen yeşil alan ve bir roket. Basılı tut
	                (tık / Space / dokun) → roket yükselir, bırak → düşer.
	                Roket alandayken sağdaki çubuk dolar, dışındayken boşalır.
	                Dolunca sunucuya "CapsuleCatch": kapsülün 10 saniyelik
	                kazancı bir anda gelir (sunucu sınırlıyor).
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
local SoundFX = require(script.Parent.SoundFX)

local CapsuleFX = {}

export type Handle = {
	Destroy: () -> (),
}

local player = Players.LocalPlayer
local Z = 28

-- Mini oyun ayarları (hat yüksekliğinin kesri olarak)
local ZONE_H = 0.28
local RISE = 2.8           -- basılıyken yukarı ivme
local FALL = 2.3           -- bırakınca aşağı ivme
local MAX_V = 1.25
local FILL = 0.13          -- alandayken çubuk dolma hızı (sn başına)
local DRAIN = 0.1
local START = 0.2
-- Tur arası: sunucunun beklemesi (CatchCooldown) dolmadan çubuk dolamasın
local INTRO = math.max(1.5, Config.Capsule.CatchCooldown - (1 - START) / FILL + 0.1)

local function speed(): number
	local v = player:GetAttribute("SpaceSpeed")
	return if typeof(v) == "number" then v else Config.Space.BaseSpeed
end

local function capsuleLevel(): number
	local v = player:GetAttribute("Upg_SpaceCapsule")
	return if typeof(v) == "number" then v else 0
end

--[[ Hızın yetmediği ilk canavar (hepsi yetiyorsa nil). ]]
local function nextMonster(value: number): Config.SpaceMonsterDef?
	for _, def in Config.SpaceMonsters do
		if value < def.need then
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

	-- ─── Mini oyun paneli ───────────────────────────────────────────────
	local gameFrame = Instance.new("Frame")
	gameFrame.Name = "CapsuleGame"
	gameFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	gameFrame.Position = UDim2.fromScale(0.7, 0.54)
	gameFrame.Size = UDim2.fromOffset(190, 380)
	gameFrame.BackgroundTransparency = 1
	gameFrame.Visible = false
	gameFrame.Parent = screen
	local gameScale = Instance.new("UIScale")
	gameScale.Parent = gameFrame

	local panel = CardKit.card(gameFrame, Color3.fromRGB(34, 60, 150), UDim2.fromScale(1, 1), Z, UDim2.fromScale(0.5, 0.2), 380)
	local head = CardKit.bold(panel, "FLIGHT TRAINING", 16, CardKit.YELLOW, Z + 3, 2)
	head.Position = UDim2.fromOffset(0, 8)
	head.Size = UDim2.new(1, 0, 0, 20)
	local sub = CardKit.bold(panel, "Keep the rocket in the green zone!", 11, CardKit.WHITE, Z + 3, 1.5)
	sub.Position = UDim2.fromOffset(8, 28)
	sub.Size = UDim2.new(1, -16, 0, 26)
	sub.TextWrapped = true

	local TRACK_Y, TRACK_H = 60, 250
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(34, TRACK_Y)
	track.Size = UDim2.fromOffset(64, TRACK_H)
	track.BackgroundColor3 = Color3.fromRGB(10, 14, 36)
	track.BorderSizePixel = 0
	track.ClipsDescendants = true
	track.ZIndex = Z + 3
	track.Parent = panel
	CardKit.corner(track, 10)
	CardKit.border(track, CardKit.OUTLINE, 3)
	-- Hattın içinde kayan yıldızlar
	local stars: { Frame } = {}
	for i = 1, 12 do
		local st = Instance.new("Frame")
		st.Size = UDim2.fromOffset(2, 2 + (i % 3) * 2)
		st.Position = UDim2.fromScale((i * 0.37) % 1, (i * 0.23) % 1)
		st.BackgroundColor3 = Color3.fromRGB(200, 230, 255)
		st.BackgroundTransparency = 0.3
		st.BorderSizePixel = 0
		st.ZIndex = Z + 3
		st.Parent = track
		table.insert(stars, st)
	end

	local zone = Instance.new("Frame")
	zone.Name = "Zone"
	zone.AnchorPoint = Vector2.new(0, 0.5)
	zone.Size = UDim2.new(1, 0, ZONE_H, 0)
	zone.BackgroundColor3 = Color3.fromRGB(80, 230, 90)
	zone.BackgroundTransparency = 0.25
	zone.BorderSizePixel = 0
	zone.ZIndex = Z + 4
	zone.Parent = track
	CardKit.corner(zone, 8)
	CardKit.gradient(zone, Color3.fromRGB(150, 255, 150), Color3.fromRGB(40, 170, 60))
	local zoneStroke = CardKit.border(zone, Color3.fromRGB(220, 255, 220), 2, 0.2)
	local _ = zoneStroke

	local rocket = CardKit.bold(track, "🚀", 30, CardKit.WHITE, Z + 6, 0)
	rocket.AnchorPoint = Vector2.new(0.5, 0.5)
	rocket.Size = UDim2.fromOffset(40, 40)
	rocket.Rotation = -45
	local flame = Instance.new("Frame")
	flame.AnchorPoint = Vector2.new(0.5, 0)
	flame.Size = UDim2.fromOffset(10, 14)
	flame.BackgroundColor3 = Color3.fromRGB(255, 170, 60)
	flame.BorderSizePixel = 0
	flame.ZIndex = Z + 5
	flame.Parent = track
	CardKit.corner(flame, 5)

	-- İlerleme çubuğu (dikey)
	local prog = Instance.new("Frame")
	prog.Name = "Progress"
	prog.Position = UDim2.fromOffset(116, TRACK_Y)
	prog.Size = UDim2.fromOffset(34, TRACK_H)
	prog.BackgroundColor3 = Color3.fromRGB(16, 18, 28)
	prog.BorderSizePixel = 0
	prog.ZIndex = Z + 3
	prog.Parent = panel
	CardKit.corner(prog, 8)
	CardKit.border(prog, CardKit.OUTLINE, 3)
	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, START)
	fill.BackgroundColor3 = CardKit.YELLOW
	fill.BorderSizePixel = 0
	fill.ZIndex = Z + 4
	fill.Parent = prog
	CardKit.corner(fill, 8)
	CardKit.gradient(fill, Color3.fromRGB(255, 240, 140), Color3.fromRGB(255, 160, 30))

	local hint = CardKit.bold(panel, if UserInputService.TouchEnabled then "HOLD THE BUTTON" else "HOLD CLICK / SPACE", 12, CardKit.YELLOW, Z + 3, 1.5)
	hint.Position = UDim2.fromOffset(0, TRACK_Y + TRACK_H + 6)
	hint.Size = UDim2.new(1, 0, 0, 16)

	-- Dokunmatik: panelin altında büyük basılı tutma düğmesi
	local holdButton = Instance.new("TextButton")
	holdButton.Name = "Hold"
	holdButton.AnchorPoint = Vector2.new(0.5, 0)
	holdButton.Position = UDim2.new(0.5, 0, 1, 8)
	holdButton.Size = UDim2.fromOffset(170, 52)
	holdButton.BackgroundColor3 = CardKit.GREEN
	holdButton.AutoButtonColor = false
	holdButton.Text = ""
	holdButton.Visible = UserInputService.TouchEnabled
	holdButton.ZIndex = Z + 3
	holdButton.Parent = gameFrame
	CardKit.corner(holdButton, 14)
	CardKit.border(holdButton, CardKit.OUTLINE, 3)
	local holdLabel = CardKit.bold(holdButton, "HOLD TO FLY", 20, CardKit.WHITE, Z + 4, 2.5)
	holdLabel.Size = UDim2.fromScale(1, 1)

	-- Tur arası yazısı
	local banner = CardKit.bold(panel, "", 22, CardKit.WHITE, Z + 9, 3)
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.new(0.5, 0, 0, TRACK_Y + TRACK_H / 2)
	banner.Size = UDim2.new(1, -10, 0, 60)
	banner.TextWrapped = true

	-- ─── Girdi: basılı tutma ────────────────────────────────────────────
	local holdingKey = false
	local holdingButton = false
	local holdingTouch = 0
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.ButtonA then
			holdingKey = true
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 and not processed then
			holdingKey = true
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.ButtonA
			or input.UserInputType == Enum.UserInputType.MouseButton1 then
			holdingKey = false
		end
	end))
	table.insert(connections, holdButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			holdingButton = true
			holdingTouch += 1
		end
	end))
	table.insert(connections, holdButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			holdingTouch = math.max(0, holdingTouch - 1)
			holdingButton = holdingTouch > 0
		end
	end))

	local function moving(): boolean
		local move = Vector3.zero
		if controls then
			local ok, mv = pcall(function()
				return controls:GetMoveVector()
			end)
			if ok and typeof(mv) == "Vector3" then
				move = mv
			end
		end
		if move.Magnitude > 0.1 then
			return true
		end
		if UserInputService:GetFocusedTextBox() then
			return false
		end
		for _, k in { Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right } do
			if UserInputService:IsKeyDown(k) then
				return true
			end
		end
		return false
	end

	-- ─── Uçuş pozu ──────────────────────────────────────────────────────
	local floatAtt: Attachment? = nil
	local floatPos: AlignPosition? = nil
	local floatRot: AlignOrientation? = nil
	local floating = false

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
			ap.Responsiveness = 14
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
			if humanoid then
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
	end

	-- ─── Durum ──────────────────────────────────────────────────────────
	local inside = false
	local lastSpeed = speed()
	local rocketY, rocketV = 0.3, 0
	local zoneC, zoneTarget, zoneSpeed, nextTarget = 0.5, 0.5, 0.4, 0
	local progress = START
	local roundAt = 0          -- bu andan önce tur başlamadı (hazırlık)
	local stillSince = 0
	local walkedOff = false
	local clock = 0

	local camera = workspace.CurrentCamera
	local baseFov = if camera then camera.FieldOfView else 70

	local function newRound(delay: number)
		progress = START
		roundAt = os.clock() + delay
		zoneC = 0.5
		zoneTarget = 0.5
	end

	local function setInside(on: boolean)
		if on == inside then
			return
		end
		inside = on
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
			rocketY, rocketV = 0.3, 0
			stillSince = os.clock()
			walkedOff = false
			if cam then
				baseFov = cam.FieldOfView
				TweenService:Create(cam, TweenInfo.new(0.6), { FieldOfView = baseFov + 8 }):Play()
			end
		else
			holder.Visible = false
			gameFrame.Visible = false
			setFloating(false)
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
		if not inside then
			return
		end
		local now = os.clock()

		-- Mini oyun
		local holding = holdingKey or holdingButton
		local live = now >= roundAt
		if live then
			banner.Text = ""
			rocketV += (if holding then RISE else -FALL) * dt
			rocketV = math.clamp(rocketV, -MAX_V, MAX_V)
			rocketY += rocketV * dt
			if rocketY < 0 then
				rocketY = 0
				rocketV = -rocketV * 0.3
			elseif rocketY > 1 then
				rocketY = 1
				rocketV = 0
			end
			-- Alan rastgele hedeflere kayıyor; seviye yükseldikçe biraz hızlı
			if now >= nextTarget then
				nextTarget = now + 0.5 + math.random() * 1.1
				zoneTarget = ZONE_H / 2 + math.random() * (1 - ZONE_H)
				zoneSpeed = 0.25 + math.random() * 0.35 + math.min(0.2, capsuleLevel() * 0.01)
			end
			local d = zoneTarget - zoneC
			zoneC += math.sign(d) * math.min(math.abs(d), zoneSpeed * dt)

			local inZone = math.abs(rocketY - zoneC) <= ZONE_H / 2
			progress = math.clamp(progress + (if inZone then FILL else -DRAIN) * dt, 0, 1)
			zone.BackgroundTransparency = if inZone then 0.05 else 0.35
			if progress >= 1 then
				-- Sunucu da aynı bonusu hesaplıyor; burada gösterim
				local bonus = Config.GetCapsuleGain(capsuleLevel(), speed()) * Config.Capsule.CatchBonusSeconds
				catchRemote:FireServer()
				SoundFX.Success()
				popup(gameFrame, string.format("+%.2f SPEED!", bonus), CardKit.YELLOW, 26, UDim2.new(0.5, 0, 0, TRACK_Y + TRACK_H / 2))
				newRound(INTRO)
			elseif progress <= 0 then
				SoundFX.Deny()
				popup(gameFrame, "MISSED!", Color3.fromRGB(255, 110, 110), 24, UDim2.new(0.5, 0, 0, TRACK_Y + TRACK_H / 2))
				newRound(1.5)
			end
		else
			local left = math.ceil(roundAt - now)
			banner.Text = if left <= 1 then "GO!" else string.format("GET READY\n%d", left)
			rocketY = math.max(0, rocketY - dt * 0.6)
		end

		zone.Position = UDim2.fromScale(0, 1 - zoneC)
		rocket.Position = UDim2.new(0.5, 0, 0, (1 - rocketY) * (TRACK_H - 36) + 18)
		flame.Visible = holding and live
		flame.Position = rocket.Position + UDim2.fromOffset(-6, 12)
		flame.Size = UDim2.fromOffset(10, 10 + math.abs(math.sin(clock * 30)) * 8)
		fill.Size = UDim2.fromScale(1, progress)
		for i, st in stars do
			local y = (st.Position.Y.Scale + dt * (0.25 + (i % 3) * 0.2)) % 1
			st.Position = UDim2.fromScale(st.Position.X.Scale, y)
		end

		-- Uçuş pozu: durunca tüpte süzül, yürümeye başlayınca bırak
		local capsule = myCapsule()
		local pad = capsule and capsule:FindFirstChild("Pad")
		if moving() then
			stillSince = now
			walkedOff = true
			setFloating(false)
		elseif walkedOff and now - stillSince > 1.2 then
			walkedOff = false
		end
		if not walkedOff and pad and pad:IsA("BasePart") and now - stillSince > 0.4 then
			setFloating(true)
			if floatPos and floatRot then
				local base = pad.Position
				local height = 3.6 + rocketY * 6 + math.sin(clock * 2.2) * 0.4
				floatPos.Position = base + Vector3.new(math.sin(clock * 0.9) * 0.8, height, math.cos(clock * 0.7) * 0.8)
				-- Kapıya (üsse) bakan, öne yatık "süzülen" poz; yükselirken burun kalkar
				local capsuleCf = (capsule :: Model):GetPivot()
				local look = -capsuleCf.LookVector
				local door = capsule and capsule:FindFirstChild("Screen")
				if door and door:IsA("BasePart") then
					local toDoor = Vector3.new(door.Position.X - base.X, 0, door.Position.Z - base.Z)
					if toDoor.Magnitude > 0.1 then
						look = toDoor.Unit
					end
				end
				local pitch = math.rad(-72) + math.clamp(rocketV, -1, 1) * math.rad(18)
				local roll = math.sin(clock * 1.6) * math.rad(10)
				floatRot.CFrame = CFrame.lookAt(Vector3.zero, look) * CFrame.Angles(pitch, 0, roll)
			end
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
