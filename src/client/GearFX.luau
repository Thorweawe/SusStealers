--!strict
--[[
	Ekipmanın canlı tarafı: kol animasyonları, vuruş efektleri, savrulma.

	═══ ANİMASYON ══════════════════════════════════════════════════════════

	Hazır animasyon varlığı (yüklenmiş Animation) yok; yüklemek hesap ve
	izin ister. Onun yerine klipler çalışma anında KeyframeSequence olarak
	kuruluyor ve KeyframeSequenceProvider'a kaydediliyor: dönen geçici
	kimlikle Roblox'un kendi Animator'ı oynatıyor. Öncelik Action4, yani
	aleti tutma pozunun üstüne biniyor; bitince tutuş pozu geri geliyor.

	Neden eklemleri elle döndürmüyoruz: iki yol denendi. Motor6D.Transform'u
	Animator bizden sonra yeniden yazıyor; yeni avatarlarda eklem
	AnimationConstraint ve çerçevesini elle değiştirmek kolu oynatmıyor.
	Animator ise iki eklem türünde de çalışıyor.

	Geçici kimlik yalnızca bu istemcide geçerli ve oynatma ağdan GİTMİYOR.
	Bu yüzden sunucu her kullanımı herkese duyuruyor ("use") ve her
	istemci o karakterde klibi kendisi oynatıyor. Kullanan oyuncu kendi
	animasyonunu beklemeden, tıkladığı anda başlatıyor (sunucunun yankısını
	yok sayıyor).

	  Slap Glove       — kol sağa açılıp soldan tokat gibi savruluyor
	  Stun Gun         — ateşte kol yukarı tepiyor, uçtan hedefe mavi ışın
	  Ghost Serum      — şişe havaya kalkıyor, yeşil duman, karakter solar
	  Emergency Button — kol yükselip düğmeye vuruyor, kırmızı şok halkası

	═══ SAVRULMA ═══════════════════════════════════════════════════════════

	Karakterin fiziği kendi istemcisinde; sunucu "hit" deyince VURULANIN
	istemcisi kendini savuruyor (PlatformStand + hız, sersemlik bitince
	ayağa kalkıyor) ya da şok tabancasında donuyor (kök parça kısa süre
	sabit). Diğer istemciler yalnızca efekti çiziyor.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)

local SoundFX = require(script.Parent.SoundFX)

local GearFX = {}

export type Handle = {
	Destroy: () -> (),
}

type Shaker = { Shake: (strength: number, duration: number) -> (), Flash: (color: Color3, strength: number, duration: number) -> () }

local player = Players.LocalPlayer

-- ─── Kol animasyonları ─────────────────────────────────────────────────────

--[[
	Anahtar kareler: { t (0..1), yaw (derece), pitch (derece) }.
	Kolun gövdeye göre yönü (R15 omuz eklemi): pitch 0 aşağı sarkık, 90
	önde yatay (aleti tutarken olduğu gibi), 180 yukarıda; yaw + sola
	(gövdenin önünden karşıya), - sağa. `waist`: gövde kolun yaw'ının bu
	oranı kadar dönüyor (tokatta omuzdan savurma).
]]
type Key = { number }
type Clip = { duration: number, keys: { Key }, waist: number }

local CLIPS: { [string]: Clip } = {
	SlapGlove = {
		duration = 0.42,
		keys = { { 0, 0, 90 }, { 0.32, -80, 100 }, { 0.52, 75, 82 }, { 0.62, 76, 82 }, { 1, 0, 90 } },
		waist = 0.35,
	},
	StunGun = {
		duration = 0.32,
		keys = { { 0, 0, 90 }, { 0.18, 0, 118 }, { 1, 0, 90 } },
		waist = 0,
	},
	GhostSerum = {
		duration = 0.9,
		keys = { { 0, 0, 90 }, { 0.3, 25, 155 }, { 0.75, 25, 155 }, { 1, 0, 90 } },
		waist = 0,
	},
	EmergencyButton = {
		duration = 0.6,
		keys = { { 0, 0, 90 }, { 0.4, 0, 170 }, { 0.55, 0, 45 }, { 0.7, 0, 45 }, { 1, 0, 90 } },
		waist = 0,
	},
}

--[[
	Klibi KeyframeSequence'a çevirip kaydeder; kimlik önbellekte. Poz
	ağacı R15 hiyerarşisi: kök > alt gövde > üst gövde (bel) > sağ üst kol
	(omuz). Ağırlığı 0 olan pozlar yalnızca yolu taşıyor, eklemi
	etkilemiyor.
]]
local registered: { [string]: string } = {}

local function animationId(gearId: string): string?
	local cached = registered[gearId]
	if cached then
		return cached
	end
	local clip = CLIPS[gearId]
	if not clip then
		return nil
	end
	local kfs = Instance.new("KeyframeSequence")
	kfs.Priority = Enum.AnimationPriority.Action4
	kfs.Loop = false
	for _, k in clip.keys do
		local frame = Instance.new("Keyframe")
		frame.Time = k[1] * clip.duration
		local function pose(name: string, parent: Instance, weight: number, cf: CFrame?): Pose
			local p = Instance.new("Pose")
			p.Name = name
			p.Weight = weight
			p.CFrame = cf or CFrame.identity
			p.EasingStyle = Enum.PoseEasingStyle.Cubic
			p.EasingDirection = Enum.PoseEasingDirection.InOut
			p.Parent = parent
			return p
		end
		local root = pose("HumanoidRootPart", frame, 0)
		local lower = pose("LowerTorso", root, 0)
		local upper = pose("UpperTorso", lower, if clip.waist ~= 0 then 1 else 0,
			CFrame.Angles(0, math.rad(k[2] * clip.waist), 0))
		pose("RightUpperArm", upper, 1, CFrame.Angles(0, math.rad(k[2]), 0) * CFrame.Angles(math.rad(k[3]), 0, 0))
		frame.Parent = kfs
	end
	local ok, id = pcall(function()
		return game:GetService("KeyframeSequenceProvider"):RegisterKeyframeSequence(kfs)
	end)
	if not ok or typeof(id) ~= "string" then
		return nil
	end
	registered[gearId] = id
	return id
end

-- Animator -> alet -> yüklü iz (karakter gidince anahtar da gidiyor)
local tracks: { [Animator]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any

local function play(character: Model?, gearId: string, slow: number?)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not (animator and humanoid and humanoid.RigType == Enum.HumanoidRigType.R15) then
		return
	end
	local id = animationId(gearId)
	if not id then
		return
	end
	local list = tracks[animator]
	if not list then
		list = {}
		tracks[animator] = list
	end
	local track = list[gearId]
	if not track then
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, loaded = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if not ok then
			return
		end
		track = loaded
		list[gearId] = loaded
	end
	local t = track :: AnimationTrack
	t:Play(0.05, 1, 1 / (slow or 1))
end

--[[ Bir karakterde aletin kol animasyonunu oynatır. `slow` > 1 yavaşlatır (önizleme). ]]
function GearFX.Play(character: Model, gearId: string, slow: number?)
	play(character, gearId, slow)
end

-- ─── Efekt parçaları ────────────────────────────────────────────────────────

local fxFolder: Folder? = nil
local function folder(): Folder
	if not fxFolder or not fxFolder.Parent then
		local f = Instance.new("Folder")
		f.Name = "GearEffects"
		f.Parent = workspace
		fxFolder = f
	end
	return fxFolder :: Folder
end

local function fxPart(size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = size
	p.CFrame = cf
	if shape then
		p.Shape = shape
	end
	p.Parent = folder()
	return p
end

local function rootOf(character: Model): BasePart?
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function headOf(character: Model): BasePart?
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return rootOf(character)
end

--[[ Karakterin başında beliren, yükselip sönen çizgi roman yazısı. ]]
local function popWord(character: Model, text: string, color: Color3)
	local head = headOf(character)
	if not head then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "GearWord"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(160, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Parent = folder()
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0
	label.Rotation = math.random(-12, 12)
	label.Text = text
	label.Parent = gui
	TweenService:Create(label, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 1) }):Play()
	TweenService:Create(gui, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffsetWorldSpace = Vector3.new(0, 4.2, 0) }):Play()
	task.delay(0.45, function()
		TweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	Debris:AddItem(gui, 0.85)
end

--[[ Noktadan saçılan kısa parıltı (Roblox'un yerleşik parçacık dokusu). ]]
local function burst(at: Vector3, color: Color3, count: number, speed: number)
	local holder = Instance.new("Attachment")
	holder.WorldPosition = at
	holder.Parent = workspace.Terrain
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.8
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.3, 0.55)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 4
	e.Rate = 0
	e.Parent = holder
	e:Emit(count)
	Debris:AddItem(holder, 1)
end

--[[ Karakterin elindeki aletin ucu (ışının çıktığı yer). ]]
local function toolTip(character: Model): Vector3?
	local tool = character:FindFirstChildOfClass("Tool")
	local tip = tool and tool:FindFirstChild("Tip")
	if tip and tip:IsA("BasePart") then
		return tip.Position
	end
	local root = rootOf(character)
	return if root then root.Position + root.CFrame.LookVector * 2 + Vector3.new(0, 1, 0) else nil
end

--[[ Şok ışını: uçtan hedefe zikzak üç parça, çeyrek saniyede sönüyor. ]]
local function zapBeam(from: Vector3, to: Vector3)
	local points = { from }
	local segments = 4
	for i = 1, segments - 1 do
		local p = from:Lerp(to, i / segments)
		table.insert(points, p + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.4)
	end
	table.insert(points, to)
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local length = (b - a).Magnitude
		local seg = fxPart(Vector3.new(0.22, 0.22, length), CFrame.lookAt((a + b) / 2, b), Color3.fromRGB(120, 210, 255))
		TweenService:Create(seg, TweenInfo.new(0.28), { Transparency = 1, Size = Vector3.new(0.05, 0.05, length) }):Play()
		Debris:AddItem(seg, 0.3)
	end
end

--[[ Acil durum düğmesi: yerde büyüyen kırmızı şok halkası ve parlama. ]]
local function shockRing(at: Vector3, radius: number)
	local ring = fxPart(Vector3.new(0.4, 2, 2), CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 60, 70), Enum.PartType.Cylinder)
	ring.Transparency = 0.15
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.4, radius * 2, radius * 2), Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 0.5)
	local flash = fxPart(Vector3.new(3, 3, 3), CFrame.new(at + Vector3.new(0, 2, 0)), Color3.fromRGB(255, 200, 120), Enum.PartType.Ball)
	flash.Transparency = 0.2
	TweenService:Create(flash, TweenInfo.new(0.35), { Size = Vector3.new(12, 12, 12), Transparency = 1 }):Play()
	Debris:AddItem(flash, 0.4)
end

--[[ Sersem yıldızları: başın çevresinde dönen sarı noktalar. ]]
local function dizzy(character: Model, seconds: number, color: Color3)
	local head = headOf(character)
	if not head then
		return
	end
	local stars: { Part } = {}
	for _ = 1, 3 do
		table.insert(stars, fxPart(Vector3.new(0.4, 0.4, 0.4), head.CFrame, color, Enum.PartType.Ball))
	end
	local started = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if t > seconds or not head.Parent then
			conn:Disconnect()
			for _, s in stars do
				s:Destroy()
			end
			return
		end
		for i, s in stars do
			local a = t * 6 + i * (math.pi * 2 / 3)
			s.CFrame = CFrame.new(head.Position + Vector3.new(math.cos(a) * 1.2, 1.1, math.sin(a) * 1.2))
		end
	end)
end

-- ─── Kendi karakterin: savrulma, donma, görünmezlik ─────────────────────────

local stunToken = 0

local function knockSelf(gearId: string, from: Vector3, knock: number, stun: number, shaker: Shaker?)
	local character = player.Character
	local root = character and rootOf(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and root and humanoid) or humanoid.Health <= 0 then
		return
	end
	stunToken += 1
	local token = stunToken
	if shaker then
		shaker.Shake(if knock > 0 then 0.8 else 0.4, 0.35)
	end

	if knock <= 0 then
		-- Şok: olduğu yerde donuyor
		root.Anchored = true
		task.delay(stun, function()
			if token == stunToken and root.Parent then
				root.Anchored = false
			end
		end)
		return
	end

	-- Savrulma: vurandan uzağa, biraz yukarı, yuvarlanarak
	local away = root.Position - from
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.1 then
		away = -root.CFrame.LookVector
	end
	root.Anchored = false
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = away.Unit * knock + Vector3.new(0, knock * 0.45, 0)
	root.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit * 10
	task.delay(stun, function()
		if token == stunToken and humanoid.Parent then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

--[[
	Görünmezken oyuncu kendini tamamen kaybetmesin: sunucu herkese
	saydamlığı 1 yaptı, kendi ekranında gövde soluk görünüyor. Bu yerel
	değer ağdan gitmiyor; bitince sunucunun geri yazdığı değer geliyor.
]]
local function ghostSelf(character: Model, on: boolean)
	if not on then
		return
	end
	task.wait()
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency >= 1 and d.Parent and not d.Parent:IsA("Tool") then
			d.Transparency = 0.75
		elseif d:IsA("BasePart") and d.Parent and d.Parent:IsA("Tool") and d.Transparency >= 1 then
			d.Transparency = 0.5
		end
	end
end

-- ─── Başlatma ───────────────────────────────────────────────────────────────

function GearFX.Start(shaker: Shaker?): Handle
	local remote = Net.Get("GearFX")
	local connections: { RBXScriptConnection } = {}

	-- Kendi tıklaman: bekleme süresi dolduysa animasyon hemen (sunucu yankısını beklemeden)
	local lastLocal: { [string]: number } = {}
	local function watchTool(tool: Instance)
		if not tool:IsA("Tool") then
			return
		end
		local id = tool:GetAttribute("GearId")
		local def = if typeof(id) == "string" then Config.GetGear(id) else nil
		if not def or def.kind == "speed" or tool:GetAttribute("GearFXBound") then
			return
		end
		tool:SetAttribute("GearFXBound", true)
		local gearDef = def :: Config.GearDef
		tool.Activated:Connect(function()
			local now = os.clock()
			if now - (lastLocal[gearDef.id] or -math.huge) < (gearDef.cooldown or 1) - 0.15 then
				return
			end
			lastLocal[gearDef.id] = now
			play(player.Character, gearDef.id)
			if gearDef.kind == "slap" then
				local character = player.Character
				local root = character and rootOf(character)
				if root then
					SoundFX.GearSound("GearSwing", root.Position)
				end
			end
		end)
	end
	local function watchCharacter(character: Model)
		for _, child in character:GetChildren() do
			watchTool(child)
		end
		table.insert(connections, character.ChildAdded:Connect(watchTool))
	end
	if player.Character then
		watchCharacter(player.Character)
	end
	table.insert(connections, player.CharacterAdded:Connect(watchCharacter))

	table.insert(connections, remote.OnClientEvent:Connect(function(kind, character, a, b, c, d)
		if typeof(character) ~= "Instance" or not character:IsA("Model") then
			return
		end
		local mine = character == player.Character
		local root = rootOf(character)

		if kind == "use" and typeof(a) == "string" then
			local gearId = a
			if not mine then
				play(character, gearId)
				if gearId == "SlapGlove" and root then
					SoundFX.GearSound("GearSwing", root.Position)
				end
			end
			if gearId == "StunGun" then
				local from = toolTip(character)
				local target = if typeof(b) == "Instance" and b:IsA("Model") then b else nil
				local targetHead = target and headOf(target)
				if from then
					local to = if targetHead then targetHead.Position else (from + (if root then root.CFrame.LookVector else Vector3.zAxis) * 30)
					task.delay(0.05, zapBeam, from, to)
					SoundFX.GearSound("GearZap", from)
				end
			elseif gearId == "GhostSerum" then
				if root then
					task.delay(0.3, function()
						burst(root.Position, Color3.fromRGB(120, 255, 220), 30, 10)
						SoundFX.GearSound("GearPoof", root.Position)
					end)
				end
			elseif gearId == "EmergencyButton" then
				local def = Config.GetGear(gearId)
				if root and def then
					local ground = root.Position - Vector3.new(0, 2.8, 0)
					task.delay(0.3, function()
						shockRing(ground, def.range or 20)
						SoundFX.GearSound("GearBlast", root.Position)
						if mine and shaker then
							shaker.Shake(0.5, 0.3)
						end
					end)
				end
			end
		elseif kind == "hit" and typeof(a) == "string" and typeof(b) == "Vector3" then
			local gearId, from = a, b
			local knock = if typeof(c) == "number" then c else 0
			local stun = if typeof(d) == "number" then math.clamp(d, 0, 5) else 1
			local delay = if gearId == "SlapGlove" then 0.18 elseif gearId == "EmergencyButton" then 0.3 else 0.08
			task.delay(delay, function()
				local head = headOf(character)
				if gearId == "SlapGlove" then
					popWord(character, "SLAP!", Color3.fromRGB(255, 235, 90))
					if head then
						burst(head.Position, Color3.fromRGB(255, 250, 220), 20, 14)
						SoundFX.GearSound("GearSlap", head.Position)
					end
					dizzy(character, stun, Color3.fromRGB(255, 225, 80))
				elseif gearId == "StunGun" then
					popWord(character, "ZAP!", Color3.fromRGB(120, 210, 255))
					if head then
						burst(head.Position, Color3.fromRGB(120, 210, 255), 26, 12)
					end
					dizzy(character, stun, Color3.fromRGB(120, 210, 255))
				else
					popWord(character, "BOOM!", Color3.fromRGB(255, 90, 90))
					dizzy(character, stun, Color3.fromRGB(255, 225, 80))
				end
				if mine then
					knockSelf(gearId, from, knock, stun, shaker)
				end
			end)
		elseif kind == "cloak" then
			if mine then
				task.spawn(ghostSelf, character, a == true)
			elseif a == false and root then
				burst(root.Position, Color3.fromRGB(120, 255, 220), 18, 8)
			end
		end
	end))

	-- Klipler ilk kullanımda beklemesin: şimdiden kaydet
	task.spawn(function()
		for gearId in CLIPS do
			animationId(gearId)
		end
	end)

	return {
		Destroy = function()
			for _, conn in connections do
				conn:Disconnect()
			end
		end,
	}
end

return GearFX
