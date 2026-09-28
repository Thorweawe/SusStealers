--!strict
--[[
	Taşıma animasyonu (2026-09-28, Batur: "crewmate sadece üstümüzde uçuyor,
	elimizle tutmuyoruz, hiçbir şey yokmuş gibi").

	Sunucu (SpaceService) çalınan crewmate'i karakterin başının üstüne
	kaynaklıyor ("SpaceCarry" modeli, "CarryWeld"). Bu modül HER istemcide
	HER taşıyan için:

	  Kollar  — iki kol başın üstünde, dirsekler hafif bükük; crewmate'i
	            tutuyor. Adım ritminde hafifçe iniş-çıkış.
	  Kapma   — crewmate bulunduğu yerden ellere uçuyor (0.45 sn, hafif
	            taşarak yerine oturuyor). Sunucu GrabFrom/GrabAt veriyor.
	  Çırpınma— taşınırken sağa sola kıpırdıyor, arada bir silkiniyor.

	Kollar eklemin Transform'uyla (R15; Motor6D ya da yeni AnimationConstraint), RunService.Stepped'de — Animator'ın
	o karedeki pozundan SONRA, yani yürüme/uçuş animasyonunun üstüne
	yazıyor, bacaklar kendi animasyonunda kalıyor. Crewmate'in oynaması
	kaynağın C0'ı yerelde değiştirilerek; kimseye bir şey gönderilmiyor,
	herkes aynı hesabı kendi ekranında yapıyor. R6'da yalnızca crewmate
	oynuyor (kollar dokunulmuyor).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CarryPose = {}

-- FlyPose ile aynı eklem uzayı: pitch 180 kol yukarıda, roll + sağ kol dışa
local ARMS = {
	{ part = "RightUpperArm", joint = "RightShoulder", pitch = 174, roll = 8 },
	{ part = "LeftUpperArm", joint = "LeftShoulder", pitch = 174, roll = -8 },
	{ part = "RightLowerArm", joint = "RightElbow", pitch = 10, roll = 0 },
	{ part = "LeftLowerArm", joint = "LeftElbow", pitch = 10, roll = 0 },
}

local PICKUP = 0.45
local BLEND_IN = 0.2

type Holder = {
	model: Model,
	weld: Weld,
	base: CFrame,
	seen: number,
	grabAt: number?,
	from: Vector3?,
	phase: number,
}
local holders: { [Model]: Holder } = {}

local function holderOf(character: Model): Holder?
	local model = character:FindFirstChild("SpaceCarry")
	if not (model and model:IsA("Model")) then
		return nil
	end
	local h = holders[model]
	if h then
		return h
	end
	local primary = model.PrimaryPart
	local weld = primary and primary:FindFirstChild("CarryWeld")
	if not (weld and weld:IsA("Weld")) then
		return nil
	end
	local grabAt = model:GetAttribute("GrabAt")
	local from = model:GetAttribute("GrabFrom")
	local fresh: { grabAt: number?, from: Vector3? } = {}
	-- Yalnızca yeni kapılan (1 sn içinde) crewmate uçarak geliyor; geç
	-- görülen (sonradan katılan oyuncu) doğrudan elde
	if typeof(grabAt) == "number" and typeof(from) == "Vector3" and workspace:GetServerTimeNow() - grabAt < 1 then
		fresh.grabAt = grabAt
		fresh.from = from
	end
	h = {
		model = model,
		weld = weld,
		base = weld.C0,
		seen = os.clock(),
		grabAt = fresh.grabAt,
		from = fresh.from,
		phase = math.random() * 10,
	}
	holders[model] = h
	return h
end

-- Taşarak oturma (easeOutBack)
local function backOut(u: number): number
	local c1, c3 = 1.4, 2.4
	return 1 + c3 * (u - 1) ^ 3 + c1 * (u - 1) ^ 2
end

local function poseArms(character: Model, weight: number, t: number, phase: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return
	end
	-- Adım ritminde iniş-çıkış (yürürken biraz daha belirgin)
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local bob = math.sin(t * (if moving then 9 else 3) + phase) * (if moving then 5 else 3)
	for _, arm in ARMS do
		local part = character:FindFirstChild(arm.part)
		local joint = part and part:FindFirstChild(arm.joint)
		-- Yeni avatar eklemleri AnimationConstraint (Motor6D değil); ikisinde de Transform var
		if joint and (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then
			local pitch = arm.pitch + (if arm.joint:find("Shoulder") then bob else -bob * 0.5)
			local target = CFrame.Angles(math.rad(pitch), 0, math.rad(arm.roll))
			local j = joint :: any
			j.Transform = if weight >= 1 then target else (j.Transform :: CFrame):Lerp(target, weight)
		end
	end
end

local function animateHeld(h: Holder, t: number)
	local root = h.weld.Part0
	if not root then
		return
	end
	-- Çırpınma: sağa sola sallanma, ara ara silkinme
	local wiggle = math.sin(t * 7 + h.phase) * 0.14
	local shake = math.max(0, math.sin(t * 1.3 + h.phase)) ^ 8
	local hold = h.base
		* CFrame.new(0, math.sin(t * 5 + h.phase) * 0.08, 0)
		* CFrame.Angles(math.sin(t * 5.5 + h.phase) * 0.08, 0, wiggle + math.sin(t * 40) * 0.12 * shake)
	if h.grabAt and h.from then
		local u = math.clamp((workspace:GetServerTimeNow() - h.grabAt) / PICKUP, 0, 1)
		if u < 1 then
			-- Yerinden (ayak hizası + biraz yukarı) ellere kavisli uçuş
			local startWorld = CFrame.new(h.from + Vector3.new(0, 1.5, 0)) * (root.CFrame * hold).Rotation
			local start = root.CFrame:ToObjectSpace(startWorld)
			local k = backOut(u)
			local arc = CFrame.new(0, math.sin(u * math.pi) * 2.5, 0)
			h.weld.C0 = start:Lerp(hold, k) * arc * CFrame.Angles(0, (1 - u) * math.pi * 2, 0)
			return
		end
		h.grabAt = nil
	end
	h.weld.C0 = hold
end

function CarryPose.Start()
	local clock = 0
	-- Kollar: Animator'dan sonra (Stepped), animasyonun üstüne
	RunService.Stepped:Connect(function(_, dt)
		clock += dt
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character then
				local h = holderOf(character)
				if h then
					poseArms(character, math.clamp((os.clock() - h.seen) / BLEND_IN, 0, 1), clock, h.phase)
				end
			end
		end
	end)
	-- Crewmate: her karede kaynağın C0'ı
	RunService.RenderStepped:Connect(function()
		for model, h in holders do
			if not model.Parent or not h.weld.Parent then
				holders[model] = nil
			else
				animateHeld(h, clock)
			end
		end
	end)
end

return CarryPose
