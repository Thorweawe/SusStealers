--!strict
--[[
	Uzay soygununun istemci tarafı (sunucusu SpaceService).

	  Uçuş      — kuzey duvarın dışında (güverte hariç) karakter uçuyor:
	              kamera yönünde, "SpaceSpeed" niteliği hızında. Zıplama
	              tuşu yükselir, Ctrl/C alçalır. Fizik oyuncunun makinesinde
	              (LinearVelocity + AlignOrientation), ağda karakter olarak
	              gidiyor. Güverteye girince yerçekimi geri geliyor.
	  Canavarlar— sunucudaki görünmez kökleri izleyip her birine
	              MonsterModel kopyası kuruyor, iskeleti duruma göre
	              oynatıyor (boşta salınım, kükreme, kovalama, kavrama, fırlatma)
	  Yakalanma — "grab": karakter canavarın eline yapışıyor, sonra
	              SpaceField.ThrowPath yayıyla gemiye uçuyor
	  Gösterge  — üst ortada görev kartı + yön oku + hız; kovalayan canavar
	              yaklaşınca ekran kenarı kırmızı nabız; canavarların
	              üstünde ad ve gereken hız (yetiyorsa yeşil)
	  Jetpack   — uzaydaki herkesin sırtında (InSpace niteliği), alevli
]]

local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local MonsterModel = require(Shared.MonsterModel)
local Net = require(Shared.Net)
local SpaceField = require(Shared.SpaceField)

local CardKit = require(script.Parent.CardKit)
local FlyPose = require(script.Parent.FlyPose)
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

local RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

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

--[[ Uçuş hızı: kapsül hızı + pet bonusu (sunucudaki SpaceService.speedOf ile aynı). ]]
local function mySpeed(): number
	local v = player:GetAttribute("SpaceSpeed")
	local pet = player:GetAttribute("PetSpeedBonus")
	return Config.GetFlightSpeed(if typeof(v) == "number" then v else Config.Space.BaseSpeed,
		if typeof(pet) == "number" then pet else 0)
end

--[[ Kapsülde kazanılan hız (pet bonusu olmadan): canavar eşikleri buna bakıyor. ]]
local function trainedSpeed(): number
	local v = player:GetAttribute("SpaceSpeed")
	return if typeof(v) == "number" then v else Config.Space.BaseSpeed
end

local function bestRarity(def: Config.SpaceMonsterDef): string
	local best = "Common"
	for _, name in RARITY_ORDER do
		if def.odds[name] then
			best = name
		end
	end
	return best
end

function SpaceFX.Start(screen: Instance, effects: Shaker): Handle
	local s = Config.Space
	local connections: { RBXScriptConnection } = {}

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

	-- ─── Gösterge ───────────────────────────────────────────────────────
	local hud = Instance.new("Frame")
	hud.Name = "SpaceHud"
	hud.AnchorPoint = Vector2.new(0.5, 0)
	hud.Position = UDim2.new(0.5, 0, 0, 72)
	hud.Size = UDim2.fromOffset(460, 78)
	hud.BackgroundTransparency = 1
	hud.Visible = false
	hud.Parent = screen

	local card = CardKit.card(hud, Color3.fromRGB(46, 96, 210), UDim2.fromScale(1, 1), Z, UDim2.fromScale(0.2, 0.5), 420)
	local arrow = CardKit.bold(card, "▲", 40, CardKit.YELLOW, Z + 3, 3)
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.new(0, 38, 0.5, 0)
	arrow.Size = UDim2.fromOffset(52, 52)
	local title = CardKit.bold(card, "SPACE HEIST", 15, Color3.fromRGB(170, 225, 255), Z + 3, 2)
	title.Position = UDim2.fromOffset(72, 6)
	title.Size = UDim2.new(1, -84, 0, 20)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local objective = CardKit.bold(card, "", 24, CardKit.WHITE, Z + 3, 2.5)
	objective.Position = UDim2.fromOffset(72, 26)
	objective.Size = UDim2.new(1, -84, 0, 32)
	objective.TextXAlignment = Enum.TextXAlignment.Left
	CardKit.fit(objective, 24, 12)
	local speedText = CardKit.bold(card, "", 14, CardKit.YELLOW, Z + 3, 2)
	speedText.Position = UDim2.fromOffset(72, 56)
	speedText.Size = UDim2.new(1, -84, 0, 16)
	speedText.TextXAlignment = Enum.TextXAlignment.Left

	-- Büyük orta yazı
	local shout = CardKit.bold(screen, "", 54, CardKit.WHITE, Z + 5, 5)
	shout.Name = "SpaceShout"
	shout.AnchorPoint = Vector2.new(0.5, 0.5)
	shout.Position = UDim2.fromScale(0.5, 0.34)
	shout.Size = UDim2.fromOffset(900, 70)
	shout.Visible = false
	CardKit.fit(shout, 54, 20)
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

	-- Tehlike kenarı
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

	--[[
		JET BOOST (2026-09-28, JetBoost yükseltmesi): uçarken Q / gamepad X /
		mobilde BOOST düğmesi kısa bir hız patlaması veriyor. Uçuş istemcide
		olduğu için etki de burada; sunucu teslimdeki hız kontrolünde boost
		çarpanını hesaba katıyor (SpaceService.deliver).
	]]
	local BOOST_ACTION = "SpaceJetBoost"
	local boostUntil, boostReadyAt, boostCooldown = 0, 0, 1
	local boostBound = false
	local boostBar = CardKit.bar(screen, UDim2.fromOffset(230, 30), Color3.fromRGB(255, 170, 60), Z + 2, 15)
	boostBar.frame.Name = "JetBoostBar"
	boostBar.frame.AnchorPoint = Vector2.new(0.5, 1)
	boostBar.frame.Position = UDim2.new(0.5, 0, 1, -178)
	boostBar.frame.Visible = false

	local function jetParams(): Config.JetBoost?
		local level = player:GetAttribute("Upg_JetBoost")
		return Config.GetJetBoost(if typeof(level) == "number" then level else 0)
	end


	-- ─── Canavar görselleri ─────────────────────────────────────────────
	type Visual = {
		holder: Model,          -- sunucudaki (kök)
		root: BasePart,
		def: Config.SpaceMonsterDef,
		model: Model,
		rig: MonsterModel.Rig,
		cf: CFrame,
		grab: number,
		roar: number,
		sway: number,
		rate: number,
		state: string,
		stateAt: number,
		label: TextLabel,
		needLabel: TextLabel,
		tag: TextLabel,
		posedAt: number?,
	}
	local visuals: { [Model]: Visual } = {}
	local localFolder = Instance.new("Folder")
	localFolder.Name = "SpaceMonstersLocal"
	localFolder.Parent = workspace

	local function makeLabel(v: Model, def: Config.SpaceMonsterDef): (TextLabel, TextLabel, TextLabel)
		local anchor = Instance.new("Part")
		anchor.Name = "LabelAnchor"
		anchor.Size = Vector3.one * 0.2
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor:SetAttribute("Bone", "")
		anchor.CFrame = CFrame.new(0, 22 * def.scale, 0)
		anchor.Parent = v
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(260, 84)
		gui.MaxDistance = 420
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		gui.Parent = anchor
		local list = Instance.new("UIListLayout")
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.VerticalAlignment = Enum.VerticalAlignment.Bottom
		list.Parent = gui
		local tag = CardKit.bold(gui, "zzz", 16, Color3.fromRGB(200, 200, 255), 2, 2)
		tag.LayoutOrder = 1
		tag.Size = UDim2.new(1, 0, 0, 18)
		local name = CardKit.bold(gui, string.upper(def.name), 28, def.glow:Lerp(Color3.new(1, 1, 1), 0.3), 2, 3)
		name.LayoutOrder = 2
		name.Size = UDim2.new(1, 0, 0, 32)
		local need = CardKit.bold(gui, "", 17, CardKit.WHITE, 2, 2)
		need.LayoutOrder = 3
		need.Size = UDim2.new(1, 0, 0, 20)
		return name, need, tag
	end

	local function addVisual(holder: Instance)
		if not holder:IsA("Model") or visuals[holder] then
			return
		end
		local id = holder:GetAttribute("MonsterId")
		local root = holder:WaitForChild("Root", 10)
		local def = typeof(id) == "string" and Config.GetSpaceMonster(id)
		if not (def and root and root:IsA("BasePart")) then
			return
		end
		local model = MonsterModel.Build(def.id, def.scale)
		local name, need, tag = makeLabel(model, def)
		model.Parent = localFolder
		local rig = MonsterModel.Rig(model)
		-- Hemen yerine koy: model (0,0,0)'da kuruldu, orası 1. üssün içi
		rig:Pose(root.CFrame, 0, { sway = 1, rate = 1, grab = 0, roar = 0 })
		visuals[holder] = {
			holder = holder,
			root = root,
			def = def,
			model = model,
			rig = rig,
			cf = root.CFrame,
			grab = 0,
			roar = 0,
			sway = 1,
			rate = 1,
			state = "idle",
			stateAt = os.clock(),
			label = name,
			needLabel = need,
			tag = tag,
		}
	end

	local function removeVisual(holder: Instance)
		local v = visuals[holder :: Model]
		if v then
			v.model:Destroy()
			visuals[holder :: Model] = nil
		end
	end

	local monstersFolder: Instance? = nil
	local function watchZone()
		local zone = workspace:WaitForChild("SpaceZone", 60)
		local folder = zone and zone:WaitForChild("Monsters", 30)
		if not folder then
			return
		end
		monstersFolder = folder
		for _, child in folder:GetChildren() do
			task.spawn(addVisual, child)
		end
		table.insert(connections, folder.ChildAdded:Connect(function(child)
			task.spawn(addVisual, child)
		end))
		table.insert(connections, folder.ChildRemoved:Connect(removeVisual))
	end
	task.spawn(watchZone)

	-- ─── Jetpack (uzaydaki herkes) ──────────────────────────────────────
	local jetpacks: { [Player]: Model } = {}

	local function buildJetpack(character: Model): Model?
		local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		if not (torso and torso:IsA("BasePart")) then
			return nil
		end
		local pack = Instance.new("Model")
		pack.Name = "SpaceJetpack"
		local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?, material: Enum.Material?): BasePart
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.Color = color
			p.Material = material or Enum.Material.SmoothPlastic
			if shape then
				p.Shape = shape
			end
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			p.CastShadow = false
			p.CFrame = torso.CFrame * offset
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = torso
			weld.Part1 = p
			weld.Parent = p
			p.Parent = pack
			return p
		end
		piece("Pack", Vector3.new(1.7, 1.7, 0.7), CFrame.new(0, 0.1, 0.8), Color3.fromRGB(200, 208, 222))
		for _, x in { -0.55, 0.55 } do
			piece("Tank", Vector3.new(1.8, 0.8, 0.8), CFrame.new(x, 0, 1.25) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(230, 70, 70), Enum.PartType.Cylinder)
			local nozzle = piece("Nozzle", Vector3.new(0.5, 0.6, 0.6), CFrame.new(x, -1.05, 1.25) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 76, 90), Enum.PartType.Cylinder)
			local a = Instance.new("Attachment")
			a.Position = Vector3.new(-0.3, 0, 0)
			a.Parent = nozzle
			local flame = Instance.new("ParticleEmitter")
			flame.Texture = "rbxasset://textures/particles/fire_main.dds"
			flame.Color = ColorSequence.new(Color3.fromRGB(120, 210, 255), Color3.fromRGB(255, 140, 60))
			flame.LightEmission = 1
			flame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0) })
			flame.Transparency = NumberSequence.new(0.1, 1)
			flame.Lifetime = NumberRange.new(0.2, 0.35)
			flame.Speed = NumberRange.new(10, 14)
			flame.EmissionDirection = Enum.NormalId.Left
			flame.Rate = 60
			flame.Parent = a
		end
		pack.Parent = character
		return pack
	end

	local function refreshJetpack(other: Player)
		local want = other:GetAttribute("InSpace") == true or other:GetAttribute("SpaceGrabbed") ~= nil
		local character = other.Character
		local pack = jetpacks[other]
		if pack and (not want or not pack.Parent or pack.Parent ~= character) then
			pack:Destroy()
			jetpacks[other] = nil
			pack = nil
		end
		if want and not pack and character then
			local built = buildJetpack(character)
			if built then
				jetpacks[other] = built
			end
		end
	end

	local function watchPlayer(other: Player)
		table.insert(connections, other:GetAttributeChangedSignal("InSpace"):Connect(function()
			refreshJetpack(other)
		end))
		table.insert(connections, other.CharacterAdded:Connect(function()
			jetpacks[other] = nil
		end))
		refreshJetpack(other)
	end
	for _, other in Players:GetPlayers() do
		watchPlayer(other)
	end
	table.insert(connections, Players.PlayerAdded:Connect(watchPlayer))
	table.insert(connections, Players.PlayerRemoving:Connect(function(other)
		jetpacks[other] = nil
	end))

	-- ─── Uçuş ───────────────────────────────────────────────────────────
	local flying = false
	local flyVelocity = Vector3.zero
	local flyAtt: Attachment? = nil
	local flyVel: LinearVelocity? = nil
	local flyAlign: AlignOrientation? = nil
	local grade: ColorCorrectionEffect? = nil

	local function humanoidOf(): (Humanoid?, BasePart?)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and root and root:IsA("BasePart") then
			return humanoid, root
		end
		return nil, nil
	end

	local flyPose: FlyPose.Handle? = nil

	local function setFlying(on: boolean)
		if on == flying then
			return
		end
		flying = on
		local humanoid, root = humanoidOf()
		if on and humanoid and root then
			-- Güverteden koşarak (bobinle) çıkan uzay hızından hızlı başlamasın
			flyVelocity = root.AssemblyLinearVelocity
			if flyVelocity.Magnitude > mySpeed() then
				flyVelocity = flyVelocity.Unit * mySpeed()
			end
			local att = Instance.new("Attachment")
			att.Name = "SpaceFlyAtt"
			att.Parent = root
			local lv = Instance.new("LinearVelocity")
			lv.Name = "SpaceFly"
			lv.Attachment0 = att
			lv.RelativeTo = Enum.ActuatorRelativeTo.World
			lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
			lv.MaxForce = math.huge
			lv.VectorVelocity = flyVelocity
			lv.Parent = root
			local align = Instance.new("AlignOrientation")
			align.Name = "SpaceAlign"
			align.Mode = Enum.OrientationAlignmentMode.OneAttachment
			align.Attachment0 = att
			align.MaxTorque = math.huge
			align.Responsiveness = 16
			align.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z))
			align.Parent = root
			flyAtt, flyVel, flyAlign = att, lv, align
			humanoid.PlatformStand = true
			-- Heykel gibi durmasın: uçuş animasyonu (süzülme / süper kahraman)
			if flyPose then
				flyPose:Destroy()
			end
			flyPose = FlyPose.Start(humanoid.Parent :: Model)
			if not grade then
				local g = Instance.new("ColorCorrectionEffect")
				g.Name = "SpaceGrade"
				g.TintColor = Color3.fromRGB(218, 224, 255)
				g.Contrast = 0.08
				g.Saturation = 0.1
				g.Parent = Lighting
				grade = g
			end
		else
			if flyVel then
				flyVel:Destroy()
			end
			if flyAlign then
				flyAlign:Destroy()
			end
			if flyAtt then
				flyAtt:Destroy()
			end
			flyAtt, flyVel, flyAlign = nil, nil, nil
			if flyPose then
				flyPose:Destroy()
				flyPose = nil
			end
			if humanoid then
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			end
			if grade then
				grade:Destroy()
				grade = nil
			end
		end
	end

	local function inputVector(): Vector3
		local camera = workspace.CurrentCamera
		if not camera then
			return Vector3.zero
		end
		--[[
			Giriş üç kaynaktan, ilk dolu olan: oyunun kontrol modülü (joystick
			dahil), klavye (WASD / oklar), Humanoid.MoveDirection. Eskiden
			yalnızca ilki okunuyordu; boş gelince karakter sadece Space/C ile
			yukarı-aşağı gidiyordu.
		]]
		local move = Vector3.zero
		if controls then
			local ok, mv = pcall(function()
				return controls:GetMoveVector()
			end)
			if ok and typeof(mv) == "Vector3" then
				move = mv
			end
		end
		if move.Magnitude < 0.05 and not UserInputService:GetFocusedTextBox() then
			local function key(a: Enum.KeyCode, b: Enum.KeyCode): number
				return if UserInputService:IsKeyDown(a) or UserInputService:IsKeyDown(b) then 1 else 0
			end
			move = Vector3.new(key(Enum.KeyCode.D, Enum.KeyCode.Right) - key(Enum.KeyCode.A, Enum.KeyCode.Left), 0,
				key(Enum.KeyCode.S, Enum.KeyCode.Down) - key(Enum.KeyCode.W, Enum.KeyCode.Up))
		end

		-- Yatay hareket kameranın yatay yönüne göre (eğimi yok): W hep ileri gider
		local cam = camera.CFrame
		local look = cam.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		flatLook = if flatLook.Magnitude > 0.01 then flatLook.Unit else Vector3.new(0, 0, -1)
		local flatRight = Vector3.new(cam.RightVector.X, 0, cam.RightVector.Z)
		flatRight = if flatRight.Magnitude > 0.01 then flatRight.Unit else Vector3.new(1, 0, 0)
		local dir = flatRight * move.X + flatLook * -move.Z
		-- Kamera belirgin yukarı/aşağı bakıyorsa ileri basınca o yöne de süzülür
		if math.abs(look.Y) > 0.45 and move.Z ~= 0 then
			dir += Vector3.yAxis * look.Y * -move.Z
		end
		local humanoid = humanoidOf()
		if dir.Magnitude < 0.05 and humanoid and humanoid.MoveDirection.Magnitude > 0.05 then
			dir = humanoid.MoveDirection
		end
		local up = (humanoid and humanoid.Jump) or UserInputService:IsKeyDown(Enum.KeyCode.Space)
			or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
		local down = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.C)
			or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonB)
		if up then
			dir += Vector3.yAxis
		end
		if down then
			dir -= Vector3.yAxis
		end
		if dir.Magnitude > 1 then
			dir = dir.Unit
		end
		return dir
	end

	local function stepFlight(dt: number, root: BasePart)
		local speed = mySpeed()
		local boosting = os.clock() < boostUntil
		if boosting then
			local jet = jetParams()
			speed *= if jet then jet.mul else 1
		end
		local move = inputVector()
		-- Boost sırasında tuşa basılmasa da ileri atılıyor (kameranın yatay yönü)
		if boosting and move.Magnitude < 0.1 then
			local camera = workspace.CurrentCamera
			local look = if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1)
			local flat = Vector3.new(look.X, 0, look.Z)
			move = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
		end
		local target = move * speed
		local k = 1 - math.exp(-s.FlyAccel * (if boosting then 2.5 else 1) * dt)
		flyVelocity = flyVelocity:Lerp(target, k)

		-- Sınır: dışarı doğru hız sıfırlanıyor, dışarıdaysa içeri itiliyor
		local pos = root.Position
		local lo, hi = s.BoundsMin, s.BoundsMax
		local v = flyVelocity
		local function axis(p: number, vv: number, a: number, b: number): number
			if p < a then
				return math.max(vv, (a - p) * 2)
			elseif p > b then
				return math.min(vv, (b - p) * 2)
			end
			return vv
		end
		-- Güvertenin önü dışında geminin çevresinden dolaşılmasın (duvar hizası)
		local deckLo, deckHi = SpaceField.DeckBox()
		local zMax = if pos.X > deckLo.X and pos.X < deckHi.X and pos.Y < deckHi.Y then hi.Z + 40 else SpaceField.WallOuterZ() - 3
		v = Vector3.new(axis(pos.X, v.X, lo.X, hi.X), axis(pos.Y, v.Y, lo.Y, hi.Y), axis(pos.Z, v.Z, lo.Z, zMax))
		flyVelocity = v
		if flyVel then
			flyVel.VectorVelocity = v
		end

		-- Yön: gidilen yöne dön, hızlanınca öne eğil (süzülme pozu)
		if flyAlign then
			local flat = Vector3.new(v.X, 0, v.Z)
			local look = if flat.Magnitude > 2 then flat.Unit else nil
			if not look then
				local camera = workspace.CurrentCamera
				local cl = if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1)
				look = Vector3.new(cl.X, 0, cl.Z)
				if look.Magnitude < 0.01 then
					look = Vector3.new(0, 0, -1)
				end
				look = look.Unit
			end
			local lean = math.clamp(v.Magnitude / math.max(1, speed), 0, 1)
			-- Dururken dik süzülür, hızlanınca ~45° öne yatar (kol ileride, klip FlyPose)
			local pitch = -math.rad(45) * lean + math.clamp(v.Y / math.max(1, speed), -1, 1) * math.rad(20)
			if flyPose then
				flyPose:SetBlend(lean)
			end
			local bob = math.sin(os.clock() * 2.4) * math.rad(3)
			flyAlign.CFrame = CFrame.lookAt(Vector3.zero, look :: Vector3) * CFrame.Angles(pitch + bob, 0, 0)
		end
	end

	-- ─── Yakalanma ve fırlatma ──────────────────────────────────────────
	type Grab = { visual: Visual?, t0: number, hold: number, throw: number, from: Vector3?, last: Vector3? }
	local grab: Grab? = nil

	local function tryBoost()
		local jet = jetParams()
		local now = os.clock()
		if not (jet and flying and not grab) or now < boostReadyAt then
			return
		end
		boostUntil = now + jet.duration
		boostCooldown = jet.cooldown
		boostReadyAt = now + jet.cooldown
		effects.Shake(0.35, 0.25)
		local camera = workspace.CurrentCamera
		if camera then
			local base = camera.FieldOfView
			TweenService:Create(camera, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base + 14 }):Play()
			task.delay(jet.duration, function()
				TweenService:Create(camera, TweenInfo.new(0.4), { FieldOfView = base }):Play()
			end)
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			SoundFX.GearSound("GearZap", root.Position)
			local flame = Instance.new("ParticleEmitter")
			flame.Name = "JetBoostFlame"
			flame.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 90, 30))
			flame.LightEmission = 1
			flame.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0) })
			flame.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
			flame.Lifetime = NumberRange.new(0.25, 0.45)
			flame.Speed = NumberRange.new(8, 14)
			flame.Rate = 90
			flame.EmissionDirection = Enum.NormalId.Back
			flame.Parent = root
			task.delay(jet.duration, function()
				flame.Enabled = false
				task.wait(0.5)
				flame:Destroy()
			end)
		end
	end

	local function setBoostBinding(on: boolean)
		if on == boostBound then
			return
		end
		boostBound = on
		if on then
			ContextActionService:BindAction(BOOST_ACTION, function(_, state)
				if state == Enum.UserInputState.Begin then
					tryBoost()
				end
				return Enum.ContextActionResult.Sink
			end, true, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
			ContextActionService:SetTitle(BOOST_ACTION, "BOOST")
			ContextActionService:SetPosition(BOOST_ACTION, UDim2.new(1, -210, 1, -150))
		else
			ContextActionService:UnbindAction(BOOST_ACTION)
		end
	end

	--[[ Her karede: bağlama, gösterge. ]]
	local function stepBoostUi()
		local jet = jetParams()
		local show = flying and jet ~= nil and not grab
		setBoostBinding(show)
		if boostBar.frame.Visible ~= show then
			boostBar.frame.Visible = show
		end
		if not show then
			return
		end
		local now = os.clock()
		local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		if now < boostUntil then
			boostBar.set(1, "BOOSTING!")
		elseif now < boostReadyAt then
			boostBar.set(1 - (boostReadyAt - now) / math.max(0.1, boostCooldown), string.format("BOOST %ds", math.ceil(boostReadyAt - now)))
		else
			boostBar.set(1, if touch then "BOOST READY" else "BOOST READY [Q]")
		end
	end

	local function stepGrab(root: BasePart, humanoid: Humanoid)
		local g = grab :: Grab
		local now = os.clock()
		local t = now - g.t0
		humanoid.PlatformStand = true
		local pos: Vector3
		local rot: CFrame
		if t < g.hold then
			local handCf = if g.visual then g.visual.rig:HandCFrame() else root.CFrame
			local shake = Vector3.new(math.sin(now * 38), math.sin(now * 31), math.cos(now * 35)) * 0.35
			pos = handCf.Position + Vector3.new(0, -0.6, 0) + shake
			rot = CFrame.Angles(math.sin(now * 20) * 0.25, now * 2, math.cos(now * 17) * 0.25)
			g.from = pos
		else
			local u = math.clamp((t - g.hold) / g.throw, 0, 1)
			pos = SpaceField.ThrowPath(g.from or root.Position, u)
			rot = CFrame.Angles(u * 14, u * 5, u * 9)
			if u >= 1 then
				grab = nil
				root.AssemblyLinearVelocity = Vector3.zero
				root.CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, 1))
				humanoid.PlatformStand = false
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				effects.Shake(1.6, 0.4)
				effects.Flash(Color3.fromRGB(255, 255, 255), 0.35, 0.4)
				SoundFX.GearSound("GearBlast", pos)
				yell("THROWN BACK TO THE SHIP!", Color3.fromRGB(255, 190, 90), 2.2)
				return
			end
		end
		local last = g.last or pos
		root.CFrame = CFrame.new(pos) * rot
		root.AssemblyLinearVelocity = (pos - last) / math.max(1 / 240, 1 / 60)
		root.AssemblyAngularVelocity = Vector3.zero
		if flyVel then
			flyVel.VectorVelocity = root.AssemblyLinearVelocity
		end
		g.last = pos
	end

	-- ─── Her kare ───────────────────────────────────────────────────────
	local clock = 0
	local lastCarrying: boolean? = nil
	local shownHud = false

	local function poseFor(v: Visual, dt: number, now: number)
		local state = (v.holder:GetAttribute("State") :: string?) or "idle"
		if state ~= v.state then
			v.state = state
			v.stateAt = now
		end
		local since = now - v.stateAt
		local gGoal, rGoal, swayGoal, rateGoal = 0, 0, 1, 1
		if state == "wake" then
			rGoal, swayGoal, rateGoal = 1, 0.5, 3
		elseif state == "chase" then
			gGoal, rGoal, swayGoal, rateGoal = 0.35, 0.35, 1.6, 2.3
		elseif state == "grab" then
			gGoal, rGoal, swayGoal, rateGoal = 1, 0.6, 0.6, 3
		elseif state == "throw" then
			-- Önce geriye kurup sonra öne savuruyor
			gGoal = if since < 0.22 then 1.5 else -0.5
			rGoal, swayGoal, rateGoal = 0.9, 0.4, 2
		elseif state == "return" then
			swayGoal, rateGoal = 1.2, 1.6
		end
		local k = 1 - math.exp(-(if state == "throw" then 18 else 7) * dt)
		v.grab += (gGoal - v.grab) * k
		v.roar += (rGoal - v.roar) * k
		v.sway += (swayGoal - v.sway) * k
		v.rate += (rateGoal - v.rate) * k
		return state
	end

	table.insert(connections, RunService.RenderStepped:Connect(function(dt)
		clock += dt
		local now = os.clock()
		local humanoid, root = humanoidOf()
		local camera = workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero

		-- Canavarlar
		for _, v in visuals do
			local state = poseFor(v, dt, now)
			local target = v.root.CFrame
			local far = (target.Position - camPos).Magnitude > 1100
			v.cf = v.cf:Lerp(target, 1 - math.exp(-10 * dt))
			--[[
				Model (0,0,0)'da kuruluyor; uzaktakiler de EN AZ bir kez ve sonra
				saniyede bir çizilmeli. Eskiden hiç çizilmeyen uzak canavar
				1. üssün içinde duruyordu (Void Leviathan gemide görünüyordu).
			]]
			if far then
				if v.posedAt and now - v.posedAt < 1 then
					continue
				end
			end
			v.posedAt = now
			local lift = if state == "idle" then 0 else (2 + math.sin(clock * 2.2) * 1.2) * v.def.scale
			local shake = if state == "wake" or state == "grab" then Vector3.new(math.sin(clock * 47), 0, math.cos(clock * 41)) * 0.35 * v.def.scale else Vector3.zero
			local breathe = math.sin(clock * 1.4) * 0.15 * v.def.scale
			v.rig:Pose(v.cf + Vector3.new(0, lift + breathe, 0) + shake, clock, { sway = v.sway, rate = v.rate, grab = v.grab, roar = v.roar })

			-- Etiket
			local need = v.def.need
			local ok = trainedSpeed() >= need
			local text = string.format("Needs %d Space Speed  ·  up to %s", need, bestRarity(v.def))
			if v.needLabel.Text ~= text then
				v.needLabel.Text = text
			end
			local color = if ok then Color3.fromRGB(120, 255, 130) else Color3.fromRGB(255, 110, 110)
			if v.needLabel.TextColor3 ~= color then
				v.needLabel.TextColor3 = color
			end
			local tag = if state == "idle" then "zzz" elseif state == "return" then "..." else "!!"
			if v.tag.Text ~= tag then
				v.tag.Text = tag
				v.tag.TextColor3 = if tag == "!!" then Color3.fromRGB(255, 80, 90) else Color3.fromRGB(200, 200, 255)
			end
		end

		if not (humanoid and root) then
			return
		end

		-- Yakalanmışken her şeyi fırlatma yönetiyor
		if grab then
			if not flying then
				setFlying(true)
			end
			stepGrab(root, humanoid)
			if not grab then
				setFlying(false)
			end
			return
		end

		local inSpace = SpaceField.InSpace(root.Position) and humanoid.Health > 0
		setFlying(inSpace)
		stepBoostUi()
		if flying then
			stepFlight(dt, root)
		end

		-- Gösterge: uzayda ya da güvertede
		local onDeck = SpaceField.InDeck(root.Position)
		-- Görev kartı yalnızca öğretici sürerken (oyuncu yolu öğrendikten sonra kalabalık yapıyordu)
		local step = player:GetAttribute("TutorialStep")
		local learning = typeof(step) == "number" and step < #Config.Tutorial
		local show = (inSpace or onDeck) and learning
		if show ~= shownHud then
			shownHud = show
			hud.Visible = show
		end
		if show then
			local carrying = player:GetAttribute("SpaceCarry") == true
			local speed = trainedSpeed()
			local best = Config.BestSpaceMonster(speed)
			local goal: Vector3
			if carrying then
				goal = SpaceField.DeckCenter()
			else
				goal = best.position
			end
			arrow.Rotation = bearingTo(goal, root.Position)
			speedText.Text = string.format("SPACE SPEED %.1f", speed)
			if carrying ~= lastCarrying then
				lastCarrying = carrying
				if carrying then
					objective.Text = "FLY BACK TO THE LAUNCH BAY!"
					CardKit.tintCard(card, Color3.fromRGB(210, 60, 80))
				else
					objective.Text = string.format("Fly to %s and steal a crewmate", best.name)
					CardKit.tintCard(card, Color3.fromRGB(46, 96, 210))
				end
			elseif not carrying then
				local text = string.format("Fly to %s and steal a crewmate", best.name)
				if objective.Text ~= text then
					objective.Text = text
				end
			end
		end

		-- Tehlike kenarı: beni kovalayan canavar yakınsa (kart gizliyken de)
		if not (inSpace or onDeck) then
			dangerStroke.Transparency = 1
			return
		end
		local nearest = math.huge
		for _, v in visuals do
			if v.state == "chase" and v.holder:GetAttribute("Target") == player.UserId then
				nearest = math.min(nearest, (v.cf.Position - root.Position).Magnitude - 6 * v.def.scale)
			end
		end
		if nearest < 60 then
			local kk = 1 - math.max(0, nearest) / 60
			dangerStroke.Transparency = 1 - (0.25 + 0.55 * kk) * (0.6 + 0.4 * math.abs(math.sin(clock * (6 + 8 * kk))))
		else
			dangerStroke.Transparency = 1
		end
	end))

	table.insert(connections, player.CharacterAdded:Connect(function()
		grab = nil
		flying = false
		flyAtt, flyVel, flyAlign = nil, nil, nil
		flyPose = nil
		if grade then
			grade:Destroy()
			grade = nil
		end
	end))

	-- ─── Sunucu olayları ────────────────────────────────────────────────
	table.insert(connections, Net.Get("SpaceFX").OnClientEvent:Connect(function(kind, a, b, c)
		if kind == "roar" and typeof(a) == "string" then
			local def = Config.GetSpaceMonster(a)
			local _, root = humanoidOf()
			local mine = b == player.UserId
			local near = false
			if def and root then
				near = (def.position - root.Position).Magnitude < 260
			end
			if mine or near then
				effects.Shake(if mine then 1.8 else 0.8, 0.8)
				SoundFX.Alarm()
			end
			if mine and def then
				yell(string.format("%s WOKE UP! FLY!", string.upper(def.name)), Color3.fromRGB(255, 80, 110), 2.4)
			end
		elseif kind == "grab" and typeof(a) == "string" and typeof(b) == "number" and typeof(c) == "number" then
			local visual: Visual? = nil
			for _, v in visuals do
				if v.def.id == a then
					visual = v
				end
			end
			grab = { visual = visual, t0 = os.clock(), hold = b, throw = c }
			effects.Shake(2.2, b)
			effects.Flash(Color3.fromRGB(255, 60, 80), 0.45, 0.5)
			SoundFX.Deny()
			local def = Config.GetSpaceMonster(a)
			yell(string.format("%s GOT YOU!", string.upper(if def then def.name else "IT")), Color3.fromRGB(255, 70, 90), b + 0.4)
		elseif kind == "lunge" and typeof(a) == "string" then
			local def = Config.GetSpaceMonster(a)
			effects.Shake(1.2, 0.5)
			yell(string.format("%s LUNGES!", string.upper(if def then def.name else "IT")), Color3.fromRGB(255, 90, 90), 1.2)
		elseif kind == "delivered" then
			effects.Flash(Color3.fromRGB(90, 255, 120), 0.45, 0.6)
			SoundFX.Success()
			yell(string.format("STOLE %s!", string.upper(tostring(a))), Color3.fromRGB(120, 255, 130), 2.4)
		end
	end))

	return {
		Destroy = function()
			for _, conn in connections do
				conn:Disconnect()
			end
			setFlying(false)
			for _, pack in jetpacks do
				pack:Destroy()
			end
			localFolder:Destroy()
			hud:Destroy()
			shout:Destroy()
			danger:Destroy()
			local _ = monstersFolder
		end,
	}
end

return SpaceFX
