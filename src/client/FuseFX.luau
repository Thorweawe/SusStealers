--!strict
--[[
	Birleştirme makinesindeki animasyon (MedBay tarayıcısı).

	Eskiden birleştirme yumurta açılışının ekran kartını kullanıyordu; üç
	pet görünmüyor, "makinede birleşti" hissi yoktu. Artık dünyada, makinenin
	üstünde oynuyor:

	  1. Üç kopya platformun üstünde belirip yavaşça dönüyor.
	  2. Yeşil tarama halkası yukarıdan iniyor; içinden geçtiği her parça
	     beyaz parlamaya dönüyor.
	  3. Üç beyaz pet dönerek ortada birleşiyor, parlamayla yeni (bir boy
	     büyük) pet büyüyerek çıkıyor.
	  4. Halka yukarı çıkarken beyaz parlama geçtiği yerden kalkıyor, yeni
	     pet asıl rengiyle görünüyor.
	  5. Pet oyuncuya uçup küçülerek "envantere giriyor".

	Hepsi YEREL: parçalar yalnızca bu istemcide var, başka oyuncuya
	gitmiyor. Sonucu sunucu belirledi (PetHatched "fuse"); burası yalnızca
	gösteriyor. Makine haritada yoksa Available() false döner ve HatchFX'in
	ekran kartı kullanılır.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PetModel = require(Shared.PetModel)

local FuseFX = {}

export type Hooks = {
	-- Animasyon başlarken (pencereyi kapatmak için) ve bitince
	onStart: (() -> ())?,
	onEnd: (() -> ())?,
}

export type Handle = {
	IsPlaying: () -> boolean,
	Destroy: () -> (),
}

local GREEN = Color3.fromRGB(90, 255, 150)
local WHITE = Color3.new(1, 1, 1)

-- Halka makinedeki ışık sütununun içinde kalıyor (sütun çapı 10.5)
local RING_R = 4.6
local RING_TOP = 13        -- platformdan yükseklik
local ORBIT_R = 2.6        -- üç petin dizildiği çember
local SRC_MAX = 2.6        -- kaynak petlerin en geniş ölçüsü (üçü halkaya sığsın)
local RES_MAX = 6.2        -- sonuç petin en geniş ölçüsü
local HOVER = 0.5

local function findMachine(): (BasePart?, BasePart?)
	local decor = workspace:FindFirstChild("Decor")
	local hatchery = decor and decor:FindFirstChild("Hatchery")
	local core = hatchery and hatchery:FindFirstChild("FuseCore")
	if not (core and core:IsA("BasePart")) then
		return nil, nil
	end
	local panel = hatchery:FindFirstChild("ScanPanel")
	return core, if panel and panel:IsA("BasePart") then panel else nil
end

function FuseFX.Available(): boolean
	return (findMachine()) ~= nil
end

-- Süreli adım: her karede 0..1 arası ilerleme
local function run(seconds: number, step: (number) -> ())
	local started = os.clock()
	while true do
		local a = math.clamp((os.clock() - started) / seconds, 0, 1)
		step(a)
		if a >= 1 then
			break
		end
		RunService.RenderStepped:Wait()
	end
end

local function easeInOut(a: number): number
	return a * a * (3 - 2 * a)
end

local function easeOutBack(a: number): number
	local c = 1.9
	local t = a - 1
	return 1 + (c + 1) * t * t * t + c * t * t
end

--[[ Parçanın asıl görünümü; beyaz parlamadan geri dönerken lazım. ]]
type Look = { part: BasePart, color: Color3, material: Enum.Material, reflectance: number, white: boolean }

type Pet = {
	model: Model,
	body: BasePart,
	scale: number,     -- ScaleTo değeri (1 = gösterim boyu)
	baseScale: number, -- modelin kendi GetScale değeri, gösterim boyunda
	lift: number,      -- gösterim boyunda gövde merkezinin tabandan yüksekliği
	width: number,     -- gösterim boyundaki en geniş ölçü
	looks: { Look },
}

local function makePet(key: string, parent: Instance): (Pet?, number)
	local model = PetModel.Build(key)
	if not model then
		return nil, 0
	end
	local body = model.PrimaryPart :: BasePart
	local _, extents = model:GetBoundingBox()
	local natural = math.max(extents.X, extents.Z, extents.Y * 0.8)

	local looks: { Look } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = false
			table.insert(looks, { part = d, color = d.Color, material = d.Material, reflectance = d.Reflectance, white = false })
		end
	end
	model.Parent = parent
	return {
		model = model,
		body = body,
		scale = 1,
		baseScale = model:GetScale(),
		lift = 0,
		width = natural,
		looks = looks,
	}, natural
end

-- Gösterim boyunu sabitler: `factor` doğal boyuna göre çarpan
local function fitPet(pet: Pet, factor: number)
	pet.model:ScaleTo(pet.baseScale * factor)
	pet.baseScale = pet.model:GetScale()
	local cf, extents = pet.model:GetBoundingBox()
	pet.lift = pet.body.Position.Y - (cf.Position.Y - extents.Y / 2)
	pet.width *= factor
end

local function setScale(pet: Pet, s: number)
	local clamped = math.max(s, 0.02)
	if math.abs(clamped - pet.scale) > 1e-3 then
		pet.model:ScaleTo(pet.baseScale * clamped)
		pet.scale = clamped
	end
end

-- Pet gösterim ölçeğini hesaba katarak tabanı `floorY`'ye oturt
local function place(pet: Pet, x: number, floorY: number, z: number, face: Vector3, spin: number)
	local pos = Vector3.new(x, floorY + pet.lift * pet.scale, z)
	local look = CFrame.lookAt(pos, Vector3.new(face.X, pos.Y, face.Z))
	pet.model:PivotTo(look * CFrame.Angles(0, spin, 0))
end

local function whiten(look: Look)
	if look.white then
		return
	end
	look.white = true
	look.part.Color = WHITE
	look.part.Material = Enum.Material.Neon
	look.part.Reflectance = 0
end

local function restore(look: Look)
	if not look.white then
		return
	end
	look.white = false
	look.part.Color = look.color
	look.part.Material = look.material
	look.part.Reflectance = look.reflectance
end

--[[
	Halka: 36 parçalı neon çember + içinde çok soluk bir tarama diski.
	Silindir tek başına dolu disk olurdu ve petleri örterdi.
]]
type Ring = { parts: { { part: BasePart, offset: CFrame } }, light: PointLight }

local function makeRing(parent: Instance): Ring
	local list = {}
	local segments = 36
	local len = 2 * math.pi * RING_R / segments + 0.12
	for i = 1, segments do
		local a = (i / segments) * math.pi * 2
		local p = Instance.new("Part")
		p.Name = "FuseRing"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = GREEN
		p.Size = Vector3.new(0.34, 0.34, len)
		p.Parent = parent
		table.insert(list, { part = p, offset = CFrame.new(math.cos(a) * RING_R, 0, math.sin(a) * RING_R) * CFrame.Angles(0, -a, 0) })
	end
	local disc = Instance.new("Part")
	disc.Name = "FuseScan"
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored = true
	disc.CanCollide = false
	disc.CanQuery = false
	disc.CanTouch = false
	disc.CastShadow = false
	disc.Material = Enum.Material.Neon
	disc.Color = GREEN
	disc.Transparency = 0.82
	disc.Size = Vector3.new(0.06, RING_R * 2, RING_R * 2)
	disc.Parent = parent
	table.insert(list, { part = disc, offset = CFrame.Angles(0, 0, math.rad(90)) })

	local light = Instance.new("PointLight")
	light.Color = GREEN
	light.Range = 14
	light.Brightness = 2
	light.Parent = disc
	return { parts = list, light = light }
end

local function moveRing(ring: Ring, center: Vector3, y: number, spin: number)
	local base = CFrame.new(center.X, y, center.Z) * CFrame.Angles(0, spin, 0)
	for _, item in ring.parts do
		item.part.CFrame = base * item.offset
	end
end

local function sizeTone(key: string): Color3
	local def = Config.ParsePetKey(key)
	if not def then
		return WHITE
	end
	if def.rarity == "Secret" then
		return Color3.fromRGB(190, 150, 255)
	end
	return Config.Rarities[def.rarity].color
end

function FuseFX.Create(hooks: Hooks?): Handle
	local player = Players.LocalPlayer
	local queue: { { key: string, from: string } } = {}
	local playing = false

	local function play(newKey: string, fromKey: string)
		local core, panel = findMachine()
		if not core then
			return
		end

		local folder = Instance.new("Folder")
		folder.Name = "FuseFX"
		folder.Parent = workspace

		local camera = workspace.CurrentCamera
		local oldType = camera.CameraType

		-- Makinenin kendi halkası animasyon boyunca gizli; ikisi üst üste binmesin
		local decorRing = core.Parent and core.Parent:FindFirstChild("ScanRing")
		if decorRing and decorRing:IsA("BasePart") then
			decorRing.LocalTransparencyModifier = 1
		end

		local ok, err = pcall(function()
			local center = core.Position
			-- FuseCore dik silindir: yüksekliği X ekseninde; platform üstü biraz yukarıda
			local floorY = center.Y + core.Size.X / 2 + 0.12 + HOVER

			-- Kamera: panelden makineye doğru bakan yönün karşısında, hafif yukarıda
			local away = if panel then (center - panel.Position) * Vector3.new(1, 0, 1) else Vector3.zero
			if away.Magnitude < 0.1 then
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				away = if root and root:IsA("BasePart") then (root.Position - center) * Vector3.new(1, 0, 1) else Vector3.new(-1, 0, 0)
			end
			away = away.Unit
			local shot = CFrame.lookAt(center + away * 17 + Vector3.new(0, 7.5, 0), center + Vector3.new(0, 3.6, 0))
			local face = center + away * 40

			camera.CameraType = Enum.CameraType.Scriptable
			local from = camera.CFrame
			if hooks and hooks.onStart then
				hooks.onStart()
			end

			-- ── 1. Üç kopya ─────────────────────────────────────────────────
			local sources: { Pet } = {}
			local factor = 1
			for i = 1, Config.PetFuseCount do
				local pet, natural = makePet(fromKey, folder)
				if pet then
					if i == 1 then
						factor = math.min(1, SRC_MAX / math.max(natural, 0.1))
					end
					fitPet(pet, factor)
					setScale(pet, 0.05)
					table.insert(sources, pet)
				end
			end

			local spin = 0
			local function orbit(radius: number, scale: number?)
				for i, pet in sources do
					local a = spin + (i - 1) * (math.pi * 2 / #sources)
					if scale then
						setScale(pet, scale)
					end
					local bob = math.sin(os.clock() * 3 + i) * 0.15
					place(pet, center.X + math.cos(a) * radius, floorY + bob, center.Z + math.sin(a) * radius, face, 0)
				end
			end

			run(0.6, function(a)
				camera.CFrame = from:Lerp(shot, easeInOut(a))
				spin += 0.01
				orbit(ORBIT_R, 0.05 + 0.95 * easeOutBack(a))
			end)

			-- ── 2. Halka iniyor, geçtiği yer beyaza dönüyor ─────────────────
			local ring = makeRing(folder)
			local topY = floorY + RING_TOP
			local bottomY = floorY - HOVER + 0.1
			run(1.3, function(a)
				local y = topY + (bottomY - topY) * easeInOut(a)
				spin += 0.012
				moveRing(ring, center, y, spin * 2)
				orbit(ORBIT_R)
				for _, pet in sources do
					for _, look in pet.looks do
						if look.part.Position.Y >= y then
							whiten(look)
						end
					end
				end
			end)
			for _, pet in sources do
				for _, look in pet.looks do
					whiten(look)
				end
			end

			-- ── 3. Birleşme: dönerek ortaya, parlama, yeni pet büyüyor ──────
			local speed = 0.012
			run(0.9, function(a)
				speed += 0.004
				spin += speed
				local e = a * a
				orbit(ORBIT_R * (1 - e), 1 - 0.45 * e)
				moveRing(ring, center, bottomY, spin * 2)
			end)
			for _, pet in sources do
				pet.model:Destroy()
			end

			local result, natural = makePet(newKey, folder)
			if result then
				-- Kaynaklarla aynı çarpan: bir boy büyüdüğü gerçekten görünsün; halkayı taşmasın
				fitPet(result, math.min(factor, RES_MAX / math.max(natural, 0.1)))
				for _, look in result.looks do
					whiten(look)
				end
				setScale(result, 0.1)
			end

			local flash = Instance.new("Part")
			flash.Name = "FuseFlash"
			flash.Shape = Enum.PartType.Ball
			flash.Anchored = true
			flash.CanCollide = false
			flash.CanQuery = false
			flash.CanTouch = false
			flash.CastShadow = false
			flash.Material = Enum.Material.Neon
			flash.Color = WHITE
			flash.Parent = folder
			local burst = Instance.new("PointLight")
			burst.Color = WHITE
			burst.Range = 22
			burst.Parent = flash

			local turn = 0
			run(0.55, function(a)
				local d = 1 + a * 8
				flash.Size = Vector3.new(d, d, d)
				flash.CFrame = CFrame.new(center.X, floorY + 2, center.Z)
				flash.Transparency = a
				burst.Brightness = 6 * (1 - a)
				if result then
					setScale(result, 0.1 + 0.9 * easeOutBack(a))
					turn += 0.05
					place(result, center.X, floorY, center.Z, face, turn)
				end
				moveRing(ring, center, bottomY, spin * 2)
			end)
			flash:Destroy()

			-- ── 4. Halka çıkıyor, beyaz parlama geçtiği yerden kalkıyor ─────
			run(1.2, function(a)
				local y = bottomY + (topY - bottomY) * easeInOut(a)
				spin += 0.012
				moveRing(ring, center, y, spin * 2)
				if result then
					turn += 0.02
					place(result, center.X, floorY + math.sin(os.clock() * 3) * 0.12, center.Z, face, turn)
					for _, look in result.looks do
						if look.part.Position.Y <= y then
							restore(look)
						end
					end
				end
				ring.light.Brightness = 2 * (1 - a * 0.6)
			end)
			for _, item in ring.parts do
				item.part:Destroy()
			end
			if not result then
				return
			end
			for _, look in result.looks do
				restore(look)
			end

			-- Adı ve boyu: kısa bir an, kademe renginde
			local tag = Instance.new("BillboardGui")
			tag.Size = UDim2.fromOffset(320, 60)
			tag.StudsOffsetWorldSpace = Vector3.new(0, 1.2, 0)
			tag.AlwaysOnTop = true
			tag.Adornee = result.body
			tag.Parent = folder
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.TextColor3 = sizeTone(newKey)
			label.TextStrokeTransparency = 0
			label.Text = Config.PetDisplayName(newKey)
			label.Parent = tag
			-- Etiket gövdenin üstünde dursun: gövde merkezinden modelin tepesine
			local cf, extents = result.model:GetBoundingBox()
			tag.StudsOffsetWorldSpace = Vector3.new(0, (cf.Position.Y + extents.Y / 2) - result.body.Position.Y + 1.2, 0)

			run(1.1, function()
				turn += 0.03
				place(result, center.X, floorY + math.sin(os.clock() * 3) * 0.12, center.Z, face, turn)
			end)

			-- ── 5. Envantere: oyuncuya uçup küçülüyor ──────────────────────
			tag:Destroy()
			local startPos = result.body.Position
			run(0.7, function(a)
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				local target = if root and root:IsA("BasePart") then root.Position else startPos + Vector3.new(0, 6, 0)
				local e = a * a
				-- Hafif yay çizerek
				local p = startPos:Lerp(target, e) + Vector3.new(0, math.sin(a * math.pi) * 3, 0)
				setScale(result, 1 - 0.95 * e)
				turn += 0.08
				result.model:PivotTo(CFrame.new(p) * CFrame.Angles(0, turn, 0))
				camera.CFrame = shot:Lerp(from, easeInOut(a))
			end)
		end)
		if not ok then
			warn("[FuseFX] " .. tostring(err))
		end

		folder:Destroy()
		if decorRing and decorRing:IsA("BasePart") then
			decorRing.LocalTransparencyModifier = 0
		end
		camera.CameraType = if oldType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else oldType
		if hooks and hooks.onEnd then
			hooks.onEnd()
		end
	end

	local function drain()
		if playing then
			return
		end
		playing = true
		while #queue > 0 do
			local item = table.remove(queue, 1)
			play(item.key, item.from)
		end
		playing = false
	end

	local connection = Net.Get("PetHatched").OnClientEvent:Connect(function(keys, source, fromKey)
		if source ~= "fuse" or typeof(fromKey) ~= "string" or typeof(keys) ~= "table" then
			return
		end
		local newKey = keys[1]
		if typeof(newKey) ~= "string" or not FuseFX.Available() then
			return
		end
		table.insert(queue, { key = newKey, from = fromKey })
		task.spawn(drain)
	end)

	return {
		IsPlaying = function(): boolean
			return playing
		end,
		Destroy = function()
			connection:Disconnect()
		end,
	}
end

return FuseFX
