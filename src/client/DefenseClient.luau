--!strict
--[[
	Gezegen savunmasının istemci yöneticisi (init.client kuruyor).

	  - "DefenseState" olaylarını dinliyor, DefenseUI (2B) ve DefenseFX (3B)
	    modüllerini besliyor
	  - İniş / kalkış animasyonu: ekran kararıyor, gezegen yükseliyor, gemi
	    alçalıyor; varışta kamera gökyüzünden gemiye süzülüyor, toz kalkıyor
	  - Taktik görünüm (KOMUTA konsolu): kamera alanın üstünde, karakter
	    duruyor; dokun/tıkla ile crewmate koy, taşı, Orbital Strike nişanla
	  - Gezegendeyken atmosfer gezegenin renginde (DefensePlanet niteliği)
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local DefenseConfig = require(Shared.DefenseConfig)

local DefenseFX = require(script.Parent.DefenseFX)
local DefenseUI = require(script.Parent.DefenseUI)
local SoundFX = require(script.Parent.SoundFX)

local DefenseClient = {}

local player = Players.LocalPlayer
local WHITE = Color3.new(1, 1, 1)

function DefenseClient.Start(screen: ScreenGui)
	-- Mod kapalıyken (canlı oyun) hiçbir şey kurulmuyor (DefenseConfig.Live)
	if not DefenseConfig.IsEnabled() then
		return
	end
	local remote = Net.Get("Defense")
	local stateRemote = Net.Get("DefenseState")

	local data: any = nil
	local run: any = nil
	local planet: number? = nil
	-- Oyuncunun gezegen kopyası (dünya konumu buna göre)
	local arena = 1
	local beacon: BasePart? = nil
	local pickedSupport: string? = nil

	local function send(...: any)
		remote:FireServer(...)
	end



	-- ─── Ekranın üstündeki perde (animasyonlar) ─────────────────────────────
	local overlayGui = Instance.new("ScreenGui")
	overlayGui.Name = "DefenseOverlay"
	overlayGui.IgnoreGuiInset = true
	overlayGui.ResetOnSpawn = false
	overlayGui.DisplayOrder = 150
	overlayGui.Parent = player:WaitForChild("PlayerGui")
	local curtain = Instance.new("Frame")
	curtain.Size = UDim2.fromScale(1, 1)
	curtain.BackgroundColor3 = Color3.fromRGB(4, 4, 12)
	curtain.BackgroundTransparency = 1
	curtain.Visible = false
	curtain.Parent = overlayGui
	local planetDisc = Instance.new("Frame")
	planetDisc.AnchorPoint = Vector2.new(0.5, 0.5)
	planetDisc.Size = UDim2.fromScale(0.9, 0.9)
	planetDisc.SizeConstraint = Enum.SizeConstraint.RelativeXX
	planetDisc.Position = UDim2.fromScale(0.5, 1.6)
	planetDisc.BackgroundColor3 = WHITE
	planetDisc.Parent = curtain
	local discCorner = Instance.new("UICorner")
	discCorner.CornerRadius = UDim.new(0.5, 0)
	discCorner.Parent = planetDisc
	local discGrad = Instance.new("UIGradient")
	discGrad.Rotation = 90
	discGrad.Parent = planetDisc
	local shipIcon = Instance.new("TextLabel")
	shipIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	shipIcon.Position = UDim2.fromScale(0.5, -0.1)
	shipIcon.Size = UDim2.fromOffset(120, 120)
	shipIcon.BackgroundTransparency = 1
	shipIcon.Text = "🚀"
	shipIcon.TextScaled = true
	shipIcon.Rotation = 180
	shipIcon.AutoLocalize = false
	shipIcon.Parent = curtain
	local curtainText = Instance.new("TextLabel")
	curtainText.AnchorPoint = Vector2.new(0.5, 0)
	curtainText.Position = UDim2.fromScale(0.5, 0.12)
	curtainText.Size = UDim2.fromScale(0.8, 0.09)
	curtainText.BackgroundTransparency = 1
	curtainText.Font = Enum.Font.FredokaOne
	curtainText.TextScaled = true
	curtainText.TextColor3 = WHITE
	curtainText.AutoLocalize = false
	curtainText.Parent = curtain
	local textStroke = Instance.new("UIStroke")
	textStroke.Thickness = 3
	textStroke.Color = Color3.fromRGB(22, 20, 34)
	textStroke.Parent = curtainText

	local function fadeCurtain(show: boolean, seconds: number)
		curtain.Visible = true
		local t = TweenService:Create(curtain, TweenInfo.new(seconds), { BackgroundTransparency = if show then 0 else 1 })
		t:Play()
		for _, l in { curtainText, shipIcon } do
			TweenService:Create(l, TweenInfo.new(seconds), { TextTransparency = if show then 0 else 1 }):Play()
		end
		TweenService:Create(planetDisc, TweenInfo.new(seconds), { BackgroundTransparency = if show then 0 else 1 }):Play()
		if not show then
			task.delay(seconds, function()
				if curtain.BackgroundTransparency > 0.99 then
					curtain.Visible = false
				end
			end)
		end
	end

	-- ─── Atmosfer ───────────────────────────────────────────────────────────
	local savedAtmo: { [string]: any }? = nil
	local function applyEnvironment(index: number?)
		local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
		if index then
			local def = Config.SpaceMonsters[index]
			if not def then
				return
			end
			if not atmo then
				atmo = Instance.new("Atmosphere")
				atmo.Name = "DefenseAtmosphere"
				atmo.Parent = Lighting
			end
			local a = atmo :: Atmosphere
			if not savedAtmo then
				savedAtmo = { Density = a.Density, Offset = a.Offset, Color = a.Color, Decay = a.Decay, Glare = a.Glare, Haze = a.Haze }
			end
			a.Density = 0.32
			a.Offset = 0.2
			a.Color = def.planetColor:Lerp(WHITE, 0.45)
			a.Decay = def.planetColor2
			a.Glare = 0.2
			a.Haze = 1.4
		elseif savedAtmo and atmo then
			local a = atmo :: Atmosphere
			for k, v in savedAtmo do
				(a :: any)[k] = v
			end
			savedAtmo = nil
			if a.Name == "DefenseAtmosphere" then
				a:Destroy()
			end
		end
	end

	-- ─── Taktik görünüm ─────────────────────────────────────────────────────
	local camera = workspace.CurrentCamera
	local ui: DefenseUI.UI

	-- ─── Arayüz kancaları ───────────────────────────────────────────────────
	ui = DefenseUI.Create(screen, {
		send = send,
		pickSupport = function(id: string?)
			-- Orbital Strike nişan ister (sonraki tıklama yerde); diğerleri hemen
			if id and id ~= "Strike" then
				send("support", id)
				pickedSupport = nil
				ui.SetPicked(nil)
				return
			end
			pickedSupport = id
			ui.SetPicked(id)
		end,
		takeoff = function()
			send("takeoff")
		end,
	})

	-- ─── Tıklama → yer noktası (Orbital Strike nişanı) ──────────────────────
	local function fieldPoint(screenPos: Vector2): Vector2?
		if not planet then
			return nil
		end
		-- Girdi konumu üst çubuğu (GuiInset) saymıyor: ScreenPointToRay onu hesaba katıyor
		local ray = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
		local origin = DefenseConfig.WorldOrigin(arena)
		if math.abs(ray.Direction.Y) < 1e-4 then
			return nil
		end
		local t = (origin.Y - ray.Origin.Y) / ray.Direction.Y
		if t <= 0 then
			return nil
		end
		local hit = ray.Origin + ray.Direction * t
		return Vector2.new(hit.X - origin.X, hit.Z - origin.Z)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or pickedSupport ~= "Strike" then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			local p = fieldPoint(Vector2.new(input.Position.X, input.Position.Y))
			if p then
				send("support", "Strike", p.X, p.Y)
				pickedSupport = nil
				ui.SetPicked(nil)
				DefenseFX.Marker(nil, false)
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if pickedSupport ~= "Strike" or input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		local p = fieldPoint(Vector2.new(input.Position.X, input.Position.Y))
		if p then
			DefenseFX.Marker(p, true, DefenseConfig.StrikeRadius)
		end
	end)

	-- Hazırlıkta yerdeki crewmate'in yanına gidip E: geri ele al
	DefenseFX.OnPickup(function(uid: number)
		send("pickup", uid)
	end)

	--[[
		Hedefli bırakma (Batur: "elimle koymak çok zor, tam istediğim yere
		koyamıyorum"): crewmate elindeyken yerde nereye düşeceği halkayla
		görünüyor; tıklayınca FARENİN gösterdiği noktaya (telefonda dokunulan
		yere) bırakılıyor. Karakterden en fazla DROP_REACH; gamepad'de ya da
		nokta yoksa karakterin önü. Sunucu da erişimi doğruluyor.
	]]
	local DROP_REACH = 42
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local lastTouch: Vector2? = nil
	local lastTouchAt = 0
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			lastTouch = Vector2.new(input.Position.X, input.Position.Y)
			lastTouchAt = os.clock()
		end
	end)

	local function rootLocal(): (Vector2?, Vector3?)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (root and planet) then
			return nil, nil
		end
		local rel = root.Position - DefenseConfig.WorldOrigin(arena)
		return Vector2.new(rel.X, rel.Z), root.CFrame.LookVector
	end

	local function rayToField(ray: Ray): Vector2?
		local origin = DefenseConfig.WorldOrigin(arena)
		if math.abs(ray.Direction.Y) < 1e-4 then
			return nil
		end
		local t = (origin.Y - ray.Origin.Y) / ray.Direction.Y
		if t <= 0 then
			return nil
		end
		local hit = ray.Origin + ray.Direction * t
		return Vector2.new(hit.X - origin.X, hit.Z - origin.Z)
	end

	-- Bırakılacak nokta: fare / son dokunuş; erişim dışındaysa karakterin önü
	local function aimPoint(preview: boolean): Vector2?
		local me, look = rootLocal()
		if not (me and look) then
			return nil
		end
		local p: Vector2? = nil
		if not touchOnly and UserInputService.MouseEnabled then
			local m = UserInputService:GetMouseLocation()
			p = rayToField(camera:ViewportPointToRay(m.X, m.Y))
		elseif not preview and lastTouch and os.clock() - lastTouchAt < 0.6 then
			p = rayToField(camera:ScreenPointToRay(lastTouch.X, lastTouch.Y))
		end
		if p and (p - me).Magnitude <= DROP_REACH then
			return p
		end
		return me + Vector2.new(look.X, look.Z).Unit * 5
	end

	local function dropOk(p: Vector2): boolean
		local F = DefenseConfig.Field
		if math.abs(p.X) > F.halfWidth or p.Y < F.zMin or p.Y > F.zMax then
			return false
		end
		if run then
			for _, u in run.units do
				if (Vector2.new(u.x, u.z) - p).Magnitude < DefenseConfig.UnitSpacing then
					return false
				end
			end
		end
		return true
	end

	local function heldCrew(): Tool?
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		return if tool and tool:GetAttribute("DefenseCrew") ~= nil then tool else nil
	end

	local previewing = false
	RunService.RenderStepped:Connect(function()
		local tool = heldCrew()
		if not tool or pickedSupport == "Strike" then
			if previewing then
				previewing = false
				if pickedSupport ~= "Strike" then
					DefenseFX.Marker(nil, false)
				end
			end
			return
		end
		local p = aimPoint(true)
		if p then
			previewing = true
			local unitId = tool:GetAttribute("UnitId")
			local role = if typeof(unitId) == "string" then DefenseConfig.GetRole(unitId) else nil
			DefenseFX.Marker(p, dropOk(p), if role then role.leash else nil)
		end
	end)

	-- ─── İniş ve kalkış ─────────────────────────────────────────────────────
	local function dustAt(at: Vector3, color: Color3)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Transparency = 1
		p.Size = Vector3.one
		p.CFrame = CFrame.new(at)
		p.Parent = workspace
		local e = Instance.new("ParticleEmitter")
		e.Color = ColorSequence.new(color)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(1.2, 2)
		e.Speed = NumberRange.new(10, 18)
		e.SpreadAngle = Vector2.new(80, 10)
		e.EmissionDirection = Enum.NormalId.Top
		e.Rate = 0
		e.Parent = p
		e:Emit(30)
		task.delay(3, function()
			p:Destroy()
		end)
	end

	local landingToken = 0
	local function onLanding(payload: any)
		local index = payload.planet
		local where = payload.arena
		landingToken += 1
		local token = landingToken
		-- Emniyet: varış gelmezse (sunucu iptal etti, bağlantı koptu) perde kalksın
		task.delay(8, function()
			if landingToken == token and curtain.Visible and curtain.BackgroundTransparency < 0.5 then
				fadeCurtain(false, 0.4)
			end
		end)
		ui.CloseAll()
		local def = Config.SpaceMonsters[index]
		if def then
			discGrad.Color = ColorSequence.new(def.planetColor:Lerp(WHITE, 0.2), def.planetColor2)
			curtainText.Text = "LANDING ON " .. string.upper(def.planet) .. "..."
		end
		planetDisc.Position = UDim2.fromScale(0.5, 1.6)
		shipIcon.Position = UDim2.fromScale(0.5, -0.1)
		fadeCurtain(true, 0.45)
		TweenService:Create(planetDisc, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromScale(0.5, 1.15) }):Play()
		TweenService:Create(shipIcon, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromScale(0.5, 0.62) }):Play()
		SoundFX.GearSound("GearBlast", camera.CFrame.Position)
		task.spawn(function()
			pcall(function()
				player:RequestStreamAroundAsync(DefenseConfig.ToWorld(where, DefenseConfig.Layout.spawn, 3), 5)
			end)
		end)
	end

	local function onArrived(payload: any)
		local index = payload.planet
		landingToken += 1
		planet = index
		arena = payload.arena
		DefenseFX.SetPlanet(index)
		DefenseFX.SetArena(arena)
		applyEnvironment(index)
		-- (Konsolun üstündeki ışık sütunu kalktı: "bozuk görünüyor"; altta DEFEND düğmesi var)
		if beacon then
			beacon:Destroy()
			beacon = nil
		end
		-- Kamera gökten gemiye süzülüyor
		local ship = DefenseConfig.ToWorld(arena, Vector2.new(0, DefenseConfig.Layout.shipZ), 10)
		local high = CFrame.lookAt(ship + Vector3.new(110, 120, 170), ship)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = high
		fadeCurtain(false, 0.6)
		local def = Config.SpaceMonsters[index]
		local dustColor = if def then def.planetColor:Lerp(WHITE, 0.3) else WHITE
		for _, x in { -13, 13 } do
			for _, z in { -36, -4, 28 } do
				dustAt(DefenseConfig.ToWorld(arena, Vector2.new(x, DefenseConfig.Layout.shipZ + z), 0.5), dustColor)
			end
		end
		task.spawn(function()
			local character = player.Character
			local root = character and character:WaitForChild("HumanoidRootPart", 3) :: BasePart?
			if root then
				local behind = root.CFrame * CFrame.new(0, 6, 14)
				local tween = TweenService:Create(camera, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ CFrame = CFrame.lookAt(behind.Position, root.Position + Vector3.new(0, 2, 0)) })
				tween:Play()
				tween.Completed:Wait()
			end
			camera.CameraType = Enum.CameraType.Custom
		end)
		local name = if def then string.upper(def.planet) else "PLANET"
		ui.Banner(name, "Press ⚔ DEFEND at the bottom to pick your crew!", Color3.fromRGB(120, 230, 255))
		ui.SetPlanetHud(true)
	end

	local function onLaunch()
		landingToken += 1
		local token = landingToken
		task.delay(8, function()
			if landingToken == token and curtain.Visible and curtain.BackgroundTransparency < 0.5 then
				fadeCurtain(false, 0.4)
			end
		end)
		ui.CloseAll()
		curtainText.Text = "TAKING OFF..."
		planetDisc.Position = UDim2.fromScale(0.5, 1.15)
		shipIcon.Position = UDim2.fromScale(0.5, 0.62)
		fadeCurtain(true, 0.4)
		TweenService:Create(planetDisc, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.fromScale(0.5, 1.7) }):Play()
		TweenService:Create(shipIcon, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.fromScale(0.5, -0.2) }):Play()
		SoundFX.GearSound("GearBlast", camera.CFrame.Position)
	end

	local function onHome()
		landingToken += 1
		planet = nil
		run = nil
		ui.SetPlanetHud(false)
		if beacon then
			beacon:Destroy()
			beacon = nil
		end
		DefenseFX.Clear()
		applyEnvironment(nil)
		camera.CameraType = Enum.CameraType.Custom
		fadeCurtain(false, 0.6)
	end

	-- ─── Sunucu olayları ────────────────────────────────────────────────────
	stateRemote.OnClientEvent:Connect(function(kind: string, payload: any)
		if kind == "data" then
			data = payload
			ui.SetData(payload)
		elseif kind == "landing" then
			onLanding(payload)
		elseif kind == "arrived" then
			onArrived(payload)
		elseif kind == "launch" then
			onLaunch()
		elseif kind == "home" then
			onHome()
		elseif kind == "defend" then
			ui.OpenPrepare()
		elseif kind == "dropped" then
			SoundFX.Success()
		elseif kind == "open" then
			ui.OpenShop(payload)
		elseif kind == "run" then
			local wasFight = run ~= nil and run.phase == "fight"
			run = payload
			ui.SetRun(payload, if payload then payload.planet else planet)
			if payload then
				DefenseFX.SetPlanet(payload.planet)
				DefenseFX.SetArena(payload.arena or arena)
				if payload.phase == "prep" then
					if wasFight then
						DefenseFX.ClearEnemies()
					end
					DefenseFX.ResetUnitHealth()
				end
				DefenseFX.SyncUnits(payload.units)
				DefenseFX.SetPrep(payload.phase == "prep")
				DefenseFX.ShowPaths(payload.plan.paths, payload.phase == "fight")
			else
				DefenseFX.Clear()
				pickedSupport = nil
				ui.SetPicked(nil)
			end
		elseif kind == "tick" then
			DefenseFX.Tick(payload, if run then run.plan.paths else nil)
			ui.SetTick(payload)
		elseif kind == "waveEnd" then
			if payload.won then
				if payload.sector then
					local sub = string.format("%s   %s", string.rep("★", payload.stars) .. string.rep("☆", 3 - payload.stars),
						if payload.gold > 0 then string.format("+%d GOLD", payload.gold) else "no new stars")
					ui.Banner(string.format("SECTOR %d CLEAR!", payload.sector), sub, Color3.fromRGB(255, 220, 80))
					SoundFX.Success()
				else
					ui.Banner(string.format("WAVE %d CLEARED", payload.wave),
						if payload.losses > 0 then string.format("%d crewmate(s) sent to hospital", payload.losses) else "No losses!",
						Color3.fromRGB(120, 255, 140))
				end
			end
		elseif kind == "over" then
			if payload.reason == "lost" then
				ui.Banner("DEFEATED", string.format("The ship fell on wave %d. %d crewmate(s) went to the hospital.",
					payload.wave, payload.fell), Color3.fromRGB(255, 90, 90))
				SoundFX.Deny()
			else
				ui.Banner("RETREAT", string.format("%d wave(s) cleared · +%d gold", payload.wavesCleared, payload.gold),
					Color3.fromRGB(200, 210, 255))
			end
		end
	end)

	--[[
		Işın kılıcı (sunucu Tool olarak veriyor, vuruşu sunucu sayıyor):
		burada yalnızca savuruş. Tutuşu (Grip) yay çizerek döndürüyoruz,
		klasik kılıç animasyonu gibi; arenada yalnız olduğun için başkası
		görmese de olur.
	]]
	local bound: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local function bindSaber(tool: Instance)
		if bound[tool] or not tool:IsA("Tool") then
			return
		end
		local isSaber = tool:GetAttribute("DefenseSaber") ~= nil
		local isCrew = tool:GetAttribute("DefenseCrew") ~= nil
		local isGun = tool:GetAttribute("DefenseRayGun") ~= nil
		if not (isSaber or isCrew or isGun) then
			return
		end
		bound[tool] = true
		local t = tool :: Tool
		local baseGrip = t.Grip
		local swinging = false
		t.Activated:Connect(function()
			if isCrew then
				local uid = t:GetAttribute("DefenseCrew")
				local p = aimPoint(false)
				if typeof(uid) == "number" and p then
					if dropOk(p) then
						send("drop", uid, p.X, p.Y)
					else
						SoundFX.Deny()
						return
					end
				end
			end
			if swinging then
				return
			end
			swinging = true
			if not isGun then
				SoundFX.GearSound(if isSaber then "GearSwing" else "GearPoof", camera.CFrame.Position)
			end
			task.spawn(function()
				-- Kılıç: yay çizerek savur. Tabanca: geri tepme. Crewmate: öne eğilip yere bırak
				local length = if isSaber then 0.28 elseif isGun then 0.14 else 0.22
				local t0 = os.clock()
				while os.clock() - t0 < length and t.Parent do
					local a = (os.clock() - t0) / length
					local k = math.sin(a * math.pi)
					t.Grip = if isSaber then baseGrip * CFrame.Angles(math.rad(-110 * k), 0, math.rad(40 * k))
						elseif isGun then baseGrip * CFrame.new(0, 0, -0.35 * k) * CFrame.Angles(math.rad(-14 * k), 0, 0)
						else baseGrip * CFrame.new(0, 0, -1.2 * k) * CFrame.Angles(math.rad(50 * k), 0, 0)
					task.wait()
				end
				if t.Parent then
					t.Grip = baseGrip
				end
				swinging = false
			end)
		end)
	end
	local function watchCharacter(character: Model)
		for _, child in character:GetChildren() do
			bindSaber(child)
		end
		character.ChildAdded:Connect(bindSaber)
	end
	if player.Character then
		watchCharacter(player.Character)
	end

	player.CharacterAdded:Connect(function(character)
		watchCharacter(character)
	end)
	player:GetAttributeChangedSignal("DefensePlanet"):Connect(function()
		local p = player:GetAttribute("DefensePlanet")
		if typeof(p) ~= "number" then
			planet = nil
			applyEnvironment(nil)
			ui.SetPlanetHud(false)
		end
	end)

	DefenseFX.Start()
	-- Oturum ortasında yeniden kurulduysa (Studio) durumu iste
	task.delay(3, function()
		send("sync")
	end)
end

return DefenseClient
