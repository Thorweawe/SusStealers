--!strict
--[[
	Ekipmanın canlı tarafı: kol animasyonları ve vuruş efektleri.

	═══ ANİMASYON ══════════════════════════════════════════════════════════

	Hazır animasyon varlığı (yüklenmiş Animation) yok; yüklemek hesap ve
	izin ister. Klipler anahtar kare tablosu (CLIPS) ve her karede kol ile
	bel ekleminin Transform'u elle yazılıyor (RunService.Stepped, Animator'dan
	sonra). KeyframeSequenceProvider denendi: yalnızca Studio'da çalışıyor.

	Oynatma yalnızca bu istemcide ve ağdan GİTMİYOR.
	Bu yüzden sunucu her kullanımı herkese duyuruyor ("use") ve her
	istemci o karakterde klibi kendisi oynatıyor. Kullanan oyuncu kendi
	animasyonunu beklemeden, tıkladığı anda başlatıyor (sunucunun yankısını
	yok sayıyor).

	  Slap Glove       — kol sağa açılıp soldan tokat gibi savruluyor
	  Stun Gun         — ateşte kol yukarı tepiyor, uçtan hedefe mavi ışın
	  Emergency Button — kol yükselip düğmeye vuruyor, kırmızı şok halkası

	═══ HEDEF: CANAVAR ═════════════════════════════════════════════════════

	2026-09-28: oyuncudan çalma kalktı, aletler uzaydaki canavarlara
	vuruyor. Sunucu vurulan her canavar için "monster" gönderiyor (canavarın
	holder modeli). Canavarın görseli istemcide ayrı kuruluyor, holder'ın
	kökü görünmez ve ayak hizasında: efektler gövde yüksekliğinde
	(anchorOf) çiziliyor; sersem yıldızları canavarla birlikte gidiyor.
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
	Klibi eklemlerin Transform'uyla oynatır (CarryPose ile aynı yol):
	RunService.Stepped Animator'dan SONRA çalışıyor, yani aleti tutma
	animasyonunun üstüne biniyor; klip bitince Animator kaldığı yerden
	sürüyor. Motor6D ve yeni avatarların AnimationConstraint eklemi, ikisinde
	de Transform var.

	2026-09-30: eskiden klip KeyframeSequenceProvider'a kaydedilip
	Animator'la oynatılıyordu. O kimlik yalnızca Studio'da çalışıyor;
	yayındaki oyunda tokat hiç görünmüyordu.
]]
type Active = { clip: Clip, startAt: number, duration: number }
local active: { [Model]: Active } = setmetatable({}, { __mode = "k" }) :: any
local stepping: RBXScriptConnection? = nil

local function smooth(u: number): number
	return u * u * (3 - 2 * u)
end

--[[ Klibin u (0..1) anındaki kol yönü: iki anahtar kare arası yumuşak geçiş. ]]
local function sample(clip: Clip, u: number): (number, number)
	local keys = clip.keys
	for index = 2, #keys do
		local k1, k0 = keys[index], keys[index - 1]
		if u <= k1[1] then
			local span = k1[1] - k0[1]
			local w = if span > 0 then smooth((u - k0[1]) / span) else 1
			return k0[2] + (k1[2] - k0[2]) * w, k0[3] + (k1[3] - k0[3]) * w
		end
	end
	local last = keys[#keys]
	return last[2], last[3]
end

local function jointOf(character: Model, partName: string, jointName: string): any
	local part = character:FindFirstChild(partName)
	local joint = part and part:FindFirstChild(jointName)
	if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
		return joint
	end
	return nil
end

local function step()
	local now = os.clock()
	for character, a in active do
		local u = (now - a.startAt) / a.duration
		if u >= 1 or not character.Parent then
			active[character] = nil
			continue
		end
		local yaw, pitch = sample(a.clip, u)
		local shoulder = jointOf(character, "RightUpperArm", "RightShoulder")
		if shoulder then
			shoulder.Transform = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
		end
		if a.clip.waist ~= 0 then
			local waist = jointOf(character, "UpperTorso", "Waist")
			if waist then
				waist.Transform = CFrame.Angles(0, math.rad(yaw * a.clip.waist), 0)
			end
		end
	end
	if next(active) == nil and stepping then
		stepping:Disconnect()
		stepping = nil
	end
end

local function play(character: Model?, gearId: string, slow: number?)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and humanoid and humanoid.RigType == Enum.HumanoidRigType.R15) then
		return
	end
	local clip = CLIPS[gearId]
	if not clip then
		return
	end
	active[character] = { clip = clip, startAt = os.clock(), duration = clip.duration * (slow or 1) }
	if not stepping then
		stepping = RunService.Stepped:Connect(step)
	end
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

--[[
	Efektin bağlanacağı parça ve onun üstündeki yükseklik. Canavarın
	(MonsterId niteliği) kökü görünmez ve ayak hizasında: gövdesi
	7 × ölçek yukarıda (SpaceService.bodyHeight ile aynı).
]]
local function anchorOf(model: Model): (BasePart?, number)
	local monsterId = model:GetAttribute("MonsterId")
	if typeof(monsterId) == "string" then
		local def = Config.GetSpaceMonster(monsterId)
		local scale = if def then def.scale else 1
		return model.PrimaryPart, 7 * scale
	end
	return headOf(model), 0
end

--[[ Karakterin (ya da canavarın) başında beliren, yükselip sönen çizgi roman yazısı. ]]
local function popWord(character: Model, text: string, color: Color3)
	local head, lift = anchorOf(character)
	if not head then
		return
	end
	local big = lift > 0
	local gui = Instance.new("BillboardGui")
	gui.Name = "GearWord"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(if big then 240 else 160, if big then 90 else 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2.2 + lift * 1.6, 0)
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
	TweenService:Create(gui, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffsetWorldSpace = Vector3.new(0, 4.2 + lift * 1.6, 0) }):Play()
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
	local head, lift = anchorOf(character)
	if not head then
		return
	end
	-- Canavarda yıldızlar büyük ve gövdenin tepesinde geniş bir halkada
	local size = if lift > 0 then 1.6 else 0.4
	local ring = if lift > 0 then lift * 0.9 else 1.2
	local up = if lift > 0 then lift * 1.7 else 1.1
	local stars: { Part } = {}
	for _ = 1, (if lift > 0 then 5 else 3) do
		table.insert(stars, fxPart(Vector3.new(size, size, size), head.CFrame, color, Enum.PartType.Ball))
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
			local a = t * 6 + i * (math.pi * 2 / #stars)
			s.CFrame = CFrame.new(head.Position + Vector3.new(math.cos(a) * ring, up, math.sin(a) * ring))
		end
	end)
end

-- ─── Savrulma (vurulan oyuncu) ─────────────────────────────────────────────

--[[
	Kendi karakterim vuruldu. İstasyonda yere savruluyor (PlatformStand +
	hız, sersemlik bitince kalkıyor). Uzayda uçuş denetimi SpaceFX'te: ona
	yerel nitelikle "şu kadar sn savruluyorsun, şu hızla" diyoruz, o da
	dönerek sürükleniyor (istasyon animasyonundan farklı, 2026-09-28).
]]
local function knockSelf(from: Vector3, knock: number, stun: number, inSpace: boolean)
	local character = player.Character
	local root = character and rootOf(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and humanoid) then
		return
	end
	local away = root.Position - from
	away = if away.Magnitude > 0.1 then away.Unit else -root.CFrame.LookVector
	if inSpace then
		player:SetAttribute("SpaceKnock", away * knock + Vector3.new(0, knock * 0.25, 0))
		player:SetAttribute("SpaceStunUntil", os.clock() + stun)
		return
	end
	local flat = Vector3.new(away.X, 0, away.Z)
	flat = if flat.Magnitude > 0.1 then flat.Unit else -root.CFrame.LookVector
	humanoid.PlatformStand = true
	root.AssemblyLinearVelocity = flat * knock + Vector3.new(0, knock * 0.45, 0)
	root.AssemblyAngularVelocity = Vector3.new(math.random(-6, 6), math.random(-3, 3), math.random(-6, 6))
	task.delay(stun, function()
		if humanoid.Parent then
			humanoid.PlatformStand = false
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

--[[
	Yerel alet kullanımı (tıklandığı an): gezen süs mürettebat (MapLife)
	kendi istemcisinde savrulsun diye. (Konum, bakış, alet kimliği)
]]
GearFX.LocalUsed = Instance.new("BindableEvent")

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
			local me = player.Character and rootOf(player.Character)
			if me then
				GearFX.LocalUsed:Fire(me.Position, me.CFrame.LookVector, gearDef.id)
			end
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

	table.insert(connections, remote.OnClientEvent:Connect(function(kind, character, a, b, c, d, ...)
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
				local anchor, lift = nil, 0
				if target then
					anchor, lift = anchorOf(target)
				end
				if from then
					local to = if anchor then anchor.Position + Vector3.new(0, lift, 0) else (from + (if root then root.CFrame.LookVector else Vector3.zAxis) * 30)
					task.delay(0.05, zapBeam, from, to)
					SoundFX.GearSound("GearZap", from)
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
			-- Oyuncu vuruldu: (karakter, alet, merkez, savrulma, sersemlik, uzayda mı)
			local gearId = a
			local knock = if typeof(c) == "number" then math.clamp(c, 0, 120) else 30
			local stun = if typeof(d) == "number" then math.clamp(d, 0, 4) else 1
			local inSpace = select(1, ...) == true
			local delay = if gearId == "SlapGlove" then 0.18 elseif gearId == "EmergencyButton" then 0.3 else 0.08
			task.delay(delay, function()
				local anchor = rootOf(character)
				local at = if anchor then anchor.Position else nil
				local color = if gearId == "StunGun" then Color3.fromRGB(120, 210, 255)
					elseif gearId == "EmergencyButton" then Color3.fromRGB(255, 120, 90) else Color3.fromRGB(255, 235, 90)
				local word = if inSpace then (if gearId == "StunGun" then "ZZAP!" else "SPIN!")
					elseif gearId == "SlapGlove" then "SLAP!" elseif gearId == "StunGun" then "ZAP!" else "BOOM!"
				popWord(character, word, color)
				if at then
					burst(at, color, if inSpace then 30 else 40, if inSpace then 18 else 26)
					SoundFX.GearSound(if gearId == "StunGun" then "GearZap" elseif gearId == "SlapGlove" then "GearSlap" else "GearBlast", at)
				end
				dizzy(character, stun, color)
				if mine then
					knockSelf(b, knock, stun, inSpace)
					if shaker then
						shaker.Shake(if inSpace then 0.8 else 1.2, 0.35)
					end
				end
			end)
		end
	end))


	return {
		Destroy = function()
			for _, conn in connections do
				conn:Disconnect()
			end
		end,
	}
end

return GearFX
