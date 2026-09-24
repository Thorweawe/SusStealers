--!strict
--[[
	Haritanın canlılığı — tamamen istemcide, sunucuya hiçbir şey sormuyor:

	  Uyarı lambaları  — Decor.Polish.Beacons'taki "WarnBeacon"lar sırayla
	                     yanıp sönüyor. Her lambanın fazı farklı; hepsi aynı
	                     anda yansa "alarm" gibi duruyordu.
	  Gezen mürettebat — koridorda dolaşan birkaç Among Us mürettebatı.
	                     Sadece süs: çarpışmıyor, çalınamıyor, isim etiketi
	                     yok (kaidedeki karakterlerle karışmasın diye).

	NEDEN İSTEMCİDE: sunucuda her karede konum/ışık değiştirmek her oyuncuya
	her karede paket demek. Bu iki şey herkeste aynı görünmek zorunda değil.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UnitModel = require(Shared.UnitModel)

local MapLife = {}

export type Handle = {
	Destroy: () -> (),
}

-- ─── Uyarı lambaları ────────────────────────────────────────────────────────

local BLINK_PERIOD = 1.6
local BLINK_ON = 0.45
local LAMP_ON = Color3.fromRGB(255, 70, 60)
local LAMP_OFF = Color3.fromRGB(90, 24, 24)

-- ─── Gezen mürettebat ───────────────────────────────────────────────────────

-- Koridorun ortasındaki bant: odaların ağzına girmesinler, yolu kesmesinler
local WALK_X = { -20, 380 }
local WALK_Z = { 44, 72 }
local WALK_SPEED = 6
local CREW = { "RedCrew", "BlueCrew", "YellowCrew", "LimeCrew" }

type Walker = {
	model: Model,
	lift: number,
	pos: Vector3,
	target: Vector3,
	pauseUntil: number,
	phase: number,
}

local function randomPoint(rng: Random): Vector3
	return Vector3.new(rng:NextNumber(WALK_X[1], WALK_X[2]), 0, rng:NextNumber(WALK_Z[1], WALK_Z[2]))
end

function MapLife.Start(): Handle
	local rng = Random.new()
	local decor = workspace:WaitForChild("Decor", 30)
	local polish = decor and decor:WaitForChild("Polish", 10)
	local beaconFolder = polish and polish:FindFirstChild("Beacons")

	-- Lambalar: her birine sabit bir faz kayması
	local lamps: { { part: BasePart, light: PointLight?, offset: number } } = {}
	if beaconFolder then
		for i, d in beaconFolder:GetChildren() do
			if d:IsA("BasePart") and d.Name == "WarnBeacon" then
				table.insert(lamps, {
					part = d,
					light = d:FindFirstChildOfClass("PointLight"),
					offset = (i * 0.37) % BLINK_PERIOD,
				})
			end
		end
	end

	-- Mürettebat: istemciye özel klasör (sunucu görmüyor)
	local folder = Instance.new("Folder")
	folder.Name = "CrewWalkers"
	folder.Parent = workspace

	local walkers: { Walker } = {}
	for i, unitId in CREW do
		local ok, model = pcall(UnitModel.Build, unitId)
		if ok and model and model.PrimaryPart then
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.CastShadow = false
				end
			end
			local start = randomPoint(rng)
			-- Pivot gövdenin ortası; ayaklar zemine (karo üstü 0.27) otursun
			local lift = model:GetPivot().Position.Y + 0.27
			model:PivotTo(CFrame.new(start + Vector3.new(0, lift, 0)))
			model.Parent = folder
			table.insert(walkers, {
				model = model,
				lift = lift,
				pos = start,
				target = randomPoint(rng),
				pauseUntil = 0,
				phase = i * 0.7,
			})
		end
	end

	local clock = 0
	local lampAccum = 0
	local connection = RunService.Heartbeat:Connect(function(dt)
		clock += dt

		-- Lambalar saniyede ~12 kez yeter
		lampAccum += dt
		if lampAccum >= 0.08 then
			lampAccum = 0
			for _, lamp in lamps do
				local on = ((clock + lamp.offset) % BLINK_PERIOD) < BLINK_ON
				lamp.part.Color = if on then LAMP_ON else LAMP_OFF
				if lamp.light then
					lamp.light.Brightness = if on then 3 else 0
				end
			end
		end

		for _, w in walkers do
			if clock < w.pauseUntil then
				-- Durup bakınıyor: hafif sallanma yok, sadece bekliyor
				continue
			end
			local delta = w.target - w.pos
			local dist = delta.Magnitude
			if dist < 1 then
				-- Hedefe vardı: biraz bekle, yeni hedef seç
				w.pauseUntil = clock + rng:NextNumber(1, 4)
				w.target = randomPoint(rng)
				continue
			end
			local step = math.min(dist, WALK_SPEED * dt)
			w.pos += delta.Unit * step
			-- Yürürken zıplar gibi hafif sekme: Among Us yürüyüşü
			local bob = math.abs(math.sin((clock + w.phase) * 9)) * 0.35
			local facing = Vector3.new(delta.X, 0, delta.Z)
			local cf = CFrame.lookAt(w.pos, w.pos + facing) + Vector3.new(0, w.lift + bob, 0)
			w.model:PivotTo(cf)
		end
	end)

	return {
		Destroy = function()
			connection:Disconnect()
			folder:Destroy()
		end,
	}
end

return MapLife
