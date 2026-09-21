--!strict
-- Kaidedeki karakterin nadirliğine göre görsel vurgu.
--
-- Oyunun bütün amacı pahalı karakter toplamak ama Amogus Prime ile Red
-- Crewmate kaidede aynı görünüyordu. Hedef görünmezse hedef değildir.
--
-- Etki basamaklı: ucuzlar sade kalıyor, pahalılar sırayla ışık sütunu,
-- dönen halka, ikinci halka ve parçacık kazanıyor. Böylece hem uzaktan
-- "orada değerli bir şey var" okunuyor, hem de kademeler birbirinden
-- ayırt ediliyor.
--
-- Tamamen istemci tarafı. Her oyuncu kendi makinesinde üretiyor, ağda
-- hiçbir şey taşınmıyor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local RarityFX = {}

local FX_NAME = "RarityFX"

--[[
	Kademeler. order 1-2 (Common, Uncommon) kasıtlı olarak boş: her kaide
	ışıldarsa hiçbiri öne çıkmaz. Vurgu ancak zıtlıkla çalışıyor.
]]
local function tierOf(order: number): { beam: number, rings: number, particles: boolean }
	if order <= 2 then
		return { beam = 0, rings = 0, particles = false }
	elseif order == 3 then
		return { beam = 7, rings = 0, particles = false }      -- Rare
	elseif order == 4 then
		return { beam = 10, rings = 1, particles = false }     -- Epic
	elseif order == 5 then
		return { beam = 14, rings = 1, particles = true }      -- Legendary
	elseif order == 6 then
		return { beam = 18, rings = 2, particles = true }      -- Mythic
	end
	return { beam = 24, rings = 3, particles = true }          -- Secret
end

export type FX = {
	Update: () -> (),
	Stop: () -> (),
}

type Ring = { part: BasePart, speed: number, base: CFrame }

function RarityFX.Create(): FX
	local rings: { Ring } = {}

	local function clear(podium: BasePart)
		local old = podium:FindFirstChild(FX_NAME)
		if old then
			-- Dönen halkalar listesinden de çıkar
			for i = #rings, 1, -1 do
				if not rings[i].part:IsDescendantOf(podium) then
					continue
				end
				table.remove(rings, i)
			end
			old:Destroy()
		end
	end

	local function build(podium: BasePart, unitId: string, mutationId: string?)
		local def = Config.GetUnit(unitId)
		if not def then
			return
		end

		local rarity = Config.Rarities[def.rarity]
		if not rarity then
			return
		end

		local tier = tierOf(rarity.order)
		if tier.beam <= 0 then
			return -- ucuz karakter, vurgu yok
		end

		local color = rarity.color
		local mutation = Config.GetMutation(mutationId)
		if mutation and mutation.tint then
			-- Mutasyonlu karakter kendi rengini bastırsın: zaten özel
			color = color:Lerp(mutation.tint, 0.6)
		end

		local holder = Instance.new("Folder")
		holder.Name = FX_NAME
		holder.Parent = podium

		local top = podium.Position + Vector3.new(0, podium.Size.Y / 2, 0)

		--[[
			Işık sütunu: yukarı doğru incelen ve sönen bir huzme. Tek parça
			yerine üç katman, çünkü tek saydam kutu düz bir levha gibi
			duruyor; katmanlar derinlik veriyor.
		]]
		for layer = 1, 3 do
			local t = layer / 3
			local beam = Instance.new("Part")
			beam.Name = "Beam"
			beam.Size = Vector3.new(5.2 * (1 - t * 0.55), tier.beam * (1 - t * 0.2), 5.2 * (1 - t * 0.55))
			beam.CFrame = CFrame.new(top + Vector3.new(0, beam.Size.Y / 2, 0))
			beam.Color = color
			beam.Material = Enum.Material.Neon
			beam.Transparency = 0.88 + t * 0.06
			beam.Anchored = true
			beam.CanCollide = false
			beam.CanQuery = false
			beam.CanTouch = false
			beam.CastShadow = false
			beam.Parent = holder
		end

		-- Zemin halkası ve ışık
		local base = Instance.new("Part")
		base.Name = "Halo"
		base.Size = Vector3.new(6.4, 0.08, 6.4)
		base.CFrame = CFrame.new(top + Vector3.new(0, 0.06, 0))
		base.Color = color
		base.Material = Enum.Material.Neon
		base.Transparency = 0.25
		base.Anchored = true
		base.CanCollide = false
		base.CanQuery = false
		base.CanTouch = false
		base.CastShadow = false
		base.Parent = holder

		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 10 + rarity.order * 2.5
		light.Brightness = 0.8 + rarity.order * 0.25
		light.Parent = base

		-- Dönen halkalar: her biri ters yönde, hızları farklı
		for i = 1, tier.rings do
			local ring = Instance.new("Part")
			ring.Name = "Ring"
			ring.Size = Vector3.new(7 + i * 1.6, 0.22, 0.6)
			ring.CFrame = CFrame.new(top + Vector3.new(0, 1.6 + i * 1.9, 0))
			ring.Color = color
			ring.Material = Enum.Material.Neon
			ring.Transparency = 0.15
			ring.Anchored = true
			ring.CanCollide = false
			ring.CanQuery = false
			ring.CanTouch = false
			ring.CastShadow = false
			ring.Parent = holder

			table.insert(rings, {
				part = ring,
				speed = (if i % 2 == 0 then -1 else 1) * (28 + i * 14),
				base = ring.CFrame,
			})
		end

		if tier.particles then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Color = ColorSequence.new(color)
			emitter.Size = NumberSequence.new(0.35, 0)
			emitter.Transparency = NumberSequence.new(0.35, 1)
			emitter.Lifetime = NumberRange.new(1.4, 2.4)
			emitter.Rate = 6 + rarity.order * 3
			emitter.Speed = NumberRange.new(1.5, 3.5)
			emitter.SpreadAngle = Vector2.new(22, 22)
			emitter.LightEmission = 1
			emitter.Parent = base
		end
	end

	--[[ Kaidedeki karakter değişince efekti yeniden kur. ]]
	local function refresh(podium: BasePart)
		local unitId = podium:GetAttribute("UnitId")
		local mutationId = podium:GetAttribute("MutationId")

		clear(podium)

		if typeof(unitId) == "string" and unitId ~= "" then
			build(podium, unitId, if typeof(mutationId) == "string" and mutationId ~= "" then mutationId else nil)
		end
	end

	local hooked: { [BasePart]: boolean } = {}

	local function update()
		local plots = workspace:FindFirstChild("Plots")
		if not plots then
			return
		end

		for _, plot in plots:GetChildren() do
			if not plot:IsA("Model") then
				continue
			end

			for _, podium in plot:GetDescendants() do
				if not (podium:IsA("BasePart") and podium.Name == "Podium") then
					continue
				end

				if not hooked[podium] then
					hooked[podium] = true
					podium:GetAttributeChangedSignal("UnitId"):Connect(function()
						refresh(podium)
					end)
					refresh(podium)
				end
			end
		end
	end

	local connection = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for _, r in rings do
			if r.part.Parent then
				r.part.CFrame = r.base * CFrame.Angles(0, math.rad(r.speed * t), 0)
			end
		end
	end)

	return {
		Update = update,
		Stop = function()
			connection:Disconnect()
		end,
	}
end

return RarityFX
