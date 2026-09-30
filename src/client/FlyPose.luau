--!strict
--[[
	Uçuş animasyonu: uzayda (SpaceFX) ve kapsülde (CapsuleFX).

	Eskiden karakter PlatformStand'le kaskatı bir heykel gibi 55-72°
	yatırılıyordu. Şimdi iki döngü klibi oynuyor ve hıza göre karışıyor
	(2026-09-28: jetpack'e uygun pozlar):

	  Hover — dik süzülme: kollar hafif yanda dengede, bacaklar bitişik,
	          dizler yumuşak, ağır salınım
	  Move  — jetpack'le atılma: kollar geride gövdeye yakın (itiyor gibi),
	          bacaklar bitişik ve düz, baş ileri bakıyor. Gövdenin eğimini
	          (~45°) çağıran AlignOrientation'la veriyor; bu klip uzuvlar.

	Klipler GearFX ve CarryPose'taki gibi eklemlerin Transform'uyla
	oynuyor (RunService.Stepped, Animator'dan sonra; Motor6D ya da yeni
	avatarların AnimationConstraint eklemi, yalnızca R15). 2026-09-30'a
	kadar KeyframeSequenceProvider'la Animator'da oynuyordu: o kimlik
	yalnızca Studio'da çalışıyor, yayında karakter heykel gibi kalıyordu.

	Transform ağdan gitmiyor: diğer oyuncuları da her istemci kendisi
	oynatıyor (sunucunun InSpace niteliği, hızı gövdenin hızından). Mürettebat
	taşıyanın kollarını CarryPose tutuyor (SpaceCarry): burada yalnızca
	gövde ve bacaklar.

	Açılar R15 eklem uzayında: kolda pitch 0 aşağı sarkık, 90 önde yatay,
	180 yukarıda; roll + sağ kolu dışa açar (sol kolda -). Bacakta pitch +
	ileri, dizde - geriye büküm. Başta pitch + yukarı bakış.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local FlyPose = {}

export type Handle = {
	SetBlend: (self: Handle, moving: number) -> (),
	Destroy: (self: Handle) -> (),
}

-- Parça -> { pitch, yaw, roll } (derece)
type Frame = { [string]: { number } }
type Clip = { duration: number, frames: { { t: number, pose: Frame } } }

local HOVER: Clip = {
	duration = 2.2,
	frames = {
		{ t = 0, pose = {
			UpperTorso = { 2, 0, 0 },
			RightUpperArm = { 14, 0, 26 }, RightLowerArm = { 22, 0, 0 },
			LeftUpperArm = { 14, 0, -26 }, LeftLowerArm = { 22, 0, 0 },
			RightUpperLeg = { 6, 0, 3 }, RightLowerLeg = { -16, 0, 0 },
			LeftUpperLeg = { 10, 0, -3 }, LeftLowerLeg = { -22, 0, 0 },
			Head = { 2, 0, 0 },
		} },
		{ t = 0.5, pose = {
			UpperTorso = { 4, 0, 0 },
			RightUpperArm = { 20, 0, 32 }, RightLowerArm = { 30, 0, 0 },
			LeftUpperArm = { 20, 0, -32 }, LeftLowerArm = { 30, 0, 0 },
			RightUpperLeg = { 12, 0, 3 }, RightLowerLeg = { -26, 0, 0 },
			LeftUpperLeg = { 4, 0, -3 }, LeftLowerLeg = { -14, 0, 0 },
			Head = { 6, 0, 0 },
		} },
		{ t = 1, pose = {
			UpperTorso = { 2, 0, 0 },
			RightUpperArm = { 14, 0, 26 }, RightLowerArm = { 22, 0, 0 },
			LeftUpperArm = { 14, 0, -26 }, LeftLowerArm = { 22, 0, 0 },
			RightUpperLeg = { 6, 0, 3 }, RightLowerLeg = { -16, 0, 0 },
			LeftUpperLeg = { 10, 0, -3 }, LeftLowerLeg = { -22, 0, 0 },
			Head = { 2, 0, 0 },
		} },
	},
}

local MOVE: Clip = {
	duration = 0.9,
	frames = {
		{ t = 0, pose = {
			UpperTorso = { -4, 0, 0 },
			RightUpperArm = { -30, 0, 12 }, RightLowerArm = { 14, 0, 0 },
			LeftUpperArm = { -30, 0, -12 }, LeftLowerArm = { 14, 0, 0 },
			RightUpperLeg = { -4, 0, 2 }, RightLowerLeg = { -10, 0, 0 },
			LeftUpperLeg = { -4, 0, -2 }, LeftLowerLeg = { -12, 0, 0 },
			Head = { 36, 0, 0 },
		} },
		{ t = 0.5, pose = {
			UpperTorso = { -2, 0, 0 },
			RightUpperArm = { -36, 0, 16 }, RightLowerArm = { 10, 0, 0 },
			LeftUpperArm = { -36, 0, -16 }, LeftLowerArm = { 10, 0, 0 },
			RightUpperLeg = { -8, 0, 2 }, RightLowerLeg = { -16, 0, 0 },
			LeftUpperLeg = { -2, 0, -2 }, LeftLowerLeg = { -8, 0, 0 },
			Head = { 38, 0, 0 },
		} },
		{ t = 1, pose = {
			UpperTorso = { -4, 0, 0 },
			RightUpperArm = { -30, 0, 12 }, RightLowerArm = { 14, 0, 0 },
			LeftUpperArm = { -30, 0, -12 }, LeftLowerArm = { 14, 0, 0 },
			RightUpperLeg = { -4, 0, 2 }, RightLowerLeg = { -10, 0, 0 },
			LeftUpperLeg = { -4, 0, -2 }, LeftLowerLeg = { -12, 0, 0 },
			Head = { 36, 0, 0 },
		} },
	},
}

-- Parça -> onu üst parçaya bağlayan eklem (R15; eklem parçanın içinde)
local JOINTS: { [string]: string } = {
	UpperTorso = "Waist",
	Head = "Neck",
	RightUpperArm = "RightShoulder",
	RightLowerArm = "RightElbow",
	LeftUpperArm = "LeftShoulder",
	LeftLowerArm = "LeftElbow",
	RightUpperLeg = "RightHip",
	RightLowerLeg = "RightKnee",
	LeftUpperLeg = "LeftHip",
	LeftLowerLeg = "LeftKnee",
}
local ARMS = { RightUpperArm = true, RightLowerArm = true, LeftUpperArm = true, LeftLowerArm = true }

-- Açılma / kapanma süresi (sn)
local FADE_IN = 0.3
local FADE_OUT = 0.25

local function smooth(u: number): number
	return u * u * (3 - 2 * u)
end

--[[ Döngü klibinin `phase` (0..1) anında parçanın açıları (yoksa nil). ]]
local function sample(clip: Clip, name: string, phase: number): (number?, number?, number?)
	local frames = clip.frames
	for index = 2, #frames do
		local f1, f0 = frames[index], frames[index - 1]
		if phase <= f1.t then
			local a, b = f0.pose[name], f1.pose[name]
			if not (a and b) then
				return nil
			end
			local span = f1.t - f0.t
			local w = if span > 0 then smooth((phase - f0.t) / span) else 1
			return a[1] + (b[1] - a[1]) * w, a[2] + (b[2] - a[2]) * w, a[3] + (b[3] - a[3]) * w
		end
	end
	return nil
end

type Entry = {
	blend: number,       -- 0 süzülme, 1 atılma
	hoverT: number,      -- klip saatleri (sn)
	moveT: number,
	weight: number,      -- 0..1 açılma
	closing: boolean,    -- kapanıyor (bitince kayıt siliniyor)
	remote: boolean,     -- başka oyuncu: blend gövde hızından
	player: Player?,
}

local entries: { [Model]: Entry } = setmetatable({}, { __mode = "k" }) :: any

local function applyPose(character: Model, e: Entry, skipArms: boolean)
	local w = smooth(math.clamp(e.weight, 0, 1))
	local hp = (e.hoverT / HOVER.duration) % 1
	local mp = (e.moveT / MOVE.duration) % 1
	for name, jointName in JOINTS do
		if skipArms and ARMS[name] then
			continue
		end
		local part = character:FindFirstChild(name)
		local joint = part and part:FindFirstChild(jointName)
		if not (joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint"))) then
			continue
		end
		local h1, h2, h3 = sample(HOVER, name, hp)
		local m1, m2, m3 = sample(MOVE, name, mp)
		if not (h1 and m1) then
			continue
		end
		local b = e.blend
		local pitch = (h1 :: number) + ((m1 :: number) - (h1 :: number)) * b
		local yaw = (h2 :: number) + ((m2 :: number) - (h2 :: number)) * b
		local roll = (h3 :: number) + ((m3 :: number) - (h3 :: number)) * b
		local target = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, math.rad(roll))
		local j = joint :: any
		j.Transform = if w >= 1 then target else (j.Transform :: CFrame):Lerp(target, w)
	end
end

local function step(_: number, dt: number)
	-- Diğer oyuncular: uzaydayken (sunucunun niteliği) poz, hız gövdeden
	local localPlayer = Players.LocalPlayer
	for _, other in Players:GetPlayers() do
		if other == localPlayer then
			continue
		end
		local character = other.Character
		if not character then
			continue
		end
		local e = entries[character]
		local inSpace = other:GetAttribute("InSpace") == true
		if inSpace and not e then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
				entries[character] = { blend = 0, hoverT = 0, moveT = 0, weight = 0, closing = false, remote = true, player = other }
			end
		elseif e and e.remote then
			e.closing = not inSpace
		end
	end

	for character, e in entries do
		if not character.Parent then
			entries[character] = nil
			continue
		end
		if e.remote then
			local root = character:FindFirstChild("HumanoidRootPart")
			local speed = if root and root:IsA("BasePart") then root.AssemblyLinearVelocity.Magnitude else 0
			local target = math.clamp((speed - 8) / 40, 0, 1)
			e.blend += (target - e.blend) * math.min(1, dt * 5)
		end
		e.hoverT += dt
		-- Hızlanınca bacak çırpması da hızlansın
		e.moveT += dt * (0.8 + e.blend * 0.6)
		if e.closing then
			e.weight -= dt / FADE_OUT
			if e.weight <= 0 then
				entries[character] = nil
				continue
			end
		else
			e.weight = math.min(1, e.weight + dt / FADE_IN)
		end
		local owner = e.player or Players:GetPlayerFromCharacter(character)
		local carrying = owner ~= nil and owner:GetAttribute("SpaceCarry") == true
		applyPose(character, e, carrying)
	end
end

RunService.Stepped:Connect(step)

--[[ Karakterde uçuş pozunu başlatır. R15 değilse boş (hiçbir şey yapmayan) nesne. ]]
function FlyPose.Start(character: Model): Handle
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local e: Entry? = nil
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		e = { blend = 0, hoverT = 0, moveT = 0, weight = 0, closing = false, remote = false, player = nil }
		entries[character] = e :: Entry
	end

	local pose = {} :: any
	function pose.SetBlend(_self: Handle, moving: number)
		if e then
			(e :: Entry).blend = math.clamp(moving, 0, 1)
		end
	end
	function pose.Destroy(_self: Handle)
		if e then
			(e :: Entry).closing = true
		end
	end
	return pose :: Handle
end

return FlyPose
