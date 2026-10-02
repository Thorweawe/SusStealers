--!strict
--[[
	Sınırlı etkinliğin havası (2026-09-30, Config.LimitedEvent) — hepsi
	istemcide, ağda bir şey taşınmıyor.

	  GÖKYÜZÜ  — etkinlik sürerken gökte ara ara kayan yıldızlar (etkinlik
	             renginde, kuyruklu). Dünya "şu an özel bir hafta" desin;
	             kameradan uzakta, oynanışa dokunmuyor.
	             Cadılar Bayramında (decor "pumpkins") yarasa sürüsü ve hayalet.
	  +N ✨    — etkinlik parası artınca (EventCandy niteliği) raydaki EVENT
	             düğmesinin yanından yükselen "+N ✨" ve düğmenin zıplaması:
	             kazanç elle tutulur olsun (geri bildirim). Harcama (azalma)
	             sessiz.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local T = require(ReplicatedStorage:WaitForChild("Shared").VfxThemes)

local LimitedFX = {}

export type Handle = { Destroy: () -> () }

local player = Players.LocalPlayer

local function shootingStar(folder: Instance)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local e = Config.LimitedEvent
	-- Kameranın önünde, ufkun üstünde bir yer; yatay kayıp biraz düşüyor
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local side = Vector3.new(-flat.Z, 0, flat.X)
	local start = camera.CFrame.Position + flat * 380 + side * math.random(-260, 260) + Vector3.new(0, math.random(140, 260), 0)
	local dir = (side * (if math.random() < 0.5 then -1 else 1) * 1 + Vector3.new(0, -0.35, 0)).Unit
	local star = Instance.new("Part")
	star.Name = "ShootingStar"
	star.Shape = Enum.PartType.Ball
	star.Size = Vector3.one * 2.2
	star.Material = Enum.Material.Neon
	star.Color = if math.random() < 0.5 then e.color else Color3.new(1, 1, 1)
	star.Anchored = true
	star.CanCollide = false
	star.CanQuery = false
	star.CanTouch = false
	star.CastShadow = false
	star.Position = start
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1, 0)
	a0.Parent = star
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1, 0)
	a1.Parent = star
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), e.color)
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Lifetime = 0.5
	trail.Transparency = NumberSequence.new(0, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = star
	star.Parent = folder
	local travel = math.random(160, 260)
	local tween = TweenService:Create(star, TweenInfo.new(0.9, Enum.EasingStyle.Linear), { Position = start + dir * travel })
	tween.Completed:Connect(function()
		star:Destroy()
	end)
	tween:Play()
end

--[[
	Cadılar Bayramı göğü (decor "pumpkins", 2026-10-02): kayan yıldız yerine
	ufukta karşıdan karşıya geçen yarasa sürüsü ya da yavaşça süzülen izli
	hayalet. Tema dokuları VfxThemes'ten (yüklenmeden genel dokuya düşüyor).
]]
--[[ ReplicatedStorage.EventMeshes.<ad> (Cadılar Bayramı 3D: Ghost, Candy) varsa
     kopyası; `host` parçasına kaynaklı ve `size` boyuna ölçekli. Yoksa nil. ]]
local function meshOn(host: BasePart, name: string, size: number): Model?
	local folder = ReplicatedStorage:FindFirstChild("EventMeshes")
	local template = folder and folder:FindFirstChild(name)
	if not (template and template:IsA("Model")) then
		return nil
	end
	local m = template:Clone()
	local _, ext = m:GetBoundingBox()
	m:ScaleTo(m:GetScale() * size / math.max(ext.X, ext.Y, ext.Z))
	m:PivotTo(host.CFrame)
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.CastShadow = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = host
			w.Part1 = p
			w.Parent = p
		end
	end
	m.Parent = host
	return m
end

local function skyStart(): (Vector3, Vector3)?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local side = Vector3.new(-flat.Z, 0, flat.X) * (if math.random() < 0.5 then -1 else 1)
	return camera.CFrame.Position + flat * 300 - side * 220 + Vector3.new(0, math.random(90, 200), 0), side
end

local function carrier(folder: Instance, start: Vector3): Part
	local p = Instance.new("Part")
	p.Name = "SpookySky"
	p.Size = Vector3.one
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Position = start
	p.Parent = folder
	return p
end

local function batFlock(folder: Instance)
	local start, side = skyStart()
	if not (start and side) then
		return
	end
	local p = carrier(folder, start)
	local bats = Instance.new("ParticleEmitter")
	bats.Texture = T("bat", Config.Vfx.Star)
	bats.Color = ColorSequence.new(Color3.fromRGB(70, 40, 100), Color3.fromRGB(20, 10, 30))
	bats.LightEmission = 0
	bats.LightInfluence = 0
	bats.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 7) })
	bats.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0), NumberSequenceKeypoint.new(0.85, 0), NumberSequenceKeypoint.new(1, 1) })
	bats.Lifetime = NumberRange.new(3, 4)
	bats.Speed = NumberRange.new(4, 10)
	bats.SpreadAngle = Vector2.new(25, 25)
	bats.RotSpeed = NumberRange.new(-30, 30)
	bats.Rate = 14
	bats.Parent = p
	local travel = TweenService:Create(p, TweenInfo.new(5, Enum.EasingStyle.Linear), { Position = start + side * 440 + Vector3.new(0, 20, 0) })
	travel:Play()
	task.delay(4, function()
		bats.Enabled = false
	end)
	task.delay(9, function()
		p:Destroy()
	end)
end

local function ghost(folder: Instance)
	local start, side = skyStart()
	if not (start and side) then
		return
	end
	local g = Instance.new("Part")
	g.Name = "SkyGhost"
	g.Shape = Enum.PartType.Ball
	g.Size = Vector3.one * 7
	g.Material = Enum.Material.Neon
	g.Color = Color3.fromRGB(190, 255, 225)
	g.Transparency = 0.45
	g.Anchored = true
	g.CanCollide = false
	g.CanQuery = false
	g.CanTouch = false
	g.CastShadow = false
	g.Position = start
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 2.5, 0)
	a0.Parent = g
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -2.5, 0)
	a1.Parent = g
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.fromRGB(200, 255, 230), Color3.fromRGB(120, 60, 190))
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Lifetime = 1.6
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.Parent = g
	local wisp = Instance.new("ParticleEmitter")
	wisp.Texture = Config.Vfx.Wisp
	wisp.Color = ColorSequence.new(Color3.fromRGB(190, 255, 225), Color3.fromRGB(90, 200, 150))
	wisp.LightEmission = 0.6
	wisp.Size = NumberSequence.new(5, 1)
	wisp.Transparency = NumberSequence.new(0.5, 1)
	wisp.Lifetime = NumberRange.new(1.2, 1.8)
	wisp.Speed = NumberRange.new(0.5, 1.5)
	wisp.Rate = 8
	wisp.Parent = g
	g.Parent = folder
	if meshOn(g, "Ghost", 16) then
		g.Transparency = 1
	end
	-- Dalgalanarak süzülüyor: iki yarım yol, ikincisi biraz aşağıda
	local mid = start + side * 220 + Vector3.new(0, 25, 0)
	local first = TweenService:Create(g, TweenInfo.new(4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Position = mid })
	first.Completed:Connect(function()
		local second = TweenService:Create(g, TweenInfo.new(4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Position = mid + side * 220 - Vector3.new(0, 15, 0), Transparency = 1 })
		second.Completed:Connect(function()
			g:Destroy()
		end)
		second:Play()
	end)
	first:Play()
end

local function popup(screen: Instance, amount: number)
	local rail = screen:FindFirstChild("SideRail")
	local button = rail and rail:FindFirstChild("Event")
	if not (button and button:IsA("GuiObject") and button.Visible) then
		return
	end
	local e = Config.LimitedEvent
	local label = Instance.new("TextLabel")
	label.Name = "EventGain"
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 26
	-- Açık ton: etkinlik rengi koyu olsa da okunsun
	label.TextColor3 = e.color:Lerp(Color3.new(1, 1, 1), 0.35)
	label.Text = string.format("+%d %s", amount, e.icon)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.fromOffset(140, 30)
	label.ZIndex = 40
	local pos = button.AbsolutePosition
	local size = button.AbsoluteSize
	label.Position = UDim2.fromOffset(pos.X + size.X + 8, pos.Y + size.Y * 0.2)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(10, 12, 24)
	stroke.Parent = label
	label.Parent = screen
	local info = TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(label, info, { Position = label.Position - UDim2.fromOffset(0, 46), TextTransparency = 1 }):Play()
	TweenService:Create(stroke, info, { Transparency = 1 }):Play()
	task.delay(1.2, function()
		label:Destroy()
	end)
	-- Düğme zıplasın
	local scale = button:FindFirstChild("GainPop") :: UIScale?
	if not scale then
		local s = Instance.new("UIScale")
		s.Name = "GainPop"
		s.Parent = button
		scale = s
	end
	local pop = scale :: UIScale
	pop.Scale = 1.18
	TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function LimitedFX.Start(screen: Instance): Handle
	local folder = Instance.new("Folder")
	folder.Name = "LimitedFX"
	folder.Parent = workspace
	local running = true

	--[[
		Yağmurun düşen parçaları sunucuda neon küre (LimitedEventService,
		"EventStars"). Temanın 3D parçası varsa (Starfall: Star, Cadılar
		Bayramı: Candy; ReplicatedStorage.EventMeshes) küre yerelde gizlenip
		ağ biniyor; ışık, parıltı ve üstteki simge aynen kalıyor.
	]]
	local candyConn: RBXScriptConnection? = nil
	local pickupMesh = if Config.LimitedEvent.decor == "pumpkins" then "Candy"
		elseif Config.LimitedEvent.decor == "stars" then "Star"
		else nil
	if pickupMesh then
		local function dress(d: Instance)
			if d:IsA("BasePart") and (d.Name == "EventStar" or d.Name == "SuperStar") then
				task.defer(function()
					if meshOn(d, pickupMesh :: string, d.Size.X * 1.6) then
						d.Transparency = 1
					end
				end)
			end
		end
		local function watch(f: Instance)
			for _, d in f:GetChildren() do
				dress(d)
			end
			candyConn = f.ChildAdded:Connect(dress)
		end
		task.spawn(function()
			while running do
				local f = workspace:FindFirstChild("EventStars")
				if f then
					if candyConn then
						candyConn:Disconnect()
					end
					watch(f)
					-- Sunucu her yağmurda klasörü yeniden kuruyor
					f.AncestryChanged:Wait()
				else
					task.wait(2)
				end
			end
		end)
	end

	task.spawn(function()
		while running do
			task.wait(math.random(35, 80) / 10)
			if running and Config.IsLimitedEventActive(Config.ServerNow()) then
				if Config.LimitedEvent.decor == "pumpkins" then
					if math.random() < 0.6 then
						batFlock(folder)
					else
						ghost(folder)
					end
				else
					shootingStar(folder)
				end
			end
		end
	end)

	local last: number? = nil
	local conn = player:GetAttributeChangedSignal("EventCandy"):Connect(function()
		local v = player:GetAttribute("EventCandy")
		if typeof(v) ~= "number" then
			return
		end
		-- İlk değer (kayıttan) sayılmıyor
		if last and v > last then
			popup(screen, v - last)
		end
		last = v
	end)
	local first = player:GetAttribute("EventCandy")
	last = if typeof(first) == "number" then first else nil

	return {
		Destroy = function()
			running = false
			conn:Disconnect()
			if candyConn then
				candyConn:Disconnect()
			end
			folder:Destroy()
		end,
	}
end

return LimitedFX
