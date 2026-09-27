--!strict
--[[
	Uçuş animasyonu: uzayda (SpaceFX) ve kapsülde (CapsuleFX).

	Eskiden karakter PlatformStand'le kaskatı bir heykel gibi 55-72°
	yatırılıyordu ("uçma kötü görünüyor"). Şimdi iki döngü klibi oynuyor
	ve hıza göre karışıyor:

	  Hover — dik süzülme: kollar yanlara açık, bir diz kırık, hafif salınım
	  Move  — süper kahraman: sağ kol ileri uzanmış, sol kol geride,
	          bacaklar arkada çırpınıyor. Gövdenin eğimini (~45°) çağıran
	          AlignOrientation'la veriyor; bu klip yalnızca uzuvlar.

	Klipler GearFX'teki gibi çalışma anında KeyframeSequence olarak
	kuruluyor (KeyframeSequenceProvider, yalnızca R15). Karakterin kendi
	Animator'ında oynadığı için diğer oyuncular da görüyor.

	Açılar R15 eklem uzayında: kolda pitch 0 aşağı sarkık, 90 önde yatay,
	180 yukarıda; roll + sağ kolu dışa açar (sol kolda -). Bacakta pitch +
	ileri, dizde - geriye büküm. Başta pitch + yukarı bakış.
]]

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local FlyPose = {}

export type Handle = {
	SetBlend: (self: Handle, moving: number) -> (),
	Destroy: (self: Handle) -> (),
}

-- Parça -> { pitch, yaw, roll } (derece)
type Frame = { [string]: { number } }
type Clip = { duration: number, frames: { { t: number, pose: Frame } } }

local HOVER: Clip = {
	duration = 1.8,
	frames = {
		{ t = 0, pose = {
			RightUpperArm = { 25, 0, 38 }, RightLowerArm = { 25, 0, 0 },
			LeftUpperArm = { 25, 0, -38 }, LeftLowerArm = { 25, 0, 0 },
			LeftUpperLeg = { 12, 0, -4 }, LeftLowerLeg = { -22, 0, 0 },
			RightUpperLeg = { -4, 0, 4 }, RightLowerLeg = { -38, 0, 0 },
			Head = { 4, 0, 0 },
		} },
		{ t = 0.5, pose = {
			RightUpperArm = { 30, 0, 46 }, RightLowerArm = { 30, 0, 0 },
			LeftUpperArm = { 30, 0, -46 }, LeftLowerArm = { 30, 0, 0 },
			LeftUpperLeg = { 4, 0, -4 }, LeftLowerLeg = { -32, 0, 0 },
			RightUpperLeg = { 6, 0, 4 }, RightLowerLeg = { -26, 0, 0 },
			Head = { 8, 0, 0 },
		} },
		{ t = 1, pose = {
			RightUpperArm = { 25, 0, 38 }, RightLowerArm = { 25, 0, 0 },
			LeftUpperArm = { 25, 0, -38 }, LeftLowerArm = { 25, 0, 0 },
			LeftUpperLeg = { 12, 0, -4 }, LeftLowerLeg = { -22, 0, 0 },
			RightUpperLeg = { -4, 0, 4 }, RightLowerLeg = { -38, 0, 0 },
			Head = { 4, 0, 0 },
		} },
	},
}

local MOVE: Clip = {
	duration = 1.1,
	frames = {
		{ t = 0, pose = {
			RightUpperArm = { 168, 0, 8 }, RightLowerArm = { 6, 0, 0 },
			LeftUpperArm = { -22, 0, -16 }, LeftLowerArm = { 12, 0, 0 },
			LeftUpperLeg = { -8, 0, -3 }, LeftLowerLeg = { -24, 0, 0 },
			RightUpperLeg = { 2, 0, 3 }, RightLowerLeg = { -12, 0, 0 },
			Head = { 30, 0, 0 },
		} },
		{ t = 0.5, pose = {
			RightUpperArm = { 174, 0, 4 }, RightLowerArm = { 2, 0, 0 },
			LeftUpperArm = { -30, 0, -12 }, LeftLowerArm = { 16, 0, 0 },
			LeftUpperLeg = { 0, 0, -3 }, LeftLowerLeg = { -34, 0, 0 },
			RightUpperLeg = { -8, 0, 3 }, RightLowerLeg = { -22, 0, 0 },
			Head = { 32, 0, 0 },
		} },
		{ t = 1, pose = {
			RightUpperArm = { 168, 0, 8 }, RightLowerArm = { 6, 0, 0 },
			LeftUpperArm = { -22, 0, -16 }, LeftLowerArm = { 12, 0, 0 },
			LeftUpperLeg = { -8, 0, -3 }, LeftLowerLeg = { -24, 0, 0 },
			RightUpperLeg = { 2, 0, 3 }, RightLowerLeg = { -12, 0, 0 },
			Head = { 30, 0, 0 },
		} },
	},
}

-- R15 hiyerarşisi: parça -> üst parça (kök HumanoidRootPart)
local PARENT: { [string]: string } = {
	LowerTorso = "HumanoidRootPart",
	UpperTorso = "LowerTorso",
	Head = "UpperTorso",
	RightUpperArm = "UpperTorso",
	RightLowerArm = "RightUpperArm",
	LeftUpperArm = "UpperTorso",
	LeftLowerArm = "LeftUpperArm",
	RightUpperLeg = "LowerTorso",
	RightLowerLeg = "RightUpperLeg",
	LeftUpperLeg = "LowerTorso",
	LeftLowerLeg = "LeftUpperLeg",
}
local ORDER = { "LowerTorso", "UpperTorso", "Head", "RightUpperArm", "RightLowerArm", "LeftUpperArm", "LeftLowerArm",
	"RightUpperLeg", "RightLowerLeg", "LeftUpperLeg", "LeftLowerLeg" }

local registered: { [Clip]: string } = {}

local function register(clip: Clip): string?
	local cached = registered[clip]
	if cached then
		return cached
	end
	local kfs = Instance.new("KeyframeSequence")
	kfs.Priority = Enum.AnimationPriority.Action2
	kfs.Loop = true
	for _, f in clip.frames do
		local frame = Instance.new("Keyframe")
		frame.Time = f.t * clip.duration
		local made: { [string]: Instance } = {}
		local root = Instance.new("Pose")
		root.Name = "HumanoidRootPart"
		root.Weight = 0
		root.Parent = frame
		made.HumanoidRootPart = root
		for _, name in ORDER do
			local p = Instance.new("Pose")
			p.Name = name
			local a = f.pose[name]
			p.Weight = if a then 1 else 0
			p.CFrame = if a then CFrame.Angles(0, math.rad(a[2]), 0) * CFrame.Angles(math.rad(a[1]), 0, math.rad(a[3])) else CFrame.identity
			p.EasingStyle = Enum.PoseEasingStyle.Cubic
			p.EasingDirection = Enum.PoseEasingDirection.InOut
			p.Parent = made[PARENT[name]]
			made[name] = p
		end
		frame.Parent = kfs
	end
	local ok, id = pcall(function()
		return KeyframeSequenceProvider:RegisterKeyframeSequence(kfs)
	end)
	if not ok or typeof(id) ~= "string" then
		return nil
	end
	registered[clip] = id
	return id
end

local function load(animator: Animator, clip: Clip): AnimationTrack?
	local id = register(clip)
	if not id then
		return nil
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	return if ok then track else nil
end

--[[ Karakterde uçuş pozunu başlatır. R15 değilse boş (hiçbir şey yapmayan) nesne. ]]
function FlyPose.Start(character: Model): Handle
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local hover: AnimationTrack? = nil
	local move: AnimationTrack? = nil
	if animator and humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		hover = load(animator, HOVER)
		move = load(animator, MOVE)
	end
	if hover then
		hover:Play(0.3, 1, 1)
	end
	if move then
		move:Play(0.3, 0.01, 1)
	end
	local blend = 0

	local pose = {} :: any
	function pose.SetBlend(_self: Handle, moving: number)
		local b = math.clamp(moving, 0, 1)
		if math.abs(b - blend) < 0.02 then
			return
		end
		blend = b
		if hover then
			hover:AdjustWeight(math.max(0.01, 1 - b), 0.2)
		end
		if move then
			move:AdjustWeight(math.max(0.01, b), 0.2)
			-- Hızlanınca bacak çırpması da hızlansın
			move:AdjustSpeed(0.8 + b * 0.6)
		end
	end
	function pose.Destroy(_self: Handle)
		if hover then
			hover:Stop(0.25)
		end
		if move then
			move:Stop(0.25)
		end
	end
	return pose :: Handle
end

return FlyPose
