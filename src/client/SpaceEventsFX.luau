--!strict
--[[
	Uzay istasyonu olaylarının GÖRÜNÜŞÜ (sunucusu EventService / SpaceService).
	Olay workspace.EventId'den okunuyor; ağda ek bir şey taşınmıyor.

	  Meteor Shower   — göktaşları shared/MeteorShower'dan (sunucuyla aynı
	                    tohum): yanan kaya + alev kuyruğu + ışık, söndüğü
	                    yerde patlama halkası. Kameraya uzak olanlar çizilmiyor.
	  Nebula Blackout — uzaydayken ekran kararıp mora çalıyor, karakterin
	                    başında el feneri (SpotLight) yanıyor; mürettebat
	                    auraları ve canavar gözleri karanlıkta öne çıkıyor.
	  Solar Wind      — uzaydayken kameranın önünden akan altın rüzgâr
	                    çizgileri ve sıcak renk tonu.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MeteorShower = require(Shared.MeteorShower)

local SpaceEventsFX = {}

export type Handle = { Destroy: () -> () }

local player = Players.LocalPlayer

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	return p
end

function SpaceEventsFX.Start(): Handle
	local conns: { RBXScriptConnection } = {}
	local folder = Instance.new("Folder")
	folder.Name = "SpaceEventsFX"
	folder.Parent = workspace

	-- Ton: tek ColorCorrection, olaya göre hedef değerlere yumuşak geçiş
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "SpaceEventGrade"
	grade.Enabled = true
	grade.Parent = Lighting
	local lastGoalKey = ""
	local function setGrade(key: string, goal: { [string]: any })
		if key == lastGoalKey then
			return
		end
		lastGoalKey = key
		TweenService:Create(grade, TweenInfo.new(1.2), goal):Play()
	end

	-- ─── Göktaşları ──────────────────────────────────────────────────────
	type Rock = { body: Part, glow: Part, emitter: ParticleEmitter, light: PointLight }
	local pool: { Rock } = {}
	local active: { [number]: Rock } = {}
	local meteors: { MeteorShower.Meteor } = {}
	local builtFor = 0

	local function makeRock(): Rock
		local body = part("Meteor", Vector3.one * 3, Color3.fromRGB(110, 86, 78), Enum.Material.Slate, Enum.PartType.Ball)
		local glow = part("MeteorGlow", Vector3.one * 3.6, Color3.fromRGB(255, 120, 40), Enum.Material.Neon, Enum.PartType.Ball)
		glow.Transparency = 0.55
		local att = Instance.new("Attachment")
		att.Parent = body
		local fire = Instance.new("ParticleEmitter")
		fire.Texture = "rbxasset://textures/particles/fire_main.dds"
		fire.Color = ColorSequence.new(Color3.fromRGB(255, 230, 120), Color3.fromRGB(255, 70, 20))
		fire.LightEmission = 1
		fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 0.2) })
		fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		fire.Lifetime = NumberRange.new(0.5, 0.8)
		fire.Rate = 60
		fire.Speed = NumberRange.new(1, 3)
		fire.LockedToPart = false
		fire.Parent = att
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 140, 60)
		light.Range = 22
		light.Brightness = 2
		light.Parent = body
		body.Parent = folder
		glow.Parent = folder
		return { body = body, glow = glow, emitter = fire, light = light }
	end
	local function take(): Rock
		local r = table.remove(pool)
		if r then
			r.body.Transparency = 0
			r.glow.Transparency = 0.55
			r.emitter.Enabled = true
			r.light.Enabled = true
			return r
		end
		return makeRock()
	end
	local function give(r: Rock)
		r.body.Transparency = 1
		r.glow.Transparency = 1
		r.emitter.Enabled = false
		r.light.Enabled = false
		table.insert(pool, r)
	end
	local function impact(position: Vector3, size: number)
		local ring = part("MeteorImpact", Vector3.new(0.3, size * 2, size * 2), Color3.fromRGB(255, 170, 70), Enum.Material.Neon, Enum.PartType.Cylinder)
		ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
		ring.Transparency = 0.2
		ring.Parent = folder
		TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.3, size * 7, size * 7), Transparency = 1 }):Play()
		task.delay(0.65, function()
			ring:Destroy()
		end)
	end

	-- ─── Fener (Blackout) ────────────────────────────────────────────────
	local torch: SpotLight? = nil
	local function setTorch(on: boolean)
		local head = player.Character and player.Character:FindFirstChild("Head")
		if on and head and not (torch and torch.Parent == head) then
			if torch then
				torch:Destroy()
			end
			local l = Instance.new("SpotLight")
			l.Name = "BlackoutTorch"
			l.Angle = 55
			l.Range = 60
			l.Brightness = 3
			l.Color = Color3.fromRGB(255, 240, 210)
			l.Face = Enum.NormalId.Front
			l.Parent = head
			torch = l
		elseif not on and torch then
			torch:Destroy()
			torch = nil
		end
	end

	-- ─── Güneş rüzgârı çizgileri ─────────────────────────────────────────
	local windHost = part("SolarWindHost", Vector3.one, Color3.new(1, 1, 1))
	windHost.Transparency = 1
	windHost.Parent = folder
	local wind = Instance.new("ParticleEmitter")
	wind.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	wind.Color = ColorSequence.new(Color3.fromRGB(255, 240, 170), Color3.fromRGB(255, 160, 40))
	wind.LightEmission = 1
	wind.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0) })
	wind.Squash = NumberSequence.new(3)
	wind.Lifetime = NumberRange.new(0.6, 1)
	wind.Speed = NumberRange.new(60, 90)
	wind.SpreadAngle = Vector2.new(25, 25)
	wind.Rate = 0
	wind.Shape = Enum.ParticleEmitterShape.Box
	wind.Parent = windHost
	windHost.Size = Vector3.new(60, 30, 2)

	table.insert(conns, RunService.RenderStepped:Connect(function()
		local eventId = workspace:GetAttribute("EventId")
		local inSpace = player:GetAttribute("InSpace") == true or player:GetAttribute("SpaceGrabbed") ~= nil
		local camera = workspace.CurrentCamera
		local camCf = if camera then camera.CFrame else CFrame.identity

		-- Ton
		if eventId == "Blackout" and inSpace then
			setGrade("blackout", { Brightness = -0.28, Contrast = 0.15, Saturation = -0.35, TintColor = Color3.fromRGB(190, 170, 255) })
		elseif eventId == "SolarWind" and inSpace then
			setGrade("solar", { Brightness = 0.04, Contrast = 0.05, Saturation = 0.15, TintColor = Color3.fromRGB(255, 236, 205) })
		else
			setGrade("none", { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = Color3.new(1, 1, 1) })
		end
		setTorch(eventId == "Blackout" and inSpace)

		-- Rüzgâr: kameranın önünden ona doğru akıyor
		if eventId == "SolarWind" and inSpace then
			windHost.CFrame = camCf * CFrame.new(0, 0, -45) * CFrame.Angles(0, math.rad(180), 0)
			wind.Rate = 90
		else
			wind.Rate = 0
		end

		-- Göktaşları
		local seed = workspace:GetAttribute("MeteorSeed")
		local startAt = workspace:GetAttribute("MeteorStart")
		if typeof(seed) == "number" and typeof(startAt) == "number" then
			if builtFor ~= seed then
				builtFor = seed
				local def = Config.GetEvent("Meteors")
				meteors = MeteorShower.Build(seed, startAt, if def then def.duration else 90)
			end
		elseif #meteors > 0 then
			meteors = {}
			builtFor = 0
		end
		local t = workspace:GetServerTimeNow()
		local seen: { [number]: boolean } = {}
		for _, m in meteors do
			local p = MeteorShower.PositionAt(m, t)
			if p and (p - camCf.Position).Magnitude < 700 then
				seen[m.index] = true
				local r = active[m.index]
				if not r then
					r = take()
					active[m.index] = r
					r.body.Size = Vector3.one * m.size
					r.glow.Size = Vector3.one * m.size * 1.25
				end
				local cf = CFrame.lookAt(p, m.to)
				r.body.CFrame = cf * CFrame.Angles(t * 3, t * 2, 0)
				r.glow.CFrame = cf
			end
		end
		for index, r in active do
			if not seen[index] then
				local m = meteors[index]
				if m and t >= m.t1 then
					impact(m.to, m.size)
				end
				give(r)
				active[index] = nil
			end
		end
	end))

	return {
		Destroy = function()
			for _, c in conns do
				c:Disconnect()
			end
			setTorch(false)
			grade:Destroy()
			folder:Destroy()
		end,
	}
end

return SpaceEventsFX
