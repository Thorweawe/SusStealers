--!strict
--[[
	Uzay yürüyüşünün istemci tarafı (sunucusu SpaceService).

	  Yerçekimi   — uzaydayken workspace.Gravity düşüyor (karakter fiziği
	                oyuncunun makinesinde): uzun, süzülen zıplamalar
	  Asteroitler — shared/SpaceField'dan her karede çiziliyor (ağda konum
	                yok). Yolun üstünde her şeridin kırmızı uyarı çizgisi:
	                asteroit yola girmeden ~1.4 sn önce yanıp sönüyor, oyuncu
	                ne zaman geçeceğini okuyabiliyor
	  Çarpma      — KENDİ ekranında görülüyor (gecikmesiz, adil): savrulma
	                hemen, sunucuya "SpaceHit" (taşıdığını düşürsün diye)
	  Gösterge    — üst ortada görev kartı + yön oku; kovalayan canavar
	                yaklaşınca ekran kenarı kırmızı nabız atıyor
	  Olaylar     — sunucudan "enter" / "exit" / "roar" / "knock" / "delivered"
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local SpaceField = require(Shared.SpaceField)

local CardKit = require(script.Parent.CardKit)
local SoundFX = require(script.Parent.SoundFX)

local SpaceFX = {}

type Shaker = {
	Shake: (strength: number, duration: number) -> (),
	Flash: (color: Color3, strength: number, duration: number) -> (),
}

export type Handle = {
	Destroy: () -> (),
}

local player = Players.LocalPlayer
local Z = 30
local FAR = CFrame.new(0, -5000, 0)

local function bearingTo(target: Vector3, from: Vector3): number
	local camera = workspace.CurrentCamera
	if not camera then
		return 0
	end
	local flat = Vector3.new(target.X - from.X, 0, target.Z - from.Z)
	if flat.Magnitude < 0.01 then
		return 0
	end
	local look = camera.CFrame.LookVector
	local camFlat = Vector3.new(look.X, 0, look.Z)
	if camFlat.Magnitude < 0.001 then
		camFlat = Vector3.new(0, 0, -1)
	end
	local dir = flat.Unit
	camFlat = camFlat.Unit
	return -math.deg(math.atan2(camFlat:Cross(dir).Y, camFlat:Dot(dir)))
end

function SpaceFX.Start(screen: Instance, effects: Shaker): Handle
	local s = Config.Space
	local connections: { RBXScriptConnection } = {}
	local hitRemote = Net.Get("SpaceHit")

	-- ─── Gösterge ───────────────────────────────────────────────────────
	local hud = Instance.new("Frame")
	hud.Name = "SpaceHud"
	hud.AnchorPoint = Vector2.new(0.5, 0)
	hud.Position = UDim2.new(0.5, 0, 0, 72)
	hud.Size = UDim2.fromOffset(440, 70)
	hud.BackgroundTransparency = 1
	hud.Visible = false
	hud.Parent = screen

	local card = CardKit.card(hud, Color3.fromRGB(46, 96, 210), UDim2.fromScale(1, 1), Z, UDim2.fromScale(0.2, 0.5), 420)
	local arrow = CardKit.bold(card, "▲", 40, CardKit.YELLOW, Z + 3, 3)
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.new(0, 38, 0.5, 0)
	arrow.Size = UDim2.fromOffset(52, 52)
	local title = CardKit.bold(card, "SPACE WALK", 15, Color3.fromRGB(170, 225, 255), Z + 3, 2)
	title.Position = UDim2.fromOffset(72, 6)
	title.Size = UDim2.new(1, -84, 0, 20)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local objective = CardKit.bold(card, "", 24, CardKit.WHITE, Z + 3, 2.5)
	objective.Position = UDim2.fromOffset(72, 26)
	objective.Size = UDim2.new(1, -84, 0, 36)
	objective.TextXAlignment = Enum.TextXAlignment.Left
	CardKit.fit(objective, 24, 12)

	-- Büyük orta yazı (giriş, kükreme, teslim)
	local shout = CardKit.bold(screen, "", 54, CardKit.WHITE, Z + 5, 5)
	shout.Name = "SpaceShout"
	shout.AnchorPoint = Vector2.new(0.5, 0.5)
	shout.Position = UDim2.fromScale(0.5, 0.36)
	shout.Size = UDim2.fromOffset(900, 70)
	shout.Visible = false
	local shoutScale = Instance.new("UIScale")
	shoutScale.Parent = shout
	local shoutToken = 0
	local function yell(text: string, color: Color3, seconds: number)
		shoutToken += 1
		local token = shoutToken
		shout.Text = text
		shout.TextColor3 = color
		shout.TextTransparency = 0
		shout.Visible = true
		shoutScale.Scale = 0.4
		TweenService:Create(shoutScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(seconds, function()
			if token == shoutToken then
				TweenService:Create(shout, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
				task.wait(0.3)
				if token == shoutToken then
					shout.Visible = false
				end
			end
		end)
	end

	-- Tehlike kenarı: kovalayan canavar yaklaşınca kırmızı nabız
	local danger = Instance.new("Frame")
	danger.Name = "SpaceDanger"
	danger.Size = UDim2.fromScale(1, 1)
	danger.BackgroundTransparency = 1
	danger.ZIndex = 1
	danger.Parent = screen
	local dangerStroke = Instance.new("UIStroke")
	dangerStroke.Color = Color3.fromRGB(255, 40, 70)
	dangerStroke.Thickness = 28
	dangerStroke.Transparency = 1
	dangerStroke.Parent = danger

	-- ─── Dünya (yalnızca bu istemcide) ──────────────────────────────────
	local folder: Folder? = nil
	type Rock = { body: BasePart, glow: BasePart, spin: Vector3 }
	local rocks: { Rock } = {}
	local warnings: { BasePart } = {}

	local function buildWorld()
		if folder then
			folder:Destroy()
		end
		local f = Instance.new("Folder")
		f.Name = "SpaceFXLocal"
		table.clear(rocks)
		table.clear(warnings)
		local rng = Random.new(77)
		for _, lane in s.Lanes do
			local body = Instance.new("Part")
			body.Name = "Asteroid"
			body.Shape = Enum.PartType.Ball
			body.Size = Vector3.one * lane.radius * 2
			body.Material = Enum.Material.Slate
			body.Color = Color3.fromRGB(120, 96, 84)
			body.Anchored = true
			body.CanCollide = false
			body.CanQuery = false
			body.CanTouch = false
			body.CFrame = FAR
			body.Parent = f
			local glow = Instance.new("Part")
			glow.Name = "AsteroidGlow"
			glow.Shape = Enum.PartType.Ball
			glow.Size = Vector3.one * lane.radius * 2.5
			glow.Material = Enum.Material.Neon
			glow.Color = Color3.fromRGB(255, 120, 40)
			glow.Transparency = 0.78
			glow.Anchored = true
			glow.CanCollide = false
			glow.CanQuery = false
			glow.CanTouch = false
			glow.CastShadow = false
			glow.CFrame = FAR
			glow.Parent = f
			-- Arkasında ateş izi
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, lane.radius * 0.6, 0)
			a0.Parent = glow
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -lane.radius * 0.6, 0)
			a1.Parent = glow
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Lifetime = 0.45
			trail.LightEmission = 1
			trail.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 60, 20))
			trail.Transparency = NumberSequence.new(0.2, 1)
			trail.Parent = glow
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 140, 60)
			light.Range = lane.radius * 4
			light.Brightness = 1.5
			light.Parent = glow
			table.insert(rocks, {
				body = body,
				glow = glow,
				spin = Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(-3, 3), rng:NextNumber(-3, 3)),
			})

			local strip = Instance.new("Part")
			strip.Name = "LaneWarning"
			strip.Size = Vector3.new(s.PathHalfWidth * 2 - 1, 0.2, lane.radius * 1.6)
			strip.CFrame = CFrame.new(s.Origin + Vector3.new(0, 0.12, lane.z))
			strip.Material = Enum.Material.Neon
			strip.Color = Color3.fromRGB(255, 50, 60)
			strip.Transparency = 0.85
			strip.Anchored = true
			strip.CanCollide = false
			strip.CanQuery = false
			strip.CanTouch = false
			strip.CastShadow = false
			strip.Parent = f
			table.insert(warnings, strip)
		end
		f.Parent = workspace
		folder = f
	end

	-- ─── Uzay atmosferi ─────────────────────────────────────────────────
	local savedGravity: number? = nil
	local grade: ColorCorrectionEffect? = nil

	local function setAtmosphere(on: boolean)
		if on then
			if not savedGravity then
				savedGravity = workspace.Gravity
			end
			workspace.Gravity = s.Gravity
			if not grade then
				local g = Instance.new("ColorCorrectionEffect")
				g.Name = "SpaceGrade"
				g.TintColor = Color3.fromRGB(215, 222, 255)
				g.Contrast = 0.08
				g.Saturation = 0.12
				g.Parent = Lighting
				grade = g
			end
		else
			if savedGravity then
				workspace.Gravity = savedGravity
				savedGravity = nil
			end
			if grade then
				grade:Destroy()
				grade = nil
			end
		end
	end

	-- ─── Savrulma ───────────────────────────────────────────────────────
	local immuneUntil = 0

	local function knock(from: Vector3, strength: number, stun: number)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (root and root:IsA("BasePart") and humanoid) then
			return
		end
		local now = os.clock()
		immuneUntil = now + s.HitImmunity
		local away = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z)
		if away.Magnitude < 0.1 then
			away = -root.CFrame.LookVector
		end
		humanoid.PlatformStand = true
		root.AssemblyLinearVelocity = away.Unit * strength + Vector3.new(0, strength * 0.45, 0)
		root.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-4, 4), math.random(-8, 8))
		effects.Shake(1.4, 0.45)
		effects.Flash(Color3.fromRGB(255, 120, 40), 0.35, 0.4)
		SoundFX.GearSound("GearBlast", root.Position)
		task.delay(stun, function()
			if humanoid.Parent then
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
	end

	-- ─── Her kare ───────────────────────────────────────────────────────
	local inSpace = false
	local clock = 0
	local lastCarrying: boolean? = nil

	local function nearestChaser(from: Vector3): number
		local zone = workspace:FindFirstChild("SpaceZone")
		local list = zone and zone:FindFirstChild("Monsters")
		local best = math.huge
		if list then
			for _, m in list:GetChildren() do
				if m:IsA("Model") and m:GetAttribute("Chasing") and m.PrimaryPart then
					best = math.min(best, (m.PrimaryPart.Position - from).Magnitude)
				end
			end
		end
		return best
	end

	table.insert(connections, RunService.RenderStepped:Connect(function(dt)
		if not inSpace then
			return
		end
		clock += dt
		local t = workspace:GetServerTimeNow()

		for i, lane in s.Lanes do
			local rock = rocks[i]
			local pos = SpaceField.AsteroidAt(lane, t)
			if rock then
				if pos then
					local cf = CFrame.new(pos) * CFrame.Angles(clock * rock.spin.X, clock * rock.spin.Y, clock * rock.spin.Z)
					rock.body.CFrame = cf
					rock.glow.CFrame = CFrame.new(pos)
				elseif rock.body.CFrame.Y > -4000 then
					rock.body.CFrame = FAR
					rock.glow.CFrame = FAR
				end
			end
			local strip = warnings[i]
			if strip then
				local until_ = SpaceField.SecondsUntilCrossing(lane, t)
				local target = if until_ <= 0 then 0.15 elseif until_ < 1.4 then 0.35 + 0.35 * math.abs(math.sin(clock * 14)) else 0.85
				strip.Transparency = target
			end
		end

		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end

		-- Çarpma: kendi ekranında görüldüğü an
		local now = os.clock()
		if now >= immuneUntil then
			local lane = SpaceField.HitAt(t, root.Position, 2.2)
			if lane then
				local rockPos = SpaceField.AsteroidAt(s.Lanes[lane], t) or root.Position
				knock(rockPos, s.AsteroidKnock, s.AsteroidStun)
				hitRemote:FireServer(lane, t)
			end
		end

		-- Görev kartı ve ok
		local carrying = player:GetAttribute("SpaceCarry") == true
		local goal = if carrying then SpaceField.DockCenter() else SpaceField.NestCenter()
		arrow.Rotation = bearingTo(goal, root.Position)
		if carrying ~= lastCarrying then
			lastCarrying = carrying
			if carrying then
				objective.Text = "RUN TO THE AIRLOCK!"
				CardKit.tintCard(card, Color3.fromRGB(210, 60, 80))
			else
				objective.Text = "Grab a crewmate from the nest"
				CardKit.tintCard(card, Color3.fromRGB(46, 96, 210))
			end
		end

		-- Tehlike kenarı
		local d = if carrying then nearestChaser(root.Position) else math.huge
		if d < 45 then
			local k = 1 - d / 45
			dangerStroke.Transparency = 1 - (0.25 + 0.55 * k) * (0.6 + 0.4 * math.abs(math.sin(clock * (6 + 8 * k))))
		else
			dangerStroke.Transparency = 1
		end
	end))

	local function setInSpace(on: boolean)
		if on == inSpace then
			return
		end
		inSpace = on
		hud.Visible = on
		setAtmosphere(on)
		if on then
			buildWorld()
		else
			if folder then
				folder:Destroy()
				folder = nil
			end
			dangerStroke.Transparency = 1
			shout.Visible = false
		end
	end

	table.insert(connections, player:GetAttributeChangedSignal("InSpace"):Connect(function()
		setInSpace(player:GetAttribute("InSpace") == true)
	end))
	setInSpace(player:GetAttribute("InSpace") == true)
	table.insert(connections, player.CharacterAdded:Connect(function()
		immuneUntil = 0
	end))

	-- ─── Sunucu olayları ────────────────────────────────────────────────
	table.insert(connections, Net.Get("SpaceFX").OnClientEvent:Connect(function(kind, a, b, c)
		if kind == "enter" then
			setInSpace(true)
			yell("SPACE WALK", Color3.fromRGB(140, 220, 255), 2.2)
			effects.Flash(Color3.fromRGB(120, 200, 255), 0.5, 0.6)
		elseif kind == "exit" then
			setInSpace(false)
		elseif kind == "roar" then
			effects.Shake(1.8, 0.9)
			SoundFX.Alarm()
			if player:GetAttribute("SpaceCarry") then
				yell("THE VOID BEASTS WOKE UP! RUN!", Color3.fromRGB(255, 80, 110), 2.4)
			else
				yell("Someone woke the Void Beasts!", Color3.fromRGB(255, 150, 200), 2)
			end
		elseif kind == "knock" and typeof(a) == "Vector3" and typeof(b) == "number" and typeof(c) == "number" then
			knock(a, b, c)
		elseif kind == "delivered" then
			effects.Flash(Color3.fromRGB(90, 255, 120), 0.45, 0.6)
			SoundFX.Success()
			yell(string.format("RESCUED %s!", string.upper(tostring(a))), Color3.fromRGB(120, 255, 130), 2.4)
		end
	end))

	return {
		Destroy = function()
			for _, conn in connections do
				conn:Disconnect()
			end
			setInSpace(false)
			hud:Destroy()
			shout:Destroy()
			danger:Destroy()
		end,
	}
end

return SpaceFX
