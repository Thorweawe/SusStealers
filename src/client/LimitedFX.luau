--!strict
--[[
	Sınırlı etkinliğin havası (2026-09-30, Config.LimitedEvent) — hepsi
	istemcide, ağda bir şey taşınmıyor.

	  GÖKYÜZÜ  — etkinlik sürerken gökte ara ara kayan yıldızlar (etkinlik
	             renginde, kuyruklu). Dünya "şu an özel bir hafta" desin;
	             kameradan uzakta, oynanışa dokunmuyor.
	  +N ✨    — etkinlik parası artınca (EventCandy niteliği) raydaki EVENT
	             düğmesinin yanından yükselen "+N ✨" ve düğmenin zıplaması:
	             kazanç elle tutulur olsun (geri bildirim). Harcama (azalma)
	             sessiz.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)

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

	task.spawn(function()
		while running do
			task.wait(math.random(35, 80) / 10)
			if running and Config.IsLimitedEventActive(Config.ServerNow()) then
				shootingStar(folder)
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
			folder:Destroy()
		end,
	}
end

return LimitedFX
